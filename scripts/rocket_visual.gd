extends Node3D
## Cosmetic only. World-space particles and a timed ribbon follow the real trajectory.

const ASSETS := preload("res://scripts/vfx_assets.gd")
const FLAME := preload("res://scripts/rocket_visual.gdshader")
const BURST_GROUP := "prototype0_rocket_bursts"
const WAKE_GROUP := "prototype0_rocket_wakes"
const MAX_BURSTS := 12
const MAX_WAKES := 16
const TRAIL_LIFE := 0.18
static var _materials: Dictionary = {}

var _chassis: Node3D
var _exhaust: Node3D
var _wake: Node3D
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _ribbon: MeshInstance3D
var _health_bar: MeshInstance3D
var _health_back: MeshInstance3D
var _samples: Array[Dictionary] = []
var _heading := Vector3.FORWARD
var _previous_heading := Vector3.FORWARD
var _bank := 0.0
var _clock := 0.0
var _phase := 0.0
var _hit_time := 0.0
var _health_ratio := 1.0
var _finished := false
var _started := false


func _ready() -> void:
	name = "RocketVisual"
	process_priority = 40
	_phase = float(hash(str(get_parent().get("rocket_id"))) % 1024) / 1024.0 * TAU
	_build_chassis()
	_build_exhaust()
	_build_health()
	_wake = Node3D.new()
	_wake.name = "RocketWake"
	add_child(_wake)
	_smoke = _particles(_wake, "ExhaustSmoke", 28, 0.62, Vector2(0.25, 0.25), false)
	_smoke.emitting = false
	var smoke_process := _smoke.process_material as ParticleProcessMaterial
	smoke_process.initial_velocity_min = 0.3
	smoke_process.initial_velocity_max = 0.7
	smoke_process.gravity = Vector3(0, 0.45, 0)
	smoke_process.spread = 16.0
	smoke_process.color_ramp = _ramp([Color("#d8bb91", 0.22), Color("#96958d", 0.30), Color("#687078", 0.0)])
	smoke_process.scale_curve = _curve([0.3, 1.1, 1.8])
	_embers = _particles(_wake, "ExhaustEmbers", 10, 0.22, Vector2(0.045, 0.10), true)
	_embers.emitting = false
	var ember_process := _embers.process_material as ParticleProcessMaterial
	ember_process.initial_velocity_min = 2.0
	ember_process.initial_velocity_max = 3.8
	ember_process.spread = 12.0
	ember_process.color_ramp = _ramp([Color("#fff1b0"), Color("#ff9a36"), Color("#ff501c", 0.0)])
	ember_process.scale_curve = _curve([0.4, 0.75, 0.0])
	_ribbon = _mesh(_wake, "HotWake", ImmediateMesh.new(), _material("ribbon", Color.WHITE, true, true))
	_ribbon.top_level = true
	_ribbon.global_transform = Transform3D.IDENTITY


func update_pose(heading: Vector3, health_ratio: float) -> void:
	if heading.length_squared() > 0.001:
		_heading = heading.normalized()
	if health_ratio < _health_ratio:
		_hit_time = 0.16
	_health_ratio = clampf(health_ratio, 0.0, 1.0)


