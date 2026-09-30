extends SceneTree
## Offline mesh authoring tool. Run with --headless --script; never used at
## game startup. Placements stay in salvage_yard.tscn and all geometry is baked.

const OUTPUT := "res://art/environment/yard/"
const MATERIAL_NAMES := ["paint", "rust", "steel", "rubber", "ivory", "energy"]
var _surfaces: Dictionary = {}
var _materials: Array[Material] = []


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	_make_materials()
	_reset()
	_crane()
	_save_mesh("north_hoist")
	_reset()
	_crawler()
	_save_mesh("crawler_wreck")
	_reset()
	_canopy_frame()
	_save_mesh("service_canopy_frame")
	_reset()
	_power_unit()
	_save_mesh("power_unit")
	_reset()
	_fan()
	_save_mesh("fan_rotor")
	_cloth("hanging_banner", 4.4, 1.28, false)
	_cloth("service_canopy", 3.5, 6.1, true)
	print("YARD ASSETS: four static compositions and reusable cloth/rotor baked.")
	quit()


func _make_materials() -> void:
	var palette := [Color("#bba887"), Color("#a75f38"), Color("#403b32"), Color("#292d29"), Color("#e7d1a7"), Color("#376668")]
	var shared_paths := {0: "paint_cream", 1: "joint_rust", 2: "steel_frame", 4: "paint_ivory"}
	for index in palette.size():
		if shared_paths.has(index):
			_materials.append(load("res://art/environment/families/" + str(shared_paths[index]) + ".tres"))
			continue
		var material := StandardMaterial3D.new()
		material.resource_name = "Yard_" + MATERIAL_NAMES[index]
		material.albedo_color = palette[index]
		material.roughness = 0.93 if index != 2 else 0.80
		material.metallic = 0.12 if index in [0, 2, 4] else 0.0
		if index == 5:
			material.emission_enabled = true
			material.emission = Color("#246368")
			material.emission_energy_multiplier = 0.48
			material.roughness = 0.45
		var material_path: String = OUTPUT + str(MATERIAL_NAMES[index]) + ".tres"
		var error := ResourceSaver.save(material, material_path, ResourceSaver.FLAG_CHANGE_PATH)
		assert(error == OK)
		material.take_over_path(material_path)
		_materials.append(material)


func _reset() -> void:
	_surfaces.clear()
	for index in MATERIAL_NAMES.size():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(_materials[index])
		_surfaces[index] = {"tool": surface, "count": 0}


func _triangle(material: int, a: Vector3, b: Vector3, c: Vector3, ua: Vector2 = Vector2.ZERO, ub: Vector2 = Vector2.RIGHT, uc: Vector2 = Vector2.ONE) -> void:
	var surface: SurfaceTool = _surfaces[material]["tool"]
	var normal := (b - a).cross(c - a).normalized()
	# Godot front faces use clockwise winding. Authored input is outward CCW.
	for item in [[a, ua], [c, uc], [b, ub]]:
		surface.set_normal(normal)
		surface.set_uv(item[1])
		surface.add_vertex(item[0])
	_surfaces[material]["count"] += 3


func _quad(material: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_scale: Vector2 = Vector2.ONE) -> void:
	_triangle(material, a, b, c, Vector2.ZERO, Vector2(uv_scale.x, 0), uv_scale)
	_triangle(material, a, c, d, Vector2.ZERO, uv_scale, Vector2(0, uv_scale.y))


func _box(material: int, center: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO, bevel: float = 0.0) -> void:
	var basis := Basis.from_euler(rotation * PI / 180.0)
	var h := size * 0.5
	var edge := minf(bevel, minf(h.x, h.z) * 0.8)
	var footprint := [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)] if edge <= 0.001 else [Vector2(-h.x + edge, -h.z), Vector2(h.x - edge, -h.z), Vector2(h.x, -h.z + edge), Vector2(h.x, h.z - edge), Vector2(h.x - edge, h.z), Vector2(-h.x + edge, h.z), Vector2(-h.x, h.z - edge), Vector2(-h.x, -h.z + edge)]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for p in footprint:
		top.append(center + basis * Vector3(p.x, h.y, p.y))
		bottom.append(center + basis * Vector3(p.x, -h.y, p.y))
	for index in footprint.size():
		var next := (index + 1) % footprint.size()
		_quad(material, bottom[index], top[index], top[next], bottom[next], Vector2(size.y * 0.28, size.x * 0.20))
		_triangle(material, center + basis * Vector3(0, h.y, 0), top[next], top[index])
		_triangle(material, center + basis * Vector3(0, -h.y, 0), bottom[index], bottom[next])


