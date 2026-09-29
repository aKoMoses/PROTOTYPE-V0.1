class_name TrainingBot
extends Node

const DUEL_EQUIPMENT := preload("res://scripts/duel_bot_equipment.gd")

## Lightweight local opponent used for manual combat/visibility testing.
## It is opt-in (F7), uses a readable wind-up telegraph, and deliberately
## applies raw damage only: status effects must still come from the player's
## weapons/modules or explicit diagnostics.

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
const PELTO_SMASH := preload("res://scripts/pelto_smash.gd")
const FULGURO_CHARGE_SOUND: AudioStream = preload("res://art/audio/blaster-charge-v2.wav")

const ATTACK_INTERVAL := 2.20
const ATTACK_DAMAGE := 35.0
const ATTACK_RANGE := 9.5
const WINDUP_DURATION := 0.55
const MOVE_RADIUS_X := 2.8
const MOVE_RADIUS_Z := 2.0
const MOVE_SPEED := 1.8
const PROJECTILE_TRAVEL_TIME := 0.16
const IDEAL_RANGE_MIN := 5.6
const IDEAL_RANGE_MAX := 8.4
const DODGE_DURATION := 0.34
const DODGE_COOLDOWN := 3.5
const DODGE_SPEED := 7.2
const MOVE_ACCELERATION := 7.0
const CHARGER_ATTACK_RANGE := 6.0
const BOSS_ATTACK_RANGE := 8.0
const SURVIVAL_ARENA_LIMIT := 21.0
const CHARGE_OBSTACLE_MARGIN := 0.7
const BOT_COLLISION_MARGIN := 0.04
const BOT_CONTACT_GAP := 0.12
const DUEL_MEMORY_SECONDS := 4.0
const DUEL_ANGLE_INTERVAL := 1.25
const DUEL_RELOAD_REACTION := 0.35
const DUEL_DODGE_REACTION := 0.20
const DUEL_PRESS_SPEED := 3.0
const DUEL_FLANK_SPEED := 3.2
var training_stationary := false
var training_attack_interval := ATTACK_INTERVAL
var training_attack_damage := ATTACK_DAMAGE
var survival_elite := ""
var boss_phase_two := false
var _double_charge_pending := false
var _shield_facing := Vector3.FORWARD
var survival_role := ""
var _charge_target := Vector3.ZERO
var _charge_remaining := 0.0
var _charge_hit := false

var enabled := false
var _elapsed := 0.0
var _next_attack_at := 1.0
var _attack_serial := 0
var _spawn_position := Vector3.ZERO
var _windup_remaining := 0.0
var _windup_player: Node3D
var _telegraph_ring: MeshInstance3D
var _telegraph_line: MeshInstance3D
var _telegraph_target: MeshInstance3D
var _telegraph_beacon: MeshInstance3D
var _telegraph_clock := 0.0
var _dodge_remaining := 0.0
var _dodge_cooldown_remaining := 0.0
var _dodge_direction := Vector3.ZERO
var _move_velocity := Vector3.ZERO
var _last_observed_position := Vector3.ZERO
var _has_last_observed_position := false
var _visual_aim_position := Vector3.ZERO
var _has_visual_aim_position := false
var _blocked_time := 0.0
var _avoid_direction := Vector3.ZERO
var _last_seen_at := -100.0
var _reload_observed_at := -1.0
var _attack_observed_at := -1.0
var _next_angle_at := 0.0
var _angle_destination := Vector3.ZERO
var _has_angle_destination := false
var _duel_equipment: Node
var _threat_serial := 0
var _threat_position := Vector3.ZERO
var _projectile_previous: Dictionary = {}
var _attack_mode := "ranged"
var _fulguro_direction := Vector3.FORWARD
var _fulguro_charge_ratio := 0.0
var _next_fulguro_ready_at := 0.0
var _pelto_direction := Vector3.FORWARD
var _next_pelto_ready_at := 0.0
var _fulguro_charge_audio: AudioStreamPlayer


func _ready() -> void:
	var owner_3d := get_parent() as Node3D
	if owner_3d != null:
		_spawn_position = owner_3d.global_position
	_duel_equipment = DUEL_EQUIPMENT.new()
	_duel_equipment.name = "DuelEquipment"
	add_child(_duel_equipment)
	_build_telegraph()
	_fulguro_charge_audio = AudioStreamPlayer.new()
	_fulguro_charge_audio.name = "FulguroChargeAudio"
	_fulguro_charge_audio.stream = FULGURO_CHARGE_SOUND
	_fulguro_charge_audio.volume_db = -12.0
	_fulguro_charge_audio.pitch_scale = 1.28
	add_child(_fulguro_charge_audio)
	set_physics_process(false)


func set_enabled(value: bool) -> void:
	enabled = value
	_elapsed = 0.0
	_next_attack_at = 1.0
	_attack_serial = 0
	_windup_remaining = 0.0
	_windup_player = null
	_dodge_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_dodge_direction = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_last_observed_position = Vector3.ZERO
	_has_last_observed_position = false
	_has_visual_aim_position = false
	_blocked_time = 0.0
	_avoid_direction = Vector3.ZERO
	_reset_duel_decisions()
	if _duel_equipment != null and survival_role == "":
		_duel_equipment.call("reset")
	_charge_remaining = 0.0
	_charge_hit = false
	_attack_mode = "ranged"
	_fulguro_direction = Vector3.FORWARD
	_fulguro_charge_ratio = 0.0
	_next_fulguro_ready_at = 0.0
	_pelto_direction = Vector3.FORWARD
	_next_pelto_ready_at = 0.0
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.stop()
	_update_telegraph()
	set_physics_process(enabled)
	var owner_3d := get_parent() as Node3D
	if owner_3d != null:
		owner_3d.set_meta("training_bot_enabled", enabled)


func set_spawn_position(value: Vector3) -> void:
	_spawn_position = value
	reset_clock()


func toggle() -> bool:
	set_enabled(not enabled)
	return enabled


