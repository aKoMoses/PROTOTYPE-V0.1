extends CharacterBody3D

@export var move_speed := 7.5
@export var attack_interval := 0.64

# Electro Axe V0.1 — first playable combat lot. Damage values are deliberately
# centralized so balancing after the human test does not touch hitbox code.
const AXE_DAMAGE := [120.0, 145.0, 80.0]
const AXE_RANGE := [4.4, 3.2, 2.8]
const AXE_COMBO_WINDOW := 1.70
const AXE_SLOW_DURATION := 0.25
const AXE_SLOW_PERCENT := 30.0
const AXE_SHOCKWAVE_DURATION := 0.50
const AXE_STUN_DURATION := 0.50
const CRIT_MULTIPLIER := 1.5

var aim_direction := Vector3(0.0, 0.0, -1.0)
var _last_attack_time := -10.0
var _combo_step := 0
var _combo_expires_at := -1.0
var _attack_label: Label3D
var _axe_pivot: Node3D
var _axe_pivot_home := Vector3(0.5, 1.0, -0.55)
var _axe_pivot_home_rotation := Vector3.ZERO
var _robot_visuals: Node3D
var _axe_light: OmniLight3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	_build_collision()
	_build_robot()


func _physics_process(_delta: float) -> void:
	_update_aim()
	_update_movement()
	_update_attack()


func _update_movement() -> void:
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1.0

	input_vector = input_vector.normalized()
	velocity = Vector3(input_vector.x, 0.0, input_vector.y) * move_speed
	move_and_slide()
	global_position.y = 0.0


func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	if absf(ray_direction.y) < 0.001:
		return
	var distance_to_ground := -ray_origin.y / ray_direction.y
	if distance_to_ground <= 0.0:
		return
	var aim_point := ray_origin + ray_direction * distance_to_ground
	var flat_direction := aim_point - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.04:
		aim_direction = flat_direction.normalized()
		look_at(global_position + aim_direction, Vector3.UP)


func _update_attack() -> void:
	var wants_to_attack := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	var now := Time.get_ticks_msec() / 1000.0
	if now > _combo_expires_at:
		_combo_step = 0
	if wants_to_attack and now - _last_attack_time >= attack_interval:
		_last_attack_time = now
		_perform_axe_attack()


func _perform_axe_attack() -> void:
	var step := _combo_step
	_combo_step = (_combo_step + 1) % 3
	_combo_expires_at = Time.get_ticks_msec() / 1000.0 + AXE_COMBO_WINDOW
	_attack_label.text = "ELECTRO AXE  •  COUP %d/3" % (step + 1)
	_play_axe_animation(step)
	var target := get_tree().current_scene.get_node_or_null("TargetDummy")
	var impact_point: Vector3 = global_position + aim_direction * AXE_RANGE[step]
	var did_hit := false
	var distance := 0.0
	if target != null:
		var offset: Vector3 = target.global_position - global_position
		var flat_offset := Vector3(offset.x, 0.0, offset.z)
		distance = flat_offset.length()
		var facing_dot := aim_direction.dot(flat_offset.normalized()) if distance > 0.01 else -1.0
		var cone_limit := 0.88 if step == 0 else (0.35 if step == 1 else -0.25)
		did_hit = distance <= AXE_RANGE[step] and distance > 0.01 and facing_dot >= cone_limit
		if did_hit:
			impact_point = target.global_position
	_show_attack_hitbox(step, impact_point, did_hit)
	if not did_hit or target == null:
		return
	var damage: float = float(AXE_DAMAGE[step])
	if step == 2 and distance <= 0.9:
		damage *= CRIT_MULTIPLIER
		target.call("apply_stun", AXE_STUN_DURATION)
		target.call("flash_impact", true)
	else:
		target.call("apply_slow", AXE_SLOW_DURATION if step < 2 else AXE_SHOCKWAVE_DURATION, AXE_SLOW_PERCENT)
		target.call("flash_impact", false)
	target.call("take_damage", damage)
	_create_target_hit_fx(impact_point, step == 2 and distance <= 0.9)


