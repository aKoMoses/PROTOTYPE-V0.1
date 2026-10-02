extends Node

# Health, passives, status effects, death and bush visibility.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "CombatComponent"


func _mark_combat_event() -> void:
	if player._visual_rig != null and player._visual_rig.presence_modifier != null:
		player._visual_rig.presence_modifier.interrupt_rest()
	player.get_node("/root/GameSfx").mark_combat()
	if player.visibility_state != null:
		player.visibility_state.mark_combat_event()
	player._update_bush_presentation()


func get_combat_reveal_remaining() -> float:
	return player.visibility_state.combat_remaining if player.visibility_state != null else 0.0


func get_spotted_reveal_remaining() -> float:
	return player.visibility_state.spotted_remaining if player.visibility_state != null else 0.0


func is_revealed() -> bool:
	return player.visibility_state != null and player.visibility_state.is_revealed()


func is_attack_committed() -> bool:
	return player._action_gate.is_busy()


func is_in_bush() -> bool:
	player._sync_bush_state()
	return player._current_bush != null and is_instance_valid(player._current_bush)


func get_current_bush_name() -> String:
	return player._current_bush_name if player.is_in_bush() else ""


func get_current_bush() -> Node3D:
	player._sync_bush_state()
	return player._current_bush


func is_bush_concealed() -> bool:
	return player.is_in_bush() and not player.is_revealed()


func get_bush_transition_clock() -> float:
	return player._bush_transition_clock


func is_visible_to(observer: Node3D) -> bool:
	return player.get_visibility_weight(observer) > 0.0


func get_vision_radius() -> float:
	return player.vision_radius


func get_vision_fade_width() -> float:
	return player.vision_fade_width


func get_visibility_epoch() -> int:
	return player._visibility_epoch


func get_visibility_weight(observer: Node3D) -> float:
	if player.is_eclipse_travelling():
		return 0.0
	if observer == null or not is_instance_valid(observer):
		return 1.0
	if observer == player:
		return 1.0
	var range_alpha := PLAYER_STATE.VISIBILITY_STATE.range_weight(player, observer)
	if range_alpha <= 0.0:
		return 0.0
	var world := player.get_world_3d()
	if world == null:
		return range_alpha if PLAYER_STATE.BUSH_STATE.visible_to(player, observer, player.is_revealed(), true) else 0.0
	var query := PhysicsRayQueryParameters3D.create(observer.global_position + Vector3.UP * 0.72, player.global_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()])
	if observer is CollisionObject3D:
		query.exclude.append(observer.get_rid())
	var line_of_sight := world.direct_space_state.intersect_ray(query).is_empty()
	return range_alpha if PLAYER_STATE.BUSH_STATE.visible_to(player, observer, player.is_revealed(), line_of_sight) else 0.0


func _update_bush_state(delta: float) -> void:
	player._sync_bush_state()
	player._bush_transition_clock = maxf(0.0, player._bush_transition_clock - delta)
	player._update_bush_presentation()


func _sync_bush_state() -> void:
	var next_bush: Node3D = player._find_bush_at_position()
	var changed := next_bush != player._current_bush
	var was_in_bush := player._current_bush != null and is_instance_valid(player._current_bush)
	player._current_bush = next_bush
	player._current_bush_name = str(next_bush.name) if next_bush != null else ""
	if changed:
		player._bush_transition_clock = 0.22
		player.bush_state_changed.emit(player._current_bush != null, player._current_bush_name)
		# Local feedback only: enemy movement in concealed grass stays silent.
		if player._gameplay_enabled and player._uses_local_feedback() and was_in_bush != (player._current_bush != null):
			var sfx := player.get_node_or_null("/root/GameSfx")
			if sfx != null:
				sfx.call("play_event", "bush_entry" if player._current_bush != null else "bush_exit")


func _uses_local_feedback() -> bool:
	return true


func _find_bush_at_position() -> Node3D:
	return PLAYER_STATE.BUSH_STATE.find_bush(player)


