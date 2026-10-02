extends Node

# Fulguro charge, strike, projection and wall impacts.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "FulguroComponent"


func get_fulguro_hit_radius() -> float:
	return 0.55


func is_fulguro_projected() -> bool:
	return player._fulguro_projection_active


func is_action_locked() -> bool:
	return player.is_real_dead() or player._stasis_remaining > 0.0 or player._fulguro_projection_active or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE) or (player.combat_state != null and player.combat_state.is_stunned())


func start_fulguro_projection(direction: Vector3, max_distance: float, max_duration: float, wall_damage: float, wall_stun: float, source_id: String, attack_id: String) -> void:
	if player.is_eclipse_travelling():
		return
	player._cancel_longshot_attack()
	if player.is_real_dead() or max_distance <= 0.0 or max_duration <= 0.0:
		return
	player._cancel_mekatana_attack()
	if player._counter != null:
		player._counter.cancel()
	player._cancel_pelto_pull()
	player._cancel_fulguro_attack("FULGURO PUNCH  •  PROJETÉ")
	player._cancel_pelto_smash("PELTO SMASH  •  PROJETÉ")
	if player._dash_active:
		player._cancel_dash()
	if player._blaster_charge_active or player._touch_fire_active:
		player.cancel_touch_fire("FULGURO PUNCH  •  PROJETÉ")
	if player._blaster_attack_busy:
		player._cancel_blaster_attack()
	if player._shotgun_attack_busy:
		player._cancel_shotgun_attack()
	player._cancel_pending_module_action()
	player._fulguro_projection_active = true
	player._fulguro_projection_direction = PLAYER_STATE.FULGURO.flat_direction(direction)
	player._fulguro_projection_distance_remaining = maxf(0.0, max_distance)
	player._fulguro_projection_time_remaining = maxf(0.001, max_duration)
	player._fulguro_projection_speed = PLAYER_STATE.KNOCKBACK.speed(player._fulguro_projection_distance_remaining, player._fulguro_projection_time_remaining)
	player._fulguro_projection_wall_damage = maxf(0.0, wall_damage)
	player._fulguro_projection_wall_stun = maxf(0.0, wall_stun)
	player._fulguro_projection_source_id = source_id
	player._fulguro_projection_attack_id = attack_id
	player.velocity = Vector3.ZERO
	player._spawn_particle_burst(player.global_position + Vector3.UP * 0.82, Color("#65e9ff"), 8, 0.22, 3.0, 0.09, player._fulguro_projection_direction, 24.0)


func _update_fulguro_projection(delta: float) -> void:
	if not player._fulguro_projection_active:
		return
	var available_time := minf(maxf(delta, 0.0), player._fulguro_projection_time_remaining)
	var step_distance := PLAYER_STATE.KNOCKBACK.step(player._fulguro_projection_distance_remaining, player._fulguro_projection_time_remaining, available_time)
	if step_distance <= 0.0001:
		player._finish_fulguro_projection(false)
		return
	var collision := player.move_and_collide(ARENA_TRAVERSAL.motion(player, player._fulguro_projection_direction * step_distance))
	ARENA_TRAVERSAL.snap(player)
	var travelled := step_distance
	if collision != null:
		travelled = collision.get_travel().length()
	player._fulguro_projection_distance_remaining = maxf(0.0, player._fulguro_projection_distance_remaining - travelled)
	player._fulguro_projection_time_remaining = maxf(0.0, player._fulguro_projection_time_remaining - available_time)
	player._fulguro_projection_speed = PLAYER_STATE.KNOCKBACK.speed(player._fulguro_projection_distance_remaining, player._fulguro_projection_time_remaining)
	if collision != null:
		var crushing := PLAYER_STATE.FULGURO.is_crushing_wall(collision.get_collider(), collision.get_normal(), player._fulguro_projection_direction)
		player._finish_fulguro_projection(crushing, collision.get_position(), collision.get_normal())
		return
	if player._fulguro_projection_distance_remaining <= 0.001 or player._fulguro_projection_time_remaining <= 0.001:
		player._finish_fulguro_projection(false)