func _play_axe_animation(step: int) -> void:
	if _axe_pivot == null:
		return
	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(_axe_pivot, "position", _axe_pivot_home, 0.01)
	tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.01)
	if step == 0:
		# A readable thrust: the weapon lunges toward the target and snaps back.
		tween.tween_property(_axe_pivot, "position", Vector3(0.5, 1.0, -0.20), 0.12)
		tween.tween_property(_axe_pivot, "position", Vector3(0.5, 1.0, -1.65), 0.14)
		tween.tween_property(_axe_pivot, "position", _axe_pivot_home, 0.28)
	elif step == 1:
		# A lateral sweep, with a brief anticipation in the opposite direction.
		tween.tween_property(_axe_pivot, "rotation", Vector3(0.0, deg_to_rad(-65.0), deg_to_rad(-12.0)), 0.12)
		tween.tween_property(_axe_pivot, "rotation", Vector3(0.0, deg_to_rad(78.0), deg_to_rad(14.0)), 0.19)
		tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.30)
	else:
		# Overhead slam: weapon rises, pauses, then drives down into the floor.
		tween.tween_property(_axe_pivot, "rotation", Vector3(deg_to_rad(-72.0), 0.0, 0.0), 0.18)
		tween.tween_interval(0.08)
		tween.tween_property(_axe_pivot, "rotation", Vector3(deg_to_rad(78.0), 0.0, 0.0), 0.15)
		tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.34)
	if _robot_visuals != null:
		var recoil := create_tween()
		recoil.tween_property(_robot_visuals, "position", -aim_direction * (0.10 if step < 2 else 0.18), 0.06)
		recoil.tween_property(_robot_visuals, "position", Vector3.ZERO, 0.18 if step < 2 else 0.28)
		recoil.tween_property(_robot_visuals, "rotation", Vector3(0.0, 0.0, deg_to_rad(-7.0 if step == 1 else 0.0)), 0.05)
		recoil.tween_property(_robot_visuals, "rotation", Vector3.ZERO, 0.16)
	if _axe_light != null:
		_axe_light.light_energy = 8.0 if step == 2 else 5.0
		var light_tween := create_tween()
		light_tween.tween_property(_axe_light, "light_energy", 0.0, 0.24 if step < 2 else 0.42)
	var rig := get_tree().current_scene.get_node_or_null("CameraRig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.05 if step < 2 else 0.13)


func _create_fx_material(color: Color, alpha: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 5.0
	return material


func _set_material_alpha(alpha: float, material: StandardMaterial3D) -> void:
	if material == null:
		return
	var color := material.albedo_color
	color.a = alpha
	material.albedo_color = color


func _spawn_particle_burst(origin: Vector3, color: Color, amount: int, lifetime: float, speed: float, particle_scale: float) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = speed * 0.55
	process_material.initial_velocity_max = speed
	process_material.gravity = Vector3(0.0, -10.0, 0.0)
	process_material.scale_min = particle_scale * 0.55
	process_material.scale_max = particle_scale
	particles.process_material = process_material
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.12
	particle_mesh.height = 0.24
	particle_mesh.material = _create_fx_material(color, 0.92)
	particles.draw_pass_1 = particle_mesh
	get_tree().current_scene.add_child(particles)
	particles.global_position = origin
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.35).timeout.connect(particles.queue_free)


func _play_impact_fx(step: int, impact_point: Vector3, did_hit: bool) -> void:
	if step == 0:
		var thrust := MeshInstance3D.new()
		var thrust_mesh := BoxMesh.new()
		thrust_mesh.size = Vector3(0.18, 0.18, AXE_RANGE[0])
		thrust.mesh = thrust_mesh
		thrust.material_override = _create_fx_material(Color("#8cefff"), 0.85)
		get_tree().current_scene.add_child(thrust)
		thrust.global_position = global_position + Vector3.UP * 0.95 + aim_direction * (AXE_RANGE[0] * 0.5)
		thrust.look_at(thrust.global_position + aim_direction, Vector3.UP)
		var tween := create_tween()
		tween.tween_property(thrust, "scale", Vector3(1.8, 1.8, 0.2), 0.12)
		tween.tween_callback(thrust.queue_free)
		_spawn_particle_burst(impact_point + Vector3.UP * 0.9, Color("#a9f5ff"), 16 if did_hit else 8, 0.32, 5.0, 0.16)
		if did_hit:
			_create_hit_flash(impact_point, Color("#a9f5ff"), 0.65)
	elif step == 1:
		var slash := _create_slash_fan(AXE_RANGE[1], deg_to_rad(58.0))
		get_tree().current_scene.add_child(slash)
		slash.global_position = global_position + Vector3.UP * 0.9
		slash.look_at(slash.global_position + aim_direction, Vector3.UP)
		var tween := create_tween()
		tween.tween_property(slash, "scale", Vector3(1.25, 1.0, 1.25), 0.16)
		tween.tween_callback(slash.queue_free)
		var slash_echo := _create_slash_fan(AXE_RANGE[1] * 0.82, deg_to_rad(48.0))
		get_tree().current_scene.add_child(slash_echo)
		slash_echo.global_position = slash.global_position + Vector3.UP * 0.08
		slash_echo.look_at(slash_echo.global_position + aim_direction, Vector3.UP)
		slash_echo.material_override = _create_fx_material(Color("#e8fcff"), 0.55)
		var echo_tween := create_tween()
		echo_tween.tween_property(slash_echo, "scale", Vector3(1.7, 1.0, 1.7), 0.22)
		echo_tween.tween_callback(slash_echo.queue_free)
		var slash_outline := _create_slash_outline(AXE_RANGE[1] * 1.02, deg_to_rad(58.0), Color("#d8fbff"))
		get_tree().current_scene.add_child(slash_outline)
		slash_outline.global_position = slash.global_position + Vector3.UP * 0.06
		slash_outline.look_at(slash_outline.global_position + aim_direction, Vector3.UP)
		var outline_tween := create_tween()
		outline_tween.tween_property(slash_outline, "scale", Vector3(1.14, 1.0, 1.14), 0.25)
		outline_tween.tween_callback(slash_outline.queue_free)
		_spawn_particle_burst(impact_point + Vector3.UP * 0.8, Color("#55e9ff"), 22 if did_hit else 12, 0.42, 4.0, 0.14)
		if did_hit:
			_create_hit_flash(impact_point, Color("#72edff"), 0.8)
	else:
		_create_shockwave_fx(impact_point)


func _create_hit_flash(origin: Vector3, color: Color, radius: float) -> void:
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.32
	mesh.height = 0.64
	flash.mesh = mesh
	var material := _create_fx_material(color, 0.92)
	flash.material_override = material
	get_tree().current_scene.add_child(flash)
	flash.global_position = origin + Vector3.UP * 0.9
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * radius * 3.0, 0.16)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.92, 0.0, 0.18)
	tween.set_parallel(false)
	tween.tween_callback(flash.queue_free)
	_spawn_particle_burst(flash.global_position, color, 12, 0.30, 3.5, 0.12)


