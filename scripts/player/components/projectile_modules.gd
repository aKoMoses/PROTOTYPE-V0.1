extends Node

const COMBAT_AUDIO := preload("res://scripts/combat_audio.gd")

# Modulo Drone and Javelin launch, hit and recast.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "ProjectileModulesComponent"


func _update_javelin_mark() -> void:
	if player._javelin_mark_target == null or not is_instance_valid(player._javelin_mark_target):
		player._javelin_mark_target = null
		return
	if not bool(player._javelin_mark_target.call("has_javelin_mark")):
		COMBAT_AUDIO.play(player, "javelin_mark_end")
		player._javelin_mark_target = null


func get_javelin_recast_fraction() -> float:
	if not player._has_live_javelin_mark() and player.survival_mode and player.survival_evolution_effects != null:
		return player.survival_evolution_effects.javelin_fraction()
	if player._javelin_mark_target == null or not is_instance_valid(player._javelin_mark_target):
		return 0.0
	if not player._javelin_mark_target.has_method("get_javelin_mark_remaining"):
		return 0.0
	var remaining := float(player._javelin_mark_target.call("get_javelin_mark_remaining"))
	return clampf(remaining / maxf(0.001, player._javelin_active_mark_duration), 0.0, 1.0)


func _perform_rocket_basket() -> void:
	if not player._module_ready("rocket_basket"):
		return
	var action_token: int = player._try_begin_module_action("rocket_basket")
	if action_token == 0:
		return
	player._mark_combat_event()
	player._module_token += 1
	var token := player._module_token
	player._module_busy = true
	player._start_module_cooldown("rocket_basket", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.rocket_basket.cooldown))
	player.get_node("/root/GameSfx").play_module_event("rocket_arm", player.global_position)
	if player._attack_label != null:
		player._attack_label.text = "PANIER ROQUETTES  •  PRÉPARATION"
	player.get_tree().create_timer(float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.rocket_basket.preparation), false, true).timeout.connect(func() -> void:
		if token != player._module_token or not player._module_action_can_execute(action_token, "rocket_basket"):
			player._end_module_action(action_token, "rocket_basket")
			return
		var attack_id := "rocket_basket:%d:%d:%d" % [player.get_instance_id(), player._visibility_epoch, token]
		player._presentation_component.confirm_module_release("rocket_basket")
		player.register_offensive_attack(attack_id)
		PLAYER_STATE.ROCKET_BASKET.launch(player, player.aim_direction, "player", attack_id, player._module_cooldowns, player._rocket_damage_multiplier, func(_target: Node3D, applied: float) -> void:
			player.on_direct_offensive_hit(attack_id, applied, _target)
		, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.rocket_basket.cooldown) * float(player._survival_cooldown_multipliers.get("offensive", 1.0)))
		player._end_module_action(action_token, "rocket_basket")
	)


func _select_javelin_target(origin: Vector3, direction: Vector3, shot_range: float = -1.0) -> Node:
	var target: Node = player._module_target()
	if target == null or not is_instance_valid(target) or float(target.call("get_health")) <= 0.0:
		return null
	var offset: Vector3 = target.global_position - origin
	offset.y = 0.0
	var along := direction.dot(offset)
	var closest := origin + direction * along
	var lateral := Vector3(target.global_position.x - closest.x, 0.0, target.global_position.z - closest.z).length()
	if along <= 0.0 or along > (shot_range if shot_range > 0.0 else player._javelin_max_range) or lateral > 0.70:
		return null
	var path_excluded: Array[RID] = [target.get_rid()]
	if not player._solid_path_clear(origin, target.global_position, path_excluded):
		return null
	return target


func _perform_javelin() -> void:
	if player._begin_javelin_charge():
		player._release_javelin_charge()


func _begin_javelin_charge() -> bool:
	if player._can_buffer_defensive_action() and player._has_live_javelin_mark():
		player._buffer_javelin_recast()
		return true
	if player._stasis_remaining > 0.0 or player._fulguro_projection_active or (player.combat_state != null and player.combat_state.is_stunned()):
		return false
	if not player._has_live_javelin_mark() and player.survival_mode and player.survival_evolution_effects != null and player.survival_evolution_effects.has_javelin_anchor():
		player._recast_javelin()
		return true
	if player._has_live_javelin_mark():
		player._mark_combat_event()
		player._recast_javelin()
		return true
	player._javelin_mark_target = null
	if not player._module_ready("javelin"):
		return false
	var action_token: int = player._try_begin_module_action("javelin")
	if action_token == 0:
		return false
	player._mark_combat_event()
	player._module_busy = true
	player._module_token += 1
	player._javelin_launch_token += 1
	player._javelin_charging = true
	COMBAT_AUDIO.charge(player, "javelin_charge")
	player._javelin_elapsed = 0.0
	player._javelin_release_at = -1.0
	player._javelin_charge_action_token = action_token
	player._javelin_module_aim = Vector3.ZERO
	player._start_module_cooldown("javelin", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["javelin"]["cooldown"]))
	player._javelin_charge_visual = PLAYER_STATE.JAVELIN_VISUAL.new()
	player._javelin_charge_visual.name = "JavelinCharge"
	player.add_child(player._javelin_charge_visual)
	player._javelin_charge_visual.call("configure", true)
	player._update_javelin_charge(0.0)
	return true


