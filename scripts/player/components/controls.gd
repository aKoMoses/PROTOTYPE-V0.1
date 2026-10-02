extends Node

# Movement, aiming, desktop/touch commands and exclusive action ownership.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const INPUT_BUFFER_SECONDS := 0.14

var player: PLAYER_STATE
var _input_time := 0.0
var _queued_command: Dictionary = {}
var _desktop_down_last := false


func advance_input_time(delta: float) -> void:
	_input_time += maxf(0.0, delta)
	if not _queued_command.is_empty() and _input_time > float(_queued_command.expires):
		_queued_command.clear()


func clear_command_buffer() -> void:
	_queued_command.clear()
	_desktop_down_last = false


func _queue_command(command: Dictionary) -> bool:
	if not player._gameplay_enabled or player.is_real_dead():
		return false
	command["expires"] = _input_time + INPUT_BUFFER_SECONDS
	command["weapon"] = player._weapon_id
	_queued_command = command
	return true


func _module_id(action: String) -> String:
	return player._offensive_module_id if action == "offensive" else player._defensive_module_id if action == "defensive" else player._mobility_module_id if action == "mobility" else ""


func _static_shield_remaining() -> float:
	if player.survival_mode and player.survival_evolution_effects != null:
		return maxf(player._stasis_remaining, player.survival_evolution_effects.shield_remaining)
	return player._stasis_remaining


func _module_blocked(action: String) -> bool:
	var module_id := _module_id(action)
	# Static Shield preempts casts and crowd control; only its recharge gates entry.
	if module_id == "static_shield":
		return _static_shield_remaining() <= 0.0 and not player._module_ready(module_id)
	var recast: bool = module_id == "javelin" and player._has_live_javelin_mark()
	if player._action_incapacitated() or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE) or player._action_gate.was_claimed_this_frame():
		return true
	if module_id in ["pyro_boots", "counter", "eclipse"] and player._dash_active:
		return true
	if module_id in ["counter", "eclipse"] and player._pelto_pull_active:
		return true
	return not recast and not player._module_ready(module_id)


func request_module_command(action: String, touch: bool = false, released: bool = false) -> bool:
	var module_id := _module_id(action)
	if module_id.is_empty() or not player._gameplay_enabled or player.is_real_dead():
		return false
	# A second finger must never release a cast owned by the first one.
	if player._active_module_id == module_id:
		return false
	# Preserve the longer escape buffer during a forced Fulguro displacement.
	if player._can_buffer_defensive_action():
		if action == "mobility" and module_id == "pyro_boots":
			player._buffer_dash()
			return true
		if action == "offensive" and module_id == "javelin" and player._has_live_javelin_mark():
			player._buffer_javelin_recast()
			return true
	if touch and bool(_queued_command.get("touch", false)) and str(_queued_command.get("action", "")) == action and not bool(_queued_command.get("released", false)):
		return false
	var command := {"type": "module", "action": action, "module": module_id, "touch": touch, "released": released}
	if _module_blocked(action):
		return _queue_command(command)
	_queued_command.clear()
	return _execute_module_command(command)


func _execute_module_command(command: Dictionary) -> bool:
	var action: String = command.action
	var touch: bool = command.touch
	var generation: int = player._action_gate._generation
	var shield_before := _static_shield_remaining()
	var recast_accepted := false
	if action == "offensive":
		if player._offensive_module_id == "fulguro_punch":
			player._begin_fulguro_charge()
			player._desktop_fulguro_charge_held = not touch and player.is_fulguro_charging()
		elif player._offensive_module_id == "javelin":
			recast_accepted = player._begin_javelin_charge()
			if touch and player.is_javelin_charging():
				player._javelin_module_aim = player.aim_direction.normalized()
			player._desktop_javelin_charge_held = not touch and player.is_javelin_charging()
		elif player._offensive_module_id == "pelto_smash":
			player._perform_pelto_smash(true)
			player._desktop_pelto_aim_held = not touch and player.is_pelto_preparing()
		else:
			player._perform_offensive_module()
	elif action == "mobility" and player._mobility_module_id == "eclipse":
		player._eclipse.begin(player, touch)
	elif action == "defensive":
		player._activate_defensive_module()
	elif action == "mobility":
		player._activate_mobility_module()
	var accepted: bool = recast_accepted or generation != player._action_gate._generation or _static_shield_remaining() < shield_before
	if accepted and bool(command.released):
		end_touch_action(action, touch)
	return accepted


func _weapon_unavailable() -> bool:
	if player._action_incapacitated() or player._action_gate.is_busy() or player._action_gate.was_claimed_this_frame():
		return true
	var now := Time.get_ticks_msec() / 1000.0
	match player._weapon_id:
		"blaster": return now < player._blaster_next_attack_ready_at
		"longshot": return player._longshot_attack_busy or now < player._longshot_next_attack_ready_at
		"shotgun": return player._shotgun_attack_busy or player._shotgun_reloading or player._shotgun_ammo <= 0
		"mekatana": return player._mekatana_attack.is_busy() or player._dash_active or player._pelto_pull_active
	return false


