extends Node

# Legacy axe combo, trails, hit shapes and associated effects.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "LegacyAxeComponent"


func _perform_axe_attack() -> void:
	var action_token: int = player._try_begin_weapon_action("legacy_axe")
	if action_token == 0:
		return
	player._axe_action_token = action_token
	player._mark_combat_event()
	var step := player._combo_step
	player._combo_step = (player._combo_step + 1) % 3
	player._axe_attack_token += 1
	var token := player._axe_attack_token
	player._axe_attack_busy = true
	player._axe_attack_step = step
	player._axe_attack_origin = player.global_position
	player._axe_attack_direction = player.aim_direction.normalized()
	player._axe_attack_impact_point = player._axe_attack_origin + player._axe_attack_direction * float(player._axe_wave_outer_radius)
	player._combo_expires_at = -1.0
	player._attack_label.text = "LEGACY ATTACK  •  COUP %d/3" % (step + 1)
	var attack_speed: float = player.get_attack_speed_multiplier()
	player._play_axe_animation(step, attack_speed)
	player._begin_axe_trail(step, attack_speed)
	var total := (float(player._axe_preparation[step]) + float(player._axe_active[step]) + float(player._axe_recovery[step])) / attack_speed
	if step < 2:
		var strike_timer := player.get_tree().create_timer((float(player._axe_preparation[step]) + float(player._axe_active[step]) * 0.5) / attack_speed, true, false, false)
		strike_timer.timeout.connect(func() -> void: player._resolve_axe_strike(token, step))
	else:
		var center_timer := player.get_tree().create_timer(float(player._axe_preparation[step]) / attack_speed, true, false, false)
		center_timer.timeout.connect(func() -> void: player._resolve_axe_center(token))
		var wave_timer := player.get_tree().create_timer((float(player._axe_preparation[step]) + float(player._axe_active[step])) / attack_speed, true, false, false)
		wave_timer.timeout.connect(func() -> void: player._resolve_axe_wave(token))
	var finish_timer := player.get_tree().create_timer(total, true, false, false)
	finish_timer.timeout.connect(func() -> void: player._finish_axe_attack(token))


func _attack_token_valid(token: int) -> bool:
	return player.is_inside_tree() and player._axe_attack_busy and token == player._axe_attack_token and player._action_gate.owns(player._axe_action_token, PLAYER_STATE.ACTION_GATE.Kind.WEAPON, "legacy_axe") and not (player.combat_state != null and player.combat_state.is_stunned())


func _resolve_axe_strike(token: int, step: int) -> void:
	if not player._attack_token_valid(token):
		return
	var target := player.get_tree().current_scene.get_node_or_null("TargetDummy")
	var did_hit = target != null and player._axe_target_in_shape(target, step)
	var impact_point: Vector3 = target.global_position if did_hit else player._axe_attack_origin + player._axe_attack_direction * float(player._axe_range[step])
	var tip_position := player._axe_tip.global_position if player._axe_tip != null else player.global_position + Vector3.UP * 0.96 + player._axe_attack_direction * 1.68
	player._show_attack_hitbox(step, impact_point, did_hit, tip_position, player._get_axe_forward())
	if not did_hit:
		return
	player._apply_axe_hit(target, impact_point, float(player._axe_damage[step]), player._axe_slow_duration[step], false, token, step)


func _resolve_axe_center(token: int) -> void:
	if not player._attack_token_valid(token):
		return
	var target := player.get_tree().current_scene.get_node_or_null("TargetDummy")
	var did_hit = target != null and player._axe_target_in_radius(target, player._axe_wave_inner_radius)
	var impact_point := player._axe_attack_origin
	player._show_attack_hitbox(2, impact_point, did_hit, player._axe_tip.global_position if player._axe_tip != null else impact_point, player._get_axe_forward(), "center")
	if not did_hit:
		return
	player._apply_axe_hit(target, impact_point, float(player._axe_damage[2]), 0.0, true, token, 20)


func _resolve_axe_wave(token: int) -> void:
	if not player._attack_token_valid(token):
		return
	var target := player.get_tree().current_scene.get_node_or_null("TargetDummy")
	var did_hit = target != null and player._axe_target_in_wave(target)
	var impact_point := player._axe_attack_origin
	player._show_attack_hitbox(2, impact_point, did_hit, player._axe_tip.global_position if player._axe_tip != null else impact_point, player._get_axe_forward(), "wave")
	if not did_hit:
		return
	player._apply_axe_hit(target, impact_point, 45.0, player._axe_slow_duration[2], false, token, 21)