func _update_bush_presentation() -> void:
	if player._bush_status_label == null:
		return
	player._bush_status_label.visible = player._gameplay_enabled and player._current_bush != null and not player.is_real_dead()
	if player._attack_label != null:
		player._attack_label.position.y = 4.15 * PLAYER_STATE.COMBAT_DATA.CHARACTER_VISUAL_SCALE + (0.9 if player._bush_status_label.visible else 0.0)
	if not player._bush_status_label.visible:
		if player._visual_rig != null:
			player._visual_rig.set_bush_concealed(false)
		return
	var remaining = maxf(player.get_combat_reveal_remaining(), player.get_spotted_reveal_remaining())
	if remaining > 0.0:
		player._bush_status_label.text = "RÉVÉLÉ  ·  %.1f s" % remaining
		player._bush_status_label.modulate = Color("#ffc77a")
		if player._visual_rig != null:
			player._visual_rig.set_bush_concealed(false)
		return
	for enemy in player.get_tree().get_nodes_in_group("prototype0_combat_bots"):
		if enemy is Node3D and enemy.is_visible_in_tree() and not bool(enemy.call("is_real_dead")) and PLAYER_STATE.BUSH_STATE.shares_bush(player, enemy) and player.is_visible_to(enemy):
			player._bush_status_label.text = "DÉTECTÉ"
			player._bush_status_label.modulate = Color("#ffc77a")
			if player._visual_rig != null:
				player._visual_rig.set_bush_concealed(false)
			return
	player._bush_status_label.text = "CAMOUFLÉ"
	player._bush_status_label.modulate = Color("#9fdaa0")
	if player._visual_rig != null:
		player._visual_rig.set_bush_concealed(true)


func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if player.is_eclipse_travelling():
		return 0.0
	if player.training_invulnerable:
		return 0.0
	if player._stasis_remaining > 0.0:
		return 0.0
	if player.combat_state == null or player.passive_state == null:
		return 0.0
	if player.survival_mode and player.survival_evolution_effects != null:
		amount = player.survival_evolution_effects.receive_damage(amount, attack_id)
		if amount <= 0.0:
			return 0.0
	if amount <= 0.0 or (attack_id != "" and (player._received_attack_ids.has(attack_id) or player.combat_state._processed_attack_ids.has(attack_id))):
		return 0.0
	if attack_id != "":
		player._received_attack_ids[attack_id] = true
	if amount > 0.0 and player.visibility_state != null:
		player._mark_combat_event()
	amount = player.combat_state.absorb_shield_damage(amount)
	if amount <= 0.0:
		if attack_id != "":
			player.combat_state._processed_attack_ids[attack_id] = true
		return 0.0
	var result: Dictionary = player.passive_state.intercept_damage(amount, player.combat_state.health)
	if bool(result["triggered_baroud"]):
		player.get_node("/root/GameSfx").play_event("baroud_activation")
		player._low_health_sound_armed = false
		if player.survival_mode and player.survival_evolution_effects != null:
			player.combat_state.health = 1.0
			player.combat_state.health_changed.emit(player.combat_state.health, player.combat_state.max_health)
			player.survival_evolution_effects.start_baroud()
		if player._survival_evolved("passive") and player._passive_id == "baroud":
			player._survival_area_damage(player.global_position, 4.0, 90.0, "baroud_pulse", Color("#f17285"))
		if player._attack_label != null and not player.survival_mode:
			player._attack_label.text = "BAROUD D'HONNEUR  •  2.5s"
		return 0.0
	var effective := float(result["effective"])
	if effective <= 0.0:
		return 0.0
	player.get_node("/root/GameSfx").play_event("damage_received")
	player.effective_damage_taken.emit(effective, source_id, attack_id)
	player._external_damage_pending = true
	if bool(result["real_death"]):
		player.combat_state.apply_damage(player.combat_state.health, source_id, attack_id)
	else:
		# Baroud damage is kept on its temporary gauge, not normal PV.
		if player.passive_state.baroud_active:
			if player._attack_label != null:
				player._attack_label.text = "BAROUD  •  %d PV" % int(round(player.passive_state.baroud_health))
		else:
			player.combat_state.apply_damage(effective, source_id, attack_id)
	player._external_damage_pending = false
	player.flash_impact(bool(result["real_death"]))
	return effective


