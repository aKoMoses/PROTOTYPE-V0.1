extends Node

# Mekatana combo, dash ownership, damage hooks and cancellation.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "MekatanaComponent"


func get_mekatana_state() -> Dictionary:
	return {"phase": player._mekatana_attack.phase, "step": player._mekatana_attack.step,
		"next_step": player._mekatana_attack.next_step, "combo_remaining": player._mekatana_attack.combo_remaining,
		"progress": player._mekatana_attack.progress()}


func _can_apply_mekatana_damage() -> bool:
	return true


func _perform_mekatana_attack() -> void:
	if player._weapon_id != "mekatana" or player._mekatana_attack.is_busy() or player._action_incapacitated() or player._dash_active or player._pelto_pull_active:
		return
	var token: int = player._try_begin_weapon_action("mekatana")
	if token == 0:
		return
	player._mekatana_action_token = token
	player._mekatana_attack.damage_enabled = player._can_apply_mekatana_damage()
	var facing := player.aim_direction
	if not facing.is_finite() or Vector2(facing.x, facing.z).length_squared() < 0.001:
		facing = -player._visual_rig.global_basis.z if player._visual_rig != null else -player.global_basis.z
	if not player._mekatana_attack.start(facing, 1.0, player.get_attack_speed_multiplier()):
		player._action_gate.release(token)
		player._mekatana_action_token = 0
		return
	player.aim_direction = player._mekatana_attack.direction
	player.velocity = Vector3.ZERO
	player._round_warmup_active = false
	player._play_player_animation(&"idle")
	player._mark_combat_event()
	player._sync_mekatana_pose()
	if player._attack_label != null:
		player._attack_label.text = "MEKATANA  •  COUP %d/3" % (player._mekatana_attack.step + 1)


func _update_mekatana_attack(delta: float) -> bool:
	player._mekatana_velocity = Vector3.ZERO
	player._mekatana_movement_owned = false
	if player._mekatana_attack.is_busy() and (player._weapon_id != "mekatana" or player._action_incapacitated() or not player._action_gate.owns(player._mekatana_action_token, PLAYER_STATE.ACTION_GATE.Kind.WEAPON, "mekatana")):
		player._cancel_mekatana_attack()
	if player._weapon_id != "mekatana":
		return false
	var owned_movement: bool = player._mekatana_attack.is_direction_locked()
	var before := player.global_position
	player._mekatana_attack.update(delta)
	player._mekatana_movement_owned = owned_movement
	if owned_movement:
		player._mekatana_velocity = (player.global_position - before) / maxf(delta, 0.001)
		player.velocity = Vector3.ZERO
	player._sync_mekatana_pose()
	return owned_movement


func _move_mekatana_dash(motion: Vector3) -> Vector3:
	var before := player.global_position
	player.move_and_collide(motion)
	player.global_position = Vector3(clampf(player.global_position.x, -27.0, 27.0), 0.0, clampf(player.global_position.z, -27.0, 27.0))
	return player.global_position - before


func _sync_mekatana_pose() -> void:
	if player._visual_rig == null:
		return
	if player._mekatana_attack.is_busy():
		player._visual_rig.set_mekatana_pose(player._mekatana_attack.step, player._mekatana_attack.phase, player._mekatana_attack.progress())
	else:
		player._visual_rig.clear_mekatana_pose()


func _on_mekatana_slash_started(rank: int) -> void:
	if player._visual_rig != null:
		player._visual_rig.set_mekatana_pose(rank, "active", 0.0)


func _on_mekatana_hit(target: Node3D, _applied: float, multiplier: float) -> void:
	player._mark_combat_event()
	if player._visual_rig != null:
		player._visual_rig.set_mekatana_impact(target, multiplier)
	# Existing target damage callbacks credit effective damage and Omnivamp.
	# Presentation never credits it a second time or adds an electrical status.
	if player._uses_local_feedback() and player._mekatana_attack.step == 2 and multiplier >= 1.6:
		player._camera_impulse(0.045, 0.025)


func _on_mekatana_finished() -> void:
	player._action_gate.release(player._mekatana_action_token)
	player._mekatana_action_token = 0
	player._sync_mekatana_pose()


func _cancel_mekatana_attack() -> void:
	player._mekatana_attack.cancel()
	player._action_gate.release(player._mekatana_action_token)
	player._mekatana_action_token = 0
	player._mekatana_movement_owned = false
	player._mekatana_velocity = Vector3.ZERO
	if player._visual_rig != null:
		player._visual_rig.clear_mekatana_pose()
