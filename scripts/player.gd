extends CharacterBody3D

const ROBOT_CREAM_TEXTURE: Texture2D = preload("res://art/metal_cream.svg")
const ROBOT_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const ROBOT_STEEL_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const COMBAT_STATE := preload("res://scripts/combat_state.gd")

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
const SHOW_DEBUG_HITBOX := false
const HIT_STOP_NORMAL := 0.045
const HIT_STOP_CRITICAL := 0.085

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
var _axe_tip: Node3D
var _trail_mesh: MeshInstance3D
var _trail_material: StandardMaterial3D
var _trail_points: Array[Vector3] = []
var _trail_elapsed := 0.0
var _trail_duration := 0.0
var _trail_width := 0.1
var _trail_active := false
var combat_state
var _debug_key_latches: Dictionary = {}


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	combat_state = COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH)
	_build_collision()
	_build_robot()


func _physics_process(delta: float) -> void:
	if combat_state != null:
		combat_state.update(delta)
	_update_aim()
	_update_movement()
	_update_debug_effects()
	_update_attack()
	_update_axe_trail(delta)


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
	if combat_state != null and combat_state.is_stunned():
		input_vector = Vector2.ZERO
	var slow_multiplier := 1.0
	if combat_state != null:
		slow_multiplier = 1.0 - combat_state.get_slow_percent() / 100.0
	velocity = Vector3(input_vector.x, 0.0, input_vector.y) * move_speed * slow_multiplier
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
	if combat_state != null and combat_state.is_stunned():
		return
	var wants_to_attack := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	var now := Time.get_ticks_msec() / 1000.0
	if now > _combo_expires_at:
		_combo_step = 0
	if wants_to_attack and now - _last_attack_time >= attack_interval:
		_last_attack_time = now
		_perform_axe_attack()


func _update_debug_effects() -> void:
	# Temporary PC-only mannequin probes for P0-102. They do not replace the
	# future module bindings and are intentionally explicit in the HUD/README.
	var active_scene := get_tree().current_scene
	if active_scene == null:
		return
	var target := active_scene.get_node_or_null("TargetDummy")
	if target == null:
		return
	if _pressed_once(KEY_F1):
		target.call("apply_burn", COMBAT_DATA.BURN_DURATION, COMBAT_DATA.BURN_DAMAGE_PER_SECOND, "debug")
	if _pressed_once(KEY_F2):
		target.call("apply_slow", 1.5, 30.0, "debug")
	if _pressed_once(KEY_F3):
		target.call("apply_stun", 1.5, "debug")
	if _pressed_once(KEY_F4):
		target.call("apply_spotted", 5.0, "debug")
	if _pressed_once(KEY_F5):
		target.call("reset_combat_state")


func _pressed_once(keycode: Key) -> bool:
	var is_down := Input.is_key_pressed(keycode)
	var was_down := bool(_debug_key_latches.get(keycode, false))
	_debug_key_latches[keycode] = is_down
	return is_down and not was_down


func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	return combat_state.apply_damage(amount, source_id, attack_id) if combat_state != null else 0.0


func heal(amount: float, source_id: String = "") -> float:
	return combat_state.heal(amount, source_id) if combat_state != null else 0.0