func execute_buffered_command() -> void:
	if _queued_command.is_empty():
		return
	if not player._gameplay_enabled or player.is_real_dead() or _input_time > float(_queued_command.expires) or str(_queued_command.weapon) != player._weapon_id:
		_queued_command.clear()
		return
	var command := _queued_command
	if str(command.type) == "module":
		if str(command.module) != _module_id(str(command.action)):
			_queued_command.clear()
			return
		if _module_blocked(str(command.action)):
			return
		_queued_command = {}
		_execute_module_command(command)
		return
	if _weapon_unavailable():
		return
	_queued_command = {}
	if bool(command.touch) and not bool(command.released):
		player._touch_attack_rearm_required = false
		player.begin_touch_fire()
		return
	if not bool(command.touch):
		player._desktop_attack_rearm_required = false
	player._set_aim_direction(command.direction)
	match player._weapon_id:
		"blaster":
			player._desktop_blaster_tap_buffered = false
			if not bool(command.touch) and player._desktop_attack_input_held():
				player._begin_blaster_charge(Time.get_ticks_msec() / 1000.0)
			else:
				player._fire_blaster_projectile(player._blaster_damage, 0.0, command.direction)
		"shotgun": player._perform_shotgun_attack()
		"longshot": player._perform_longshot_attack()
		"mekatana": player._perform_mekatana_attack()


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "ControlsComponent"


func _update_movement(delta: float) -> void:
	if player.is_eclipse_travelling():
		player.velocity = Vector3.ZERO
		player.move_direction = Vector3.ZERO
		return
	if player._update_mekatana_attack(delta):
		return
	if player._stasis_remaining > 0.0:
		player.velocity = Vector3.ZERO
		player.move_direction = Vector3.ZERO
		return
	if player._fulguro_projection_active:
		player._update_fulguro_projection(delta)
		return
	if player._dash_active:
		player._update_dash(delta)
		return
	if player._pelto_pull_active:
		player._update_pelto_pull(delta)
		return
	var input_vector := player._touch_move_vector
	if input_vector.length_squared() <= 0.001:
		input_vector = Vector2.ZERO
		if Input.is_action_pressed("game_move_left"):
			input_vector.x -= 1.0
		if Input.is_action_pressed("game_move_right"):
			input_vector.x += 1.0
		if Input.is_action_pressed("game_move_up"):
			input_vector.y -= 1.0
		if Input.is_action_pressed("game_move_down"):
			input_vector.y += 1.0

	input_vector = input_vector.limit_length(1.0)
	var world_move_direction: Vector3 = player._camera_relative_direction(input_vector)
	if world_move_direction.length_squared() > 0.001:
		player._last_move_direction = world_move_direction
	if player.combat_state != null and player.combat_state.is_stunned():
		input_vector = Vector2.ZERO
		world_move_direction = Vector3.ZERO
	var slow_multiplier := 1.0
	if player.combat_state != null:
		slow_multiplier = 1.0 - player.combat_state.get_slow_percent() / 100.0
	var bio_multiplier := player._bio_speed_multiplier if player._bio_remaining > 0.0 else 1.0
	var permutation_multiplier := float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.permutation.speed_multiplier) if player._permutation_speed_remaining > 0.0 else 1.0
	var charge_multiplier := player._blaster_charge_slow_multiplier if player._blaster_charge_active else 1.0
	if player._active_module_id == "rocket_basket":
		charge_multiplier *= float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.rocket_basket.cast_move_multiplier)
	var evolution_speed: float = player.survival_evolution_effects.movement_multiplier() if player.survival_mode and player.survival_evolution_effects != null else 1.0
	player.velocity = world_move_direction * player.move_speed * bio_multiplier * permutation_multiplier * slow_multiplier * charge_multiplier * evolution_speed * (player._counter.movement_multiplier() if player._counter != null else 1.0) * player._longshot_state.movement_multiplier()
	player.velocity = ARENA_TRAVERSAL.motion(player, player.velocity * delta) / maxf(delta, 0.001)
	player.move_and_slide()
	ARENA_TRAVERSAL.snap(player)


func _get_actual_move_velocity() -> Vector3:
	if player._mekatana_movement_owned:
		return player._mekatana_velocity
	if player._stasis_remaining > 0.0 or (player.combat_state != null and player.combat_state.is_stunned()):
		return Vector3.ZERO
	if player._fulguro_projection_active:
		return player._fulguro_projection_direction * player._fulguro_projection_speed
	if player._dash_active and player._dash_direction.length_squared() > 0.001:
		var dash_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.get("pyro_boots", {})
		var dash_duration := maxf(0.001, float(dash_definition.get("dash_duration", 0.25)))
		return player._dash_direction * float(dash_definition.get("dash_distance", 3.0)) / dash_duration
	var actual_velocity := player.get_real_velocity()
	actual_velocity.y = 0.0
	return actual_velocity


func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.length_squared() <= 0.001:
		return Vector3.ZERO
	var camera := player.get_viewport().get_camera_3d() if player.get_viewport() != null else null
	var camera_right := Vector3.RIGHT
	var camera_forward := Vector3.FORWARD
	if camera != null:
		camera_right = camera.global_basis.x
		camera_forward = -camera.global_basis.z
		camera_right.y = 0.0
		camera_forward.y = 0.0
		if camera_right.length_squared() > 0.001:
			camera_right = camera_right.normalized()
		if camera_forward.length_squared() > 0.001:
			camera_forward = camera_forward.normalized()
	var world_direction := camera_right * input_vector.x - camera_forward * input_vector.y
	world_direction.y = 0.0
	return world_direction.normalized() if world_direction.length_squared() > 0.001 else Vector3.ZERO


func _update_aim() -> void:
	if player.is_pelto_preparing() and player._pelto_aim_held:
		if player._pelto_release_requested:
			player._set_aim_direction(player._pelto_direction)
			return
		if player._pelto_module_aim.length_squared() > 0.001:
			player._set_aim_direction(player._pelto_module_aim)
			return
	if player.is_javelin_charging():
		if player._javelin_release_at >= 0.0:
			player._set_aim_direction(player._javelin_release_direction)
			return
		if player._javelin_module_aim.length_squared() > 0.001:
			player._set_aim_direction(player._javelin_module_aim)
			return
	if player._touch_aim_active and player._touch_aim_vector.length_squared() > 0.04:
		player._set_aim_direction(player._camera_relative_direction(player._touch_aim_vector))
		return
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		if player._last_move_direction.length_squared() > 0.001:
			player._set_aim_direction(player._last_move_direction)
		return
	var camera := player.get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse_position := player.get_viewport().get_mouse_position()
	player._aim_at_screen_position(mouse_position, camera)


