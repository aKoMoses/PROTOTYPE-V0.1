extends SceneTree
## Offline authoring tool. The saved skins contain one baked ArrayMesh each,
## six shared opaque materials, and no runtime script or physics nodes.

const ART_DIR := "res://art/environment/families/"
const SCENE_DIR := "res://scenes/environment/"
const NAMES := ["paint_cream", "paint_ivory", "steel_frame", "joint_rust", "sand_ochre", "cloth_brick"]
const COLORS := [Color.WHITE, Color("#e7e2d3"), Color.WHITE, Color("#9b603b"), Color("#b99a61"), Color("#884535")]
var materials: Array[Material] = []
var batches: Array = []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))
	for index in range(NAMES.size()):
		var material := StandardMaterial3D.new()
		material.resource_name = "Salvage / " + NAMES[index]
		material.albedo_color = COLORS[index]
		material.vertex_color_use_as_albedo = true
		material.roughness = [0.85, 0.88, 0.66, 0.96, 0.94, 0.99][index]
		material.metallic = [0.08, 0.08, 0.48, 0.18, 0.05, 0.0][index]
		if index in [0, 1, 2]:
			var finish := "steel" if index == 2 else "paint"
			material.albedo_texture = load("res://art/environment/courtyard_%s_albedo.png" % finish)
			material.normal_enabled = true
			material.normal_texture = load("res://art/environment/courtyard_%s_normal.png" % finish)
			material.normal_scale = 0.5
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3(0.42, 0.42, 0.42)
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		ResourceSaver.save(material, ART_DIR + NAMES[index] + ".tres")
		materials.append(load(ART_DIR + NAMES[index] + ".tres"))
	for variant in [0, 1]:
		batches.clear()
		for index in range(NAMES.size()):
			batches.append({"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()})
		_build_skin(variant)
		var mesh := ArrayMesh.new()
		mesh.resource_name = "Baked armored salvage " + ("A" if variant == 0 else "B")
		var triangle_count := 0
		for index in range(batches.size()):
			var data: Dictionary = batches[index]
			if data.vertices.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = data.vertices
			arrays[Mesh.ARRAY_NORMAL] = data.normals
			arrays[Mesh.ARRAY_COLOR] = data.colors
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[index])
			triangle_count += data.vertices.size() / 3
		var suffix := "" if variant == 0 else "_b"
		var mesh_path := ART_DIR + "cover_skin" + suffix + "_mesh.tres"
		ResourceSaver.save(mesh, mesh_path)
		var root_node := Node3D.new()
		root_node.name = "SalvageCover" + ("A" if variant == 0 else "B")
		root_node.set_meta("authored_unit_bounds", AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))
		root_node.set_meta("visual_only", true)
		var geometry := MeshInstance3D.new()
		geometry.name = "BakedArmorAndHardware"
		geometry.mesh = load(mesh_path)
		root_node.add_child(geometry)
		geometry.owner = root_node
		var scene := PackedScene.new()
		scene.pack(root_node)
		ResourceSaver.save(scene, SCENE_DIR + "cover_skin" + suffix + ".tscn")
		print("COVER_SKIN ", suffix, " triangles=", triangle_count, " surfaces=", mesh.get_surface_count(), " bounds=", mesh.get_aabb())
		root_node.free()
	quit()

func _tri(mat: int, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, tint := Color.WHITE) -> void:
	# Godot front faces are clockwise. Explicit outward normals retain the
	# bright bevels under sunlight and survive nonuniform instance scaling.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var temporary := b
		b = c
		c = temporary
	for vertex in [a, b, c]:
		assert(vertex.x >= -0.50001 and vertex.x <= 0.50001)
		assert(vertex.y >= -0.50001 and vertex.y <= 0.50001)
		assert(vertex.z >= -0.50001 and vertex.z <= 0.50001)
		batches[mat].vertices.append(vertex)
		batches[mat].normals.append(normal.normalized())
		batches[mat].colors.append(tint)

func _poly(mat: int, points: Array, normal: Vector3, tint := Color.WHITE) -> void:
	for index in range(1, points.size() - 1):
		_tri(mat, points[0], points[index], points[index + 1], normal, tint)