func _process(delta: float) -> void:
	if _finished:
		return
	_clock += delta
	_hit_time = maxf(0.0, _hit_time - delta)
	# Bank the model through turns; never change the collision or flight direction.
	var turn := _previous_heading.cross(_heading).y / maxf(delta, 0.001)
	_bank = lerpf(_bank, clampf(-turn * 0.12, -0.42, 0.42), 1.0 - exp(-delta * 12.0))
	_previous_heading = _heading
	var up := Vector3.RIGHT if absf(_heading.dot(Vector3.UP)) > 0.97 else Vector3.UP
	_chassis.look_at(global_position + _heading, up)
	_chassis.rotate_object_local(Vector3.FORWARD, _bank + sin(_clock * 9.0 + _phase) * 0.022)
	_exhaust.global_transform = _chassis.global_transform
	var ignition := smoothstep(0.0, 0.12, _clock)
	var pulse := 1.0 + sin(_clock * 48.0 + _phase) * 0.09 + sin(_clock * 73.0 + _phase) * 0.035
	_exhaust.scale = Vector3(1.0, 1.0, (0.65 + ignition * 0.35) * pulse)
	_wake.global_transform = _chassis.global_transform
	_smoke.position = Vector3(0, 0, 0.39)
	_embers.position = Vector3(0, 0, 0.34)
	if not _started:
		_started = true
		_smoke.emitting = true
		_embers.emitting = true
	_health_bar.scale.x = maxf(0.01, _health_ratio)
	_health_bar.position.x = -0.16 * (1.0 - _health_ratio)
	# Intact missiles read by silhouette; show individual health when damaged.
	_health_bar.visible = _health_ratio < 0.999
	_health_back.visible = _health_bar.visible
	_chassis.scale = Vector3.ONE * (1.0 + _hit_time * 0.12)
	_update_ribbon()


func finish(normal: Vector3 = Vector3.UP, intercepted: bool = false) -> void:
	if _finished:
		return
	_finished = true
	var scene := get_tree().current_scene
	spawn_burst(scene, global_position, _heading, normal, intercepted)
	# Keep emitted smoke at its world position after the projectile is freed.
	_smoke.emitting = false
	_embers.emitting = false
	_ribbon.visible = false
	if is_instance_valid(scene) and _clock > 0.04:
		_limit(scene, WAKE_GROUP, MAX_WAKES)
		_wake.reparent(scene)
		_wake.add_to_group(WAKE_GROUP)
		_wake.add_to_group("prototype0_fx_budget")
		var wake := _wake
		wake.get_tree().create_timer(0.72, false).timeout.connect(wake.queue_free)


func _update_ribbon() -> void:
	var point := global_position - _heading * 0.34
	if not _samples.is_empty() and point.distance_to(_samples[0].point) > 3.0:
		_samples.clear() # A new network snapshot must not draw a line across the map.
	if _samples.is_empty() or point.distance_squared_to(_samples[0].point) > 0.0004:
		_samples.push_front({"point": point, "time": _clock})
	while not _samples.is_empty() and (_clock - float(_samples.back().time) > TRAIL_LIFE or _samples.size() > 20):
		_samples.pop_back()
	var mesh := _ribbon.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	var view := camera.global_basis.z if camera != null else Vector3.UP
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(_samples.size() - 1):
		var a: Vector3 = _samples[index].point
		var b: Vector3 = _samples[index + 1].point
		var side := (a - b).cross(view).normalized()
		var fade_a := 1.0 - clampf((_clock - float(_samples[index].time)) / TRAIL_LIFE, 0.0, 1.0)
		var fade_b := 1.0 - clampf((_clock - float(_samples[index + 1].time)) / TRAIL_LIFE, 0.0, 1.0)
		var width_a := side * 0.036 * fade_a
		var width_b := side * 0.036 * fade_b
		for vertex in [[a - width_a, fade_a], [a + width_a, fade_a], [b + width_b, fade_b], [a - width_a, fade_a], [b + width_b, fade_b], [b - width_b, fade_b]]:
			mesh.surface_set_color(Color(1.0, 0.48, 0.10, float(vertex[1]) * 0.55))
			mesh.surface_add_vertex(vertex[0])
	mesh.surface_end()