func is_javelin_charging() -> bool:
	return player._javelin_charging


func get_javelin_charge_fraction() -> float:
	return clampf(player._javelin_elapsed / float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin.charge_max), 0.0, 1.0) if player._javelin_charging else 0.0


func _javelin_power(seconds: float) -> float:
	return clampf((seconds - player._javelin_preparation) / (float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin.charge_max) - player._javelin_preparation), 0.0, 1.0)


func set_javelin_touch_aim(vector: Vector2) -> void:
	if not player._javelin_charging or player._javelin_release_at >= 0.0 or vector.length_squared() < 0.04:
		return
	player._javelin_module_aim = player._camera_relative_direction(vector)
	player._set_aim_direction(player._javelin_module_aim)


func _release_javelin_charge() -> void:
	if not player._javelin_charging or player._javelin_release_at >= 0.0:
		return
	player._javelin_release_at = maxf(player._javelin_preparation, player._javelin_elapsed)
	player._javelin_release_direction = player.aim_direction.normalized()


func _update_javelin_charge(delta: float) -> void:
	if not player._javelin_charging:
		return
	if not player._module_action_can_execute(player._javelin_charge_action_token, "javelin"):
		player._cancel_javelin_charge()
		return
	player._javelin_elapsed = minf(player._javelin_elapsed + delta, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin.charge_max))
	if player._javelin_elapsed >= float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin.charge_max) - 0.000001:
		player._javelin_elapsed = float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin.charge_max)
	var power: float = player._javelin_power(player._javelin_elapsed)
	if is_instance_valid(player._javelin_charge_visual):
		var direction := player._javelin_release_direction if player._javelin_release_at >= 0.0 else player.aim_direction.normalized()
		player._javelin_charge_visual.global_position = player.global_position + Vector3.UP * 1.25 + direction * 1.05
		player._javelin_charge_visual.look_at(player._javelin_charge_visual.global_position + direction, Vector3.UP)
		player._javelin_charge_visual.call("set_power", power, lerpf(player._javelin_max_range, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin.charged_range), power))
	if player._attack_label != null:
		player._attack_label.text = "JAVELIN  •  %.2f / %.2f s  •  %s" % [player._javelin_elapsed, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin.charge_max), "PUISSANCE MAX" if player.get_javelin_charge_fraction() >= 1.0 else "CHARGE"]
	if player._javelin_release_at >= 0.0 and player._javelin_elapsed >= player._javelin_release_at:
		var action_token := player._javelin_charge_action_token
		var launch_power: float = player._javelin_power(player._javelin_release_at)
		player._javelin_charging = false
		player._clear_javelin_charge_visual()
		player._emit_javelin(player._javelin_launch_token, action_token, player.global_position, player._javelin_release_direction, launch_power)


func _clear_javelin_charge_visual() -> void:
	COMBAT_AUDIO.stop_charge(player, "javelin_charge")
	if is_instance_valid(player._javelin_charge_visual):
		player._javelin_charge_visual.queue_free()
	player._javelin_charge_visual = null
	player._javelin_module_aim = Vector3.ZERO


func _cancel_javelin_charge() -> void:
	if not player._javelin_charging:
		return
	player._javelin_charging = false
	player._presentation_component.cancel_module_gesture("javelin")
	player._javelin_launch_token += 1
	player._clear_javelin_charge_visual()
	player._end_module_action(player._javelin_charge_action_token, "javelin")
	player._javelin_charge_action_token = 0
	player._desktop_javelin_charge_held = false


