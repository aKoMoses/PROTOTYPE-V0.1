extends SceneTree
const BATCHER := preload("res://scripts/static_scene_batcher.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)
	node.position = at
	return node

func _helper(world: Node3D, garage: bool = false) -> Node:
	var helper := BATCHER.new()
	helper.world = world
	helper.garage = garage
	world.add_child(helper)
	helper.build()
	return helper

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var scenery := Node3D.new()
	scenery.name = "ArenaPresentation"
	world.add_child(scenery)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	var second_material := StandardMaterial3D.new()
	second_material.albedo_color = Color.BLUE
	var box := BoxMesh.new()
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
	geometry.surface_set_material(0, material)
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
	geometry.surface_set_material(1, second_material)
	var a := _mesh(scenery, geometry, Vector3(1, 2, 1))
	var b := _mesh(scenery, geometry, Vector3(3, 2, 1))
	b.rotation.y = 0.4
	b.scale = Vector3(1.5, 2, 0.7)
	var collision := StaticBody3D.new()
	a.add_child(collision)
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	collision.add_child(collider)
	var original_collision_id := collider.get_instance_id()
	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var glass := _mesh(scenery, box, Vector3(1, 2, 2))
	glass.material_override = transparent
	var mirrored := _mesh(scenery, box, Vector3(1, 2, 2))
	mirrored.material_override = material
	mirrored.scale.x = -1
	var actor := Node3D.new()
	actor.name = "HeroRobot"
	world.add_child(actor)
	var robot_mesh := _mesh(actor, geometry, Vector3.ZERO)
	var helper := _helper(world)
	if helper.stats.batches == 0:
		_check(false, "No batch created")
		quit(1)
		return
	_check(a.layers == 0 and b.layers == 0, "Rigid sources should use the batch")
	_check(glass.layers == 1 and mirrored.layers == 1 and robot_mesh.layers == 1, "Transparent, mirrored and actor meshes must remain independent")
	_check(helper.stats.saved_surfaces == 2, "Four surfaces should become two")
	_check(collider.get_instance_id() == original_collision_id and collider.shape is BoxShape3D, "Collision must remain intact")
	var batch: MeshInstance3D = scenery.get_node("StaticRenderBatch")
	_check(batch.mesh.get_surface_count() == 2, "Distinct materials must remain distinct")
	var original: Array = box.surface_get_arrays(0)
	for surface in 2:
		var actual: Array = batch.mesh.surface_get_arrays(surface)
		var vertex_count: int = original[Mesh.ARRAY_VERTEX].size()
		_check(actual[Mesh.ARRAY_VERTEX].size() == vertex_count * 2, "No vertex can be dropped")
		_check(actual[Mesh.ARRAY_INDEX].size() == original[Mesh.ARRAY_INDEX].size() * 2, "Triangle topology must be preserved")
		var sources: Array[MeshInstance3D] = [a, b]
		for source_index in 2:
			var source: MeshInstance3D = sources[source_index]
			var pose := scenery.global_transform.affine_inverse() * source.global_transform
			for vertex in vertex_count:
				var offset := source_index * vertex_count + vertex
				_check(actual[Mesh.ARRAY_VERTEX][offset].distance_to(pose * original[Mesh.ARRAY_VERTEX][vertex]) < 0.001, "World geometry must stay identical")
				_check(actual[Mesh.ARRAY_NORMAL][offset].distance_to((pose.basis.inverse().transposed() * original[Mesh.ARRAY_NORMAL][vertex]).normalized()) < 0.01, "Normals must support non-uniform scaling")
				_check(actual[Mesh.ARRAY_TEX_UV][offset].distance_to(original[Mesh.ARRAY_TEX_UV][vertex]) < 0.001, "Texture coordinates must stay identical")
		_check(batch.mesh.surface_get_material(surface) == (material if surface == 0 else second_material), "Original material resources must be reused")
	a.hide()
	_check(a.layers == 1 and b.layers == 1 and not batch.visible, "Visibility changes must restore originals immediately")
	await process_frame
	a.show()
	helper.build()
	b.position.x += 0.1
	helper.call("_process", 0.0)
	_check(a.layers == 1 and b.layers == 1, "Transform changes must restore original geometry")
	helper.build()
	b.set_surface_override_material(1, material)
	helper.call("_process", 0.0)
	_check(a.layers == 1 and b.layers == 1, "Material replacement must restore original rendering")
	helper.build()
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	helper.call("_process", 0.0)
	_check(a.layers == 1 and b.layers == 1, "Render property changes must restore originals")
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	helper.build()
	world.remove_child(scenery)
	_check(a.layers == 1 and b.layers == 1, "Detaching a map must restore original meshes immediately")
	world.add_child(scenery)
	helper.free()
	world.queue_free()
	await process_frame
	await _payload_test()
	await _real_scene_test()
	if failures.is_empty():
		print("STATIC_SCENE_BATCHER_OK geometry normals UV materials collision visibility transforms payload garage arena")
	quit(0 if failures.is_empty() else 1)

func _payload_test() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var stations := Node3D.new()
	stations.name = "ModuleStorageStations"
	world.add_child(stations)
	var item := Node3D.new()
	item.name = "Cartridge_test"
	stations.add_child(item)
	var material := StandardMaterial3D.new()
	var box := BoxMesh.new()
	box.material = material
	var a := _mesh(item, box, Vector3(0.1, 0.1, 0.1))
	var b := _mesh(item, box, Vector3(0.3, 0.1, 0.1))
	var helper := _helper(world, true)
	_check(a.layers == 0 and b.layers == 0, "Cartridge contents should batch inside their own item")
	var payload := item.duplicate(0) as Node3D
	world.add_child(payload)
	_check(payload.has_node("StaticRenderBatch"), "Transport payload must include its batched geometry")
	var batch: MeshInstance3D = payload.get_node("StaticRenderBatch")
	_check(batch.layers == 1 and batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 72, "Payload must preserve both complete boxes")
	item.hide()
	_check(batch.visible and batch.layers == 1, "Hiding catalog item cannot hide the already cloned payload")
	helper.free()
	_check(a.layers == 1 and b.layers == 1, "Freeing helper must preserve original nodes")
	world.queue_free()
	await process_frame

func _real_scene_test() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 12:
		await process_frame
	await create_timer(0.3).timeout
	var helper := scene.get_node_or_null("StaticSceneBatcher")
	if helper == null:
		helper = _helper(scene)
	else:
		helper.build()
	_check(helper.stats.saved_surfaces > 0, "Actual arena should reduce static surface submissions")
	var flow := scene.get_node("Interface")
	flow.call("_open_equipment")
	for frame in 12:
		await process_frame
	var garage: Node = flow.get("_forge_garage")
	var stage: Node = garage.get("stage")
	var world: Node3D = stage.get("world")
	var garage_helper := world.get_node_or_null("StaticSceneBatcher")
	if garage_helper == null:
		garage_helper = _helper(world, true)
	else:
		garage_helper.build()
	_check(garage_helper.stats.saved_surfaces > 100, "Actual garage should reduce rack and cartridge submissions")
	for branch_name in ["HeroRobot", "ServiceMechanism"]:
		var branch := world.get_node_or_null(branch_name)
		if branch != null:
			for mesh: MeshInstance3D in branch.find_children("*", "MeshInstance3D", true, false):
				_check(mesh.layers != 0, "Animated garage actors must retain original rendering")
	print("STATIC_BATCH_REAL arena=", helper.stats, " garage=", garage_helper.stats)
	current_scene = null
	scene.queue_free()
	await process_frame