func _aim_at_screen_position(mouse_position: Vector2, camera: Camera3D) -> void:
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	if absf(ray_direction.y) < 0.001:
		return
	# The isometric camera projects the torso and the floor to different pixels.
	# Aim on the combat plane so pointing at a robot's body does not turn the
	# barrel toward a point behind it, especially when it stands to either side.
	var distance_to_aim_plane := (player.global_position.y + PLAYER_STATE.MOUSE_AIM_HEIGHT - ray_origin.y) / ray_direction.y
	if distance_to_aim_plane <= 0.0:
		return
	var aim_point := ray_origin + ray_direction * distance_to_aim_plane
	var flat_direction := aim_point - player.global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.04:
		player._set_aim_direction(flat_direction.normalized())


func _set_aim_direction(direction: Vector3) -> void:
	if player._mekatana_attack.is_direction_locked():
		player.aim_direction = player._mekatana_attack.direction
		return
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		player.aim_direction = direction.normalized()
	elif player._last_move_direction.length_squared() > 0.001:
		player.aim_direction = player._last_move_direction.normalized()
	else:
		player.aim_direction = Vector3(0.0, 0.0, -1.0)


func _normalized_aim_direction() -> Vector3:
	var direction := player.aim_direction
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)


## Presentation only: use the same origin, direction and collision settings as shots.


func get_weapon_aim_preview() -> Dictionary:
	if not player._uses_local_feedback() or not player._gameplay_enabled or player.is_real_dead() or player._weapon_id not in ["blaster", "longshot"]:
		return {}
	# Only a currently held, accepted fire input owns this guide. Movement,
	# mouse emulation and the lingering aim/fire pose must not keep it visible.
	if not _weapon_aim_input_held():
		return {}
	var direction: Vector3 = player._normalized_aim_direction()
	var muzzle := player._blaster_muzzle if player._weapon_id == "blaster" else player._longshot_muzzle
	var start := muzzle.global_position if muzzle != null else player.global_position + Vector3.UP * 0.9 + direction * (0.62 if player._weapon_id == "blaster" else 0.7)
	var excluded: Array[RID] = [player.get_rid()]
	if player.survival_mode and player.survival_evolution_effects != null:
		excluded.append_array(player.survival_evolution_effects.own_wall_exclusions())
	excluded = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, excluded)
	var radius := 0.0
	var maximum := player._blaster_max_range
	var mask := 1 | 2 | 8
	if player._weapon_id == "blaster":
		start = player._safe_projectile_origin(start)
	else:
		if player._has_skeletal_weapon_attachment():
			direction = player._visual_rig.get_aim_forward_direction().normalized()
		radius = float(player._longshot_definition["projectile_radius"])
		if player.is_longshot_enhanced_ready():
			radius *= float(player._longshot_definition["enhanced_size_multiplier"])
		maximum = float(player._longshot_definition["max_range"])
		mask |= 4
	direction = ARENA_TRAVERSAL.shot_direction(player, start, direction)
	return {"origin": start, "direction": direction, "range": maximum, "radius": radius,
		"mask": mask, "exclude": excluded, "support": player.global_position + Vector3.UP * 0.9,
		"weapon": player._weapon_id}


func _weapon_aim_input_held() -> bool:
	if player._action_incapacitated() or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE):
		return false
	var touch_held := not player._touch_attack_rearm_required and (player._touch_fire_active or player._touch_attack_held)
	var desktop_held: bool = not player._desktop_attack_rearm_required and player._desktop_attack_input_held()
	return touch_held or desktop_held


func _weapon_pose_uses_aim() -> bool:
	return player.weapon_pose_state in [PLAYER_STATE.WeaponPoseState.AIM, PLAYER_STATE.WeaponPoseState.FIRE, PLAYER_STATE.WeaponPoseState.AIM_HOLD]


func get_weapon_pose_state_name() -> StringName:
	return PLAYER_STATE.WEAPON_POSE_NAMES[player.weapon_pose_state]


func _set_weapon_pose_state(next_state: PLAYER_STATE.WeaponPoseState, restart_hold: bool = false) -> void:
	player.weapon_pose_state = next_state
	if next_state == PLAYER_STATE.WeaponPoseState.FIRE:
		player._fire_pose_remaining = PLAYER_STATE.SKELETAL_FIRE_POSE_DURATION
	if next_state == PLAYER_STATE.WeaponPoseState.AIM_HOLD and restart_hold:
		player._aim_hold_remaining = player.aim_hold_time
	player._update_aim_pose_state()


func _begin_weapon_aim() -> void:
	if player._weapon_id not in ["blaster", "shotgun", "longshot"]:
		return
	if player._round_warmup_active and player._gameplay_enabled:
		player._play_player_animation(&"idle")
		player._round_warmup_active = false
	player._set_weapon_pose_state(PLAYER_STATE.WeaponPoseState.AIM)


func _begin_weapon_fire() -> void:
	if player._weapon_id not in ["blaster", "shotgun", "longshot"]:
		return
	if player._round_warmup_active and player._gameplay_enabled:
		player._play_player_animation(&"idle")
		player._round_warmup_active = false
	player._set_weapon_pose_state(PLAYER_STATE.WeaponPoseState.FIRE)
	if player._visual_rig != null:
		player._visual_rig.commit_firing_pose(player._normalized_aim_direction())