func _build_chassis() -> void:
	_chassis = Node3D.new()
	_chassis.name = "BankingChassis"
	add_child(_chassis)
	var paint := _material("paint", Color("#ded6b8"))
	var metal := _material("metal", Color("#343e47"))
	var copper := _material("copper", Color("#bd6b38"))
	var cyan := _material("seeker", Color("#67e5eb"), true)
	_cylinder(_chassis, "Warhead", 0.095, 0.112, 0.20, -0.29, paint)
	_cylinder(_chassis, "Nose", 0.0, 0.095, 0.15, -0.465, metal)
	_cylinder(_chassis, "SeekerBand", 0.096, 0.096, 0.028, -0.38, cyan)
	_cylinder(_chassis, "MotorHousing", 0.112, 0.105, 0.37, -0.005, paint)
	_cylinder(_chassis, "ArmourBand", 0.114, 0.114, 0.046, -0.15, copper)
	_cylinder(_chassis, "RearCollar", 0.108, 0.108, 0.055, 0.18, metal)
	_cylinder(_chassis, "Nozzle", 0.085, 0.055, 0.11, 0.26, metal)
	_cylinder(_chassis, "HotNozzle", 0.058, 0.058, 0.014, 0.32, _material("hot", Color("#ffc567"), true))
	for index in range(4):
		var fin := _mesh(_chassis, "SweptFin%d" % index, _fin_mesh(), metal)
		fin.rotation.z = float(index) * PI * 0.5 + PI * 0.25
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.036, 0.008, 0.10)
		var marking := _mesh(fin, "CopperTip", stripe, copper, Vector3(0.168, 0, 0.21))
		marking.rotation.y = -0.32
	# Long dark seams make the silhouette legible under the overhead game camera.
	for side in [-1.0, 1.0]:
		var rail := BoxMesh.new()
		rail.size = Vector3(0.015, 0.02, 0.23)
		_mesh(_chassis, "MotorSeam", rail, metal, Vector3(side * 0.08, 0.078, -0.015))


func _build_exhaust() -> void:
	_exhaust = Node3D.new()
	_exhaust.name = "PulsingExhaust"
	add_child(_exhaust)
	for inner in [false, true]:
		var flame := CylinderMesh.new()
		flame.top_radius = 0.002
		flame.bottom_radius = 0.052 if inner else 0.088
		flame.height = 0.29 if inner else 0.56
		flame.radial_segments = 12
		flame.rings = 4
		var material := ShaderMaterial.new()
		material.shader = FLAME
		material.set_shader_parameter("phase", _phase)
		if inner:
			material.set_shader_parameter("hot_color", Color("#fff7cd"))
			material.set_shader_parameter("tail_color", Color("#ffbe44"))
		var jet := _mesh(_exhaust, "WhiteCore" if inner else "AmberPlume", flame, material, Vector3(0, 0, 0.32 + flame.height * 0.5))
		jet.rotation.x = PI * 0.5


func _build_health() -> void:
	var background := QuadMesh.new()
	background.size = Vector2(0.37, 0.065)
	_health_back = _mesh(self, "DamagedHealthBack", background, _material("health_back", Color("#1b252b"), true), Vector3(0, 0.30, 0))
	var bar := QuadMesh.new()
	bar.size = Vector2(0.32, 0.035)
	_health_bar = _mesh(self, "DamagedHealth", bar, _material("health", Color("#ffd77f"), true), Vector3(0, 0.30, 0.004))
	for visual in [_health_back, _health_bar]:
		var material := visual.material_override as StandardMaterial3D
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		visual.visible = false


