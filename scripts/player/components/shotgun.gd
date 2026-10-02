extends Node

# Shotgun salvo, damage falloff, ammunition and reload.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "ShotgunComponent"


func get_shotgun_ammo() -> int:
	return player._shotgun_ammo


func get_shotgun_magazine_size() -> int:
	return player._shotgun_magazine_size


func get_shotgun_reload_progress() -> float:
	if not player._shotgun_reloading:
		return 0.0
	return 1.0 - player._shotgun_reload_remaining / maxf(0.001, player._shotgun_reload_duration)


func is_shotgun_reloading() -> bool:
	return player._shotgun_reloading


func reset_shotgun_state() -> void:
	player._shotgun_attack_token += 1
	player._shotgun_reload_token += 1
	player._shotgun_attack_busy = false
	player._shotgun_attack_emitted = false
	player._action_gate.release(player._shotgun_action_token)
	player._shotgun_action_token = 0
	player._shotgun_reloading = false
	player._shotgun_reload_remaining = 0.0
	player._shotgun_ammo = player._shotgun_magazine_size
	player._kill_weapon_recoil_tweens(player._shotgun_recoil_tweens)
	if player._shotgun_pivot != null:
		player._shotgun_pivot.transform = player._shotgun_pivot_home_transform
	if player._shotgun_recoil_pivot != null:
		player._shotgun_recoil_pivot.transform = Transform3D.IDENTITY
	if player._shotgun_light != null:
		player._shotgun_light.light_energy = 0.0
	if player._shotgun_shot_audio != null:
		player._shotgun_shot_audio.stop()
	if player._shotgun_cycle_audio != null:
		player._shotgun_cycle_audio.stop()
	if player._shotgun_reload_audio != null:
		player._shotgun_reload_audio.stop()
		player._shotgun_reload_audio.stream_paused = false


func _update_shotgun_reload_input() -> void:
	if player._weapon_id == "shotgun" and player._pressed_action_once("reload"):
		player._start_shotgun_reload()


func _update_shotgun_attack(wants_to_attack: bool) -> void:
	if player._shotgun_reloading or player._shotgun_attack_busy:
		return
	if player._shotgun_ammo <= 0:
		player._start_shotgun_reload()
		return
	if wants_to_attack:
		player._perform_shotgun_attack()


func _perform_shotgun_attack() -> void:
	if player._shotgun_reloading or player._shotgun_attack_busy:
		return
	if player._shotgun_ammo <= 0:
		player._start_shotgun_reload()
		return
	var action_token: int = player._try_begin_weapon_action("shotgun")
	if action_token == 0:
		return
	player._shotgun_action_token = action_token
	player._shotgun_attack_emitted = false
	player._mark_combat_event()
	player._begin_weapon_aim()
	player._shotgun_attack_token += 1
	var token := player._shotgun_attack_token
	player._shotgun_attack_busy = true
	if not player.training_unlimited_ammo:
		player._shotgun_ammo -= 1
	player._shotgun_attack_origin = player.global_position
	player._shotgun_attack_direction = player.aim_direction.normalized()
	var attack_speed: float = player.get_attack_speed_multiplier()
	# Preparation keeps the live aim pose; kick/flash start with pellet emission.
	player._attack_label.text = "SHOTGUN  •  %d/%d CARTOUCHES" % [player._shotgun_ammo, player._shotgun_magazine_size]
	var salvo := {
		"id": token,
		"action_token": action_token,
		"hits_by_target": {},
		"credited": {},
	}
	var emission_timer := player.get_tree().create_timer(player._shotgun_preparation / attack_speed, false, false, false)
	emission_timer.timeout.connect(func() -> void: player._emit_shotgun_salvo(token, salvo))
	var finish_timer := player.get_tree().create_timer((player._shotgun_preparation + (0.01 if player.training_instant_cooldowns else player._shotgun_recovery)) / attack_speed, false, false, false)
	finish_timer.timeout.connect(func() -> void: player._finish_shotgun_attack(token))


