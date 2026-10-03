extends RefCounted
## Reusable authored object families. All geometry is local to a supplied parent.
## Attach the result to the real moving body/pivot; never duplicate its motion.
const BATCH := preload("res://scripts/environment/arena_detail_batch.gd")
var core := BATCH.new()
var details := BATCH.new()
var fine := BATCH.new()
var palette: Dictionary

func _init(materials: Dictionary) -> void:
	palette = materials

func panel(at: Vector3, size: Vector2, basis: Basis = Basis.IDENTITY, paint: bool = true) -> void:
	details.beveled_box(palette.dark, at, Vector3(size.x + 0.09, size.y + 0.09, 0.06), 0.025, basis)
	details.beveled_box(palette.paint if paint else palette.stone, at + basis * Vector3(0, 0, 0.038), Vector3(size.x, size.y, 0.035), 0.012, basis)
	for side in [-1.0, 1.0]:
		details.box(palette.bright, at + basis * Vector3(0, side * (size.y * 0.5 + 0.025), 0.014), Vector3(size.x + 0.12, 0.026, 0.04), basis)
		for x in [-1.0, 1.0]:
			bolt(at + basis * Vector3(x * size.x * 0.46, side * size.y * 0.45, 0.065), 0.025, basis * Basis(Vector3.RIGHT, PI * 0.5))

func bolt(at: Vector3, radius: float, basis: Basis = Basis.IDENTITY) -> void:
	fine.cylinder(palette.dark, at, radius * 1.35, 0.012, basis, 12)
	fine.cylinder(palette.bright, at + basis * Vector3.UP * 0.008, radius, 0.022, basis, 6)

func vent(at: Vector3, size: Vector2, basis: Basis = Basis.IDENTITY) -> void:
	details.beveled_box(palette.trim, at, Vector3(size.x + 0.08, 0.032, size.y + 0.08), 0.01, basis)
	details.box(palette.dark, at + basis * Vector3.UP * 0.024, Vector3(size.x, 0.008, size.y), basis)
	for index in range(7):
		var x := size.x * (-0.42 + float(index) * 0.14)
		details.beveled_box(palette.metal, at + basis * Vector3(x, 0.04, 0), Vector3(size.x * 0.058, 0.06, size.y), 0.012, basis)
	for side in [-1.0, 1.0]:
		bolt(at + basis * Vector3(side * size.x * 0.44, 0.042, size.y * 0.39), 0.028, basis)

func plaque(at: Vector3, number: int, scale: float = 1.0, basis: Basis = Basis.IDENTITY) -> void:
	details.beveled_box(palette.dark, at, Vector3(0.47, 0.27, 0.025) * scale, 0.013 * scale, basis)
	var digits := [int(number / 10) % 10, number % 10]
	var segments := [[0,1,2,4,5,6], [2,5], [0,2,3,4,6], [0,2,3,5,6], [1,2,3,5], [0,1,3,5,6], [0,1,3,4,5,6], [0,2,5], [0,1,2,3,4,5,6], [0,1,2,3,5,6]]
	var positions := [Vector2(0,0.09), Vector2(-0.05,0.047), Vector2(0.05,0.047), Vector2.ZERO, Vector2(-0.05,-0.047), Vector2(0.05,-0.047), Vector2(0,-0.09)]
	for digit in range(2):
		for segment in segments[digits[digit]]:
			var position: Vector2 = positions[segment]
			var horizontal: bool = segment in [0,3,6]
			var size := Vector3(0.083, 0.013, 0.007) if horizontal else Vector3(0.013, 0.068, 0.007)
			details.box(palette.marking, at + basis * Vector3(position.x + (float(digit) - 0.5) * 0.17, position.y, 0.016) * scale, size * scale, basis)

