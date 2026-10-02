extends Node3D

const HEIGHT := 2.4
const MAP_HALF_EXTENTS := Vector2(17.4, 14.5)
const PLAYABLE_HALF_EXTENTS := Vector2(15.8, 13.1)
const RAMP_LENGTH := 6.3
const BUSH_VISUAL := preload("res://scripts/bush_visual.gd")
const BRIDGE_MATERIALS := [
	preload("res://art/environment/families/steel_frame.tres"),
	preload("res://art/environment/families/paint_cream.tres"),
	preload("res://art/environment/families/paint_ivory.tres"),
	preload("res://art/environment/families/joint_rust.tres")
]
var surfaces: Array[StaticBody3D] = []
var _art_batches: Array[SurfaceTool] = []


func configure(base_nodes: Array[Node3D], factory: Node3D) -> void:
	# Keep the yard perimeter and floor; author fewer, deliberate gameplay props.
	for source in base_nodes:
		if source.is_in_group("bush_placeholder") or source.is_in_group("repair_kits"):
			continue
		var label := str(source.name)
		if source.get_meta("blocks_navigation", false) and not ("Panel" in label or "Limit" in label):
			continue
		var copy := source.duplicate() as Node3D
		copy.transform = Transform3D(Basis.from_scale(Vector3(0.6, 1, 0.5)), Vector3.ZERO) * source.transform
		add_child(copy)
	# Ground routes are broad; brush conceals actors without blocking movement.
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var label := ("West" if side < 0 else "East") + ("North" if end < 0 else "South")
			var cover: StaticBody3D = factory.call("_create_scrap_barrier", label + "LaneCover", Vector3(side * 9.8, 0.75, end * 5.5), Vector3(2.8, 1.5, 0.7))
			cover.reparent(self)
			_bush(label + "LaneBush", Vector3(side * 13.0, 0, end * 5.0), 1.6, 2.15)
			_bush(label + "ApproachBush", Vector3(side * 7.4, 0, end * 10.3), 1.35, 2.0)
	for entry in [
		["HealthPadWest", Vector3(-14, 0, 0)], ["HealthPadEast", Vector3(14, 0, 0)],
		["HealthPadNorth", Vector3(0, 0, -7)], ["HealthPadSouth", Vector3(0, 0, 7)]
	]:
		var kit: Area3D = factory.REPAIR_KIT_SCENE.instantiate()
		kit.name = entry[0]
		kit.position = entry[1]
		kit.collection_radius = 1.25
		kit.visual_scale = 1.3
		kit.add_child(factory.REPAIR_SOCKET.instantiate())
		add_child(kit)
		kit.call("set_collection_active", false)
	for x in [-3.5, 3.5]:
		var side := "West" if x < 0 else "East"
		_box(side + "Platform", Vector3(x, HEIGHT * 0.5, 0.6), Vector3(3.8, HEIGHT, 5.8), factory)
		_ramp(side + "NorthRamp", x, -8.6, -2.3, 0.0, HEIGHT, factory)
		_ramp(side + "SouthRamp", x, 3.5, 9.8, HEIGHT, 0.0, factory)
		for z in [-8.4, 9.6]:
			var signpost := Label3D.new()
			signpost.text = "↑  ACCÈS  ↑"
			signpost.position = Vector3(x, height_at(Vector3(x, 0, z)) + 0.045, z)
			signpost.rotation_degrees.x = -90
			signpost.font_size = 32
			signpost.pixel_size = 0.010
			signpost.modulate = Color("#d8cfb8")
			add_child(signpost)
	_box("CentralBridge", Vector3(0, HEIGHT - 0.18, 0.6), Vector3(3.2, 0.36, 2.8), factory)
	# Short outer shields leave the inner lane, bridge and both ramp exits open.
	for side in [-1.0, 1.0]:
		_platform_cover(side, factory)
		_lane_markers(side, factory)
	_bridge_presentation()


