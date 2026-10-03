extends Node

const COMBAT_AUDIO := preload("res://scripts/combat_audio.gd")

# Module cooldowns, defensive casts, dash, injector and buffered commands.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const STASIS_VISUAL := preload("res://scripts/stasis_visual.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "UtilityModulesComponent"


func reset_module_state() -> void:
	player._cancel_projector_cast()
	PLAYER_STATE.ROCKET_BASKET.clear(player)
	if player._counter != null:
		player._counter.cancel(true)
	player._projector_passive_remaining = 0.0
	if player.passive_state != null:
		player.passive_state.clear_triggers()
	player._eclipse.cancel(player)
	player._clear_permutation()
	player._cancel_javelin_charge()
	player._module_token += 1
	player._javelin_launch_token += 1
	player._static_pulse_token += 1
	player._module_cooldowns.clear()
	player._module_busy = false
	player._cancel_fulguro_attack()
	player._cancel_pelto_smash()
	player._cancel_fulguro_projection()
	player._cancel_pelto_pull()
	player._clear_defensive_buffer()
	for wave in player._pelto_waves:
		if wave != null and is_instance_valid(wave):
			wave.queue_free()
	player._pelto_waves.clear()
	player._javelin_mark_target = null
	player._dash_token += 1
	player._dash_active = false
	player._dash_direction = Vector3.ZERO
	player._dash_elapsed = 0.0
	player._bio_remaining = 0.0
	player._stasis_remaining = 0.0
	if is_instance_valid(player._stasis_visual):
		player._stasis_visual.queue_free()
	player._stasis_visual = null
	if player._magnetic_wall != null and is_instance_valid(player._magnetic_wall):
		player._magnetic_wall.queue_free()
	player._magnetic_wall = null
	if player._active_module_action_token != 0:
		player._end_module_action(player._active_module_action_token, player._active_module_id)


func _update_module_cooldowns(delta: float) -> void:
	player._longshot_state.tick(delta)
	player._projector_passive_remaining = maxf(0.0, player._projector_passive_remaining - delta)
	player._permutation_speed_remaining = maxf(0.0, player._permutation_speed_remaining - delta)
	var bio_active := player._bio_remaining > 0.0
	if bio_active:
		player._bio_remaining = maxf(0.0, player._bio_remaining - delta)
		if player._bio_remaining <= 0.0:
			COMBAT_AUDIO.play(player, "bio_end")
		if player._uses_local_feedback() and player._bio_remaining <= 1.0 and player._bio_remaining + delta > 1.0:
			player._spawn_particle_burst(player.global_position + Vector3.UP * 0.85, Color("#ffe6a0"), 12, 0.35, 2.0, 0.10, Vector3.UP, 60.0)
			if player._attack_label != null:
				player._attack_label.text = "BIO INJECTOR  •  DERNIÈRE SECONDE"
		elif player._uses_local_feedback() and player._bio_remaining <= 0.0:
			if player._attack_label != null:
				player._attack_label.text = "BIO INJECTOR  •  TERMINÉ"
	for module_id in player._module_cooldowns.keys():
		var rate := player._bio_other_cooldown_rate if bio_active and module_id != "bio_injector" else 1.0
		player._module_cooldowns[module_id] = maxf(0.0, float(player._module_cooldowns[module_id]) - delta * rate)


func get_module_cooldown(module_id: String) -> float:
	if player.training_instant_cooldowns:
		return 0.0
	if module_id == "pyro_boots":
		return PLAYER_STATE.PYRO_BOOTS.recharge_remaining(player._module_cooldowns)
	return maxf(0.0, float(player._module_cooldowns.get(module_id, 0.0)))


func is_module_busy() -> bool:
	return player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE)


func _module_ready(module_id: String) -> bool:
	if module_id == "pyro_boots":
		return player.get_pyro_charges() > 0
	return player.get_module_cooldown(module_id) <= 0.0


func _start_module_cooldown(module_id: String, duration: float) -> void:
	if player._presentation_component != null:
		player._presentation_component.begin_module_gesture(module_id)
	if module_id == "pyro_boots":
		PLAYER_STATE.PYRO_BOOTS.spend(player._module_cooldowns, 0.0 if player.training_instant_cooldowns else duration * float(player._survival_cooldown_multipliers.get("mobility", 1.0)))
		return
	var category := "offensive" if module_id in ["rocket_basket", "javelin", "fulguro_punch", "pelto_smash"] else "defensive" if module_id in ["magnetic_field", "static_shield", "projector", "counter"] else "mobility"
	player._module_cooldowns[module_id] = 0.0 if player.training_instant_cooldowns else maxf(0.0, duration * float(player._survival_cooldown_multipliers.get(category, 1.0)))


