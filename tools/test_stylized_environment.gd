extends SceneTree
## Visual-only contract: production physics/cameras and actor/VFX materials
## must survive a finish pass, including dynamically constructed platforms.
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("STYLIZED ENVIRONMENT: " + message)

func _run() -> void:
	var director := root.get_node("StylizedEnvironment")
	director.enabled = false
	for size in [Vector3(4, 2, 1), Vector3(0.5, 1.3, 2), Vector3(88, 2.2, 0.6)]:
		var mesh: ArrayMesh = director.beveled_box(size)
		_check(mesh.get_aabb().position.is_equal_approx(-size * 0.5) and mesh.get_aabb().size.is_equal_approx(size), "Bevel moved the block's outer bounds")
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_check(vertices.size() == 132, "Chamfered box should have 44 triangles")
		for index in range(0, vertices.size(), 3):
			var cross := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
			_check(cross.length() > 0.000001 and cross.dot(normals[index]) < 0, "Degenerate or inward-facing bevel triangle")
		_check(director.beveled_box(size) == mesh, "Equal-sized blocks should share geometry")
	var normal := StandardMaterial3D.new()
	normal.albedo_color = Color("#bc9a71")
	var finish: ShaderMaterial = director._paint(normal)
	_check(finish != null and director._paint(normal) == finish, "Opaque finishes should be shared")
	_check(normal.albedo_color == Color("#bc9a71") and normal is StandardMaterial3D, "Source material was modified")
	for role in ["glow", "alpha", "unshaded", "billboard"]:
		var special := normal.duplicate() as StandardMaterial3D
		match role:
			"glow": special.emission_enabled = true
			"alpha": special.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"unshaded": special.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			"billboard": special.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_check(director._paint(special) == null, "Protected " + role + " material was replaced")
	if not OS.get_cmdline_user_args().has("core"):
		for path in ["res://scenes/main.tscn", "res://scenes/training_ground.tscn", "res://scenes/survival.tscn"]:
			var packed := load(path) as PackedScene
			var scene := packed.instantiate() as Node3D
			root.add_child(scene)
			current_scene = scene
			# Finish the actors' deferred startup before the before/after snapshot.
			await process_frame
			# Snapshot before processing so actors, menus and camera are stationary.
			_freeze(scene)
			var before := _signature(scene)
			await director._prepare_scene(scene)
			_check(before == _signature(scene), "Physics, camera or actor/VFX visuals changed in " + path)
			# The reference finish and workshop equipment build scenery over two
			# deferred frames. Settle that bootstrap before comparing repeat passes.
			for frame in 4:
				await process_frame
			_freeze(scene)
			await director._prepare_scene(scene)
			_check(before == _signature(scene), "Deferred scenery changed a protected gameplay resource in " + path)
			var styled := _styled_count(scene)
			_check(styled > 0, "No environment finishes applied in " + path)
			await director._prepare_scene(scene)
			_check(styled == _styled_count(scene), "Finish pass is not idempotent")
			if path.ends_with("main.tscn"):
				director.enabled = true
				scene.call("set_arena_variant", "test")
				_freeze(scene)
				var test_before := _signature(scene)
				await process_frame
				await process_frame
				_check(test_before == _signature(scene), "Test arena gameplay changed")
				_check(_styled_count(scene.get_node("TestArena")) > 0, "Test arena did not inherit the art direction")
				director.enabled = false
			else:
				var vfx := scene.get_node("VFXManager")
				vfx.set("quality", 0)
				director._update_quality()
				for sun in scene.find_children("*", "DirectionalLight3D", false, false):
					_check(not sun.shadow_enabled, "Secondary arena did not disable shadows at low quality")
				vfx.set("quality", 1)
				director._update_quality()
				var suns := scene.find_children("*", "DirectionalLight3D", false, false)
				_check(suns.any(func(sun: DirectionalLight3D) -> bool: return sun.shadow_enabled), "Normal quality did not restore a key shadow")
			print("STYLIZED SCENE: ", path, " finished meshes=", _styled_count(scene))
			scene.queue_free()
			await process_frame
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null:
		sfx.call("clear")
	print("STYLIZED ENVIRONMENT: ", "PASS" if _failures.is_empty() else "FAIL", " checks=", _checks)
	quit(0 if _failures.is_empty() else 1)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _signature(scene: Node) -> String:
	var data: Array = []
	for node in scene.find_children("*", "Node3D", true, false):
		if node is CollisionObject3D:
			data.append([String(scene.get_path_to(node)), node.transform, node.collision_layer, node.collision_mask])
		elif node is CollisionShape3D:
			data.append([String(scene.get_path_to(node)), node.transform, node.shape.get_instance_id(), node.disabled])
		elif node is Camera3D:
			data.append([String(scene.get_path_to(node)), node.transform, node.fov, node.projection, node.size])
		elif node is MeshInstance3D:
			var path := String(scene.get_path_to(node))
			if path.begins_with("Player/") or path.begins_with("TargetDummy/") or path.begins_with("VFXManager/") or path.begins_with("Training_") or path.begins_with("WaveEnemy_"):
				var materials: Array = []
				if node.mesh != null:
					for surface in node.mesh.get_surface_count():
						var material: Material = node.get_active_material(surface)
						materials.append(material.get_instance_id() if material != null else 0)
				data.append([path, node.mesh.get_instance_id() if node.mesh != null else 0, node.material_override.get_instance_id() if node.material_override != null else 0, materials])
	return var_to_str(data)

func _styled_count(scene: Node) -> int:
	var count := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		if node.has_meta("stylized_finish"):
			count += 1
	return count