func reset_clock() -> void:
	_elapsed = 0.0
	_next_attack_at = 1.0
	_attack_serial = 0
	_windup_remaining = 0.0
	_windup_player = null
	_dodge_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_dodge_direction = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_last_observed_position = Vector3.ZERO
	_has_last_observed_position = false
	_has_visual_aim_position = false
	_blocked_time = 0.0
	_avoid_direction = Vector3.ZERO
	_reset_duel_decisions()
	if _duel_equipment != null and survival_role == "":
		_duel_equipment.call("reset")
	_charge_remaining = 0.0
	_charge_hit = false
	_attack_mode = "ranged"
	_fulguro_direction = Vector3.FORWARD
	_fulguro_charge_ratio = 0.0
	_next_fulguro_ready_at = 0.0
	_pelto_direction = Vector3.FORWARD
	_next_pelto_ready_at = 0.0
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.stop()
	_update_telegraph()


func is_enabled() -> bool:
	return enabled


func is_telegraph_active() -> bool:
	return enabled and _windup_remaining > 0.0


func is_dodging() -> bool:
	return enabled and _dodge_remaining > 0.0


func get_dodge_cooldown_remaining() -> float:
	return maxf(0.0, _dodge_cooldown_remaining)


func _reset_duel_decisions() -> void:
	_last_seen_at = -100.0
	_reload_observed_at = -1.0
	_attack_observed_at = -1.0
	_next_angle_at = 0.0
	_has_angle_destination = false
	_threat_serial = 0
	_projectile_previous.clear()


func set_duel_profile(value: String) -> void:
	if _duel_equipment != null:
		_duel_equipment.call("set_profile", value)


func get_duel_profile() -> String:
	return str(_duel_equipment.get("profile")) if _duel_equipment != null else "blaster"


func get_duel_ammo() -> int:
	return int(_duel_equipment.get("ammo")) if _duel_equipment != null else 0


func is_duel_reloading() -> bool:
	return bool(_duel_equipment.call("is_reloading")) if _duel_equipment != null else false


func get_attack_phase() -> String:
	if not enabled:
		return "DISABLED"
	return "WINDUP" if _windup_remaining > 0.0 else "READY"


func get_visual_aim_point() -> Vector3:
	# Presentation remembers only genuinely observed target positions. It must
	# not read a hidden player's live transform while aiming between attacks.
	if _has_visual_aim_position:
		return _visual_aim_position + Vector3.UP * 0.92
	var bot_body := get_parent() as Node3D
	if bot_body != null:
		return bot_body.global_position - bot_body.global_basis.z * 4.0 + Vector3.UP * 0.92
	return Vector3.FORWARD * 4.0 + Vector3.UP * 0.92


func _physics_process(delta: float) -> void:
	if not enabled or delta <= 0.0:
		return
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	var player := scene.get_node_or_null("Player") as Node3D if scene != null else null
	if bot_body == null or player == null or not is_instance_valid(player):
		return
	if bot_body.has_method("is_real_dead") and bool(bot_body.call("is_real_dead")):
		_move_velocity = Vector3.ZERO
		_windup_remaining = 0.0
		_update_telegraph()
		return
	if player.has_method("is_real_dead") and bool(player.call("is_real_dead")):
		_move_velocity = Vector3.ZERO
		_windup_remaining = 0.0
		_update_telegraph()
		return
	if survival_role != "":
		if bot_body.has_method("is_action_locked") and bool(bot_body.call("is_action_locked")):
			_consider_buffered_dodge(bot_body, player)
			_windup_remaining = 0.0
			_windup_player = null
			_charge_remaining = 0.0
			_double_charge_pending = false
			_move_velocity = Vector3.ZERO
			_update_telegraph()
			return
		_update_survival_bot(bot_body, player, delta)
		return
	if bot_body.has_method("is_action_locked") and bool(bot_body.call("is_action_locked")):
		_consider_buffered_dodge(bot_body, player)
		_windup_remaining = 0.0
		_windup_player = null
		_move_velocity = Vector3.ZERO
		_update_telegraph()
		return
	_elapsed += delta
	var duel_tactics := bot_body.has_method("is_duel_mode") and bool(bot_body.call("is_duel_mode"))
	var target_visible := (not player.has_method("is_visible_to") or bool(player.call("is_visible_to", bot_body))) and _line_of_sight_clear(bot_body, player)
	if target_visible:
		_last_observed_position = player.global_position
		_has_last_observed_position = true
		_visual_aim_position = player.global_position
		_has_visual_aim_position = true
		_last_seen_at = _elapsed
	elif duel_tactics and _elapsed - _last_seen_at > DUEL_MEMORY_SECONDS:
		_has_last_observed_position = false
		_has_visual_aim_position = false
	if duel_tactics:
		_observe_duel_reload(player, target_visible)
		_duel_equipment.call("tick", delta, _elapsed, target_visible, _last_observed_position, bot_body, player, self)
	var pursuit_position := _last_observed_position if _has_last_observed_position else _spawn_position
	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	_try_interrupt_pelto_pull(bot_body, player)
	if training_stationary:
		_move_velocity = Vector3.ZERO
	elif _dodge_remaining > 0.0:
		_dodge_remaining = maxf(0.0, _dodge_remaining - delta)
		_move_velocity = _move_velocity.move_toward(_dodge_direction * DODGE_SPEED, MOVE_ACCELERATION * delta)
		_move_bot(bot_body, delta)
	else:
		_try_dodge(bot_body, player, target_visible, duel_tactics)
		if _dodge_remaining <= 0.0:
			if duel_tactics:
				if bool(_duel_equipment.call("is_dashing")):
					_duel_equipment.call("advance_dash", bot_body, self, delta)
				else:
					_update_duel_movement(bot_body, pursuit_position, target_visible, delta)
			else:
				_update_patrol(bot_body, pursuit_position, delta)
	if duel_tactics:
		return
	_telegraph_clock += delta
	if _windup_remaining > 0.0:
		_windup_remaining = maxf(0.0, _windup_remaining - delta)
		_update_telegraph()
		if _windup_remaining <= 0.0:
			_resolve_attack(bot_body, _windup_player)
			_windup_player = null
			_next_attack_at = _elapsed + (maxf(0.1, training_attack_interval - WINDUP_DURATION) if training_stationary else training_attack_interval)
		return
	if _elapsed < _next_attack_at:
		return
	if _can_attack(bot_body, player):
		_begin_attack(bot_body, player)
	else:
		# Recheck quickly when the player is behind cover instead of locking the
		# bot into a long empty cooldown.
		_next_attack_at = _elapsed + 0.35