func apply_burn(duration: float = COMBAT_DATA.BURN_DURATION, damage_per_second: float = COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_burn(duration, damage_per_second, source_id)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_slow(duration, percent, source_id)


func apply_stun(duration: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_stun(duration, source_id)


func apply_spotted(duration: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_spotted(duration, source_id)


func reset_combat_state() -> void:
	if combat_state != null:
		combat_state.reset()


func _perform_axe_attack() -> void:
	var step := _combo_step
	_combo_step = (_combo_step + 1) % 3
	_combo_expires_at = Time.get_ticks_msec() / 1000.0 + AXE_COMBO_WINDOW
	_attack_label.text = "ELECTRO AXE  •  COUP %d/3" % (step + 1)
	_play_axe_animation(step)
	_begin_axe_trail(step)
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
	var critical_hit := did_hit and step == 2 and distance <= 0.9
	var damage: float = float(AXE_DAMAGE[step]) * (CRIT_MULTIPLIER if critical_hit else 1.0)
	_queue_attack_impact(step, target, did_hit, impact_point, damage, critical_hit)


func _queue_attack_impact(step: int, target: Node, did_hit: bool, impact_point: Vector3, damage: float, critical_hit: bool) -> void:
	var impact_delays := [0.26, 0.31, 0.41]
	var timer := get_tree().create_timer(impact_delays[step], true, false, false)
	timer.timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		var tip_position := _axe_tip.global_position if _axe_tip != null else global_position + Vector3.UP * 0.96 + aim_direction * 1.68
		var tip_forward := _get_axe_forward()
		var effect_point := impact_point
		if step == 2:
			effect_point = Vector3(tip_position.x, 0.0, tip_position.z)
		_show_attack_hitbox(step, effect_point, did_hit, tip_position, tip_forward)
		if not did_hit or target == null or not is_instance_valid(target):
			return
		if step == 2 and critical_hit:
			target.call("apply_stun", AXE_STUN_DURATION)
			target.call("flash_impact", true)
		else:
			target.call("apply_slow", AXE_SLOW_DURATION if step < 2 else AXE_SHOCKWAVE_DURATION, AXE_SLOW_PERCENT)
			target.call("flash_impact", false)
		target.call("take_damage", damage)
		_create_target_hit_fx(impact_point, critical_hit)
		_trigger_hit_stop(HIT_STOP_CRITICAL if critical_hit else HIT_STOP_NORMAL)
	)


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


func _begin_axe_trail(step: int) -> void:
	_finish_axe_trail(0.08)
	_trail_points.clear()
	_trail_elapsed = 0.0
	_trail_duration = [0.56, 0.64, 0.70][step]
	_trail_width = [0.07, 0.24, 0.13][step]
	_trail_active = true
	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.name = "AxeEnergyTrail"
	_trail_material = _create_fx_material(Color("#7befff") if step < 2 else Color("#d8fcff"), 0.78)
	get_tree().current_scene.add_child(_trail_mesh)


func _update_axe_trail(delta: float) -> void:
	if not _trail_active or _axe_tip == null or _trail_mesh == null:
		return
	_trail_elapsed += delta
	var tip_position := _axe_tip.global_position
	if _trail_points.is_empty() or _trail_points[-1].distance_to(tip_position) >= 0.025:
		_trail_points.append(tip_position)
		if _trail_points.size() > 18:
			_trail_points.pop_front()
		_rebuild_axe_trail()
	if _trail_elapsed >= _trail_duration:
		_finish_axe_trail(0.22)


func _rebuild_axe_trail() -> void:
	if _trail_mesh == null or _trail_points.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _trail_material)
	for index in range(1, _trail_points.size()):
		var previous := _trail_points[index - 1]
		var current := _trail_points[index]
		var movement := current - previous
		var side := movement.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.001:
			side = Vector3(-aim_direction.z, 0.0, aim_direction.x).normalized()
		var age_ratio := float(index) / float(_trail_points.size() - 1)
		var segment_width := _trail_width * lerpf(0.20, 1.0, age_ratio)
		var previous_left := previous - side * segment_width
		var previous_right := previous + side * segment_width
		var current_left := current - side * segment_width
		var current_right := current + side * segment_width
		mesh.surface_add_vertex(previous_left)
		mesh.surface_add_vertex(previous_right)
		mesh.surface_add_vertex(current_right)
		mesh.surface_add_vertex(previous_left)
		mesh.surface_add_vertex(current_right)
		mesh.surface_add_vertex(current_left)
	mesh.surface_end()
	_trail_mesh.mesh = mesh


func _finish_axe_trail(fade_duration: float) -> void:
	if not _trail_active:
		return
	_trail_active = false
	var finished_mesh := _trail_mesh
	var finished_material := _trail_material
	_trail_mesh = null
	_trail_material = null
	if finished_mesh == null:
		return
	var tween := create_tween()
	if finished_material != null:
		tween.tween_method(Callable(self, "_set_material_alpha").bind(finished_material), finished_material.albedo_color.a, 0.0, fade_duration)
	tween.tween_callback(finished_mesh.queue_free)


func _trigger_hit_stop(duration: float) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.08
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = 1.0
	)


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