func cover(size: Vector3, style: String, number: int) -> void:
	# Orient the facade along the long axis, including narrow rotating covers.
	var basis := Basis.IDENTITY if size.x >= size.z else Basis(Vector3.UP, PI * 0.5)
	var width := maxf(size.x, size.z)
	var depth := minf(size.x, size.z)
	var h := size.y
	core.beveled_box(palette.stone if style != "clock" else palette.paint, Vector3.ZERO, size * Vector3(0.99, 0.98, 0.99), minf(depth * 0.1, 0.08))
	for y in [-h * 0.5 + 0.085, h * 0.5 - 0.09]:
		details.beveled_box(palette.metal, basis * Vector3(0, y, 0), Vector3(width, 0.15, depth), 0.04, basis)
		details.box(palette.dark, basis * Vector3(0, y - 0.085, 0), Vector3(width * 0.96, 0.035, depth * 0.99), basis)
	for side in [-1.0, 1.0]:
		var face := basis * Basis(Vector3.UP, 0.0 if side > 0 else PI)
		var facade := basis * Vector3(0, 0, side * depth * 0.498)
		var columns := maxi(2, int(width / 1.55))
		for index in columns:
			var x := (float(index) + 0.5) * width / float(columns) - width * 0.5
			var at := facade + basis * Vector3(x, 0.07, 0)
			var panel_width := width / float(columns) * 0.83
			panel(at, Vector2(panel_width, h * 0.60), face, style != "garden")
			if style == "solar":
				# An actual heat exchanger, with recessed fins and copper headers.
				details.box(palette.dark, at + face * Vector3(0, 0, 0.065), Vector3(panel_width * 0.84, h * 0.48, 0.025), face)
				for slat in range(9):
					var x_fin := (float(slat) - 4.0) * panel_width * 0.084
					details.beveled_box(palette.metal, at + face * Vector3(x_fin, 0, 0.096), Vector3(0.065, h * 0.48, 0.095), 0.013, face)
				for y_fin in [-0.25, 0.25]:
					details.pipe(palette.bright, at + face * Vector3(-panel_width * 0.42, y_fin * h, 0.12), at + face * Vector3(panel_width * 0.42, y_fin * h, 0.12), 0.055, 12)
			elif style == "garden":
				# Irrigation manifolds distinguish the planters from machine cabinets.
				for sign_value in [-1.0, 1.0]:
					var x_pipe: float = sign_value * panel_width * 0.30
					details.pipe(palette.metal, at + face * Vector3(x_pipe, -h * 0.24, 0.075), at + face * Vector3(x_pipe, h * 0.26, 0.075), 0.055)
				details.pipe(palette.bright, at + face * Vector3(-panel_width * 0.38, h * 0.26, 0.075), at + face * Vector3(panel_width * 0.38, h * 0.26, 0.075), 0.06)
				gauge(at + face * Vector3(0, h * 0.15, 0.11), 0.17, face)
			elif style == "clock":
				var radius := minf(panel_width * 0.41, h * 0.29)
				var wheel_basis := face * Basis(Vector3.RIGHT, PI * 0.5)
				details.cylinder(palette.dark, at + face * Vector3(0, 0, 0.08), radius * 1.12, 0.08, wheel_basis, 32)
				gear(at + face * Vector3(0, 0.08, 0.135), radius, wheel_basis, 18)
				gear(at + face * Vector3(radius * 0.83, -radius * 0.8, 0.14), radius * 0.38, wheel_basis, 10)
				for joint in [-1.0, 1.0]:
					details.pipe(palette.bright, at + face * Vector3(joint * radius * 0.74, -h * 0.20, 0.10), at + face * Vector3(joint * radius * 0.74, h * 0.20, 0.10), 0.016, 8)
		plaque(facade + face * Vector3(-width * 0.29, -h * 0.30, 0.078), number, 1.0, face)
		for end in [-1.0, 1.0]:
			var at := facade + basis * Vector3(end * width * 0.445, 0, 0)
			details.beveled_box(palette.trim, at, Vector3(0.14, h * 0.92, 0.095), 0.026, face)
			for y in [-0.34, 0.34]:
				bolt(at + face * Vector3(0, y * h, 0.062), 0.043, face * Basis(Vector3.RIGHT, PI * 0.5))
	var roof := Vector3.UP * (h * 0.5 - 0.025)
	if style == "garden":
		details.beveled_box(palette.dark, roof, Vector3(width * 0.87, 0.09, depth * 0.76), 0.025, basis)
		details.box(palette.soil, roof + Vector3.UP * 0.038, Vector3(width * 0.82, 0.02, depth * 0.69), basis)
		for index in range(4):
			var x_plant := (float(index) - 1.5) * width * 0.21
			fern(roof + basis * Vector3(x_plant, 0.05, 0), minf(depth * 0.86, 0.95), number + index)
		palm(roof + basis * Vector3(width * 0.08, 0.055, 0), minf(depth * 1.15, 1.15), number + 9)
	else:
		vent(roof + basis * Vector3(width * 0.20, 0.005, 0), Vector2(width * 0.22, depth * 0.58), basis)
		if style == "solar":
			# Low receiver cylinders give each battery a visible roof silhouette.
			for x in [-0.32, -0.12]:
				var receiver := roof + basis * Vector3(width * x, 0.11, 0)
				details.cylinder(palette.paint, receiver, depth * 0.29, 0.20, basis, 24)
				details.ring(palette.bright, receiver + Vector3.UP * 0.09, depth * 0.29, 0.035, 0.035, basis, 24)
				vent(receiver + Vector3.UP * 0.105, Vector2(depth * 0.38, depth * 0.38), basis)
		else:
			gear(roof + basis * Vector3(-width * 0.26, 0.035, 0), minf(depth * 0.27, 0.25), basis, 12)
		for x in [-0.48, 0.48]:
			for z in [-0.43, 0.43]:
				bolt(roof + basis * Vector3(x * width, 0.04, z * depth), 0.04, basis)
		for z in [-0.41, 0.41]:
			details.pipe(palette.bright, roof + basis * Vector3(-width * 0.41, 0.005, z * depth), roof + basis * Vector3(width * 0.41, 0.005, z * depth), 0.022)
	# Narrow end faces matter at the gameplay camera angle as much as facades.
	for end in [-1.0, 1.0]:
		var face := basis * Basis(Vector3.UP, end * PI * 0.5)
		var at := basis * Vector3(end * width * 0.498, -h * 0.04, 0)
		panel(at, Vector2(depth * 0.71, h * 0.62), face, style != "garden")
		if style != "garden":
			gauge(at + face * Vector3(0, h * 0.17, 0.07), depth * 0.19, face)
			vent(at + face * Vector3(0, -h * 0.19, 0.07), Vector2(depth * 0.60, h * 0.24), face * Basis(Vector3.RIGHT, PI * 0.5))