func _finish_fulguro_projection(crushed_wall: bool, impact_position: Vector3 = Vector3.ZERO, impact_normal: Vector3 = Vector3.ZERO) -> void:
	if not player._fulguro_projection_active:
		return
	player._fulguro_projection_active = false
	player._fulguro_projection_distance_remaining = 0.0
	player._fulguro_projection_time_remaining = 0.0
	player._fulguro_projection_speed = 0.0
	player.velocity = Vector3.ZERO
	if crushed_wall and not player.is_real_dead():
		var wall_attack_id := "%s:wall" % player._fulguro_projection_attack_id
		var applied: float = player.take_damage(player._fulguro_projection_wall_damage, player._fulguro_projection_source_id, wall_attack_id)
		if applied > 0.0 and not player.is_real_dead():
			player._fulguro_wall_stun_active = true
			player.apply_stun(player._fulguro_projection_wall_stun, "fulguro_wall")
			player._spawn_fulguro_wall_impact(impact_position, impact_normal)
	player._try_execute_defensive_buffer()


func _cancel_fulguro_projection() -> void:
	player._fulguro_projection_active = false
	player._fulguro_projection_direction = Vector3.ZERO
	player._fulguro_projection_distance_remaining = 0.0
	player._fulguro_projection_time_remaining = 0.0
	player._fulguro_projection_speed = 0.0
	player._fulguro_wall_stun_active = false


func _spawn_fulguro_wall_impact(impact_position: Vector3, impact_normal: Vector3) -> void:
	var position := impact_position if impact_position != Vector3.ZERO else player.global_position + Vector3.UP * 0.85
	var normal := impact_normal if impact_normal.length_squared() > 0.001 else -player._fulguro_projection_direction
	var vfx: Node = player._vfx_manager()
	if vfx != null:
		vfx.call("impact", position, normal, "environment", 1.65, Color("#ffb34f"))
	player._spawn_particle_burst(position, Color("#ffca63"), 16, 0.34, 5.2, 0.13, normal, 48.0)
	player._camera_impulse(0.14, 0.11)


func _fulguro_targets() -> Array:
	var scene := player.get_tree().current_scene if player.get_tree() != null else null
	if scene == null:
		return []
	var targets: Array = []
	if scene.has_method("get_training_targets"):
		targets.append_array(scene.call("get_training_targets"))
	else:
		var target: Node = player._module_target()
		if is_instance_valid(target):
			targets.append(target)
	for rocket in player.get_tree().get_nodes_in_group("prototype0_homing_rockets"):
		if rocket.caster != player:
			targets.append(rocket)
	return targets


func _perform_fulguro_punch() -> void:
	player._begin_fulguro_charge()
	player._release_fulguro_charge()


func _begin_fulguro_charge() -> void:
	if player._stasis_remaining > 0.0 or player._fulguro_projection_active or not player._module_ready("fulguro_punch") or player.is_real_dead() or (player.combat_state != null and player.combat_state.is_stunned()):
		return
	var action_token: int = player._try_begin_module_action("fulguro_punch")
	if action_token == 0:
		return
	player._mark_combat_event()
	player._module_busy = true
	player._module_token += 1
	player._fulguro_attack_serial += 1
	player._fulguro_phase = "preparation"
	player._fulguro_elapsed = 0.0
	player._fulguro_direction = PLAYER_STATE.FULGURO.flat_direction(player.aim_direction)
	player._fulguro_hit_resolved = false
	player._fulguro_release_requested = false
	player._fulguro_release_at = -1.0
	player._fulguro_charge_ratio = 0.0
	player._fulguro_strike_range = player._fulguro_range
	player._fulguro_strike_damage = player._fulguro_damage
	player._fulguro_strike_wall_damage = player._fulguro_wall_damage
	player._fulguro_flame_clock = 0.0
	player._start_module_cooldown("fulguro_punch", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]["cooldown"]))
	player._create_fulguro_telegraph()
	if player._fulguro_charge_audio != null:
		player._fulguro_charge_audio.play()
	if player._attack_label != null:
		player._attack_label.text = "FULGURO PUNCH  •  CHARGE 0.00 / %.1f s" % player._fulguro_charge_max
	player._update_fulguro_pose()


func _release_fulguro_charge() -> void:
	if player._fulguro_phase != "preparation" or player._fulguro_release_requested:
		return
	player._fulguro_release_requested = true
	player._fulguro_release_at = clampf(maxf(player._fulguro_elapsed, player._fulguro_preparation), player._fulguro_preparation, player._fulguro_charge_max)


