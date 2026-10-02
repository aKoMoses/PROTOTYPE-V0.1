extends "res://tools/environment/build_workshop_dressing.gd"
## Offline extension of the reference courtyard's exact prop authoring family.
## All added geometry is visual-only; fixed details follow existing solids.
var _map_id := ""
var _grass_count := 0

func _output_dir() -> String:
	return "res://art/environment/map_reference/%s/" % _map_id

func _make_materials() -> void:
	for material_name in NAMES:
		_materials.append(load(OUTPUT+material_name+".tres"))

func _build() -> void:
	root.get_node("StylizedEnvironment").set("enabled",false)
	_make_materials()
	for map_id in ["test","training","survival"]:
		_map_id = map_id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir()))
		_batches.clear()
		_lights.clear()
		_cloth_count = 0
		_cable_runs = 0
		_triangles = 0
		_grass_count = 0
		_dressing = Node3D.new()
		_dressing.name = "ReferenceMapDressing"
		_dressing.set_script(load("res://scripts/environment/map_reference_presentation.gd"))
		_dressing.set_meta("visual_only",true)
		_dressing.set_meta("reference_map",map_id)
		var scene_path := "res://scenes/%s.tscn" % ("main" if map_id=="test" else "training_ground" if map_id=="training" else "survival")
		var source := load(scene_path).instantiate() as Node3D
		root.add_child(source)
		if map_id=="test":
			source.call("set_arena_variant","test")
			_test_map(source.get_node("TestArena"))
		elif map_id=="training":
			_training_map(source)
		else:
			_survival_map(source)
		if not _save_batches():
			quit(1)
			return
		_save_lights()
		_dressing.set_meta("baked_triangles",_triangles)
		_dressing.set_meta("cloth_panels",_cloth_count)
		_dressing.set_meta("suspended_cable_runs",_cable_runs)
		_dressing.set_meta("decorative_grass_clumps",_grass_count)
		var packed := PackedScene.new()
		assert(packed.pack(_dressing)==OK)
		var error := ResourceSaver.save(packed,"res://scenes/environment/reference_%s.tscn" % map_id)
		if error!=OK:
			push_error("Map decoration save failed: "+error_string(error))
			quit(1)
			return
		print("MAP REFERENCE BAKED: %s triangles=%d batches=%d cloth=%d cables=%d grass=%d" % [map_id,_triangles,_batches.size(),_cloth_count,_cable_runs,_grass_count])
		root.get_node("GameSfx").call("clear")
		source.queue_free()
		_dressing.free()
		await process_frame
	quit()

func _at(point: Vector3, yaw := 0.0) -> void:
	_pose = Transform3D(Basis(Vector3.UP,yaw),point)
	_cell = _cell_for(point)

func _service_bay(point: Vector3, yaw: float, word: String, variant: int) -> void:
	# Back wall, storage and all uprights are beyond the playable perimeter.
	# The canvas cantilevers inward at 3.3 m; the ground below remains open.
	_at(point,yaw)
	_box(0,Vector3(0,1.15,0),Vector3(5.0,2.3,1.5),.12)
	_box(1,Vector3(0,1.05,.76),Vector3(4.74,1.95,.10),.045)
	_cover(5.0,2.3,1.5,variant,true)
	_sign(word,"07" if variant%2 else "02",5.0,2.3,1.5,7 if variant%2 else 8)
	for side in [-1.0,1.0]:
		_pole(Vector3(side*2.4,0,0),3.55)
		_beam(0,Vector3(side*2.4,2.6,0),Vector3(side*2.4,3.55,2.5),.045)
		_crate(Vector3(side*1.8,.48,.8),Vector3(.75,.90,.70),2 if side<0 else 0)
		_drum(Vector3(side*2.05,.58,1.0),.32,1.12,3)
		_lantern(Vector3(side*1.9,2.12,1.02))
	_cloth(4.8,2.5,_pose*Transform3D(Basis.IDENTITY,Vector3(0,3.55,0)),true,"BayCanopy%d" % variant)
	_sag_cable(Vector3(-2.4,3.6,2.4),Vector3(2.4,3.6,2.4),.22,.04,true)