func _beam(material: int, a: Vector3, b: Vector3, width: float, depth: float = -1.0) -> void:
	var direction := (b - a).normalized()
	var reference := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.96 else Vector3.UP
	var right := direction.cross(reference).normalized()
	var forward := right.cross(direction).normalized()
	var h_width := width * 0.5
	var h_depth := (width if depth < 0.0 else depth) * 0.5
	var corners: Array[Vector3] = []
	for point in [a, b]:
		for offset in [right * -h_width + forward * -h_depth, right * h_width + forward * -h_depth, right * h_width + forward * h_depth, right * -h_width + forward * h_depth]:
			corners.append(point + offset)
	_quad(material, corners[0], corners[1], corners[2], corners[3])
	_quad(material, corners[4], corners[7], corners[6], corners[5])
	for index in 4:
		var next := (index + 1) % 4
		_quad(material, corners[index], corners[index + 4], corners[next + 4], corners[next])


func _cylinder(material: int, center: Vector3, radius: float, height: float, rotation: Vector3 = Vector3.ZERO, segments: int = 10, top_radius: float = -1.0) -> void:
	var basis := Basis.from_euler(rotation * PI / 180.0)
	var r_top := radius if top_radius < 0 else top_radius
	for index in segments:
		var angle := float(index) * TAU / segments
		var next_angle := float(index + 1) * TAU / segments
		var a := Vector3(cos(angle) * radius, -height * 0.5, sin(angle) * radius)
		var b := Vector3(cos(next_angle) * radius, -height * 0.5, sin(next_angle) * radius)
		var c := Vector3(cos(next_angle) * r_top, height * 0.5, sin(next_angle) * r_top)
		var d := Vector3(cos(angle) * r_top, height * 0.5, sin(angle) * r_top)
		_quad(material, center + basis * a, center + basis * d, center + basis * c, center + basis * b)
		_triangle(material, center + basis * Vector3(0, height * 0.5, 0), center + basis * c, center + basis * d)
		_triangle(material, center + basis * Vector3(0, -height * 0.5, 0), center + basis * a, center + basis * b)


func _ring(material: int, center: Vector3, radius: float, thickness: float, rotation: Vector3 = Vector3.ZERO, segments: int = 12) -> void:
	var basis := Basis.from_euler(rotation * PI / 180.0)
	for index in segments:
		var angle := float(index) * TAU / segments
		var next := float(index + 1) * TAU / segments
		var a := center + basis * Vector3(cos(angle) * radius, sin(angle) * radius, 0)
		var b := center + basis * Vector3(cos(next) * radius, sin(next) * radius, 0)
		_beam(material, a, b, thickness)


func _bolt(center: Vector3, radius: float = 0.075) -> void:
	_cylinder(2, center, radius, 0.055, Vector3(90, 0, 0), 6)


func _plate_wear(center: Vector3, size: Vector3, rotation: Vector3) -> void:
	# A handful of deliberate paint chips at edges. These are opaque baked
	# patches, offset 8mm from the armour, rather than all-over texture noise.
	var basis := Basis.from_euler(rotation * PI / 180.0)
	for item in [[Vector3(-0.36, 0, -0.35), Vector3(0.18, 0.013, 0.38)], [Vector3(0.32, 0, 0.37), Vector3(0.25, 0.013, 0.17)], [Vector3(0.38, 0, -0.33), Vector3(0.12, 0.013, 0.25)]]:
		var offset: Vector3 = item[0]
		offset.x *= size.x
		offset.z *= size.z
		offset.y = size.y * 0.5 + 0.008
		_box(1, center + basis * offset, item[1], rotation, 0.025)


