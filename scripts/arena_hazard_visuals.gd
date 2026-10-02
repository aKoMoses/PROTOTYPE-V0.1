extends Node3D

## Mechanical concept A, in real geometry. This presentation receives the
## controller's paused combat clock; it never changes damage or collision.
const STEEL_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")

var _kind := "tile"
var _phase := "idle"
var _return_time := 0.0
var _recoil_time := 0.0
var _flash_time := 0.0
var _opening := 0.0
var _extension := 0.0
var _shutters: Array[Node3D] = []
var _lamps: Array[StandardMaterial3D] = []
var _vents: StandardMaterial3D
var _electric_outer: ImmediateMesh
var _electric_core: ImmediateMesh
var _electric_root: Node3D
var _barrel: Node3D
var _hatch: Node3D
var _flash: MeshInstance3D
var _muzzle: Marker3D
var _lane: MeshInstance3D
var _lane_mesh: ImmediateMesh
var _lane_length := -1.0
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _smoke_texture: ImageTexture


func configure(kind: String, direction: Vector3) -> void:
	_kind = kind
	if kind == "tile":
		_build_tile()
	else:
		rotation.y = atan2(direction.x, direction.z)
		_build_cannon()
	_batch_static()
	reset_visual()


func reset_visual() -> void:
	_phase = "idle"
	_return_time = 0.0
	_recoil_time = 0.0
	_flash_time = 0.0
	_opening = 0.0
	_extension = 0.0
	if _smoke != null:
		_smoke.emitting = false
	if _sparks != null:
		_sparks.emitting = false
	update_visual("idle", 0.0, 0.0, 0.0, 54.0)


func update_visual(phase: String, progress: float, delta: float, clock: float, lane_length: float) -> void:
	if _phase == "active" and phase == "idle":
		_return_time = 0.55
		_smoke.restart()
		_smoke.emitting = true
	_phase = phase
	_return_time = maxf(0.0, _return_time - delta)
	_recoil_time = maxf(0.0, _recoil_time - delta)
	_flash_time = maxf(0.0, _flash_time - delta)
	var returning := _return_time / 0.55
	var charged := smoothstep(0.0, 0.75, progress) if phase == "warning" else (1.0 if phase == "active" else returning)
	if _kind == "tile":
		_opening = charged
		for index in range(_shutters.size()):
			var shutter := _shutters[index]
			shutter.rotation.z = (0.55 if index % 2 == 0 else -0.55) * charged
			shutter.position.y = 0.065 + charged * 0.10
		_vents.emission_energy_multiplier = 0.35 * charged
		for index in range(_lamps.size()):
			var lamp := _lamps[index]
			var lit := progress >= float(index % 4) / 4.0
			var color := Color("#82dcff") if phase == "active" else Color("#f09a37")
			var strength := 1.0 if phase == "active" else (0.55 + 0.45 * absf(sin(clock * 7.0)) if phase == "warning" and lit else 0.18)
			lamp.albedo_color = color * strength
			lamp.emission = color
			lamp.emission_energy_multiplier = 0.5 if phase == "active" else (0.18 + 0.35 * absf(sin(clock * 7.0)) if phase == "warning" and lit else 0.015)
		_electric_root.visible = phase == "active"
		if phase == "active":
			_draw_electricity(clock)
	else:
		_extension = charged
		var kick := sin((_recoil_time / 0.18) * PI * 0.5)
		_barrel.position.z = -0.52 + charged * 0.86 - kick * 0.16
		_hatch.rotation.x = -sin(returning * PI) * 0.48
		_flash.visible = _flash_time > 0.0
		_flash.scale = Vector3(0.7, 0.7, 1.7) * (0.55 + _flash_time / 0.07 * 0.45)
		for lamp in _lamps:
			lamp.albedo_color = Color("#eaa047") * (0.55 + 0.45 * absf(sin(clock * 7.0)) if phase == "warning" else (0.8 if phase == "active" else 0.18))
			lamp.emission_energy_multiplier = 0.5 if phase == "warning" else (0.22 if phase == "active" else 0.025)
		_lane.visible = phase == "warning" or phase == "active"
		if not is_equal_approx(lane_length, _lane_length):
			_draw_lane(lane_length)


