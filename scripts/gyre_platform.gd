extends Node3D

## Fixed raised deck. Only the surrounding floor carries fighters in orbit.
const HEIGHT := 1.8
const HALF_DECK := Vector2(2.8, 2.5)
const HALF_RAMP_WIDTH := 1.6
const RAMP_END := 6.8
var surfaces: Array[StaticBody3D] = []
var _half_size := Vector2(12.5, 11.25)

func configure(stage: Node3D) -> void:
	_half_size = stage.get("_definition").half_size
	var materials: Dictionary = stage.get("_materials")
	var deck_material := StandardMaterial3D.new()
	deck_material.albedo_color = Color("#82919b")
	deck_material.roughness = 0.72
	deck_material.metallic = 0.35
	_box("RaisedFoundryDeck", Vector3(0, HEIGHT * 0.5, 0), Vector3(HALF_DECK.x * 2, HEIGHT, HALF_DECK.y * 2), materials.foundry_steel, true)
	for column in [-1.0, 1.0]:
		for row in range(3):
			_box("DeckPlate", Vector3(column * 1.29, HEIGHT + 0.012, (row - 1) * 1.57), Vector3(2.5, 0.024, 1.49), deck_material, false, false)
	for side in [-1.0, 1.0]:
		_ramp(side, deck_material)
		_box("DeckShield", Vector3(side * 2.48, HEIGHT + 0.6, 0), Vector3(0.38, 1.2, 1.8), materials.cast_iron, false)
		_box("ShieldCap", Vector3(side * 2.48, HEIGHT + 1.21, 0), Vector3(0.42, 0.04, 1.88), materials.foundry_ochre, false, false)
		_box("DeckEdgeBeam", Vector3(side * 2.7, HEIGHT - 0.06, 0), Vector3(0.16, 0.12, 5), materials.foundry_ochre, false, false)
		for index in range(8):
			var z: float = side * (HALF_DECK.y + (index + 0.5) * (RAMP_END - HALF_DECK.y) / 8)
			var rib := _box("RampGrip", Vector3(0, height_at(Vector3(0, 0, z)) + 0.018, z), Vector3(2.8, 0.024, 0.07), materials.foundry_ochre, false, false)
			rib.rotation.x = side * atan(HEIGHT / (RAMP_END - HALF_DECK.y))

func height_at(point: Vector3) -> float:
	if absf(point.x) <= HALF_DECK.x and absf(point.z) <= HALF_DECK.y:
		return HEIGHT
	if absf(point.x) <= HALF_RAMP_WIDTH and absf(point.z) > HALF_DECK.y and absf(point.z) <= RAMP_END:
		return HEIGHT * (RAMP_END - absf(point.z)) / (RAMP_END - HALF_DECK.y)
	return 0.0

func segment_walkable(origin: Vector3, destination: Vector3) -> bool:
	var outline := preload("res://scripts/compact_arena_catalog.gd").footprint("gyre")
	if not Geometry2D.is_point_in_polygon(Vector2(destination.x, destination.z), outline):
		return false
	var steps := maxi(1, ceili(Vector2(destination.x - origin.x, destination.z - origin.z).length() / 0.10))
	var previous := height_at(origin)
	for index in range(1, steps + 1):
		var level := height_at(origin.lerp(destination, float(index) / steps))
		if absf(level - previous) > 0.16:
			return false
		previous = level
	return true

func navigation_extent() -> float:
	return _half_size.x - 0.6

func _box(label: String, at: Vector3, size: Vector3, material: Material, walkable: bool, solid: bool = true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	return _surface(label, at, mesh, shape, material, walkable, solid)

func _ramp(side: float, material: Material) -> void:
	var start := side * HALF_DECK.y
	var end := side * RAMP_END
	var points := PackedVector3Array([
		Vector3(-HALF_RAMP_WIDTH, -0.04, start), Vector3(HALF_RAMP_WIDTH, -0.04, start),
		Vector3(-HALF_RAMP_WIDTH, -0.04, end), Vector3(HALF_RAMP_WIDTH, -0.04, end),
		Vector3(-HALF_RAMP_WIDTH, HEIGHT, start), Vector3(HALF_RAMP_WIDTH, HEIGHT, start),
		Vector3(-HALF_RAMP_WIDTH, 0, end), Vector3(HALF_RAMP_WIDTH, 0, end)])
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in [[4, 6, 5], [5, 6, 7], [0, 2, 4], [4, 2, 6], [1, 5, 3], [5, 7, 3], [0, 4, 1], [1, 4, 5], [2, 3, 6], [3, 7, 6]]:
		if side < 0:
			triangle.reverse()
		for index in triangle:
			builder.add_vertex(points[index])
	builder.generate_normals()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	_surface("AccessRamp", Vector3.ZERO, builder.commit(), shape, material, true, true)

func _surface(label: String, at: Vector3, mesh: Mesh, shape: Shape3D, material: Material, walkable: bool, solid: bool) -> Node3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name = label
	body.position = at
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	if solid:
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("arena_solid")
		body.set_meta("blocks_navigation", not walkable)
		body.set_meta("blocks_projectiles", true)
		body.set_meta("blocks_line_of_sight", true)
		body.set_meta("vfx_surface", "metal")
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		if walkable:
			surfaces.append(body)
	return body
