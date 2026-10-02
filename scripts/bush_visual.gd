extends Node3D

const FOLIAGE_SHADER: Shader = preload("res://scripts/bush_foliage.gdshader")
const BLADE_COUNT := 184
const FOOTPRINT_SEGMENTS := 48
const GOLDEN_ANGLE := 2.39996323

var _radius := 1.28
var _height := 2.35
var _foliage_material: ShaderMaterial
var _local_player: Node3D
var _resolve_clock := 0.0


func setup(radius: float, height: float, seed_value: int) -> void:
	_radius = radius
	_height = height
	var random := RandomNumberGenerator.new()
	random.seed = absi(seed_value)
	_create_footprint(random)
	_create_foliage(random)
	set_meta("foliage_blade_count", BLADE_COUNT)
	set_meta("foliage_draw_calls", 2)
	set_meta("foliage_radius", radius)
	set_meta("foliage_height", height)


func _process(delta: float) -> void:
	if _foliage_material == null:
		return
	_resolve_clock -= delta
	if not is_instance_valid(_local_player) and _resolve_clock <= 0.0:
		_resolve_clock = 0.5
		var scene := get_tree().current_scene
		if scene != null:
			var flow := scene.get_node_or_null("Interface")
			_local_player = flow.get("player") as Node3D if flow != null else scene.get_node_or_null("Player") as Node3D
	var influence := 0.0
	if is_instance_valid(_local_player):
		var relative := to_local(_local_player.global_position)
		if Vector2(relative.x, relative.z).length() <= _radius + 0.6:
			influence = 1.0
			_foliage_material.set_shader_parameter("local_actor_position", relative)
	# Only the local player parts the grass. Hidden opponent positions are never
	# passed to the shader, so foliage cannot give away their movement or presence.
	_foliage_material.set_shader_parameter("local_actor_influence", influence)


func set_local_player(player: Node3D) -> void:
	_local_player = player
	_resolve_clock = 0.0


func _create_footprint(random: RandomNumberGenerator) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.append(Vector3(0.0, 0.003, 0.0))
	normals.append(Vector3.UP)
	colors.append(Color("#344239"))
	# The outer contour is the exact hiding radius. A muted moss/soil lip makes
	# entry legible without an artificial glowing gameplay ring.
	for ring in range(2):
		var ring_radius := _radius * (0.76 if ring == 0 else 1.0)
		for index in range(FOOTPRINT_SEGMENTS):
			var angle := TAU * float(index) / float(FOOTPRINT_SEGMENTS)
			vertices.append(Vector3(cos(angle) * ring_radius, 0.003, sin(angle) * ring_radius))
			normals.append(Vector3.UP)
			var color := Color("#46533c") if ring == 0 else Color("#776b49")
			colors.append(color.darkened(random.randf_range(0.0, 0.10)))
	for index in range(FOOTPRINT_SEGMENTS):
		var next := (index + 1) % FOOTPRINT_SEGMENTS
		var inside := 1 + index
		var inside_next := 1 + next
		var outside := 1 + FOOTPRINT_SEGMENTS + index
		var outside_next := 1 + FOOTPRINT_SEGMENTS + next
		# Godot uses clockwise front faces. Keep the soil patch facing the top
		# camera; upward vertex normals alone do not prevent back-face culling.
		indices.append_array(PackedInt32Array([0, inside, inside_next, inside, outside, inside_next, outside, outside_next, inside_next]))
	var mesh_arrays: Array = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_COLOR] = colors
	mesh_arrays[Mesh.ARRAY_INDEX] = indices
	var footprint := MeshInstance3D.new()
	footprint.name = "OrganicFootprint"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	footprint.mesh = mesh
	footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	footprint.material_override = material
	add_child(footprint)


