extends SceneTree
## Offline authoring: decorative equipment follows the existing cover footprints.
## Geometry is baked in spatial batches; no physics or navigation is generated.
const OUTPUT := "res://art/environment/workshops/"
const NAMES := ["steel", "paint", "rust", "ochre", "rubber", "dark", "brass", "cyan", "red", "amber", "stencil", "oil", "cyan_glow", "red_glow"]
var _materials: Array[Material] = []
var _batches: Dictionary = {}
var _pose := Transform3D.IDENTITY
var _cell := 0
var _dressing: Node3D
var _lights: Array[Dictionary] = []
var _cloth_count := 0
var _cover_count := 0
var _cable_runs := 0
var _triangles := 0

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_make_materials()
	_dressing = Node3D.new()
	_dressing.name = "WorkshopDressing"
	_dressing.set_script(load("res://scripts/environment/workshop_dressing.gd"))
	_dressing.set_meta("visual_only", true)
	var arena := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(arena)
	for body in get_nodes_in_group("arena_solid"):
		if body.get_meta("invisible_safety_limit", false):
			continue
		var size: Vector3 = (body.get_node("Collision").shape as BoxShape3D).size
		_pose = body.global_transform
		_pose.origin.y -= size.y * .5
		if size.x < size.z:
			_pose.basis *= Basis(Vector3.UP, PI * .5)
		_cell = _cell_for(_pose.origin)
		var name_text := str(body.name)
		var perimeter := "Panel" in name_text
		_cover(maxf(size.x, size.z), size.y, minf(size.x, size.z), absi(name_text.hash()), perimeter)
		if not perimeter:
			_cover_count += 1
			if name_text in ["SouthWestAngle", "NorthWestAngle"]:
				_sign("ATELIER", "07", maxf(size.x,size.z), size.y, minf(size.x,size.z), 7)
			elif name_text in ["SouthEastAngle", "NorthEastAngle"]:
				_sign("PIECES", "02", maxf(size.x,size.z), size.y, minf(size.x,size.z), 8)
			elif "Spine" in name_text:
				_text(10, "02" if "East" in name_text else "01", Vector3(-maxf(size.x,size.z)*.32,size.y*.55,minf(size.x,size.z)*.5+.018), .62)
			elif "Block" in name_text:
				_roof_storage(maxf(size.x,size.z), size.y, minf(size.x,size.z), absi(name_text.hash()))
			if name_text in ["SouthCenterCover", "NorthCenterCover", "WestPocketShort", "EastPocketShort"]:
				_canopy(maxf(size.x,size.z), size.y, minf(size.x,size.z), name_text)
	_pose = Transform3D.IDENTITY
	_overhead_network()
	_perimeter_workshops()
	_save_batches()
	_save_lights()
	_dressing.set_meta("dressed_covers", _cover_count)
	_dressing.set_meta("suspended_cable_runs", _cable_runs)
	_dressing.set_meta("cloth_panels", _cloth_count)
	_dressing.set_meta("baked_triangles", _triangles)
	var packed := PackedScene.new()
	assert(packed.pack(_dressing) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/environment/workshop_dressing.tscn") == OK)
	print("WORKSHOPS BAKED: %d covers, %d anchored overhead cable runs, %d cloth panels, %d triangles, %d spatial batches" % [_cover_count,_cable_runs,_cloth_count,_triangles,_batches.size()])
	root.get_node("GameSfx").call("clear")
	arena.queue_free()
	_dressing.free()
	await process_frame
	quit()

func _make_materials() -> void:
	var colors := ["#849099", "#bbb39b", "#8c4d34", "#b18b3c", "#252a2c", "#28363b", "#947554", "#32d5de", "#ff6446", "#ffd18a", "#d1c6a8"]
	for index in colors.size():
		var material := StandardMaterial3D.new()
		material.resource_name = "Workshop_" + NAMES[index]
		material.albedo_color = Color(colors[index])
		material.roughness = .85
		if index in [0,1,2,3,6]:
			material.albedo_texture = load("res://art/environment/courtyard_steel_albedo.png" if index in [0,6] else "res://art/environment/courtyard_paint_albedo.png")
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3.ONE * .9
			material.metallic = .55 if index in [0,6] else .16
			material.normal_enabled = true
			material.normal_texture = load("res://art/environment/courtyard_steel_normal.png")
			material.normal_scale = .32
		if index in [7,8,9]:
			material.emission_enabled = true
			material.emission = Color(colors[index])
			material.emission_energy_multiplier = 1.15 if index != 9 else 1.2
		if index == 10:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		assert(ResourceSaver.save(material,OUTPUT+NAMES[index]+".tres",ResourceSaver.FLAG_CHANGE_PATH) == OK)
		_materials.append(material)
	var stain := ShaderMaterial.new()
	stain.shader = load("res://shaders/workshop_oil.gdshader")
	assert(ResourceSaver.save(stain,OUTPUT+"oil.tres",ResourceSaver.FLAG_CHANGE_PATH) == OK)
	_materials.append(stain)
	for index in [12,13]:
		var glow := ShaderMaterial.new()
		glow.shader = load("res://shaders/workshop_neon_halo.gdshader")
		glow.set_shader_parameter("neon_color",Color("#30ceda") if index==12 else Color("#ff5a32"))
		assert(ResourceSaver.save(glow,OUTPUT+NAMES[index]+".tres",ResourceSaver.FLAG_CHANGE_PATH) == OK)
		_materials.append(glow)

func _cell_for(point: Vector3) -> int:
	return clampi(floori((point.x+32)/16),0,3) + 4*clampi(floori((point.z+32)/16),0,3)

func _data(material: int) -> Dictionary:
	var key := "%02d_%02d" % [_cell,material]
	if not _batches.has(key):
		_batches[key] = {"v":PackedVector3Array(),"n":PackedVector3Array(),"uv":PackedVector2Array(),"mat":material}
	return _batches[key]

func _triangle(material: int, a: Vector3, b: Vector3, c: Vector3, ua := Vector2.ZERO, ub := Vector2.RIGHT, uc := Vector2.ONE) -> void:
	var normal := _pose.basis * (b-a).cross(c-a).normalized()
	var data := _data(material)
	data.v.append_array(PackedVector3Array([_pose*a,_pose*c,_pose*b]))
	data.n.append_array(PackedVector3Array([normal,normal,normal]))
	data.uv.append_array(PackedVector2Array([ua,uc,ub]))
	_triangles += 1

func _quad(material: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(material,a,b,c)
	_triangle(material,a,c,d,Vector2.ZERO,Vector2.ONE,Vector2.DOWN)

func _box(material: int, center: Vector3, size: Vector3, bevel := .025, basis := Basis.IDENTITY) -> void:
	var h := size*.5
	var e := minf(bevel,minf(h.x,h.z)*.7)
	var footprint := [Vector2(-h.x,-h.z),Vector2(h.x,-h.z),Vector2(h.x,h.z),Vector2(-h.x,h.z)] if bevel <= .01 or minf(size.x,minf(size.y,size.z)) < .06 else [Vector2(-h.x+e,-h.z),Vector2(h.x-e,-h.z),Vector2(h.x,-h.z+e),Vector2(h.x,h.z-e),Vector2(h.x-e,h.z),Vector2(-h.x+e,h.z),Vector2(-h.x,h.z-e),Vector2(-h.x,-h.z+e)]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for p in footprint:
		top.append(center+basis*Vector3(p.x,h.y,p.y))
		bottom.append(center+basis*Vector3(p.x,-h.y,p.y))
	for index in footprint.size():
		var next := (index+1)%footprint.size()
		_quad(material,bottom[index],top[index],top[next],bottom[next])
		_triangle(material,center+basis*Vector3(0,h.y,0),top[next],top[index])
		_triangle(material,center+basis*Vector3(0,-h.y,0),bottom[index],bottom[next])

func _tube(material: int, points: Array[Vector3], radius: float, sides := 6) -> void:
	for index in range(points.size()-1):
		var a := points[index]
		var b := points[index+1]
		var direction := (b-a).normalized()
		var right := direction.cross(Vector3.UP if absf(direction.y)<.9 else Vector3.RIGHT).normalized()
		var up := direction.cross(right).normalized()
		for side in sides:
			var angle := float(side)*TAU/sides
			var next := float(side+1)*TAU/sides
			var p := (right*cos(angle)+up*sin(angle))*radius
			var q := (right*cos(next)+up*sin(next))*radius
			_quad(material,a+p,a+q,b+q,b+p)

func _beam(material: int, a: Vector3, b: Vector3, radius: float) -> void:
	_tube(material,[a,b],radius)

func _cylinder(material: int, center: Vector3, radius: float, height: float, basis := Basis.IDENTITY, segments := 12) -> void:
	for index in segments:
		var angle := float(index)*TAU/segments
		var next := float(index+1)*TAU/segments
		var a := center+basis*Vector3(cos(angle)*radius,-height*.5,sin(angle)*radius)
		var b := center+basis*Vector3(cos(next)*radius,-height*.5,sin(next)*radius)
		var c := b+basis*Vector3.UP*height
		var d := a+basis*Vector3.UP*height
		_quad(material,a,d,c,b)
		_triangle(material,center+basis*Vector3.UP*height*.5,c,d)
		_triangle(material,center-basis*Vector3.UP*height*.5,a,b)

func _ring(material: int, center: Vector3, radius: float, thickness: float, basis := Basis.IDENTITY, segments := 20) -> void:
	var points: Array[Vector3] = []
	for index in range(segments+1):
		var angle := float(index)*TAU/segments
		points.append(center+basis*Vector3(cos(angle)*radius,sin(angle)*radius,0))
	_tube(material,points,thickness)

func _bolt(point: Vector3) -> void:
	_cylinder(6,point,.045,.028,Basis(Vector3.RIGHT,PI*.5),6)

func _text(material: int, value: String, center: Vector3, width: float) -> void:
	var mesh := TextMesh.new()
	mesh.font = ThemeDB.fallback_font
	mesh.text = value
	mesh.font_size = 80
	mesh.pixel_size = .01
	mesh.depth = 0
	var bounds := mesh.get_aabb()
	var scale_factor := width/maxf(bounds.size.x,.001)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var data := _data(material)
		for index in indices:
			data.v.append(_pose*(center+(vertices[index]-bounds.get_center())*scale_factor))
			data.n.append(_pose.basis*normals[index])
			data.uv.append(Vector2.ZERO)
		_triangles += indices.size()/3

func _neon_word(material: int, word: String, center: Vector3, width: float) -> void:
	# Bent glass tubing with metal mounting clips, rather than a luminous solid font.
	var glyphs := {
		"A":[[0,0,.5,1,1,0],[.22,.42,.78,.42]],
		"T":[[0,1,1,1],[.5,1,.5,0]],
		"E":[[1,1,0,1,0,0,1,0],[0,.5,.80,.5]],
		"L":[[0,1,0,0,1,0]],
		"I":[[.5,1,.5,0]],
		"R":[[0,0,0,1,.80,1,1,.82,1,.63,.8,.52,0,.52],[.48,.52,1,0]],
		"P":[[0,0,0,1,.80,1,1,.82,1,.63,.8,.52,0,.52]],
		"C":[[1,.91,.78,1,.18,1,0,.82,0,.18,.18,0,.8,0,1,.10]],
		"S":[[1,.91,.78,1,.18,1,0,.82,0,.65,.18,.5,.82,.5,1,.35,1,.18,.82,0,.18,0,0,.09]],
		"Y":[[0,1,.5,.52,1,1],[.5,.52,.5,0]],
		"G":[[1,.91,.78,1,.18,1,0,.82,0,.18,.18,0,.82,0,1,.18,1,.47,.57,.47]],
		"B":[[0,0,0,1,.75,1,1,.8,1,.7,.75,.52,0,.52],[.75,.52,1,.32,1,.2,.75,0,0,0]],
		"0":[[.18,0,0,.2,0,.8,.18,1,.82,1,1,.8,1,.2,.82,0,.18,0]],
		"1":[[.15,.8,.5,1,.5,0]],
		"2":[[0,.8,.2,1,.8,1,1,.8,1,.65,0,0,1,0]],
		"3":[[0,1,.8,1,1,.8,.8,.5,.4,.5],[.8,.5,1,.2,.8,0,0,0]],
		"4":[[.8,0,.8,1,0,.3,1,.3]],
		"5":[[1,1,0,1,0,.55,.8,.55,1,.35,1,.2,.8,0,0,0]],
		"6":[[1,1,.2,1,0,.8,0,.2,.2,0,.8,0,1,.2,1,.45,.8,.55,0,.55]],
		"7":[[0,1,1,1,.3,0]],
		"8":[[.2,.5,0,.7,0,.82,.2,1,.8,1,1,.82,1,.7,.8,.5,.2,.5,0,.3,0,.2,.2,0,.8,0,1,.2,1,.3,.8,.5]],
		"9":[[1,.45,.2,.45,0,.65,0,.8,.2,1,.8,1,1,.8,1,.2,.8,0,0,0]]
	}
	var advance := width/word.length()
	var glyph_width := advance*.68
	var glyph_height := minf(.42,advance*1.18)
	for index in word.length():
		var character := word.substr(index,1)
		if not glyphs.has(character):
			continue
		for stroke in glyphs[character]:
			var points: Array[Vector3] = []
			for vertex in range(stroke.size()/2):
				points.append(center+Vector3(-width*.5+advance*(index+.16)+float(stroke[vertex*2])*glyph_width,(float(stroke[vertex*2+1])-.5)*glyph_height,0))
			_tube(5,points,.036)
			for point_index in points.size():
				points[point_index].z += .028
			_tube(material,points,.024,8)
			_tube(12 if material==7 else 13,points,.070,8)
			for point in [points[0],points[-1]]:
				_box(6,point-Vector3(0,0,.04),Vector3(.05,.07,.025),.004)

func _cover(length: float, height: float, depth: float, seed_value: int, perimeter: bool) -> void:
	# Bolted front equipment stays recessed into the original blocking volume.
	# Only thin lips, connectors and conduits project a few centimetres.
	var face := depth*.5+.025
	var placements := [-.29,.21] if length > 5 else [-.24,.22]
	for side in [-1.0,1.0]:
		var saved_pose := _pose
		if side < 0:
			_pose.basis *= Basis(Vector3.UP,PI)
		var x := length*float(placements[0])
		var box_y := height*.48
		_box(2 if seed_value%3==0 else 1,Vector3(x,box_y,face-.12),Vector3(.90,height*.62,.28),.06)
		_box(5,Vector3(x,box_y+.12,face+.025),Vector3(.69,height*.31,.023))
		for row in range(6):
			_box(0,Vector3(x,box_y-.12+float(row)*.075,face+.045),Vector3(.63,.025,.052),.003)
		_box(6,Vector3(x+.29,box_y-.34,face+.055),Vector3(.05,.11,.028))
		for dx in [-.35,.35]:
			for dy in [-height*.26,height*.26]:
				_bolt(Vector3(x+dx,box_y+dy,face+.03))
		var cabinet := Vector3(length*float(placements[1]),height*.45,face-.08)
		_box(0,cabinet,Vector3(.70,.86,.22),.045)
		_box(3,cabinet+Vector3(0,0,.125),Vector3(.54,.68,.022),.025)
		_box(5,cabinet+Vector3(0,.18,.15),Vector3(.26,.15,.015))
		for lamp in range(3):
			_box(7 if lamp==0 else 9,cabinet+Vector3(-.13+float(lamp)*.13,-.10,.15),Vector3(.035,.045,.02))
		_bolt(cabinet+Vector3(.21,-.21,.15))
		_tube(4,[cabinet+Vector3(0,-.44,.10),Vector3(cabinet.x,height*.14,face+.025),Vector3(x,height*.12,face+.025),Vector3(x,box_y-.40,face+.025)],.035)
		_tube(6,[Vector3(-length*.44,height*.77,face+.015),Vector3(length*.43,height*.77,face+.015)],.025)
		for clip in range(5):
			_box(0,Vector3((- .41 + clip*.205)*length,height*.77,face+.025),Vector3(.065,.14,.06),.008)
		if not perimeter:
			_lantern(Vector3(length*.36,height*.86,face+.13))
			_spare_parts(Vector3(-length*.42,height*.50,face-.035),seed_value)
			# Coiled service hose, brackets and tools occupy the remaining panel.
			var coil := Vector3(length*.01,height*.49,face+.04)
			for loop in range(3):
				_ring(4,coil+Vector3(0,0,loop*.022),.27-loop*.025,.023)
			_box(6,coil+Vector3(0,.27,0),Vector3(.13,.08,.12),.01)
			_tube(4,[coil+Vector3(.17,-.21,.04),coil+Vector3(.24,-.42,.04),coil+Vector3(.13,-.52,.04)],.023)
			for tool in range(2):
				var point := Vector3(length*.10+tool*.22,height*.48,face+.05)
				_box(0,point,Vector3(.045,.30,.055),.006)
				_ring(6,point+Vector3.UP*.18,.065,.021, Basis.IDENTITY,10)
			# Faded repair patches give each workshop face a different history.
			for chip in range(7):
				var offset := fposmod(float(seed_value%1000)*.13+chip*1.71,1.0)
				_box(2,Vector3((- .40 + offset*.78)*length,height*(.12+fposmod(chip*.37,1.0)*.75),face+.011),Vector3(.12+offset*.14,.024,.008),.001)
			_ground_stain(Vector3(length*.24,.016,depth*.5+.33),Vector2(2.3,1.4))
		_pose = saved_pose
	# Roof details: low enclosed vents, protective ribs, power leads and scrap.
	for item in range(3 if not perimeter else 1):
		var x := (-.31+float(item)*.30)*length
		_box(5,Vector3(x,height+.045,0),Vector3(.76,.07,minf(depth*.64,.66)),.045)
		for rib in range(5):
			_box(0,Vector3(x-.28+rib*.14,height+.091,0),Vector3(.042,.034,minf(depth*.55,.60)),.004)
	var points: Array[Vector3] = []
	for step in range(18):
		var t := float(step)/17
		points.append(Vector3(lerpf(-length*.46,length*.46,t),height+.075,sin(t*TAU*1.7+seed_value)*minf(depth*.25,.3)))
	_tube(4,points,.042)
	_tube(6,[Vector3(-length*.38,height+.04,-depth*.30),Vector3(length*.32,height+.04,-depth*.30)],.023)
	if not perimeter:
		_box(2,Vector3(length*.34,height+.17,-depth*.18),Vector3(.66,.28,.46),.07)
		_box(0,Vector3(length*.34,height+.32,-depth*.18),Vector3(.73,.06,.49),.04)
		for latch in [-.23,.23]:
			_box(6,Vector3(length*.34+latch,height+.19,depth*.05),Vector3(.055,.14,.04),.006)
		for item in range(3):
			_box(0 if item%2==0 else 6,Vector3(-length*.36+item*.24,height+.06,depth*.12),Vector3(.34,.07,.16),.02,Basis(Vector3.UP,float(item)*.27))
		if depth>1.70:
			_end_machines(length,height,depth,seed_value)

func _end_machines(length: float, height: float, depth: float, variant: int) -> void:
	var saved_pose := _pose
	for side in [-1.0,1.0]:
		_pose = saved_pose*Transform3D(Basis(Vector3.UP,side*PI*.5),Vector3(side*length*.5,0,0))
		var width := depth*.79
		_box(2,Vector3(0,height*.5,-.065),Vector3(width,height*.76,.15),.055)
		_box(5,Vector3(0,height*.57,.02),Vector3(width*.85,height*.38,.03),.025)
		for row in range(7):
			_box(0,Vector3(0,height*.42+row*height*.048,.046),Vector3(width*.76,.045,.058),.004)
		_box(1,Vector3(0,height*.23,.034),Vector3(width*.83,height*.18,.03),.02)
		_text(10,str(variant%8+1).pad_zeros(2),Vector3(0,height*.23,.055),width*.36)
		for dx in [-width*.41,width*.41]:
			for y in [height*.16,height*.82]:
				_bolt(Vector3(dx,y,.032))
		_box(9,Vector3(width*.34,height*.78,.065),Vector3(.055,.055,.025),.007)
		_tube(4,[Vector3(-width*.37,height*.16,.075),Vector3(-width*.37,.10,.04),Vector3(width*.37,.10,.04),Vector3(width*.37,height*.17,.075)],.025)
	_pose = saved_pose

func _spare_parts(point: Vector3, variant: int) -> void:
	if variant%2==0:
		# Pressure vessel, strap, gauge and attached hose.
		_cylinder(3,point,.16,.74)
		for dy in [-.25,.25]:
			_cylinder(0,point+Vector3.UP*dy,.18,.065)
		_cylinder(6,point+Vector3(0,.40,0),.07,.12)
		_cylinder(5,point+Vector3(0,.16,.16),.08,.055,Basis(Vector3.RIGHT,PI*.5),10)
		_box(10,point+Vector3(0,.17,.20),Vector3(.075,.014,.015),.001)
		_tube(4,[point+Vector3(0,.43,0),point+Vector3(.26,.30,.04),point+Vector3(.26,-.40,.10),point+Vector3(-.02,-.48,.08)],.023)
	else:
		# A robot forearm clamped to the panel: joints, pistons and open gripper.
		for dy in [-.27,.23]:
			_cylinder(0,point+Vector3(0,dy,.10),.105,.10,Basis(Vector3.RIGHT,PI*.5),10)
		_box(2,point+Vector3(0,-.03,.08),Vector3(.20,.43,.14),.05)
		for dx in [-.14,.14]:
			_beam(6,point+Vector3(dx,-.20,.09),point+Vector3(dx,.16,.09),.025)
		for dx in [-.07,.07]:
			_tube(0,[point+Vector3(dx,-.35,.10),point+Vector3(dx*1.8,-.47,.10),point+Vector3(dx,-.52,.12)],.030)
		_box(6,point+Vector3(0,.28,.04),Vector3(.37,.075,.13),.018)

func _ground_stain(point: Vector3, size: Vector2) -> void:
	var a := point+Vector3(-size.x*.5,0,-size.y*.5)
	var b := point+Vector3(-size.x*.5,0,size.y*.5)
	var c := point+Vector3(size.x*.5,0,size.y*.5)
	var d := point+Vector3(size.x*.5,0,-size.y*.5)
	_triangle(11,a,b,c,Vector2.ZERO,Vector2.DOWN,Vector2.ONE)
	_triangle(11,a,c,d,Vector2.ZERO,Vector2.ONE,Vector2.RIGHT)

func _lantern(point: Vector3) -> void:
	_box(0,point+Vector3(0,.15,-.065),Vector3(.34,.12,.25),.06)
	_cylinder(9,point,.095,.24,Basis.IDENTITY,10)
	_cylinder(5,point+Vector3(0,-.15,0),.14,.055)
	for angle in range(4):
		var a := float(angle)*TAU/4
		_beam(5,point+Vector3(cos(a)*.12,-.14,sin(a)*.12),point+Vector3(cos(a)*.12,.14,sin(a)*.12),.014)
	var world := _pose*point
	_lights.append({"position":world,"color":Color("#ffc279"),"range":3.4,"energy":1.05})

func _sign(word: String, number: String, length: float, height: float, depth: float, color: int) -> void:
	var center := Vector3(-length*.04,height+.41,depth*.24)
	var width := minf(length*.72,3.8)
	# Posts are physically attached to the lid, and do not enter the walkable lane.
	for side in [-1.0,1.0]:
		_box(0,Vector3(center.x+side*width*.39,height+.26,center.z-.06),Vector3(.08,.63,.10),.015)
		_box(6,Vector3(center.x+side*width*.39,height+.025,center.z-.06),Vector3(.26,.05,.30))
	_box(2,center,Vector3(width,.66,.16),.07)
	_box(5,center+Vector3(0,0,.094),Vector3(width-.13,.52,.035),.035)
	_neon_word(color,word,center+Vector3(-width*.11,0,.12),width*.70)
	_neon_word(8 if color==7 else 7,number,center+Vector3(width*.37,0,.12),width*.20)
	for dy in [-.28,.28]:
		_box(6,center+Vector3(0,dy,.12),Vector3(width-.12,.025,.028),.003)
	for side in [-1.0,1.0]:
		_bolt(center+Vector3(side*(width*.5-.08),.22,.12))
	_tube(4,[center+Vector3(width*.46,-.28,-.04),Vector3(width*.46,height+.06,-depth*.15),Vector3(length*.34,height+.06,-depth*.15)],.032)
	_lights.append({"position":_pose*(center+Vector3(0,-.24,.23)),"color":Color("#3ed3dd") if color==7 else Color("#ff6241"),"range":3.8,"energy":.85})

func _roof_storage(length: float, height: float, depth: float, variant: int) -> void:
	for item in range(3):
		var x := (-.25+item*.25)*length
		var z := .16 if item%2==0 else -.34
		_box(1 if item==0 else 2,Vector3(x,height+.25,z),Vector3(.68,.42,.73),.08)
		for dz in [-.29,.29]:
			_box(0,Vector3(x,height+.47,z+dz),Vector3(.72,.045,.075))
		_box(6,Vector3(x,height+.24,z+.37),Vector3(.26,.15,.024),.01)
	var face := depth*.5+.035
	_text(10,"DEPOT " + str(variant%8+1).pad_zeros(2),Vector3(0,height*.70,face),length*.57)
	# A visible spare rotor bolted flat to the existing roof.
	_ring(4,Vector3(length*.25,height+.05,-depth*.22),.37,.06,Basis(Vector3.RIGHT,PI*.5))
	for blade in range(5):
		var a := float(blade)*TAU/5
		var b := Basis(Vector3.UP,a)
		_box(0,Vector3(length*.25,height+.08,-depth*.22)+b*Vector3(.20,0,0),Vector3(.36,.045,.12),.025,b)

func _canopy(length: float, height: float, depth: float, name_text: String) -> void:
	var width := minf(length*.44,3.4)
	var center_x := -.05*length
	var front := depth*.47
	var back := -depth*.43
	for side in [-1.0,1.0]:
		var x: float = center_x+side*width*.5
		_beam(0,Vector3(x,height+.02,back),Vector3(x,height+.60,back),.035)
		_beam(0,Vector3(x,height+.02,front),Vector3(x,height+.32,front),.035)
		_beam(6,Vector3(x,height+.60,back),Vector3(x,height+.32,front),.021)
	_cloth(width,depth*.90,_pose*Transform3D(Basis.IDENTITY,Vector3(center_x,height+.61,back)),true,"Canopy"+name_text)
	# Sewn front banner sits against the blocking wall, with a gear identity.
	_cloth(minf(length*.28,2.4),.70,_pose*Transform3D(Basis.IDENTITY,Vector3(length*.02,height*.82,depth*.5+.06)),false,"Banner"+name_text)
	for side in [-1.0,1.0]:
		_bolt(Vector3(length*.02+side*minf(length*.14,1.2),height*.82,depth*.5+.07))

func _cloth(width: float, extent: float, transform: Transform3D, canopy: bool, node_name: String) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/environment/yard_cloth.gdshader")
	material.set_shader_parameter("canvas_texture",load("res://art/environment/workshop_canvas.svg"))
	material.set_shader_parameter("canvas_tint",Color("#ebc393") if canopy else Color("#cd8d61"))
	material.set_shader_parameter("four_corner_pin",canopy)
	material.set_shader_parameter("phase",float(_cloth_count)*1.43)
	surface.set_material(material)
	var resolution := 12
	for y in resolution:
		for x in resolution:
			var coords := [Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y+1)]
			var vertices: Array[Vector3] = []
			for coord in coords:
				var uv: Vector2 = coord/resolution
				var sag := sin(uv.x*PI)*sin(uv.y*PI)
				vertices.append(Vector3((uv.x-.5)*width,-uv.y*.28-sag*.12,uv.y*extent) if canopy else Vector3((uv.x-.5)*width,-uv.y*extent,.035*sin(uv.x*TAU)*uv.y))
			for index in [0,1,2,0,2,3]:
				surface.set_uv(coords[index]/resolution)
				surface.set_normal(Vector3(0,extent,.28).normalized() if canopy else Vector3.BACK)
				surface.add_vertex(vertices[index])
	var mesh := surface.commit()
	var path := OUTPUT+node_name+".res"
	assert(ResourceSaver.save(mesh,path) == OK)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = load(path)
	node.material_override = material
	node.transform = transform
	node.extra_cull_margin = .22
	node.set_meta("workshop_cloth",true)
	_dressing.add_child(node)
	node.owner = _dressing
	_cloth_count += 1

func _pole(point: Vector3, top: float) -> void:
	_box(6,point+Vector3(0,.08,0),Vector3(.34,.16,.34))
	_cylinder(0,point+Vector3(0,top*.5,0),.055,top)
	for dy in [-.13,0,.13]:
		_cylinder(3,point+Vector3(0,top-.17+dy,0),.10,.065)
	_box(2,point+Vector3(0,.29,0),Vector3(.30,.50,.20),.03)

func _sag_cable(a: Vector3, b: Vector3, sag: float, radius: float, bulbs := false) -> void:
	_cell = _cell_for((a+b)*.5)
	var points: Array[Vector3] = []
	for index in range(33):
		var t := float(index)/32
		points.append(a.lerp(b,t)-Vector3.UP*(4*t*(1-t)*sag))
	_tube(4,points,radius)
	_cable_runs += 1
	for index in [0,32]:
		_ring(6,points[index],.11,.025)
	if bulbs:
		for index in [8,16,24]:
			var p: Vector3 = points[index]
			_beam(4,p,p-Vector3.UP*.16,.019)
			_lantern(p-Vector3.UP*.30)

func _overhead_network() -> void:
	# All cables cross lanes well above combat height and terminate on roof poles.
	for z in [-2.7,5.0]:
		for x in [-7.0,7.0]:
			_cell = _cell_for(Vector3(x,0,z))
			_pole(Vector3(x,2.20,z),1.45)
		_sag_cable(Vector3(-7,3.65,z),Vector3(7,3.65,z),.60,.052,true)
		_sag_cable(Vector3(-7,3.62,z-.12),Vector3(7,3.62,z-.12),.51,.025)
	for side in [-1.0,1.0]:
		var a := Vector3(side*12,1.9,8.1 if side<0 else -6.7)
		var b := Vector3(side*18.5,2.0,8.5 if side<0 else -8.5)
		for point in [a,b]:
			_cell = _cell_for(point)
			_pole(point,1.4)
		_sag_cable(a+Vector3.UP*1.40,b+Vector3.UP*1.40,.22,.042,true)
		_sag_cable(a+Vector3.UP*1.32+Vector3.FORWARD*.09,b+Vector3.UP*1.32+Vector3.FORWARD*.09,.19,.024)
	# Peripheral feeds are attached to the perimeter itself.
	for side in [-1.0,1.0]:
		for z in [-20.0,0.0,20.0]:
			_cell = _cell_for(Vector3(side*28.1,0,z))
			_pole(Vector3(side*28.1,2.1,z),1.65)
		for interval in [-20.0,0.0]:
			_sag_cable(Vector3(side*28.1,3.75,interval),Vector3(side*28.1,3.75,interval+20),.53,.048,true)

func _perimeter_workshops() -> void:
	# Entire bulky store compositions remain outside the continuous arena limits.
	for bay in range(8):
		var x := -35.0 if bay%2==0 else 35.0
		var z := -21.0+float(bay/2)*14.0
		_pose = Transform3D(Basis(Vector3.UP,PI*.5 if x<0 else -PI*.5),Vector3(x,0,z))
		_cell = _cell_for(_pose.origin)
		_box(2,Vector3(0,1.1,0),Vector3(5.0,2.2,2.7),.15)
		_box(0,Vector3(0,2.3,0),Vector3(5.6,.25,3.1),.08)
		for dx in [-1.7,0,1.7]:
			_box(5,Vector3(dx,1.2,1.37),Vector3(1.4,1.55,.08))
			for slat in range(8):
				_box(0,Vector3(dx,.50+slat*.17,1.43),Vector3(1.36,.065,.065),.008)
		_text(10,"DEPOT " + str(bay+1).pad_zeros(2),Vector3(0,1.94,1.46),2.4)
		_roof_storage(4.6,2.43,2.6,bay)
		_sign("RECYCLAGE" if bay%2==0 else "BATTERIES",str(bay+1).pad_zeros(2),5.0,2.50,2.7,7 if bay%2==0 else 8)
		for dx in [-2.0,2.0]:
			_lantern(Vector3(dx,2.05,1.55))
			for stack in range(3):
				_cylinder(4,Vector3(dx,.18+stack*.22,2.0),.39,.18)
				_cylinder(0,Vector3(dx,.18+stack*.22,2.0),.24,.19)
	_pose = Transform3D.IDENTITY

func _save_batches() -> void:
	for key in _batches:
		var data: Dictionary = _batches[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.v
		arrays[Mesh.ARRAY_NORMAL] = data.n
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(0,_materials[data.mat])
		var indexed := SurfaceTool.new()
		indexed.create_from(mesh,0)
		indexed.index()
		mesh = indexed.commit()
		var path := OUTPUT+"batch_"+str(key)+".res"
		assert(ResourceSaver.save(mesh,path) == OK)
		var node := MeshInstance3D.new()
		node.name = "Workshop_"+str(key)
		node.mesh = load(path)
		if data.mat in [7,8,9,10,11,12,13]:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dressing.add_child(node)
		node.owner = _dressing

func _save_lights() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/workshop_light_pool.gdshader")
	for index in _lights.size():
		var data: Dictionary = _lights[index]
		var light := OmniLight3D.new()
		light.name = "WorkshopLight%02d" % index
		light.position = data.position
		light.light_color = data.color
		light.light_energy = data.energy
		light.omni_range = data.range
		light.omni_attenuation = 1.6
		light.shadow_enabled = false
		light.set_meta("workshop_light",true)
		_dressing.add_child(light)
		light.owner = _dressing
		# Small baked radial pools keep the warm ambience also on low quality.
		# One quad per lamp, no shadow maps or extra depth texture.
		var mesh := PlaneMesh.new()
		mesh.size = Vector2.ONE*data.range*1.35
		var pool := MeshInstance3D.new()
		pool.name = "LightPool%02d" % index
		pool.mesh = mesh
		pool.position = Vector3(data.position.x,.027+float(index%4)*.001,data.position.z)
		pool.material_override = material.duplicate()
		pool.material_override.set_shader_parameter("light_color",data.color)
		pool.material_override.set_shader_parameter("strength",.48 if data.color.r>data.color.g else .30)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dressing.add_child(pool)
		pool.owner = _dressing