func get_fulguro_charge_fraction() -> float:
	if player._fulguro_phase != "preparation":
		return 0.0
	return clampf(player._fulguro_elapsed / maxf(0.001, player._fulguro_charge_max), 0.0, 1.0)


func is_fulguro_charging() -> bool:
	return player._fulguro_phase == "preparation"


func _update_fulguro_attack(delta: float) -> void:
	if player._fulguro_phase == "":
		return
	if not player._module_action_can_execute(player._active_module_action_token, "fulguro_punch"):
		player._cancel_fulguro_attack()
		return
	if player.is_real_dead() or player._stasis_remaining > 0.0 or player._fulguro_projection_active or (player.combat_state != null and player.combat_state.is_stunned()):
		player._cancel_fulguro_attack("FULGURO PUNCH  •  INTERROMPU")
		return
	if player._fulguro_phase == "preparation":
		var release_time := player._fulguro_release_at if player._fulguro_release_requested else player._fulguro_charge_max
		player._fulguro_elapsed = minf(player._fulguro_elapsed + maxf(0.0, delta), release_time)
		player._update_fulguro_telegraph(delta)
		player._update_fulguro_pose()
		if player._attack_label != null:
			var percent = int(round(player._fulguro_power_ratio() * 100.0))
			player._attack_label.text = "FULGURO PUNCH  •  CHARGE %.2f / %.1f s  •  %d%%" % [player._fulguro_elapsed, player._fulguro_charge_max, percent]
		if player._fulguro_elapsed >= release_time - 0.000001:
			player._commit_fulguro_strike()
		return
	var phase_duration := player._fulguro_active_window if player._fulguro_phase == "active" else player._fulguro_recovery
	player._fulguro_elapsed += maxf(0.0, delta)
	if player._fulguro_elapsed >= phase_duration:
		player._fulguro_elapsed = 0.0
		if player._fulguro_phase == "active":
			player._fulguro_phase = "recovery"
			if player._attack_label != null:
				player._attack_label.text = "FULGURO PUNCH  •  RÉCUPÉRATION"
		else:
			player._finish_fulguro_attack()
			return
	player._update_fulguro_pose()


func _fulguro_power_ratio() -> float:
	return clampf(inverse_lerp(player._fulguro_preparation, player._fulguro_charge_max, player._fulguro_elapsed), 0.0, 1.0)


func _commit_fulguro_strike() -> void:
	if not player._module_action_can_execute(player._active_module_action_token, "fulguro_punch"):
		player._cancel_fulguro_attack()
		return
	player._fulguro_charge_ratio = player._fulguro_power_ratio()
	player._fulguro_strike_range = lerpf(player._fulguro_range, player._fulguro_range_max, player._fulguro_charge_ratio)
	player._fulguro_strike_damage = lerpf(player._fulguro_damage, player._fulguro_damage_max, player._fulguro_charge_ratio)
	player._fulguro_strike_wall_damage = lerpf(player._fulguro_wall_damage, player._fulguro_wall_damage_max, player._fulguro_charge_ratio)
	player._fulguro_phase = "active"
	player._fulguro_elapsed = 0.0
	if player._fulguro_charge_audio != null:
		player._fulguro_charge_audio.stop()
	if player._fulguro_release_audio != null:
		player._fulguro_release_audio.pitch_scale = lerpf(1.03, 0.78, player._fulguro_charge_ratio)
		player._fulguro_release_audio.play()
	player._clear_fulguro_telegraph()
	player._resolve_fulguro_strike()
	player._spawn_fulguro_strike_fx()
	if player._attack_label != null:
		player._attack_label.text = "FULGURO PUNCH  •  DÉCHARGE INCANDESCENTE  •  %d%%" % int(round(player._fulguro_charge_ratio * 100.0))
	player._update_fulguro_pose()