func _create_lightning_arc(start: Vector3, end: Vector3, color: Color, width: float = 0.045, lifetime: float = 0.24) -> void:
	var arc := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(color, 0.95)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var delta := end - start
	var perpendicular := Vector3(-delta.z, 0.0, delta.x).normalized()
	for index in range(7):
		var t := float(index) / 6.0
		var jitter := 0.0
		if index > 0 and index < 6:
			jitter = randf_range(-0.18, 0.18)
		mesh.surface_add_vertex(start.lerp(end, t) + perpendicular * jitter + Vector3.UP * (0.03 + width))
	mesh.surface_end()
	arc.mesh = mesh
	get_tree().current_scene.add_child(arc)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale", Vector3.ONE * 1.22, lifetime * 0.35)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.95, 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(arc.queue_free)


func _create_axe_lightning(step: int, tip_position: Vector3) -> void:
	var blade_origin := tip_position
	var forward := _get_axe_forward()
	var blade_end := tip_position + forward * (0.75 if step == 0 else 0.45)
	var bolt_color := Color("#8ff7ff")
	for index in range(3 if step < 2 else 6):
		var side := Vector3.UP * randf_range(-0.20, 0.30) + Vector3(-forward.z, 0.0, forward.x) * randf_range(-0.45, 0.45)
		_create_lightning_arc(blade_origin + side, blade_end + side * 0.3, bolt_color, 0.04, 0.26 if step < 2 else 0.42)


func _get_axe_forward() -> Vector3:
	if _axe_tip != null:
		var forward := -_axe_tip.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			return forward.normalized()
	return aim_direction


func _spawn_particle_burst(origin: Vector3, color: Color, amount: int, lifetime: float, speed: float, particle_scale: float, emission_direction: Vector3 = Vector3.UP, emission_spread: float = 180.0) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = emission_spread
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
	if emission_direction != Vector3.UP and emission_direction.length_squared() > 0.001:
		process_material.direction = Vector3.FORWARD
		particles.look_at(origin + emission_direction.normalized(), Vector3.UP)
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.35).timeout.connect(particles.queue_free)


func _play_impact_fx(step: int, impact_point: Vector3, did_hit: bool, tip_position: Vector3, tip_forward: Vector3) -> void:
	_create_axe_lightning(step, tip_position)
	if step == 0:
		var start := tip_position
		var end := impact_point + Vector3.UP * 0.92 if did_hit else tip_position + tip_forward * 1.0
		for index in range(3):
			_create_lightning_arc(start + Vector3.UP * (float(index) - 1.0) * 0.08, end + Vector3.UP * (float(index) - 1.0) * 0.08, Color("#67eaff") if index < 2 else Color("#d2fcff"), 0.05, 0.30)
		_spawn_particle_burst(tip_position, Color("#a9f5ff"), 16 if did_hit else 8, 0.32, 5.0, 0.16, tip_forward, 42.0)
		if did_hit:
			_create_hit_flash(impact_point, Color("#a9f5ff"), 0.65)
	elif step == 1:
		var center := tip_position
		var forward := tip_forward
		var side := Vector3(-forward.z, 0.0, forward.x)
		var reach := AXE_RANGE[1] if not did_hit else maxf(0.5, (impact_point - global_position).length())
		_create_cleave_arc(center, forward, side, reach, 0.0, Color("#52e7ff"), 0.32)
		_create_cleave_arc(center + Vector3.UP * 0.10, forward, side, reach * 0.92, 0.12, Color("#d5fcff"), 0.38)
		_spawn_particle_burst(tip_position, Color("#55e9ff"), 22 if did_hit else 12, 0.42, 4.0, 0.14, tip_forward, 70.0)
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