func get_mobility_module_id() -> String:
	return player._mobility_module_id


func get_defensive_module_id() -> String:
	return player._defensive_module_id


func get_stasis_remaining() -> float:
	return player._stasis_remaining


func _perform_defensive_module() -> void:
	if player._defensive_module_id == "":
		return
	if player._defensive_module_id == "projector":
		player._perform_projector()
	elif player._defensive_module_id == "counter":
		player._perform_counter()
	elif player._defensive_module_id == "static_shield":
		player._perform_static_shield()
	else:
		player._perform_magnetic_field()


func _perform_magnetic_field() -> void:
	if player.survival_mode and player.survival_evolution_effects != null and player._stasis_remaining <= 0.0 and (player.combat_state == null or not player.combat_state.is_stunned()) and player.survival_evolution_effects.release_wall():
		return
	if player._stasis_remaining > 0.0 or player._fulguro_projection_active or not player._module_ready("magnetic_field") or (player.combat_state != null and player.combat_state.is_stunned()):
		return
	var direction := player.aim_direction.normalized()
	var origin := player.global_position
	var center := PLAYER_STATE.MAGNETIC_WALL.find_placement(player, direction, player._magnetic_distance, player._magnetic_width, player._magnetic_height, player.gameplay_arena_center)
	if not center.is_finite():
		if player._attack_label != null:
			player._attack_label.text = "MAGNETIC FIELD  •  PLACEMENT REFUSÉ"
		return
	var action_token: int = player._try_begin_module_action("magnetic_field")
	if action_token == 0:
		return
	player._mark_combat_event()
	player._module_busy = true
	player._module_token += 1
	var token := player._module_token
	player._start_module_cooldown("magnetic_field", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["magnetic_field"]["cooldown"]))
	if player._attack_label != null:
		player._attack_label.text = "MAGNETIC FIELD  •  PRÉPARATION"
	var timer := player.get_tree().create_timer(player._magnetic_preparation, true, false, false)
	timer.timeout.connect(func() -> void: player._create_magnetic_wall(token, action_token, center, direction))


func _magnetic_placement_valid(origin: Vector3, center: Vector3) -> bool:
	if absf(center.x - player.gameplay_arena_center.x) > 23.0 or absf(center.z - player.gameplay_arena_center.z) > 23.0:
		return false
	var world := player.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.72, center + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()])
	return world.direct_space_state.intersect_ray(query).is_empty()


func _create_magnetic_wall(token: int, action_token: int, center: Vector3, direction: Vector3) -> void:
	if token != player._module_token or not player._module_action_can_execute(action_token, "magnetic_field"):
		return
	player._presentation_component.confirm_module_release("magnetic_field")
	var wall := PLAYER_STATE.MAGNETIC_WALL.new()
	wall.configure(player, player._magnetic_width, player._magnetic_height, player._magnetic_duration)
	player.get_tree().current_scene.add_child(wall)
	wall.global_position = center
	wall.rotation.y = atan2(direction.x, direction.z)
	player._magnetic_wall = wall
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.wall_created(wall, direction)
	player._survival_magnetic_clock = 0.0
	player._end_module_action(action_token, "magnetic_field")
	if player._attack_label != null:
		player._attack_label.text = "WALL  •  %.1fs" % player._magnetic_duration
	var lifetime_timer := player.get_tree().create_timer(player._magnetic_duration, true, false, false)
	var wall_reference: WeakRef = weakref(wall)
	lifetime_timer.timeout.connect(func() -> void:
		var surviving_wall: Area3D = wall_reference.get_ref()
		if is_instance_valid(surviving_wall):
			surviving_wall.call("expire")
		if player._magnetic_wall == surviving_wall:
			player._magnetic_wall = null
	)