func _begin_aim_hold() -> void:
	if player._weapon_id in ["blaster", "shotgun", "longshot"] and player._gameplay_enabled and not player.is_real_dead():
		player._set_weapon_pose_state(PLAYER_STATE.WeaponPoseState.AIM_HOLD, true)
	else:
		player._reset_weapon_pose_to_locomotion()


func _reset_weapon_pose_to_locomotion(immediate: bool = false) -> void:
	player._aim_hold_remaining = 0.0
	player._fire_pose_remaining = 0.0
	var moving = player._get_actual_move_velocity().length() > 0.15
	player.weapon_pose_state = PLAYER_STATE.WeaponPoseState.LOCOMOTION if moving else PLAYER_STATE.WeaponPoseState.IDLE
	if player._visual_rig != null:
		player._visual_rig.set_aim_enabled(false, immediate)


func _update_weapon_pose_state(delta: float) -> void:
	if not player._gameplay_enabled or player.is_real_dead() or player._weapon_id not in ["blaster", "shotgun", "longshot"]:
		player._reset_weapon_pose_to_locomotion(true)
		return
	var aim_held := _weapon_aim_input_held()
	if aim_held and not player._weapon_pose_uses_aim():
		player._begin_weapon_aim()
	if player.weapon_pose_state == PLAYER_STATE.WeaponPoseState.AIM:
		if not player._blaster_charge_active and not player._shotgun_attack_busy and not player._longshot_attack_busy:
			player._begin_aim_hold()
		return
	if player.weapon_pose_state == PLAYER_STATE.WeaponPoseState.FIRE:
		player._fire_pose_remaining = maxf(0.0, player._fire_pose_remaining - delta)
		if (player._visual_rig == null or not player._visual_rig.is_shot_kick_active()) and player._fire_pose_remaining <= 0.0:
			player._begin_aim_hold()
		return
	if player.weapon_pose_state == PLAYER_STATE.WeaponPoseState.AIM_HOLD:
		# Cooldown may outlast the post-shot hold. Keep following live aim until
		# the accepted fire input is released, then start the usual lowering delay.
		player._aim_hold_remaining = player.aim_hold_time if aim_held else maxf(0.0, player._aim_hold_remaining - delta)
		if player._aim_hold_remaining <= 0.0:
			player._reset_weapon_pose_to_locomotion()
		return
	var moving = player._get_actual_move_velocity().length() > 0.15
	player._set_weapon_pose_state(PLAYER_STATE.WeaponPoseState.LOCOMOTION if moving else PLAYER_STATE.WeaponPoseState.IDLE)


func reset_desktop_inputs() -> void:
	clear_command_buffer()
	if player._eclipse.aiming:
		player._eclipse.cancel(player)
	player._desktop_mouse_attack_held = false
	player._desktop_blaster_tap_buffered = false
	player._desktop_attack_rearm_required = player._desktop_attack_input_held()
	player._attack_hold_last = false
	if player._blaster_charge_active and not player._touch_fire_charge_started:
		player._cancel_blaster_charge()
	if player._desktop_fulguro_charge_held and player.is_fulguro_charging():
		player._cancel_fulguro_attack()
	player._desktop_fulguro_charge_held = false
	if player._desktop_javelin_charge_held:
		player._cancel_javelin_charge()
	player._desktop_javelin_charge_held = false


func _desktop_attack_input_held() -> bool:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		player._desktop_mouse_attack_held = false
	# The mapped action also includes emulated mouse events and GUI presses.
	# Read its keyboard bindings separately, keeping the validated mouse latch.
	if InputMap.has_action("game_attack"):
		for event in InputMap.action_get_events("game_attack"):
			if event is InputEventKey and Input.is_key_pressed(event.keycode):
				return true
	return player._desktop_mouse_attack_held


func _action_incapacitated() -> bool:
	return not player._gameplay_enabled or player.is_real_dead() or player.is_eclipse_travelling() or player._stasis_remaining > 0.0 or player._fulguro_projection_active or (player.combat_state != null and player.combat_state.is_stunned())


func _try_begin_weapon_action(action_id: String) -> int:
	if player._action_incapacitated() or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE):
		return 0
	var token: int = player._action_gate.try_acquire(PLAYER_STATE.ACTION_GATE.Kind.WEAPON, action_id)
	if token != 0 and str(_queued_command.get("type", "")) == "weapon":
		_queued_command.clear()
	return token


func _try_begin_module_action(module_id: String) -> int:
	var action_token := 0
	if module_id == "static_shield":
		if not player._gameplay_enabled or player.is_real_dead() or not player._module_ready(module_id):
			return 0
		player._cancel_fulguro_attack()
		player._cancel_pelto_smash()
		player._cancel_pending_module_action()
		player._eclipse.cancel(player)
		# Invalidate the old owner even when it started during this physics frame.
		player._action_gate.release(player._action_gate.get_generation())
		action_token = player._action_gate.try_acquire(PLAYER_STATE.ACTION_GATE.Kind.MODULE, module_id, -1, true)
	elif player._action_incapacitated() or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE):
		return 0
	elif player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.WEAPON):
		action_token = player._action_gate.replace_weapon_with_module(module_id)
	else:
		action_token = player._action_gate.try_acquire(PLAYER_STATE.ACTION_GATE.Kind.MODULE, module_id)
	if action_token == 0:
		return 0
	_queued_command.clear()
	player._active_module_action_token = action_token
	player._active_module_id = module_id
	player._interrupt_weapon_for_module()
	return action_token


