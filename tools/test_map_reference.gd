extends SceneTree
## Verifies before/after gameplay signatures, complete bakes and late map changes.
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error("MAP REFERENCE: "+message)

func _run() -> void:
	var director := root.get_node("StylizedEnvironment")
	director.enabled = false
	for id in ["test","training","survival"]:
		var path := "res://scenes/%s.tscn" % ("main" if id=="test" else "training_ground" if id=="training" else "survival")
		var scene := load(path).instantiate() as Node3D
		root.add_child(scene)
		current_scene = scene
		await process_frame
		if id=="test":
			scene.call("set_arena_variant","test")
		_freeze(scene)
		var before := _signature(scene)
		if id=="test":
			await director._prepare_test_details(weakref(scene.get_node("TestArena")))
		await director._prepare_scene(scene)
		_check(before==_signature(scene),id+" physics, gameplay groups or camera changed")
		var parent := scene.get_node("TestArena") if id=="test" else scene
		var decor := parent.get_node("ReferenceMapDressing") as Node3D
		var count := 0
		for mesh in decor.find_children("Workshop_*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				count += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
		_check(count==int(decor.get_meta("baked_triangles")),id+" references incomplete baked geometry")
		var queue: Array[Node] = [decor]
		while not queue.is_empty():
			var node := queue.pop_back() as Node
			_check(not node is CollisionObject3D and not node is CollisionShape3D and not node is NavigationRegion3D and not node is NavigationObstacle3D,id+" adds gameplay geometry")
			_check(not node.is_in_group("bush_placeholder") and not node.is_in_group("repair_kits"),id+" decorative node changes gameplay groups")
			for child in node.get_children():
				queue.append(child)
		var vfx := scene.get_node("VFXManager")
		var actor_lamps: Array = []
		for light in scene.get_node("Player").find_children("*","Light3D",true,false):
			actor_lamps.append([light,light.visible,light.light_energy])
		vfx.set("quality",0)
		decor.call("_sync")
		for entry in actor_lamps:
			_check(entry[0].visible==entry[1] and entry[0].light_energy==entry[2],id+" scenery quality interferes with weapon light")
		_check(_lights(scene)==0,id+" low quality leaves local lamps active")
		vfx.set("quality",1)
		decor.call("_sync")
		decor.call("_process",.5)
		_check(_lights(scene)<=6,id+" exceeds the shared six-light budget")
		var floor := parent.get_node("Ground") if id=="test" else scene.get_node("TrainingFloor/Visual") if id=="training" else scene.get_node("Floor/Visual")
		_check(floor.material_override.get_shader_parameter("world_layout")==true,id+" floor is not aligned in world metres")
		await director._prepare_scene(scene)
		_check(parent.find_children("ReferenceMapDressing","Node3D",false,false).size()==1,id+" duplicates decoration on repeated preparation")
		if id=="test":
			scene.call("set_arena_variant","classic")
			_check(not decor.is_visible_in_tree(),"test decoration survives transition to classic")
			scene.call("set_arena_variant","test")
			_check(decor.is_visible_in_tree(),"test decoration fails to restore")
		elif id=="survival":
			var hatch_materials: Array[Material] = []
			for mesh in scene.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh is BoxMesh and mesh.mesh.size.is_equal_approx(Vector3(3.2,.04,2.1)):
					hatch_materials.append(mesh.material_override)
			_check(hatch_materials.size()==9,"survival service hatches lost their original footprints")
			for material in hatch_materials:
				_check(material==hatch_materials[0] and material is ShaderMaterial and material.shader==director.TREAD,"survival hatches should share the detailed steel finish")
			scene.call("_choose_weapon","blaster")
			scene.call("_open_passage")
			scene.call("_enter_factory")
			decor.call("_sync")
			_check(scene.get("arena_center")==Vector3(54,0,0),"factory transition altered")
			_check(is_equal_approx(scene.get_node("SurvivalSun").light_energy,.86),"factory transition loses approved lighting")
			_check(scene.get_node("FactoryFloor/Visual").material_override.get_shader_parameter("layout_origin")==Vector2(30,-24),"factory atlas uses the wrong world origin")
			_check(scene.get_node("PassageFloor/Visual").material_override.get_shader_parameter("layout_span")==Vector2(8,12),"passage atlas loses its own scale")
		print("MAP REFERENCE VERIFIED: ",id," triangles=",count)
		root.get_node("GameSfx").call("clear")
		scene.queue_free()
		await process_frame
	print("MAP REFERENCE: ","PASS" if _failures.is_empty() else "FAIL"," checks=",_checks," failures=",_failures.size())
	quit(0 if _failures.is_empty() else 1)

func _lights(scene: Node3D) -> int:
	var count := 0
	for light in scene.find_children("*","OmniLight3D",true,false):
		var branch: Node = light
		while branch.get_parent()!=scene:
			branch = branch.get_parent()
		if branch.get_script()!=null and not branch.name in ["TestArena","ArenaPresentation","ReferenceMapDressing"]:
			continue # Weapon/VFX lamps have their own lifetime and budget.
		if light.get_viewport()==scene.get_viewport() and light.is_visible_in_tree():
			count += 1
	return count

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _signature(scene: Node3D) -> String:
	var signature: Array = []
	for node in scene.find_children("*","Node3D",true,false):
		if node is CollisionObject3D:
			signature.append([str(scene.get_path_to(node)),node.transform,node.collision_layer,node.collision_mask,node.get_groups()])
		elif node is CollisionShape3D:
			signature.append([str(scene.get_path_to(node)),node.transform,node.shape.get_instance_id(),node.disabled])
		elif node is Camera3D:
			signature.append([str(scene.get_path_to(node)),node.transform,node.fov,node.projection])
	return var_to_str(signature)