func _update_survival_bot(bot_body: Node3D, player: Node3D, delta: float) -> void:
	_elapsed += delta
	_telegraph_clock += delta
	var toward := player.global_position - bot_body.global_position
	toward.y = 0.0
	var distance := toward.length()
	if survival_role == "boss" and not boss_phase_two and float(bot_body.call("get_health")) <= float(bot_body.get("combat_state").max_health) * 0.5:
		boss_phase_two = true
		training_attack_interval = 1.8
		bot_body.get_node("TargetHealthReadout").call("update_actor_identity", Color("#ff8056"), "BROYEUR · SURCHARGE")
	if survival_elite == "shield" and distance > 0.01:
		var angle := rotate_toward(atan2(_shield_facing.x, _shield_facing.z), atan2(toward.x, toward.z), delta * 1.6)
		_shield_facing = Vector3(sin(angle), 0.0, cos(angle))
		bot_body.set_meta("shield_facing", _shield_facing)
		var shield := bot_body.get_node_or_null("EliteShield") as Node3D
		if shield != null:
			shield.global_position = bot_body.global_position + _shield_facing * 1.1 + Vector3.UP
			shield.global_rotation.y = atan2(_shield_facing.x, _shield_facing.z)
	if _charge_remaining > 0.0:
		_charge_remaining = maxf(0.0, _charge_remaining - delta)
		_advance_charge(bot_body, delta)
		if not _charge_hit and bot_body.global_position.distance_to(player.global_position) < (2.0 if survival_role == "boss" else 1.35) and _line_of_sight_clear(bot_body, player):
			player.call("take_damage", training_attack_damage, "survival_charge", "charge:%d:%d" % [get_instance_id(), _attack_serial])
			_charge_hit = true
		if _charge_remaining <= 0.0:
			_next_attack_at = _elapsed + training_attack_interval
			if _double_charge_pending:
				_double_charge_pending = false
				_attack_serial += 1
				_charge_target = player.global_position
				_windup_player = player
				_windup_remaining = 0.75
				_update_telegraph()
		return
	if _windup_remaining > 0.0:
		_windup_remaining = maxf(0.0, _windup_remaining - delta)
		_update_telegraph()
		if _windup_remaining <= 0.0:
			if survival_role == "charger" or (survival_role == "boss" and _attack_serial % 2 == 1):
				_charge_remaining = 0.8
				_charge_hit = false
			elif survival_role == "chaser":
				if distance < 2.2 and _line_of_sight_clear(bot_body, player):
					player.call("take_damage", training_attack_damage, "survival_melee", "melee:%d:%d" % [get_instance_id(), _attack_serial])
			else:
				if survival_role == "boss" or survival_elite == "spread":
					_spawn_attack_visual(player, "boss_spread:%d:center" % _attack_serial)
					_spawn_attack_visual(player, "boss_spread:%d:left" % _attack_serial, Vector3(-1.6, 0, 0))
					_spawn_attack_visual(player, "boss_spread:%d:right" % _attack_serial, Vector3(1.6, 0, 0))
					if boss_phase_two:
						_spawn_attack_visual(player, "boss_spread:%d:far_left" % _attack_serial, Vector3(-3.2, 0, 0))
						_spawn_attack_visual(player, "boss_spread:%d:far_right" % _attack_serial, Vector3(3.2, 0, 0))
				else:
					_attack_player(player)
			_next_attack_at = _elapsed + training_attack_interval
			_update_telegraph()
		return
	var desired_speed := 0.0
	if survival_role == "chaser" or survival_role == "charger":
		desired_speed = 4.0 if survival_role == "chaser" else 2.4
	elif survival_role == "boss":
		desired_speed = 2.2 if distance > 7.0 else -1.0 if distance < 4.0 else 0.0
	else:
		desired_speed = 2.5 if distance > 9.0 else -2.2 if distance < 6.0 else 0.0
	if distance > 0.1:
		var slow := 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95) if bot_body.has_method("get_slow_percent") else 1.0
		_move_velocity = _move_velocity.move_toward(toward.normalized() * desired_speed * slow, MOVE_ACCELERATION * delta)
		_move_bot(bot_body, delta)
	var attack_range := 2.1 if survival_role == "chaser" else CHARGER_ATTACK_RANGE if survival_role == "charger" else BOSS_ATTACK_RANGE if survival_role == "boss" else 12.0
	if _elapsed >= _next_attack_at and distance <= attack_range and _line_of_sight_clear(bot_body, player):
		_attack_serial += 1
		_double_charge_pending = survival_elite == "double_charge"
		_charge_target = player.global_position
		_windup_player = player
		_windup_remaining = (0.65 if boss_phase_two else 0.85) if survival_role in ["charger", "boss"] else 0.6 if survival_elite == "spread" else 0.45
		_update_telegraph()


func _advance_charge(bot_body: Node3D, delta: float) -> void:
	if not _recover_bot_from_cover(bot_body):
		_charge_remaining = 0.0
		_move_velocity = Vector3.ZERO
		return
	var to_target := _charge_target - bot_body.global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= 0.01:
		_charge_remaining = 0.0
		_move_velocity = Vector3.ZERO
		return
	var direction := to_target / distance
	var step := minf(distance, (18.0 if survival_role == "charger" else 14.0) * delta)
	var previous_position := bot_body.global_position
	var safe_motion := _safe_bot_motion(bot_body, direction * (step + CHARGE_OBSTACLE_MARGIN))
	var next_position := previous_position + direction * minf(step, safe_motion.length())
	next_position.x = clampf(next_position.x, -SURVIVAL_ARENA_LIMIT, SURVIVAL_ARENA_LIMIT)
	next_position.z = clampf(next_position.z, -SURVIVAL_ARENA_LIMIT, SURVIVAL_ARENA_LIMIT)
	next_position.y = 0.0
	bot_body.global_position = next_position
	if next_position.distance_to(_charge_target) <= 0.01 or next_position.distance_to(previous_position) < step - 0.01:
		_charge_remaining = 0.0
		_move_velocity = Vector3.ZERO


