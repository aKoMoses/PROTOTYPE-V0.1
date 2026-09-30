extends SceneTree

## Visual-pass guard: captures every gameplay blocker, shape, bush zone, kit,
## spawn and shipped camera property. Writes only to a caller-supplied path.
## Usage: --script res://tools/test_arena_art_contract.gd -- capture <baseline>
##        --script res://tools/test_arena_art_contract.gd -- verify <baseline> <current>

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["capture", "verify"]:
		push_error("Use capture|verify <baseline.json> [current.json]")
		quit(2)
		return
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	# _ready has synchronously built the complete production arena. Capture
	# before the menu camera or gameplay simulation can move any actor.
	var current := _collect_contract(scene)
	var code := 0
	var bounds_failures := _validate_visible_bounds()
	# The shipped canvas and stretch policy were inspected before the art pass.
	for entry in [["display/window/size/viewport_width", 1280], ["display/window/size/viewport_height", 720], ["display/window/stretch/mode", "canvas_items"]]:
		if ProjectSettings.get_setting(entry[0]) != entry[1]:
			bounds_failures.append("Gameplay viewport/stretch setting changed: %s" % entry[0])
	if not bounds_failures.is_empty():
		for failure in bounds_failures:
			push_error("ARENA ART BOUNDS: %s" % failure)
		code = 1
	if args[0] == "capture":
		code = maxi(code, _write_json(args[1], current))
		print("ARENA ART CONTRACT: CAPTURED %s blockers=%d bushes=%d kits=%d" % [args[1], current.solids.size(), current.bushes.size(), current.kits.size()])
	else:
		if args.size() > 2:
			code = maxi(code, _write_json(args[2], current))
		var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		if not baseline is Dictionary:
			push_error("Missing or invalid arena baseline: %s" % args[1])
			code = 1
		elif _canonical(baseline) != _canonical(current):
			push_error("ARENA ART CONTRACT: FAIL — gameplay geometry or camera changed")
			for key in current.keys():
				if _canonical(baseline.get(key)) != _canonical(current[key]):
					print("ARENA ART CONTRACT DIFF: %s" % key)
			code = 1
		else:
			print("ARENA ART CONTRACT: PASS (%d blockers, %d bushes, %d kits; complete shape/transform/camera signature)" % [current.solids.size(), current.bushes.size(), current.kits.size()])
	await _cleanup(scene)
	quit(code)


func _validate_visible_bounds() -> Array[String]:
	var failures: Array[String] = []
	for node in get_nodes_in_group("arena_solid"):
		var body := node as StaticBody3D
		if body == null or bool(body.get_meta("invisible_safety_limit", false)):
			continue
		var visual := body.get_node_or_null("CollisionMatchedVisual") as MeshInstance3D
		var collision := body.get_node_or_null("Collision") as CollisionShape3D
		if visual == null or visual.mesh == null or collision == null or not collision.shape is BoxShape3D:
			failures.append("%s missing collision-matched shell or box" % body.name)
			continue
		var size := (collision.shape as BoxShape3D).size
		var visual_bounds: AABB = visual.global_transform * visual.mesh.get_aabb()
		var collision_bounds: AABB = collision.global_transform * AABB(-size * 0.5, size)
		if visual_bounds.position.distance_to(collision_bounds.position) > 0.035 or visual_bounds.size.distance_to(collision_bounds.size) > 0.035:
			failures.append("%s visible world bounds differ from collision" % body.name)
	return failures