func _emit_javelin(token: int, action_token: int, origin: Vector3, direction: Vector3, power: float = 0.0) -> void:
	if token != player._javelin_launch_token or not player._module_action_can_execute(action_token, "javelin"):
		return
	player._presentation_component.confirm_module_release("javelin")
	COMBAT_AUDIO.play(player, "javelin_launch")
	if player.survival_mode and player.survival_evolution_effects != null and player.survival_evolution_effects.launch_beacon(origin, direction):
		player._end_module_action(action_token, "javelin")
		return
	var definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin
	var shot_range := lerpf(player._javelin_max_range, float(definition.charged_range), power)
	var shot_speed := lerpf(player._javelin_speed, float(definition.charged_speed), power)
	var shot_damage := player._javelin_damage * lerpf(1.0, float(definition.charged_damage) / float(definition.damage), power)
	var mark_duration := lerpf(player._javelin_mark_duration, float(definition.charged_mark_duration), power)
	player._javelin_active_mark_duration = mark_duration
	player._javelin_active_recast_range = shot_range
	var target: Node = player._select_javelin_target(origin, direction, shot_range)
	var visual_start: Vector3 = player._module_visual_start(direction)
	visual_start.y = maxf(visual_start.y, player.global_position.y + 0.85)
	visual_start = player._safe_projectile_origin(visual_start)
	var flight_direction := direction
	if target != null and is_instance_valid(target):
		flight_direction = (target.global_position + Vector3.UP * 0.9 - visual_start).normalized()
	var projectile := PLAYER_STATE.LIVE_PROJECTILE.new()
	projectile.name = "JavelinProjectile"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.get_tree().current_scene.add_child(projectile)
	player._register_fx_budget(projectile, "projectile")
	projectile.global_position = visual_start
	projectile.look_at(visual_start + flight_direction, Vector3.UP)
	var excluded: Array[RID] = [player.get_rid()]
	if player.survival_mode and player.survival_evolution_effects != null:
		excluded.append_array(player.survival_evolution_effects.own_wall_exclusions())
	projectile.configure(flight_direction, shot_speed, shot_range, 1 | 2 | 8, excluded)
	player._register_projectile_motion(projectile, visual_start, visual_start + flight_direction * shot_range, shot_range / shot_speed, 0.12)
	var spear := PLAYER_STATE.JAVELIN_VISUAL.new()
	spear.name = "JavelinBody"
	projectile.add_child(spear)
	spear.call("configure", false)
	spear.call("set_power", power, shot_range)
	player._create_muzzle_burst(visual_start, flight_direction, Color("#7df4ff"), 0.90 + power * 0.65)
	player._spawn_particle_burst(visual_start, Color("#bcffff"), 12 + roundi(power * 12.0), 0.28, 4.0 + power * 4.0, 0.08, flight_direction, 26.0)
	player.register_offensive_attack("javelin:%d" % token)
	projectile.finished.connect(player._on_javelin_finished.bind(token, shot_damage, mark_duration, shot_range, power))
	player._attack_label.text = "JAVELIN  •  %d%%  •  CD 12s" % roundi(power * 100.0)

	player._end_module_action(action_token, "javelin")


func _on_javelin_finished(hit: Dictionary, _distance: float, token: int, damage: float = 140.0, mark_duration: float = 2.5, shot_range: float = 8.0, power: float = 0.0) -> void:
	if token != player._javelin_launch_token:
		return
	if hit.get("collider") is Node and hit.collider.is_in_group("prototype0_homing_rockets"):
		hit.collider.take_damage(damage, "player", "javelin:%d" % token)
		return
	if not hit.is_empty():
		var target := hit.get("collider") as Node
		if target != null and target.has_method("take_damage") and target.has_method("apply_javelin_mark"):
			var shield_before := PLAYER_STATE.PASSIVE_STATE.shield_health(target)
			var applied := float(target.call("take_damage", damage, "player", "javelin:%d" % token))
			var accepted := PLAYER_STATE.PASSIVE_STATE.accepted_damage(target, applied, shield_before)
			player.on_direct_offensive_hit("javelin:%d" % token, accepted, target)
			if accepted > 0.0:
				if player.survival_mode and player.survival_evolution_effects != null:
					player.survival_evolution_effects.javelin_hit(target, target.global_position)
				if player._survival_evolved("offensive"):
					player._survival_area_damage(target.global_position, 3.0, damage * 0.45, "javelin_splash", Color("#7df4ff"), target)
				COMBAT_AUDIO.play(player, "javelin_impact", target.global_position)
				target.call("apply_javelin_mark", mark_duration, "javelin")
				player._javelin_active_mark_duration = mark_duration
				player._javelin_active_recast_range = shot_range
				player._javelin_mark_target = target
				player._create_target_hit_fx(target.global_position, true)
				target.call("flash_impact", true)
				player._create_hit_flash(hit["position"], Color("#bdffff"), 0.75 + power * 0.5)
				player._spawn_particle_burst(hit["position"], Color("#70eaff"), 16 + roundi(power * 16.0), 0.32, 5.0 + power * 3.0, 0.09, Vector3.UP, 100.0)
				for side in [-1.0, 1.0]:
					player._create_lightning_arc(hit["position"], hit["position"] + Vector3(side * (0.5 + power), 0.5, 0.3), Color("#8ff7ff"), 0.04, 0.22)
		else:
			player._contact_fx(hit, Color("#70eaff"))