func kick() -> void:
	if _kind != "cannon":
		return
	_recoil_time = 0.18
	_flash_time = 0.07
	_sparks.restart()
	_sparks.emitting = true


func get_muzzle_world() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position


func get_presentation() -> Dictionary:
	return {"phase": _phase, "opening": _opening, "extension": _extension,
		"recoil": _recoil_time, "returning": _return_time, "flash": _flash_time}


func _build_tile() -> void:
	var steel := _metal("steel", Color("#59636d"))
	var dark := _metal("dark", Color("#292f34"))
	var rim := _metal("rim", Color("#796653"), STEEL_TEXTURE)
	var bronze := _metal("bronze", Color("#776d5e"))
	_part(self, _bevel_mesh(Vector3(3.18, 0.08, 3.18), 0.10), Vector3(0, 0.015, 0), dark)
	for sign_value in [-1.0, 1.0]:
		_part(self, _bevel_mesh(Vector3(3.18, 0.065, 0.17), 0.035), Vector3(0, 0.065, 1.49 * sign_value), rim)
		_part(self, _bevel_mesh(Vector3(0.17, 0.065, 2.85), 0.035), Vector3(1.49 * sign_value, 0.065, 0), rim)
		_part(self, _bevel_mesh(Vector3(2.58, 0.025, 0.035), 0.008), Vector3(0, 0.10, 1.37 * sign_value), bronze)
		_part(self, _bevel_mesh(Vector3(0.035, 0.025, 2.58), 0.008), Vector3(1.37 * sign_value, 0.10, 0), bronze)
	_vents = _glow(Color("#b96920"), 0.0)
	for index in range(4):
		var x := -0.975 + float(index) * 0.65
		_part(self, _box_mesh(Vector3(0.055, 0.014, 2.5)), Vector3(x, 0.065, 0), _vents)
		var pivot := Node3D.new()
		pivot.name = "Louver%d" % index
		pivot.position = Vector3(x, 0.065, 0)
		add_child(pivot)
		_shutters.append(pivot)
		_part(pivot, _bevel_mesh(Vector3(0.58, 0.075, 2.53), 0.025), Vector3.ZERO, steel)
		_part(pivot, _box_mesh(Vector3(0.035, 0.012, 2.31)), Vector3(-0.21, 0.044, 0), bronze)
		for z in [-0.88, -0.25, 0.43, 0.91]:
			var scratch := _part(pivot, _box_mesh(Vector3(0.09, 0.003, 0.009)), Vector3(0.04, 0.039, z), bronze)
			scratch.rotation.y = 0.32 if z > 0 else -0.21
	for x in [-1.30, 1.30]:
		for z in [-1.30, 1.30]:
			_part(self, _bevel_mesh(Vector3(0.32, 0.085, 0.32), 0.04), Vector3(x, 0.105, z), dark)
			_part(self, _cylinder_mesh(0.11, 0.055, 12), Vector3(x, 0.165, z), bronze)
			var lamp := _glow(Color("#e0a05a"), 0.02)
			_lamps.append(lamp)
			_part(self, _box_mesh(Vector3(0.115, 0.016, 0.115)), Vector3(x, 0.2, z), lamp)
	for edge in [-1.47, 1.47]:
		for index in range(4):
			_part(self, _box_mesh(Vector3(0.28, 0.016, 0.055)), Vector3(-0.84 + float(index) * 0.56, 0.101, edge), _lamps[index])
	for x in [-1.48, 1.48]:
		for z in [-1.48, -0.55, 0.55, 1.48]:
			_part(self, _cylinder_mesh(0.035, 0.021, 6), Vector3(x, 0.106, z), steel)
	_electric_root = Node3D.new()
	_electric_root.name = "ElectricalDischarge"
	add_child(_electric_root)
	_electric_outer = ImmediateMesh.new()
	_electric_core = ImmediateMesh.new()
	_part(_electric_root, _electric_outer, Vector3.ZERO, _glow(Color("#468dff"), 0.45), true)
	_part(_electric_root, _electric_core, Vector3.ZERO, _glow(Color("#d9f5ff"), 0.4), true)
	_smoke = _smoke_emitter(Vector3(0, 0.18, 0), Vector3(1.0, 0.0, 0.45))