func _apply_axe_hit(target: Node, impact_point: Vector3, damage: float, slow_duration: float, critical_hit: bool, token: int, phase: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var attack_id := "legacy_attack:%d:%d%s" % [token, phase, ":critical" if critical_hit else ""]
	var effective_damage := float(target.call("take_damage", damage, "player", attack_id))
	if critical_hit:
		target.call("apply_stun", player._axe_stun_duration, "legacy_attack")
	elif slow_duration > 0.0:
		target.call("apply_slow", slow_duration, player._axe_slow_percent, "legacy_attack")
	target.call("flash_impact", critical_hit)
	player._create_target_hit_fx(impact_point, critical_hit)
	if effective_damage > 0.0:
		player._trigger_hit_stop(PLAYER_STATE.HIT_STOP_CRITICAL if critical_hit else PLAYER_STATE.HIT_STOP_NORMAL)


func _finish_axe_attack(token: int) -> void:
	if token != player._axe_attack_token or not player._axe_attack_busy:
		return
	player._axe_attack_busy = false
	player._axe_attack_step = -1
	player._action_gate.release(player._axe_action_token)
	player._axe_action_token = 0
	var now := Time.get_ticks_msec() / 1000.0
	player._combo_expires_at = now + PLAYER_STATE.LEGACY_COMBO_WINDOW
	player._next_attack_ready_at = now


func _cancel_axe_attack() -> void:
	if not player._axe_attack_busy:
		player._action_gate.release(player._axe_action_token)
		player._axe_action_token = 0
		return
	player._axe_attack_token += 1
	player._axe_attack_busy = false
	player._axe_attack_step = -1
	player._action_gate.release(player._axe_action_token)
	player._axe_action_token = 0
	player._combo_step = 0
	var now := Time.get_ticks_msec() / 1000.0
	player._combo_expires_at = now + PLAYER_STATE.LEGACY_COMBO_WINDOW
	player._next_attack_ready_at = now
	player._finish_axe_trail(0.10)
	player._attack_label.text = "LEGACY ATTACK  •  INTERROMPU"
	if player._axe_pivot != null:
		var tween := player.create_tween()
		tween.tween_property(player._axe_pivot, "position", player._axe_pivot_home, 0.12)
		tween.tween_property(player._axe_pivot, "rotation", player._axe_pivot_home_rotation, 0.12)


func _axe_target_in_shape(target: Node, step: int) -> bool:
	var flat_offset: Vector3 = target.global_position - player._axe_attack_origin
	flat_offset.y = 0.0
	var distance: float = flat_offset.length()
	if distance <= 0.01 or not player._axe_path_clear(target, player._axe_attack_origin, target.global_position):
		return false
	var along := player._axe_attack_direction.dot(flat_offset)
	if step == 0:
		var lateral := absf(player._axe_attack_direction.cross(flat_offset).y)
		return along > 0.0 and along <= float(player._axe_range[0]) and lateral <= player._axe_estoc_width * 0.5
	var facing_dot := player._axe_attack_direction.dot(flat_offset.normalized())
	return distance <= float(player._axe_range[1]) and facing_dot >= cos(deg_to_rad(player._axe_sweep_half_angle))


func _axe_target_in_radius(target: Node, radius: float) -> bool:
	var flat_offset: Vector3 = target.global_position - player._axe_attack_origin
	flat_offset.y = 0.0
	return flat_offset.length() > 0.01 and flat_offset.length() <= radius and player._axe_path_clear(target, player._axe_attack_origin, target.global_position)


func _axe_target_in_wave(target: Node) -> bool:
	var flat_offset: Vector3 = target.global_position - player._axe_attack_origin
	flat_offset.y = 0.0
	var distance: float = flat_offset.length()
	return distance > player._axe_wave_inner_radius and distance <= player._axe_wave_outer_radius and player._axe_path_clear(target, player._axe_attack_origin, target.global_position)


func _axe_path_clear(target: Node, from_position: Vector3, to_position: Vector3) -> bool:
	var world := player.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_position + Vector3.UP * 0.72, to_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player.get_rid(), target.get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


func _play_axe_animation(step: int, speed_multiplier: float = 1.0) -> void:
	if player._axe_pivot == null:
		return
	var speed_scale := 1.0 / maxf(0.01, speed_multiplier)
	var tween := player.create_tween()
	tween.set_parallel(false)
	tween.tween_property(player._axe_pivot, "position", player._axe_pivot_home, 0.01 * speed_scale)
	tween.tween_property(player._axe_pivot, "rotation", player._axe_pivot_home_rotation, 0.01 * speed_scale)
	if step == 0:
		# A readable thrust: the weapon lunges toward the target and snaps back.
		tween.tween_property(player._axe_pivot, "position", Vector3(0.5, 1.0, -0.20), 0.20 * speed_scale)
		tween.tween_property(player._axe_pivot, "position", Vector3(0.5, 1.0, -1.65), 0.10 * speed_scale)
		tween.tween_property(player._axe_pivot, "position", player._axe_pivot_home, 0.25 * speed_scale)
	elif step == 1:
		# A lateral sweep, with a brief anticipation in the opposite direction.
		tween.tween_property(player._axe_pivot, "rotation", Vector3(0.0, deg_to_rad(-65.0), deg_to_rad(-12.0)), 0.20 * speed_scale)
		tween.tween_property(player._axe_pivot, "rotation", Vector3(0.0, deg_to_rad(78.0), deg_to_rad(14.0)), 0.10 * speed_scale)
		tween.tween_property(player._axe_pivot, "rotation", player._axe_pivot_home_rotation, 0.30 * speed_scale)
	else:
		# Overhead slam: weapon rises, pauses, then drives down into the floor.
		tween.tween_property(player._axe_pivot, "rotation", Vector3(deg_to_rad(-72.0), 0.0, 0.0), 0.35 * speed_scale)
		tween.tween_property(player._axe_pivot, "rotation", Vector3(deg_to_rad(78.0), 0.0, 0.0), 0.25 * speed_scale)
		tween.tween_property(player._axe_pivot, "rotation", player._axe_pivot_home_rotation, 0.25 * speed_scale)
	if player._robot_visuals != null:
		var recoil := player.create_tween()
		recoil.tween_property(player._robot_visuals, "position", player._world_offset_to_visual_local(-player.aim_direction * (0.10 if step < 2 else 0.18)), 0.06)
		recoil.tween_property(player._robot_visuals, "position", Vector3.ZERO, 0.18 if step < 2 else 0.28)
		recoil.tween_property(player._robot_visuals, "rotation", Vector3(0.0, 0.0, deg_to_rad(-7.0 if step == 1 else 0.0)), 0.05)
		recoil.tween_property(player._robot_visuals, "rotation", Vector3.ZERO, 0.16)
	if player._axe_light != null:
		player._axe_light.light_energy = 8.0 if step == 2 else 5.0
		var light_tween := player.create_tween()
		light_tween.tween_property(player._axe_light, "light_energy", 0.0, 0.24 if step < 2 else 0.42)
	var rig := player.get_tree().current_scene.get_node_or_null("CameraRig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.05 if step < 2 else 0.13)


func _begin_axe_trail(step: int, speed_multiplier: float = 1.0) -> void:
	player._finish_axe_trail(0.08)
	player._trail_points.clear()
	player._trail_elapsed = 0.0
	player._trail_duration = (float(player._axe_preparation[step]) + float(player._axe_active[step]) + float(player._axe_recovery[step])) / maxf(0.01, speed_multiplier)
	player._trail_width = [0.07, 0.24, 0.13][step]
	player._trail_active = true
	player._trail_mesh = MeshInstance3D.new()
	player._trail_mesh.name = "AxeEnergyTrail"
	player._trail_material = player._create_fx_material(Color("#7befff") if step < 2 else Color("#d8fcff"), 0.78)
	player.get_tree().current_scene.add_child(player._trail_mesh)


func _update_axe_trail(delta: float) -> void:
	if not player._trail_active or player._axe_tip == null or player._trail_mesh == null:
		return
	player._trail_elapsed += delta
	var tip_position := player._axe_tip.global_position
	if player._trail_points.is_empty() or player._trail_points[-1].distance_to(tip_position) >= 0.025:
		player._trail_points.append(tip_position)
		if player._trail_points.size() > 18:
			player._trail_points.pop_front()
		player._rebuild_axe_trail()
	if player._trail_elapsed >= player._trail_duration:
		player._finish_axe_trail(0.22)


func _rebuild_axe_trail() -> void:
	if player._trail_mesh == null or player._trail_points.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, player._trail_material)
	for index in range(1, player._trail_points.size()):
		var previous := player._trail_points[index - 1]
		var current := player._trail_points[index]
		var movement := current - previous
		var side := movement.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.001:
			side = Vector3(-player.aim_direction.z, 0.0, player.aim_direction.x).normalized()
		var age_ratio := float(index) / float(player._trail_points.size() - 1)
		var segment_width := player._trail_width * lerpf(0.20, 1.0, age_ratio)
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
	player._trail_mesh.mesh = mesh


func _finish_axe_trail(fade_duration: float) -> void:
	if not player._trail_active:
		return
	player._trail_active = false
	var finished_mesh := player._trail_mesh
	var finished_material := player._trail_material
	player._trail_mesh = null
	player._trail_material = null
	if finished_mesh == null:
		return
	var tween := player.create_tween()
	if finished_material != null:
		tween.tween_method(Callable(player, "_set_material_alpha").bind(finished_material), finished_material.albedo_color.a, 0.0, fade_duration)
	tween.tween_callback(finished_mesh.queue_free)


func _trigger_hit_stop(duration: float) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.08
	var timer := player.get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = 1.0
	)