func _recast_javelin(preferred_destination: Vector3 = Vector3.INF) -> void:
	# Survival aspects retain their own recall behavior. An ordinary Javelin
	# still uses the newly pulled teleport in front of its marked target.
	if player.survival_mode and player.survival_evolution_effects != null and player.survival_evolution_effects.has_javelin_anchor() and player.survival_evolution_effects.path("offensive") in ["harpoon", "beacon"]:
		player.survival_evolution_effects.recall_javelin()
		return
	if not player._has_live_javelin_mark() and player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.recall_javelin()
		return
	var target := player._javelin_mark_target
	if target == null or not is_instance_valid(target) or not bool(target.call("has_javelin_mark")):
		player._javelin_mark_target = null
		return
	var path_excluded: Array[RID] = [target.get_rid()]
	if float(target.call("get_health")) <= 0.0 or player.global_position.distance_to(target.global_position) > player._javelin_active_recast_range or not player._solid_path_clear(player.global_position, target.global_position, path_excluded):
		player._attack_label.text = "JAVELIN  •  REACTIVATION REFUSÉE"
		return
	var destination = preferred_destination if preferred_destination.is_finite() else player._find_javelin_destination(target)
	if preferred_destination.is_finite() and not player._javelin_destination_valid(target, preferred_destination):
		destination = Vector3.INF
	if destination == Vector3.INF:
		player._attack_label.text = "JAVELIN  •  DESTINATION BLOQUÉE"
		return
	var action_token: int = player._try_begin_module_action("javelin_recast")
	if action_token == 0:
		return
	player._mark_combat_event()
	var teleport_origin := player.global_position
	player._cancel_pelto_pull()
	player.global_position = destination
	player.velocity = Vector3.ZERO
	player._set_aim_direction((target.global_position - destination).normalized())
	player._begin_weapon_aim()
	# A successful approach briefly holds the marked foe for a manual follow-up.
	var target_protected := bool(target.get_meta("duel_static_shield", false)) or (target.has_method("get_stasis_remaining") and float(target.call("get_stasis_remaining")) > 0.0)
	if player.passive_authoritative() and not target_protected and target.has_method("apply_slow"):
		var definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.javelin
		target.call("apply_slow", float(definition.recast_slow_duration), float(definition.recast_slow_percent), "javelin_recast:%d" % player.get_instance_id())
	if player.survival_synergies != null:
		player.survival_synergies.teleport_trail(teleport_origin, destination)
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.call("_clear_javelin")
	target.call("clear_javelin_mark")
	player._javelin_mark_target = null
	player._create_teleport_fx(destination)
	player.get_node("/root/GameSfx").play_event("javelin_teleport")
	player._attack_label.text = "JAVELIN  •  TÉLÉPORTÉ"
	player._end_module_action(action_token, "javelin_recast")


func _find_javelin_destination(target: Node) -> Vector3:
	var front: Vector3 = target.call("get_javelin_front_direction") if target.has_method("get_javelin_front_direction") else -target.global_transform.basis.z
	front.y = 0.0
	front = front.normalized() if front.length_squared() > 0.001 else Vector3.FORWARD
	var base: Vector3 = target.global_position + front * player._javelin_teleport_distance
	var candidates: Array[Vector3] = [base, target.global_position + front.rotated(Vector3.UP, deg_to_rad(30.0)) * player._javelin_teleport_distance, target.global_position + front.rotated(Vector3.UP, deg_to_rad(-30.0)) * player._javelin_teleport_distance]
	for candidate in candidates:
		candidate.y = 0.0
		if player._javelin_destination_valid(target, candidate):
			return candidate
	return Vector3.INF


func get_javelin_front_direction() -> Vector3:
	return player._normalized_aim_direction()


func _javelin_destination_valid(target: Node, candidate: Vector3) -> bool:
	if target == null or not is_instance_valid(target) or not target is CollisionObject3D or not candidate.is_finite():
		return false
	if absf(candidate.x - player.gameplay_arena_center.x) > 23.0 or absf(candidate.z - player.gameplay_arena_center.z) > 23.0:
		return false
	if not player._solid_path_clear(player.global_position, candidate):
		return false
	var world := player.get_world_3d()
	if world == null:
		return true
	var query := PhysicsPointQueryParameters3D.new()
	query.position = candidate + Vector3.UP * 0.72
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.exclude = [player.get_rid(), (target as CollisionObject3D).get_rid()]
	return world.direct_space_state.intersect_point(query, 8).is_empty()