func _crane() -> void:
	for x in [-4.8, 4.8]:
		_box(2, Vector3(x, 0.12, 0), Vector3(1.65, 0.24, 2.5), Vector3.ZERO, 0.14)
		_box(1, Vector3(x, 0.43, 0), Vector3(1.14, 0.62, 1.24), Vector3.ZERO, 0.08)
		_box(2, Vector3(x, 2.55, 0), Vector3(0.32, 4.5, 0.65))
		_box(0, Vector3(x, 2.90, 0.36), Vector3(0.66, 2.45, 0.12), Vector3.ZERO, 0.08)
		for y in [1.74, 3.95]:
			_bolt(Vector3(x - 0.20, y, 0.46))
			_bolt(Vector3(x + 0.20, y, 0.46))
		for z in [-0.92, 0.92]:
			_beam(2, Vector3(x, 1.64, 0), Vector3(x, 0.30, z), 0.16)
		_box(4, Vector3(x, 0.49, 0.68), Vector3(0.88, 0.16, 0.08))
	_box(1, Vector3(0, 4.48, 0), Vector3(11.65, 0.58, 0.72), Vector3.ZERO, 0.1)
	_box(2, Vector3(0, 4.82, 0), Vector3(11.90, 0.12, 0.98))
	_box(2, Vector3(0, 4.15, 0), Vector3(11.90, 0.10, 0.96))
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		_beam(2, Vector3(x - 0.52, 4.28, 0.40), Vector3(x + 0.25, 4.65, 0.40), 0.065)
	_box(0, Vector3(2.15, 4.10, 0), Vector3(1.24, 0.65, 1.0), Vector3.ZERO, 0.12)
	_cylinder(2, Vector3(2.15, 3.98, 0.57), 0.26, 0.11, Vector3(90, 0, 0), 10)
	_beam(2, Vector3(2.15, 3.84, 0.12), Vector3(2.15, 2.17, 0.12), 0.028)
	_box(1, Vector3(2.15, 2.11, 0.12), Vector3(0.42, 0.43, 0.34), Vector3.ZERO, 0.10)
	_ring(2, Vector3(2.15, 1.80, 0.12), 0.20, 0.07)
	# Visible slings connect the suspended salvage motor to the hoist hook.
	_beam(2, Vector3(2.15, 1.69, 0.12), Vector3(1.37, 1.44, 0.12), 0.045)
	_beam(2, Vector3(2.15, 1.69, 0.12), Vector3(2.91, 1.44, 0.12), 0.045)
	_box(0, Vector3(2.15, 1.14, 0.12), Vector3(1.84, 0.63, 1.00), Vector3(0, 0, -5), 0.13)
	for x in [1.52, 1.84, 2.16, 2.48, 2.80]:
		_box(2, Vector3(x, 1.25, 0.72), Vector3(0.10, 0.48, 0.15))
	_cylinder(1, Vector3(3.20, 1.14, 0.12), 0.22, 0.34, Vector3(0, 0, 90), 8)
	# Fixed banner header and hanging canvas rings.
	_beam(2, Vector3(-3.80, 4.21, 0.61), Vector3(0.60, 4.21, 0.61), 0.07)
	for x in [-3.78, 0.58]:
		_ring(4, Vector3(x, 4.16, 0.61), 0.055, 0.035, Vector3.ZERO, 8)
	# Organized stack: broad plates rather than a cloud of little scrap.
	for index in 3:
		_box(1 if index == 1 else 2, Vector3(-1.8, 0.08 + index * 0.16, -1.48), Vector3(3.4 - index * 0.18, 0.16, 1.6), Vector3(0, index * 4.0, 0), 0.07)