func _finalize_passive_death() -> void:
	if player.combat_state == null or player.combat_state.is_dead():
		return
	player.combat_state.apply_damage(player.combat_state.health, "baroud", "baroud:expiry")
	if player._attack_label != null:
		player._attack_label.text = "ÉLIMINÉ"


func _on_state_died() -> void:
	if player._visual_rig != null:
		player._visual_rig.reset_presence()
	if player._counter != null:
		player._counter.cancel(true)
	if player.passive_state != null:
		player.passive_state.clear_triggers()
	player._eclipse.cancel(player)
	player._cancel_javelin_charge()
	player._clear_permutation()
	player._cancel_mekatana_attack()
	player.reset_longshot_state()
	if not player._gameplay_enabled:
		return
	if player._status_vfx != null:
		player._status_vfx.call("clear")
	player._round_warmup_active = false
	player._play_player_animation(&"fall", 0.10)
	player._gameplay_enabled = false
	player._update_bush_presentation()
	player._update_aim_pose_state()
	player.clear_touch_inputs()
	player._clear_defensive_buffer()
	player._cancel_fulguro_projection()
	player._cancel_fulguro_attack()
	player._cancel_pelto_smash()
	player._cancel_pelto_pull()
	player._cancel_blaster_charge()
	player._cancel_shotgun_attack()
	player._cancel_axe_attack()
	player._cancel_pending_module_action()
	player._static_pulse_token += 1
	player._reset_action_ownership()
	player.died.emit()


func is_real_dead() -> bool:
	return (player.passive_state != null and player.passive_state.real_dead) or (player.combat_state != null and player.combat_state.is_dead())


func set_passive(passive_id: String) -> void:
	if player.passive_state != null:
		player.passive_state.clear_triggers()
	player._passive_id = passive_id if passive_id in PLAYER_STATE.PASSIVE_STATE.IDS else ""
	if player.passive_state != null:
		player.passive_state.configure(player._passive_id)


func passive_authoritative() -> bool:
	return true


func emit_passive_weapon() -> Dictionary:
	var attack: Dictionary = player.passive_state.emit_weapon() if player.passive_state != null and player.passive_authoritative() else {}
	attack["counter_attack"] = PLAYER_STATE.COUNTER.weapon_attack(player, "weapon:%d:%d" % [player.get_instance_id(), Time.get_ticks_usec()], PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS.get(player._weapon_id, {}))
	return attack


func passive_weapon_damage(target: Node, amount: float, source: String, component: String, attack: Dictionary, impact_point: Vector3 = Vector3.INF) -> float:
	if not player.passive_authoritative() or not is_instance_valid(target) or target == player:
		return 0.0
	var point: Vector3 = impact_point if impact_point.is_finite() else target.global_position + Vector3.UP * 0.85
	var shield_before := PLAYER_STATE.PASSIVE_STATE.shield_health(target)
	var applied := PLAYER_STATE.COUNTER.impact(target, amount * float(attack.get("multiplier", 1.0)), source, component, attack.get("counter_attack", {}), point)
	if player.passive_state != null:
		var reduction: float = player.passive_state.weapon_hit(target, PLAYER_STATE.PASSIVE_STATE.accepted_damage(target, applied, shield_before), attack, player.get_module_cooldown(player._offensive_module_id))
		if reduction > 0.0:
			player._module_cooldowns[player._offensive_module_id] = maxf(0.0, player.get_module_cooldown(player._offensive_module_id) - reduction)
	return applied