func _grass(point: Vector3, radius := .58) -> void:
	var author := load("res://scripts/bush_visual.gd").new() as Node3D
	root.add_child(author)
	# Decorative brush is far shorter than the functional concealment volumes.
	# No bush group, actor-parting script, collision or navigation is serialized.
	author.call("setup",radius,.52,hash(point))
	var original := author.get_node("LayeredHighGrass") as MeshInstance3D
	var mesh_path := _output_dir()+"grass_%02d.res" % _grass_count
	assert(ResourceSaver.save(original.mesh,mesh_path,ResourceSaver.FLAG_CHANGE_PATH)==OK)
	var visual := MeshInstance3D.new()
	visual.name = "DecorativeGrass%02d" % _grass_count
	visual.mesh = ResourceLoader.load(mesh_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	visual.material_override = original.material_override.duplicate()
	visual.position = point+Vector3.UP*.02
	visual.set_meta("reference_grass",true)
	_dressing.add_child(visual)
	visual.owner = _dressing
	_grass_count += 1
	_at(point)
	var random := RandomNumberGenerator.new()
	random.seed = hash(point)
	for index in range(12):
		var angle := float(index)*TAU/12
		_rock(Vector3(cos(angle)*radius,.02,sin(angle)*radius),Vector3(.10,.07,.09),random)
	author.queue_free()

func _test_map(arena: Node3D) -> void:
	for body in arena.find_children("*LaneCover","StaticBody3D",true,false):
		_at(body.global_position-Vector3.UP*.75)
		_cover(2.8,1.5,.7,absi(body.name.hash()),false)
	# Deck machinery mounts on the outer shields. Decks, bridge and ramp entries
	# receive no new uprights, roofs or geometry above their walking surfaces.
	for side in [-1.0,1.0]:
		_at(Vector3(side*4.65,2.4,.6),PI*.5)
		for z in [-.60,.60]:
			_box(1,Vector3(z,.62,side*.27),Vector3(.48,.80,.045),.02)
			_ring(6,Vector3(z,.64,side*.305),.11,.025)
		_tube(4,[Vector3(-.86,.23,side*.28),Vector3(.86,.23,side*.28)],.028)
		_service_bay(Vector3(side*11.6,0,15.65),PI,"ATELIER" if side<0 else "PIECES",20 if side>0 else 21)
		_service_bay(Vector3(side*11.6,0,-15.65),0,"ATELIER" if side<0 else "PIECES",22 if side>0 else 23)
	_at(Vector3.ZERO)
	_foliage_debris()
	for point in [Vector3(-16,0,-12),Vector3(16,0,12)]:
		_grass(point)

func _training_map(arena: Node3D) -> void:
	for name_text in ["FixedCrates","MovingCrates","ShooterCrates","ShooterCoverLeft","ShooterCoverRight"]:
		var body := arena.get_node(name_text) as StaticBody3D
		_at(body.global_position-Vector3.UP*.675)
		_cover(2.1,1.35,2.1,absi(name_text.hash()),false)
		_canopy(2.1,1.35,2.1,name_text)
		if "Crates" in name_text:
			_sign("PIECES" if name_text=="ShooterCrates" else "ATELIER","07",2.1,1.35,2.1,8 if name_text=="ShooterCrates" else 7)
	for node in arena.get_children():
		if not node is StaticBody3D:
			continue
		var shapes := node.find_children("*","CollisionShape3D",false,false)
		var collision := shapes[0] as CollisionShape3D if not shapes.is_empty() else null
		if collision==null or not collision.shape is BoxShape3D:
			continue
		var size := (collision.shape as BoxShape3D).size
		if not is_equal_approx(size.y,.84) or minf(size.x,size.z)>.50:
			continue
		_at(node.global_position-Vector3.UP*.42,PI*.5 if size.x<size.z else 0)
		var length := maxf(size.x,size.z)
		for x in range(ceili(length/1.7)):
			var p := Vector3(-length*.45+x*1.55,.44,.24)
			_box(1,p,Vector3(1.36,.56,.045),.012)
			for sign_value in [-1.0,1.0]:
				_bolt(p+Vector3(sign_value*.53,.17,.03))
		_tube(4,[Vector3(-length*.47,.12,.26),Vector3(length*.47,.12,.26)],.035)
	for side in [-1.0,1.0]:
		_service_bay(Vector3(side*25,0,-39.2),0,"ATELIER" if side<0 else "PIECES",31 if side<0 else 32)
		_service_bay(Vector3(side*12,0,39.2),PI,"ATELIER" if side<0 else "PIECES",33 if side<0 else 34)
		for z in [-34.0,13.0,34.0]:
			_grass(Vector3(side*42,0,z),.72)
		_grass(Vector3(side*38.5,0,8.9),.62)
	# Tall cables frame the target bays; all endpoints are on solid divider rails.
	for x in [-28.5,-19.5]:
		_at(Vector3(x,0,-17))
		_pole(Vector3.ZERO,3.9)
	_at(Vector3.ZERO)
	_sag_cable(Vector3(-28.5,3.9,-17),Vector3(-19.5,3.9,-17),.40,.045,true)

func _survival_map(arena: Node3D) -> void:
	for wreck in arena.get_children():
		if not String(wreck.name).begins_with("Wreck") and not String(wreck.name).begins_with("BorderWreck"):
			continue
		_at(wreck.global_position,wreck.rotation.y)
		# The hull remains a wreck, with service equipment and new wear on its
		# existing casing. Broken wheels and existing navigable gaps stay intact.
		_roof_wear(4.0,1.90,1.65,absi(wreck.name.hash()))
		for side in [-1.0,1.0]:
			var face: float = side*1.045
			_box(1,Vector3(.52,.72,face),Vector3(1.35,.63,.045),.02)
			for x in [.0,1.03]:
				for y in [.48,.98]:
					_bolt(Vector3(x,y,face+side*.035))
			_ring(4,Vector3(-.82,.82,face+side*.025),.24,.031)
			_tube(6,[Vector3(-1.70,.34,face),Vector3(1.65,.34,face)],.027)
	for side in [-1.0,1.0]:
		_service_bay(Vector3(side*12,0,24.4),PI,"ATELIER" if side<0 else "PIECES",41 if side<0 else 42)
		_service_bay(Vector3(side*12,0,-24.4),0,"ATELIER" if side<0 else "PIECES",43 if side<0 else 44)
		for z in [-20.0,17.0]:
			_grass(Vector3(side*20.5,0,z),.76)
	# Factory machines and tanks share the workshop steel/ivory hardware family.
	for point in [Vector3(47,0,-4),Vector3(61,0,7),Vector3(49,0,11),Vector3(64,0,-11)]:
		_at(point)
		_cover(4.0,2.2,2.6,absi(hash(point)),false)
		_cloth(1.5,1.0,_pose*Transform3D(Basis.IDENTITY,Vector3(0,1.85,1.44)),false,"MachineBanner%d" % int(point.x+point.z))
	for point in [Vector3(39,0,-13),Vector3(70,0,12)]:
		_at(point)
		_tube(4,[Vector3(1.60,2.7,0),Vector3(1.9,2.5,0),Vector3(1.9,.10,0),Vector3(2.1,.10,.55)],.075,10)
		_cylinder(6,Vector3(0,2.87,0),.16,.17)
		_ring(0,Vector3(0,2.90,0),.40,.06,Basis(Vector3.RIGHT,PI*.5))
	for z in [-23.8,23.8]:
		_service_bay(Vector3(54,0,z),PI if z>0 else 0,"PIECES",50 if z>0 else 51)
		for x in [35.0,73.0]:
			_grass(Vector3(x,0,z*.87),.65)
	# The original gate leaf moves, so no decoration is baked onto it. Feeds
	# terminate on the two fixed columns and stay above the open doorway.
	_at(Vector3.ZERO)
	_sag_cable(Vector3(27,5.1,-6),Vector3(27,5.1,6),.30,.055,true)