func _play_shotgun_animation(speed_scale: float) -> void:
	player._kill_weapon_recoil_tweens(player._shotgun_recoil_tweens)
	if player._shotgun_recoil_pivot != null:
		player._shotgun_recoil_pivot.transform = Transform3D.IDENTITY
	if player._has_skeletal_weapon_attachment():
		player._update_aim_pose_state()
		# The same shoulder/arm impulse as a charged blaster, with both hands attached.
		player._visual_rig.play_shot_kick(1.0)
	elif player._shotgun_recoil_pivot != null:
		var duration_scale := maxf(0.5, speed_scale)
		var kick := player.create_tween().set_parallel(true)
		kick.tween_property(player._shotgun_recoil_pivot, "position", Vector3(0.0, 0.0, 0.07), 0.05 / duration_scale)
		kick.tween_property(player._shotgun_recoil_pivot, "rotation", Vector3(deg_to_rad(2.0), 0.0, 0.0), 0.05 / duration_scale)
		kick.chain().tween_property(player._shotgun_recoil_pivot, "position", Vector3.ZERO, 0.12 / duration_scale)
		kick.parallel().tween_property(player._shotgun_recoil_pivot, "rotation", Vector3.ZERO, 0.12 / duration_scale)
		player._shotgun_recoil_tweens.append(kick)
	if player._shotgun_light != null:
		player._shotgun_light.light_energy = 0.0
	player._camera_impulse(0.105, 0.085)


func _emit_shotgun_salvo(token: int, salvo: Dictionary) -> void:
	var echo := bool(salvo.get("echo", false))
	var action_token := int(salvo.get("action_token", 0))
	if not player._gameplay_enabled or (not echo and (token != player._shotgun_attack_token or not player._shotgun_attack_busy)):
		return
	if not player._action_gate.owns(action_token, PLAYER_STATE.ACTION_GATE.Kind.WEAPON, "shotgun"):
		return
	if echo and (player.survival_synergies == null or int(salvo.get("generation", -1)) != player.survival_synergies.generation):
		return
	if player.combat_state != null and player.combat_state.is_stunned():
		player._cancel_shotgun_attack()
		return
	# Commit every input scheme from the same live source of truth at emission.
	player._shotgun_attack_origin = player.global_position
	player._shotgun_attack_direction = player._normalized_aim_direction()
	player._shotgun_attack_emitted = true
	player._last_projectile_direction = player._shotgun_attack_direction
	player._begin_weapon_fire()
	if player._has_skeletal_weapon_attachment():
		# The preparation timer runs after physics. Read the next final skeletal
		# pose, not the lowered attachment left by the preceding tick.
		await player._visual_rig.skeleton.skeleton_updated
		if not player._gameplay_enabled or not player._action_gate.owns(action_token, PLAYER_STATE.ACTION_GATE.Kind.WEAPON, "shotgun") or (not echo and token != player._shotgun_attack_token):
			return
		player._shotgun_attack_direction = player._visual_rig.get_aim_forward_direction()
		player._last_projectile_direction = player._shotgun_attack_direction
	salvo["passive_attack"] = {} if echo else player.emit_passive_weapon()
	player._shotgun_shot_audio.play()
	var cycle_timer = player.get_tree().create_timer(0.26 / player.get_attack_speed_multiplier(), true, false, false)
	cycle_timer.timeout.connect(func() -> void: player._play_shotgun_cycle_audio(token))
	var visual_start := player._shotgun_muzzle.global_position if player._shotgun_muzzle != null else player._shotgun_attack_origin + Vector3.UP * 0.85 + player._shotgun_attack_direction * 0.45
	visual_start = player._safe_projectile_origin(visual_start)
	player._create_muzzle_burst(visual_start, player._shotgun_attack_direction, Color("#ff9d4e"), 1.35, player._shotgun_muzzle)
	# Spread is symmetric around the evaluated barrel/aim axis, at every range.
	var center_direction := player._shotgun_attack_direction
	for index in range(player._shotgun_pellet_angles.size()):
		var angle := deg_to_rad(float(player._shotgun_pellet_angles[index]))
		var direction := center_direction.rotated(Vector3.UP, angle).normalized()
		var endpoint := visual_start + direction * player._shotgun_max_range
		if player._show_debug_hitbox:
			player._create_lightning_arc(visual_start, endpoint, Color("#ffc56e"), 0.025, 0.45)
		player._spawn_shotgun_projectile(visual_start, endpoint, salvo, index)
	if not echo and player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.shotgun_salvo(visual_start, player._shotgun_attack_direction)
	player._play_shotgun_animation(player.get_attack_speed_multiplier())
	if not echo and player.survival_synergies != null and player.survival_synergies.consume_double():
		var second := {"id": token, "action_token": action_token, "hits_by_target": {}, "credited": {}, "echo": true, "generation": player.survival_synergies.generation, "source": "double", "damage_scale": 0.65 if bool(player.survival_synergies.evolved.get("mobility", false)) else 0.45}
		player.get_tree().create_timer(0.16, false).timeout.connect(func() -> void: player._emit_shotgun_salvo(token, second))