func _observe_duel_reload(player: Node3D, target_visible: bool) -> void:
	var reloading := target_visible and player.has_method("get_weapon_id") and str(player.call("get_weapon_id")) == "shotgun" and player.has_method("is_shotgun_reloading") and bool(player.call("is_shotgun_reloading"))
	if reloading:
		if _reload_observed_at < 0.0:
			_reload_observed_at = _elapsed
	else:
		_reload_observed_at = -1.0


func _update_duel_movement(bot_body: Node3D, pursuit_position: Vector3, target_visible: bool, delta: float) -> void:
	var desired := pursuit_position
	var speed := MOVE_SPEED
	var shotgun := get_duel_profile() == "shotgun"
	var reloading := is_duel_reloading()
	if target_visible:
		_has_angle_destination = false
		var toward := pursuit_position - bot_body.global_position
		toward.y = 0.0
		var distance := toward.length()
		if distance > 0.05:
			var direction := toward / distance
			var press_reload := _reload_observed_at >= 0.0 and _elapsed - _reload_observed_at >= DUEL_RELOAD_REACTION
			var minimum_range := 6.0 if reloading else 1.8 if shotgun else 4.5 if press_reload else 7.0
			var maximum_range := 8.0 if reloading else 3.0 if shotgun else 6.0 if press_reload else 10.5
			if distance < minimum_range:
				desired = bot_body.global_position - direction * 2.2
			elif distance > maximum_range:
				desired = bot_body.global_position + direction * 2.0
			else:
				var side := Vector3(-direction.z, 0.0, direction.x)
				desired = bot_body.global_position + side * (1.5 if _attack_serial % 2 == 0 else -1.5)
			if press_reload:
				speed = DUEL_PRESS_SPEED
	elif _has_last_observed_position:
		if not _has_angle_destination or bot_body.global_position.distance_to(_angle_destination) < 0.65 or (_blocked_time > 0.6 and _elapsed >= _next_angle_at):
			_select_duel_angle(bot_body, pursuit_position)
			_next_angle_at = _elapsed + DUEL_ANGLE_INTERVAL
		if _has_angle_destination:
			desired = _angle_destination
			speed = DUEL_FLANK_SPEED
	else:
		_has_angle_destination = false
	var to_desired := desired - bot_body.global_position
	to_desired.y = 0.0
	var desired_velocity := Vector3.ZERO
	if to_desired.length_squared() > 0.16:
		var slow_multiplier := 1.0
		if bot_body.has_method("get_slow_percent"):
			slow_multiplier = 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95)
		desired_velocity = to_desired.normalized() * speed * slow_multiplier * float(_duel_equipment.call("get_speed_multiplier"))
	_move_velocity = _move_velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)
	_move_bot(bot_body, delta)


func _select_duel_angle(bot_body: Node3D, last_known_position: Vector3) -> void:
	_has_angle_destination = false
	var toward := last_known_position - bot_body.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.25:
		return
	var direction := toward.normalized()
	var side := Vector3(-direction.z, 0.0, direction.x)
	var best_score := INF
	for lateral_distance in [3.0, 6.0, 9.0, 11.0]:
		for side_sign in [-1.0, 1.0]:
			var candidate: Vector3 = bot_body.global_position + side * lateral_distance * side_sign + direction * 1.5
			if absf(candidate.x) > 26.0 or absf(candidate.z) > 26.0:
				continue
			var travel := candidate - bot_body.global_position
			if _safe_bot_motion(bot_body, travel).length_squared() < travel.length_squared() * 0.98:
				continue
			var shot_clear := _duel_path_clear(bot_body, candidate, last_known_position)
			var range_to_target: float = candidate.distance_to(last_known_position)
			var score: float = (0.0 if shot_clear else 20.0) + absf(range_to_target - 7.0) * 0.6 + lateral_distance * 0.1
			if score < best_score:
				best_score = score
				_angle_destination = candidate
				_has_angle_destination = true


func _duel_path_clear(bot_body: Node3D, origin: Vector3, destination: Vector3) -> bool:
	var world := bot_body.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.72, destination + Vector3.UP * 0.72)
	query.collision_mask = 1 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [bot_body.get_rid()]
	var scene := get_tree().current_scene if get_tree() != null else null
	var player := scene.get_node_or_null("Player") as CollisionObject3D if scene != null else null
	if player != null:
		query.exclude.append(player.get_rid())
	return world.direct_space_state.intersect_ray(query).is_empty()


func _update_patrol(bot_body: Node3D, pursuit_position: Vector3, delta: float) -> void:
	var to_player := pursuit_position - bot_body.global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var desired: Vector3
	if distance < IDEAL_RANGE_MIN and distance > 0.05:
		desired = bot_body.global_position - to_player.normalized() * 2.2
	elif distance > IDEAL_RANGE_MAX and distance > 0.05:
		desired = bot_body.global_position + to_player.normalized() * 2.0
	else:
		desired = _spawn_position + Vector3(
			sin(_elapsed * 0.72) * MOVE_RADIUS_X,
			0.0,
			cos(_elapsed * 0.53) * MOVE_RADIUS_Z
		)
	desired.x = clampf(desired.x, -27.0, 27.0)
	desired.z = clampf(desired.z, -27.0, 27.0)
	var to_desired := desired - bot_body.global_position
	to_desired.y = 0.0
	var desired_velocity := Vector3.ZERO
	if to_desired.length_squared() > 0.04:
		var slow_multiplier := 1.0
		if bot_body.has_method("get_slow_percent"):
			slow_multiplier = 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95)
		desired_velocity = to_desired.normalized() * MOVE_SPEED * slow_multiplier
	_move_velocity = _move_velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)
	_move_bot(bot_body, delta)


