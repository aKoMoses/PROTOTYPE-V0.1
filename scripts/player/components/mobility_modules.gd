extends Node

# Specialized module behavior; state and public API stay on Player.
const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "MobilityModulesComponent"


func get_pyro_charges() -> int:
	return 2 if player.training_instant_cooldowns else PLAYER_STATE.PYRO_BOOTS.charges(player._module_cooldowns)


func is_eclipse_travelling() -> bool:
	return player._eclipse.travelling


func is_eclipse_aiming() -> bool:
	return player._eclipse.aiming


func set_eclipse_touch_vector(value: Vector2) -> void:
	player._eclipse.set_touch_vector(player, value)


func _perform_eclipse(destination: Vector3) -> bool:
	if player._mobility_module_id != "eclipse":
		return false
	return player._eclipse.depart(player, destination)


func _on_eclipse_arrived(_origin: Vector3, destination: Vector3) -> void:
	if player.passive_state != null and player.passive_authoritative():
		player.passive_state.mobility_finished()
	player.on_permutation_relocated()
	PLAYER_STATE.PERMUTATION.refresh_sweeps(player.get_tree())
	player.get_node("/root/GameSfx").play_event("javelin_teleport")
	if not player._permutation_authoritative():
		return
	var scene := player.get_tree().current_scene
	var targets: Array = []
	if player.survival_mode:
		targets = player._survival_targets()
	elif scene.has_method("get_training_targets"):
		targets = scene.call("get_training_targets")
	else:
		var target: Node = player._module_target()
		if is_instance_valid(target):
			targets.append(target)
	var attack_id := "eclipse:%d:%d" % [player.get_instance_id(), player._eclipse.serial]
	var definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.eclipse
	var radius := float(definition.explosion_radius)
	var hit := false
	for target in targets:
		if not is_instance_valid(target) or target == player or not target is Node3D or not target.has_method("take_damage"):
			continue
		if destination.distance_to(target.global_position) > radius or not player._solid_path_clear(destination, target.global_position):
			continue
		var shield_before := float(target.call("get_shield_health")) if target.has_method("get_shield_health") else 0.0
		var applied := float(target.call("take_damage", float(definition.damage), "player", attack_id))
		var shield_after := float(target.call("get_shield_health")) if target.has_method("get_shield_health") else 0.0
		if applied <= 0.0 and shield_after >= shield_before:
			continue
		hit = true
		if target.has_method("apply_burn"):
			target.call("apply_burn", float(definition.burn_duration), float(definition.burn_damage_per_second), "player:eclipse")
		if applied > 0.0:
			player._credit_eclipse_damage(applied)
		if target.has_method("flash_impact"):
			target.call("flash_impact", false)
	if hit:
		player.combat_state.grant_shield(float(definition.shield_amount), float(definition.shield_duration))


func _credit_eclipse_damage(amount: float) -> void:
	player._on_damage_dealt(amount)


func _permutation_target() -> Node3D:
	var scene := player.get_tree().current_scene
	if scene == null or not scene.has_method("get_training_targets"):
		return player._module_target() as Node3D
	var best: Node3D
	var best_alignment := -1.0
	var best_distance := INF
	# The mark acquires through cover. In multi-target training, aim chooses
	# the enemy; ordinary damaging projectiles retain their own LOS checks.
	for candidate in scene.call("get_training_targets"):
		if not candidate is Node3D or not PLAYER_STATE.PERMUTATION.can_activate(player, candidate):
			continue
		var offset: Vector3 = candidate.global_position - player.global_position
		offset.y = 0.0
		var alignment := player.aim_direction.normalized().dot(offset.normalized())
		var distance := offset.length()
		if alignment >= cos(deg_to_rad(25.0)) and (alignment > best_alignment + 0.001 or (absf(alignment - best_alignment) <= 0.001 and distance < best_distance)):
			best = candidate
			best_alignment = alignment
			best_distance = distance
	return best