func _perform_static_shield() -> void:
	if not player._gameplay_enabled or player.is_real_dead():
		return
	var mobile_shield := player.survival_evolution_effects if player.survival_mode else null
	if mobile_shield != null and mobile_shield.shield_remaining > 0.0:
		COMBAT_AUDIO.play(player, "static_off")
		mobile_shield.shield_remaining = 0.0
		mobile_shield.shield_health = 0.0
		mobile_shield.shield_energy = 0.0
		if is_instance_valid(mobile_shield.shield_visual):
			mobile_shield.shield_visual.queue_free()
		mobile_shield.shield_visual = null
		if player._attack_label != null:
			player._attack_label.text = "STATIC SHIELD  •  SORTIE"
		return
	if player._stasis_remaining > 0.0:
		COMBAT_AUDIO.play(player, "static_off")
		player._stasis_remaining = 0.0
		if is_instance_valid(player._stasis_visual):
			player._stasis_visual.queue_free()
		player._stasis_visual = null
		if player._attack_label != null:
			player._attack_label.text = "STATIC SHIELD  •  SORTIE"
		return
	if not player._module_ready("static_shield"):
		return
	var action_token: int = player._try_begin_module_action("static_shield")
	if action_token == 0:
		return
	player._cancel_fulguro_projection()
	player._cancel_pelto_pull()
	player._clear_defensive_buffer()
	PLAYER_STATE.PERMUTATION.cancel_for_actor(player)
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	if player._dash_active:
		player._cancel_dash()
	player._mark_combat_event()
	player._start_module_cooldown("static_shield", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["static_shield"]["cooldown"]))
	COMBAT_AUDIO.play(player, "static_on")
	if player.passive_authoritative() and player.combat_state != null:
		player.combat_state.cleanse_burn_and_slow()
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.activate_shield()
		player.survival_evolution_effects.shield_remaining = minf(player.survival_evolution_effects.shield_remaining, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.static_shield.duration))
		player._end_module_action(action_token, "static_shield")
		return
	player._static_pulse_token += 1
	var pulse_token := player._static_pulse_token
	player._static_duration = minf(player._static_duration, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.static_shield.duration))
	player._stasis_remaining = player._static_duration
	if player._attack_label != null:
		player._attack_label.text = "STATIC SHIELD  •  PURIFIÉ  •  %.1fs" % player._stasis_remaining
	player._create_stasis_fx()
	player._end_module_action(action_token, "static_shield")
	if player._survival_evolved("defensive"):
		var pulse_timer := player.get_tree().create_timer(player._static_duration, false)
		pulse_timer.timeout.connect(func() -> void:
			if pulse_token == player._static_pulse_token and player.is_inside_tree() and not player.is_real_dead() and player.survival_mode and player._defensive_module_id == "static_shield":
				player._survival_area_damage(player.global_position, 4.0, 70.0, "static_pulse", Color("#ba97ff"))
		)


func _create_stasis_fx() -> void:
	if is_instance_valid(player._stasis_visual):
		player._stasis_visual.queue_free()
	var shield := STASIS_VISUAL.new()
	shield.configure(player._static_duration, Callable(player, "get_stasis_remaining"))
	player._stasis_visual = shield
	player.add_child(shield)
	shield.tree_exiting.connect(func() -> void:
		if player._stasis_visual == shield:
			player._stasis_visual = null
	)


func get_bio_remaining() -> float:
	return player._bio_remaining


func get_current_move_speed() -> float:
	var slow_multiplier := 1.0
	if player.combat_state != null:
		slow_multiplier = 1.0 - player.combat_state.get_slow_percent() / 100.0
	var charge_multiplier := player._blaster_charge_slow_multiplier if player._blaster_charge_active else 1.0
	if player._active_module_id == "rocket_basket":
		charge_multiplier *= float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.rocket_basket.cast_move_multiplier)
	var evolution_speed: float = player.survival_evolution_effects.movement_multiplier() if player.survival_mode and player.survival_evolution_effects != null else 1.0
	var permutation_speed := float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.speed_multiplier) if player._permutation_speed_remaining > 0.0 else 1.0
	return player.move_speed * (player._bio_speed_multiplier if player._bio_remaining > 0.0 else 1.0) * permutation_speed * slow_multiplier * charge_multiplier * evolution_speed * player._longshot_state.movement_multiplier()


func get_attack_speed_multiplier() -> float:
	var boost: float = player.survival_evolution_effects.attack_multiplier() if player.survival_mode and player.survival_evolution_effects != null else 1.0
	return (player._bio_attack_speed_multiplier if player._bio_remaining > 0.0 else 1.0) * boost


func is_dash_active() -> bool:
	return player._dash_active


