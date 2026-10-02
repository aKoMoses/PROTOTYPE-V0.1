extends SceneTree
## Integration guard for local lighting and arena/quality transitions.
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var presentation := scene.get_node("ArenaPresentation")
	var workshops := presentation.get_node("WorkshopDressing")
	var actual_triangles := 0
	for mesh in workshops.find_children("Workshop_*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			actual_triangles += (indices.size() if not indices.is_empty() else vertices.size())/3
			_check(mesh.mesh.get_aabb().size.is_finite(),"baked decoration has invalid bounds")
	_check(actual_triangles==int(workshops.get_meta("baked_triangles",0)),"baked scene references stale or incomplete geometry")
	var camera := scene.get_node("CameraRig") as Node3D
	camera.set_process(false)
	camera.global_position = Vector3.ZERO
	# A visual resource must not create hidden obstacles or vision volumes.
	var nodes: Array[Node] = [workshops]
	while not nodes.is_empty():
		var node := nodes.pop_back() as Node
		_check(not node is CollisionObject3D and not node is CollisionShape3D and not node is NavigationRegion3D and not node is NavigationObstacle3D,"workshop decoration adds a physics/navigation object")
		_check(not node.is_in_group("bush_placeholder") and not node.is_in_group("repair_kits"),"decoration must not alter concealment or healing groups")
		for child in node.get_children():
			nodes.append(child)
	presentation.call("set_quality",1)
	workshops.call("_process",.36)
	_check(_active_lights(workshops)>0 and _active_lights(workshops)<=6,"normal quality must activate a bounded set of nearby lights")
	for light in workshops.find_children("*","OmniLight3D",true,false):
		_check(not light.shadow_enabled,"local workshop lights must not add shadow maps")
	presentation.call("set_quality",0)
	_check(_active_lights(workshops)==0,"low quality must disable the local lights")
	# Choosing a different arena must remove all courtyard lighting as well as meshes.
	presentation.call("set_quality",1)
	scene.call("set_arena_variant","test")
	workshops.call("_process",.36)
	_check(not workshops.is_visible_in_tree() and _active_lights(workshops)==0,"test arena must hide the workshop decor and all its lights")
	scene.call("set_arena_variant","classic")
	workshops.call("_process",.36)
	_check(workshops.is_visible_in_tree() and _active_lights(workshops)>0,"returning to classic must restore workshop lighting")
	# Lamp selection follows the production camera rather than a fixed arena corner.
	camera.global_position = Vector3(-22,0,-20)
	workshops.call("_process",.36)
	for light in workshops.find_children("*","OmniLight3D",true,false):
		if light.visible:
			_check(light.global_position.distance_squared_to(camera.global_position)<230.0,"active light remained behind when the camera moved")
	_check(_active_lights(workshops)<=6,"moving camera must preserve the local-light budget")
	print("WORKSHOP PRESENTATION: ","PASS" if _failures.is_empty() else "FAIL"," (visual-only resources; quality and arena transitions; camera-following light budget)")
	for failure in _failures:
		push_error(failure)
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)

func _active_lights(workshops: Node) -> int:
	var count := 0
	for light in workshops.find_children("*","OmniLight3D",true,false):
		if light.visible:
			count += 1
	return count

func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
