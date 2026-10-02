extends Node

# Blaster charge, shot, projectile completion and recoil.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "BlasterComponent"


func reset_blaster_state() -> void:
	player._blaster_attack_token += 1
	player._blaster_attack_busy = false
	player._blaster_next_attack_ready_at = -10.0
	player._attack_hold_last = false
	player._desktop_blaster_tap_buffered = false
	player.cancel_touch_fire()
	player._action_gate.release(player._blaster_action_token)
	player._blaster_action_token = 0


func _begin_blaster_charge(now: float = -1.0) -> void:
	if player._weapon_id != "blaster" or player._blaster_charge_active or player._blaster_attack_busy:
		return
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	if now < player._blaster_next_attack_ready_at:
		return
	var action_token: int = player._try_begin_weapon_action("blaster")
	if action_token == 0:
		return
	player._blaster_action_token = action_token
	player._blaster_charge_active = true
	player._begin_weapon_aim()
	player._blaster_charge_started_at = now
	player._blaster_charge_ratio = 0.0
	player._blaster_ready_cued = false
	if player._blaster_charge_audio_fade != null and player._blaster_charge_audio_fade.is_running():
		player._blaster_charge_audio_fade.kill()
	player._blaster_charge_audio.stop()
	player._blaster_charge_hold_audio.stop()
	player._blaster_ready_audio.stop()
	player._blaster_charge_audio.volume_db = -9.0
	player._blaster_charge_hold_audio.volume_db = -10.0
	player._blaster_charge_audio.play()
	player._mark_combat_event()
	if player._attack_label != null:
		player._attack_label.text = ""
	player._update_blaster_charge_visual(0.0)


func _play_blaster_ready_sound() -> void:
	if player._blaster_ready_cued or not player._blaster_charge_active:
		return
	player._blaster_ready_cued = true
	player._blaster_charge_audio.stop()
	player._blaster_charge_hold_audio.play()
	player._blaster_ready_audio.play()


func _stop_blaster_charge_audio() -> void:
	if player._blaster_charge_audio == null:
		return
	player._blaster_ready_audio.stop()
	if player._blaster_charge_audio_fade != null and player._blaster_charge_audio_fade.is_running():
		player._blaster_charge_audio_fade.kill()
	if not player._blaster_charge_audio.playing and not player._blaster_charge_hold_audio.playing:
		return
	player._blaster_charge_audio_fade = player.create_tween().set_parallel(true)
	if player._blaster_charge_audio.playing:
		player._blaster_charge_audio_fade.tween_property(player._blaster_charge_audio, "volume_db", -60.0, 0.02)
	if player._blaster_charge_hold_audio.playing:
		player._blaster_charge_audio_fade.tween_property(player._blaster_charge_hold_audio, "volume_db", -60.0, 0.02)
	player._blaster_charge_audio_fade.chain().tween_callback(player._finish_blaster_charge_audio_stop)


func _finish_blaster_charge_audio_stop() -> void:
	player._blaster_charge_audio.stop()
	player._blaster_charge_hold_audio.stop()
	player._blaster_charge_audio.volume_db = -9.0
	player._blaster_charge_hold_audio.volume_db = -10.0


func _cancel_blaster_charge(reason: String = "", release_action: bool = true) -> void:
	player._stop_blaster_charge_audio()
	player._blaster_charge_active = false
	player._blaster_charge_started_at = -1.0
	player._blaster_charge_ratio = 0.0
	player._blaster_ready_cued = false
	if player._blaster_charge_visual != null:
		player._blaster_charge_visual.call("set_charge", false, 0.0, 0.0)
	if player._blaster_light != null:
		player._blaster_light.light_energy = 0.0
	if release_action:
		player._action_gate.release(player._blaster_action_token)
		player._blaster_action_token = 0
	if reason != "" and player._attack_label != null:
		player._attack_label.text = reason


func _cancel_blaster_attack() -> void:
	if player._blaster_attack_busy:
		player._blaster_attack_token += 1
		player._blaster_attack_busy = false
	player._action_gate.release(player._blaster_action_token)
	player._blaster_action_token = 0


func _release_blaster_charge() -> void:
	if not player._blaster_charge_active:
		return
	var ratio := clampf(player._blaster_charge_ratio, 0.0, 1.0)
	var damage := lerpf(player._blaster_damage, player._blaster_max_damage, ratio)
	var direction := player.aim_direction.normalized()
	var action_token := player._blaster_action_token
	player._cancel_blaster_charge("", false)
	player._fire_blaster_projectile(damage, ratio, direction, action_token)