func _play_shotgun_cycle_audio(token: int) -> void:
	if token == player._shotgun_attack_token and player._weapon_id == "shotgun":
		player._shotgun_cycle_audio.play()


func _spawn_shotgun_projectile(start: Vector3, endpoint: Vector3, salvo: Dictionary, index: int) -> void:
	var projectile := PLAYER_STATE.LIVE_PROJECTILE.new()
	projectile.name = "ShotgunPellet"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.get_tree().current_scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = start
	var direction := endpoint - start
	direction = direction.normalized() if direction.length_squared() > 0.001 else player._shotgun_attack_direction
	projectile.look_at(start + direction, Vector3.UP)
	var excluded: Array[RID] = [player.get_rid()]
	if player.survival_mode and player.survival_evolution_effects != null:
		excluded.append_array(player.survival_evolution_effects.own_wall_exclusions())
	projectile.configure(direction, player._shotgun_pellet_speed, player._shotgun_max_range, 1 | 2 | 8, excluded)
	player._register_projectile_motion(projectile, start, start + direction * player._shotgun_max_range, player._shotgun_max_range / player._shotgun_pellet_speed, 0.12)
	projectile.finished.connect(player._on_shotgun_pellet_finished.bind(salvo, index))
	var vfx: Node = player._vfx_manager()
	if vfx != null:
		vfx.call("projectile_visual", projectile, "shotgun", 0.0)


func _on_shotgun_pellet_finished(hit: Dictionary, distance: float, salvo: Dictionary, index: int) -> void:
	salvo["impact_point"] = hit.get("position", Vector3.INF)
	var collider: Node = hit.get("collider")
	if not hit.is_empty() and (collider == null or not collider.has_method("take_damage")):
		PLAYER_STATE.COUNTER.invalidate(salvo.get("passive_attack", {}).get("counter_attack", {}))
	if hit.is_empty():
		return
	var target := hit.get("collider") as Node
	if target != null and target.has_method("take_damage") and target.has_method("get_health"):
		player._resolve_shotgun_projectile(salvo, index, true, target, distance)
	# Three readable impact clusters communicate the six-pellet spread.
	if index % 2 == 0:
		player._contact_fx(hit, Color("#e39a54"), 1.05, "shotgun")


func _resolve_shotgun_projectile(salvo: Dictionary, index: int, did_hit: bool, target: Node, distance: float) -> void:
	if not did_hit or target == null or not is_instance_valid(target):
		return
	var projectile_id := "%s:%d:%d" % [str(salvo.get("source", "shotgun")), int(salvo["id"]), index]
	var credited: Dictionary = salvo["credited"]
	if credited.has(projectile_id):
		return
	credited[projectile_id] = true
	var damage: float = player._shotgun_damage_at_distance(distance) * float(salvo.get("damage_scale", 1.0))
	var effective_damage: float = player.passive_weapon_damage(target, damage, "player", projectile_id, salvo.get("passive_attack", {}), salvo.get("impact_point", target.global_position + Vector3.UP * 0.85))
	if effective_damage <= 0.0:
		return
	if player.survival_mode and player.survival_evolution_effects != null:
		player.survival_evolution_effects.shotgun_hit(target, salvo)
	var hits_by_target: Dictionary = salvo["hits_by_target"]
	var target_id := target.get_instance_id()
	var tally: Dictionary = hits_by_target.get(target_id, {"valid_hits": 0, "base_damage_sum": 0.0, "critical_applied": false})
	tally["valid_hits"] = int(tally["valid_hits"]) + 1
	tally["base_damage_sum"] = float(tally["base_damage_sum"]) + damage * float(salvo.get("passive_attack", {}).get("multiplier", 1.0))
	hits_by_target[target_id] = tally
	player._create_target_hit_fx(target.global_position, false)
	target.call("flash_impact", false)
	if int(tally["valid_hits"]) == player._shotgun_pellet_angles.size() and not bool(tally["critical_applied"]):
		tally["critical_applied"] = true
		var bonus := float(tally["base_damage_sum"]) * (PLAYER_STATE.CRIT_MULTIPLIER - 1.0)
		var bonus_id := "%s:%d:critical:%d" % [str(salvo.get("source", "shotgun")), int(salvo["id"]), target_id]
		target.call("take_damage", bonus, "player", bonus_id)
		target.call("apply_burn", PLAYER_STATE.COMBAT_DATA.BURN_DURATION, PLAYER_STATE.COMBAT_DATA.BURN_DAMAGE_PER_SECOND * float(salvo.get("damage_scale", 1.0)), "player:" + str(salvo.get("source", "shotgun")))
		target.call("flash_impact", true)