func _build_cannon() -> void:
	var steel := _metal("steel", Color("#59636d"))
	var dark := _metal("dark", Color("#2b3033"))
	var rust := _metal("rust", Color("#b9a291"), RUST_TEXTURE)
	var bronze := _metal("bronze", Color("#8d8270"))
	_part(self, _bevel_mesh(Vector3(1.8, 1.5, 0.30), 0.10), Vector3(0, 0.14, -0.80), dark)
	_part(self, _bevel_mesh(Vector3(1.58, 1.31, 0.16), 0.07), Vector3(0, 0.14, -0.57), rust)
	_part(self, _bevel_mesh(Vector3(1.15, 0.83, 0.72), 0.08), Vector3(0, -0.06, -0.39), dark)
	for x in [-0.69, 0.69]:
		_part(self, _bevel_mesh(Vector3(0.18, 1.3, 0.45), 0.025), Vector3(x, 0.12, -0.45), steel)
		for y in [-0.43, 0.08, 0.68]:
			var bolt := _part(self, _cylinder_mesh(0.055, 0.035, 6), Vector3(x, y, -0.20), bronze)
			bolt.rotation.x = PI * 0.5
	for x in [-0.44, 0.44]:
		var piston := _part(self, _cylinder_mesh(0.075, 0.55, 12), Vector3(x, -0.07, -0.2), bronze)
		piston.rotation.x = PI * 0.5
		var sleeve := _part(self, _cylinder_mesh(0.105, 0.24, 12), Vector3(x, -0.07, -0.40), steel)
		sleeve.rotation.x = PI * 0.5
	_part(self, _bevel_mesh(Vector3(1.45, 0.23, 0.12), 0.035), Vector3(0, 0.68, -0.34), dark)
	var lamp := _glow(Color("#eaa047"), 0.02)
	_lamps.append(lamp)
	_part(self, _box_mesh(Vector3(1.11, 0.085, 0.015)), Vector3(0, 0.68, -0.272), lamp, true)
	_barrel = Node3D.new()
	_barrel.name = "RetractableBarrel"
	add_child(_barrel)
	_part(_barrel, _bevel_mesh(Vector3(0.69, 0.59, 0.48), 0.06), Vector3(0, -0.06, -0.09), steel)
	for z in [0.12, 0.62]:
		var collar := _part(_barrel, _cylinder_mesh(0.27, 0.14, 12), Vector3(0, -0.06, z), bronze)
		collar.rotation.x = PI * 0.5
	var tube := _part(_barrel, _cylinder_mesh(0.235, 0.78, 16), Vector3(0, -0.06, 0.26), steel)
	tube.rotation.x = PI * 0.5
	var bore := _part(_barrel, _cylinder_mesh(0.19, 0.012, 16), Vector3(0, -0.06, 0.701), dark)
	bore.rotation.x = PI * 0.5
	for z in [0.24, 0.37, 0.50]:
		_part(_barrel, _box_mesh(Vector3(0.10, 0.013, 0.065)), Vector3(0, 0.18, z), dark)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0, -0.06, 0.74)
	_barrel.add_child(_muzzle)
	_hatch = Node3D.new()
	_hatch.name = "CoolingHatch"
	_hatch.position = Vector3(0, 0.87, -0.88)
	add_child(_hatch)
	_part(_hatch, _bevel_mesh(Vector3(1.70, 0.09, 0.87), 0.06), Vector3(0, 0, 0.4), steel)
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.21
	flash_mesh.height = 0.42
	_flash = _part(_muzzle, flash_mesh, Vector3(0, 0, 0.17), _glow(Color("#ffce7a"), 0.8), true)
	_flash.scale = Vector3(0.7, 0.7, 1.7)
	_lane_mesh = ImmediateMesh.new()
	_lane = _part(self, _lane_mesh, Vector3(0, -0.79, 0), _glow(Color("#eaaa43"), 0.22), true)
	_lane.name = "WarningChevrons"
	_smoke = _smoke_emitter(Vector3(0, 0.91, -0.35), Vector3(0.40, 0, 0.10))
	_sparks = CPUParticles3D.new()
	_sparks.amount = 5
	_sparks.lifetime = 0.18
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.direction = Vector3(0, 0.4, 1)
	_sparks.spread = 25.0
	_sparks.gravity = Vector3(0, -6, 0)
	_sparks.initial_velocity_min = 1.4
	_sparks.initial_velocity_max = 2.4
	_sparks.scale_amount_min = 0.025
	_sparks.scale_amount_max = 0.04
	var spark := SphereMesh.new()
	spark.radius = 0.5
	spark.height = 1.0
	spark.material = _glow(Color("#ffd08c"), 0.4)
	_sparks.mesh = spark
	_muzzle.add_child(_sparks)