func _crawler() -> void:
	_box(2, Vector3(0, 0.48, 0), Vector3(6.5, 0.5, 3.45), Vector3.ZERO, 0.18)
	for z in [-1.43, 1.43]:
		_box(3, Vector3(0, 0.55, z), Vector3(6.8, 1.10, 0.76), Vector3.ZERO, 0.31)
		for x in [-2.50, -1.25, 0, 1.25, 2.50]:
			_cylinder(2, Vector3(x, 0.57, z + signf(z) * 0.38), 0.43, 0.09, Vector3(90, 0, 0), 10)
			_cylinder(1, Vector3(x, 0.57, z + signf(z) * 0.44), 0.16, 0.09, Vector3(90, 0, 0), 8)
		for index in 13:
			var x := -3.05 + index * 0.50
			_box(2, Vector3(x, 1.04, z), Vector3(0.19, 0.13, 0.90))
	_box(0, Vector3(-0.35, 1.48, 0), Vector3(5.40, 1.35, 2.55), Vector3.ZERO, 0.22)
	_box(4, Vector3(-1.2, 2.05, 0), Vector3(2.65, 0.18, 2.7), Vector3(0, 0, -8), 0.12)
	_plate_wear(Vector3(-1.2, 2.05, 0), Vector3(2.65, 0.18, 2.7), Vector3(0, 0, -8))
	_box(1, Vector3(2.0, 1.63, 0), Vector3(1.40, 0.19, 2.6), Vector3(0, 0, -30), 0.12)
	_box(2, Vector3(-1.70, 2.42, 0), Vector3(1.66, 1.13, 1.95), Vector3.ZERO, 0.18)
	_box(0, Vector3(-1.70, 3.02, 0), Vector3(1.95, 0.15, 2.2), Vector3(0, 0, -7), 0.10)
	_plate_wear(Vector3(-1.70, 3.02, 0), Vector3(1.95, 0.15, 2.2), Vector3(0, 0, -7))
	for z in [-1.01, 1.01]:
		_box(4, Vector3(-1.70, 2.49, z), Vector3(1.54, 0.87, 0.11), Vector3.ZERO, 0.08)
		_box(3, Vector3(-1.70, 2.57, z + signf(z) * 0.07), Vector3(1.12, 0.49, 0.04), Vector3.ZERO, 0.08)
		_box(2, Vector3(-1.70, 2.57, z + signf(z) * 0.11), Vector3(0.07, 0.51, 0.035))
	for x in [-2.5, -0.85, 0.85]:
		_box(1, Vector3(x, 1.08, 1.34), Vector3(1.48, 0.10, 0.05))
		for offset in [-0.53, 0.53]:
			_bolt(Vector3(x + offset, 1.81, 1.36))
	# Broken engine bay: regular radiator ribs framed by two broad armour skins.
	_box(2, Vector3(1.30, 2.07, 0), Vector3(1.6, 0.21, 2.02))
	for index in 7:
		_box(1, Vector3(0.72 + index * 0.20, 2.27, 0), Vector3(0.08, 0.43, 1.62))
	_cylinder(1, Vector3(-2.40, 2.30, -1.29), 0.10, 1.38, Vector3.ZERO, 8)
	_cylinder(2, Vector3(-2.40, 3.01, -1.29), 0.17, 0.12, Vector3.ZERO, 8)
	# Detached hood grounded beside the wreck; no levitating thin plates.
	_box(0, Vector3(3.57, 0.35, 0.1), Vector3(1.48, 0.12, 2.37), Vector3(0, -12, -23), 0.13)
	_plate_wear(Vector3(3.57, 0.35, 0.1), Vector3(1.48, 0.12, 2.37), Vector3(0, -12, -23))
	_box(1, Vector3(2.85, 0.15, -2.41), Vector3(1.8, 0.30, 0.75), Vector3(0, 9, 0), 0.08)