func _create_axe_lightning(step: int, tip_position: Vector3) -> void:
	var blade_origin := tip_position
	var forward: Vector3 = player._get_axe_forward()
	var blade_end := tip_position + forward * (0.75 if step == 0 else 0.45)
	var bolt_color := Color("#8ff7ff")
	for index in range(3 if step < 2 else 6):
		var side := Vector3.UP * randf_range(-0.20, 0.30) + Vector3(-forward.z, 0.0, forward.x) * randf_range(-0.45, 0.45)
		player._create_lightning_arc(blade_origin + side, blade_end + side * 0.3, bolt_color, 0.04, 0.26 if step < 2 else 0.42)


func _get_axe_forward() -> Vector3:
	if player._axe_tip != null:
		var forward := -player._axe_tip.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			return forward.normalized()
	return player.aim_direction


func _play_impact_fx(step: int, impact_point: Vector3, did_hit: bool, tip_position: Vector3, tip_forward: Vector3, phase: String = "") -> void:
	player._create_axe_lightning(step, tip_position)
	if step == 0:
		var start := tip_position
		var end := impact_point + Vector3.UP * 0.92 if did_hit else tip_position + tip_forward * 1.0
		for index in range(3):
			player._create_lightning_arc(start + Vector3.UP * (float(index) - 1.0) * 0.08, end + Vector3.UP * (float(index) - 1.0) * 0.08, Color("#67eaff") if index < 2 else Color("#d2fcff"), 0.05, 0.30)
		player._spawn_particle_burst(tip_position, Color("#a9f5ff"), 16 if did_hit else 8, 0.32, 5.0, 0.16, tip_forward, 42.0)
		if did_hit:
			player._create_hit_flash(impact_point, Color("#a9f5ff"), 0.65)
		else:
			player._create_surface_impact_fx(impact_point, -tip_forward, Color("#62e7ff"))
	elif step == 1:
		var center := tip_position
		var forward := tip_forward
		var side := Vector3(-forward.z, 0.0, forward.x)
		var reach := float(player._axe_range[1]) if not did_hit else maxf(0.5, (impact_point - player._axe_attack_origin).length())
		player._create_cleave_arc(center, forward, side, reach, 0.0, Color("#52e7ff"), 0.32)
		player._create_cleave_arc(center + Vector3.UP * 0.10, forward, side, reach * 0.92, 0.12, Color("#d5fcff"), 0.38)
		player._spawn_particle_burst(tip_position, Color("#55e9ff"), 22 if did_hit else 12, 0.42, 4.0, 0.14, tip_forward, 70.0)
		if did_hit:
			player._create_hit_flash(impact_point, Color("#72edff"), 0.8)
		else:
			player._create_surface_impact_fx(impact_point, -forward, Color("#52d9ef"))
	else:
		if phase == "center":
			player._create_hit_flash(impact_point, Color("#fff0a1"), 0.90)
			player._spawn_particle_burst(impact_point + Vector3.UP * 0.72, Color("#eaffff"), 22, 0.42, 5.0, 0.14)
			return
		player._create_shockwave_fx(impact_point)