func _shotgun_damage_at_distance(distance: float) -> float:
	if distance <= player._shotgun_falloff_start:
		return player._shotgun_pellet_damage
	var ratio := clampf((distance - player._shotgun_falloff_start) / maxf(0.001, player._shotgun_max_range - player._shotgun_falloff_start), 0.0, 1.0)
	return lerpf(player._shotgun_pellet_damage, player._shotgun_minimum_damage, ratio)


func _finish_shotgun_attack(token: int) -> void:
	if token != player._shotgun_attack_token or not player._shotgun_attack_busy:
		return
	player._shotgun_attack_busy = false
	player._shotgun_attack_emitted = false
	player._action_gate.release(player._shotgun_action_token)
	player._shotgun_action_token = 0
	player._begin_aim_hold()
	if player._shotgun_ammo <= 0:
		player._start_shotgun_reload()


func _cancel_shotgun_attack() -> void:
	if not player._shotgun_attack_busy:
		player._action_gate.release(player._shotgun_action_token)
		player._shotgun_action_token = 0
		return
	player._shotgun_attack_token += 1
	if not player._shotgun_attack_emitted and not player.training_unlimited_ammo:
		player._shotgun_ammo = mini(player._shotgun_magazine_size, player._shotgun_ammo + 1)
	player._shotgun_attack_busy = false
	player._shotgun_attack_emitted = false
	player._action_gate.release(player._shotgun_action_token)
	player._shotgun_action_token = 0
	player._shotgun_cycle_audio.stop()
	player._attack_label.text = ""


func _start_shotgun_reload() -> void:
	if player._shotgun_reloading or player._shotgun_ammo >= player._shotgun_magazine_size:
		return
	player._shotgun_reloading = true
	player._shotgun_reload_token += 1
	player._shotgun_reload_remaining = player._shotgun_reload_duration
	player._shotgun_reload_audio.stream_paused = false
	player._shotgun_reload_audio.play()
	player._attack_label.text = ""


func _update_shotgun_reload(delta: float) -> void:
	if not player._shotgun_reloading:
		return
	player._shotgun_reload_audio.stream_paused = player._stasis_remaining > 0.0 or player.is_eclipse_travelling()
	if player._stasis_remaining > 0.0 or player.is_eclipse_travelling():
		return
	player._shotgun_reload_remaining = maxf(0.0, player._shotgun_reload_remaining - delta * (player.get_attack_speed_multiplier() if player.survival_mode else 1.0))
	if player._shotgun_reload_remaining > 0.0:
		return
	player._shotgun_ammo = player._shotgun_magazine_size
	player._shotgun_reloading = false
	player._attack_label.text = ""


func _update_shotgun_reload_visual() -> void:
	if player._shotgun_pivot == null:
		return
	player._shotgun_pivot.transform = player._shotgun_pivot_home_transform
	# The skeletal root is hand-local. The old body-space lift detaches the
	# grip during reload and leaves the next muzzle more than a metre away.
	if not player._shotgun_reloading or player._weapon_id != "shotgun" or player._has_skeletal_weapon_attachment():
		return
	var phase: float = player.get_shotgun_reload_progress()
	var lift := sin(phase * PI)
	var reload_transform := player._shotgun_pivot_home_transform
	reload_transform.origin += Vector3(0.0, 0.14 * lift, 0.12 * lift)
	reload_transform.basis *= Basis.from_euler(Vector3(-0.22 * lift, 0.0, 0.12 * lift))
	player._shotgun_pivot.transform = reload_transform
