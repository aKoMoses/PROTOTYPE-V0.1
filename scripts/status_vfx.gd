extends Node3D

## Presentation only: CombatState owns all durations, stacking and damage.
const DATA := preload("res://scripts/combat_data.gd")
const EFFECTS := [DATA.EFFECT_BURN, DATA.EFFECT_SLOW, DATA.EFFECT_STUN, DATA.EFFECT_SPOTTED]

@export_range(0.25, 1.0) var particle_density := 1.0
@export_range(1.8, 4.0) var marker_height := 3.30

static var _textures: Dictionary = {}
var _groups: Dictionary = {}
var _emitters: Dictionary = {}
var _active: Array[String] = []
var _clock := 0.0
var _stun_arcs: Node3D
var _stun_symbol: MeshInstance3D
var _spotted_symbol: MeshInstance3D
var _slow_ring: MeshInstance3D
var _stun_timer := 0.0
var _stun_remaining := 0.0
var _rng := RandomNumberGenerator.new()


func configure(actor: Node3D) -> void:
	if not _groups.is_empty():
		return
	if get_parent() == null:
		actor.add_child(self)
	name = "StatusVFX"
	_rng.randomize()
	_build_burn()
	_build_slow()
	_build_stun()
	_build_spotted()
	clear()


func sync(active_effects: Array) -> void:
	for effect: String in EFFECTS:
		var enabled := active_effects.has(effect)
		if enabled == _active.has(effect):
			continue
		if enabled:
			_active.append(effect)
		else:
			_active.erase(effect)
		var group := _groups.get(effect) as Node3D
		if group != null:
			group.visible = enabled
		for emitter: GPUParticles3D in _emitters.get(effect, []):
			emitter.emitting = enabled
			if enabled:
				emitter.restart()
		if effect == DATA.EFFECT_STUN:
			_stun_timer = 0.0
			_stun_remaining = 0.0
			_stun_arcs.visible = false
	set_process(not _active.is_empty())


func clear() -> void:
	sync([])
	_clock = 0.0
	set_process(false)


func get_active_effects() -> Array[String]:
	return _active.duplicate()


func get_debug_counts() -> Dictionary:
	var emitter_count := 0
	var emitting_count := 0
	for emitters: Array in _emitters.values():
		for emitter: GPUParticles3D in emitters:
			emitter_count += 1
			if emitter.emitting:
				emitting_count += emitter.amount
	return {"active_effects": _active.size(), "particle_emitters": emitter_count, "emitting_particles": emitting_count, "lights": 0}


func _process(delta: float) -> void:
	_clock += delta
	if not is_visible_in_tree():
		return
	if _active.has(DATA.EFFECT_STUN):
		_stun_timer -= delta
		_stun_remaining = maxf(0.0, _stun_remaining - delta)
		if _stun_timer <= 0.0:
			_stun_timer = _rng.randf_range(0.18, 0.34)
			_stun_remaining = _rng.randf_range(0.065, 0.105)
			_stun_arcs.rotation.y = _rng.randf_range(-PI, PI)
			_stun_arcs.visible = _stun_remaining > 0.0
		_stun_symbol.scale = Vector3.ONE * (1.10 if _stun_remaining > 0.0 else 1.0)
	if _active.has(DATA.EFFECT_SPOTTED):
		var scan_pulse := pow(maxf(0.0, sin(_clock * 3.6)), 10.0) * 0.08
		_spotted_symbol.scale = Vector3.ONE * (1.0 + sin(_clock * 4.2) * 0.065 + scan_pulse)
	if _active.has(DATA.EFFECT_SLOW) and _slow_ring != null:
		_slow_ring.rotation.y += delta * 0.42
		var slow_material := _slow_ring.material_override as StandardMaterial3D
		if slow_material != null:
			slow_material.albedo_color.a = 0.34 + sin(_clock * 2.8) * 0.08
	# Fixed left/right tactical slots flank the health readout instead of covering it.
	_stun_symbol.position = Vector3(-2.25, marker_height, 0.0)
	_spotted_symbol.position = Vector3(2.25, marker_height, 0.0)
	_face_camera(_stun_symbol)
	_face_camera(_spotted_symbol)


func _face_camera(symbol: Node3D) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		symbol.global_basis = camera.global_basis.orthonormalized().scaled(symbol.scale)