func register_offensive_attack(activation: String) -> void:
	if player.passive_state != null and player.passive_authoritative():
		player.passive_state.register_module(activation)


func on_direct_offensive_hit(activation: String, applied: float, target: Node = null) -> void:
	if target != null and (not PLAYER_STATE.PASSIVE_STATE.combat_target(target) or not PLAYER_STATE.COUNTER.enemies(player, target)):
		return
	if player.passive_state != null and player.passive_authoritative():
		player.passive_state.module_hit(activation, applied)


func get_passive_weapon_point() -> Vector3:
	var muzzle: Node3D = player._longshot_muzzle if player._weapon_id == "longshot" else player._shotgun_muzzle if player._weapon_id == "shotgun" else player._blaster_muzzle if player._weapon_id == "blaster" else null
	return muzzle.global_position if is_instance_valid(muzzle) else player.global_position + Vector3.UP * 1.3 + player.aim_direction * 1.0


func get_tracker_locations() -> Array[Node3D]:
	return player.passive_state.revealed_targets() if player.passive_state != null else []


func get_passive_status() -> Dictionary:
	return player.passive_state.snapshot() if player.passive_state != null else {}


func get_passive_id() -> String:
	return player._passive_id


func get_baroud_remaining() -> float:
	return player.passive_state.baroud_remaining if player.passive_state != null else 0.0


func get_baroud_health() -> float:
	return player.passive_state.baroud_health if player.passive_state != null else 0.0


func _on_damage_dealt(effective_damage: float, target: Node3D = null) -> void:
	if effective_damage > 0.0:
		player._mark_combat_event()
	if player.passive_state == null:
		return
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.dealt_damage(effective_damage, target)
	var amount: float = float(player.passive_state.omnivamp_heal_for(effective_damage))
	if amount > 0.0:
		var actual: float = player.heal(amount, "omnivamp")
		if player.survival_mode and player.survival_evolution_effects != null:
			player.survival_evolution_effects.overflow_heal(amount - actual)


func get_health() -> float:
	return player.combat_state.health if player.combat_state != null else 0.0


func get_max_health() -> float:
	return player.combat_state.max_health if player.combat_state != null else PLAYER_STATE.COMBAT_DATA.MAX_HEALTH


func get_shield_health() -> float:
	return player.combat_state.shield_health if player.combat_state != null else 0.0


func get_active_effect_types() -> Array[String]:
	return player.combat_state.get_active_effect_types() if player.combat_state != null else []


func _on_health_changed(current: float, maximum: float) -> void:
	player._update_projector_threshold(current, maximum)
	var ratio := current / maxf(maximum, 1.0)
	if ratio >= 0.4:
		player._low_health_sound_armed = true
	elif current > 0.0 and ratio <= 0.25 and player._low_health_sound_armed and player._gameplay_enabled and not player.training_invulnerable:
		player._low_health_sound_armed = false
		player.get_node("/root/GameSfx").play_event("low_health")
	if player._health_readout != null:
		player._health_readout.call("set_health", current, maximum)


func _on_damage_applied(amount: float, source_id: String, _attack_id: String) -> void:
	if not player.combat_state.processing_burn and source_id != "surcharge":
		player._presentation_component.react_to_damage(amount)
	if not player._external_damage_pending:
		player.effective_damage_taken.emit(amount, source_id, _attack_id)
	# CombatState applies BURN directly, so all effective damage must refresh
	# reveal here as well as in take_damage's external damage path.
	if amount > 0.0:
		player._mark_combat_event()
		if source_id == "duel_bot" or source_id.begins_with("duel_bot:"):
			var scene := player.get_tree().current_scene
			var attacker := scene.get_node_or_null("TargetDummy") if scene != null else null
			if attacker != null and attacker.has_method("mark_combat_event"):
				attacker.call("mark_combat_event")
	if player._health_readout != null:
		player._health_readout.call("show_damage", amount)