func _interrupt_weapon_for_module() -> void:
	player._cancel_mekatana_attack()
	player._cancel_longshot_attack()
	player._desktop_attack_rearm_required = player._desktop_attack_rearm_required or player._desktop_attack_input_held()
	player._desktop_blaster_tap_buffered = false
	player._touch_attack_rearm_required = player._touch_attack_rearm_required or player._touch_fire_active or player._touch_attack_held
	player._touch_fire_requests.clear()
	if player._blaster_charge_active or player._touch_fire_active or player._touch_attack_held:
		player.cancel_touch_fire()
	if player._blaster_attack_busy:
		player._cancel_blaster_attack()
	if player._shotgun_attack_busy:
		player._cancel_shotgun_attack()
	if player._axe_attack_busy:
		player._cancel_axe_attack()
	player._attack_hold_last = player._desktop_attack_input_held()


func _module_action_can_execute(action_token: int, module_id: String) -> bool:
	return player._action_gate.owns(action_token, PLAYER_STATE.ACTION_GATE.Kind.MODULE, module_id) and not player._action_incapacitated()


func _end_module_action(action_token: int, module_id: String) -> bool:
	if not player._action_gate.owns(action_token, PLAYER_STATE.ACTION_GATE.Kind.MODULE, module_id):
		return false
	player._action_gate.release(action_token)
	if player._active_module_action_token == action_token:
		player._active_module_action_token = 0
		player._active_module_id = ""
	player._module_busy = false
	return true


func _cancel_pending_module_action(reason: String = "") -> void:
	if player._active_module_id == "projector":
		player._cancel_projector_cast()
	if player._active_module_id == "counter" and player._counter != null:
		player._counter.cancel()
		return
	if player._active_module_action_token == 0:
		return
	if player._active_module_id == "eclipse":
		player._eclipse.cancel(player)
		return
	if player._active_module_id == "javelin" and player.is_javelin_charging():
		player._cancel_javelin_charge()
		if reason != "" and player._attack_label != null:
			player._attack_label.text = reason
		return
	var module_id := player._active_module_id
	var action_token := player._active_module_action_token
	player._module_token += 1
	player._javelin_launch_token += 1
	player._end_module_action(action_token, module_id)
	if reason != "" and player._attack_label != null:
		player._attack_label.text = reason


func _reset_action_ownership() -> void:
	clear_command_buffer()
	player._cancel_mekatana_attack()
	player._longshot_action_token = 0
	player._action_gate.reset()
	player._active_module_action_token = 0
	player._active_module_id = ""
	player._blaster_action_token = 0
	player._shotgun_action_token = 0
	player._axe_action_token = 0
	player._desktop_attack_rearm_required = player._desktop_attack_input_held()
	player._desktop_mouse_attack_held = false
	player._desktop_fulguro_charge_held = false
	player._desktop_blaster_tap_buffered = false
	player._touch_attack_rearm_required = false


func get_action_owner() -> String:
	return player._action_gate.get_owner_id()


func _update_attack(force_action_blocked: bool = false) -> void:
	var desktop_wants_attack: bool = player._desktop_attack_input_held()
	if not desktop_wants_attack:
		player._desktop_attack_rearm_required = false
	var new_press := desktop_wants_attack and not _desktop_down_last
	_desktop_down_last = desktop_wants_attack
	if new_press and not player._desktop_attack_rearm_required and _weapon_unavailable():
		_queue_command({"type": "weapon", "touch": false, "released": false, "direction": player._normalized_aim_direction()})
	if force_action_blocked or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE) or player._action_incapacitated():
		player._desktop_blaster_tap_buffered = false
		if desktop_wants_attack:
			player._desktop_attack_rearm_required = true
		if player._touch_fire_active or player._touch_attack_held:
			player._touch_attack_rearm_required = true
			player.cancel_touch_fire()
		player._touch_fire_requests.clear()
		player._attack_hold_last = desktop_wants_attack
		return
	if player._desktop_attack_rearm_required:
		if desktop_wants_attack:
			player._attack_hold_last = true
			desktop_wants_attack = false
		else:
			player._desktop_attack_rearm_required = false
			player._attack_hold_last = false
	var wants_to_attack := player._touch_attack_held or desktop_wants_attack
	if player._weapon_id == "mekatana":
		if wants_to_attack:
			player._perform_mekatana_attack()
		player._attack_hold_last = wants_to_attack
		return
	if player._weapon_id == "longshot":
		if wants_to_attack:
			player._perform_longshot_attack()
		player._attack_hold_last = wants_to_attack
		return
	if player._weapon_id == "shotgun":
		player._update_shotgun_attack(wants_to_attack)
		player._attack_hold_last = wants_to_attack
		return
	var now := Time.get_ticks_msec() / 1000.0
	var processed_touch_request := false
	if not player._touch_fire_requests.is_empty():
		player._process_touch_fire_request()
		processed_touch_request = true
	if player._touch_fire_active:
		player._update_mobile_blaster_contact(now)
		# Le flux tactile possède sa propre machine d'état. Il ne doit jamais être
		# interprété une seconde fois comme le maintien PC historique.
		player._attack_hold_last = wants_to_attack
		return
	if processed_touch_request:
		player._attack_hold_last = wants_to_attack
		return
	if player._desktop_blaster_tap_buffered:
		if wants_to_attack:
			# Un nouveau maintien remplace le tap en attente et suit le chemin de charge.
			player._desktop_blaster_tap_buffered = false
		elif now >= player._blaster_next_attack_ready_at:
			player._desktop_blaster_tap_buffered = false
			player._fire_blaster_projectile(player._blaster_damage, 0.0, player.aim_direction.normalized())
			player._attack_hold_last = false
			return
	var just_released := not wants_to_attack and player._attack_hold_last
	# Un appui PC peut commencer pendant le cooldown du tir précédent. Dans ce
	# cas, la première tentative est refusée mais le maintien doit amorcer la
	# charge dès que l'arme redevient disponible. Le réarmement post-cast a déjà
	# forcé `desktop_wants_attack` à false plus haut tant qu'aucun relâchement
	# réel n'a eu lieu, donc cette relance ne mémorise jamais une entrée interdite.
	if wants_to_attack and not player._blaster_charge_active:
		player._begin_blaster_charge(now)
	player._update_active_blaster_charge(now)
	if just_released:
		if player._blaster_charge_active:
			player._release_blaster_charge()
		elif now < player._blaster_next_attack_ready_at:
			# Un tap bref pendant la cadence conserve uniquement un tir normal. Les
			# entrées de cast passent par la branche bloquée plus haut et effacent ce
			# tampon, elles ne peuvent donc jamais être rejouées après l'incantation.
			player._desktop_blaster_tap_buffered = true
	player._attack_hold_last = wants_to_attack