func height_at(point: Vector3) -> float:
	if absf(point.x) <= 1.6 and point.z >= -0.8 and point.z <= 2.0:
		return HEIGHT
	if absf(absf(point.x) - 3.5) <= 1.9:
		if point.z >= -2.3 and point.z <= 3.5:
			return HEIGHT
		if point.z >= -8.6 and point.z < -2.3:
			return HEIGHT * (point.z + 8.6) / RAMP_LENGTH
		if point.z > 3.5 and point.z <= 9.8:
			return HEIGHT * (9.8 - point.z) / RAMP_LENGTH
	return 0.0


func segment_walkable(origin: Vector3, destination: Vector3) -> bool:
	if absf(destination.x) > PLAYABLE_HALF_EXTENTS.x or absf(destination.z) > PLAYABLE_HALF_EXTENTS.y:
		return false
	var steps := maxi(1, ceili(Vector2(destination.x - origin.x, destination.z - origin.z).length() / 0.12))
	var previous := height_at(origin)
	for index in range(1, steps + 1):
		var level := height_at(origin.lerp(destination, float(index) / float(steps)))
		if absf(level - previous) > 0.16:
			return false
		previous = level
	return true


func map_half_extents() -> Vector2:
	return MAP_HALF_EXTENTS


func navigation_extent() -> float:
	return PLAYABLE_HALF_EXTENTS.x


func _bush(label: String, point: Vector3, radius: float, height: float) -> void:
	var bush := Node3D.new()
	bush.name = label
	bush.position = point
	bush.add_to_group("bush_placeholder")
	bush.add_to_group("arena_passable_decor")
	bush.set_meta("bush_center", point)
	bush.set_meta("bush_visual_position", point)
	bush.set_meta("bush_radius", radius)
	bush.set_meta("bush_height", height)
	var visual := BUSH_VISUAL.new()
	visual.name = "GroundedVegetation"
	visual.position.y = 0.012
	visual.setup(radius, height, label.hash())
	bush.add_child(visual)
	add_child(bush)


func _lane_markers(side: float, factory: Node3D) -> void:
	var tint := Color("#b97b58") if side < 0 else Color("#6e9ca0")
	for z in [-8.0, 0.0, 8.0]:
		var marking := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 0.025, 1.8)
		marking.mesh = mesh
		marking.position = Vector3(side * 11.8, 0.025, z)
		marking.material_override = factory.call("_material", tint, 0.95)
		marking.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marking)
	var label := Label3D.new()
	label.text = "OUEST // 03" if side < 0 else "EST // 07"
	label.position = Vector3(side * 11.8, 0.04, 10.9)
	label.rotation_degrees.x = -90
	label.font_size = 48
	label.pixel_size = 0.012
	label.modulate = tint
	label.outline_size = 3
	add_child(label)


func _platform_cover(side: float, factory: Node3D) -> void:
	var label := "WestDeckCover" if side < 0 else "EastDeckCover"
	var body := _box(label, Vector3(side * 4.65, HEIGHT + 0.65, 0.6), Vector3(0.5, 1.3, 2.0), factory, false)
	# Reclaimed steel with a pale face and a warm cap: readable from above.
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.52, 0.86, 1.72)
	plate.mesh = plate_mesh
	plate.material_override = BRIDGE_MATERIALS[1]
	body.add_child(plate)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.54, 0.06, 2.0)
	cap.mesh = cap_mesh
	cap.position.y = 0.62
	cap.material_override = BRIDGE_MATERIALS[2]
	body.add_child(cap)