func _canopy_frame() -> void:
	for x in [-1.75, 1.75]:
		for z in [-3.05, 3.05]:
			_box(2, Vector3(x, 0.09, z), Vector3(0.63, 0.18, 0.63), Vector3.ZERO, 0.08)
			_cylinder(2, Vector3(x, 1.62, z), 0.08, 3.15, Vector3.ZERO, 8)
			_beam(2, Vector3(x, 2.45, z), Vector3(x, 3.11, z - signf(z) * 0.70), 0.06)
	for x in [-1.75, 1.75]:
		_beam(2, Vector3(x, 3.17, -3.05), Vector3(x, 3.17, 3.05), 0.065)
	for z in [-3.05, 3.05]:
		_beam(2, Vector3(-1.75, 3.17, z), Vector3(1.75, 3.17, z), 0.065)
	# A working repair bench, supported shelves and grounded generator housing.
	for x in [-1.32, 1.32]:
		_box(2, Vector3(x, 0.50, -1.52), Vector3(0.18, 1.0, 1.4))
	_box(0, Vector3(0, 1.05, -1.52), Vector3(2.96, 0.18, 1.65), Vector3.ZERO, 0.08)
	_box(1, Vector3(0, 0.43, -1.52), Vector3(2.75, 0.12, 1.48))
	_box(2, Vector3(0.80, 1.24, -1.67), Vector3(0.74, 0.23, 0.66), Vector3.ZERO, 0.1)
	_cylinder(1, Vector3(-0.67, 1.25, -1.49), 0.25, 0.38, Vector3(0, 0, 90), 8)
	_box(1, Vector3(0.46, 0.55, 1.22), Vector3(1.70, 1.1, 1.7), Vector3.ZERO, 0.16)
	_box(4, Vector3(0.46, 1.12, 1.22), Vector3(1.78, 0.13, 1.77), Vector3.ZERO, 0.12)
	_box(2, Vector3(0.46, 0.63, 2.12), Vector3(1.33, 0.75, 0.06))
	for x in [-0.02, 0.22, 0.46, 0.7, 0.94]:
		_box(1, Vector3(x, 0.63, 2.17), Vector3(0.08, 0.65, 0.08))
	_cylinder(0, Vector3(-1.18, 0.82, 0.77), 0.29, 1.54, Vector3.ZERO, 10, 0.23)
	_cylinder(2, Vector3(-1.18, 1.69, 0.77), 0.10, 0.17, Vector3.ZERO, 8)
	_beam(2, Vector3(-1.18, 1.72, 0.77), Vector3(-0.84, 1.72, 0.77), 0.055)
	# Upper side screen gives a broad ivory shape beneath the red awning.
	_box(0, Vector3(-1.68, 2.12, -1.26), Vector3(0.10, 0.84, 2.55), Vector3.ZERO, 0.04)
	_box(1, Vector3(-1.63, 1.86, -1.26), Vector3(0.13, 0.10, 2.51))
	for z in [-2.31, -0.22]:
		_beam(2, Vector3(-1.72, 1.45, z), Vector3(-1.72, 2.6, z), 0.075)


func _power_unit() -> void:
	for x in [-1.42, 1.42]:
		_box(2, Vector3(x, 0.12, 0), Vector3(0.46, 0.24, 4.88), Vector3.ZERO, 0.10)
	_box(2, Vector3(0, 0.40, 0), Vector3(3.18, 0.42, 4.44), Vector3.ZERO, 0.12)
	_box(0, Vector3(0, 1.51, 0), Vector3(2.96, 1.89, 4.18), Vector3.ZERO, 0.21)
	_box(4, Vector3(0, 2.49, 0), Vector3(3.14, 0.15, 4.34), Vector3.ZERO, 0.12)
	_plate_wear(Vector3(0, 2.49, 0), Vector3(3.14, 0.15, 4.34), Vector3.ZERO)
	_box(0, Vector3(-0.18, 2.59, 0.36), Vector3(1.68, 0.065, 1.66), Vector3.ZERO, 0.08)
	_box(2, Vector3(-0.18, 2.63, 0.36), Vector3(0.82, 0.055, 0.09))
	for z in [-1.54, 1.40]:
		_box(1, Vector3(0, 2.58, z), Vector3(3.16, 0.13, 0.24))
	for side in [-1.0, 1.0]:
		_box(2, Vector3(side * 1.53, 1.56, -0.27), Vector3(0.14, 1.48, 2.77))
		for index in 10:
			_box(1, Vector3(side * 1.67, 1.56, -1.40 + index * 0.25), Vector3(0.23, 1.30, 0.08))
	_box(2, Vector3(0, 1.53, 2.12), Vector3(2.56, 1.45, 0.15), Vector3.ZERO, 0.10)
	_cylinder(3, Vector3(-0.41, 1.58, 2.23), 0.80, 0.10, Vector3(90, 0, 0), 14)
	_ring(4, Vector3(-0.41, 1.58, 2.35), 0.82, 0.095)
	for angle in [0.0, 60.0, 120.0]:
		var radians := deg_to_rad(angle)
		var delta := Vector3(cos(radians) * 0.79, sin(radians) * 0.79, 0)
		_beam(2, Vector3(-0.41, 1.58, 2.42) - delta, Vector3(-0.41, 1.58, 2.42) + delta, 0.035)
	_box(1, Vector3(1.0, 1.54, 2.28), Vector3(0.48, 1.16, 0.10), Vector3.ZERO, 0.07)
	_box(5, Vector3(1.01, 1.85, 2.35), Vector3(0.30, 0.18, 0.06), Vector3.ZERO, 0.025)
	_box(2, Vector3(1.01, 1.53, 2.35), Vector3(0.30, 0.34, 0.06))
	for x in [-1.18, 1.18]:
		for y in [0.89, 2.19]:
			_bolt(Vector3(x, y, 2.26))
	# Vent riser and elbows visibly welded to the housing. Steam starts here.
	_cylinder(2, Vector3(1.03, 2.70, -1.25), 0.19, 0.36, Vector3.ZERO, 8)
	_cylinder(1, Vector3(1.03, 2.90, -1.25), 0.29, 0.12, Vector3.ZERO, 10)
	_cylinder(2, Vector3(1.03, 3.00, -1.25), 0.16, 0.12, Vector3.ZERO, 8)
	# Exterior conduits have a housing connection and a ground terminus.
	_beam(2, Vector3(1.55, 0.66, -1.62), Vector3(2.15, 0.66, -1.62), 0.13)
	_beam(2, Vector3(2.15, 0.66, -1.62), Vector3(2.15, 0.12, -1.62), 0.13)
	_beam(2, Vector3(2.15, 0.12, -1.62), Vector3(3.46, 0.12, -1.62), 0.13)
	_box(1, Vector3(3.49, 0.16, -1.62), Vector3(0.40, 0.32, 0.52), Vector3.ZERO, 0.07)
	_box(2, Vector3(0.8, 0.10, -3.32), Vector3(2.57, 0.20, 1.28), Vector3(0, 12, 0), 0.13)
	_box(1, Vector3(0.8, 0.29, -3.32), Vector3(1.8, 0.16, 1.13), Vector3(0, 17, 0), 0.10)