func _create_cleave_arc(center: Vector3, forward: Vector3, side: Vector3, reach: float, height_offset: float, color: Color, lifetime: float) -> void:
	var arc := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(color, 0.95)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var radius := reach * 0.72
	var half_angle := deg_to_rad(68.0)
	for index in range(15):
		var angle := lerpf(-half_angle, half_angle, float(index) / 14.0)
		var jitter := Vector3(randf_range(-0.06, 0.06), randf_range(-0.03, 0.03), randf_range(-0.06, 0.06))
		var point := center + forward * (cos(angle) * radius) + side * (sin(angle) * radius) + Vector3.UP * height_offset + jitter
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	arc.mesh = mesh
	get_tree().current_scene.add_child(arc)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale", Vector3(1.18, 1.0, 1.18), lifetime * 0.45)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.95, 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(arc.queue_free)


func _create_shockwave_fx(impact_point: Vector3) -> void:
	_create_shockwave_wave(impact_point, 0.55, Color("#8ff7ff"), 0.58)
	_create_shockwave_wave(impact_point + Vector3.UP * 0.04, 0.34, Color("#e7ffff"), 0.42)
	var crater := MeshInstance3D.new()
	var crater_mesh := ImmediateMesh.new()
	var crater_material := _create_fx_material(Color("#1d2730"), 0.96)
	crater_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, crater_material)
	var crater_points: Array[Vector3] = []
	var core_points: Array[Vector3] = []
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var outer_radius := 0.78 + randf_range(-0.12, 0.18)
		var inner_radius := 0.30 + randf_range(-0.06, 0.06)
		crater_points.append(Vector3(cos(angle) * outer_radius, 0.06, sin(angle) * outer_radius))
		core_points.append(Vector3(cos(angle) * inner_radius, 0.09, sin(angle) * inner_radius))
	for index in range(12):
		var next_index := (index + 1) % 12
		crater_mesh.surface_add_vertex(core_points[index])
		crater_mesh.surface_add_vertex(crater_points[index])
		crater_mesh.surface_add_vertex(crater_points[next_index])
		crater_mesh.surface_add_vertex(core_points[index])
		crater_mesh.surface_add_vertex(crater_points[next_index])
		crater_mesh.surface_add_vertex(core_points[next_index])
	crater_mesh.surface_end()
	crater.mesh = crater_mesh
	crater.material_override = crater_material
	get_tree().current_scene.add_child(crater)
	crater.global_position = impact_point
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.28
	core_mesh.height = 0.32
	core.mesh = core_mesh
	var core_material := _create_fx_material(Color("#07131e"), 0.98)
	core.material_override = core_material
	get_tree().current_scene.add_child(core)
	core.global_position = impact_point + Vector3.UP * 0.08
	var crust := MeshInstance3D.new()
	var crust_mesh := ImmediateMesh.new()
	var crust_material := _create_fx_material(Color("#65ecff"), 0.95)
	crust_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, crust_material)
	for point in crater_points:
		crust_mesh.surface_add_vertex(point + Vector3.UP * 0.13)
	crust_mesh.surface_end()
	crust.mesh = crust_mesh
	get_tree().current_scene.add_child(crust)
	crust.global_position = impact_point
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(crater, "scale", Vector3(1.30, 1.0, 1.30), 0.70)
	tween.tween_property(core, "scale", Vector3(1.15, 0.75, 1.15), 0.55)
	tween.tween_property(crust, "scale", Vector3(1.55, 1.0, 1.55), 0.85)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(crater_material), 0.94, 0.0, 1.55)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(core_material), 0.98, 0.0, 1.15)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(crust_material), 0.95, 0.0, 1.38)
	tween.set_parallel(false)
	tween.tween_interval(0.90)
	tween.tween_callback(crater.queue_free)
	tween.tween_callback(core.queue_free)
	tween.tween_callback(crust.queue_free)
	for index in range(8):
		_create_lightning_spark(impact_point, index)
	_create_crater_fractures(impact_point)
	for index in range(6):
		var direction := Vector3(cos(TAU * float(index) / 6.0), 0.0, sin(TAU * float(index) / 6.0))
		_create_lightning_arc(impact_point + Vector3.UP * 0.16, impact_point + direction * randf_range(1.2, 1.9) + Vector3.UP * 0.16, Color("#3de6ff"), 0.05, 0.60)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.18, Color("#a8f8ff"), 34, 0.75, 7.0, 0.19)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.12, Color("#ffb13b"), 16, 0.52, 5.0, 0.14)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.2, Color("#d19b70"), 22, 0.80, 4.0, 0.18)