func _create_foliage(random: RandomNumberGenerator) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var palette: Array[Color] = [Color("#687749"), Color("#87904c"), Color("#a49d5c"), Color("#bcaa60"), Color("#5d7351")]
	var clump_phase := random.randf_range(0.0, TAU)
	for blade_index in range(BLADE_COUNT):
		# Sunflower distribution covers the whole circular hiding volume. Shorter
		# rim leaves and taller inner tufts form an organic, readable high-grass mass.
		var fraction := sqrt((float(blade_index) + 0.5) / float(BLADE_COUNT))
		var angle := float(blade_index) * GOLDEN_ANGLE + random.randf_range(-0.11, 0.11)
		var radial := _radius * fraction * 0.94
		var base := Vector3(cos(angle) * radial, 0.0, sin(angle) * radial)
		# Three loose tufts replace the uniform cone. The footprint and hiding
		# volume remain the same, with tall inner leaves and a shorter readable rim.
		var tuft := 0.5 + 0.5 * sin(angle * 3.0 + clump_phase)
		var blade_height := _height * random.randf_range(0.54, 0.98) * lerpf(0.80, 1.0, tuft) * lerpf(1.0, 0.69, pow(fraction, 3.0))
		var heading := angle + random.randf_range(-1.4, 1.4)
		var direction := Vector3(cos(heading), 0.0, sin(heading))
		var side := Vector3(-sin(heading), 0.0, cos(heading))
		var lean := minf(random.randf_range(0.20, 0.54) * _radius, _radius - radial)
		var width := random.randf_range(0.060, 0.12) * _radius
		var leaf_color: Color = palette[random.randi_range(0, palette.size() - 1)]
		if blade_index % 13 == 0:
			leaf_color = Color("#bfac5c")
		var points: Array[Vector3] = []
		var levels := [0.0, 0.36, 0.76, 1.0]
		var widths := [0.28, 1.0, 0.48, 0.0]
		for level in range(4):
			var t := float(levels[level])
			var centre := base + Vector3.UP * blade_height * (t - 0.12 * t * t * t) + direction * lean * t * t
			var half_width := width * float(widths[level])
			points.append(centre - side * half_width)
			points.append(centre + direction * width * 0.30 * sin(t * PI))
			points.append(centre + side * half_width)
		for segment in range(3):
			for fold in range(2):
				var low := segment * 3 + fold
				var high := (segment + 1) * 3 + fold
				_append_leaf_triangle(vertices, normals, colors, uvs, points[low], points[high], points[low + 1], float(levels[segment]), float(levels[segment + 1]), float(levels[segment]), leaf_color, fold)
				if segment < 2:
					_append_leaf_triangle(vertices, normals, colors, uvs, points[low + 1], points[high], points[high + 1], float(levels[segment]), float(levels[segment + 1]), float(levels[segment + 1]), leaf_color, fold)
	var mesh_arrays: Array = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_COLOR] = colors
	mesh_arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	var foliage := MeshInstance3D.new()
	foliage.name = "LayeredHighGrass"
	foliage.mesh = mesh
	foliage.extra_cull_margin = 0.45
	foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_foliage_material = ShaderMaterial.new()
	_foliage_material.shader = FOLIAGE_SHADER
	_foliage_material.set_shader_parameter("wind_phase", random.randf_range(0.0, TAU))
	foliage.material_override = _foliage_material
	add_child(foliage)


func _append_leaf_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, ta: float, tb: float, tc: float, leaf_color: Color, fold: int) -> void:
	var normal := (b - a).cross(c - a).normalized()
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))
	for t in [ta, tb, tc]:
		var gradient := Color("#3b4432").lerp(leaf_color, smoothstep(0.0, 0.75, float(t)))
		gradient = gradient.lerp(Color("#c7b77b"), maxf(0.0, float(t) - 0.72) * 0.48)
		# Shader ALBEDO expects linear RGB. Authored hex colours are sRGB;
		# converting here prevents the Mobile renderer washing the leaves out.
		colors.append(gradient.darkened(0.09 if fold == 0 else 0.0).srgb_to_linear())
		uvs.append(Vector2(float(fold), float(t)))