func _move_bot(bot_body: Node3D, delta: float) -> void:
	if _move_velocity.length_squared() <= 0.0001:
		_move_velocity = Vector3.ZERO
	if not _recover_bot_from_cover(bot_body):
		_move_velocity = Vector3.ZERO
		return
	var requested_motion := _move_velocity * delta
	var safe_motion := _safe_bot_motion(bot_body, requested_motion)
	bot_body.global_position += safe_motion
	if safe_motion.length_squared() + 0.000001 < requested_motion.length_squared():
		_blocked_time += delta
		if _avoid_direction == Vector3.ZERO:
			var side := Vector3(-_move_velocity.z, 0.0, _move_velocity.x).normalized()
			_avoid_direction = side if int(_elapsed * 2.0) % 2 == 0 else -side
		var slide_velocity := _avoid_direction * maxf(MOVE_SPEED * 0.8, _move_velocity.length() * 0.65)
		var slide_motion := slide_velocity * delta
		var safe_slide := _safe_bot_motion(bot_body, slide_motion)
		if safe_slide.length_squared() < slide_motion.length_squared() * 0.25:
			_avoid_direction = -_avoid_direction
			slide_velocity = -slide_velocity
			safe_slide = _safe_bot_motion(bot_body, slide_velocity * delta)
		bot_body.global_position += safe_slide
		_move_velocity = _move_velocity.move_toward(slide_velocity, MOVE_ACCELERATION * delta)
	else:
		_blocked_time = maxf(0.0, _blocked_time - delta * 0.5)
		_avoid_direction = Vector3.ZERO
	var arena_limit := SURVIVAL_ARENA_LIMIT if survival_role != "" else 27.0
	bot_body.global_position.x = clampf(bot_body.global_position.x, -arena_limit, arena_limit)
	bot_body.global_position.z = clampf(bot_body.global_position.z, -arena_limit, arena_limit)
	bot_body.global_position.y = 0.0


func _bot_shape_query(bot_body: Node3D) -> PhysicsShapeQueryParameters3D:
	var collision: CollisionShape3D
	for child in bot_body.get_children():
		if child is CollisionShape3D:
			collision = child as CollisionShape3D
			break
	if collision == null or collision.shape == null:
		return null
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = 1 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [bot_body.get_rid()]
	query.margin = BOT_COLLISION_MARGIN
	return query


func _safe_bot_motion(bot_body: Node3D, motion: Vector3) -> Vector3:
	var world := bot_body.get_world_3d()
	if world == null or motion.length_squared() <= 0.000001:
		return motion
	var query := _bot_shape_query(bot_body)
	if query == null:
		return Vector3.ZERO
	query.motion = motion
	var cast := world.direct_space_state.cast_motion(query)
	if cast.size() < 2:
		return Vector3.ZERO
	if cast[0] >= 1.0:
		return motion
	return motion.normalized() * maxf(0.0, motion.length() * cast[0] - BOT_CONTACT_GAP)


func _navigation_motion_is_clear(bot_body: Node3D, motion: Vector3) -> bool:
	var world := bot_body.get_world_3d()
	if world == null or motion.length_squared() <= 0.000001:
		return true
	var query := _bot_shape_query(bot_body)
	if query == null:
		return false
	query.motion = motion
	var travel := world.direct_space_state.cast_motion(query)
	return travel.is_empty() or travel[0] >= 0.98


func _recover_bot_from_cover(bot_body: Node3D) -> bool:
	var world := bot_body.get_world_3d()
	if world == null:
		return false
	var query := _bot_shape_query(bot_body)
	if query == null or world.direct_space_state.intersect_shape(query, 1).is_empty():
		return query != null
	var origin := bot_body.global_position
	var shape_offset := query.transform.origin - origin
	var arena_limit := SURVIVAL_ARENA_LIMIT if survival_role != "" else 27.0
	for radius in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
		for index in range(16):
			var angle := TAU * float(index) / 16.0
			var candidate: Vector3 = origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if absf(candidate.x) > arena_limit or absf(candidate.z) > arena_limit:
				continue
			query.transform.origin = candidate + shape_offset
			if world.direct_space_state.intersect_shape(query, 1).is_empty():
				bot_body.global_position = candidate
				_move_velocity = Vector3.ZERO
				_avoid_direction = Vector3.ZERO
				return true
	return false


func _try_dodge(bot_body: Node3D, player: Node3D, target_visible: bool, duel_tactics: bool) -> void:
	var threatened := _visible_player_threat(bot_body, player, target_visible) if duel_tactics else player.has_method("is_attack_committed") and bool(player.call("is_attack_committed"))
	if not threatened:
		_attack_observed_at = -1.0
		return
	if _dodge_cooldown_remaining > 0.0:
		return
	if duel_tactics:
		if _attack_observed_at < 0.0:
			_attack_observed_at = _elapsed
			_threat_serial += 1
			if _threat_serial % 4 == 0:
				_attack_observed_at = INF
		if _elapsed - _attack_observed_at < DUEL_DODGE_REACTION:
			return
	var away := bot_body.global_position - (_threat_position if duel_tactics else player.global_position)
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.RIGHT
	else:
		away = away.normalized()
	_dodge_direction = Vector3(-away.z, 0.0, away.x).normalized()
	if int(_attack_serial + int(_elapsed * 10.0)) % 2 == 0:
		_dodge_direction = -_dodge_direction
	_dodge_remaining = DODGE_DURATION
	_dodge_cooldown_remaining = DODGE_COOLDOWN
	_move_velocity = _dodge_direction * DODGE_SPEED


