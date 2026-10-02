extends RefCounted
## Cached, deterministic presentation assets. Never uses combat's random stream.

static var _textures: Dictionary = {}
static var _particles: Dictionary = {}


static func texture(kind: String, variant: int = 0) -> Texture2D:
	var key := kind + str(variant)
	if _textures.has(key):
		return _textures[key]
	var noise := FastNoiseLite.new()
	noise.seed = 1709 + variant * 113
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var uv := (Vector2(x, y) - Vector2.ONE * 63.5) / 63.5
			var radius := uv.length()
			var angle := atan2(uv.y, uv.x)
			var grain := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var edge := 0.74 + sin(angle * 5.0 + variant) * 0.07 + sin(angle * 9.0 - variant) * 0.045
			var alpha := (1.0 - smoothstep(edge * 0.24, edge, radius)) * (0.36 + grain * 0.64)
			if kind == "decal":
				var core := 1.0 - smoothstep(0.08, 0.32 + grain * 0.12, radius)
				var soot := (1.0 - smoothstep(0.28, edge, radius)) * grain * 0.42
				var cracks := pow(maxf(0.0, cos(angle * 7.0 + radius * 5.0 + variant)), 36.0)
				cracks *= smoothstep(0.20, 0.36, radius) * (1.0 - smoothstep(edge * 0.65, edge, radius))
				alpha = clampf(core * 0.90 + soot + cracks * 0.72, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var result := ImageTexture.create_from_image(image)
	_textures[key] = result
	return result


static func particle_mesh(style: String) -> Mesh:
	if _particles.has(style):
		return _particles[style]
	var mesh: Mesh
	if style == "dust":
		mesh = QuadMesh.new()
	else:
		var shape := ImmediateMesh.new()
		shape.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		# A tapered spindle along velocity, a chipped plate, or an energy diamond.
		var tip := Vector3(0.0, 2.2 if style == "spark" else 0.65, 0.0)
		var tail := Vector3(0.0, -1.6 if style == "spark" else -0.50, 0.0)
		var radius := 0.22 if style == "spark" else 0.50
		for side in range(4):
			var angle_a := TAU * side / 4.0
			var angle_b := TAU * (side + 1) / 4.0
			var a := Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
			var b := Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
			if style == "debris":
				a.y = 0.20 if side % 2 == 0 else -0.12
				a.z *= 0.22
				b.z *= 0.22
			for point in [tip, a, b, tail, b, a]:
				shape.surface_add_vertex(point)
		shape.surface_end()
		mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = style in ["spark", "energy"]
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.65
	if style == "dust":
		material.albedo_texture = texture("smoke", 2)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if mesh is ImmediateMesh:
		mesh.surface_set_material(0, material)
	else:
		(mesh as PrimitiveMesh).material = material
	_particles[style] = mesh
	return mesh