func _update_active_blaster_charge(now: float) -> void:
	if not player._blaster_charge_active:
		return
	player._blaster_charge_ratio = clampf((now - player._blaster_charge_started_at) / maxf(0.001, player._blaster_charge_time), 0.0, 1.0)
	if player._blaster_charge_ratio >= 1.0:
		player._play_blaster_ready_sound()


func _update_mobile_blaster_contact(now: float) -> void:
	if not player._touch_fire_active or player._weapon_id != "blaster":
		return
	var held_for := maxf(0.0, now - player._touch_fire_started_at)
	if not player._touch_fire_charge_started and held_for >= player.mobile_blaster_charge_threshold and now >= player._blaster_next_attack_ready_at:
		# Le délai de distinction ne rallonge pas la charge existante : une charge
		# commencée à 0,20 s conserve l'instant du toucher comme origine.
		var charge_origin := maxf(player._touch_fire_started_at, player._blaster_next_attack_ready_at)
		player._begin_blaster_charge(charge_origin)
		player._touch_fire_charge_started = player._blaster_charge_active
	player._update_active_blaster_charge(now)


func _process_touch_fire_request() -> void:
	if player._touch_fire_requests.is_empty():
		return
	var pending: Dictionary = player._touch_fire_requests.front()
	var now := Time.get_ticks_msec() / 1000.0
	if now > float(pending.get("expires", now + INPUT_BUFFER_SECONDS)):
		player._touch_fire_requests.pop_front()
		return
	if now < player._blaster_next_attack_ready_at:
		return
	var request: Dictionary = player._touch_fire_requests.pop_front()
	if not player._gameplay_enabled or player.is_real_dead() or player._weapon_id != "blaster":
		return
	var direction: Vector3 = request.get("direction", player._normalized_aim_direction())
	var charge_ratio := clampf(float(request.get("charge_ratio", 0.0)), 0.0, 1.0)
	var damage := lerpf(player._blaster_damage, player._blaster_max_damage, charge_ratio)
	player._fire_blaster_projectile(damage, charge_ratio, direction)


func _update_debug_effects() -> void:
	if player._pressed_once(KEY_F8):
		player._direction_debug_enabled = not player._direction_debug_enabled
		if player._direction_debug_mesh != null:
			player._direction_debug_mesh.visible = player._direction_debug_enabled
		if player._direction_debug_label != null:
			player._direction_debug_label.visible = player._direction_debug_enabled
		if player._attack_label != null:
			player._attack_label.text = "DEBUG DIRECTIONS : %s (F8)" % ("ON" if player._direction_debug_enabled else "OFF")
	# Temporary PC-only mannequin probes for P0-102. They do not replace the
	# future module bindings and are intentionally explicit in the HUD/README.
	var active_scene := player.get_tree().current_scene
	if active_scene == null:
		return
	# Debug mannequin shortcuts only exist in the duel scene. Gameplay module
	# inputs continue in Survival and Training Ground as well.
	var target := active_scene.get_node_or_null("TargetDummy") if not active_scene.has_method("get_training_targets") else null
	if target != null:
		if player._pressed_once(KEY_F1):
			target.call("apply_burn", PLAYER_STATE.COMBAT_DATA.BURN_DURATION, PLAYER_STATE.COMBAT_DATA.BURN_DAMAGE_PER_SECOND, "debug")
		if player._pressed_once(KEY_F2):
			target.call("apply_slow", 1.5, 30.0, "debug")
		if player._pressed_once(KEY_F3):
			target.call("apply_stun", 1.5, "debug")
		if player._pressed_once(KEY_F4):
			target.call("apply_spotted", 5.0, "debug")
		if player._pressed_once(KEY_F5):
			target.call("reset_combat_state")
		if player._pressed_once(KEY_F6):
			player._show_debug_hitbox = not player._show_debug_hitbox
			player._attack_label.text = "DIAGNOSTIC HITBOX : %s" % ("ON" if player._show_debug_hitbox else "OFF")
		if player._pressed_once(KEY_F7):
			var bot_enabled := bool(target.call("toggle_training_bot"))
			player._attack_label.text = "BOT D'ENTRAÎNEMENT : %s" % ("ON" if bot_enabled else "OFF")
	if not player.survival_mode and player._pressed_action_once("weapon"):
		player._cycle_weapon()
	for action in ["offensive", "defensive", "mobility"]:
		var mapped: String = "game_" + action
		var down := Input.is_action_pressed(mapped)
		var was_down := bool(player._debug_key_latches.get(mapped, false))
		player._debug_key_latches[mapped] = down
		if down and not was_down:
			request_module_command(action)
		elif not down and was_down:
			end_touch_action(action, false)
			if action == "offensive":
				player._desktop_fulguro_charge_held = false
				player._desktop_javelin_charge_held = false
				player._desktop_pelto_aim_held = false
	if not player.survival_mode and player._consume_touch_action("weapon"):
		player._cycle_weapon()
	if player._consume_touch_action("offensive"):
		request_module_command("offensive", true, true)
	if player._consume_touch_action("defensive"):
		request_module_command("defensive", true, true)
	if player._consume_touch_action("mobility"):
		request_module_command("mobility", true, true)