func _on_healing_applied(amount: float, _source_id: String) -> void:
	if player._health_readout != null and player._health_readout.has_method("show_healing"):
		player._health_readout.call("show_healing", amount)
	if player._attack_label != null:
		player._attack_label.text = "SOIN  •  +%d PV" % roundi(amount)
	player._spawn_particle_burst(player.global_position + Vector3.UP * 1.05, Color("#72f0a5"), 10, 0.32, 2.2, 0.10, Vector3.UP, 58.0)


func heal(amount: float, source_id: String = "") -> float:
	if player._stasis_remaining > 0.0 or player.passive_state == null or not player.passive_state.can_heal():
		return 0.0
	return player.combat_state.heal(amount, source_id) if player.combat_state != null else 0.0


func apply_burn(duration: float = PLAYER_STATE.COMBAT_DATA.BURN_DURATION, damage_per_second: float = PLAYER_STATE.COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	if player.is_eclipse_travelling():
		return
	if player.combat_state != null:
		player.combat_state.apply_burn(duration, damage_per_second, source_id)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	if player.is_eclipse_travelling():
		return
	if player.combat_state != null:
		player.combat_state.apply_slow(duration, percent, source_id)


func apply_stun(duration: float, source_id: String = "") -> void:
	if player.is_eclipse_travelling():
		return
	if player.combat_state == null or not player.combat_state.can_receive_stun(duration):
		return
	player._controls_component.clear_command_buffer()
	if duration > 0.0:
		player._cancel_mekatana_attack()
	if duration > 0.0:
		player._cancel_longshot_attack()
	if duration > 0.0 and player._fulguro_phase != "":
		player._cancel_fulguro_attack("FULGURO PUNCH  •  INTERROMPU")
	if duration > 0.0 and player._pelto_phase != "":
		player._cancel_pelto_smash("PELTO SMASH  •  INTERROMPU")
	if duration > 0.0:
		player._cancel_pelto_pull()
		player._cancel_pending_module_action("MODULE  •  INTERROMPU")
		player._cancel_blaster_charge()
		player._cancel_blaster_attack()
		player._cancel_shotgun_attack()
		player._cancel_axe_attack()
	if player.combat_state != null:
		player.combat_state.apply_stun(duration, source_id)


func apply_spotted(duration: float, source_id: String = "") -> void:
	if player.is_eclipse_travelling():
		return
	if player.combat_state != null:
		player.combat_state.apply_spotted(duration, source_id)
	if player.visibility_state != null:
		player.visibility_state.mark_spotted(duration)
	player._update_bush_presentation()


func reset_combat_state() -> void:
	player.reset_longshot_state()
	player._low_health_sound_armed = true
	if player.is_inside_tree() and player._uses_local_feedback():
		player.get_node("/root/GameSfx").reset_locomotion()
	player._received_attack_ids.clear()
	player._visibility_epoch += 1
	player.clear_touch_inputs()
	player._clear_defensive_buffer()
	player._cancel_fulguro_projection()
	player._cancel_fulguro_attack()
	player._cancel_pelto_smash()
	player._cancel_pelto_pull()
	if player._status_vfx != null:
		player._status_vfx.call("clear")
	if player._health_readout != null:
		player._health_readout.call("clear_damage_numbers")
	if player.combat_state != null:
		player.combat_state.reset()
	if player.passive_state != null:
		player.passive_state.configure(player._passive_id)
		player.passive_state.reset()
	if player.visibility_state != null:
		player.visibility_state.reset()
	player._current_bush = player._find_bush_at_position()
	player._current_bush_name = str(player._current_bush.name) if player._current_bush != null else ""
	player._bush_transition_clock = 0.0
	player.reset_blaster_state()
	player.reset_shotgun_state()
	player.reset_module_state()
	player._reset_action_ownership()
	player._on_health_changed(player.get_health(), player.get_max_health())
	player._start_round_warmup_animation()
	player._update_bush_presentation()