func _fan() -> void:
	for index in 5:
		var angle := float(index) * TAU / 5.0
		var center := Vector3(cos(angle) * 0.37, sin(angle) * 0.37, 0)
		_box(2, center, Vector3(0.55, 0.19, 0.055), Vector3(0, 0, rad_to_deg(angle) + 24), 0.05)
	_cylinder(1, Vector3.ZERO, 0.17, 0.12, Vector3(90, 0, 0), 10)


func _save_mesh(name: String) -> void:
	var mesh := ArrayMesh.new()
	mesh.resource_name = name
	var vertices := 0
	for index in MATERIAL_NAMES.size():
		if _surfaces[index]["count"] == 0:
			continue
		var surface: SurfaceTool = _surfaces[index]["tool"]
		surface.index()
		surface.commit(mesh)
		vertices += int(_surfaces[index]["count"])
	assert(ResourceSaver.save(mesh, OUTPUT + name + ".res") == OK)
	print(name, ": ", mesh.get_surface_count(), " material surfaces, ", vertices / 3, " triangles")


func _cloth(name: String, width: float, height: float, canopy: bool) -> void:
	_reset()
	var rows := 8
	var columns := 16
	for row in rows:
		for column in columns:
			var corners: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for offset in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var uv := Vector2(float(column + offset.x) / columns, float(row + offset.y) / rows)
				var y := -uv.y * height
				if not canopy:
					# Baked frayed lower edge: no alpha transparency, no alpha sorting.
					var edge_notch := sin(uv.x * 39.0) * 0.035 + sin(uv.x * 71.0) * 0.025
					edge_notch += maxf(0.0, 1.0 - absf(uv.x - 0.3125) / 0.065) * 0.23
					edge_notch += maxf(0.0, 1.0 - absf(uv.x - 0.75) / 0.065) * 0.17
					y += edge_notch * pow(uv.y, 6.0)
					corners.append(Vector3((uv.x - 0.5) * width, y, sin(uv.x * 10.0) * uv.y * 0.045))
				else:
					var sag := sin(uv.x * PI) * sin(uv.y * PI) * -0.15
					corners.append(Vector3((uv.x - 0.5) * width, sag, (uv.y - 0.5) * height))
				uvs.append(uv)
			_triangle(0, corners[0], corners[2], corners[1], uvs[0], uvs[2], uvs[1])
			_triangle(0, corners[0], corners[3], corners[2], uvs[0], uvs[3], uvs[2])
	var surface: SurfaceTool = _surfaces[0]["tool"]
	# The cloth material comes from its reusable scene, rather than this surface.
	surface.set_material(null)
	surface.index()
	var mesh := surface.commit()
	mesh.resource_name = name
	assert(ResourceSaver.save(mesh, OUTPUT + name + ".res") == OK)