func _create_slash_fan(radius: float, half_angle: float) -> MeshInstance3D:
	var slash := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material = player._create_fx_material(Color("#56dcff"), 0.72)
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
	var material: StandardMaterial3D = player._create_fx_material(color, 0.95)
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
	var material: StandardMaterial3D = player._create_fx_material(color, 0.95)
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
	player.get_tree().current_scene.add_child(arc)
	player._register_fx_budget(arc, "burst")
	var tween := player.create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale", Vector3(1.18, 1.0, 1.18), lifetime * 0.45)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(material), 0.95, 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(arc.queue_free)


func _create_shockwave_fx(impact_point: Vector3) -> void:
	player._create_shockwave_wave(impact_point, 0.55, Color("#8ff7ff"), 0.58)
	player._create_shockwave_wave(impact_point + Vector3.UP * 0.04, 0.34, Color("#e7ffff"), 0.42)
	var crater := MeshInstance3D.new()
	var crater_mesh := ImmediateMesh.new()
	var crater_material = player._create_fx_material(Color("#1d2730"), 0.96)
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
	player.get_tree().current_scene.add_child(crater)
	player._register_fx_budget(crater, "burst")
	crater.global_position = impact_point
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.28
	core_mesh.height = 0.32
	core.mesh = core_mesh
	var core_material = player._create_fx_material(Color("#07131e"), 0.98)
	core.material_override = core_material
	player.get_tree().current_scene.add_child(core)
	player._register_fx_budget(core, "burst")
	core.global_position = impact_point + Vector3.UP * 0.08
	var crust := MeshInstance3D.new()
	var crust_mesh := ImmediateMesh.new()
	var crust_material = player._create_fx_material(Color("#65ecff"), 0.95)
	crust_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, crust_material)
	for point in crater_points:
		crust_mesh.surface_add_vertex(point + Vector3.UP * 0.13)
	crust_mesh.surface_end()
	crust.mesh = crust_mesh
	player.get_tree().current_scene.add_child(crust)
	player._register_fx_budget(crust, "burst")
	crust.global_position = impact_point
	var tween := player.create_tween()
	tween.set_parallel(true)
	tween.tween_property(crater, "scale", Vector3(1.30, 1.0, 1.30), 0.70)
	tween.tween_property(core, "scale", Vector3(1.15, 0.75, 1.15), 0.55)
	tween.tween_property(crust, "scale", Vector3(1.55, 1.0, 1.55), 0.85)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(crater_material), 0.94, 0.0, 1.55)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(core_material), 0.98, 0.0, 1.15)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(crust_material), 0.95, 0.0, 1.38)
	tween.set_parallel(false)
	tween.tween_interval(0.90)
	tween.tween_callback(crater.queue_free)
	tween.tween_callback(core.queue_free)
	tween.tween_callback(crust.queue_free)
	for index in range(8):
		player._create_lightning_spark(impact_point, index)
	player._create_crater_fractures(impact_point)
	for index in range(6):
		var direction := Vector3(cos(TAU * float(index) / 6.0), 0.0, sin(TAU * float(index) / 6.0))
		player._create_lightning_arc(impact_point + Vector3.UP * 0.16, impact_point + direction * randf_range(1.2, 1.9) + Vector3.UP * 0.16, Color("#3de6ff"), 0.05, 0.60)
	player._spawn_particle_burst(impact_point + Vector3.UP * 0.18, Color("#a8f8ff"), 34, 0.75, 7.0, 0.19)
	player._spawn_particle_burst(impact_point + Vector3.UP * 0.12, Color("#ffb13b"), 16, 0.52, 5.0, 0.14)
	player._spawn_particle_burst(impact_point + Vector3.UP * 0.2, Color("#d19b70"), 22, 0.80, 4.0, 0.18)