func _fire_blaster_projectile(damage: float, charge_ratio: float, direction: Vector3, reserved_action_token: int = 0) -> void:
	if player._weapon_id != "blaster" or player._blaster_attack_busy:
		if reserved_action_token != 0:
			player._action_gate.release(reserved_action_token)
			if player._blaster_action_token == reserved_action_token:
				player._blaster_action_token = 0
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < player._blaster_next_attack_ready_at:
		if reserved_action_token != 0:
			player._action_gate.release(reserved_action_token)
			if player._blaster_action_token == reserved_action_token:
				player._blaster_action_token = 0
		return
	var action_token := reserved_action_token
	if action_token == 0:
		action_token = player._try_begin_weapon_action("blaster")
	if not player._action_gate.owns(action_token, PLAYER_STATE.ACTION_GATE.Kind.WEAPON, "blaster"):
		return
	player._blaster_action_token = action_token
	player._mark_combat_event()
	var shot_audio := player._blaster_charged_shot_audio if charge_ratio >= 0.85 else player._blaster_shot_audio
	shot_audio.pitch_scale = lerpf(1.05, 0.94, charge_ratio)
	shot_audio.play()
	player._set_aim_direction(direction)
	var shot_direction: Vector3 = player._normalized_aim_direction()
	player._last_projectile_direction = shot_direction
	var wait_for_firing_pose := player._visual_rig != null and not player._visual_rig.is_aim_pose_committed()
	player._begin_weapon_fire()
	player._blaster_attack_token += 1
	var token := player._blaster_attack_token
	player._blaster_attack_busy = true
	player._blaster_next_attack_ready_at = now + (0.01 if player.training_instant_cooldowns else player._blaster_cooldown)
	player._play_blaster_recoil(charge_ratio)
	player._camera_impulse(0.045 + charge_ratio * 0.035, 0.018 + charge_ratio * 0.034)
	if wait_for_firing_pose and player._visual_rig != null and player._visual_rig.skeleton != null:
		# Bone attachments update with the final skeleton pass. Delay only a tap that
		# began below full aim; charged/held fire emits immediately from the muzzle.
		await player._visual_rig.skeleton.skeleton_updated
		if token != player._blaster_attack_token or player._weapon_id != "blaster" or not player._action_gate.owns(action_token, PLAYER_STATE.ACTION_GATE.Kind.WEAPON, "blaster"):
			return
	var origin := player._blaster_muzzle.global_position if player._blaster_muzzle != null else player.global_position + Vector3.UP * 0.90 + shot_direction * 0.62
	origin = player._safe_projectile_origin(origin)
	player._create_muzzle_burst(origin, shot_direction, Color("#64e9ff"), 1.0 + charge_ratio * 0.65, player._blaster_muzzle)
	player._spawn_blaster_projectile(origin, damage, charge_ratio, token, shot_direction, player.emit_passive_weapon())
	player._action_gate.release(action_token)
	if player._blaster_action_token == action_token:
		player._blaster_action_token = 0
	# The fire lock is governed solely by the weapon cooldown. Projectile travel
	# may continue visually beyond that window without blocking the next shot.
	player._blaster_attack_busy = false
	if player._attack_label != null:
		player._attack_label.text = "BLASTER  •  TIR %d DÉGÂTS" % roundi(damage)
	if player._blaster_light != null:
		player._blaster_light.light_energy = 0.0