func _collect_contract(scene: Node3D) -> Dictionary:
	var contract := {"schema": 1, "solids": [], "bushes": [], "kits": [], "spawns": {}, "camera": {}, "camera_rig": {}}
	for node in get_nodes_in_group("arena_solid"):
		if node is CollisionObject3D:
			contract.solids.append(_body_signature(node, scene))
	contract.solids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path < b.path)
	for node in get_nodes_in_group("bush_placeholder"):
		var metadata := {}
		for key in node.get_meta_list():
			if str(key).begins_with("bush_"):
				metadata[str(key)] = _value(node.get_meta(key))
		contract.bushes.append({"path": str(scene.get_path_to(node)), "transform": _value(node.transform), "global_transform": _value(node.global_transform), "metadata": metadata})
	contract.bushes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path < b.path)
	for node in get_nodes_in_group("repair_kits"):
		var entry := _body_signature(node, scene)
		for key in ["heal_fraction", "respawn_delay", "collection_radius", "point_enabled", "monitoring", "monitorable"]:
			entry[key] = _value(node.get(key))
		contract.kits.append(entry)
	contract.kits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path < b.path)
	for name in ["Player", "TargetDummy"]:
		var node := scene.get_node_or_null(name) as Node3D
		if node != null:
			contract.spawns[name] = {"transform": _value(node.transform), "global_transform": _value(node.global_transform)}
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	contract.camera = {"transform": _value(camera.transform)}
	for key in ["projection", "fov", "size", "near", "far", "keep_aspect", "h_offset", "v_offset", "frustum_offset", "cull_mask", "current", "doppler_tracking"]:
		contract.camera[key] = _value(camera.get(key))
	var rig := scene.get_node("CameraRig")
	for key in ["follow_speed", "aim_smoothing_speed", "look_ahead_distance"]:
		contract.camera_rig[key] = _value(rig.get(key))
	contract.camera_rig["script"] = rig.get_script().resource_path
	return contract


func _body_signature(body: CollisionObject3D, scene: Node3D) -> Dictionary:
	var entry := {"path": str(scene.get_path_to(body)), "type": body.get_class(), "transform": _value(body.transform), "global_transform": _value(body.global_transform), "collision_layer": body.collision_layer, "collision_mask": body.collision_mask, "shapes": []}
	for owner_id in body.get_shape_owners():
		var owner := body.shape_owner_get_owner(owner_id) as Node
		var shape_entry := {"owner_path": str(body.get_path_to(owner)) if owner != null else "", "transform": _value(body.shape_owner_get_transform(owner_id)), "disabled": body.is_shape_owner_disabled(owner_id), "shapes": []}
		for index in range(body.shape_owner_get_shape_count(owner_id)):
			var shape: Shape3D = body.shape_owner_get_shape(owner_id, index)
			var properties := {"type": shape.get_class()}
			for property in shape.get_property_list():
				var key := str(property.name)
				if int(property.usage) & PROPERTY_USAGE_STORAGE and key not in ["resource_name", "resource_local_to_scene", "script"]:
					properties[key] = _value(shape.get(key))
			shape_entry.shapes.append(properties)
		entry.shapes.append(shape_entry)
	entry.shapes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.owner_path < b.owner_path)
	return entry


func _value(value: Variant) -> Variant:
	if value is Vector3:
		return [_round(value.x), _round(value.y), _round(value.z)]
	if value is Vector2:
		return [_round(value.x), _round(value.y)]
	if value is Transform3D:
		return {"origin": _value(value.origin), "basis": [_value(value.basis.x), _value(value.basis.y), _value(value.basis.z)]}
	if value is PackedVector3Array or value is Array:
		var result := []
		for item in value:
			result.append(_value(item))
		return result
	if value is float:
		return _round(value)
	if value is int or value is bool or value is String or value == null:
		return value
	return str(value)


func _round(value: float) -> float:
	return snappedf(value, 0.00001)


func _canonical(value: Variant) -> String:
	# Parse both sides so JSON's float representation cannot make an unchanged
	# integer layer/mask or projection enum appear different from its saved value.
	var normalized: Variant = JSON.parse_string(JSON.stringify(value, "", true, true))
	return JSON.stringify(normalized, "", true, true)


func _write_json(path: String, value: Dictionary) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s: %s" % [path, FileAccess.get_open_error()])
		return 1
	file.store_string(JSON.stringify(value, "\t", true, true) + "\n")
	return 0


func _cleanup(scene: Node) -> void:
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	scene.queue_free()
	current_scene = null
	await process_frame
