class_name TrainingBot
extends Node

## Lightweight local opponent used for manual combat/visibility testing.
## It is opt-in (F7), uses a readable wind-up telegraph, and deliberately
## applies raw damage only: status effects must still come from the player's
## weapons/modules or explicit diagnostics.

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
const DUEL_MEMORY_SECONDS := 4.0
const DUEL_ANGLE_INTERVAL := 1.25
const DUEL_RELOAD_REACTION := 0.35
const DUEL_DODGE_REACTION := 0.20
const DUEL_PRESS_SPEED := 3.0
const DUEL_FLANK_SPEED := 3.2
var training_stationary := false
var training_attack_interval := ATTACK_INTERVAL
var training_attack_damage := ATTACK_DAMAGE
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


func _ready() -> void:
	var owner_3d := get_parent() as Node3D
	if owner_3d != null:
		_spawn_position = owner_3d.global_position
	_build_telegraph()
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
	_charge_remaining = 0.0
	_charge_hit = false
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
	_charge_remaining = 0.0
	_charge_hit = false
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
		if bot_body.has_method("is_stunned") and bool(bot_body.call("is_stunned")):
			_windup_remaining = 0.0
			_windup_player = null
			_charge_remaining = 0.0
			_move_velocity = Vector3.ZERO
			_update_telegraph()
			return
		_update_survival_bot(bot_body, player, delta)
		return
	if bot_body.has_method("is_stunned") and bool(bot_body.call("is_stunned")):
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
	var pursuit_position := _last_observed_position if _has_last_observed_position else _spawn_position
	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
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
				_update_duel_movement(bot_body, pursuit_position, target_visible, delta)
			else:
				_update_patrol(bot_body, pursuit_position, delta)
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
		_begin_attack(player)
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
	if _charge_remaining > 0.0:
		_charge_remaining = maxf(0.0, _charge_remaining - delta)
		_move_velocity = (_charge_target - bot_body.global_position).normalized() * (18.0 if survival_role == "charger" else 14.0)
		_move_velocity.y = 0.0
		_move_bot(bot_body, delta)
		if not _charge_hit and bot_body.global_position.distance_to(player.global_position) < (2.0 if survival_role == "boss" else 1.35):
			player.call("take_damage", training_attack_damage, "survival_charge", "charge:%d" % _attack_serial)
			_charge_hit = true
		if bot_body.global_position.distance_to(_charge_target) < 0.8:
			_charge_remaining = 0.0
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
					player.call("take_damage", training_attack_damage, "survival_melee", "melee:%d" % _attack_serial)
			else:
				if survival_role == "boss":
					_spawn_attack_visual(player, "boss_spread:%d:center" % _attack_serial)
					_spawn_attack_visual(player, "boss_spread:%d:left" % _attack_serial, Vector3(-1.6, 0, 0))
					_spawn_attack_visual(player, "boss_spread:%d:right" % _attack_serial, Vector3(1.6, 0, 0))
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
	if _elapsed >= _next_attack_at and distance <= (2.1 if survival_role == "chaser" else 12.0) and _line_of_sight_clear(bot_body, player):
		_attack_serial += 1
		_charge_target = player.global_position
		_windup_player = player
		_windup_remaining = 0.85 if survival_role in ["charger", "boss"] else 0.45
		_update_telegraph()


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
	if target_visible:
		_has_angle_destination = false
		var toward := pursuit_position - bot_body.global_position
		toward.y = 0.0
		var distance := toward.length()
		if distance > 0.05:
			var direction := toward / distance
			var press_reload := _reload_observed_at >= 0.0 and _elapsed - _reload_observed_at >= DUEL_RELOAD_REACTION
			var minimum_range := 4.5 if press_reload else IDEAL_RANGE_MIN
			var maximum_range := 6.0 if press_reload else IDEAL_RANGE_MAX
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
		if _elapsed >= _next_angle_at or (_has_angle_destination and bot_body.global_position.distance_to(_angle_destination) < 0.65):
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
		desired_velocity = to_desired.normalized() * speed * slow_multiplier
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
			if not _duel_path_clear(bot_body, bot_body.global_position, candidate):
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
	var next_position := bot_body.global_position + _move_velocity * delta
	var world := bot_body.get_world_3d()
	if world != null and _move_velocity.length_squared() > 0.001:
		var query := PhysicsRayQueryParameters3D.create(bot_body.global_position + Vector3.UP * 0.72, next_position + Vector3.UP * 0.72)
		query.collision_mask = 1 | 8
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [bot_body.get_rid()]
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_blocked_time += delta
			if _avoid_direction == Vector3.ZERO or _blocked_time > 0.35:
				var side := Vector3(-_move_velocity.z, 0.0, _move_velocity.x).normalized()
				_avoid_direction = side if int(_elapsed * 2.0) % 2 == 0 else -side
			_blocked_time = 0.0
			var slide_velocity := _avoid_direction * maxf(MOVE_SPEED * 0.8, _move_velocity.length() * 0.65)
			next_position = bot_body.global_position + slide_velocity * delta
			_move_velocity = _move_velocity.move_toward(slide_velocity, MOVE_ACCELERATION * delta)
		else:
			_blocked_time = maxf(0.0, _blocked_time - delta * 0.5)
			_avoid_direction = Vector3.ZERO
	bot_body.global_position = next_position
	bot_body.global_position.x = clampf(bot_body.global_position.x, -27.0, 27.0)
	bot_body.global_position.z = clampf(bot_body.global_position.z, -27.0, 27.0)
	bot_body.global_position.y = 0.0