func _play_blaster_recoil(charge_ratio: float) -> void:
	player._kill_weapon_recoil_tweens(player._blaster_recoil_tweens)
	if player._blaster_sway_pivot != null:
		player._blaster_sway_pivot.transform = Transform3D.IDENTITY
	if player._blaster_recoil_pivot != null:
		player._blaster_recoil_pivot.transform = Transform3D.IDENTITY
	if player._has_skeletal_weapon_attachment():
		player._update_aim_pose_state()
		player._visual_rig.play_shot_kick(charge_ratio)
		return
	# The procedural fallback has no bones to absorb the impulse.
	if player._blaster_recoil_pivot == null:
		return
	player._blaster_recoil_pivot.transform = Transform3D.IDENTITY
	var recoil_distance := 0.07 + charge_ratio * 0.10
	var position_tween := player.create_tween()
	position_tween.tween_property(player._blaster_recoil_pivot, "position", Vector3(0.0, 0.0, recoil_distance), 0.045).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	position_tween.tween_property(player._blaster_recoil_pivot, "position", Vector3(0.0, 0.0, -0.025), 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	position_tween.tween_property(player._blaster_recoil_pivot, "position", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	player._blaster_recoil_tweens.append(position_tween)
	var rotation_tween := player.create_tween()
	rotation_tween.tween_property(player._blaster_recoil_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(-2.4 - charge_ratio * 2.0)), 0.045).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(player._blaster_recoil_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(0.7)), 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(player._blaster_recoil_pivot, "rotation", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	player._blaster_recoil_tweens.append(rotation_tween)


func _spawn_blaster_projectile(start: Vector3, damage: float, charge_ratio: float, token: int, shot_direction: Vector3, passive_attack: Dictionary = {}) -> void:
	shot_direction = ARENA_TRAVERSAL.shot_direction(player, start, shot_direction)
	var projectile := PLAYER_STATE.LIVE_PROJECTILE.new()
	projectile.name = "BlasterProjectile"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.get_tree().current_scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = start
	projectile.look_at(start + shot_direction, Vector3.UP)
	var excluded: Array[RID] = [player.get_rid()]
	if player.survival_mode and player.survival_evolution_effects != null:
		excluded.append_array(player.survival_evolution_effects.own_wall_exclusions())
	var definition: Dictionary = PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS.blaster
	var power := clampf(charge_ratio, 0.0, 1.0)
	var shot_speed := player._blaster_projectile_speed * lerpf(1.0, float(definition.charged_speed_multiplier), power)
	var shot_radius := player._blaster_projectile_radius * lerpf(1.0, float(definition.charged_size_multiplier), power)
	projectile.configure(shot_direction, shot_speed, player._blaster_max_range, 1 | 2 | 8, excluded)
	player._register_projectile_motion(projectile, start, start + shot_direction * player._blaster_max_range, player._blaster_max_range / shot_speed, shot_radius)
	projectile.finished.connect(player._on_blaster_projectile_finished.bind(damage, charge_ratio, token, shot_direction, passive_attack))
	var vfx: Node = player._vfx_manager()
	if vfx != null:
		var shot_color := Color("#52dff4").lerp(Color("#718cff"), charge_ratio * charge_ratio * 0.78)
		vfx.call("projectile_visual", projectile, "blaster", charge_ratio)
		var tracer_end = player._blaster_obstacle_endpoint(start, start + shot_direction * (1.15 + charge_ratio * 0.55))
		vfx.call("tracer", start, tracer_end, 0.036 + charge_ratio * 0.034, shot_color, 0.058 + charge_ratio * 0.014)


func _on_blaster_projectile_finished(hit: Dictionary, _distance: float, damage: float, charge_ratio: float, token: int, shot_direction: Vector3, passive_attack: Dictionary = {}) -> void:
	if hit.is_empty():
		return
	var target := hit.get("collider") as Node
	if target != null and target.has_method("take_damage") and target.has_method("get_health"):
		var applied: float = player.passive_weapon_damage(target, damage, "player", "blaster:%d" % token, passive_attack, hit.position)
		if applied > 0.0:
			if player.survival_synergies != null:
				player.survival_synergies.blaster_hit(target, charge_ratio)
			if player.survival_mode and player.survival_evolution_effects != null:
				player.survival_evolution_effects.blaster_hit(target, damage, charge_ratio, shot_direction)
			if player._survival_evolved("weapon"):
				player._survival_secondary_hit(target, damage * 0.6, 9.0, "blaster_pierce", true, shot_direction)
			target.call("flash_impact", charge_ratio >= 0.99)
	var impact_color := Color("#52dff4").lerp(Color("#718cff"), charge_ratio * charge_ratio * 0.78)
	player._contact_fx(hit, impact_color, 0.8 + charge_ratio * 0.95)


func _blaster_obstacle_endpoint(start: Vector3, end: Vector3) -> Vector3:
	var world := player.get_world_3d()
	if world == null:
		return end
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = 9
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()])
	var result := world.direct_space_state.intersect_ray(query)
	return result["position"] if not result.is_empty() else end


func _blaster_path_clear(target: Node, from_position: Vector3, to_position: Vector3) -> bool:
	var path_excluded: Array[RID] = [target.get_rid()]
	return player._module_path_clear(from_position, to_position, path_excluded) if target != null and is_instance_valid(target) else true


func _update_blaster_charge_visual(delta: float) -> void:
	if player._blaster_charge_visual == null:
		return
	var ratio := clampf(player._blaster_charge_ratio, 0.0, 1.0)
	player._blaster_charge_visual.call("set_charge", player._blaster_charge_active, ratio, delta)
	if not player._blaster_charge_active:
		if player._blaster_light != null:
			player._blaster_light.light_energy = 0.0
		return
	var charge_curve := ratio * ratio
	if player._blaster_light != null:
		player._blaster_light.light_color = Color("#48dfff").lerp(Color("#b5dfff"), charge_curve)
		player._blaster_light.light_energy = charge_curve * 0.85
	if player._attack_label != null:
		player._attack_label.text = "BLASTER  •  CHARGE %d%%" % roundi(ratio * 100.0)


func get_blaster_charge_ratio() -> float:
	return player._blaster_charge_ratio if player._blaster_charge_active else 0.0


func is_blaster_charging() -> bool:
	return player._blaster_charge_active