func _draw_electricity(clock: float) -> void:
	_electric_outer.clear_surfaces()
	_electric_core.clear_surfaces()
	_electric_outer.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_electric_core.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(-1.3, 0.24, -1.3), Vector3(1.3, 0.24, -1.3), Vector3(1.3, 0.24, 1.3), Vector3(-1.3, 0.24, 1.3)]
	for arc in range(4):
		var start: Vector3 = corners[arc]
		var end: Vector3 = corners[(arc + 1) % 4] if arc < 3 else corners[1]
		var previous := start
		for segment in range(1, 18):
			var t := float(segment) / 17.0
			var next := start.lerp(end, t)
			var wave := sin(t * PI)
			next += Vector3(sin(clock * 43 + segment * 19 + arc) * 0.15, 0.17 + absf(sin(clock * 29 + segment * 7)) * 0.23, cos(clock * 37 + segment * 13 + arc) * 0.15) * wave
			_ribbon(_electric_outer, previous, next, 0.075)
			_ribbon(_electric_core, previous, next, 0.025)
			if segment % 5 == 0:
				var side := (end - start).cross(Vector3.UP).normalized()
				var tip := next + side * sin(clock * 41 + segment + arc) * 0.34 + Vector3.UP * 0.23
				var middle := next.lerp(tip, 0.5) + Vector3(sin(clock * 37 + segment) * 0.09, 0.04, 0)
				_ribbon(_electric_outer, next, middle, 0.035)
				_ribbon(_electric_outer, middle, tip, 0.022)
				_ribbon(_electric_core, next, middle, 0.012)
				_ribbon(_electric_core, middle, tip, 0.007)
			previous = next
	_electric_outer.surface_end()
	_electric_core.surface_end()


func _ribbon(mesh: ImmediateMesh, start: Vector3, end: Vector3, width: float) -> void:
	var side := (end - start).cross(Vector3.UP).normalized() * width * 0.5
	for point in [start - side, start + side, end + side, start - side, end + side, end - side]:
		mesh.surface_add_vertex(point)


func _draw_lane(length: float) -> void:
	_lane_length = length
	_lane_mesh.clear_surfaces()
	if length <= 1.2:
		return
	_lane_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(maxi(1, int(length / 2.4))):
		var at := 0.8 + float(index) * 2.4
		if at + 0.4 >= length:
			break
		var shape := [Vector3(-0.23, 0, at), Vector3(0, 0, at + 0.28), Vector3(0.23, 0, at), Vector3(0.23, 0, at - 0.11), Vector3(0, 0, at + 0.13), Vector3(-0.23, 0, at - 0.11)]
		for triangle in [[0, 1, 4], [0, 4, 5], [1, 2, 3], [1, 3, 4]]:
			for vertex in triangle:
				_lane_mesh.surface_add_vertex(shape[vertex])
	_lane_mesh.surface_end()