func _group(effect: String, group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	group.visible = false
	add_child(group)
	_groups[effect] = group
	_emitters[effect] = []
	return group


func _build_burn() -> void:
	var group := _group(DATA.EFFECT_BURN, "Burn")
	var flame := _particles(group, DATA.EFFECT_BURN, "LocalizedFlame", 12, 0.42, Vector3(0.0, 0.88, 0.0), Vector3(0.32, 0.38, 0.23), Vector2(0.28, 0.62), Color("#ff5838"), 1.85, "flame")
	var flame_process := flame.process_material as ParticleProcessMaterial
	flame_process.initial_velocity_min = 0.45
	flame_process.initial_velocity_max = 0.90
	flame_process.gravity = Vector3(0.0, 0.35, 0.0)
	flame_process.spread = 12.0
	flame_process.color_ramp = _ramp([Color(1.0, 0.91, 0.55, 0.0), Color(1.0, 0.35, 0.16, 0.90), Color(0.38, 0.045, 0.02, 0.0)])
	var ember := _particles(group, DATA.EFFECT_BURN, "Embers", 8, 0.55, Vector3(0.0, 1.03, 0.0), Vector3(0.34, 0.36, 0.26), Vector2(0.055, 0.12), Color("#ffe0a0"), 1.75, "shard")
	var ember_process := ember.process_material as ParticleProcessMaterial
	ember_process.initial_velocity_min = 0.65
	ember_process.initial_velocity_max = 1.35
	ember_process.spread = 26.0
	var smoke := _particles(group, DATA.EFFECT_BURN, "BurnSmoke", 5, 0.76, Vector3(0.0, 1.36, 0.0), Vector3(0.27, 0.14, 0.19), Vector2(0.36, 0.34), Color(0.16, 0.18, 0.20, 0.32), 0.0, "soft")
	var smoke_process := smoke.process_material as ParticleProcessMaterial
	smoke_process.initial_velocity_min = 0.30
	smoke_process.initial_velocity_max = 0.65
	smoke_process.scale_curve = _size_curve([0.35, 0.78, 1.15])


func _build_slow() -> void:
	var group := _group(DATA.EFFECT_SLOW, "Slow")
	_slow_ring = _broken_ground_ring(group, 0.70, 0.045, Color(0.30, 0.66, 0.76, 0.42))
	_slow_ring.position.y = 0.055
	var mist := _particles(group, DATA.EFFECT_SLOW, "ColdCondensation", 9, 0.54, Vector3(0.0, 0.10, 0.0), Vector3(0.52, 0.07, 0.40), Vector2(0.52, 0.22), Color(0.32, 0.64, 0.73, 0.60), 0.45, "soft")
	var mist_process := mist.process_material as ParticleProcessMaterial
	mist_process.initial_velocity_min = 0.12
	mist_process.initial_velocity_max = 0.26
	mist_process.spread = 75.0
	var frost := _particles(group, DATA.EFFECT_SLOW, "FrostMotes", 7, 0.40, Vector3(0.0, 0.14, 0.0), Vector3(0.49, 0.08, 0.37), Vector2(0.065, 0.16), Color("#e0f9ff"), 1.05, "shard")
	var frost_process := frost.process_material as ParticleProcessMaterial
	frost_process.initial_velocity_min = 0.12
	frost_process.initial_velocity_max = 0.32
	frost_process.spread = 48.0


func _build_stun() -> void:
	var group := _group(DATA.EFFECT_STUN, "Stun")
	_stun_arcs = Node3D.new()
	_stun_arcs.name = "IntermittentArcs"
	group.add_child(_stun_arcs)
	for side in [-1.0, 1.0]:
		var points := PackedVector3Array([
			Vector3(side * 0.32, 0.76, 0.28), Vector3(side * 0.49, 0.98, 0.32),
			Vector3(side * 0.38, 1.13, 0.35), Vector3(side * 0.51, 1.38, 0.27),
		])
		_line_mesh(_stun_arcs, points, 0.028, Color("#ffe1a0"))
	_stun_symbol = _line_mesh(group, PackedVector3Array([
		Vector3(0.17, 0.28, 0.0), Vector3(-0.10, 0.025, 0.0),
		Vector3(0.10, 0.025, 0.0), Vector3(-0.17, -0.28, 0.0),
	]), 0.048, Color("#ffe1a0"), true)
	_stun_symbol.name = "StunMarker"
	_stun_symbol.position.y = marker_height


func _build_spotted() -> void:
	var group := _group(DATA.EFFECT_SPOTTED, "Spotted")
	_spotted_symbol = _line_mesh(group, PackedVector3Array([
		Vector3(-0.36, 0.0, 0.0), Vector3(-0.17, 0.17, 0.0),
		Vector3(0.17, 0.17, 0.0), Vector3(0.36, 0.0, 0.0),
		Vector3(0.17, -0.17, 0.0), Vector3(-0.17, -0.17, 0.0),
		Vector3(-0.36, 0.0, 0.0),
	]), 0.040, Color("#bbecdb"), true)
	_spotted_symbol.name = "TacticalEye"
	_spotted_symbol.position.y = marker_height
	_line_mesh(_spotted_symbol, PackedVector3Array([Vector3(0.0, -0.085, 0.0), Vector3(0.0, 0.085, 0.0)]), 0.095, Color("#ecfff7"), true)


func _particles(parent: Node3D, effect: String, emitter_name: String, amount: int, lifetime: float, origin: Vector3, extents: Vector3, size: Vector2, color: Color, energy: float, texture_kind: String = "soft") -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = emitter_name
	particles.emitting = false
	particles.amount = maxi(2, roundi(float(amount) * particle_density))
	particles.lifetime = lifetime
	particles.preprocess = lifetime * 0.25
	particles.local_coords = true
	particles.fixed_fps = 30
	particles.visibility_aabb = AABB(Vector3(-1.0, -0.5, -1.0), Vector3(2.0, 3.0, 2.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = origin
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 20.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.7
	process.scale_min = 0.65
	process.scale_max = 1.15
	process.angle_min = -15.0
	process.angle_max = 15.0
	process.color_ramp = _ramp([Color(color, 0.0), color, Color(color, 0.0)])
	process.scale_curve = _size_curve([0.35, 1.0, 0.2])
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _texture(texture_kind)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = energy
	quad.material = material
	particles.draw_pass_1 = quad
	parent.add_child(particles)
	_emitters[effect].append(particles)
	return particles


func _line_mesh(parent: Node3D, points: PackedVector3Array, width: float, color: Color, always_visible: bool = false) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var side := (end - start).cross(Vector3.FORWARD).normalized() * width * 0.5
		for point in [start - side, start + side, end + side, start - side, end + side, end - side]:
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 1.20
	material.no_depth_test = always_visible
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _broken_ground_ring(parent: Node3D, radius: float, width: float, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 24
	for index in range(segments):
		# Two missing facets per quadrant give the ring a mechanical, fractured read.
		if index % 6 >= 4:
			continue
		var angle_a := TAU * float(index) / float(segments)
		var angle_b := TAU * float(index + 1) / float(segments)
		var inner := radius - width * 0.5
		var outer := radius + width * 0.5
		var inner_a := Vector3(cos(angle_a) * inner, 0.0, sin(angle_a) * inner)
		var outer_a := Vector3(cos(angle_a) * outer, 0.0, sin(angle_a) * outer)
		var inner_b := Vector3(cos(angle_b) * inner, 0.0, sin(angle_b) * inner)
		var outer_b := Vector3(cos(angle_b) * outer, 0.0, sin(angle_b) * outer)
		for point in [inner_a, outer_a, outer_b, inner_a, outer_b, inner_b]:
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "BrokenColdRing"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 0.65
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _ramp(colors: Array[Color]) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.20, 1.0])
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _size_curve(values: Array[float]) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 1.5
	curve.add_point(Vector2(0.0, values[0]))
	curve.add_point(Vector2(0.3, values[1]))
	curve.add_point(Vector2(1.0, values[2]))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _texture(kind: String) -> ImageTexture:
	if _textures.has(kind):
		return _textures[kind]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(16.0, 16.0)) / 16.0
			var alpha := 0.0
			match kind:
				"flame":
					var vertical := clampf((uv.y + 1.0) * 0.5, 0.0, 1.0)
					var flame_width := lerpf(0.18, 0.82, vertical)
					var flame_distance := Vector2(uv.x / flame_width, (uv.y + 0.04) * 0.92).length()
					alpha = pow(maxf(0.0, 1.0 - flame_distance), 1.20)
				"shard":
					alpha = pow(maxf(0.0, 1.0 - absf(uv.x) * 1.45 - absf(uv.y) * 0.82), 0.72)
				_:
					alpha = pow(maxf(0.0, 1.0 - uv.length()), 1.5)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_textures[kind] = ImageTexture.create_from_image(image)
	return _textures[kind]