func _perform_mobility_module() -> void:
	if player._mobility_module_id == "":
		return
	if player._mobility_module_id == "bio_injector":
		player._perform_bio_injector()
	elif player._mobility_module_id == "permutation":
		player._perform_permutation()
	elif player._mobility_module_id == "eclipse":
		player._eclipse.begin(player)
	else:
		player._perform_pyro_boots()


func _perform_pyro_boots(direction_override: Vector3 = Vector3.ZERO) -> void:
	if player._stasis_remaining > 0.0 or player._fulguro_projection_active or player._dash_active or (player.combat_state != null and player.combat_state.is_stunned()):
		return
	if not (player.survival_mode and player.survival_evolution_effects != null) and not player._module_ready("pyro_boots"):
		return
	var direction := direction_override if direction_override.length_squared() > 0.001 else player._last_move_direction if player._last_move_direction.length_squared() > 0.001 else player.aim_direction.normalized()
	if direction.length_squared() <= 0.001:
		return
	var action_token: int = player._try_begin_module_action("pyro_boots")
	if action_token == 0:
		return
	if player.survival_mode and player.survival_evolution_effects != null and not player.survival_evolution_effects.prepare_dash():
		player._end_module_action(action_token, "pyro_boots")
		return
	player._cancel_pelto_pull()
	player._mark_combat_event()
	player._dash_token += 1
	player._dash_active = true
	player._dash_direction = direction.normalized()
	player._dash_elapsed = 0.0
	player._start_module_cooldown("pyro_boots", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["cooldown"]))
	if player._attack_label != null:
		player._attack_label.text = "PYRO BOOTS  •  DASH"
	player._create_dash_fx(player.global_position)
	if player.passive_authoritative():
		var scene := player.get_tree().current_scene
		var targets: Array = player._survival_targets() if player.survival_mode else scene.call("get_training_targets") if scene.has_method("get_training_targets") else [player._module_target()]
		PLAYER_STATE.PYRO_BOOTS.departure(player, targets, "player", "pyro:%d:%d:%d" % [player.get_instance_id(), player._visibility_epoch, player._dash_token], Callable(player, "_credit_pyro_damage"))
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.dash_started()
	player.get_node("/root/GameSfx").play_event("pyro_dash")
	player._end_module_action(action_token, "pyro_boots")


func _perform_bio_injector() -> void:
	if player._stasis_remaining > 0.0 or player._fulguro_projection_active or player._bio_remaining > 0.0 or not player._module_ready("bio_injector") or (player.combat_state != null and player.combat_state.is_stunned()):
		return
	var action_token: int = player._try_begin_module_action("bio_injector")
	if action_token == 0:
		return
	player._mark_combat_event()
	player._start_module_cooldown("bio_injector", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["cooldown"]))
	player._bio_remaining = float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["duration"])
	COMBAT_AUDIO.play(player, "bio_inject")
	COMBAT_AUDIO.play(player, "bio_boost")
	if player.passive_state != null and player.passive_authoritative():
		player.passive_state.mobility_finished()
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.bio_started()
	if player._attack_label != null:
		player._attack_label.text = "BIO INJECTOR  •  %.1fs" % player._bio_remaining
	player._create_bio_fx()
	if player.survival_synergies != null:
		player.survival_synergies.arm_double()
	if player._survival_evolved("mobility"):
		player._survival_area_damage(player.global_position, 4.0, 70.0, "bio_pulse", Color("#73f0bb"))
	player._end_module_action(action_token, "bio_injector")


func _update_dash(delta: float) -> void:
	if not player._dash_active:
		return
	var remaining_time := maxf(0.0, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.pyro_boots.dash_duration) - player._dash_elapsed)
	delta = minf(delta, remaining_time)
	player._dash_elapsed += delta
	var dash_distance := float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["dash_distance"]) * player._survival_dash_multiplier
	var dash_duration := float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["dash_duration"])
	var step := dash_distance * delta / maxf(0.001, dash_duration)
	var collision := player.move_and_collide(ARENA_TRAVERSAL.motion(player, player._dash_direction * step))
	var blocked := false
	# Spend only the remaining motion along the wall, never a fresh full step.
	# A frontal impact still stops; corners allow at most two further contacts.
	for contact in range(2):
		if collision == null:
			break
		var normal := collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() <= 0.001:
			blocked = true
			break
		normal = normal.normalized()
		var tangent := player._dash_direction.slide(normal)
		if tangent.length_squared() < 0.16:
			blocked = true
			break
		player._dash_direction = tangent.normalized()
		var slide_motion := collision.get_remainder().slide(normal)
		slide_motion.y = 0.0
		if slide_motion.length_squared() <= 0.000001:
			break
		collision = player.move_and_collide(ARENA_TRAVERSAL.motion(player, slide_motion))
		blocked = collision != null
	ARENA_TRAVERSAL.snap(player)
	if player.survival_synergies != null:
		player.survival_synergies.pyro_step(player.global_position)
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.pyro_step(player.global_position)
	if player._survival_evolved("mobility"):
		player._survival_trail_clock += delta
		if player._survival_trail_clock >= 0.12:
			player._survival_trail_clock = 0.0
			player._survival_area_damage(player.global_position, 1.5, 24.0, "pyro_trail", Color("#ff8a45"))
	if blocked or player._dash_elapsed >= dash_duration:
		player._finish_dash(not blocked)