func _smoke_emitter(at: Vector3, extents: Vector3) -> CPUParticles3D:
	if _smoke_texture == null:
		var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in range(32):
			for x in range(32):
				var r := Vector2(float(x) - 15.5, float(y) - 15.5).length() / 15.5
				image.set_pixel(x, y, Color(0.65, 0.69, 0.71, pow(maxf(0, 1.0 - r), 2.0)))
		_smoke_texture = ImageTexture.create_from_image(image)
	var particles := CPUParticles3D.new()
	particles.position = at
	particles.amount = 5
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.emitting = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3.UP
	particles.spread = 15.0
	particles.gravity = Vector3(0, 0.25, 0)
	particles.initial_velocity_min = 0.35
	particles.initial_velocity_max = 0.65
	particles.scale_amount_min = 0.25
	particles.scale_amount_max = 0.48
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.28))
	gradient.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = gradient
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.albedo_texture = _smoke_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	quad.material = material
	particles.mesh = quad
	add_child(particles)
	return particles


func _metal(key: String, color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture
	material.roughness = 0.58
	material.metallic = 0.45
	_materials[key] = material
	return material


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _part(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, dynamic: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	node.set_meta("batchable", not dynamic)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _batch_static() -> void:
	var buckets: Dictionary = {}
	for child in get_children():
		if child is MeshInstance3D and bool(child.get_meta("batchable", false)):
			var key := (child.material_override as Material).get_instance_id()
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(child)
	for bucket in buckets.values():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var material: Material = bucket[0].material_override
		for child in bucket:
			surface.append_from(child.mesh, 0, child.transform)
			remove_child(child)
			child.free()
		_part(self, surface.commit(), Vector3.ZERO, material, true)


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder_mesh(radius: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	return mesh


func _bevel_mesh(size: Vector3, bevel: float) -> ArrayMesh:
	var key := str(size) + ":" + str(bevel)
	if _meshes.has(key):
		return _meshes[key]
	var x := size.x * 0.5
	var z := size.z * 0.5
	var y := size.y * 0.5
	var b := minf(bevel, minf(x, z) * 0.5)
	var lip := minf(b, y * 0.48)
	var rim := [Vector2(-x + b, -z), Vector2(x - b, -z), Vector2(x, -z + b), Vector2(x, z - b), Vector2(x - b, z), Vector2(-x + b, z), Vector2(-x, z - b), Vector2(-x, -z + b)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(8):
		var next := (index + 1) % 8
		var a := Vector3(rim[index].x - signf(rim[index].x) * lip, y, rim[index].y - signf(rim[index].y) * lip)
		var c := Vector3(rim[next].x - signf(rim[next].x) * lip, y, rim[next].y - signf(rim[next].y) * lip)
		_triangle(surface, Vector3(0, y, 0), c, a, Vector3.UP, size)
		var edge_a := Vector3(rim[index].x, y - lip, rim[index].y)
		var edge_c := Vector3(rim[next].x, y - lip, rim[next].y)
		var normal := Vector3(rim[next].y - rim[index].y, 0, rim[index].x - rim[next].x).normalized()
		var slope := (normal + Vector3.UP).normalized()
		_triangle(surface, a, c, edge_c, slope, size)
		_triangle(surface, a, edge_c, edge_a, slope, size)
		var low_a := Vector3(edge_a.x, -y + lip, edge_a.z)
		var low_c := Vector3(edge_c.x, -y + lip, edge_c.z)
		_triangle(surface, edge_a, edge_c, low_c, normal, size)
		_triangle(surface, edge_a, low_c, low_a, normal, size)
		var bottom_a := Vector3(a.x, -y, a.z)
		var bottom_c := Vector3(c.x, -y, c.z)
		slope = (normal + Vector3.DOWN).normalized()
		_triangle(surface, low_a, low_c, bottom_c, slope, size)
		_triangle(surface, low_a, bottom_c, bottom_a, slope, size)
		_triangle(surface, Vector3(0, -y, 0), bottom_a, bottom_c, Vector3.DOWN, size)
	var mesh := surface.commit()
	_meshes[key] = mesh
	return mesh

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, size: Vector3) -> void:
	# Godot renders clockwise front faces.
	for vertex in [a, c, b]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(vertex.x / size.x + 0.5, vertex.z / size.z + 0.5))
		surface.add_vertex(vertex)