func _refresh_control_bindings() -> void:
	clear_command_buffer()
	player._debug_key_latches.clear()
	player.cancel_touch_fire()


func _pressed_action_once(action: String) -> bool:
	var mapped := StringName("game_" + action)
	var is_down := Input.is_action_pressed(mapped)
	var was_down := bool(player._debug_key_latches.get(mapped, false))
	player._debug_key_latches[mapped] = is_down
	return is_down and not was_down


func _pressed_once(keycode: Key) -> bool:
	var is_down := Input.is_key_pressed(keycode)
	var was_down := bool(player._debug_key_latches.get(keycode, false))
	player._debug_key_latches[keycode] = is_down
	return is_down and not was_down


func set_touch_move_vector(value: Vector2) -> void:
	player.set_move_input(value)


func set_touch_aim_vector(value: Vector2) -> void:
	player.set_aim_input(value)


func set_move_input(value: Vector2) -> void:
	player._touch_move_vector = value.limit_length(1.0)


func set_aim_input(value: Vector2) -> void:
	player._touch_aim_vector = value.limit_length(1.0)
	player._touch_aim_active = player._touch_aim_vector.length_squared() > 0.04
	if player._touch_aim_active:
		var direction: Vector3 = player._camera_relative_direction(player._touch_aim_vector)
		if direction.length_squared() > 0.001:
			player._touch_last_valid_aim_direction = direction.normalized()
			# Mettre à jour immédiatement évite de perdre le dernier drag lorsqu'un
			# relâchement arrive entre deux frames physiques.
			player._set_aim_direction(player._touch_last_valid_aim_direction)


func set_touch_attack_held(value: bool) -> void:
	if value and (player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE) or player._action_gate.was_claimed_this_frame() or player._action_incapacitated()):
		player._touch_attack_rearm_required = true
		player._touch_attack_held = false
		return
	if not value:
		player._touch_attack_rearm_required = false
	player._touch_attack_held = value


func begin_touch_fire() -> void:
	if player._touch_fire_active or not player._gameplay_enabled or player.is_real_dead():
		return
	if not player._touch_attack_rearm_required and (player._action_incapacitated() or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE) or player._action_gate.was_claimed_this_frame()):
		_queue_command({"type": "weapon", "touch": true, "released": false, "direction": player._normalized_aim_direction()})
		return
	if player._touch_attack_rearm_required or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE) or player._action_gate.was_claimed_this_frame() or player._action_incapacitated():
		player._touch_attack_rearm_required = true
		return
	player._touch_fire_active = true
	player._touch_fire_started_at = Time.get_ticks_msec() / 1000.0
	player._touch_fire_charge_started = false
	player._touch_last_valid_aim_direction = player._normalized_aim_direction()
	if player._weapon_id in ["shotgun", "longshot", "mekatana"]:
		if _weapon_unavailable():
			_queue_command({"type": "weapon", "touch": true, "released": false, "direction": player._normalized_aim_direction()})
		# Le Shotgun conserve exactement son chemin pressé/maintenu existant.
		player._touch_attack_held = true


func end_touch_fire(final_aim: Vector2 = Vector2.ZERO) -> bool:
	if final_aim.length_squared() > 0.04:
		player.set_aim_input(final_aim)
	if str(_queued_command.get("type", "")) == "weapon" and bool(_queued_command.get("touch", false)):
		_queued_command.released = true
		_queued_command.direction = player._normalized_aim_direction()
		player._touch_fire_active = false
		player._touch_attack_held = false
		return true
	if player._touch_attack_rearm_required:
		player._touch_attack_rearm_required = false
		player._touch_fire_active = false
		player._touch_attack_held = false
		player._touch_fire_requests.clear()
		return false
	if not player._touch_fire_active:
		return false
	var released_weapon := player._weapon_id
	var now := Time.get_ticks_msec() / 1000.0
	var held_for := maxf(0.0, now - player._touch_fire_started_at)
	var direction_snapshot := player._touch_last_valid_aim_direction
	if direction_snapshot.length_squared() <= 0.001:
		direction_snapshot = player._normalized_aim_direction()
	player._touch_fire_active = false
	player._touch_attack_held = false
	player._touch_fire_started_at = -1.0
	player._touch_fire_charge_started = false
	if released_weapon != "blaster":
		return false
	var ratio: float = player.mobile_blaster_release_ratio(held_for, player.mobile_blaster_charge_threshold, player._blaster_charge_time)
	if player._blaster_charge_active:
		ratio = maxf(ratio, player._blaster_charge_ratio)
	player._touch_fire_requests.append({
		"direction": direction_snapshot.normalized(),
		"charge_ratio": ratio,
		"expires": now + INPUT_BUFFER_SECONDS,
	})
	player._cancel_blaster_charge()
	return true