func _bridge_presentation() -> void:
	# Four opaque batches reuse the courtyard's materials. Decoration owns no
	# collision, navigation or height data; all walking surfaces stay intact.
	for material in BRIDGE_MATERIALS:
		var batch := SurfaceTool.new()
		batch.begin(Mesh.PRIMITIVE_TRIANGLES)
		batch.set_material(material)
		_art_batches.append(batch)
	for x in [-3.5, 3.5]:
		# Sealed salvage housings: cream service panels within the platform volume.
		for face in [-1.0, 1.0]:
			for z in [-1.25, 0.6, 2.45]:
				_art_box(1, Vector3(x + face * 1.83, 1.24, z), Vector3(0.12, 1.92, 1.70), 0.035)
				_art_box(3, Vector3(x + face * 1.84, 0.18, z), Vector3(0.12, 0.10, 1.76), 0.02)
			# Rolled edge beams sit below the deck rather than forming new rails.
			_art_box(0, Vector3(x + face * 1.82, HEIGHT - 0.08, 0.6), Vector3(0.15, 0.16, 5.72), 0.03, Basis.IDENTITY, Color(1.22, 1.22, 1.22))
		for column in [-1.0, 1.0]:
			for row in range(3):
				var point := Vector3(x + column * 0.9, HEIGHT - 0.045, -1.23 + row * 1.83)
				_deck_plate(point, Vector2(1.70, 1.72), Basis.IDENTITY, 1.10 + row * 0.035)
		# Ramp sheets, raised seam caps and short worn entry marks.
		for north in [true, false]:
			var start := -8.6 if north else 3.5
			var slope := -atan(HEIGHT / RAMP_LENGTH) if north else atan(HEIGHT / RAMP_LENGTH)
			var basis := Basis(Vector3.RIGHT, slope)
			var sheet_length := RAMP_LENGTH / cos(slope) / 3.0 - 0.07
			for row in range(3):
				var z := start + (row + 0.5) * RAMP_LENGTH / 3.0
				var point := Vector3(x, height_at(Vector3(x, 0, z)), z)
				_deck_plate(point - basis.y * 0.045, Vector2(3.36, sheet_length), basis, 1.13 + row * 0.025)
				# Narrow steel traction ribs replace the bright full-width stripes.
				for offset in [-0.42, 0.42]:
					_art_box(0, point + basis * Vector3(0, 0.023, offset), Vector3(2.85, 0.024, 0.045), 0.008, basis, Color(1.32, 1.32, 1.32))
			var middle := start + RAMP_LENGTH * 0.5
			for edge in [-1.0, 1.0]:
				_art_box(0, Vector3(x + edge * 1.79, HEIGHT * 0.5 - 0.08, middle), Vector3(0.13, 0.16, RAMP_LENGTH / cos(slope)), 0.03, basis, Color(1.20, 1.20, 1.20))
			var entry := start + (0.30 if north else RAMP_LENGTH - 0.30)
			for offset in [-1.0, 0.0, 1.0]:
				_art_box(2, Vector3(x + offset, height_at(Vector3(x, 0, entry)) + 0.018, entry), Vector3(0.48, 0.018, 0.13), 0.005, basis)
	# The connecting deck uses the same thick modular plates and folded seams.
	for x in [-0.79, 0.79]:
		for z in [-0.07, 1.27]:
			_deck_plate(Vector3(x, HEIGHT - 0.045, z), Vector2(1.48, 1.24), Basis.IDENTITY, 1.18)
	for z in [-0.70, 1.90]:
		_art_box(0, Vector3(0, HEIGHT - 0.10, z), Vector3(3.18, 0.19, 0.17), 0.035, Basis.IDENTITY, Color(1.25, 1.25, 1.25))
		for x in [-1.23, 1.23]:
			_art_box(2, Vector3(x, HEIGHT + 0.018, z), Vector3(0.42, 0.020, 0.14), 0.005)
	# A small repaired patch and two clamped joints sell the reused construction.
	_art_box(1, Vector3(0.62, HEIGHT + 0.025, 1.15), Vector3(0.68, 0.028, 0.43), 0.01, Basis(Vector3.UP, -0.12))
	for x in [-1.47, 1.47]:
		_art_box(3, Vector3(x, HEIGHT - 0.14, 0.6), Vector3(0.17, 0.12, 2.54), 0.02)
	var art := Node3D.new()
	art.name = "BridgePresentation"
	art.set_meta("visual_only", true)
	add_child(art)
	for index in range(_art_batches.size()):
		var visual := MeshInstance3D.new()
		visual.name = ["SteelPlatesAndHardware", "CreamArmor", "WornIvoryMarks", "OxidizedJoints"][index]
		visual.mesh = _art_batches[index].commit()
		art.add_child(visual)
	_art_batches.clear()