func _visible_player_threat(bot_body: Node3D, player: Node3D, target_visible: bool) -> bool:
	if target_visible and player.has_method("is_blaster_charging") and bool(player.call("is_blaster_charging")):
		_threat_position = player.global_position
		return true
	var latest: Dictionary = {}
	var threatened := false
	for projectile in get_tree().get_nodes_in_group("prototype0_gameplay_projectiles"):
		if not projectile is Node3D or not str(projectile.name) in ["BlasterProjectile", "ShotgunPellet"]:
			continue
		var id := projectile.get_instance_id()
		var position: Vector3 = projectile.global_position
		latest[id] = position
		if not _projectile_previous.has(id):
			continue
		var motion: Vector3 = position - _projectile_previous[id]
		var toward := bot_body.global_position + Vector3.UP * 0.9 - position
		if motion.length_squared() < 0.0001 or toward.length() > 8.0 or motion.normalized().dot(toward.normalized()) < 0.75:
			continue
		if _duel_path_clear(bot_body, bot_body.global_position, position):
			_threat_position = position
			threatened = true
	_projectile_previous = latest
	return threatened


func _can_attack(bot_body: Node3D, player: Node3D) -> bool:
	if bot_body.global_position.distance_to(player.global_position) > ATTACK_RANGE:
		return false
	if player.has_method("is_visible_to") and not bool(player.call("is_visible_to", bot_body)):
		return false
	return _line_of_sight_clear(bot_body, player)


func _begin_attack(bot_body: Node3D, player: Node3D) -> void:
	_windup_player = player
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]
	var pelto_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"]
	var to_player := player.global_position - bot_body.global_position
	to_player.y = 0.0
	var target_radius := FULGURO.hit_radius(player)
	var can_punch := _elapsed >= _next_fulguro_ready_at and to_player.length() <= float(definition.range_max) + target_radius
	var can_pelto := not can_punch and _elapsed >= _next_pelto_ready_at and to_player.length() <= float(pelto_definition.max_range) + target_radius
	_attack_mode = "fulguro" if can_punch else "pelto" if can_pelto else "ranged"
	if can_punch:
		_fulguro_direction = FULGURO.flat_direction(to_player)
		var required_reach := maxf(float(definition.range_min), to_player.length() - target_radius)
		_fulguro_charge_ratio = clampf(inverse_lerp(float(definition.range_min), float(definition.range_max), required_reach), 0.0, 1.0)
		_windup_remaining = lerpf(float(definition.charge_min), float(definition.charge_max), _fulguro_charge_ratio)
		_next_fulguro_ready_at = _elapsed + float(definition.cooldown)
		if _fulguro_charge_audio != null:
			_fulguro_charge_audio.play()
	elif can_pelto:
		_pelto_direction = PELTO_SMASH.flat_direction(to_player)
		_windup_remaining = float(pelto_definition.preparation)
		_next_pelto_ready_at = _elapsed + float(pelto_definition.cooldown)
	else:
		_windup_remaining = WINDUP_DURATION
	_telegraph_clock = 0.0
	_update_telegraph()


func _resolve_attack(bot_body: Node3D, player: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _attack_mode == "fulguro":
		_resolve_fulguro_attack(bot_body, player)
	elif _attack_mode == "pelto":
		_resolve_pelto_attack(bot_body)
	elif _can_attack(bot_body, player):
		_attack_player(player)
	_attack_mode = "ranged"
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.stop()


func _resolve_fulguro_attack(bot_body: Node3D, player: Node3D) -> void:
	if bot_body == null or player == null or not is_instance_valid(player):
		return
	_attack_serial += 1
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]
	var strike_range := lerpf(float(definition.range_min), float(definition.range_max), _fulguro_charge_ratio)
	var target := FULGURO.resolve_strike(
		bot_body as CollisionObject3D,
		[player],
		_fulguro_direction,
		lerpf(float(definition.damage_min), float(definition.damage_max), _fulguro_charge_ratio),
		lerpf(float(definition.wall_damage_min), float(definition.wall_damage_max), _fulguro_charge_ratio),
		float(definition.wall_stun),
		"training_bot",
		"training_bot:fulguro:%d" % _attack_serial,
		strike_range,
		float(definition.width)
	)
	var visual_target := target as Node3D
	_spawn_fulguro_strike_visual(bot_body, visual_target, strike_range)


func _spawn_fulguro_strike_visual(bot_body: Node3D, target: Node3D, strike_range: float) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	if bot_body.has_method("prepare_training_bot_shot"):
		bot_body.call("prepare_training_bot_shot", bot_body.global_position + _fulguro_direction * strike_range + Vector3.UP * 0.92)
	var trail := MeshInstance3D.new()
	trail.name = "BotFulguroPunchTrail"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]["width"]) * lerpf(0.62, 0.86, _fulguro_charge_ratio), lerpf(0.28, 0.44, _fulguro_charge_ratio), strike_range)
	trail.mesh = mesh
	trail.material_override = _fx_material(Color("#ffcf78"), 0.72, Color("#ff7a35"))
	scene.add_child(trail)
	trail.global_position = bot_body.global_position + _fulguro_direction * (strike_range * 0.5) + Vector3.UP * 0.92
	trail.global_basis = Basis.looking_at(_fulguro_direction, Vector3.UP)
	if scene.has_method("register_fx_node"):
		scene.call("register_fx_node", trail, "burst")
	var tween := trail.create_tween()
	tween.tween_property(trail, "scale", Vector3(0.55, 0.55, 1.08), float(COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]["active_window"]))
	tween.tween_callback(trail.queue_free)
	if target != null:
		var vfx := scene.get_node_or_null("VFXManager")
		if vfx != null:
			vfx.call("impact", target.global_position + Vector3.UP * 0.82, -_fulguro_direction, "robot", 1.05, Color("#ffcf78"))