func _resolve_fulguro_strike() -> void:
	if player._fulguro_hit_resolved:
		return
	player._fulguro_hit_resolved = true
	var attack_id := "fulguro:%d" % player._fulguro_attack_serial
	var target = PLAYER_STATE.FULGURO.resolve_strike(player, player._fulguro_targets(), player._fulguro_direction, player._fulguro_strike_damage, player._fulguro_strike_wall_damage, player._fulguro_wall_stun, "player", attack_id, player._fulguro_strike_range, player._fulguro_width)
	if target != null:
		var impact_position := (target as Node3D).global_position + Vector3.UP * 0.82
		player._create_target_hit_fx(impact_position, false)
		var vfx: Node = player._vfx_manager()
		if vfx != null:
			vfx.call("impact", impact_position, -player._fulguro_direction, "robot", lerpf(1.15, 1.85, player._fulguro_charge_ratio), Color("#ff7a24"))
		player._spawn_particle_burst(impact_position, Color("#fff0a3"), 10 + int(player._fulguro_charge_ratio * 10.0), 0.34, 5.0, 0.16, -player._fulguro_direction + Vector3.UP * 0.25, 52.0)
		if player._survival_evolved("offensive"):
			player._survival_area_damage((target as Node3D).global_position, 2.25, 45.0, "fulguro_incandescent_wave", Color("#ff8a32"), target)


func _create_fulguro_telegraph() -> void:
	player._clear_fulguro_telegraph()
	var root := Node3D.new()
	root.name = "FulguroTelegraph"
	var lane := MeshInstance3D.new()
	var lane_mesh := BoxMesh.new()
	lane_mesh.size = Vector3(player._fulguro_width, 0.025, player._fulguro_range)
	lane.mesh = lane_mesh
	lane.position = Vector3(0.0, 0.0, -player._fulguro_range * 0.5)
	lane.material_override = player._create_fx_material(Color("#ff7a24"), 0.46)
	root.add_child(lane)
	player._fulguro_lane_mesh = lane_mesh
	var tip := MeshInstance3D.new()
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(player._fulguro_width * 0.72, 0.035, 0.24)
	tip.mesh = tip_mesh
	tip.position = Vector3(0.0, 0.012, -player._fulguro_range + 0.10)
	tip.rotation.y = PI * 0.25
	tip.material_override = player._create_fx_material(Color("#ffd36a"), 0.82)
	root.add_child(tip)
	player._fulguro_tip_visual = tip
	var fist := MeshInstance3D.new()
	var fist_mesh := SphereMesh.new()
	fist_mesh.radius = 0.22
	fist_mesh.height = 0.38
	fist.mesh = fist_mesh
	fist.material_override = player._create_fx_material(Color("#ff5a16"), 0.78)
	root.add_child(fist)
	player._fulguro_fist_visual = fist
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.13
	core_mesh.height = 0.24
	core.mesh = core_mesh
	core.material_override = player._create_fx_material(Color("#fff2af"), 0.92)
	root.add_child(core)
	player._fulguro_fist_core = core
	player._fulguro_flame_tongues.clear()
	for index in range(3):
		var flame := MeshInstance3D.new()
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.085
		flame_mesh.height = 0.34
		flame.mesh = flame_mesh
		flame.material_override = player._create_fx_material(Color("#ff6a1f") if index != 1 else Color("#ffd66b"), 0.68)
		root.add_child(flame)
		player._fulguro_flame_tongues.append(flame)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff7b2f")
	light.light_energy = 1.2
	light.omni_range = 2.2
	light.shadow_enabled = false
	root.add_child(light)
	player._fulguro_flame_light = light
	player.get_tree().current_scene.add_child(root)
	player._fulguro_indicator = root
	player._update_fulguro_telegraph(0.0)