func gauge(at: Vector3, radius: float, basis: Basis = Basis.IDENTITY) -> void:
	var face := basis * Basis(Vector3.RIGHT, PI * 0.5)
	details.cylinder(palette.dark, at, radius * 1.1, 0.05, face, 24)
	details.cylinder(palette.marking, at + basis * Vector3(0, 0, 0.032), radius * 0.84, 0.012, face, 24)
	details.ring(palette.bright, at + basis * Vector3(0, 0, 0.040), radius, radius * 0.14, 0.03, face, 24)
	details.beam(palette.dark, at + basis * Vector3(0, 0, 0.06), at + basis * Vector3(radius * 0.45, radius * 0.4, 0.06), 0.025)
	for i in range(7):
		var angle := float(i) * PI / 4.5 - PI * 0.18
		fine.box(palette.dark, at + basis * Vector3(cos(angle) * radius * 0.66, sin(angle) * radius * 0.66, 0.053), Vector3(radius * 0.07, radius * 0.13, 0.008), basis * Basis(Vector3.FORWARD, angle))

func warning_rail(size: Vector3, live_material: Material) -> void:
	var basis := Basis.IDENTITY if size.x >= size.z else Basis(Vector3.UP, PI * 0.5)
	var width := maxf(size.x, size.z)
	var depth := minf(size.x, size.z)
	for side in [-1.0, 1.0]:
		for index in range(8):
			var x := (float(index) - 3.5) * width * 0.11
			details.box(live_material, basis * Vector3(x, size.y * 0.5 + 0.022, side * depth * 0.34), Vector3(width * 0.077, 0.025, depth * 0.16), basis)

