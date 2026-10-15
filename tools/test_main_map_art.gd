extends SceneTree
## Real-scene contracts: art remains bounded, visible only in the courtyard,
## and leaves actor, camera, collision and navigation resources intact.
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("MAIN MAP ART: " + message)

func frames(count: int) -> void:
	for frame in count:
		await process_frame

func _run() -> void:
	for preparation in [0, 2]:
		var departing := load("res://scenes/main.tscn").instantiate() as Node3D
		root.add_child(departing)
		await frames(preparation)
		root.remove_child(departing)
		await frames(6)
		check(not bool(departing.get_node("ArenaPresentation/MainMapArt").get("_initialized")), "detached scenery completed deferred construction")
		departing.free()
	# A compact arena may temporarily remove the classic presentation branch.
	# Its canceled preparation must restart once that branch is attached again.
	var returning := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(returning)
	current_scene = returning
	_freeze(returning)
	await frames(3)
	var returning_art := returning.get_node("ArenaPresentation/MainMapArt")
	var returning_branch := returning.get_node("ArenaPresentation")
	returning.remove_child(returning_branch)
	await frames(3)
	check(not bool(returning_art.get("_initialized")), "removed branch completed its canceled preparation")
	returning.add_child(returning_branch)
	await frames(8)
	check(bool(returning_art.get("_initialized")) and returning_art.get_meta("art_counts").facades == 18, "reattached branch did not rebuild all workshop decoration")
	root.get_node("GameSfx").call("clear")
	returning.queue_free()
	current_scene = null
	await frames(3)
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	_freeze(scene)
	scene.call("reset_round_camera")
	var before := _signature(scene)
	var health: int = scene.get_node("Player").call("get_health")
	await frames(9)
	var art := scene.get_node("ArenaPresentation/MainMapArt")
	check(bool(art.get("_initialized")), "courtyard art did not initialize")
	check(before == _signature(scene), "art changed actors, camera, colliders or navigation")
	check(scene.get_node("Player").call("get_health") == health, "art changed health")
	var counts: Dictionary = art.get_meta("art_counts", {})
	check(counts.get("facades", 0) == 18 and counts.get("work_corners", 0) == 18, "workshop compositions are incomplete")
	check(counts.get("markings", 0) == 18 and counts.get("plants", 0) > 120, "aprons or low vegetation are missing")
	check(counts.get("landmarks", 0) == 2 and counts.get("exterior_buildings", 0) == 4, "exterior silhouettes are incomplete")
	check(counts.get("themes", []).size() == 3 and counts.themes.all(func(value: int) -> bool: return value > 0), "a workshop colour district is missing")
	check(int(art.get_meta("triangles", 100000)) < 45000, "art exceeds geometry budget")
	check(int(art.get_meta("batches", 100000)) <= 110, "art exceeds batch budget")
	var buffers: Array = []
	var lower_vegetation := true
	var exterior_outside := true
	var solid_budget := true
	for node in art.get_children():
		check(node is MeshInstance3D, "art adds a nonvisual node")
		var mesh := node as MeshInstance3D
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var kind: String = mesh.get_meta("art_kind")
		for point in vertices:
			if kind == "leaf":
				lower_vegetation = lower_vegetation and point.y <= 0.13
			if kind == "exterior":
				exterior_outside = exterior_outside and maxf(absf(point.x), absf(point.z)) > 30.5
			if kind in ["solid", "fine"]:
				solid_budget = solid_budget and point.y < 1.7
		buffers.append([mesh.mesh.get_instance_id(), mesh.material_override.get_instance_id()])
	check(lower_vegetation, "decorative plants could imply tall-grass concealment")
	check(exterior_outside, "large exterior geometry enters the playable perimeter")
	check(solid_budget, "workbench or facade detail exceeds existing cover heights")
	var organic := scene.get_node("OrganicWorldDetails")
	organic.call("_scan")
	var independent_plants := true
	for prop in organic.get("_props"):
		independent_plants = independent_plants and not art.is_ancestor_of(prop.mesh.get_ref())
	check(independent_plants, "tiny decorative plants were registered as concealment grass")
	for node in art.find_children("*", "Node", true, false):
		check(not node is CollisionObject3D and not node is CollisionShape3D and not node is Light3D and not node is NavigationRegion3D, "art adds gameplay geometry or light")
	var director := scene.get_node("ArenaPresentation")
	for quality in [0, 1]:
		director.call("set_quality", quality)
		await frames(2)
		check(int(art.get_meta("active_quality", -1)) == quality, "quality ignored")
		var index := 0
		var quality_matches := true
		for mesh in art.get_children():
			quality_matches = quality_matches and (quality > 0 or not mesh.visible or not bool(mesh.get_meta("fine_detail")))
			if quality == 0:
				quality_matches = quality_matches and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			check(buffers[index] == [mesh.mesh.get_instance_id(), mesh.material_override.get_instance_id()], "quality rebuilt static buffers")
			index += 1
		check(quality_matches, "quality did not reduce fine geometry or shadows")
	var leaf: ShaderMaterial = art.get("_leaf_materials")[0]
	paused = true
	var paused_clock := float(art.get("_clock"))
	var paused_wind := float(leaf.get_shader_parameter("scenery_clock"))
	await frames(3)
	check(float(art.get("_clock")) == paused_clock and float(leaf.get_shader_parameter("scenery_clock")) == paused_wind, "pause advanced vegetation animation")
	paused = false
	await process_frame
	check(float(art.get("_clock")) > paused_clock, "resume did not animate scenery")
	var warm_sun := (scene.get_node("ArenaKeyLight") as DirectionalLight3D).light_color
	scene.call("set_arena_variant", "test")
	var hidden_clock := float(art.get("_clock"))
	await frames(3)
	check(not art.is_visible_in_tree() and float(art.get("_clock")) == hidden_clock, "courtyard art leaks into test arena")
	scene.call("set_arena_variant", "classic")
	await frames(2)
	check(art.is_visible_in_tree(), "returning to classic lost artwork")
	check((scene.get_node("ArenaKeyLight") as DirectionalLight3D).light_color == warm_sun, "arena roundtrip lost courtyard lighting")
	check(before == _signature(scene), "arena roundtrip changed gameplay resources")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	current_scene = null
	await frames(8)
	check(_checks >= 50, "test aborted before all contracts")
	print("MAIN MAP ART: ", "PASS" if _failures.is_empty() else "FAIL", " (", _checks, " checks, ", _failures.size(), " failures)")
	quit(0 if _failures.is_empty() else 1)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _signature(scene: Node) -> String:
	var values: Array = []
	for node in scene.find_children("*", "Node3D", true, false):
		var path := String(scene.get_path_to(node))
		if path.begins_with("TestArena/"):
			continue
		if node is CollisionObject3D:
			values.append([path, node.transform, node.collision_layer, node.collision_mask])
		elif node is CollisionShape3D:
			values.append([path, node.transform, node.shape.get_instance_id(), node.disabled])
		elif node is Camera3D:
			values.append([path, node.transform, node.fov, node.projection, node.size])
		elif node is NavigationRegion3D:
			values.append([path, node.transform, node.navigation_mesh.get_instance_id()])
	return var_to_str(values)