func _update_fulguro_telegraph(delta: float = 0.0) -> void:
	if player._fulguro_indicator == null or not is_instance_valid(player._fulguro_indicator):
		return
	player._fulguro_indicator.global_position = player.global_position + Vector3.UP * 0.055
	player._fulguro_indicator.global_basis = Basis.looking_at(player._fulguro_direction, Vector3.UP)
	var armed := clampf(player._fulguro_elapsed / maxf(0.001, player._fulguro_preparation), 0.0, 1.0)
	var power: float = player._fulguro_power_ratio()
	var live_range := lerpf(player._fulguro_range, player._fulguro_range_max, power)
	if player._fulguro_lane_mesh != null:
		player._fulguro_lane_mesh.size = Vector3(player._fulguro_width, 0.025 + power * 0.018, live_range)
	var lane := player._fulguro_indicator.get_child(0) as MeshInstance3D
	if lane != null:
		lane.position = Vector3(0.0, 0.0, -live_range * 0.5)
	if player._fulguro_tip_visual != null:
		player._fulguro_tip_visual.position = Vector3(0.0, 0.012, -live_range + 0.10)
		player._fulguro_tip_visual.scale = Vector3.ONE * (1.0 + power * 0.32 + sin(player._fulguro_elapsed * 18.0) * 0.05)
	if player._fulguro_fist_visual != null:
		var fist_position := Vector3(0.36, 0.88, 0.24 + armed * 0.18)
		var pulse := sin(player._fulguro_elapsed * lerpf(22.0, 48.0, power)) * (0.05 + power * 0.08)
		player._fulguro_fist_visual.position = fist_position
		player._fulguro_fist_visual.scale = Vector3.ONE * (0.74 + armed * 0.34 + power * 0.58 + pulse)
		var material := player._fulguro_fist_visual.material_override as StandardMaterial3D
		if material != null:
			material.emission = Color("#ff641c").lerp(Color("#fff1a6"), power * 0.72)
			material.emission_energy_multiplier = lerpf(1.8, 6.5, power)
		if player._fulguro_fist_core != null:
			player._fulguro_fist_core.position = fist_position + Vector3(0.0, 0.01, -0.025)
			player._fulguro_fist_core.scale = Vector3.ONE * (0.52 + power * 0.46 + sin(player._fulguro_elapsed * 55.0) * 0.06)
		for index in range(player._fulguro_flame_tongues.size()):
			var flame := player._fulguro_flame_tongues[index]
			var angle := player._fulguro_elapsed * lerpf(5.0, 9.0, power) + TAU * float(index) / float(player._fulguro_flame_tongues.size())
			flame.position = fist_position + Vector3(cos(angle) * (0.10 + power * 0.07), 0.13 + sin(angle * 1.7) * 0.05, sin(angle) * (0.08 + power * 0.05))
			flame.scale = Vector3(0.72 + power * 0.35, 1.05 + power * 0.85 + sin(angle * 2.0) * 0.16, 0.72 + power * 0.35)
		if player._fulguro_flame_light != null:
			player._fulguro_flame_light.position = fist_position
			player._fulguro_flame_light.light_energy = lerpf(1.2, 4.8, power) + sin(player._fulguro_elapsed * 36.0) * 0.25
			player._fulguro_flame_light.omni_range = lerpf(2.2, 4.1, power)
		player._fulguro_flame_clock -= delta
		if delta > 0.0 and player._fulguro_flame_clock <= 0.0:
			player._fulguro_flame_clock = lerpf(0.16, 0.065, power)
			var flame_origin := player._fulguro_fist_visual.global_position
			player._spawn_particle_burst(flame_origin, Color("#ff7628").lerp(Color("#fff0a0"), power * 0.65), 5 + int(power * 7.0), 0.28, lerpf(1.4, 3.5, power), 0.12, Vector3.UP - player._fulguro_direction * 0.20, 42.0)


func _clear_fulguro_telegraph() -> void:
	if player._fulguro_indicator != null and is_instance_valid(player._fulguro_indicator):
		player._fulguro_indicator.queue_free()
	player._fulguro_indicator = null
	player._fulguro_fist_visual = null
	player._fulguro_fist_core = null
	player._fulguro_flame_tongues.clear()
	player._fulguro_lane_mesh = null
	player._fulguro_tip_visual = null
	player._fulguro_flame_light = null