func floor_hatch(at: Vector3, size: Vector2, basis: Basis = Basis.IDENTITY) -> void:
	# Flush inspection plates stay below a walking robot's feet.
	details.beveled_box(palette.dark, at, Vector3(size.x, 0.013, size.y), 0.02, basis)
	details.box(palette.metal, at + Vector3.UP * 0.009, Vector3(size.x * 0.91, 0.008, size.y * 0.88), basis)
	vent(at + Vector3.UP * 0.012, size * Vector2(0.77, 0.64), basis)
	for sign_value in [-1.0, 1.0]:
		for i in range(5):
			details.box(palette.marking, at + basis * Vector3((float(i) - 2.0) * size.x * 0.17, 0.014, sign_value * size.y * 0.45), Vector3(size.x * 0.075, 0.01, 0.04), basis * Basis(Vector3.UP, 0.4))

func service_station(at: Vector3, style: String, number: int, basis: Basis = Basis.IDENTITY) -> void:
	# One mounted assembly, authored around a 1.65 x 2.40 m exterior footprint.
	core.beveled_box(palette.dark, at + basis * Vector3(0, 0.06, 0), Vector3(1.65, 0.18, 2.4), 0.055, basis)
	core.beveled_box(palette.paint, at + basis * Vector3(-0.29, 0.81, -0.18), Vector3(0.87, 1.44, 1.65), 0.09, basis)
	for z in [-0.89, 0.53]:
		details.beveled_box(palette.metal, at + basis * Vector3(-0.29, 0.80, z), Vector3(0.92, 1.44, 0.12), 0.035, basis)
	var face := basis * Basis(Vector3.UP, PI * 0.5)
	panel(at + basis * Vector3(0.16, 0.84, -0.21), Vector2(1.21, 1.03), face)
	plaque(at + basis * Vector3(0.2, 0.50, 0.15), number, 0.85, face)
	gauge(at + basis * Vector3(0.22, 1.15, -0.48), 0.20, face)
	vent(at + basis * Vector3(-0.29, 1.56, -0.18), Vector2(0.69, 1.28), basis)
	if style == "clock":
		gear(at + basis * Vector3(0.26, 0.83, -0.24), 0.47, face * Basis(Vector3.RIGHT, PI * 0.5), 20)
	else:
		for z in [-0.35, 0.52]:
			var tank := at + basis * Vector3(0.50, 0.69, z)
			core.cylinder(palette.metal, tank, 0.24, 1.12, basis, 24)
			for y in [-0.38, 0.38]:
				details.ring(palette.bright, tank + Vector3.UP * y, 0.26, 0.035, 0.075, basis, 24)
			details.cylinder(palette.dark, tank + Vector3.UP * 0.61, 0.17, 0.11, basis, 20)
	for z in [-0.85, 0.91]:
		details.pipe(palette.metal, at + basis * Vector3(0.53, 0.36, z), at + basis * Vector3(0.53, 1.65, z), 0.075)
		details.pipe(palette.bright, at + basis * Vector3(0.53, 1.65, z), at + basis * Vector3(-0.30, 1.65, z), 0.06)
	if style == "garden":
		fern(at + basis * Vector3(-0.1, 0.17, 1.0), 0.65, number)

