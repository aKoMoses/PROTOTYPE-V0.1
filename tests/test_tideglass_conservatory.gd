extends SceneTree
## The art pass must not change any physical shape or interrupt map switching.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _physics_contract(stage: Node) -> Array:
	var result := []
	for body in stage.find_children("*", "CollisionObject3D", true, false):
		var shapes := []
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes.append([child.shape.get_rid(), child.transform, child.disabled])
		result.append([body.get_instance_id(), body.transform, body.collision_layer, body.collision_mask, shapes])
	return result

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_select_arena", "tideglass")
	flow.call("_start_duel")
	var stage := scene.get_node("CompactArenaStage")
	var basin := stage.get_node("TideglassArena")
	var art := basin.get_node("TideglassConservatory")
	var before := _physics_contract(stage)
	for frame in 18:
		await process_frame
	_check(before == _physics_contract(stage), "art leaves collider identity, dimensions, transforms and layers unchanged")
	_check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "conservatory adds no physical objects")
	var snapshot: Dictionary = art.call("get_snapshot")
	_check(snapshot.initialized and snapshot.planters == 5 and snapshot.floating_gardens == 2, "all five existing covers use the new skin")
	_check(snapshot.planar_reflections, "water has a real view of the surrounding architecture")
	var mirror: Camera3D = art.get("_mirror_camera")
	var main_camera := root.get_camera_3d()
	art.call("_refresh_reflection")
	_check(is_equal_approx(mirror.global_position.y, 2.0 * float(basin.get("water_level")) - main_camera.global_position.y), "reflection view is mirrored about the actual tide level")
	for actor_name in ["Player", "TargetDummy"]:
		for mesh in scene.get_node(actor_name).find_children("*", "MeshInstance3D", true, false):
			_check((mesh.layers & mirror.cull_mask) == 0, "reflections cannot reveal a hidden opponent")
	for entry in basin.get("barges"):
		_check(entry.body.has_node("ConservatoryPlanter"), "floating garden belongs to the actual moving cover")
	basin.call("advance", 11.0)
	var leaf: ShaderMaterial = art.get("_leaf")
	var water: ShaderMaterial = basin.get("_water_material")
	_check(is_equal_approx(float(leaf.get_shader_parameter("clock")), float(water.get_shader_parameter("clock"))), "water and foliage share round time")
	var frozen: float = leaf.get_shader_parameter("clock")
	basin.call("stop")
	for frame in 5:
		await process_frame
	_check(is_equal_approx(float(leaf.get_shader_parameter("clock")), frozen), "paused round freezes decorative animation")
	# Exercise destruction while deferred presentation setup is still pending.
	for arena in ["classic", "tideglass", "clockwork", "tideglass", "classic"]:
		scene.call("set_arena_variant", arena)
		await process_frame
	for frame in 18:
		await process_frame
	_check(scene.get_node_or_null("CompactArenaStage") == null, "switching away removes the entire conservatory")
	_check(root.find_children("WaterReflectionView", "SubViewport", true, false).is_empty(), "switching away also releases the reflection viewport")
	print("TIDEGLASS CONSERVATORY TEST: ", "PASS" if failures.is_empty() else "FAIL", " ", snapshot)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