func _spawn_fulguro_strike_fx() -> void:
	var trail := MeshInstance3D.new()
	trail.name = "FulguroPunchTrail"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(player._fulguro_width * lerpf(0.62, 0.88, player._fulguro_charge_ratio), lerpf(0.28, 0.46, player._fulguro_charge_ratio), player._fulguro_strike_range)
	trail.mesh = mesh
	trail.material_override = player._create_fx_material(Color("#ff5a18"), 0.64)
	player.get_tree().current_scene.add_child(trail)
	trail.global_position = player.global_position + player._fulguro_direction * (player._fulguro_strike_range * 0.5) + Vector3.UP * 0.92
	trail.global_basis = Basis.looking_at(player._fulguro_direction, Vector3.UP)
	player._register_fx_budget(trail, "burst")
	var core := MeshInstance3D.new()
	core.name = "FulguroIncandescentCore"
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(player._fulguro_width * 0.28, 0.13, player._fulguro_strike_range * 0.98)
	core.mesh = core_mesh
	core.material_override = player._create_fx_material(Color("#fff0a0"), 0.90)
	player.get_tree().current_scene.add_child(core)
	core.global_position = trail.global_position
	core.global_basis = trail.global_basis
	player._register_fx_budget(core, "burst")
	var discharge_end := player.global_position + player._fulguro_direction * player._fulguro_strike_range + Vector3.UP * 0.90
	player._spawn_particle_burst(discharge_end, Color("#ff7928"), 12, 0.36, 5.0, 0.18, player._fulguro_direction, 28.0)
	player._spawn_particle_burst(discharge_end, Color("#fff3b0"), 8, 0.24, 4.2, 0.11, player._fulguro_direction, 20.0)
	for index in range(3 + int(player._fulguro_charge_ratio * 3.0)):
		var side := Vector3(-player._fulguro_direction.z, 0.0, player._fulguro_direction.x) * (float(index) - 2.0) * 0.055
		player._create_lightning_arc(player.global_position + Vector3.UP * 0.92 + side, discharge_end + side * 0.35, Color("#ffb044") if index % 2 == 0 else Color("#fff0a3"), 0.035 + player._fulguro_charge_ratio * 0.025, 0.18)
	var material := trail.material_override as StandardMaterial3D
	var core_material := core.material_override as StandardMaterial3D
	var tween := trail.create_tween()
	tween.set_parallel(true)
	tween.tween_property(trail, "scale", Vector3(0.55, 0.55, 1.08), player._fulguro_active_window)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(material), 0.72, 0.0, player._fulguro_active_window + 0.08)
	tween.tween_property(core, "scale", Vector3(0.48, 0.48, 1.12), player._fulguro_active_window)
	tween.tween_method(Callable(player, "_set_material_alpha").bind(core_material), 0.90, 0.0, player._fulguro_active_window + 0.10)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(trail):
			trail.queue_free()
		if is_instance_valid(core):
			core.queue_free()
	)


func _update_fulguro_pose() -> void:
	if player._visual_rig == null or not player._visual_rig.has_method("set_fulguro_pose"):
		return
	var duration := player._fulguro_active_window if player._fulguro_phase == "active" else player._fulguro_recovery
	var progress := clampf(player._fulguro_elapsed / maxf(0.001, duration), 0.0, 1.0)
	if player._fulguro_phase == "preparation":
		progress = clampf(player._fulguro_elapsed / maxf(0.001, player._fulguro_preparation), 0.0, 1.0)
	player._visual_rig.call("set_fulguro_pose", player._fulguro_phase, progress)


func _finish_fulguro_attack() -> void:
	var action_token := player._active_module_action_token if player._active_module_id == "fulguro_punch" else 0
	player._clear_fulguro_telegraph()
	if player._fulguro_charge_audio != null:
		player._fulguro_charge_audio.stop()
	if player._visual_rig != null and player._visual_rig.has_method("clear_fulguro_pose"):
		player._visual_rig.call("clear_fulguro_pose")
	player._fulguro_phase = ""
	player._fulguro_elapsed = 0.0
	player._fulguro_hit_resolved = false
	player._fulguro_release_requested = false
	player._fulguro_release_at = -1.0
	player._end_module_action(action_token, "fulguro_punch")
	player._update_aim_pose_state()
	if player._attack_label != null:
		player._attack_label.text = "FULGURO PUNCH  •  CD 8s"


func _cancel_fulguro_attack(reason: String = "") -> void:
	var action_token := player._active_module_action_token if player._active_module_id == "fulguro_punch" else 0
	if player._fulguro_phase == "" and action_token == 0:
		player._clear_fulguro_telegraph()
		return
	player._clear_fulguro_telegraph()
	if player._fulguro_charge_audio != null:
		player._fulguro_charge_audio.stop()
	if player._visual_rig != null and player._visual_rig.has_method("clear_fulguro_pose"):
		player._visual_rig.call("clear_fulguro_pose")
	player._fulguro_phase = ""
	player._fulguro_elapsed = 0.0
	player._fulguro_hit_resolved = false
	player._fulguro_release_requested = false
	player._fulguro_release_at = -1.0
	player._end_module_action(action_token, "fulguro_punch")
	player._update_aim_pose_state()
	if reason != "" and player._attack_label != null:
		player._attack_label.text = reason