func _create_target_hit_fx(origin: Vector3, critical: bool) -> void:
	var color := Color("#fff0a1") if critical else Color("#ff795e")
	var pulse := MeshInstance3D.new()
	var pulse_mesh := TorusMesh.new()
	pulse_mesh.inner_radius = 0.22 if critical else 0.16
	pulse_mesh.outer_radius = 0.34 if critical else 0.26
	pulse.mesh = pulse_mesh
	var pulse_material := _create_fx_material(color, 0.92)
	pulse.material_override = pulse_material
	get_tree().current_scene.add_child(pulse)
	pulse.global_position = origin + Vector3.UP * 0.16
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector3.ONE * (3.2 if critical else 2.4), 0.28)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(pulse_material), 0.92, 0.0, 0.32)
	tween.set_parallel(false)
	tween.tween_callback(pulse.queue_free)
	_spawn_particle_burst(origin + Vector3.UP * 0.75, color, 26 if critical else 16, 0.40 if critical else 0.28, 5.5, 0.16)


func _create_slash_fan(radius: float, half_angle: float) -> MeshInstance3D:
	var slash := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(Color("#56dcff"), 0.72)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var segments := 10
	for index in range(segments):
		var a0 := -half_angle + (2.0 * half_angle) * float(index) / float(segments)
		var a1 := -half_angle + (2.0 * half_angle) * float(index + 1) / float(segments)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(sin(a0) * radius, 0.0, -cos(a0) * radius))
		mesh.surface_add_vertex(Vector3(sin(a1) * radius, 0.0, -cos(a1) * radius))
	mesh.surface_end()
	slash.mesh = mesh
	return slash


func _create_slash_outline(radius: float, half_angle: float, color: Color) -> MeshInstance3D:
	var outline := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(color, 0.95)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var segments := 14
	for index in range(segments):
		var a0 := -half_angle + (2.0 * half_angle) * float(index) / float(segments)
		var a1 := -half_angle + (2.0 * half_angle) * float(index + 1) / float(segments)
		mesh.surface_add_vertex(Vector3(sin(a0) * radius, 0.03, -cos(a0) * radius))
		mesh.surface_add_vertex(Vector3(sin(a1) * radius, 0.03, -cos(a1) * radius))
	mesh.surface_end()
	outline.mesh = mesh
	return outline