func _quad(mat: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, tint := Color.WHITE) -> void:
	_poly(mat, [a, b, c, d], normal, tint)

func _bevel_box(mat: int, center: Vector3, dimensions: Vector3, bevel: float, tint := Color.WHITE, yaw := 0.0) -> void:
	# A clipped cuboid: six planar faces, twelve bevel quads and eight corner
	# triangles. This gives a manufactured silhouette without high poly costs.
	var h := dimensions * 0.5
	var cut := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.70)
	var basis := Basis(Vector3.UP, yaw)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			var points := []
			normal[axis] = sign_value
			for signs in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = sign_value * h[axis]
				point[u] = signs.x * (h[u] - cut)
				point[v] = signs.y * (h[v] - cut)
				points.append(center + basis * point)
			_poly(mat, points, basis * normal, tint)
	if cut == 0.0:
		return
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var points := []
				for sa in [-1.0, 1.0]:
					for state in [0, 1]:
						var point := Vector3.ZERO
						point[axis] = sa * (h[axis] - cut)
						point[u] = su * (h[u] - cut * state)
						point[v] = sv * (h[v] - cut * (1 - state))
						points.append(center + basis * point)
				var normal := Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				_poly(mat, [points[0], points[1], points[3], points[2]], basis * normal, tint.darkened(0.04))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var signs := Vector3(sx, sy, sz)
				var points := []
				for axis in range(3):
					var point := signs * (h - Vector3.ONE * cut)
					point[axis] = signs[axis] * h[axis]
					points.append(center + basis * point)
				_poly(mat, points, basis * signs, tint.darkened(0.07))

func _box(mat: int, center: Vector3, dimensions: Vector3, tint := Color.WHITE, yaw := 0.0) -> void:
	_bevel_box(mat, center, dimensions, 0.0, tint, yaw)

func _bolt(center: Vector3, axis: int, radius: float, length: float) -> void:
	var normal := Vector3.ZERO
	normal[axis] = signf(center[axis])
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var front := []
	for index in range(6):
		var angle := float(index) * TAU / 6.0
		var point := center
		point[u] += cos(angle) * radius
		point[v] += sin(angle) * radius
		point[axis] += signf(center[axis]) * length * 0.5
		front.append(point)
	_poly(2, front, normal, Color(1.55, 1.48, 1.25))
	for index in range(6):
		var next := (index + 1) % 6
		var back_a: Vector3 = front[index] - normal * length
		var back_b: Vector3 = front[next] - normal * length
		var side_normal: Vector3 = (front[index] + front[next]) * .5 - center
		side_normal[axis] = 0.0
		_quad(2, back_a, front[index], front[next], back_b, side_normal.normalized(), Color(.8,.8,.8))

func _top_patch(mat: int, x: float, z: float, width: float, depth: float, y: float, tint := Color.WHITE) -> void:
	_poly(mat, [Vector3(x-width*.5,y,z-depth*.20), Vector3(x-width*.38,y,z-depth*.5), Vector3(x+width*.21,y,z-depth*.40), Vector3(x+width*.5,y,z+depth*.12), Vector3(x+width*.23,y,z+depth*.50), Vector3(x-width*.39,y,z+depth*.32)], Vector3.UP, tint)

func _face_patch(mat: int, x: float, y: float, width: float, height: float, z: float, tint := Color.WHITE) -> void:
	_poly(mat, [Vector3(x-width*.5,y-height*.2,z),Vector3(x-width*.3,y-height*.5,z),Vector3(x+width*.15,y-height*.35,z),Vector3(x+width*.5,y+height*.15,z),Vector3(x+width*.25,y+height*.5,z),Vector3(x-width*.3,y+height*.32,z)], Vector3(0,0,signf(z)), tint)