func _resolve_pelto_attack(bot_body: Node3D) -> void:
	if bot_body == null or not is_instance_valid(bot_body) or (bot_body.has_method("is_real_dead") and bool(bot_body.call("is_real_dead"))):
		return
	_attack_serial += 1
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	if bot_body.has_method("prepare_training_bot_shot"):
		bot_body.call("prepare_training_bot_shot", bot_body.global_position + _pelto_direction * 1.4 + Vector3.UP * 0.12)
	var wave := PELTO_SMASH.new()
	wave.name = "BotPeltoSmashWave_%d" % _attack_serial
	scene.add_child(wave)
	wave.call("configure", bot_body, bot_body.global_position, _pelto_direction, "training_bot", "training_bot:pelto:%d" % _attack_serial)
	if scene.has_method("register_fx_node"):
		scene.call("register_fx_node", wave, "projectile")
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("impact", bot_body.global_position + Vector3.UP * 0.08, Vector3.UP, "environment", 1.1, Color("#c47b43"))


func _try_interrupt_pelto_pull(bot_body: Node3D, player: Node3D) -> void:
	if not bot_body.has_method("is_pelto_pulled") or not bool(bot_body.call("is_pelto_pulled")) or _dodge_cooldown_remaining > 0.0:
		return
	var away := bot_body.global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.RIGHT
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	bot_body.call("request_defensive_dodge", side)


func cancel_action() -> void:
	_windup_remaining = 0.0
	_windup_player = null
	_attack_mode = "ranged"
	_dodge_remaining = 0.0
	_move_velocity = Vector3.ZERO
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.stop()
	_update_telegraph()


func execute_buffered_dodge(direction: Vector3) -> bool:
	var bot_body := get_parent() as Node3D
	if not enabled or _dodge_cooldown_remaining > 0.0 or bot_body == null:
		return false
	if bot_body.has_method("is_action_locked") and bool(bot_body.call("is_action_locked")):
		return false
	_dodge_direction = FULGURO.flat_direction(direction)
	_dodge_remaining = DODGE_DURATION
	_dodge_cooldown_remaining = DODGE_COOLDOWN
	_move_velocity = _dodge_direction * DODGE_SPEED
	return true


func _consider_buffered_dodge(bot_body: Node3D, player: Node3D) -> void:
	if _dodge_cooldown_remaining > 0.0 or not bot_body.has_method("request_defensive_dodge") or not player.has_method("is_attack_committed"):
		return
	if not bool(player.call("is_attack_committed")):
		return
	var away := bot_body.global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.RIGHT
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	if int(_attack_serial + int(_elapsed * 10.0)) % 2 == 0:
		side = -side
	bot_body.call("request_defensive_dodge", side)


