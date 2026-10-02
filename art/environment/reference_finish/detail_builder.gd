extends RefCounted
## Deterministic, visual-only scenery. Batched by material and 32 m cell.
## Tall leaves stay outside the playable wall. Interior rubble stays below
## 12 cm and is never admitted to concealment, physics, navigation or sight.
const SHADER := preload("res://art/environment/reference_finish/details.gdshader")
var _batches: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _triangles := 0
var _plants := 0
var _stones := 0

func build(parent: Node3D, scene: Node3D) -> void:
	_rng.seed = 202610022
	var root := Node3D.new()
	root.name = "ReferenceEdgeDetails"
	root.set_meta("visual_only", true)
	parent.add_child(root)
	# The photographed yard continues into an irregular rocky desert. Keep
	# the service entrances open and retain the authored playable perimeter.
	for side in range(4):
		for index in range(22):
			var along := -43.0 + float(index) * 4.1 + _rng.randf_range(-1.0,1.0)
			var distance := _rng.randf_range(33.0,47.0)
			if distance < 38.0 and absf(absf(along)-12.0) < 3.0:
				continue
			var at := _side_point(side,along,distance)
			_tuft(at,_rng.randf_range(1.05,1.75),22)
			for item in range(5):
				var pebble := at + Vector3(_rng.randf_range(-1.3,1.3),0,_rng.randf_range(-1.3,1.3))
				_rock(pebble,Vector3(_rng.randf_range(.12,.36),_rng.randf_range(.07,.23),_rng.randf_range(.12,.35)))
			if index % 4 == 0:
				_rock(at+Vector3(1.0,0,-.4),Vector3(_rng.randf_range(.7,1.3),_rng.randf_range(.55,1.1),_rng.randf_range(.65,1.1)))
		# A narrow fringe at the outside wall anchors the perimeter to the sand.
		for index in range(18):
			var along := -27.5 + float(index)*3.2
			if absf(absf(along)-12.0) < 2.4:
				continue
			_tuft(_side_point(side,along,30.8),_rng.randf_range(.28,.46),10)
	for body in scene.get_tree().get_nodes_in_group("arena_solid"):
		if not scene.is_ancestor_of(body) or body.get_meta("invisible_safety_limit",false):
			continue
		var collision := body.get_node_or_null("Collision") as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var size := (collision.shape as BoxShape3D).size
		_cover_wear(body.global_transform * collision.transform,size)
	# Replace only the old decorative round boulders with irregular facets.
	# Positions, branch visibility and scale are retained; no gameplay node moves.
	var exterior := scene.get_node_or_null("ArenaExterior")
	if exterior != null:
		for cluster in exterior.get_children():
			# Godot gives repeated runtime node names @-identifiers. Identify the
			# authored three-boulder composition, not just its first readable name.
			if not cluster.get_meta("decorative_exterior",false) or cluster.get_child_count() != 3:
				continue
			var rocks_only := true
			for child in cluster.get_children():
				if not child is MeshInstance3D or not child.mesh is SphereMesh:
					rocks_only = false
			if not rocks_only:
				continue
			for old in cluster.get_children():
				if old is MeshInstance3D and old.mesh is SphereMesh:
					var bounds: AABB = old.mesh.get_aabb()
					var base: Vector3 = old.global_position - Vector3.UP * bounds.size.y * old.scale.y * .5
					_rock(base,Vector3(bounds.size.x*old.scale.x*.5,bounds.size.y*old.scale.y,bounds.size.z*old.scale.z*.5))
					old.visible = false
	for key in _batches:
		var data: Dictionary = _batches[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.v
		arrays[Mesh.ARRAY_NORMAL] = data.n
		arrays[Mesh.ARRAY_COLOR] = data.c
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var instance := MeshInstance3D.new()
		instance.name = "Detail_" + key
		instance.mesh = mesh
		instance.visibility_range_end = 110.0
		instance.visibility_range_end_margin = 5.0
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("leaf",data.kind == "leaf")
		material.set_shader_parameter("stone",data.kind == "stone")
		if data.kind == "stone":
			material.set_shader_parameter("concrete_detail",preload("res://art/environment/courtyard_concrete_detail.png"))
		instance.material_override = material
		root.add_child(instance)
	root.set_meta("triangles",_triangles)
	root.set_meta("plants",_plants)
	root.set_meta("stones",_stones)
	root.set_meta("batches",_batches.size())
	parent.set_meta("detail_triangles",_triangles)
	parent.set_meta("detail_batches",_batches.size())

func _side_point(side: int, along: float, distance: float) -> Vector3:
	match side:
		0: return Vector3(along,-.055,-distance)
		1: return Vector3(distance,-.055,along)
		2: return Vector3(along,-.055,distance)
		_: return Vector3(-distance,-.055,along)

func _triangle(kind: String, a: Vector3, b: Vector3, c: Vector3, color: Color, ua := Vector2.ZERO, ub := Vector2.RIGHT, uc := Vector2.ONE) -> void:
	var cell := Vector2i(floori((a.x+64.0)/32.0),floori((a.z+64.0)/32.0))
	var key := "%s_%d_%d" % [kind,cell.x,cell.y]
	if not _batches.has(key):
		_batches[key] = {"v":PackedVector3Array(),"n":PackedVector3Array(),"c":PackedColorArray(),"uv":PackedVector2Array(),"kind":kind}
	var data: Dictionary = _batches[key]
	var normal := (b-a).cross(c-a).normalized()
	data.v.append_array(PackedVector3Array([a,c,b]))
	data.n.append_array(PackedVector3Array([normal,normal,normal]))
	var linear := color.srgb_to_linear()
	data.c.append_array(PackedColorArray([linear,linear,linear]))
	data.uv.append_array(PackedVector2Array([ua,uc,ub]))
	_triangles += 1

func _tuft(at: Vector3, scale_value: float, blades: int) -> void:
	_plants += 1
	for blade in range(blades):
		var angle := float(blade)*2.39996 + _rng.randf_range(-.15,.15)
		var direction := Vector3(cos(angle),0,sin(angle))
		var across := Vector3(-direction.z,0,direction.x)
		var height := scale_value * _rng.randf_range(.55,1.0)
		var reach := scale_value * _rng.randf_range(.30,.85)
		var width := scale_value * _rng.randf_range(.075,.14)
		var start := at + direction * _rng.randf_range(.01,.16) * scale_value
		var color := Color("#657643").lerp(Color("#9a9b58"),_rng.randf_range(0,.45))
		for segment in range(3):
			var t0 := float(segment)/3.0
			var t1 := float(segment+1)/3.0
			var p0 := start + direction*reach*pow(t0,.8) + Vector3.UP*height*sin(t0*PI*.5)
			var p1 := start + direction*reach*pow(t1,.8) + Vector3.UP*height*sin(t1*PI*.5)
			var w0 := width * sin((t0*.90+.1)*PI)
			var w1 := width * sin((t1*.90+.1)*PI)
			var n0 := p0 + Vector3.UP*w0*.34
			var n1 := p1 + Vector3.UP*w1*.34
			var tint := color.darkened((1.0-(t0+t1)*.5)*.42)
			_triangle("leaf",p0-across*w0,n0,n1,tint,Vector2(0,t0),Vector2(.5,t0),Vector2(.5,t1))
			_triangle("leaf",p0-across*w0,n1,p1-across*w1,tint,Vector2(0,t0),Vector2(.5,t1),Vector2(0,t1))
			_triangle("leaf",n0,p0+across*w0,p1+across*w1,tint.lightened(.08),Vector2(.5,t0),Vector2(1,t0),Vector2(1,t1))
			_triangle("leaf",n0,p1+across*w1,n1,tint.lightened(.08),Vector2(.5,t0),Vector2(1,t1),Vector2(.5,t1))

func _rock(at: Vector3, size: Vector3) -> void:
	_stones += 1
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	var rotation := _rng.randf_range(0,TAU)
	for index in range(7):
		var angle := rotation + float(index)*TAU/7
		var extent := _rng.randf_range(.80,1.13)
		lower.append(at+Vector3(cos(angle)*size.x*extent,size.y*.12,sin(angle)*size.z*extent))
		upper.append(at+Vector3(cos(angle+.08)*size.x*extent*.65,size.y*_rng.randf_range(.64,.91),sin(angle+.08)*size.z*extent*.65))
	var cap := at + Vector3(size.x*.12,size.y,size.z*-.16)
	var color := Color("#a28d71").lerp(Color("#6f6458"),_rng.randf_range(0,.7))
	for index in range(7):
		var next := (index+1)%7
		var tint := color.darkened(_rng.randf_range(0,.10))
		_triangle("stone",lower[index],upper[index],upper[next],tint)
		_triangle("stone",lower[index],upper[next],lower[next],tint)
		_triangle("stone",upper[index],cap,upper[next],tint.lightened(.04))

func _cover_wear(pose: Transform3D, size: Vector3) -> void:
	var half := size * .5
	# Chipped roof rims, plates and faded paint flecks use real irregular
	# silhouettes, avoiding a uniformly repeating painted scratch texture.
	for side in [-1.0,1.0]:
		for index in range(24):
			var x := _rng.randf_range(-half.x*.96,half.x*.96)
			var y := _rng.randf_range(-half.y*.88,half.y*.93)
			var z: float = side*(half.z+.006)
			var point := Vector3(x,y,z)
			_patch(pose,point,Vector3.RIGHT,Vector3.UP,Vector2(_rng.randf_range(.025,.11),_rng.randf_range(.012,.045)),Color("#656d6b"))
		for index in range(20):
			var x := _rng.randf_range(-half.x*.96,half.x*.96)
			var z: float = side*half.z*_rng.randf_range(.80,.97)
			_patch(pose,Vector3(x,half.y+.016,z),Vector3.RIGHT,Vector3.BACK,Vector2(_rng.randf_range(.018,.09),_rng.randf_range(.012,.047)),Color("#948875").darkened(_rng.randf_range(.12,.40)))
	# Small loose fragments lie against the base, below gameplay silhouettes.
	for index in range(13):
		var side := -1.0 if index%2 else 1.0
		var point := pose*Vector3(_rng.randf_range(-half.x,half.x),-half.y+.01,side*(half.z+_rng.randf_range(.07,.22)))
		_rock(point,Vector3(_rng.randf_range(.045,.12),_rng.randf_range(.025,.10),_rng.randf_range(.045,.11)))

func _patch(pose: Transform3D, centre: Vector3, x: Vector3, y: Vector3, extent: Vector2, color: Color) -> void:
	var points: Array[Vector3] = []
	for index in range(5):
		var angle := float(index)*TAU/5
		points.append(pose*(centre+x*cos(angle)*extent.x*_rng.randf_range(.6,1.1)+y*sin(angle)*extent.y*_rng.randf_range(.6,1.1)))
	for index in range(1,4):
		_triangle("wear",points[0],points[index],points[index+1],color)