func _create_shockwave_fx(impact_point: Vector3) -> void:
	var crater := MeshInstance3D.new()
	var crater_mesh := CylinderMesh.new()
	crater_mesh.top_radius = 0.72
	crater_mesh.bottom_radius = 0.9
	crater_mesh.height = 0.10
	crater.mesh = crater_mesh
	var crater_material := _create_fx_material(Color("#263e50"), 0.94)
	crater.material_override = crater_material
	get_tree().current_scene.add_child(crater)
	crater.global_position = impact_point + Vector3.UP * 0.05
	var inner_crater := MeshInstance3D.new()
	var inner_mesh := CylinderMesh.new()
	inner_mesh.top_radius = 0.46
	inner_mesh.bottom_radius = 0.64
	inner_mesh.height = 0.13
	inner_crater.mesh = inner_mesh
	var inner_material := _create_fx_material(Color("#121c27"), 0.98)
	inner_crater.material_override = inner_material
	get_tree().current_scene.add_child(inner_crater)
	inner_crater.global_position = impact_point + Vector3.UP * 0.12
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.35
	ring_mesh.outer_radius = 0.52
	ring.mesh = ring_mesh
	var ring_material := _create_fx_material(Color("#42e7ff"), 0.95)
	ring.material_override = ring_material
	get_tree().current_scene.add_child(ring)
	ring.global_position = impact_point + Vector3.UP * 0.12
	var inner_ring := MeshInstance3D.new()
	var inner_ring_mesh := TorusMesh.new()
	inner_ring_mesh.inner_radius = 0.16
	inner_ring_mesh.outer_radius = 0.25
	inner_ring.mesh = inner_ring_mesh
	var inner_ring_material := _create_fx_material(Color("#e9ffff"), 0.95)
	inner_ring.material_override = inner_ring_material
	get_tree().current_scene.add_child(inner_ring)
	inner_ring.global_position = impact_point + Vector3.UP * 0.16
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(crater, "scale", Vector3(1.65, 1.0, 1.65), 0.55)
	tween.tween_property(inner_crater, "scale", Vector3(1.35, 1.0, 1.35), 0.75)
	tween.tween_property(ring, "scale", Vector3(3.8, 1.0, 3.8), 0.78)
	tween.tween_property(inner_ring, "scale", Vector3(2.8, 1.0, 2.8), 0.50)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(crater_material), 0.94, 0.0, 1.55)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(inner_material), 0.98, 0.0, 1.65)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(ring_material), 0.95, 0.0, 1.10)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(inner_ring_material), 0.95, 0.0, 0.82)
	tween.set_parallel(false)
	tween.tween_interval(1.0)
	tween.tween_callback(crater.queue_free)
	tween.tween_callback(inner_crater.queue_free)
	tween.tween_callback(ring.queue_free)
	tween.tween_callback(inner_ring.queue_free)
	for index in range(8):
		_create_lightning_spark(impact_point, index)
	_create_crater_fractures(impact_point)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.18, Color("#a8f8ff"), 34, 0.75, 7.0, 0.19)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.12, Color("#ffb13b"), 16, 0.52, 5.0, 0.14)


func _create_crater_fractures(origin: Vector3) -> void:
	for index in range(7):
		var crack := MeshInstance3D.new()
		var mesh := ImmediateMesh.new()
		var material := _create_fx_material(Color("#8cf4ff"), 0.96)
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		var angle := (TAU / 7.0) * float(index) + 0.18
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		for point_index in range(5):
			var distance := 0.28 + float(point_index) * 0.26
			var jitter := Vector3(-direction.z, 0.0, direction.x) * (0.06 if point_index % 2 == 0 else -0.04)
			mesh.surface_add_vertex(direction * distance + jitter + Vector3.UP * 0.17)
		mesh.surface_end()
		crack.mesh = mesh
		get_tree().current_scene.add_child(crack)
		crack.global_position = origin
		var tween := create_tween()
		tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.96, 0.0, 1.35)
		tween.tween_callback(crack.queue_free)


func _create_lightning_spark(origin: Vector3, index: int) -> void:
	var spark := MeshInstance3D.new()
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.055, 0.08, 1.2 + float(index % 3) * 0.35)
	spark.mesh = spark_mesh
	var spark_material := _create_fx_material(Color("#b7f8ff"), 0.95)
	spark.material_override = spark_material
	get_tree().current_scene.add_child(spark)
	var angle := (TAU / 8.0) * float(index)
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	spark.global_position = origin + direction * 0.45 + Vector3.UP * (0.10 + float(index % 2) * 0.08)
	spark.look_at(spark.global_position + direction, Vector3.UP)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector3(1.0, 1.0, 0.1), 0.48)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(spark_material), 0.95, 0.0, 0.52)
	tween.set_parallel(false)
	tween.tween_callback(spark.queue_free)