func _line_of_sight_clear(bot_body: Node3D, player: Node3D) -> bool:
	var world := bot_body.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(bot_body.global_position + Vector3.UP * 0.72, player.global_position + Vector3.UP * 0.72)
	query.collision_mask = 1 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [bot_body.get_rid(), player.get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


func _attack_player(player: Node3D) -> void:
	if not player.has_method("take_damage"):
		return
	_attack_serial += 1
	# Le dégât est résolu à l'arrivée du projectile : le flash, la secousse et
	# l'impact visuel restent ainsi synchronisés avec le tir réellement affiché.
	_spawn_attack_visual(player, "training_bot:%d" % _attack_serial)


func _spawn_attack_visual(player: Node3D, attack_id: String, offset: Vector3 = Vector3.ZERO) -> void:
	if survival_role != "":
		attack_id = "%d:%s" % [get_instance_id(), attack_id]
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	if bot_body == null or scene == null:
		return
	if survival_role != "" and offset != Vector3.ZERO:
		var toward := (player.global_position - bot_body.global_position).normalized()
		offset = Vector3(-toward.z, 0.0, toward.x).normalized() * offset.x
	var impact_position := player.global_position + Vector3.UP * 0.92 + offset
	var shot_transform := Transform3D(Basis.IDENTITY, bot_body.global_position + Vector3.UP * 1.30)
	if bot_body.has_method("prepare_training_bot_shot"):
		shot_transform = bot_body.call("prepare_training_bot_shot", impact_position)
	var start_position := shot_transform.origin
	var tracer := Node3D.new()
	tracer.name = "TrainingBotProjectile"
	tracer.process_mode = Node.PROCESS_MODE_PAUSABLE
	scene.add_child(tracer)
	if scene.has_method("register_fx_node"):
		scene.call("register_fx_node", tracer, "projectile")
	tracer.global_position = start_position
	var direction := (impact_position - start_position).normalized()
	tracer.basis = Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y) > 0.98 else Vector3.UP)
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("projectile_visual", tracer, "enemy")
		var socket := bot_body.find_child("Muzzle", true, false) as Node3D
		if socket != null:
			vfx.call("muzzle", socket, "enemy")
		else:
			vfx.call("burst", start_position, direction, Color("#ffcf87"), 4, 2.8, 0.10, 0.03, 30.0)
	var travel := tracer.create_tween()
	travel.tween_property(tracer, "global_position", impact_position, PROJECTILE_TRAVEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	travel.tween_callback(Callable(self, "_resolve_projectile").bind(player, scene, impact_position, attack_id, start_position))
	travel.tween_callback(tracer.queue_free)


func _resolve_projectile(player: Node3D, scene: Node, impact_position: Vector3, attack_id: String, start_position: Vector3 = Vector3.ZERO) -> void:
	var bot_body := get_parent() as Node3D
	var impact_confirmed := false
	if player != null and is_instance_valid(player) and bot_body != null:
		var current_target := player.global_position + Vector3.UP * 0.92
		var still_near := current_target.distance_to(impact_position) <= 1.35
		impact_confirmed = still_near and _line_of_sight_clear(bot_body, player)
		if impact_confirmed and player.has_method("take_damage"):
			player.call("take_damage", training_attack_damage, "training_bot", attack_id)
	if not is_instance_valid(scene):
		return
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx == null:
		return
	var normal := (start_position - impact_position).normalized()
	if impact_confirmed:
		vfx.call("impact", impact_position, normal, "robot", 1.0, Color("#ffbf83"))
	elif bot_body != null and bot_body.get_world_3d() != null:
		var query := PhysicsRayQueryParameters3D.create(start_position, impact_position)
		query.collision_mask = 1 | 8
		query.collide_with_areas = true
		query.exclude = [bot_body.get_rid()]
		var hit := bot_body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var surface: String = vfx.call("surface_for", hit.collider)
			vfx.call("impact", hit.position, hit.normal, surface, 0.75, Color("#ffbf83"))
			if surface == "shield" and hit.collider.name == "MagneticField":
				get_node("/root/GameSfx").play_event("magnetic_absorb")
			elif surface != "robot" and surface != "shield":
				get_node("/root/GameSfx").play_event("impact_decor")


func _fx_material(color: Color, alpha: float, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 0.8
	if alpha < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _build_telegraph() -> void:
	_telegraph_ring = MeshInstance3D.new()
	_telegraph_ring.name = "AttackTelegraph"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.77
	ring_mesh.outer_radius = 0.82
	ring_mesh.rings = 12
	ring_mesh.ring_segments = 28
	_telegraph_ring.mesh = ring_mesh
	_telegraph_ring.position.y = 0.08
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ffba58")
	material.emission_enabled = true
	material.emission = Color("#ff6b32")
	material.emission_energy_multiplier = 0.8
	_telegraph_ring.material_override = material
	_telegraph_ring.visible = false
	_add_telegraph_node(_telegraph_ring)

	# Secondary floor telegraph: a readable lane and destination marker. These
	# are visual-only and deliberately do not participate in physics or damage.
	_telegraph_line = MeshInstance3D.new()
	_telegraph_line.name = "AttackTelegraphLine"
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(0.065, 0.018, 1.0)
	_telegraph_line.mesh = line_mesh
	_telegraph_line.top_level = true
	_telegraph_line.position.y = 0.10
	_telegraph_line.material_override = _fx_material(Color("#ffb25c"), 1.0, Color("#ff4d2f"))
	_telegraph_line.visible = false
	_add_telegraph_node(_telegraph_line)

	_telegraph_target = MeshInstance3D.new()
	_telegraph_target.name = "AttackTelegraphTarget"
	var target_mesh := TorusMesh.new()
	target_mesh.inner_radius = 0.49
	target_mesh.outer_radius = 0.54
	target_mesh.rings = 10
	target_mesh.ring_segments = 24
	_telegraph_target.mesh = target_mesh
	_telegraph_target.top_level = true
	_telegraph_target.position.y = 0.11
	_telegraph_target.material_override = _fx_material(Color("#ffd17a"), 1.0, Color("#ff4b25"))
	_telegraph_target.visible = false
	_add_telegraph_node(_telegraph_target)

	_telegraph_beacon = MeshInstance3D.new()
	_telegraph_beacon.name = "AttackTelegraphBeacon"
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.04
	beacon_mesh.bottom_radius = 0.09
	beacon_mesh.height = 0.24
	beacon_mesh.radial_segments = 8
	_telegraph_beacon.mesh = beacon_mesh
	_telegraph_beacon.top_level = true
	_telegraph_beacon.material_override = _fx_material(Color("#ffe0a2"), 1.0, Color("#ff5a2d"))
	_telegraph_beacon.visible = false
	_add_telegraph_node(_telegraph_beacon)


func _add_telegraph_node(node: Node) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null:
		scene.add_child(node)
	else:
		add_child(node)


func _update_telegraph() -> void:
	if _telegraph_ring == null or _telegraph_line == null or _telegraph_target == null or _telegraph_beacon == null:
		return
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	var player := scene.get_node_or_null("Player") as Node3D if scene != null else null
	var visible_to_player := true
	if bot_body != null and player != null and bot_body.has_method("is_visible_to"):
		visible_to_player = bool(bot_body.call("is_visible_to", player))
	var active := enabled and _windup_remaining > 0.0 and visible_to_player and _windup_player != null and is_instance_valid(_windup_player)
	_telegraph_ring.visible = active
	_telegraph_line.visible = active
	_telegraph_target.visible = active
	_telegraph_beacon.visible = active
	if not active:
		return
	var bot_position := bot_body.global_position if bot_body != null else Vector3.ZERO
	var target_position := _charge_target if survival_role in ["charger", "boss"] and (survival_role == "charger" or _attack_serial % 2 == 1) else _windup_player.global_position
	if _attack_mode == "fulguro":
		var fulguro_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]
		var telegraph_range := lerpf(float(fulguro_definition.range_min), float(fulguro_definition.range_max), _fulguro_charge_ratio)
		target_position = bot_position + _fulguro_direction * telegraph_range
	elif _attack_mode == "pelto":
		var pelto_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"]
		target_position = bot_position + _pelto_direction * float(pelto_definition.max_range)
	var flat_delta := target_position - bot_position
	flat_delta.y = 0.0
	var distance := maxf(flat_delta.length(), 0.05)
	var pulse := 1.0 + sin(_telegraph_clock * 18.0) * 0.12
	_telegraph_ring.global_position = bot_position + Vector3.UP * 0.08
	_telegraph_ring.scale = Vector3.ONE * pulse
	_telegraph_target.global_position = target_position + Vector3.UP * 0.11
	var pelto_width_scale := float(COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"].width) / 0.54 if _attack_mode == "pelto" else 1.0
	_telegraph_target.scale = Vector3.ONE * (0.92 + sin(_telegraph_clock * 16.0) * 0.10) * pelto_width_scale
	_telegraph_beacon.global_position = target_position + Vector3.UP * (2.55 + sin(_telegraph_clock * 14.0) * 0.08)
	_telegraph_beacon.scale = Vector3.ONE * (0.92 + sin(_telegraph_clock * 18.0) * 0.13)
	_telegraph_line.global_position = bot_position + flat_delta * 0.5 + Vector3.UP * 0.10
	_telegraph_line.look_at(target_position + Vector3.UP * 0.10, Vector3.UP)
	var line_width_scale := float(COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"].width) / 0.065 if _attack_mode == "pelto" else 1.0
	_telegraph_line.scale = Vector3(line_width_scale, 1.0, distance)