static func spawn_burst(scene: Node, center: Vector3, heading: Vector3 = Vector3.FORWARD, normal: Vector3 = Vector3.UP, intercepted: bool = false) -> Node3D:
	if not is_instance_valid(scene) or not scene.is_inside_tree():
		return null
	_limit(scene, BURST_GROUP, MAX_BURSTS)
	var effect := Node3D.new()
	effect.name = "RocketIntercept" if intercepted else "RocketImpact"
	scene.add_child(effect)
	effect.global_position = center
	effect.add_to_group(BURST_GROUP)
	effect.add_to_group("prototype0_fx_budget")
	var size := 0.58 if intercepted else 0.92
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.5
	flash_mesh.height = 1.0
	flash_mesh.radial_segments = 12
	flash_mesh.rings = 6
	var flash_material := _material("", Color("#ffe9a2"), true, true)
	var flash := _mesh(effect, "IgnitionFlash", flash_mesh, flash_material)
	flash.scale = Vector3.ONE * 0.14
	var shell_mesh := QuadMesh.new()
	shell_mesh.size = Vector2.ONE
	var shell_material := _material("", Color("#ff8528", 0.75), true, true)
	shell_material.albedo_texture = ASSETS.texture("smoke", 2)
	shell_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var shell := _mesh(effect, "Fireball", shell_mesh, shell_material)
	shell.scale = Vector3.ONE * 0.26
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * size, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.13)
	tween.tween_property(shell, "scale", Vector3.ONE * size * 1.6, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell_material, "albedo_color:a", 0.0, 0.24)
	if not intercepted:
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.46
		ring_mesh.outer_radius = 0.48
		ring_mesh.rings = 32
		ring_mesh.ring_segments = 6
		var ring_material := _material("", Color("#ffd390", 0.55), true, true)
		var ring := _mesh(effect, "PressureRing", ring_mesh, ring_material)
		var axis := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
		ring.quaternion = Quaternion(Vector3.UP, axis)
		ring.position = axis * 0.025
		ring.scale = Vector3.ONE * 0.3
		tween.tween_property(ring, "scale", Vector3.ONE * 2.1, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring_material, "albedo_color:a", 0.0, 0.26)
	var flames := _particles(effect, "BlastFlames", 6 if intercepted else 9, 0.30, Vector2(0.44, 0.44), true, true)
	var flame_process := flames.process_material as ParticleProcessMaterial
	flame_process.direction = normal if not intercepted else -heading
	flame_process.spread = 110.0
	flame_process.initial_velocity_min = 1.0
	flame_process.initial_velocity_max = 2.3
	flame_process.damping_min = 2.0
	flame_process.damping_max = 3.0
	flame_process.color_ramp = _ramp([Color("#ffe5a1"), Color("#ff8f25"), Color("#e9430d", 0.0)])
	flame_process.scale_curve = _curve([0.6, 1.3, 0.15])
	var smoke := _particles(effect, "BlastSmoke", 9 if intercepted else 14, 0.70, Vector2(0.62, 0.62), false, true)
	var smoke_process := smoke.process_material as ParticleProcessMaterial
	smoke_process.direction = normal if not intercepted else -heading
	smoke_process.spread = 75.0 if not intercepted else 150.0
	smoke_process.initial_velocity_min = 0.65
	smoke_process.initial_velocity_max = 1.7
	smoke_process.gravity = Vector3(0, 0.55, 0)
	smoke_process.damping_min = 1.2
	smoke_process.damping_max = 2.0
	smoke_process.color_ramp = _ramp([Color("#c79e65", 0.35), Color("#737778", 0.44), Color("#767b80", 0.0)])
	smoke_process.scale_curve = _curve([0.3, 1.15, 1.9])
	var sparks := _particles(effect, "BlastSparks", 12 if intercepted else 18, 0.38, Vector2(0.045, 0.15), true, true)
	var spark_process := sparks.process_material as ParticleProcessMaterial
	spark_process.direction = normal if not intercepted else -heading
	spark_process.spread = 85.0 if not intercepted else 180.0
	spark_process.initial_velocity_min = 2.0
	spark_process.initial_velocity_max = 5.0
	spark_process.gravity = Vector3(0, -3.5, 0)
	spark_process.color_ramp = _ramp([Color("#fff2b9"), Color("#ff9c35"), Color("#ed4518", 0.0)])
	spark_process.scale_curve = _curve([0.75, 0.5, 0.0])
	var debris := _particles(effect, "CasingFragments", 5 if intercepted else 4, 0.46, Vector2.ONE, false, true)
	debris.draw_pass_1 = ASSETS.particle_mesh("debris")
	var debris_process := debris.process_material as ParticleProcessMaterial
	debris_process.direction = normal
	debris_process.spread = 150.0
	debris_process.initial_velocity_min = 1.8
	debris_process.initial_velocity_max = 3.5
	debris_process.gravity = Vector3(0, -7.0, 0)
	debris_process.scale_min = 0.035
	debris_process.scale_max = 0.07
	debris_process.angular_velocity_min = -360.0
	debris_process.angular_velocity_max = 360.0
	debris_process.color_ramp = _ramp([Color("#797d79"), Color("#625c50"), Color("#625c50", 0.0)])
	for emitter in [flames, smoke, sparks, debris]:
		emitter.restart()
		emitter.emitting = true
	tween.chain().tween_interval(0.85)
	tween.chain().tween_callback(effect.queue_free)
	return effect