func _finish_dash(completed: bool = true) -> void:
	if player.passive_state != null and player.passive_authoritative():
		player.passive_state.dash_finished(completed)
		if completed and player._passive_id == "inertia":
			player._create_dash_fx(player.global_position)
	player._dash_active = false
	player._dash_direction = Vector3.ZERO
	if player._attack_label != null:
		player._attack_label.text = "MOBILITÉ : PYRO BOOTS"


func _cancel_dash() -> void:
	if not player._dash_active:
		return
	player._dash_token += 1
	player._dash_active = false
	player._dash_direction = Vector3.ZERO
	if player._attack_label != null:
		player._attack_label.text = "DASH  •  INTERROMPU"


func _can_buffer_defensive_action() -> bool:
	return not player.is_real_dead() and (player._fulguro_projection_active or player._fulguro_wall_stun_active)


func _buffer_dash() -> void:
	var direction := player._last_move_direction if player._last_move_direction.length_squared() > 0.001 else player.aim_direction
	player._defensive_buffer = {"type": "dash", "direction": PLAYER_STATE.FULGURO.flat_direction(direction)}
	if player._attack_label != null:
		player._attack_label.text = "BUFFER  •  DASH"


func _has_live_javelin_mark() -> bool:
	return player._javelin_mark_target != null and is_instance_valid(player._javelin_mark_target) and player._javelin_mark_target.has_method("has_javelin_mark") and bool(player._javelin_mark_target.call("has_javelin_mark"))


func _buffer_javelin_recast() -> void:
	if not player._has_live_javelin_mark():
		return
	var destination: Vector3 = player._find_javelin_destination(player._javelin_mark_target)
	player._defensive_buffer = {"type": "teleport", "target": player._javelin_mark_target, "destination": destination}
	if player._attack_label != null:
		player._attack_label.text = "BUFFER  •  TÉLÉPORTATION"


func _try_execute_defensive_buffer() -> void:
	if player._defensive_buffer.is_empty() or player.is_action_locked():
		return
	var command := player._defensive_buffer.duplicate()
	player._defensive_buffer.clear()
	match str(command.get("type", "")):
		"dash":
			if player._mobility_module_id == "pyro_boots" and player._module_ready("pyro_boots"):
				var direction: Vector3 = command.get("direction", Vector3.ZERO)
				if direction.length_squared() > 0.001:
					player._perform_pyro_boots(direction)
		"teleport":
			var target := command.get("target") as Node
			var destination: Vector3 = command.get("destination", Vector3.INF)
			if player._offensive_module_id == "javelin" and target == player._javelin_mark_target and player._has_live_javelin_mark() and destination.is_finite() and player._javelin_destination_valid(target, destination):
				player._recast_javelin(destination)


func _clear_defensive_buffer() -> void:
	player._defensive_buffer.clear()


func get_buffered_defensive_action() -> String:
	return str(player._defensive_buffer.get("type", ""))


func _create_dash_fx(origin: Vector3) -> void:
	var direction := -player._dash_direction if player._dash_direction.length_squared() > 0.001 else -player.aim_direction
	if player._dash_active:
		PLAYER_STATE.PYRO_BOOTS.new().ignite(player, player._dash_direction, player)
	player._spawn_particle_burst(origin + Vector3.UP * 0.15, Color("#d99562"), 10, 0.24, 3.8, 0.10, direction + Vector3.UP * 0.28, 28.0)


func _create_bio_fx() -> void:
	player._spawn_particle_burst(player.global_position + Vector3.UP * 0.85, Color("#85bfa5"), 7, 0.30, 1.2, 0.09, Vector3.UP, 24.0)