func cancel_touch_fire(reason: String = "") -> void:
	if str(_queued_command.get("type", "")) == "weapon" and bool(_queued_command.get("touch", false)):
		_queued_command.clear()
	if player._touch_fire_active and player._weapon_id == "longshot":
		player._cancel_longshot_attack()
	player._touch_fire_active = false
	player._touch_fire_started_at = -1.0
	player._touch_fire_charge_started = false
	player._touch_attack_held = false
	player._touch_fire_requests.clear()
	if player._blaster_charge_active:
		player._cancel_blaster_charge(reason)


func get_mobile_blaster_input_state() -> StringName:
	if player._weapon_id != "blaster" or not player._touch_fire_active:
		return &"aim"
	if not player._blaster_charge_active:
		return &"aim"
	return &"ready" if player._blaster_charge_ratio >= 1.0 else &"charging"


func trigger_touch_action(action: String) -> bool:
	if action == "defensive" and player._defensive_module_id == "static_shield":
		return request_module_command(action, true, true)
	if action in ["offensive", "defensive", "mobility"]:
		if _module_blocked(action):
			return request_module_command(action, true, true)
	player._touch_actions[action] = true
	return true


func begin_touch_action(action: String) -> bool:
	if (action == "offensive" and player._offensive_module_id in ["fulguro_punch", "javelin", "pelto_smash"]) or (action == "mobility" and player._mobility_module_id == "eclipse"):
		return request_module_command(action, true)
	return player.trigger_touch_action(action)


func end_touch_action(action: String, touch: bool = true) -> void:
	if str(_queued_command.get("type", "")) == "module" and str(_queued_command.get("action", "")) == action:
		_queued_command.released = true
		return
	if action == "mobility" and player._eclipse.aiming and player._eclipse.touch_owned == touch:
		player._eclipse.release(player)
	if action == "offensive" and player._offensive_module_id == "pelto_smash":
		player._release_pelto_aim()
	if action == "offensive" and player._offensive_module_id == "javelin":
		player._release_javelin_charge()
	if action == "offensive" and player._offensive_module_id == "fulguro_punch":
		player._release_fulguro_charge()


func cancel_touch_action(action: String) -> void:
	if str(_queued_command.get("type", "")) == "module" and str(_queued_command.get("action", "")) == action:
		_queued_command.clear()
		return
	if action == "mobility" and player._eclipse.aiming and player._eclipse.touch_owned:
		player._eclipse.cancel(player)
	if action == "offensive" and player._offensive_module_id == "pelto_smash" and player._pelto_aim_held:
		player._cancel_pelto_smash()
	if action == "offensive" and player._offensive_module_id == "javelin":
		player._cancel_javelin_charge()
	# Losing the finger is an interruption, not a release requesting a strike.
	# TouchControls calls this only for contacts it owns; keyboard casts remain
	# governed by the existing action state and interruption rules.
	if action == "offensive" and player._offensive_module_id == "fulguro_punch" and player.is_fulguro_charging():
		player._cancel_fulguro_attack()


func clear_touch_inputs() -> void:
	if bool(_queued_command.get("touch", false)):
		_queued_command.clear()
	if player._eclipse.aiming and player._eclipse.touch_owned:
		player._eclipse.cancel(player)
	if player._touch_fire_active and player._weapon_id == "longshot":
		player._cancel_longshot_attack()
	var touch_owned_charge := player._touch_fire_charge_started
	player._touch_move_vector = Vector2.ZERO
	player._touch_aim_vector = Vector2.ZERO
	player._touch_aim_active = false
	player._touch_actions.clear()
	player._attack_hold_last = false
	player._touch_fire_active = false
	player._touch_fire_started_at = -1.0
	player._touch_fire_charge_started = false
	player._touch_attack_held = false
	player._touch_fire_requests.clear()
	player._touch_attack_rearm_required = false
	# A hidden/inactive touch overlay must not cancel a charge started from the
	# desktop input path. It only owns a charge it started after a touch hold.
	if touch_owned_charge and player._blaster_charge_active:
		player._cancel_blaster_charge()


func set_gameplay_enabled(value: bool) -> void:
	if player._presentation_component != null:
		player._presentation_component.reset_module_gesture()
	if player._visual_rig != null:
		player._visual_rig.reset_presence()
	if not value and player.passive_state != null:
		player.passive_state.clear_triggers()
	if not value:
		if player._counter != null:
			player._counter.cancel(true)
		player._eclipse.cancel(player)
		player._clear_permutation()
		player._cancel_longshot_attack()
	player._gameplay_enabled = value
	if player.is_inside_tree() and player._uses_local_feedback():
		player.get_node("/root/GameSfx").reset_locomotion()
	if not value:
		player._static_pulse_token += 1
		player._reset_weapon_pose_to_locomotion(true)
		player.clear_touch_inputs()
		player._cancel_fulguro_attack()
		player._cancel_pelto_smash()
		player._cancel_pending_module_action()
		player._cancel_blaster_charge()
		player._cancel_shotgun_attack()
		player._cancel_axe_attack()
		player._reset_action_ownership()
		player.velocity = Vector3.ZERO
		if not player._round_warmup_active and not player.is_real_dead():
			player._play_player_animation(&"idle")
	else:
		if player._round_warmup_active:
			# The countdown can end before the 18 s source warmup clip. Release
			# the rig's full-body action lock before the first combat shot.
			player._play_player_animation(&"idle")
		player._round_warmup_active = false
		player._reset_weapon_pose_to_locomotion(true)
		player._update_player_animation()
	player._sync_bush_state()
	player._update_bush_presentation()


func is_gameplay_enabled() -> bool:
	return player._gameplay_enabled


func _consume_touch_action(action: String) -> bool:
	if not bool(player._touch_actions.get(action, false)):
		return false
	player._touch_actions[action] = false
	return true