static func _limit(scene: Node, group: String, maximum: int) -> void:
	var effects := scene.get_tree().get_nodes_in_group(group)
	var active: Array[Node] = []
	for effect in effects:
		if not effect.is_queued_for_deletion():
			active.append(effect)
	while active.size() >= maximum:
		active.pop_front().queue_free()


static func _particles(parent: Node3D, label: String, amount: int, life: float, size: Vector2, hot: bool, burst: bool = false) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = label
	emitter.emitting = not burst
	emitter.amount = amount
	emitter.lifetime = life
	emitter.one_shot = burst
	emitter.explosiveness = 1.0 if burst else 0.0
	emitter.local_coords = false
	emitter.fixed_fps = 30
	emitter.visibility_aabb = AABB(Vector3.ONE * -3.0, Vector3.ONE * 6.0)
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.BACK
	process.gravity = Vector3.ZERO
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.035
	process.scale_min = 0.7
	process.scale_max = 1.15
	process.angle_min = -180.0
	process.angle_max = 180.0
	emitter.process_material = process
	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = ASSETS.texture("smoke", 0 if hot else 1)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if hot else BaseMaterial3D.BLEND_MODE_MIX
	quad.material = material
	emitter.draw_pass_1 = quad
	parent.add_child(emitter)
	return emitter


static func _ramp(colors: Array[Color]) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	var offsets := PackedFloat32Array()
	for index in range(colors.size()):
		offsets.append(float(index) / float(colors.size() - 1))
	gradient.offsets = offsets
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _curve(values: Array[float]) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 2.0
	for index in range(values.size()):
		curve.add_point(Vector2(float(index) / float(values.size() - 1), values[index]))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _material(key: String, color: Color, glow: bool = false, alpha: bool = false) -> StandardMaterial3D:
	if key != "" and _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.45 if not glow else 0.0
	material.roughness = 0.48
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 0.40
	if alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if glow else BaseMaterial3D.BLEND_MODE_MIX
		material.vertex_color_use_as_albedo = key == "ribbon"
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if key != "":
		_materials[key] = material
	return material


static func _mesh(parent: Node3D, label: String, mesh: Mesh, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual


static func _cylinder(parent: Node3D, label: String, tip: float, base: float, length: float, z: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = tip
	mesh.bottom_radius = base
	mesh.height = length
	mesh.radial_segments = 12
	var visual := _mesh(parent, label, mesh, material, Vector3(0, 0, z))
	visual.rotation.x = -PI * 0.5


static func _fin_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := [Vector3(0.07, 0, 0.025), Vector3(0.215, 0, 0.21), Vector3(0.205, 0, 0.29), Vector3(0.07, 0, 0.235)]
	for side in [-1.0, 1.0]:
		for index in [0, 1, 2, 0, 2, 3] if side > 0 else [2, 1, 0, 3, 2, 0]:
			surface.add_vertex(outline[index] + Vector3.UP * side * 0.009)
	for index in range(4):
		var a: Vector3 = outline[index]
		var b: Vector3 = outline[(index + 1) % 4]
		for point in [a + Vector3.UP * 0.009, a - Vector3.UP * 0.009, b - Vector3.UP * 0.009, a + Vector3.UP * 0.009, b - Vector3.UP * 0.009, b + Vector3.UP * 0.009]:
			surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()