func _create_shockwave_wave(origin: Vector3, radius: float, color: Color, lifetime: float) -> void:
	var wave := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(color, 0.92)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var points := 20
	for index in range(points + 1):
		var angle := TAU * float(index) / float(points)
		var irregular_radius := radius + randf_range(-0.10, 0.10)
		mesh.surface_add_vertex(Vector3(cos(angle) * irregular_radius, 0.12, sin(angle) * irregular_radius))
	mesh.surface_end()
	wave.mesh = mesh
	get_tree().current_scene.add_child(wave)
	wave.global_position = origin
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector3(3.0, 1.0, 3.0), lifetime)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.92, 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(wave.queue_free)


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


func _show_attack_hitbox(step: int, impact_point: Vector3 = Vector3.ZERO, did_hit: bool = false, tip_position: Vector3 = Vector3.ZERO, tip_forward: Vector3 = Vector3.ZERO) -> void:
	if SHOW_DEBUG_HITBOX:
		var hitbox := MeshInstance3D.new()
		hitbox.name = "AxeHitbox"
		var mesh := CylinderMesh.new()
		mesh.top_radius = AXE_RANGE[step] * (0.10 if step == 0 else 0.55)
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.06
		hitbox.mesh = mesh
		hitbox.position = tip_position if tip_position != Vector3.ZERO else global_position + aim_direction * (AXE_RANGE[step] * 0.5)
		hitbox.position.y = 0.04
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
	if tip_position == Vector3.ZERO:
		tip_position = _axe_tip.global_position if _axe_tip != null else global_position + Vector3.UP * 0.96 + aim_direction * 1.68
	if tip_forward == Vector3.ZERO:
		tip_forward = _get_axe_forward()
	_play_impact_fx(step, impact_point, did_hit, tip_position, tip_forward)


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
	body.material_override = _robot_textured_material(Color.WHITE, 0.78, ROBOT_CREAM_TEXTURE)
	visuals.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.48
	head_mesh.height = 0.85
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.55, 0.0)
	head.material_override = _robot_textured_material(Color.WHITE, 0.72, ROBOT_CREAM_TEXTURE)
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

	var chest_plate := MeshInstance3D.new()
	var chest_mesh := BoxMesh.new()
	chest_mesh.size = Vector3(0.72, 0.48, 0.14)
	chest_plate.mesh = chest_mesh
	chest_plate.position = Vector3(0.0, 0.88, -0.52)
	chest_plate.rotation_degrees.x = -7.0
	chest_plate.material_override = _robot_textured_material(Color.WHITE, 0.70, ROBOT_RUST_TEXTURE)
	visuals.add_child(chest_plate)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.19
	core_mesh.height = 0.28
	core.mesh = core_mesh
	core.position = Vector3(0.0, 0.90, -0.61)
	core.scale = Vector3(1.35, 0.72, 0.48)
	core.material_override = _material(Color("#49e8f1"), 0.16, Color("#22d8e8"))
	visuals.add_child(core)
	_add_robot_arm(visuals, -1.0)
	_add_robot_arm(visuals, 1.0)
	_add_robot_leg(visuals, -1.0)
	_add_robot_leg(visuals, 1.0)
	_add_robot_backpack(visuals)

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
	_axe_tip = Node3D.new()
	_axe_tip.name = "AxeTip"
	_axe_tip.position = Vector3(0.0, 0.0, -1.58)
	_axe_pivot.add_child(_axe_tip)
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