func palm(at: Vector3, reach: float, seed: int) -> void:
	# Staggered arched fronds, with tapered ribs rather than flat triangles.
	for index in range(9):
		var angle := float(index) * 2.39996 + float(seed) * 0.81
		var forward := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-forward.z, 0, forward.x)
		var length := reach * (0.78 + float((seed + index) % 4) * 0.08)
		var previous := at
		for segment in range(6):
			var t0 := float(segment) / 6.0
			var t1 := float(segment + 1) / 6.0
			var a := at + forward * length * t0 * 0.78 + Vector3.UP * sin(t0 * PI * 0.76) * length * 0.88
			var b := at + forward * length * t1 * 0.78 + Vector3.UP * sin(t1 * PI * 0.76) * length * 0.88
			var w0 := sin(t0 * PI) * length * 0.105
			var w1 := sin(t1 * PI) * length * 0.105
			var ridge0 := a + Vector3.UP * w0 * 0.45
			var ridge1 := b + Vector3.UP * w1 * 0.45
			var material: Material = palette.leaf_light if index % 3 == 0 else palette.leaf
			_leaf_quad(material, a - side * w0, b - side * w1, ridge1, ridge0, Vector2(0, t0), Vector2(0, t1), Vector2(0.5, t1), Vector2(0.5, t0))
			_leaf_quad(material, ridge0, ridge1, b + side * w1, a + side * w0, Vector2(0.5, t0), Vector2(0.5, t1), Vector2(1, t1), Vector2(1, t0))
			details.beam(palette.stem, previous, ridge1, 0.015)
			previous = ridge1

func gear(at: Vector3, radius: float, basis: Basis = Basis.IDENTITY, teeth: int = 16) -> void:
	details.ring(palette.metal, at, radius * 0.75, radius * 0.23, 0.07, basis, 32)
	details.ring(palette.bright, at + basis * Vector3.UP * 0.043, radius * 0.60, radius * 0.06, 0.018, basis, 32)
	details.cylinder(palette.dark, at, radius * 0.29, 0.05, basis, 16)
	for index in teeth:
		var angle := TAU * float(index) / float(teeth)
		var radial := Vector3(cos(angle), 0, sin(angle))
		details.beveled_box(palette.bright, at + basis * radial * radius * 0.92, Vector3(radius * 0.25, 0.08, radius * 0.20), 0.013, basis * Basis(Vector3.UP, -angle))
	for index in range(5):
		var angle := TAU * float(index) / 5.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		details.beam(palette.trim, at + basis * radial * radius * 0.2, at + basis * radial * radius * 0.7, radius * 0.065)

func mirror_frame(size: Vector2, number: int) -> void:
	for side in [-1.0, 1.0]:
		var basis := Basis(Vector3.UP, PI if side < 0 else 0.0)
		for x in [-1.0, 1.0]:
			var at := Vector3(x * (size.x * 0.5 - 0.035), 0, side * 0.09)
			details.beveled_box(palette.trim, at, Vector3(0.105, size.y + 0.04, 0.095), 0.026, basis)
			for y in [-0.42, 0.42]:
				bolt(at + basis * Vector3(0, size.y * y, 0.05), 0.042, basis * Basis(Vector3.RIGHT, PI * 0.5))
		for y in [-1.0, 1.0]:
			details.beveled_box(palette.bright, Vector3(0, y * (size.y * 0.5 - 0.04), side * 0.095), Vector3(size.x, 0.095, 0.08), 0.024, basis)
		# Thin divisions leave the mirror and the golden command hub exposed.
		for y in [-0.0, 0.42]:
			details.box(palette.metal, Vector3(0, y, side * 0.131), Vector3(size.x * 0.85, 0.021, 0.009))
		plaque(Vector3(0.38, -0.72, side * 0.135), number, 0.53, basis)

func mirror_base() -> void:
	details.ring(palette.trim, Vector3(0, 0.14, 0), 0.81, 0.07, 0.22, Basis.IDENTITY, 40)
	details.ring(palette.bright, Vector3(0, 0.266, 0), 0.72, 0.035, 0.025, Basis.IDENTITY, 40)
	for index in range(12):
		var a := TAU * float(index) / 12.0
		bolt(Vector3(cos(a) * 0.75, 0.286, sin(a) * 0.75), 0.028)
	for side in [-1.0, 1.0]:
		details.pipe(palette.metal, Vector3(side * 0.22, 0.27, 0), Vector3(side * 0.22, 0.95, 0), 0.06)