func _try_dodge(bot_body: Node3D, player: Node3D, target_visible: bool, duel_tactics: bool) -> void:
	if not player.has_method("is_attack_committed") or not bool(player.call("is_attack_committed")) or (duel_tactics and not target_visible):
		_attack_observed_at = -1.0
		return
	if _dodge_cooldown_remaining > 0.0:
		return
	if duel_tactics:
		if _attack_observed_at < 0.0:
			_attack_observed_at = _elapsed
		if _elapsed - _attack_observed_at < DUEL_DODGE_REACTION:
			return
	var away := bot_body.global_position - player.global_position
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


func _can_attack(bot_body: Node3D, player: Node3D) -> bool:
	if bot_body.global_position.distance_to(player.global_position) > ATTACK_RANGE:
		return false
	if player.has_method("is_visible_to") and not bool(player.call("is_visible_to", bot_body)):
		return false
	return _line_of_sight_clear(bot_body, player)


func _begin_attack(player: Node3D) -> void:
	_windup_player = player
	_windup_remaining = WINDUP_DURATION
	_telegraph_clock = 0.0
	_update_telegraph()


func _resolve_attack(bot_body: Node3D, player: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _can_attack(bot_body, player):
		_attack_player(player)


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
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	if bot_body == null or scene == null:
		return
	var impact_position := player.global_position + Vector3.UP * 0.92 + offset
	var shot_transform := Transform3D(Basis.IDENTITY, bot_body.global_position + Vector3.UP * 1.30)
	if bot_body.has_method("prepare_training_bot_shot"):
		shot_transform = bot_body.call("prepare_training_bot_shot", impact_position)
	var start_position := shot_transform.origin
	var tracer := Node3D.new()
	tracer.name = "TrainingBotProjectile"
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
			vfx.call("impact", hit.position, hit.normal, vfx.call("surface_for", hit.collider), 0.75, Color("#ffbf83"))


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
	var target_position := _charge_target if survival_role in ["charger", "boss"] and (survival_role == "charger" or _attack_serial % 2 == 1) else _windup_player.global_position
	var bot_position := bot_body.global_position if bot_body != null else Vector3.ZERO
	var flat_delta := target_position - bot_position
	flat_delta.y = 0.0
	var distance := maxf(flat_delta.length(), 0.05)
	var pulse := 1.0 + sin(_telegraph_clock * 18.0) * 0.12
	_telegraph_ring.global_position = bot_position + Vector3.UP * 0.08
	_telegraph_ring.scale = Vector3.ONE * pulse
	_telegraph_target.global_position = target_position + Vector3.UP * 0.11
	_telegraph_target.scale = Vector3.ONE * (0.92 + sin(_telegraph_clock * 16.0) * 0.10)
	_telegraph_beacon.global_position = target_position + Vector3.UP * (2.55 + sin(_telegraph_clock * 14.0) * 0.08)
	_telegraph_beacon.scale = Vector3.ONE * (0.92 + sin(_telegraph_clock * 18.0) * 0.13)
	_telegraph_line.global_position = bot_position + flat_delta * 0.5 + Vector3.UP * 0.10
	_telegraph_line.look_at(target_position + Vector3.UP * 0.10, Vector3.UP)
	_telegraph_line.scale = Vector3(1.0, 1.0, distance)