func _show_attack_hitbox(step: int, impact_point: Vector3 = Vector3.ZERO, did_hit: bool = false) -> void:
	var hitbox := MeshInstance3D.new()
	hitbox.name = "AxeHitbox"
	var mesh := CylinderMesh.new()
	mesh.top_radius = AXE_RANGE[step] * (0.10 if step == 0 else 0.55)
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.06
	hitbox.mesh = mesh
	hitbox.position = global_position + aim_direction * (AXE_RANGE[step] * 0.5)
	hitbox.position.y = 0.04
	hitbox.rotation_degrees = Vector3.ZERO
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.25, 0.85, 1.0, 0.42)
	material.emission_enabled = true
	material.emission = Color("#2ad9ff")
	material.emission_energy_multiplier = 2.0
	hitbox.material_override = material
	get_tree().current_scene.add_child(hitbox)
	var tween := create_tween()
	tween.tween_property(hitbox, "scale", Vector3(1.0, 1.0, 1.8), 0.12)
	tween.tween_callback(hitbox.queue_free)
	if impact_point == Vector3.ZERO:
		impact_point = global_position + aim_direction * AXE_RANGE[step]
	_play_impact_fx(step, impact_point, did_hit)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)


func _build_robot() -> void:
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	visuals.scale = Vector3.ONE * 0.88
	_robot_visuals = visuals
	add_child(visuals)

	_attack_label = Label3D.new()
	_attack_label.position = Vector3(0.0, 2.55, 0.0)
	_attack_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_attack_label.font_size = 26
	_attack_label.outline_size = 6
	_attack_label.modulate = Color("#8beaff")
	add_child(_attack_label)

	var selection_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.78
	ring_mesh.outer_radius = 0.93
	selection_ring.mesh = ring_mesh
	selection_ring.position.y = 0.045
	selection_ring.material_override = _material(Color("#bdefff"), 0.3, Color("#56dfff"))
	visuals.add_child(selection_ring)

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.25
	body.mesh = body_mesh
	body.position.y = 0.8
	body.material_override = _material(Color("#e4d0ae"), 0.72)
	visuals.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.48
	head_mesh.height = 0.85
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.55, 0.0)
	head.material_override = _material(Color("#efe1c4"), 0.65)
	visuals.add_child(head)

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.18
	eye_mesh.height = 0.26
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 1.58, -0.42)
	eye.scale = Vector3(1.2, 0.75, 0.45)
	eye.material_override = _material(Color("#4ee8ff"), 0.25, Color("#21cfff"))
	visuals.add_child(eye)

	_axe_pivot = Node3D.new()
	_axe_pivot.name = "ElectroAxePivot"
	_axe_pivot.position = _axe_pivot_home
	visuals.add_child(_axe_pivot)
	var axe_handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.09
	handle_mesh.bottom_radius = 0.12
	handle_mesh.height = 1.5
	axe_handle.mesh = handle_mesh
	axe_handle.rotation_degrees.x = -90.0
	axe_handle.position = Vector3(0.0, 0.0, -0.55)
	axe_handle.material_override = _material(Color("#4b342b"), 0.72)
	_axe_pivot.add_child(axe_handle)
	var axe_blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.78, 0.18, 0.52)
	axe_blade.mesh = blade_mesh
	axe_blade.position = Vector3(0.0, 0.0, -1.25)
	axe_blade.material_override = _material(Color("#bfefff"), 0.22, Color("#28dfff"))
	_axe_pivot.add_child(axe_blade)
	var axe_edge := MeshInstance3D.new()
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.9, 0.06, 0.08)
	axe_edge.mesh = edge_mesh
	axe_edge.position = Vector3(0.0, -0.11, -1.25)
	axe_edge.material_override = _material(Color("#eaffff"), 0.1, Color("#9cf6ff"))
	_axe_pivot.add_child(axe_edge)
	_axe_light = OmniLight3D.new()
	_axe_light.light_color = Color("#62eaff")
	_axe_light.light_energy = 0.0
	_axe_light.omni_range = 3.5
	_axe_light.position = Vector3(0.0, 0.0, -1.2)
	_axe_pivot.add_child(_axe_light)

	var scarf := MeshInstance3D.new()
	var scarf_mesh := BoxMesh.new()
	scarf_mesh.size = Vector3(0.6, 0.08, 1.15)
	scarf.mesh = scarf_mesh
	scarf.position = Vector3(0.0, 1.2, 0.65)
	scarf.rotation_degrees.x = -18.0
	scarf.material_override = _material(Color("#a62f25"), 0.9)
	visuals.add_child(scarf)


func _material(color: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 3.0
	return material
