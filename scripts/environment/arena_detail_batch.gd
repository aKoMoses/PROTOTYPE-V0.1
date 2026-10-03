extends RefCounted
## Small architectural details grouped by material. No physics or map globals.
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var triangles := 0

func _surface(material: Material) -> SurfaceTool:
	if not _surfaces.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = surface
		_materials[material] = material
	return _surfaces[material]

func triangle(material: Material, a: Vector3, b: Vector3, c: Vector3) -> void:
	var face_normal := (c - a).cross(b - a)
	if face_normal.length_squared() < 0.0000000001:
		return
	var surface := _surface(material)
	var normal := face_normal.normalized()
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		var uv := Vector2(vertex.z, -vertex.y) if absf(normal.x) > 0.7 else Vector2(vertex.x, -vertex.y) if absf(normal.z) > 0.7 else Vector2(vertex.x, vertex.z)
		surface.set_uv(uv * 0.35)
		surface.add_vertex(vertex)
	triangles += 1

func quad(material: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	triangle(material, a, b, c)
	triangle(material, a, c, d)

func triangle_uv(material: Material, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	var face_normal := (c - a).cross(b - a)
	if face_normal.length_squared() < 0.0000000001:
		return
	var surface := _surface(material)
	var normal := face_normal.normalized()
	var points := [a, b, c]
	var uvs := [uv_a, uv_b, uv_c]
	for index in range(3):
		surface.set_normal(normal)
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])
	triangles += 1

func box(material: Material, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var points: Array[Vector3] = []
	for point in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]:
		points.append(center + basis * (point * size * 0.5))
	for face in [[0,3,2,1], [4,5,6,7], [0,4,7,3], [1,2,6,5], [3,7,6,2], [0,1,5,4]]:
		quad(material, points[face[0]], points[face[3]], points[face[2]], points[face[1]])

func beam(material: Material, a: Vector3, b: Vector3, width: float) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001:
		return
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	box(material, (a + b) * 0.5, Vector3(width, width, direction.length()), Basis.looking_at(direction.normalized(), up))

func _outward_triangle(material: Material, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (c - a).cross(b - a).dot(outward) < 0.0:
		triangle(material, a, c, b)
	else:
		triangle(material, a, b, c)

func _outward_quad(material: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_outward_triangle(material, a, b, c, outward)
	_outward_triangle(material, a, c, d, outward)

func beveled_box(material: Material, center: Vector3, size: Vector3, bevel: float = 0.04, basis: Basis = Basis.IDENTITY) -> void:
	var edge := minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.24)
	var layers: Array[PackedVector3Array] = []
	for layer in range(4):
		var inset := edge if layer in [0, 3] else 0.0
		var x := size.x * 0.5 - inset
		var z := size.z * 0.5 - inset
		var cut := edge * 0.55 if layer in [0, 3] else edge * 1.55
		var y := -size.y * 0.5 if layer == 0 else -size.y * 0.5 + edge if layer == 1 else size.y * 0.5 - edge if layer == 2 else size.y * 0.5
		var ring_points := PackedVector3Array()
		for p in [Vector2(-x + cut, -z), Vector2(x - cut, -z), Vector2(x, -z + cut), Vector2(x, z - cut), Vector2(x - cut, z), Vector2(-x + cut, z), Vector2(-x, z - cut), Vector2(-x, -z + cut)]:
			ring_points.append(center + basis * Vector3(p.x, y, p.y))
		layers.append(ring_points)
	for layer in range(3):
		for index in range(8):
			var next := (index + 1) % 8
			var a := layers[layer][index]
			var b := layers[layer][next]
			var c := layers[layer + 1][next]
			var d := layers[layer + 1][index]
			_outward_quad(material, a, b, c, d, (a + b + c + d) * 0.25 - center)
	for layer in [0, 3]:
		for index in range(1, 7):
			_outward_triangle(material, layers[layer][0], layers[layer][index], layers[layer][index + 1], basis * Vector3.UP * (-1.0 if layer == 0 else 1.0))

func cylinder(material: Material, center: Vector3, radius: float, height: float, basis: Basis = Basis.IDENTITY, segments: int = 16) -> void:
	var top := center + basis * Vector3.UP * height * 0.5
	var bottom := center - basis * Vector3.UP * height * 0.5
	for index in segments:
		var a := TAU * float(index) / float(segments)
		var b := TAU * float(index + 1) / float(segments)
		var va := basis * Vector3(cos(a), 0, sin(a)) * radius
		var vb := basis * Vector3(cos(b), 0, sin(b)) * radius
		_outward_triangle(material, top, top + va, top + vb, basis * Vector3.UP)
		_outward_triangle(material, bottom, bottom + vb, bottom + va, basis * Vector3.DOWN)
		_outward_quad(material, bottom + va, bottom + vb, top + vb, top + va, va + vb)

func pipe(material: Material, a: Vector3, b: Vector3, radius: float, segments: int = 12) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001:
		return
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	var basis := Basis.looking_at(direction.normalized(), up) * Basis(Vector3.RIGHT, PI * 0.5)
	cylinder(material, (a + b) * 0.5, radius, direction.length(), basis, segments)

func ring(material: Material, center: Vector3, radius: float, width: float, height: float, basis: Basis = Basis.IDENTITY, segments: int = 24) -> void:
	for index in segments:
		var a := TAU * float(index) / float(segments)
		var b := TAU * float(index + 1) / float(segments)
		var points: Array[Vector3] = []
		for y in [-height * 0.5, height * 0.5]:
			for r in [radius - width * 0.5, radius + width * 0.5]:
				for angle in [a, b]:
					points.append(center + basis * Vector3(cos(angle) * r, y, sin(angle) * r))
		# Bottom, top, outside and inside; the contiguous segments share seams.
		quad(material, points[0], points[1], points[3], points[2])
		quad(material, points[4], points[6], points[7], points[5])
		quad(material, points[2], points[3], points[7], points[6])
		quad(material, points[1], points[0], points[4], points[5])

func leaf(material: Material, origin: Vector3, direction: Vector3, length: float, width: float, rise: float) -> void:
	var forward := direction.normalized()
	var side := Vector3(-forward.z, 0, forward.x).normalized()
	var previous_left := origin
	var previous_right := origin
	for step in range(1, 6):
		var t := float(step) / 5.0
		var center := origin + forward * length * t + Vector3.UP * (sin(t * PI) * rise + t * rise * 0.32)
		var half_width := sin(t * PI) * width * 0.5
		var left := center - side * half_width
		var right := center + side * half_width
		quad(material, previous_left, left, right, previous_right)
		previous_left = left
		previous_right = right

func flush(parent: Node3D, label: String) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for material in _surfaces:
		var mesh := MeshInstance3D.new()
		mesh.name = label + str(meshes.size())
		mesh.mesh = (_surfaces[material] as SurfaceTool).commit()
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.set_meta("visual_only", true)
		parent.add_child(mesh)
		meshes.append(mesh)
	parent.set_meta("triangles", triangles)
	parent.set_meta("detail_batches", meshes.size())
	_surfaces.clear()
	_materials.clear()
	return meshes