func fern(at: Vector3, reach: float, seed: int) -> void:
	for frond in range(4):
		var angle := float(frond) * 2.39996 + float(seed) * 0.71
		var forward := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-forward.z, 0, forward.x)
		var length := reach * (0.95 + float((seed + frond) % 3) * 0.15)
		var previous := at
		for index in range(1, 7):
			var t := float(index) / 7.0
			var center := at + forward * length * t * 0.70 + Vector3.UP * sin(t * PI * 0.8) * length * 0.8
			details.beam(palette.stem, previous, center, 0.014)
			previous = center
			for sign_value in [-1.0, 1.0]:
				var direction: Vector3 = (side * sign_value + forward * 0.38).normalized()
				var leaf_length := length * (0.38 - t * 0.28)
				_leaf(palette.leaf if (index + frond) % 3 else palette.leaf_light, center, direction, leaf_length, leaf_length * 0.38, leaf_length * 0.18)

func _leaf_quad(material: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2) -> void:
	details.triangle_uv(material, a, b, c, uv_a, uv_b, uv_c)
	details.triangle_uv(material, a, c, d, uv_a, uv_c, uv_d)

func _leaf(material: Material, at: Vector3, direction: Vector3, length: float, width: float, rise: float) -> void:
	var side := Vector3(-direction.z, 0, direction.x).normalized()
	for segment in range(5):
		var t0 := float(segment) / 5.0
		var t1 := float(segment + 1) / 5.0
		var a := at + direction * length * t0 + Vector3.UP * (sin(t0 * PI) * rise + t0 * rise * 0.32)
		var b := at + direction * length * t1 + Vector3.UP * (sin(t1 * PI) * rise + t1 * rise * 0.32)
		var w0 := sin(t0 * PI) * width * 0.5
		var w1 := sin(t1 * PI) * width * 0.5
		_leaf_quad(material, a - side * w0, b - side * w1, b + side * w1, a + side * w0, Vector2(0, t0), Vector2(0, t1), Vector2(1, t1), Vector2(1, t0))

func pendulum(reach: float) -> void:
	for side in [-1.0, 1.0]:
		details.pipe(palette.bright, Vector3(0.35, 1.10, side * 0.06), Vector3(reach - 0.38, 1.10, side * 0.06), 0.028)
	for index in range(7):
		var x := 0.7 + float(index) * (reach - 1.3) / 6.0
		details.beveled_box(palette.trim, Vector3(x, 1.1, 0), Vector3(0.055, 0.19, 0.20), 0.016)
		bolt(Vector3(x, 1.21, 0), 0.027)
	# A heavy steel bob enclosed by brass retaining hoops.
	core.cylinder(palette.paint, Vector3(reach, 0.85, 0), 0.43, 0.83, Basis.IDENTITY, 32)
	for y in [0.49, 0.85, 1.21]:
		details.ring(palette.bright, Vector3(reach, y, 0), 0.55, 0.08, 0.085, Basis.IDENTITY, 40)
	gear(Vector3(reach, 1.28, 0), 0.49, Basis.IDENTITY, 16)
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var radial := Vector3(cos(angle), 0, sin(angle)) * 0.46
		details.pipe(palette.metal, Vector3(reach, 0.52, 0) + radial, Vector3(reach, 1.23, 0) + radial, 0.037)

func flush(parent: Node3D, label: String = "AuthoredVisual") -> Dictionary:
	var root := Node3D.new()
	root.name = label
	root.set_meta("visual_only", true)
	root.set_meta("arena_visual_kit", true)
	parent.add_child(root)
	var core_meshes: Array[MeshInstance3D] = core.flush(root, "PrimarySilhouette")
	for mesh in core_meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var detail_meshes: Array[MeshInstance3D] = details.flush(root, "ObjectDetail")
	for mesh in detail_meshes:
		if mesh.material_override in [palette.leaf, palette.leaf_light]:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var optional := Node3D.new()
	optional.name = "OptionalFasteners"
	root.add_child(optional)
	var fine_meshes: Array[MeshInstance3D] = fine.flush(optional, "Fasteners")
	var triangles := core.triangles + details.triangles + fine.triangles
	root.set_meta("triangles", triangles)
	return {"root": root, "optional": optional, "batches": core_meshes.size() + detail_meshes.size() + fine_meshes.size(), "triangles": triangles}