func _build_skin(variant: int) -> void:
	# Sealed steel substructure. Outer armor differs by less than 2% from the
	# exact functional box and every vertex is inside its unit envelope.
	# Layer separation is deliberately several millimetres after scaling the
	# thinnest perimeter modules. Nearly coplanar gaskets produced striping in
	# the real perspective Mobile camera even though close GL previews were clean.
	_bevel_box(2, Vector3(0,-0.020,0), Vector3(.950,.960,.952), .012)
	_bevel_box(3, Vector3(0,-.459,0), Vector3(.998,.082,.998), .012, Color(.8,.8,.8))
	_bevel_box(2, Vector3(0,-.405,0), Vector3(.998,.033,.998), .005)
	# Cap plate modules have broad, readable subdivisions, beveled edges,
	# offset colors and diagonal repairs instead of a plain dark upper face.
	var cap_ranges := [[-.482,-.180],[-.170,.148],[.158,.482]]
	for index in range(3):
		var interval: Array = cap_ranges[index]
		var x: float = (interval[0] + interval[1]) * .5
		# The concept has blue steel lids over warm painted front armor.
		var cap_mat := 2
		_box(3, Vector3(x,.460,0), Vector3(interval[1]-interval[0]+.008,.030,.952))
		_bevel_box(cap_mat, Vector3(x,.448,0), Vector3(interval[1]-interval[0],.100,.930), .028, Color(1.12, 1.12, 1.12))
		for z in [-.385,.385]:
			for bolt_x in [interval[0]+.033,interval[1]-.033]:
				_bolt(Vector3(bolt_x,.496,z),1,.009,.006)
		_top_patch(3, interval[0]+.045, -.388, .071,.024,.4942,Color(.87,.87,.87))
		_top_patch(3, interval[1]-.062, .370, .080,.026,.4942)
		_top_patch(3, x+.035, .055, .044,.025,.4942,Color(.88,.88,.88))
		_top_patch(2, x-.054,-.20,.060,.015,.4943,Color(1.45,1.45,1.45))
	# Raised dark strap ribs retain fast readable silhouettes; their caps are
	# flush with the collision ceiling and never float above it.
	for x in [-.168,.152]:
		_bevel_box(2,Vector3(x,.476,0),Vector3(.025,.048,.984),.006,Color(1.24,1.24,1.24))
		for z in [-.440,.440]:
			_bolt(Vector3(x,.497,z),1,.008,.004)
	for z in [-.480,.480]:
		_bevel_box(2,Vector3(0,.456,z),Vector3(.992,.037,.036),.009,Color(1.18,1.18,1.18))
	# Chunky folded corner guards catch light above the painted side panels.
	for x in [-.471,.471]:
		for z in [-.404,.404]:
			_bevel_box(2,Vector3(x,.449,z),Vector3(.052,.098,.160),.014,Color(1.24,1.24,1.24))
			_bolt(Vector3(x,.496,z),1,.011,.006)
	# Full side armor on both opposing faces. The lower ochre band reads as
	# settled dust, while isolated chips and seam rust remain directional.
	for side in [-1.0,1.0]:
		var z: float = side * .472
		for index in range(3):
			var interval: Array = cap_ranges[index]
			var x: float = (interval[0]+interval[1])*.5
			var face_mat := 0 if (index+variant)%3 != 0 else 1
			if variant == 1 and index == 2:
				face_mat = 5
			_box(3,Vector3(x,.002,z),Vector3(interval[1]-interval[0]+.007,.760,.031))
			_bevel_box(face_mat,Vector3(x,.007,side*.486),Vector3(interval[1]-interval[0],.727,.016),.006)
			_box(4,Vector3(x,-.329,side*.4990),Vector3(interval[1]-interval[0]-.018,.040,.001),Color(.8,.8,.8))
			_face_patch(3,interval[0]+.032,.292,.055,.038,side*.4994)
			_face_patch(3,interval[1]-.061,-.293,.080,.032,side*.4994,Color(.84,.84,.84))
			_face_patch(3,x+.047,-.167,.032,.022,side*.4994,Color(.92,.92,.92))
			_face_patch(1,x-.045,.160,.050,.038,side*.4995)
			for bolt_x in [interval[0]+.025,interval[1]-.025]:
				for bolt_y in [-.272,.285]:
					_bolt(Vector3(bolt_x,bolt_y,side*.498),2,.013,.004)
			# Local flaked enamel and rust runs anchor wear to panel corners.
			for chip in range(7):
				var cx: float = interval[0] + .018 + float(chip % 3) * .018
				var cy: float = -.30 + float(chip) * .018
				_face_patch(3,cx,cy,.009 + float(chip % 2)*.006,.013,side*.4994)
		for x in [-.485,-.172,.153,.485]:
			_box(2,Vector3(x,.010,side*.493),Vector3(.024,.795,.014),Color(1.25,1.25,1.25))
		# A welded broad diagonal reinforcement is inset into one panel.
		var brace_x := .32 if variant == 0 else -.32
		_poly(2,[Vector3(brace_x-.11,-.30,side*.4997),Vector3(brace_x-.07,-.30,side*.4997),Vector3(brace_x+.11,.30,side*.4997),Vector3(brace_x+.07,.30,side*.4997)],Vector3(0,0,side),Color(.88,.87,.84))
		# Small stencilled ochre strip: visually secondary to gameplay colors.
		for mark in range(2):
			_box(4,Vector3(-.375+mark*.037,.207,side*.4996),Vector3(.025,.034,.0004),Color(.72,.72,.72))
	# Recessed end machinery is geometrically closed by the hull. A cream
	# collar, rust lip and low slats imply a reclaimed powertrain housing.
	for end in [-1.0,1.0]:
		_bevel_box(1,Vector3(end*.469,.018,0),Vector3(.024,.776,.938),.005)
		_box(3,Vector3(end*.484,.030,.030),Vector3(.006,.510,.674))
		_box(2,Vector3(end*.493,.030,.030),Vector3(.001,.470,.634))
		for slot in range(5):
			var y: float = -.148+slot*.086
			_box(2,Vector3(end*.4997,y,.030),Vector3(.0004,.020,.532),Color(1.17,1.14,1.07))
		for z in [-.400,.400]:
			for y in [-.30,.32]:
				_bolt(Vector3(end*.4978,y,z),0,.009,.004)
	# A patch-repaired diagonal top plate distinguishes the second variant;
	# the first has a three-louvre maintenance inspection hatch.
	if variant == 0:
		_box(3,Vector3(.303,.491,0),Vector3(.185,.004,.430))
		_box(2,Vector3(.303,.4955,0),Vector3(.166,.001,.406))
		for slot in range(4):
			_box(2,Vector3(.303,.4995,-.145+slot*.095),Vector3(.133,.001,.030),Color(1.3,1.26,1.17))
		_box(5,Vector3(-.310,.4965,.270),Vector3(.220,.001,.052),Color(.9,.9,.9))
	else:
		_box(3,Vector3(.005,.490,-.005),Vector3(.266,.003,.342),Color(.86,.86,.86),-.25)
		_box(2,Vector3(.005,.496,-.005),Vector3(.244,.004,.310),Color(1.12,1.12,1.12),-.25)
		# Attached canvas patch drapes inside the sealed armor silhouette;
		# folded triangles give dry cloth facets and a torn lower edge.
		_quad(5,Vector3(-.420,.498,.320),Vector3(-.225,.498,.302),Vector3(-.232,.498,.450),Vector3(-.420,.498,.450),Vector3.UP)
		_quad(5,Vector3(-.420,.498,.450),Vector3(-.232,.498,.450),Vector3(-.214,.410,.4995),Vector3(-.422,.410,.4995),Vector3(0,1,1).normalized())
		_quad(5,Vector3(-.422,.410,.4995),Vector3(-.325,.410,.4985),Vector3(-.327,.075,.4985),Vector3(-.396,.046,.4995),Vector3(0,0,1),Color(.73,.73,.73))
		_poly(5,[Vector3(-.325,.410,.4985),Vector3(-.214,.410,.4995),Vector3(-.245,.032,.4995),Vector3(-.275,.094,.4995),Vector3(-.310,.024,.4985),Vector3(-.327,.075,.4985)],Vector3(0,0,1))
		for x in [-.405,-.241]:
			_bolt(Vector3(x,.499,.329),1,.008,.002)