func _deck_plate(point: Vector3, size: Vector2, basis: Basis, brightness: float) -> void:
	_art_box(0, point, Vector3(size.x, 0.12, size.y), 0.035, basis, Color(brightness, brightness, brightness))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var corner := Vector3(x * (size.x * 0.5 - 0.14), 0.06, z * (size.y * 0.5 - 0.14))
			_art_box(0, point + basis * corner, Vector3(0.09, 0.032, 0.09), 0.01, basis, Color(1.45, 1.45, 1.45))
	# Local scuff/chip at a seam, with no noisy all-over rust pattern.
	_art_box(3, point + basis * Vector3(-size.x * 0.35, 0.062, size.y * 0.36), Vector3(0.22, 0.008, 0.06), 0.002, basis)


func _art_polygon(material: int, points: Array, normal: Vector3, tint: Color) -> void:
	var batch := _art_batches[material]
	for index in range(1, points.size() - 1):
		var vertices := [points[0], points[index], points[index + 1]]
		if (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).dot(normal) > 0:
			vertices.reverse()
		for vertex in vertices:
			batch.set_normal(normal.normalized())
			batch.set_color(tint)
			batch.add_vertex(vertex)


func _art_box(material: int, center: Vector3, size: Vector3, bevel: float, basis := Basis.IDENTITY, tint := Color.WHITE) -> void:
	# Clipped cuboids give broad plates bevel highlights with few triangles.
	var half := size * 0.5
	var cut := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.7)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			var points: Array = []
			normal[axis] = sign_value
			for signs in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = sign_value * half[axis]
				point[u] = signs.x * (half[u] - cut)
				point[v] = signs.y * (half[v] - cut)
				points.append(center + basis * point)
			_art_polygon(material, points, basis * normal, tint)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var points: Array = []
				for sa in [-1.0, 1.0]:
					for state in [0, 1]:
						var point := Vector3.ZERO
						point[axis] = sa * (half[axis] - cut)
						point[u] = su * (half[u] - cut * state)
						point[v] = sv * (half[v] - cut * (1 - state))
						points.append(center + basis * point)
				var normal := Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				_art_polygon(material, [points[0], points[1], points[3], points[2]], basis * normal, tint)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var signs := Vector3(sx, sy, sz)
				var points: Array = []
				for axis in range(3):
					var point := signs * (half - Vector3.ONE * cut)
					point[axis] = signs[axis] * half[axis]
					points.append(center + basis * point)
				_art_polygon(material, points, basis * signs, tint)


func _box(label: String, point: Vector3, size: Vector3, factory: Node3D, walkable: bool = true) -> StaticBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	return _surface(label, mesh, shape, point, factory, walkable)


func _ramp(label: String, x: float, start: float, end: float, low: float, high: float, factory: Node3D) -> void:
	var points := PackedVector3Array([
		Vector3(x - 1.9, -0.05, start), Vector3(x + 1.9, -0.05, start),
		Vector3(x - 1.9, -0.05, end), Vector3(x + 1.9, -0.05, end),
		Vector3(x - 1.9, low, start), Vector3(x + 1.9, low, start),
		Vector3(x - 1.9, high, end), Vector3(x + 1.9, high, end)])
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in [[4, 5, 6], [5, 7, 6], [0, 4, 2], [4, 6, 2], [1, 3, 5], [5, 3, 7], [0, 1, 4], [1, 5, 4], [2, 6, 3], [3, 6, 7]]:
		for index in triangle:
			builder.set_uv(Vector2(points[index].x * 0.3, points[index].z * 0.3))
			builder.add_vertex(points[index])
	builder.generate_normals()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	_surface(label, builder.commit(), shape, Vector3.ZERO, factory)


func _surface(label: String, mesh: Mesh, shape: Shape3D, point: Vector3, factory: Node3D, walkable: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("vfx_surface", "metal")
	body.set_meta("blocks_projectiles", true)
	body.set_meta("blocks_line_of_sight", true)
	body.set_meta("blocks_navigation", not walkable)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	if walkable and mesh is BoxMesh:
		# Inset the visible core so its cream armor is not hidden by the solid
		# box faces. The original shape remains the exact gameplay envelope.
		var core := mesh.duplicate() as BoxMesh
		core.size.x -= 0.12
		core.size.z -= 0.12
		visual.mesh = core
	visual.material_override = BRIDGE_MATERIALS[0]
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	# Only floor/ramp bodies are excluded from actor collisions and navigation.
	if walkable:
		surfaces.append(body)
	return body