func _perform_permutation() -> void:
	if player._action_incapacitated() or player._dash_active or player._pelto_pull_active or is_instance_valid(player._permutation_mark) or not player._module_ready("permutation"):
		return
	var target: Node3D = player._permutation_target()
	if not PLAYER_STATE.PERMUTATION.can_activate(player, target):
		if player._attack_label != null:
			player._attack_label.text = "PERMUTATION  •  AUCUNE CIBLE À %.0f m" % float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.activation_range)
		return
	var action_token: int = player._try_begin_module_action("permutation")
	if action_token == 0:
		return
	player._mark_combat_event()
	player._module_busy = true
	player._module_token += 1
	var token := player._module_token
	var target_epoch := PLAYER_STATE.PERMUTATION.epoch(target)
	player._start_module_cooldown("permutation", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.cooldown))
	if player._attack_label != null:
		player._attack_label.text = "PERMUTATION  •  PRÉPARATION"
	# Range is checked once on acceptance; escaping it never severs a mark.
	player.get_tree().create_timer(float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.preparation), false, true).timeout.connect(func() -> void:
		if token != player._module_token or not player._module_action_can_execute(action_token, "permutation"):
			return
		if not is_instance_valid(target) or not PLAYER_STATE.PERMUTATION.actor_available(target) or PLAYER_STATE.PERMUTATION.epoch(target) != target_epoch:
			player._end_module_action(action_token, "permutation")
			return
		var mark := PLAYER_STATE.PERMUTATION.new()
		player._presentation_component.confirm_module_release("permutation")
		mark.configure(player, target, player._permutation_authoritative())
		mark.arrived.connect(player._on_permutation_arrived)
		mark.failed.connect(player._on_permutation_failed)
		player.get_tree().current_scene.add_child(mark)
		player._permutation_mark = mark
		player._end_module_action(action_token, "permutation")
		if player._attack_label != null:
			player._attack_label.text = "PERMUTATION  •  MARQUE EN VOL"
	)


func _permutation_authoritative() -> bool:
	return true


func _on_permutation_arrived(_origin: Vector3, _destination: Vector3) -> void:
	player._permutation_mark = null
	if player.passive_state != null and player.passive_authoritative():
		player.passive_state.mobility_finished()
	player._permutation_speed_remaining = float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.duration)
	player.combat_state.grant_shield(float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.shield_amount), float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.shield_duration))
	if player._attack_label != null:
		player._attack_label.text = "PERMUTATION  •  VITESSE +35 % + BOUCLIER"
	player.get_node("/root/GameSfx").play_module_event("permutation_shield", player.global_position)


func _on_permutation_failed() -> void:
	player._permutation_mark = null
	if player._attack_label != null:
		player._attack_label.text = "PERMUTATION  •  ÉCHANGE IMPOSSIBLE"


func _clear_permutation() -> void:
	if is_instance_valid(player._permutation_mark):
		player._permutation_mark.stop_audio()
		player._permutation_mark.queue_free()
	player._permutation_mark = null
	player._permutation_speed_remaining = 0.0
	if player.combat_state != null:
		player.combat_state.clear_shield()


func get_permutation_speed_remaining() -> float:
	return player._permutation_speed_remaining


func on_permutation_relocated() -> void:
	# Preserve action tokens, charge clocks, phases, aim, dash and resources.
	player._update_world_ui_anchor()
	player._sync_bush_state()
	player._mark_combat_event()


func refresh_permutation_sweeps() -> void:
	player._mekatana_attack.rebase_after_teleport()


func start_knockback(direction: Vector3, distance: float, duration: float, source_id: String) -> void:
	if player._stasis_remaining > 0.0 or bool(player.get_meta("duel_static_shield", false)):
		return
	player.start_fulguro_projection(direction, distance, duration, 0.0, 0.0, source_id, "projector_push")
