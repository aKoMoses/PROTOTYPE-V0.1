extends SceneTree
## Integration guard: compare real actor/physics/camera resources before and
## after the deferred finish, including scene/quality transitions and re-entry.
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("REFERENCE RENDER: " + message)

func _run() -> void:
	# Scene switches can detach a branch before its deferred decoration starts
	# or between its two preparation frames. Neither director may resume it.
	for preparation_frames in [0, 1]:
		var departing := load("res://scenes/main.tscn").instantiate() as Node3D
		root.add_child(departing)
		for frame in preparation_frames:
			await process_frame
		root.remove_child(departing)
		await process_frame
		await process_frame
		var deferred_finish := departing.get_node("ArenaPresentation/ReferenceRenderFinish")
		_check(not bool(deferred_finish.get("_initialized")), "detached scene completed a deferred material pass")
		departing.free()
	for cycle in range(2):
		var scene := load("res://scenes/main.tscn").instantiate() as Node3D
		root.add_child(scene)
		current_scene = scene
		await process_frame
		_freeze(scene)
		# Freeze the camera at its resting pose, rather than partway through the
		# user's combat-zoom interpolation. Arena switches restore this pose.
		scene.call("reset_round_camera")
		var before := _signature(scene)
		for frame in range(5):
			await process_frame
		var presentation := scene.get_node("ArenaPresentation")
		var finish := presentation.get_node("ReferenceRenderFinish")
		_check(before == _signature(scene), "finish changed an actor, camera, collider, bush or repair resource")
		_check(int(finish.get_meta("finished_materials", 0)) > 10, "deferred finish did not replace authored scenery materials")
		var ground := scene.get_node("Ground") as MeshInstance3D
		_check(ground.material_override is ShaderMaterial and ground.material_override.shader.resource_path.ends_with("reference_finish/ground.gdshader"), "concrete finish not applied")
		var contacts := finish.get_node("CoverContactOcclusion") as MultiMeshInstance3D
		_check(contacts.multimesh.instance_count == 44, "contacts do not match the visible authored covers")
		_check(contacts.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "contact shading adds real shadow casters")
		var details := finish.get_node("ReferenceEdgeDetails") as Node3D
		_check(int(details.get_meta("triangles")) < 75000 and int(details.get_meta("batches")) <= 48, "decorative detail exceeded its bounded geometry budget")
		_check(int(details.get_meta("plants")) > 100 and int(details.get_meta("stones")) > 900, "reference border detail was not installed")
		var leaves_outside := true
		for mesh in details.get_children():
			var material := mesh.material_override as ShaderMaterial
			if material.get_shader_parameter("leaf") == true:
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					leaves_outside = leaves_outside and maxf(absf(vertex.x),absf(vertex.z)) > 29.8
		_check(leaves_outside, "decorative tall leaves entered a playable or concealment region")
		for node in finish.find_children("*", "Node", true, false):
			_check(not node is CollisionObject3D and not node is CollisionShape3D and not node is NavigationRegion3D and not node is Light3D, "finish added gameplay geometry or lights")
		for quality in [0, 1]:
			presentation.call("set_quality", quality)
			finish.call("_update_quality")
			_check(int(finish.get_meta("active_quality")) == quality, "finish ignored quality change")
			var shadow_setting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var quality_matches := true
			for mesh in details.get_children():
				quality_matches = quality_matches and mesh.cast_shadow == shadow_setting
			_check(quality_matches, "decorative shadow cost does not follow quality")
			if DisplayServer.get_name() != "headless":
				_check(root.msaa_3d == (Viewport.MSAA_4X if quality > 0 else Viewport.MSAA_DISABLED), "antialiasing does not follow quality")
		scene.call("set_arena_variant", "test")
		_check(not contacts.is_visible_in_tree(), "contact shading leaked into the test arena")
		_check(not details.is_visible_in_tree(), "decorative border leaked into the test arena")
		scene.call("set_arena_variant", "classic")
		_check(contacts.is_visible_in_tree(), "returning to classic lost contact shading")
		_check(details.is_visible_in_tree(), "returning to classic lost its reference border")
		_check(_signature(scene) == before, "arena roundtrip changed the classic resource contract")
		root.get_node("GameSfx").call("clear")
		var original_msaa := int(finish.get("_original_msaa"))
		scene.queue_free()
		current_scene = null
		await process_frame
		if DisplayServer.get_name() != "headless":
			_check(root.msaa_3d == original_msaa, "closing courtyard leaked its antialiasing into another scene")
	print("REFERENCE RENDER: ", "PASS" if _failures.is_empty() else "FAIL", " checks=", _checks)
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
		elif node is MeshInstance3D and (path.begins_with("Player/") or path.begins_with("TargetDummy/") or path.begins_with("HealthPad") or path.begins_with("Bush")):
			var materials: Array = []
			if node.mesh != null:
				for surface in node.mesh.get_surface_count():
					var material: Material = node.get_active_material(surface)
					materials.append(material.get_instance_id() if material != null else 0)
			values.append([path, node.transform, node.mesh.get_instance_id() if node.mesh != null else 0, node.material_override.get_instance_id() if node.material_override != null else 0, materials])
	return var_to_str(values)