func _add_robot_arm(parent: Node3D, side: float) -> void:
	var shoulder := MeshInstance3D.new()
	var shoulder_mesh := SphereMesh.new()
	shoulder_mesh.radius = 0.25
	shoulder_mesh.height = 0.42
	shoulder.mesh = shoulder_mesh
	shoulder.position = Vector3(side * 0.68, 1.05, 0.0)
	shoulder.material_override = _robot_textured_material(Color.WHITE, 0.82, ROBOT_STEEL_TEXTURE)
	parent.add_child(shoulder)
	var upper := MeshInstance3D.new()
	var upper_mesh := CylinderMesh.new()
	upper_mesh.top_radius = 0.16
	upper_mesh.bottom_radius = 0.20
	upper_mesh.height = 0.58
	upper.mesh = upper_mesh
	upper.position = Vector3(side * 0.78, 0.78, 0.0)
	upper.rotation_degrees.z = side * -11.0
	upper.material_override = _robot_textured_material(Color.WHITE, 0.82, ROBOT_CREAM_TEXTURE)
	parent.add_child(upper)
	var forearm := MeshInstance3D.new()
	var forearm_mesh := BoxMesh.new()
	forearm_mesh.size = Vector3(0.30, 0.48, 0.34)
	forearm.mesh = forearm_mesh
	forearm.position = Vector3(side * 0.82, 0.43, -0.03)
	forearm.rotation_degrees.z = side * -18.0
	forearm.material_override = _robot_textured_material(Color.WHITE, 0.84, ROBOT_RUST_TEXTURE)
	parent.add_child(forearm)
	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.17
	hand_mesh.height = 0.25
	hand.mesh = hand_mesh
	hand.position = Vector3(side * 0.84, 0.16, -0.08)
	hand.material_override = _robot_textured_material(Color.WHITE, 0.90, ROBOT_STEEL_TEXTURE)
	parent.add_child(hand)


func _add_robot_leg(parent: Node3D, side: float) -> void:
	var thigh := MeshInstance3D.new()
	var thigh_mesh := CapsuleMesh.new()
	thigh_mesh.radius = 0.20
	thigh_mesh.height = 0.62
	thigh.mesh = thigh_mesh
	thigh.position = Vector3(side * 0.31, 0.36, 0.02)
	thigh.rotation_degrees.z = side * 7.0
	thigh.material_override = _robot_textured_material(Color.WHITE, 0.84, ROBOT_STEEL_TEXTURE)
	parent.add_child(thigh)
	var shin := MeshInstance3D.new()
	var shin_mesh := BoxMesh.new()
	shin_mesh.size = Vector3(0.28, 0.48, 0.34)
	shin.mesh = shin_mesh
	shin.position = Vector3(side * 0.33, 0.05, -0.04)
	shin.rotation_degrees.z = side * -4.0
	shin.material_override = _robot_textured_material(Color.WHITE, 0.78, ROBOT_CREAM_TEXTURE)
	parent.add_child(shin)
	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.40, 0.18, 0.62)
	foot.mesh = foot_mesh
	foot.position = Vector3(side * 0.33, -0.17, -0.17)
	foot.material_override = _robot_textured_material(Color.WHITE, 0.90, ROBOT_RUST_TEXTURE)
	parent.add_child(foot)


func _add_robot_backpack(parent: Node3D) -> void:
	var pack := MeshInstance3D.new()
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.66, 0.78, 0.34)
	pack.mesh = pack_mesh
	pack.position = Vector3(0.0, 1.02, 0.55)
	pack.rotation_degrees.x = -8.0
	pack.material_override = _robot_textured_material(Color.WHITE, 0.86, ROBOT_RUST_TEXTURE)
	parent.add_child(pack)
	var coil := MeshInstance3D.new()
	var coil_mesh := TorusMesh.new()
	coil_mesh.inner_radius = 0.14
	coil_mesh.outer_radius = 0.20
	coil.mesh = coil_mesh
	coil.position = Vector3(0.0, 1.18, 0.76)
	coil.rotation_degrees.x = 90.0
	coil.material_override = _material(Color("#52e5ed"), 0.30, Color("#2bd4df"))
	parent.add_child(coil)


func _material(color: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 3.0
	return material


func _robot_textured_material(color: Color, roughness: float, texture: Texture2D) -> StandardMaterial3D:
	var material := _material(color, roughness)
	material.albedo_texture = texture
	material.uv1_scale = Vector3(1.1, 1.1, 1.1)
	material.metallic = 0.18 if texture == ROBOT_RUST_TEXTURE else (0.38 if texture == ROBOT_STEEL_TEXTURE else 0.04)
	return material