func _create_shockwave_wave(origin: Vector3, radius: float, color: Color, lifetime: float) -> void:
	var wave := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material: StandardMaterial3D = player._create_fx_material(color, 0.92)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var points := 20
	for index in range(points + 1):
		var angle := TAU * float(index) / float(points)
		var irregular_radius := radius + randf_range(-0.10, 0.10)
		mesh.surface_add_vertex(Vector3(cos(angle) * irregular_radius, 0.12, sin(angle) * irregular_radius))
	mesh.surface_end()
	wave.mesh = mesh
	player.get_tree().current_scene.add_child(wave)
	player._register_fx_budget(wave, "burst")
	wave.global_position = origin
	var tween := player.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector3(3.0, 1.0, 3.0), lifetime)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(material), 0.92, 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(wave.queue_free)


func _create_crater_fractures(origin: Vector3) -> void:
	for index in range(7):
		var crack := MeshInstance3D.new()
		var mesh := ImmediateMesh.new()
		var material = player._create_fx_material(Color("#8cf4ff"), 0.96)
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		var angle := (TAU / 7.0) * float(index) + 0.18
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		for point_index in range(5):
			var distance := 0.28 + float(point_index) * 0.26
			var jitter := Vector3(-direction.z, 0.0, direction.x) * (0.06 if point_index % 2 == 0 else -0.04)
			mesh.surface_add_vertex(direction * distance + jitter + Vector3.UP * 0.17)
		mesh.surface_end()
		crack.mesh = mesh
		player.get_tree().current_scene.add_child(crack)
		player._register_fx_budget(crack, "burst")
		crack.global_position = origin
		var tween := player.create_tween()
		tween.tween_method(Callable(player, "_set_material_alpha").bind(material), 0.96, 0.0, 1.35)
		tween.tween_callback(crack.queue_free)


func _create_lightning_spark(origin: Vector3, index: int) -> void:
	var spark := MeshInstance3D.new()
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.055, 0.08, 1.2 + float(index % 3) * 0.35)
	spark.mesh = spark_mesh
	var spark_material = player._create_fx_material(Color("#b7f8ff"), 0.95)
	spark.material_override = spark_material
	player.get_tree().current_scene.add_child(spark)
	player._register_fx_budget(spark, "burst")
	var angle := (TAU / 8.0) * float(index)
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	spark.global_position = origin + direction * 0.45 + Vector3.UP * (0.10 + float(index % 2) * 0.08)
	spark.look_at(spark.global_position + direction, Vector3.UP)
	var tween := player.create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector3(1.0, 1.0, 0.1), 0.48)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(spark_material), 0.95, 0.0, 0.52)
	tween.set_parallel(false)
	tween.tween_callback(spark.queue_free)


func _show_attack_hitbox(step: int, impact_point: Vector3 = Vector3.ZERO, did_hit: bool = false, tip_position: Vector3 = Vector3.ZERO, tip_forward: Vector3 = Vector3.ZERO, phase: String = "") -> void:
	if player._show_debug_hitbox:
		var hitbox := MeshInstance3D.new()
		hitbox.name = "AxeHitbox"
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.25, 0.85, 1.0, 0.42)
		material.emission_enabled = true
		material.emission = Color("#2ad9ff")
		material.emission_energy_multiplier = 2.0
		if step == 0:
			var estoc_mesh := BoxMesh.new()
			estoc_mesh.size = Vector3(player._axe_estoc_width, 0.06, float(player._axe_range[0]))
			hitbox.mesh = estoc_mesh
			hitbox.position = player._axe_attack_origin + player._axe_attack_direction * float(player._axe_range[0]) * 0.5
			hitbox.position.y = 0.04
			hitbox.look_at(hitbox.global_position + player._axe_attack_direction, Vector3.UP)
		elif step == 1:
			hitbox = player._create_slash_fan(float(player._axe_range[1]), deg_to_rad(player._axe_sweep_half_angle))
			hitbox.name = "AxeHitbox"
			hitbox.global_position = player._axe_attack_origin + Vector3.UP * 0.05
			hitbox.look_at(hitbox.global_position + player._axe_attack_direction, Vector3.UP)
		else:
			var ring_mesh := TorusMesh.new()
			if phase == "center":
				ring_mesh.inner_radius = 0.02
				ring_mesh.outer_radius = player._axe_wave_inner_radius
			else:
				ring_mesh.inner_radius = player._axe_wave_inner_radius
				ring_mesh.outer_radius = player._axe_wave_outer_radius
			ring_mesh.rings = 16
			ring_mesh.ring_segments = 32
			hitbox.mesh = ring_mesh
			hitbox.position = player._axe_attack_origin + Vector3.UP * 0.06
			hitbox.rotation_degrees.x = 90.0
		hitbox.material_override = material
		player.get_tree().current_scene.add_child(hitbox)
		if hitbox.material_override == null:
			hitbox.material_override = material
		var tween := player.create_tween()
		tween.tween_property(hitbox, "scale", Vector3.ONE * 1.12, 0.12)
		tween.tween_callback(hitbox.queue_free)
	if impact_point == Vector3.ZERO:
		impact_point = player.global_position + player.aim_direction * float(player._axe_range[step])
	if tip_position == Vector3.ZERO:
		tip_position = player._axe_tip.global_position if player._axe_tip != null else player.global_position + Vector3.UP * 0.96 + player.aim_direction * 1.68
	if tip_forward == Vector3.ZERO:
		tip_forward = player._get_axe_forward()
	player._play_impact_fx(step, impact_point, did_hit, tip_position, tip_forward, phase)
