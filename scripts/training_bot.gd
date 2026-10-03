class_name TrainingBot
extends Node

const DUEL_EQUIPMENT := preload("res://scripts/duel_bot_equipment.gd")
const LIVE_PROJECTILE := preload("res://scripts/live_projectile.gd")
const MAGNETIC_WALL := preload("res://scripts/magnetic_wall.gd")
const ACTION_GATE := preload("res://scripts/action_gate.gd")
const AI_PROFILE := preload("res://scripts/bot_ai_profile.gd")
const BOT_NAVIGATION := preload("res://scripts/bot_navigation.gd")
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const BUSH_STATE := preload("res://scripts/bush_state.gd")

## Shared bot controller. Duel mode runs three explicit stages: perception,
## tactical decision and command execution. Navigation and threat avoidance are
## shared by duel, training and the cheaper survival role AI.

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
const PELTO_SMASH := preload("res://scripts/pelto_smash.gd")
const FULGURO_CHARGE_SOUND: AudioStream = preload("res://art/audio/combat-sfx/fulguro-charge.wav")

const ATTACK_INTERVAL := 2.20
const ATTACK_DAMAGE := 35.0
const ATTACK_RANGE := 9.5
const WINDUP_DURATION := 0.55
const MOVE_RADIUS_X := 2.8
const MOVE_RADIUS_Z := 2.0
const MOVE_SPEED := 1.8
const PROJECTILE_SPEED := 48.0
const PROJECTILE_MAX_RANGE := 14.0
const IDEAL_RANGE_MIN := 5.6
const IDEAL_RANGE_MAX := 8.4
const DODGE_DURATION := 0.34
const DODGE_COOLDOWN := 3.5
const DODGE_SPEED := 7.2
const MOVE_ACCELERATION := 7.0
const CHARGER_ATTACK_RANGE := 6.0
const BOSS_ATTACK_RANGE := 8.0
var survival_arena_center := Vector3.ZERO
var duel_arena_limit := 27.0
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
const REPAIR_SEEK_HEALTH_RATIO := 0.62
const REPAIR_STOP_HEALTH_RATIO := 0.88
const REPAIR_SEARCH_INTERVAL := 0.40
const REPAIR_MOVE_SPEED := 3.4
const REPAIR_STUCK_TIMEOUT := 1.35
const OBSERVATION_SAMPLE_INTERVAL := 0.05
const PROGRESS_SAMPLE_INTERVAL := 0.45
const CROWD_AVOID_RADIUS := 1.65
const SURVIVAL_ACTION_ID := "survival_attack"
const BUSH_MEMORY_SECONDS := 8.0
const BUSH_ENTRY_OBSERVATION_WINDOW := 0.35
const BUSH_CONCEAL_MAX_SECONDS := 6.0
const BUSH_AMBUSH_MAX_SECONDS := 4.0
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
var _hazard_observed_at := -1.0
var _hazard_threat_id := 0
var _attack_mode := "ranged"
var _fulguro_direction := Vector3.FORWARD
var _fulguro_charge_ratio := 0.0
var _next_fulguro_ready_at := 0.0
var _pelto_direction := Vector3.FORWARD
var _next_pelto_ready_at := 0.0
var _fulguro_charge_audio: AudioStreamPlayer
var _repair_target: Node3D
var _next_repair_search_at := 0.0
var _repair_stuck_time := 0.0
var _repair_retry_after: Dictionary = {}
var difficulty_profile := AI_PROFILE.DEFAULT_PROFILE
var diagnostics_enabled := false
var _tuning: Dictionary = AI_PROFILE.values(AI_PROFILE.DEFAULT_PROFILE)
var _perception: Dictionary = {}
var _observation_samples: Array[Dictionary] = []
var _next_observation_sample_at := 0.0
var _visible_since := -1.0
var _observed_velocity := Vector3.ZERO
var _previous_reacted_position := Vector3.ZERO
var _previous_reacted_at := -1.0
var _current_intent := "search"
var _intent_reason := "initialisation"
var _intent_score := 0.0
var _intent_locked_until := 0.0
var _next_tactical_decision_at := 0.0
var _tactical_destination := Vector3.ZERO
var _has_tactical_destination := false
var _strafe_sign := 1.0
var _next_strafe_flip_at := 0.0
var _progress_anchor := Vector3.ZERO
var _progress_anchor_at := 0.0
var _diagnostic_label: Label3D
var _action_gate = ACTION_GATE.new()
var _attack_action_token := 0
var _navigation = BOT_NAVIGATION.new()
var _personality: Dictionary = {}
var _projectile_threat: Dictionary = {}
var _last_threat_scan_at := -1.0
var _search_index := 0
var _search_goal := Vector3.ZERO
var _next_search_goal_at := 0.0
var _survival_search_goal := Vector3.INF
var _survival_search_seeded := false
var _last_destination_at := 0.0
var _repair_waiting := false
var _control_repair_target: Node3D
var _suspected_bush: Node3D
var _suspected_bush_entry := Vector3.ZERO
var _suspected_bush_at := -100.0
var _last_visible_bush: Node3D
var _last_raw_visible_position := Vector3.ZERO
var _last_raw_visible_velocity := Vector3.ZERO
var _last_raw_visible_at := -100.0
var _was_raw_visible := false
var _bush_search_index := 0
var _bush_search_goal := Vector3.INF
var _next_bush_search_goal_at := 0.0
var _tactical_bush: Node3D
var _bush_plan_started_at := -100.0
var _bush_settled_at := -1.0
var _bush_retry_after := 0.0
var _holding_bush_fire := false


func _ready() -> void:
	var owner_3d := get_parent() as Node3D
	if owner_3d != null:
		_spawn_position = owner_3d.global_position
		_progress_anchor = owner_3d.global_position
	_duel_equipment = DUEL_EQUIPMENT.new()
	_duel_equipment.name = "DuelEquipment"
	_duel_equipment.call("set_action_gate", _action_gate)
	add_child(_duel_equipment)
	_build_telegraph()
	_fulguro_charge_audio = AudioStreamPlayer.new()
	_fulguro_charge_audio.name = "FulguroChargeAudio"
	_fulguro_charge_audio.stream = FULGURO_CHARGE_SOUND
	_fulguro_charge_audio.volume_db = -3.0
	_fulguro_charge_audio.pitch_scale = 1.0
	add_child(_fulguro_charge_audio)
	set_physics_process(false)


func set_enabled(value: bool) -> void:
	_action_gate.reset()
	_attack_action_token = 0
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
	_clear_repair_target()
	_next_repair_search_at = 0.0
	_repair_retry_after.clear()
	_reset_tactical_state()
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
	_action_gate.reset()
	_attack_action_token = 0
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
	_clear_repair_target()
	_next_repair_search_at = 0.0
	_repair_retry_after.clear()
	_reset_tactical_state()
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
	_hazard_observed_at = -1.0
	_hazard_threat_id = 0


func _reset_tactical_state() -> void:
	_navigation.invalidate()
	_suspected_bush = null
	_last_visible_bush = null
	_suspected_bush_at = -100.0
	_last_raw_visible_at = -100.0
	_last_raw_visible_velocity = Vector3.ZERO
	_was_raw_visible = false
	_bush_search_index = 0
	_bush_search_goal = Vector3.INF
	_next_bush_search_goal_at = 0.0
	_tactical_bush = null
	_bush_plan_started_at = -100.0
	_bush_settled_at = -1.0
	_bush_retry_after = 0.0
	_holding_bush_fire = false
	_projectile_threat.clear()
	_last_threat_scan_at = -1.0
	_search_index = int(get_instance_id() % 8)
	_next_search_goal_at = 0.0
	_survival_search_goal = Vector3.INF
	_survival_search_seeded = false
	_last_destination_at = 0.0
	_perception.clear()
	_observation_samples.clear()
	_next_observation_sample_at = 0.0
	_visible_since = -1.0
	_observed_velocity = Vector3.ZERO
	_previous_reacted_position = Vector3.ZERO
	_previous_reacted_at = -1.0
	_current_intent = "search"
	_intent_reason = "aucune cible perçue"
	_intent_score = 0.0
	_intent_locked_until = 0.0
	_next_tactical_decision_at = 0.0
	_has_tactical_destination = false
	_strafe_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0
	_next_strafe_flip_at = 0.0
	_progress_anchor_at = 0.0
	var body := get_parent() as Node3D
	_progress_anchor = body.global_position if body != null else Vector3.ZERO
	_personality = body.get_meta("bot_personality", {}).duplicate() if body != null else {}
	_update_diagnostic_label()


func set_difficulty_profile(value: String) -> void:
	difficulty_profile = AI_PROFILE.sanitize(value)
	_tuning = AI_PROFILE.values(difficulty_profile)
	_next_tactical_decision_at = 0.0


func get_difficulty_profile() -> String:
	return difficulty_profile


func set_duel_loadout(value: Dictionary) -> void:
	if _duel_equipment != null and _duel_equipment.has_method("set_loadout"):
		_duel_equipment.call("set_loadout", value)


func get_duel_loadout() -> Dictionary:
	return _duel_equipment.call("get_loadout") if _duel_equipment != null and _duel_equipment.has_method("get_loadout") else {"weapon": get_duel_profile()}


func set_diagnostics_enabled(value: bool) -> void:
	diagnostics_enabled = value
	if value and _diagnostic_label == null:
		_diagnostic_label = Label3D.new()
		_diagnostic_label.name = "BotAIDiagnostic"
		_diagnostic_label.position = Vector3(0.0, 2.65, 0.0)
		_diagnostic_label.font_size = 22
		_diagnostic_label.outline_size = 5
		_diagnostic_label.modulate = Color("#c7f7ff")
		_diagnostic_label.no_depth_test = true
		add_child(_diagnostic_label)
	if _diagnostic_label != null:
		_diagnostic_label.visible = value
	_update_diagnostic_label()


func get_diagnostic_snapshot() -> Dictionary:
	return {
		"difficulty": difficulty_profile,
		"intent": _current_intent,
		"reason": _intent_reason,
		"target_known": _has_last_observed_position,
		"target_visible": bool(_perception.get("visible", false)),
		"target_position": _last_observed_position,
		"target_age": float(_perception.get("memory_age", INF)),
		"destination": _tactical_destination if _has_tactical_destination else Vector3.INF,
		"module_reason": str(_duel_equipment.get("last_module_reason")) if _duel_equipment != null else "",
		"build": str(get_parent().get_meta("bot_build_name", "")),
		"projectile_threat": not _projectile_threat.is_empty(),
		"threat_time": float(_projectile_threat.get("time", INF)),
		"repair_waiting": _repair_waiting,
		"suspected_bush": str(_suspected_bush.name) if _has_suspected_bush() else "",
		"bush_entry": _suspected_bush_entry if _has_suspected_bush() else Vector3.INF,
		"bush_search_position": _bush_search_goal,
		"tactical_bush": str(_tactical_bush.name) if is_instance_valid(_tactical_bush) else "",
		"holding_fire": _holding_bush_fire,
		"navigation": _navigation.get_debug_state(),
	}


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
	if _duel_equipment != null:
		var melee_phase: String = _duel_equipment.call("get_mekatana_phase")
		if not melee_phase.is_empty():
			return melee_phase.to_upper()
	return "WINDUP" if _windup_remaining > 0.0 else "READY"


func get_visual_aim_point() -> Vector3:
	# Presentation remembers only genuinely observed target positions. It must
	# not read a hidden player's live transform while aiming between attacks.
	if _duel_equipment != null:
		var locked_direction: Vector3 = _duel_equipment.call("get_mekatana_direction")
		var melee_body := get_parent() as Node3D
		if melee_body != null and locked_direction.length_squared() > 0.001:
			return melee_body.global_position + locked_direction * 3.0 + Vector3.UP * 0.92
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
		cancel_action()
		_move_velocity = Vector3.ZERO
		return
	if player.has_method("is_real_dead") and bool(player.call("is_real_dead")):
		cancel_action()
		_move_velocity = Vector3.ZERO
		return
	if survival_role != "":
		if bot_body.has_method("is_action_locked") and bool(bot_body.call("is_action_locked")):
			_action_gate.reset()
			_attack_action_token = 0
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
		if _duel_equipment != null and survival_role == "":
			_duel_equipment.call("cancel_action", "interrompu par un effet de statut")
		_attack_action_token = 0
		_windup_remaining = 0.0
		_windup_player = null
		_move_velocity = Vector3.ZERO
		_update_telegraph()
		return
	_elapsed += delta
	var duel_tactics := bot_body.has_method("is_duel_mode") and bool(bot_body.call("is_duel_mode"))
	var target_visible := (not player.has_method("is_visible_to") or bool(player.call("is_visible_to", bot_body))) and _line_of_sight_clear(bot_body, player)
	_observe_bush_knowledge(bot_body, player, target_visible)
	var reacted_visible := target_visible
	if duel_tactics:
		_update_duel_perception(bot_body, player, target_visible)
		reacted_visible = bool(_perception.get("visible", false))
	elif target_visible:
		_last_observed_position = player.global_position
		_has_last_observed_position = true
		_visual_aim_position = player.global_position
		_has_visual_aim_position = true
		_last_seen_at = _elapsed
	_sense_projectile_threat(bot_body)
	var seeking_repair := duel_tactics and not training_stationary and _update_repair_target(bot_body, player)
	if duel_tactics:
		_observe_duel_reload(player, reacted_visible)
		_update_duel_decision(bot_body, player)
		if seeking_repair:
			_force_intent("seek_heal", "anticiper le retour du kit" if _repair_waiting else "rejoindre un soin par un trajet praticable")
			_tactical_destination = _repair_target.global_position
			_has_tactical_destination = true
		_perception["intent"] = _current_intent
		_perception["destination"] = _tactical_destination if _has_tactical_destination else bot_body.global_position
		_perception["projectile_threat"] = not _projectile_threat.is_empty()
		_perception["threat_time"] = float(_projectile_threat.get("time", INF))
		_perception["threat_direction"] = Vector3(_projectile_threat.get("velocity", Vector3.ZERO)).normalized()
		_perception["dodge_direction"] = _choose_dodge_direction(bot_body, Vector3(_projectile_threat.get("velocity", _last_observed_position - bot_body.global_position))) if not _projectile_threat.is_empty() or bool(_perception.get("target_charging", false)) else Vector3.ZERO
		_holding_bush_fire = _should_hold_bush_fire(bot_body)
		_perception["holding_fire"] = _holding_bush_fire
		_perception.erase("arena_control_target")
		var arena_controls := get_tree().current_scene.get_node_or_null("ArenaHazards")
		if arena_controls != null and arena_controls.has_method("get_bot_mirror_target") and str(_duel_equipment.get("profile")) != "mekatana":
			var mirror_target: Node3D = arena_controls.call("get_bot_mirror_target", bot_body, _last_observed_position if _has_last_observed_position else Vector3.INF, difficulty_profile)
			if mirror_target != null:
				_perception["arena_control_target"] = mirror_target
		if _attack_action_token != 0:
			_advance_shared_attack_windup(bot_body, delta)
		else:
			_duel_equipment.call("tick", delta, _elapsed, reacted_visible and not _holding_bush_fire, _last_observed_position, bot_body, player, self, _perception, _tuning)
		if bool(_duel_equipment.call("is_action_locked")):
			_move_velocity = Vector3.ZERO
			_dodge_remaining = 0.0
			_update_diagnostic_label()
			return
	var pursuit_position := _last_observed_position if _has_last_observed_position else _spawn_position
	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	_try_interrupt_pelto_pull(bot_body, player)
	if duel_tactics and bool(_duel_equipment.call("owns_mekatana_movement")):
		# The shared melee controller has already advanced the swept dash. Do
		# not add patrol, separation or dodge velocity to that committed motion.
		_move_velocity = Vector3.ZERO
		_dodge_remaining = 0.0
	elif training_stationary:
		_move_velocity = Vector3.ZERO
	elif duel_tactics and bool(_duel_equipment.call("is_dashing")):
		# A committed mobility cast owns movement until its swept path completes.
		_dodge_remaining = 0.0
		_move_velocity = Vector3.ZERO
		_duel_equipment.call("advance_dash", bot_body, self, delta)
	elif duel_tactics and _update_hazard_avoidance(bot_body, delta):
		pass
	elif _dodge_remaining > 0.0:
		_dodge_remaining = maxf(0.0, _dodge_remaining - delta)
		_move_velocity = _move_velocity.move_toward(_dodge_direction * DODGE_SPEED, MOVE_ACCELERATION * delta)
		_move_bot(bot_body, delta)
	else:
		_try_dodge(bot_body, player, reacted_visible, duel_tactics)
		if _dodge_remaining <= 0.0:
			if seeking_repair:
				if not _advance_repair_seek(bot_body, delta):
					_update_duel_movement(bot_body, pursuit_position, reacted_visible, delta)
			elif duel_tactics:
				_update_duel_movement(bot_body, pursuit_position, reacted_visible, delta)
			else:
				_update_patrol(bot_body, pursuit_position, delta)
	if duel_tactics:
		_update_diagnostic_label()
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


func _advance_shared_attack_windup(bot_body: Node3D, delta: float) -> void:
	if _attack_action_token == 0 or _windup_remaining <= 0.0:
		return
	_windup_remaining = maxf(0.0, _windup_remaining - delta)
	_update_telegraph()
	if _windup_remaining > 0.0:
		return
	_resolve_attack(bot_body, _windup_player)
	_windup_player = null
	_next_attack_at = _elapsed + (maxf(0.1, training_attack_interval - WINDUP_DURATION) if training_stationary else training_attack_interval)


func _observe_bush_knowledge(_bot_body: Node3D, player: Node3D, raw_visible: bool) -> void:
	# A visible entrance is information; a hidden transform is not. Keep this
	# separate from the delayed combat samples so losing vision between two
	# frames still records which patch was entered, never the current occupant.
	if raw_visible:
		var position := player.global_position
		if _was_raw_visible and _elapsed > _last_raw_visible_at + 0.0001:
			_last_raw_visible_velocity = ((position - _last_raw_visible_position) / (_elapsed - _last_raw_visible_at)).limit_length(10.0)
		else:
			_last_raw_visible_velocity = Vector3.ZERO
		_last_raw_visible_position = position
		_last_raw_visible_at = _elapsed
		_last_visible_bush = BUSH_STATE.find_bush(player)
		_clear_bush_suspicion()
	elif _was_raw_visible and _elapsed - _last_raw_visible_at <= BUSH_ENTRY_OBSERVATION_WINDOW:
		var entered_bush := _last_visible_bush if is_instance_valid(_last_visible_bush) else _infer_bush_entry()
		if entered_bush != null:
			_suspected_bush = entered_bush
			_suspected_bush_entry = _last_raw_visible_position
			_suspected_bush_at = _elapsed
			_bush_search_index = 0
			_bush_search_goal = Vector3.INF
			_next_bush_search_goal_at = 0.0
			_has_angle_destination = false
			_has_tactical_destination = false
			_next_tactical_decision_at = 0.0
			_observed_velocity = Vector3.ZERO
	_was_raw_visible = raw_visible
	if _suspected_bush != null and not _has_suspected_bush():
		_clear_bush_suspicion()


func _infer_bush_entry() -> Node3D:
	var best: Node3D
	var nearest_edge := INF
	for node in get_tree().get_nodes_in_group("bush_placeholder"):
		var bush := node as Node3D
		if bush == null or not is_instance_valid(bush):
			continue
		var toward := BUSH_STATE.center(bush) - _last_raw_visible_position
		toward.y = 0.0
		var edge_distance := maxf(0.0, toward.length() - BUSH_STATE.radius(bush))
		# A stationary actor beside grass may have gone behind a wall instead.
		# Infer an entrance only very near the border and moving into the patch.
		var moving_in := _last_raw_visible_velocity.dot(toward.normalized()) > 0.2
		if edge_distance > 0.45 or (not moving_in and not BUSH_STATE.contains(bush, _last_raw_visible_position)):
			continue
		if edge_distance < nearest_edge:
			nearest_edge = edge_distance
			best = bush
	return best


func _has_suspected_bush() -> bool:
	return is_instance_valid(_suspected_bush) and _elapsed - _suspected_bush_at <= BUSH_MEMORY_SECONDS


func _clear_bush_suspicion() -> void:
	_suspected_bush = null
	_bush_search_goal = Vector3.INF
	_next_bush_search_goal_at = 0.0


func get_suspected_bush() -> Node3D:
	return _suspected_bush if _has_suspected_bush() else null


func _select_bush_search_destination(bot_body: Node3D) -> Vector3:
	if not _has_suspected_bush():
		return _select_search_destination(bot_body)
	if _bush_search_goal.is_finite() and _elapsed < _next_bush_search_goal_at and bot_body.global_position.distance_to(_bush_search_goal) > 0.45:
		return _bush_search_goal
	var center := BUSH_STATE.center(_suspected_bush)
	var entrance := _suspected_bush_entry - center
	entrance.y = 0.0
	if entrance.length_squared() < 0.01:
		entrance = Vector3.RIGHT
	entrance = entrance.normalized()
	var radius := BUSH_STATE.radius(_suspected_bush)
	var limit := SURVIVAL_ARENA_LIMIT if survival_role != "" else duel_arena_limit
	# Check the entry, then the interior and different sides. Every point is
	# derived from map geometry and the last sighting, independent of the foe.
	for _attempt in range(6):
		var index := _bush_search_index % 6
		_bush_search_index += 1
		var offset := entrance * radius * 0.55 if index == 0 else Vector3.ZERO if index == 1 else entrance.rotated(Vector3.UP, float(index - 1) * TAU / 5.0) * radius * 0.50
		var point := center + offset
		point.y = 0.0
		if not BUSH_STATE.contains(_suspected_bush, point) or not _navigation.is_destination_clear(bot_body, point, limit):
			continue
		if _navigation.route_distance(bot_body, point, _elapsed, limit) == INF:
			continue
		_bush_search_goal = point
		_next_bush_search_goal_at = _elapsed + 2.2
		return point
	_clear_bush_suspicion()
	return _select_search_destination(bot_body)


func _update_duel_perception(bot_body: Node3D, player: Node3D, raw_visible: bool) -> void:
	var reaction_delay := float(_tuning.get("reaction_delay", 0.22))
	if raw_visible:
		if _visible_since < 0.0:
			_visible_since = _elapsed
		if _elapsed >= _next_observation_sample_at:
			_observation_samples.append({
				"time": _elapsed, "position": player.global_position,
				"reloading": player.has_method("is_shotgun_reloading") and bool(player.call("is_shotgun_reloading")),
				"counter_guard": player.has_method("is_counter_guarding") and bool(player.call("is_counter_guarding")),
				"charging": player.has_method("is_blaster_charging") and bool(player.call("is_blaster_charging")),
				"weapon": str(player.call("get_weapon_id")) if player.has_method("get_weapon_id") else "unknown",
				"aim_direction": player.get("aim_direction") if player.get("aim_direction") is Vector3 else Vector3.ZERO,
				"health": float(player.call("get_health")) / maxf(1.0, float(player.call("get_max_health"))) if player.has_method("get_health") and player.has_method("get_max_health") else 1.0,
			})
			_next_observation_sample_at = _elapsed + OBSERVATION_SAMPLE_INTERVAL
			while _observation_samples.size() > 16:
				_observation_samples.pop_front()
	else:
		_visible_since = -1.0
		_observation_samples.clear()
	var reacted_visible := raw_visible and _visible_since >= 0.0 and _elapsed - _visible_since >= reaction_delay
	var reacted_sample: Dictionary = {}
	while not _observation_samples.is_empty() and float(_observation_samples[0].get("time", _elapsed)) <= _elapsed - reaction_delay:
		reacted_sample = _observation_samples.pop_front()
	if reacted_visible and not reacted_sample.is_empty():
		var reacted_position: Vector3 = reacted_sample.get("position", _last_observed_position)
		var reacted_at := float(reacted_sample.get("time", _elapsed))
		if _previous_reacted_at >= 0.0 and reacted_at > _previous_reacted_at + 0.001:
			var measured := (reacted_position - _previous_reacted_position) / (reacted_at - _previous_reacted_at)
			measured.y = 0.0
			# A running average avoids perfect knowledge of a sudden direction change.
			_observed_velocity = _observed_velocity.lerp(measured.limit_length(10.0), 0.65)
		_previous_reacted_position = reacted_position
		_previous_reacted_at = reacted_at
		_last_observed_position = reacted_position
		_has_last_observed_position = true
		_visual_aim_position = reacted_position
		_has_visual_aim_position = true
		_last_seen_at = _elapsed
	elif not raw_visible and _elapsed - _last_seen_at > DUEL_MEMORY_SECONDS:
		_has_last_observed_position = false
		_has_visual_aim_position = false
		_observed_velocity = Vector3.ZERO
	var memory_age := maxf(0.0, _elapsed - _last_seen_at) if _has_last_observed_position else INF
	var distance := bot_body.global_position.distance_to(_last_observed_position) if _has_last_observed_position else INF
	var bot_health_fraction := 1.0
	if bot_body.has_method("get_health") and bot_body.has_method("get_max_health"):
		bot_health_fraction = float(bot_body.call("get_health")) / maxf(1.0, float(bot_body.call("get_max_health")))
	var target_health_fraction := float(_perception.get("target_health_fraction", 1.0))
	if not reacted_sample.is_empty():
		target_health_fraction = float(reacted_sample.get("health", 1.0))
	var target_reloading := bool(reacted_sample.get("reloading", _perception.get("target_reloading", false)))
	var target_charging := bool(reacted_sample.get("charging", _perception.get("target_charging", false)))
	var target_weapon := str(reacted_sample.get("weapon", _perception.get("target_weapon", "unknown")))
	var target_aim: Vector3 = reacted_sample.get("aim_direction", _perception.get("target_aim_direction", Vector3.ZERO))
	var toward_bot := bot_body.global_position - _last_observed_position
	toward_bot.y = 0.0
	var aimed_at_bot := target_aim.length_squared() < 0.01 or target_aim.normalized().dot(toward_bot.normalized()) > 0.82
	_perception = {
		"visible": reacted_visible,
		"raw_visible": raw_visible,
		"known": _has_last_observed_position,
		"position": _last_observed_position,
		"velocity": _observed_velocity,
		"memory_age": memory_age,
		"distance": distance,
		"line_of_fire": reacted_visible and _weapon_line_of_fire_clear(bot_body, player, _last_observed_position),
		"target_reloading": reacted_visible and target_reloading,
		"target_charging": reacted_visible and target_charging,
		"target_counter_guard": reacted_visible and bool(reacted_sample.get("counter_guard", _perception.get("target_counter_guard", false))),
		"target_weapon": target_weapon if reacted_visible else "unknown",
		"target_aim_direction": target_aim,
		"target_aiming_at_bot": aimed_at_bot,
		"target_health_fraction": target_health_fraction,
		"bot_health_fraction": bot_health_fraction,
		"bot_reloading": is_duel_reloading(),
	}


func _weapon_line_of_fire_clear(bot_body: Node3D, player: Node3D, target_position: Vector3) -> bool:
	var world := bot_body.get_world_3d()
	if world == null:
		return true
	var origin := bot_body.global_position + Vector3.UP * 0.90
	if bot_body.has_method("get_training_bot_muzzle_transform"):
		origin = (bot_body.call("get_training_bot_muzzle_transform") as Transform3D).origin
	var query := PhysicsRayQueryParameters3D.create(origin, target_position + Vector3.UP * 0.90)
	query.collision_mask = 1 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = MAGNETIC_WALL.owned_exclusions(self, [bot_body.get_rid(), player.get_rid()])
	return world.direct_space_state.intersect_ray(query).is_empty()


func _update_duel_decision(bot_body: Node3D, player: Node3D) -> void:
	if _elapsed < _next_tactical_decision_at:
		return
	var interval := float(_tuning.get("decision_interval", 0.23))
	var stagger := float(get_instance_id() % 5) * 0.008
	_next_tactical_decision_at = _elapsed + interval + stagger
	if get_repair_target() != null:
		return
	var known := bool(_perception.get("known", false))
	var visible := bool(_perception.get("visible", false))
	var distance := float(_perception.get("distance", INF))
	var health := float(_perception.get("bot_health_fraction", 1.0))
	var target_health := float(_perception.get("target_health_fraction", 1.0))
	var aggression := _behavior_value("aggression", 0.62)
	var caution := _behavior_value("caution", 0.58)
	var shotgun := get_duel_profile() in ["shotgun", "mekatana"]
	var ideal := _ideal_combat_range()
	var ideal_min := ideal - (0.9 if shotgun else 1.8)
	var ideal_max := ideal + (1.1 if shotgun else 1.8)
	var scores := {
		"search": 1.0,
		"engage": 0.0,
		"maintain": 0.0,
		"pressure": 0.0,
		"flank": 0.0,
		"break_line": 0.0,
		"retreat": 0.0,
		"control_repair": 0.0,
		"search_bush": 0.0,
		"hide_bush": 0.0,
		"ambush_bush": 0.0,
	}
	if not known:
		scores["search"] = 10.0
	elif not visible:
		scores["search"] = 4.0 + minf(3.0, float(_perception.get("memory_age", 0.0)))
		scores["flank"] = 7.0 * float(_tuning.get("position_quality", 0.68)) + float(_personality.get("flank_bias", 0.0))
	else:
		scores["maintain"] = 4.0 - minf(4.0, absf(distance - (ideal_min + ideal_max) * 0.5))
		scores["engage"] = maxf(0.0, distance - ideal_max) * (0.8 + aggression)
		scores["retreat"] = maxf(0.0, ideal_min - distance) * (1.0 + caution)
		scores["flank"] = (3.6 if not bool(_perception.get("line_of_fire", false)) else 1.4) * float(_tuning.get("position_quality", 0.68))
		if bool(_perception.get("target_reloading", false)) and _reload_observed_at >= 0.0:
			scores["pressure"] = 7.0 + aggression * 2.0
		if target_health < 0.28:
			scores["pressure"] = maxf(float(scores["pressure"]), 5.0 + aggression * 3.0)
		if bool(_perception.get("bot_reloading", false)):
			scores["break_line"] = 6.2 + caution * 2.0
		if bool(_perception.get("target_charging", false)) and bool(_perception.get("target_aiming_at_bot", true)):
			scores["break_line"] = maxf(float(scores["break_line"]), 5.8 + caution * 2.0)
		if not _projectile_threat.is_empty():
			scores["break_line"] = maxf(float(scores["break_line"]), 6.0 + caution * 2.0)
		if health < 0.38:
			scores["break_line"] = maxf(float(scores["break_line"]), (0.52 - health) * 13.0 + caution * 4.0)
			scores["retreat"] = maxf(float(scores["retreat"]), (0.45 - health) * 9.0 + caution * 3.0)
	if not visible and _has_suspected_bush():
		scores["search_bush"] = 10.0 + aggression
	var keeping_bush_plan := _current_intent in ["hide_bush", "ambush_bush"] and is_instance_valid(_tactical_bush)
	if keeping_bush_plan:
		var maximum := BUSH_CONCEAL_MAX_SECONDS if _current_intent == "hide_bush" else BUSH_AMBUSH_MAX_SECONDS
		var target_close := visible and distance < (3.2 if shotgun else 5.5)
		if _elapsed - _bush_plan_started_at >= maximum or (target_close and _bush_settled_at >= 0.0 and _elapsed - _bush_settled_at >= 0.65):
			keeping_bush_plan = false
			_bush_retry_after = _elapsed + 5.0
			_tactical_bush = null
			_has_tactical_destination = false
		else:
			scores[_current_intent] = 11.0
	var bush_plan: Dictionary = {}
	if not keeping_bush_plan and known and _elapsed >= _bush_retry_after and not _has_suspected_bush():
		var needs_cover := health < 0.48 or bool(_perception.get("bot_reloading", false)) or bool(_perception.get("target_charging", false)) or not _projectile_threat.is_empty()
		var wants_ambush := visible and not needs_cover and distance > (4.8 if shotgun else 7.0) and target_health > 0.25
		if needs_cover or wants_ambush:
			bush_plan = _select_shelter_bush(bot_body, wants_ambush)
			if not bush_plan.is_empty():
				if needs_cover:
					scores["hide_bush"] = 8.5 + caution + (1.0 - health) * 2.0
				else:
					scores["ambush_bush"] = 5.4 + caution
	_control_repair_target = _select_control_repair(bot_body, health, target_health)
	if _control_repair_target != null:
		scores["control_repair"] = 4.5 + (1.0 - health) * 3.0 + (1.0 - target_health) * 2.0
	if keeping_bush_plan:
		# Backing into grass increases weapon-range error. Do not let that error
		# immediately vote for engage and undo a retreat before reveal expires.
		var other_best := 0.0
		for intent_value in scores.keys():
			if str(intent_value) != _current_intent:
				other_best = maxf(other_best, float(scores[intent_value]))
		scores[_current_intent] = maxf(11.0, other_best + 1.0)
	var best_intent := "search"
	var best_score := -INF
	for intent_value in scores.keys():
		var score := float(scores[intent_value])
		if score > best_score:
			best_score = score
			best_intent = str(intent_value)
	var reason := _intent_reason_for(best_intent, distance, health)
	var previous_intent := _current_intent
	_commit_intent(best_intent, best_score, float(scores.get(_current_intent, 0.0)), reason, health < 0.22)
	if _current_intent in ["hide_bush", "ambush_bush"] and not keeping_bush_plan and not bush_plan.is_empty():
		_tactical_bush = bush_plan.bush
		_tactical_destination = bush_plan.position
		_has_tactical_destination = true
		_bush_plan_started_at = _elapsed
		_bush_settled_at = -1.0
		_last_destination_at = _elapsed
	elif not _current_intent in ["hide_bush", "ambush_bush"]:
		_tactical_bush = null
		_bush_settled_at = -1.0
	var destination_reached := _has_tactical_destination and bot_body.global_position.distance_to(_tactical_destination) < 0.70
	if previous_intent != _current_intent or not _has_tactical_destination or destination_reached or _blocked_time > 0.65 or _elapsed - _last_destination_at > 1.4:
		_select_tactical_destination(bot_body, player)
	_perception["intent"] = _current_intent


func _intent_reason_for(intent: String, distance: float, health: float) -> String:
	match intent:
		"engage": return "hors de la portée favorable"
		"maintain": return "distance d'arme favorable"
		"pressure": return "fenêtre de vulnérabilité adverse"
		"flank": return "ligne de tir bloquée"
		"break_line": return "exposition trop dangereuse"
		"retreat": return "menace proche (PV %.0f%%)" % (health * 100.0)
		"control_repair": return "prendre le soin avant l'adversaire"
		"search_bush": return "entrée observée : inspecter l'herbe sans position exacte"
		"hide_bush": return "couper le combat et reprendre la dissimulation"
		"ambush_bush": return "attendre une portée favorable dans l'herbe"
		_: return "recherche de la dernière position connue" if distance < INF else "aucune cible perçue"


func _commit_intent(next_intent: String, next_score: float, current_score: float, reason: String, urgent: bool = false) -> void:
	if next_intent != _current_intent and not urgent and _elapsed < _intent_locked_until and next_score < current_score + float(_tuning.get("intent_switch_margin", 0.62)):
		return
	if next_intent != _current_intent:
		_current_intent = next_intent
		_intent_locked_until = _elapsed + float(_tuning.get("intent_minimum_duration", 1.10))
		_has_tactical_destination = false
	_intent_score = next_score
	_intent_reason = reason


func _force_intent(next_intent: String, reason: String) -> void:
	if _current_intent != next_intent:
		_current_intent = next_intent
		_has_tactical_destination = false
	_intent_reason = reason
	_intent_locked_until = _elapsed + float(_tuning.get("intent_minimum_duration", 1.10))


func _behavior_value(key: String, fallback: float) -> float:
	return lerpf(float(_tuning.get(key, fallback)), float(_personality.get(key, _tuning.get(key, fallback))), 0.5)


func _ideal_combat_range() -> float:
	if get_duel_profile() == "longshot":
		# The maximum bonus remains attainable inside the shared 22 m vision.
		return clampf(float(_personality.get("ideal_range", 17.5)), 16.0, 18.5)
	if get_duel_profile() == "mekatana":
		var landing_gap := clampf(float(_personality.get("ideal_range", 2.0)) - 1.0, 0.6, 1.4)
		return float(_duel_equipment.call("get_mekatana_dash_distance")) + landing_gap
	var shotgun := get_duel_profile() == "shotgun"
	var ideal := float(_personality.get("ideal_range", 2.6 if shotgun else 8.0))
	if not shotgun and str(_perception.get("target_weapon", "")) == "shotgun":
		ideal = maxf(ideal, 8.5)
	var minimum := 3.8 if str(get_duel_loadout().get("offensive", "")) == "fulguro_punch" else 6.0
	return clampf(ideal, 1.8, 4.0) if shotgun else clampf(ideal, minimum, 10.8)


func _select_control_repair(bot_body: Node3D, health: float, target_health: float) -> Node3D:
	if not _has_last_observed_position or health >= 0.96 or health < 0.40 or target_health > 0.65:
		return null
	var best: Node3D
	var best_score := INF
	for node in get_tree().get_nodes_in_group("repair_kits"):
		var kit := node as Node3D
		if kit == null or not bool(kit.call("is_available")):
			continue
		var distance := bot_body.global_position.distance_to(kit.global_position)
		var rival_distance := _last_observed_position.distance_to(kit.global_position)
		if distance > 10.0 or distance > rival_distance + 2.0:
			continue
		var route: float = _navigation.route_distance(bot_body, kit.global_position, _elapsed, duel_arena_limit)
		if route < best_score and route <= rival_distance + 3.5:
			best_score = route
			best = kit
	return best


func _select_tactical_destination(bot_body: Node3D, player: Node3D) -> void:
	_last_destination_at = _elapsed
	if _current_intent == "search_bush" and _has_suspected_bush():
		_tactical_destination = _select_bush_search_destination(bot_body)
		_has_tactical_destination = true
		return
	if _current_intent in ["hide_bush", "ambush_bush"] and is_instance_valid(_tactical_bush):
		# Retain the chosen interior point; an ambush must settle instead of
		# oscillating between the two edges of a patch at each decision tick.
		_has_tactical_destination = true
		return
	if _current_intent == "control_repair" and _control_repair_target != null and is_instance_valid(_control_repair_target):
		_tactical_destination = _control_repair_target.global_position
		_has_tactical_destination = true
		return
	if not _has_last_observed_position:
		_tactical_destination = _select_search_destination(bot_body)
		_has_tactical_destination = true
		return
	if _current_intent == "flank" or (not bool(_perception.get("visible", false)) and _current_intent == "search"):
		_select_duel_angle(bot_body, _last_observed_position)
		if _has_angle_destination:
			_tactical_destination = _angle_destination
			_has_tactical_destination = true
			return
	var toward := _last_observed_position - bot_body.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		toward = Vector3.FORWARD
	var direction := toward.normalized()
	var side := Vector3(-direction.z, 0.0, direction.x)
	if _elapsed >= _next_strafe_flip_at:
		_strafe_sign = -_strafe_sign
		_next_strafe_flip_at = _elapsed + float(_personality.get("strafe_period", 1.5)) * randf_range(0.75, 1.35)
	var candidate_count := int(_tuning.get("candidate_count", 6))
	var candidates: Array[Vector3] = []
	for index in range(candidate_count):
		var sign_value := _strafe_sign if index % 2 == 0 else -_strafe_sign
		var scale_value := 1.0 + float(index / 2) * 0.45
		var offset := side * sign_value * 2.2 * scale_value
		match _current_intent:
			"engage", "pressure": offset += direction * (2.8 + scale_value * 0.45)
			"retreat": offset -= direction * (3.0 + scale_value * 0.55)
			"break_line": offset = side * sign_value * (3.6 + scale_value) - direction * 1.2
			"search": offset += direction * 2.0
			_: offset += direction * clampf((toward.length() - _ideal_combat_range()) * 0.50, -2.5, 2.5)
		var candidate := bot_body.global_position + offset
		candidate.x = clampf(candidate.x, -duel_arena_limit + 1.0, duel_arena_limit - 1.0)
		candidate.z = clampf(candidate.z, -duel_arena_limit + 1.0, duel_arena_limit - 1.0)
		candidate.y = 0.0
		candidates.append(candidate)
	# Evaluate cover corners across the arena as well as nearby strafing points.
	# A useful corner can require a detour, so a blocked direct ray is not a veto.
	if _current_intent in ["break_line", "retreat", "flank", "engage", "pressure"]:
		for corner in _arena_cover_positions(bot_body):
			candidates.append(corner)
	var ranked: Array[Dictionary] = []
	for candidate in candidates:
		var travel := candidate - bot_body.global_position
		if travel.length_squared() < 0.36 or not _navigation.is_destination_clear(bot_body, candidate, duel_arena_limit):
			continue
		var range_to_target := candidate.distance_to(_last_observed_position)
		var ideal := _ideal_combat_range()
		if _current_intent == "pressure" and get_duel_profile() != "mekatana":
			ideal *= 0.68
		elif _current_intent in ["retreat", "break_line"]:
			ideal += 2.5
		var exposed := _duel_path_clear(bot_body, candidate, _last_observed_position)
		var exposure_cost := 0.0
		if _current_intent in ["retreat", "break_line"]:
			exposure_cost = 8.0 if exposed else -3.0
		else:
			exposure_cost = 0.0 if exposed else 4.5
		var edge_cost := maxf(0.0, maxf(absf(candidate.x), absf(candidate.z)) - 23.0) * 0.8
		var lateral_preference := -0.25 if travel.dot(side) * _strafe_sign > 0.0 else 0.25
		var score := absf(range_to_target - ideal) * 0.8 + travel.length() * 0.16 + exposure_cost + edge_cost + lateral_preference + _candidate_crowd_penalty(bot_body, candidate)
		ranked.append({"position": candidate, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
	_has_tactical_destination = false
	var best_score := INF
	for index in range(mini(4, ranked.size())):
		var candidate: Vector3 = ranked[index].position
		var route: float = _navigation.route_distance(bot_body, candidate, _elapsed, duel_arena_limit)
		if route == INF:
			continue
		var score := float(ranked[index].score) + maxf(0.0, route - bot_body.global_position.distance_to(candidate)) * 0.35
		if score < best_score:
			best_score = score
			_tactical_destination = candidate
			_has_tactical_destination = true
	if not _has_tactical_destination:
		_tactical_destination = _last_observed_position
		_has_tactical_destination = _navigation.is_destination_clear(bot_body, _tactical_destination, duel_arena_limit)


func _select_shelter_bush(bot_body: Node3D, for_ambush: bool) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var current_distance := bot_body.global_position.distance_to(_last_observed_position)
	for node in get_tree().get_nodes_in_group("bush_placeholder"):
		var bush := node as Node3D
		if bush == null or not is_instance_valid(bush) or bush == _last_visible_bush or bush == get_suspected_bush():
			continue
		var center := BUSH_STATE.center(bush)
		var travel := center.distance_to(bot_body.global_position)
		if travel > 9.0:
			continue
		var target_distance := center.distance_to(_last_observed_position)
		if target_distance < (2.5 if for_ambush else 4.5):
			continue
		if not for_ambush and target_distance < current_distance - 1.0:
			continue
		var ideal := _ideal_combat_range() if for_ambush else current_distance + 2.5
		var score := travel * 0.55 + absf(target_distance - ideal) * (0.65 if for_ambush else 0.25)
		candidates.append({"bush": bush, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
	var best: Dictionary = {}
	var best_score := INF
	for index in range(mini(5, candidates.size())):
		var bush: Node3D = candidates[index].bush
		var center := BUSH_STATE.center(bush)
		var away := center - _last_observed_position
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.01 else Vector3.RIGHT
		# Move fully inside the footprint so the edge does not flicker between
		# hidden and visible. Alternate points handle grass beside solid cover.
		var offsets := [away * BUSH_STATE.radius(bush) * 0.38, Vector3.ZERO, away.rotated(Vector3.UP, PI * 0.5) * BUSH_STATE.radius(bush) * 0.32, away.rotated(Vector3.UP, -PI * 0.5) * BUSH_STATE.radius(bush) * 0.32]
		for offset_value in offsets:
			var point := center + Vector3(offset_value)
			point.y = 0.0
			if not BUSH_STATE.contains(bush, point) or not _navigation.is_destination_clear(bot_body, point, duel_arena_limit):
				continue
			var route: float = _navigation.route_distance(bot_body, point, _elapsed, duel_arena_limit)
			if route == INF or route > 13.0:
				continue
			var score := float(candidates[index].score) + route * 0.32 + _candidate_crowd_penalty(bot_body, point)
			if score < best_score:
				best_score = score
				best = {"bush": bush, "position": point}
	return best


func _should_hold_bush_fire(bot_body: Node3D) -> bool:
	if not _current_intent in ["hide_bush", "ambush_bush"] or not is_instance_valid(_tactical_bush):
		return false
	var inside := BUSH_STATE.contains(_tactical_bush, bot_body.global_position)
	if inside and _bush_settled_at < 0.0:
		_bush_settled_at = _elapsed
	elif not inside:
		_bush_settled_at = -1.0
	# Shooting while approaching or during the combat reveal would reset that
	# reveal forever. Give the timer a chance to expire before taking a shot.
	var revealed := bot_body.has_method("is_revealed") and bool(bot_body.call("is_revealed"))
	if not inside or revealed or _bush_settled_at < 0.0 or _elapsed - _bush_settled_at < 0.65:
		return true
	var visible := bool(_perception.get("visible", false))
	var distance := float(_perception.get("distance", INF))
	if visible and distance < (3.2 if get_duel_profile() == "shotgun" else 5.5):
		_bush_retry_after = _elapsed + 5.0
		return false
	return _current_intent == "hide_bush" or not visible or distance > _ideal_combat_range() + 1.0


func _arena_cover_positions(bot_body: Node3D) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var scene := get_tree().current_scene
	if scene == null:
		return positions
	for child in scene.get_children():
		if not child is StaticBody3D or (child.collision_layer & 1) == 0 or child == bot_body:
			continue
		for shape_node in child.get_children():
			if not shape_node is CollisionShape3D or not shape_node.shape is BoxShape3D:
				continue
			var half: Vector3 = shape_node.shape.size * 0.5
			if half.x > 20.0 or half.z > 20.0:
				continue
			for x_sign in [-1.0, 1.0]:
				for z_sign in [-1.0, 1.0]:
					var point: Vector3 = shape_node.global_transform * Vector3((half.x + 1.25) * x_sign, 0.0, (half.z + 1.25) * z_sign)
					point.y = 0.0
					if absf(point.x) < duel_arena_limit - 1.0 and absf(point.z) < duel_arena_limit - 1.0:
						positions.append(point)
	return positions


func _select_search_destination(bot_body: Node3D) -> Vector3:
	if _elapsed < float(_tuning.get("reaction_delay", 0.22)) + 0.15:
		return bot_body.global_position
	if _elapsed < _next_search_goal_at and bot_body.global_position.distance_to(_search_goal) > 1.2:
		return _search_goal
	# Sweep lanes, health pads and map quadrants without consulting a hidden target.
	var sectors := [Vector3(-13, 0, -18), Vector3(0, 0, -20.8), Vector3(13, 0, -18), Vector3(21, 0, 0), Vector3(13, 0, 18), Vector3(0, 0, 20.8), Vector3(-13, 0, 18), Vector3(-21, 0, 0), Vector3(0, 0, 0)]
	var limit := SURVIVAL_ARENA_LIMIT if survival_role != "" else duel_arena_limit
	for index in range(sectors.size()):
		sectors[index] += survival_arena_center
	# Grass is also worth inspecting when no entrance was witnessed. Sweep all
	# map patches in the same schedule, never selecting the occupied one by fiat.
	for node in get_tree().get_nodes_in_group("bush_placeholder"):
		var bush := node as Node3D
		if bush != null and is_instance_valid(bush):
			var point := BUSH_STATE.center(bush)
			if absf(point.x - survival_arena_center.x) < limit - 1.0 and absf(point.z - survival_arena_center.z) < limit - 1.0:
				sectors.append(point)
	for _attempt in range(sectors.size()):
		_search_index = (_search_index + 1) % sectors.size()
		var candidate: Vector3 = sectors[_search_index]
		candidate.x = clampf(candidate.x, survival_arena_center.x - limit + 1.0, survival_arena_center.x + limit - 1.0)
		candidate.z = clampf(candidate.z, survival_arena_center.z - limit + 1.0, survival_arena_center.z + limit - 1.0)
		if bot_body.global_position.distance_to(candidate) <= 1.2:
			continue
		if _navigation.is_destination_clear(bot_body, candidate, limit) and _navigation.route_distance(bot_body, candidate, _elapsed, limit) < INF:
			_search_goal = candidate
			_next_search_goal_at = _elapsed + 10.0
			return candidate
	return bot_body.global_position


func _candidate_crowd_penalty(bot_body: Node3D, candidate: Vector3) -> float:
	var penalty := 0.0
	for other_value in get_tree().get_nodes_in_group("prototype0_combat_bots"):
		var other := other_value as Node3D
		if other == null or other == bot_body or not is_instance_valid(other):
			continue
		var distance := candidate.distance_to(other.global_position)
		if distance < CROWD_AVOID_RADIUS * 2.0:
			penalty += (CROWD_AVOID_RADIUS * 2.0 - distance) * 2.4
	return penalty


func _update_diagnostic_label() -> void:
	if _diagnostic_label == null or not diagnostics_enabled:
		return
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene
	var player := scene.get_node_or_null("Player") as Node3D if scene != null else null
	_diagnostic_label.visible = bot_body == null or player == null or not bot_body.has_method("is_visible_to") or bool(bot_body.call("is_visible_to", player))
	var destination_text := "—"
	if _has_tactical_destination:
		destination_text = "%.1f, %.1f" % [_tactical_destination.x, _tactical_destination.z]
	var target_text := "visible" if bool(_perception.get("visible", false)) else "mémoire %.1fs" % float(_perception.get("memory_age", 0.0)) if _has_last_observed_position else "perdue"
	var module_reason := str(_duel_equipment.get("last_module_reason")) if _duel_equipment != null else ""
	_diagnostic_label.text = "%s · %s\nCible %s · Dest %s%s" % [_current_intent.to_upper(), _intent_reason, target_text, destination_text, "\nModule : %s" % module_reason if not module_reason.is_empty() else ""]


func get_current_intent() -> String:
	return _current_intent


func get_repair_target() -> Node3D:
	return _repair_target if _repair_target != null and is_instance_valid(_repair_target) else null


func _update_repair_target(bot_body: Node3D, player: Node3D) -> bool:
	if not bot_body.has_method("get_health") or not bot_body.has_method("get_max_health"):
		_clear_repair_target()
		return false
	var maximum := maxf(1.0, float(bot_body.call("get_max_health")))
	var ratio := float(bot_body.call("get_health")) / maximum
	var threshold := clampf(float(_personality.get("heal_threshold", REPAIR_SEEK_HEALTH_RATIO)), 0.32, 0.76)
	if ratio >= (REPAIR_STOP_HEALTH_RATIO if _repair_target != null else threshold):
		_clear_repair_target()
		return false
	if _repair_target != null and (not is_instance_valid(_repair_target) or not _repair_usable(_repair_target)):
		_clear_repair_target()
	if _elapsed < _next_repair_search_at and _repair_target != null:
		return true
	if _elapsed < _next_repair_search_at:
		return false
	_next_repair_search_at = _elapsed + REPAIR_SEARCH_INTERVAL
	var best: Node3D
	var best_score := INF
	for candidate_node in get_tree().get_nodes_in_group("repair_kits"):
		var candidate := candidate_node as Node3D
		if candidate == null or not _repair_usable(candidate):
			continue
		var retry_at := float(_repair_retry_after.get(candidate.get_instance_id(), 0.0))
		if _elapsed < retry_at:
			continue
		var travel_distance: float = _navigation.route_distance(bot_body, candidate.global_position, _elapsed, SURVIVAL_ARENA_LIMIT if survival_role != "" else duel_arena_limit)
		if travel_distance == INF:
			continue
		var returning := not bool(candidate.call("is_available"))
		var respawn := float(candidate.call("get_respawn_remaining")) if returning else 0.0
		var base_speed := float(COMBAT_DATA.ROBOT_DEFINITIONS[str(_duel_equipment.get("robot_id"))].move_speed)
		var arrival := travel_distance / (base_speed * 0.96)
		var waiting_time := maxf(0.0, respawn - arrival)
		if returning and (waiting_time > 2.0 or respawn > 6.0):
			continue
		var player_distance := _last_observed_position.distance_to(candidate.global_position) if _has_last_observed_position else 20.0
		# Prefer short routes, but penalise pads controlled by the opponent or
		# exposed to a direct firing lane. The bot can still choose a dangerous
		# pad when it is the only viable repair source.
		var danger := maxf(0.0, 9.0 - player_distance) * 1.25
		if _has_last_observed_position and _position_exposed_from_known(bot_body, _last_observed_position, candidate.global_position):
			danger += 3.5
		# With critical health the actual heal matters more than an ideal firing lane.
		var score := travel_distance + danger * (0.55 if ratio < 0.28 else 1.0) + waiting_time * REPAIR_MOVE_SPEED
		if candidate == _repair_target:
			score -= 2.0 # Keep a planned route unless another objective is clearly better.
		if score < best_score:
			best_score = score
			best = candidate
	if best != _repair_target:
		_repair_target = best
		_repair_stuck_time = 0.0
	_repair_waiting = best != null and not bool(best.call("is_available"))
	return _repair_target != null


func _repair_usable(kit: Node3D) -> bool:
	if not kit.has_method("is_available"):
		return false
	if bool(kit.call("is_available")):
		return true
	return kit.has_method("get_visual_state_name") and str(kit.call("get_visual_state_name")) == "recharging" and float(kit.call("get_respawn_remaining")) <= 6.0


func _advance_repair_seek(bot_body: Node3D, delta: float) -> bool:
	if _repair_target == null or not is_instance_valid(_repair_target) or not _repair_usable(_repair_target):
		_clear_repair_target()
		return false
	var before_distance := bot_body.global_position.distance_to(_repair_target.global_position)
	var before_position := bot_body.global_position
	var collection_distance := float(_repair_target.call("get_collection_radius")) + 0.10
	if before_distance <= collection_distance and bool(_repair_target.call("is_accessible_to", bot_body)):
		_move_velocity = Vector3.ZERO
		if not bool(_repair_target.call("is_available")):
			_repair_waiting = true
			_repair_stuck_time = 0.0
			return true
		var applied := float(_repair_target.call("try_collect", bot_body))
		if applied > 0.0 or not bool(_repair_target.call("is_available")):
			_clear_repair_target()
			return true
		_repair_stuck_time += delta
	else:
		var direction: Vector3 = _navigation.get_direction(bot_body, _repair_target.global_position, _elapsed, SURVIVAL_ARENA_LIMIT if survival_role != "" else duel_arena_limit)
		var slow := 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95) if bot_body.has_method("get_slow_percent") else 1.0
		var base_speed := float(COMBAT_DATA.ROBOT_DEFINITIONS[str(_duel_equipment.get("robot_id"))].move_speed)
		var speed := base_speed * 0.96 * slow * float(_duel_equipment.call("get_speed_multiplier"))
		_move_velocity = _move_velocity.move_toward(direction * speed, MOVE_ACCELERATION * delta)
		_move_bot(bot_body, delta)
		# A valid detour may initially move away from the pad.
		if bot_body.global_position.distance_to(before_position) > 0.005:
			_repair_stuck_time = maxf(0.0, _repair_stuck_time - delta * 0.5)
		else:
			_repair_stuck_time += delta
	if _repair_stuck_time >= REPAIR_STUCK_TIMEOUT:
		_repair_retry_after[_repair_target.get_instance_id()] = _elapsed + 2.5
		_clear_repair_target()
		_next_repair_search_at = _elapsed
		_navigation.invalidate()
		return false
	return true


func _clear_repair_target() -> void:
	_repair_target = null
	_repair_stuck_time = 0.0
	_repair_waiting = false


func _environment_path_clear(actor: Node3D, destination: Vector3) -> bool:
	var world := actor.get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 0.72, destination + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query).is_empty()


func _position_exposed_to_actor(actor: Node3D, position: Vector3) -> bool:
	var world := actor.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 0.72, position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query).is_empty()


func _position_exposed_from_known(observer: Node3D, known_threat_position: Vector3, position: Vector3) -> bool:
	var world := observer.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(known_threat_position + Vector3.UP * 0.72, position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query).is_empty()


func _update_survival_bot(bot_body: Node3D, player: Node3D, delta: float) -> void:
	_navigation.arena_center = survival_arena_center
	_elapsed += delta
	_telegraph_clock += delta
	var target_visible := (not player.has_method("is_visible_to") or bool(player.call("is_visible_to", bot_body))) and _line_of_sight_clear(bot_body, player)
	_observe_bush_knowledge(bot_body, player, target_visible)
	if target_visible:
		_last_observed_position = player.global_position
		_has_last_observed_position = true
		_visual_aim_position = _last_observed_position
		_has_visual_aim_position = true
		_last_seen_at = _elapsed
		# An observation may become stale before a long legal detour is complete.
		# Keep its fixed location as an investigation goal, without retaining
		# current target knowledge or enabling attacks after memory has expired.
		_survival_search_goal = _last_observed_position
		_survival_search_goal.x = clampf(_survival_search_goal.x, survival_arena_center.x - 20.0, survival_arena_center.x + 20.0)
		_survival_search_goal.z = clampf(_survival_search_goal.z, survival_arena_center.z - 20.0, survival_arena_center.z + 20.0)
		_survival_search_seeded = true
	elif _elapsed - _last_seen_at > DUEL_MEMORY_SECONDS:
		_has_last_observed_position = false
		_has_visual_aim_position = false
	_sense_projectile_threat(bot_body)
	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	var pursuit := _last_observed_position if _has_last_observed_position else bot_body.global_position
	var toward := pursuit - bot_body.global_position
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
		if not _action_gate.owns(_attack_action_token, ACTION_GATE.Kind.WEAPON, SURVIVAL_ACTION_ID):
			_charge_remaining = 0.0
			_double_charge_pending = false
			_attack_action_token = 0
			return
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
				_charge_target = pursuit
				_windup_player = player
				_windup_remaining = 0.75
				get_node("/root/GameSfx").play_enemy("enemy_charge_warning", bot_body.global_position, player.global_position)
				_update_telegraph()
			else:
				_action_gate.release(_attack_action_token)
				_attack_action_token = 0
		return
	if _windup_remaining > 0.0:
		if not _action_gate.owns(_attack_action_token, ACTION_GATE.Kind.WEAPON, SURVIVAL_ACTION_ID):
			_windup_remaining = 0.0
			_windup_player = null
			_attack_action_token = 0
			_update_telegraph()
			return
		_windup_remaining = maxf(0.0, _windup_remaining - delta)
		_update_telegraph()
		if _windup_remaining <= 0.0:
			if survival_role == "charger" or (survival_role == "boss" and _attack_serial % 2 == 1):
				_charge_remaining = 0.8
				_charge_hit = false
			elif survival_role == "chaser":
				get_node("/root/GameSfx").play_enemy("enemy_melee", bot_body.global_position, player.global_position)
				# A committed melee swing resolves physical contact, not distance to
				# an old memory that the target may already have moved away from.
				if bot_body.global_position.distance_to(player.global_position) < 2.2 and _line_of_sight_clear(bot_body, player):
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
			if _charge_remaining <= 0.0:
				_action_gate.release(_attack_action_token)
				_attack_action_token = 0
			_next_attack_at = _elapsed + training_attack_interval
			_update_telegraph()
		return
	if _dodge_remaining > 0.0:
		_dodge_remaining = maxf(0.0, _dodge_remaining - delta)
		_move_velocity = _dodge_direction * DODGE_SPEED
		_move_bot(bot_body, delta)
		return
	if not _projectile_threat.is_empty() and _dodge_cooldown_remaining <= 0.0:
		var evade := _choose_dodge_direction(bot_body, Vector3(_projectile_threat.velocity))
		if evade.length_squared() > 0.01:
			_dodge_direction = evade
			_dodge_remaining = DODGE_DURATION
			_dodge_cooldown_remaining = DODGE_COOLDOWN
	var desired_speed := 0.0
	if survival_role == "chaser" or survival_role == "charger":
		desired_speed = 4.0 if survival_role == "chaser" else 2.4
	elif survival_role == "boss":
		desired_speed = 2.2 if distance > 7.0 else -1.0 if distance < 4.0 else 0.0
	else:
		desired_speed = 2.5 if distance > 9.0 else -2.2 if distance < 6.0 else 0.0
	var desired := pursuit
	if not target_visible and _has_suspected_bush():
		desired = _select_bush_search_destination(bot_body)
		desired_speed = 2.8 if survival_role == "chaser" else 2.4
	elif not _has_last_observed_position:
		desired = _select_survival_search_destination(bot_body)
		desired.x = clampf(desired.x, survival_arena_center.x - 20.0, survival_arena_center.x + 20.0)
		desired.z = clampf(desired.z, survival_arena_center.z - 20.0, survival_arena_center.z + 20.0)
		desired_speed = 3.4 if survival_role == "chaser" else 2.4
	elif survival_role in ["shooter", "boss"] or survival_role not in ["chaser", "charger"]:
		var away := -toward.normalized() if distance > 0.1 else Vector3.RIGHT
		var sign_value := 1.0 if get_instance_id() % 2 == 0 else -1.0
		var ideal := 5.8 if survival_role == "boss" else 7.5
		desired = pursuit + away.rotated(Vector3.UP, sign_value * 0.32) * ideal
		desired_speed = 2.2 if survival_role == "boss" else 2.5
	elif survival_role == "chaser" and distance < 7.0:
		var angle := TAU * float(get_instance_id() % 7) / 7.0
		desired = pursuit + Vector3(cos(angle), 0, sin(angle)) * 1.3
	desired.x = clampf(desired.x, survival_arena_center.x - 20.0, survival_arena_center.x + 20.0)
	desired.z = clampf(desired.z, survival_arena_center.z - 20.0, survival_arena_center.z + 20.0)
	if not _navigation.is_destination_clear(bot_body, desired, SURVIVAL_ARENA_LIMIT):
		desired = pursuit
	if bot_body.global_position.distance_to(desired) > 0.5:
		var slow := 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95) if bot_body.has_method("get_slow_percent") else 1.0
		var direction: Vector3 = _navigation.get_direction(bot_body, desired, _elapsed, SURVIVAL_ARENA_LIMIT)
		_move_velocity = _move_velocity.move_toward(direction * absf(desired_speed) * slow, MOVE_ACCELERATION * delta)
		_move_bot(bot_body, delta)
	else:
		_move_velocity = Vector3.ZERO
	var attack_range := 2.1 if survival_role == "chaser" else CHARGER_ATTACK_RANGE if survival_role == "charger" else BOSS_ATTACK_RANGE if survival_role == "boss" else 12.0
	var melee_attack := survival_role in ["chaser", "charger"] or (survival_role == "boss" and (_attack_serial + 1) % 2 == 1)
	var attack_path_clear := target_visible and (_line_of_sight_clear(bot_body, player) if melee_attack else _weapon_line_of_fire_clear(bot_body, player, pursuit))
	if _elapsed >= _next_attack_at and distance <= attack_range and target_visible and attack_path_clear:
		var action_token: int = _action_gate.try_acquire(ACTION_GATE.Kind.WEAPON, SURVIVAL_ACTION_ID)
		if action_token == 0:
			return
		_attack_action_token = action_token
		_mark_bot_combat_event(bot_body)
		_attack_serial += 1
		_double_charge_pending = survival_elite == "double_charge"
		_charge_target = pursuit
		_windup_player = player
		_windup_remaining = (0.65 if boss_phase_two else 0.85) if survival_role in ["charger", "boss"] else 0.6 if survival_elite == "spread" else 0.45
		if survival_role == "charger" or (survival_role == "boss" and _attack_serial % 2 == 1):
			get_node("/root/GameSfx").play_enemy("enemy_charge_warning", bot_body.global_position, player.global_position)
		_update_telegraph()


func _select_survival_search_destination(bot_body: Node3D) -> Vector3:
	# Commit to a reachable investigation until arrival. The generic ten-second
	# sector clock must not reverse a route halfway around a large obstacle.
	if _survival_search_goal.is_finite():
		_survival_search_goal.x = clampf(_survival_search_goal.x, survival_arena_center.x - 20.0, survival_arena_center.x + 20.0)
		_survival_search_goal.z = clampf(_survival_search_goal.z, survival_arena_center.z - 20.0, survival_arena_center.z + 20.0)
	if _survival_search_goal.is_finite() and bot_body.global_position.distance_to(_survival_search_goal) > 1.2:
		if _navigation.is_destination_clear(bot_body, _survival_search_goal, SURVIVAL_ARENA_LIMIT):
			return _survival_search_goal
	_survival_search_goal = Vector3.INF
	if not _survival_search_seeded:
		_survival_search_seeded = true
		# With no observation, inspect the opposite map half using only our own
		# position. This crosses a useful lane instead of circling the spawn.
		var origin := bot_body.global_position - survival_arena_center
		var opposite := Vector3(-13.0 if origin.x >= 0.0 else 13.0, 0.0, clampf(origin.z, -10.0, 10.0))
		if absf(origin.z) > absf(origin.x):
			opposite = Vector3(clampf(origin.x, -10.0, 10.0), 0.0, -13.0 if origin.z >= 0.0 else 13.0)
		for offset in [Vector3.ZERO, Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, -3.0), Vector3(3.0, 0.0, 0.0), Vector3(-3.0, 0.0, 0.0)]:
			var candidate: Vector3 = survival_arena_center + opposite + offset
			if _navigation.is_destination_clear(bot_body, candidate, SURVIVAL_ARENA_LIMIT) and _navigation.route_distance(bot_body, candidate, _elapsed, SURVIVAL_ARENA_LIMIT) < INF:
				_survival_search_goal = candidate
				return candidate
	# After checking the last sighting or the initial lane, sweep the authored
	# sectors in their ordinary schedule. Each selected route stays committed.
	_survival_search_goal = _select_search_destination(bot_body)
	_survival_search_goal.x = clampf(_survival_search_goal.x, survival_arena_center.x - 20.0, survival_arena_center.x + 20.0)
	_survival_search_goal.z = clampf(_survival_search_goal.z, survival_arena_center.z - 20.0, survival_arena_center.z + 20.0)
	if not _navigation.is_destination_clear(bot_body, _survival_search_goal, SURVIVAL_ARENA_LIMIT):
		# Clamping an edge observation can land on cover. Advance the search
		# schedule next frame instead of repeatedly steering at a blocked goal.
		_next_search_goal_at = 0.0
		_survival_search_goal = Vector3.INF
		return bot_body.global_position
	return _survival_search_goal


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
	next_position.x = clampf(next_position.x, survival_arena_center.x - SURVIVAL_ARENA_LIMIT, survival_arena_center.x + SURVIVAL_ARENA_LIMIT)
	next_position.z = clampf(next_position.z, survival_arena_center.z - SURVIVAL_ARENA_LIMIT, survival_arena_center.z + SURVIVAL_ARENA_LIMIT)
	next_position.y = 0.0
	bot_body.global_position = next_position
	if next_position.distance_to(_charge_target) <= 0.01 or next_position.distance_to(previous_position) < step - 0.01:
		_charge_remaining = 0.0
		_move_velocity = Vector3.ZERO


func _observe_duel_reload(player: Node3D, target_visible: bool) -> void:
	var reloading := target_visible and bool(_perception.get("target_reloading", false))
	if reloading:
		if _reload_observed_at < 0.0:
			_reload_observed_at = _elapsed
	else:
		_reload_observed_at = -1.0


func _update_hazard_avoidance(bot_body: Node3D, delta: float) -> bool:
	var hazards := get_tree().current_scene.get_node_or_null("ArenaHazards")
	if hazards == null or not bool(hazards.get("running")):
		_hazard_observed_at = -1.0
		_hazard_threat_id = 0
		return false
	var threats: Array[Dictionary] = hazards.call("get_threats")
	if threats.is_empty():
		_hazard_observed_at = -1.0
		_hazard_threat_id = 0
		return false
	var threat: Dictionary = hazards.call("threat_at", bot_body.global_position, 0.65, threats)
	if threat.is_empty():
		threat = hazards.call("threat_at", bot_body.global_position + _move_velocity * 0.65, 0.65, threats)
	if threat.is_empty():
		_hazard_observed_at = -1.0
		_hazard_threat_id = 0
		return false
	var threat_id := int(threat.id)
	if _hazard_threat_id != threat_id:
		_hazard_threat_id = threat_id
		_hazard_observed_at = _elapsed
	var reaction := float(_tuning.get("reaction_delay", 0.22))
	if hazards.has_method("get_heat") and float(hazards.call("get_heat", bot_body)) > 0.6:
		reaction *= 0.6
	# Its normal difficulty delay applies; occasional committed mistakes remain.
	var mistake_cycle := 4 if difficulty_profile == "easy" else (12 if difficulty_profile == "hard" else 8)
	if threat_id % mistake_cycle == 0 or _elapsed - _hazard_observed_at < reaction:
		return false
	var origin := bot_body.global_position
	var best := origin
	var best_score := INF
	for radius in [2.8, 4.2, 5.5]:
		for index in range(16):
			var angle := TAU * float(index) / 16.0
			var motion := Vector3(cos(angle), 0, sin(angle)) * float(radius)
			var candidate := origin + motion
			if absf(candidate.x) > duel_arena_limit - 1.0 or absf(candidate.z) > duel_arena_limit - 1.0:
				continue
			if not (hazards.call("threat_at", candidate, 0.85, threats) as Dictionary).is_empty():
				continue
			if _safe_bot_motion(bot_body, motion).length() < motion.length() - 0.08:
				continue
			var score := motion.length() - motion.normalized().dot(_move_velocity.normalized()) * 0.4
			if score < best_score:
				best_score = score
				best = candidate
		if best != origin:
			break
	if best == origin:
		_move_velocity = _move_velocity.move_toward(Vector3.ZERO, MOVE_ACCELERATION * delta)
		return true
	_dodge_remaining = 0.0
	var speed := float(COMBAT_DATA.ROBOT_DEFINITIONS[str(_duel_equipment.get("robot_id"))].move_speed)
	var slow := 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95)
	_move_velocity = _move_velocity.move_toward((best - origin).normalized() * speed * slow * float(_duel_equipment.call("get_speed_multiplier")), MOVE_ACCELERATION * delta)
	_move_bot(bot_body, delta)
	_force_intent("avoid_hazard", "zone piégée annoncée")
	return true


func _update_duel_movement(bot_body: Node3D, pursuit_position: Vector3, target_visible: bool, delta: float) -> void:
	var desired := _tactical_destination if _has_tactical_destination else pursuit_position
	var base_speed := float(COMBAT_DATA.ROBOT_DEFINITIONS[str(_duel_equipment.get("robot_id"))].move_speed)
	var speed := base_speed * lerpf(0.80, 1.0, float(_tuning.get("position_quality", 0.68)))
	if _current_intent in ["search_bush", "hide_bush", "ambush_bush"]:
		_has_angle_destination = false
	elif target_visible:
		_has_angle_destination = false
		if _current_intent == "pressure":
			speed = base_speed
		elif _current_intent in ["retreat", "break_line"]:
			speed = base_speed * 0.88
	elif _has_last_observed_position:
		if not _has_tactical_destination or bot_body.global_position.distance_to(desired) < 0.65 or (_blocked_time > 0.6 and _elapsed >= _next_angle_at):
			_select_duel_angle(bot_body, pursuit_position)
			_next_angle_at = _elapsed + DUEL_ANGLE_INTERVAL
		if _has_angle_destination:
			desired = _angle_destination
	else:
		_has_angle_destination = false
	if get_duel_profile() == "mekatana" and target_visible:
		var toward := pursuit_position - bot_body.global_position
		toward.y = 0.0
		var engagement: Vector2 = _duel_equipment.call("get_mekatana_engagement_range")
		if toward.length() < engagement.x:
			# Recovery can prepare spacing for the longer next dash. Keep the
			# configured travel intact instead of striking past a close target.
			var forward := toward.normalized() if toward.length_squared() > 0.001 else -bot_body.global_basis.z
			desired = pursuit_position - forward * _ideal_combat_range()
			_has_tactical_destination = false
			_next_tactical_decision_at = 0.0
	var to_desired := desired - bot_body.global_position
	to_desired.y = 0.0
	var desired_velocity := Vector3.ZERO
	if to_desired.length_squared() > 0.16:
		var slow_multiplier := 1.0
		if bot_body.has_method("get_slow_percent"):
			slow_multiplier = 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95)
		var route_direction: Vector3 = _navigation.get_direction(bot_body, desired, _elapsed, duel_arena_limit)
		desired_velocity = route_direction * speed * slow_multiplier * float(_duel_equipment.call("get_speed_multiplier"))
	_move_velocity = _move_velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)
	_move_bot(bot_body, delta)
	if _current_intent == "control_repair" and _control_repair_target != null and is_instance_valid(_control_repair_target):
		# Static bot bodies are moved by swept transforms. Explicitly interact
		# with the objective rather than depending on Area overlap notification.
		if bool(_control_repair_target.call("is_available")) and float(_control_repair_target.call("try_collect", bot_body)) > 0.0:
			_control_repair_target = null
			_force_intent("maintain", "soin pris, reprendre un angle de combat")
			_next_tactical_decision_at = 0.0


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
			if absf(candidate.x) > duel_arena_limit - 1.0 or absf(candidate.z) > duel_arena_limit - 1.0:
				continue
			if not _navigation.is_destination_clear(bot_body, candidate, duel_arena_limit):
				continue
			var shot_clear := _duel_path_clear(bot_body, candidate, last_known_position)
			if not shot_clear:
				continue
			var range_to_target: float = candidate.distance_to(last_known_position)
			var route: float = _navigation.route_distance(bot_body, candidate, _elapsed, duel_arena_limit)
			var score: float = absf(range_to_target - _ideal_combat_range()) * 0.6 + route * 0.18
			if score < best_score:
				best_score = score
				_angle_destination = candidate
				_has_angle_destination = true
	if not _has_angle_destination and _navigation.is_destination_clear(bot_body, last_known_position, duel_arena_limit):
		_angle_destination = last_known_position
		_has_angle_destination = true


func _duel_path_clear(bot_body: Node3D, origin: Vector3, destination: Vector3) -> bool:
	var world := bot_body.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.72, destination + Vector3.UP * 0.72)
	query.collision_mask = 1 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = MAGNETIC_WALL.owned_exclusions(self, [bot_body.get_rid()])
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
	if _has_suspected_bush():
		desired = _select_bush_search_destination(bot_body)
	elif distance < IDEAL_RANGE_MIN and distance > 0.05:
		desired = bot_body.global_position - to_player.normalized() * 2.2
	elif distance > IDEAL_RANGE_MAX and distance > 0.05:
		desired = bot_body.global_position + to_player.normalized() * 2.0
	else:
		desired = _spawn_position + Vector3(
			sin(_elapsed * 0.72) * MOVE_RADIUS_X,
			0.0,
			cos(_elapsed * 0.53) * MOVE_RADIUS_Z
		)
	desired.x = clampf(desired.x, -duel_arena_limit, duel_arena_limit)
	desired.z = clampf(desired.z, -duel_arena_limit, duel_arena_limit)
	var to_desired := desired - bot_body.global_position
	to_desired.y = 0.0
	var desired_velocity := Vector3.ZERO
	if to_desired.length_squared() > 0.04:
		var slow_multiplier := 1.0
		if bot_body.has_method("get_slow_percent"):
			slow_multiplier = 1.0 - clampf(float(bot_body.call("get_slow_percent")) / 100.0, 0.0, 0.95)
		desired_velocity = _navigation.get_direction(bot_body, desired, _elapsed, duel_arena_limit) * MOVE_SPEED * slow_multiplier
	_move_velocity = _move_velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)
	_move_bot(bot_body, delta)


func _move_bot(bot_body: Node3D, delta: float) -> void:
	if _move_velocity.length_squared() <= 0.0001:
		_move_velocity = Vector3.ZERO
	if not _recover_bot_from_cover(bot_body):
		_move_velocity = Vector3.ZERO
		return
	var separation := _bot_separation_velocity(bot_body)
	var requested_motion := (_move_velocity + separation) * delta
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
	var arena_limit := SURVIVAL_ARENA_LIMIT if survival_role != "" else duel_arena_limit
	bot_body.global_position.x = clampf(bot_body.global_position.x, survival_arena_center.x - arena_limit, survival_arena_center.x + arena_limit)
	bot_body.global_position.z = clampf(bot_body.global_position.z, survival_arena_center.z - arena_limit, survival_arena_center.z + arena_limit)
	ARENA_TRAVERSAL.snap(bot_body)
	if _elapsed >= _progress_anchor_at + PROGRESS_SAMPLE_INTERVAL:
		var progressed := bot_body.global_position.distance_to(_progress_anchor)
		var still_has_route := _has_tactical_destination and bot_body.global_position.distance_to(_tactical_destination) > 0.85
		if still_has_route and _move_velocity.length() > 0.5 and progressed < 0.08:
			_blocked_time = maxf(_blocked_time, PROGRESS_SAMPLE_INTERVAL)
			_has_tactical_destination = false
			_next_tactical_decision_at = 0.0
			_strafe_sign = -_strafe_sign
			_navigation.invalidate()
		_progress_anchor = bot_body.global_position
		_progress_anchor_at = _elapsed


func _bot_separation_velocity(bot_body: Node3D) -> Vector3:
	var separation := Vector3.ZERO
	for other_value in get_tree().get_nodes_in_group("prototype0_combat_bots"):
		var other := other_value as Node3D
		if other == null or other == bot_body or not is_instance_valid(other):
			continue
		if other.has_method("is_training_bot_enabled") and not bool(other.call("is_training_bot_enabled")):
			continue
		var away := bot_body.global_position - other.global_position
		away.y = 0.0
		var distance := away.length()
		if distance <= 0.001 or distance >= CROWD_AVOID_RADIUS:
			continue
		separation += away / distance * (CROWD_AVOID_RADIUS - distance) / CROWD_AVOID_RADIUS * 2.4
	return separation.limit_length(2.4)


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
	var excluded := MAGNETIC_WALL.owned_exclusions(self, [bot_body.get_rid()])
	excluded.append_array(ARENA_TRAVERSAL.exclusions(bot_body))
	query.exclude = excluded
	query.margin = BOT_COLLISION_MARGIN
	var scene := bot_body.get_tree().current_scene
	if scene != null and scene.has_meta("arena_floor_rid"):
		var exclusions := query.exclude
		exclusions.append(scene.get_meta("arena_floor_rid"))
		query.exclude = exclusions
	return query


func _safe_bot_motion(bot_body: Node3D, motion: Vector3) -> Vector3:
	motion = ARENA_TRAVERSAL.motion(bot_body, motion)
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
	var arena_limit := SURVIVAL_ARENA_LIMIT if survival_role != "" else duel_arena_limit
	for radius in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
		for index in range(16):
			var angle := TAU * float(index) / 16.0
			var candidate: Vector3 = origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if absf(candidate.x - survival_arena_center.x) > arena_limit or absf(candidate.z - survival_arena_center.z) > arena_limit:
				continue
			query.transform.origin = candidate + shape_offset
			if world.direct_space_state.intersect_shape(query, 1).is_empty():
				bot_body.global_position = candidate
				_move_velocity = Vector3.ZERO
				_avoid_direction = Vector3.ZERO
				return true
	return false


func _try_dodge(bot_body: Node3D, player: Node3D, target_visible: bool, duel_tactics: bool) -> void:
	if duel_tactics and _duel_equipment != null and bool(_duel_equipment.call("is_dashing")):
		return
	var threatened := _visible_player_threat(bot_body, player, target_visible) if duel_tactics else (target_visible and player.has_method("is_attack_committed") and bool(player.call("is_attack_committed"))) or not _projectile_threat.is_empty()
	if not threatened:
		_attack_observed_at = -1.0
		return
	if _dodge_cooldown_remaining > 0.0:
		return
	if duel_tactics:
		# Target windups have already passed through the delayed observation queue.
		# Flying shots have their own first-seen reaction clock.
		if _attack_observed_at < 0.0:
			_attack_observed_at = _elapsed
			_threat_serial += 1
			var evade_cycle := maxi(3, int(round(3.0 + float(_tuning.get("position_quality", 0.68)) * 3.0)))
			if _threat_serial % evade_cycle == 0:
				_attack_observed_at = INF
		if _attack_observed_at == INF:
			return
	var incoming := Vector3(_projectile_threat.get("velocity", (_threat_position if duel_tactics else _last_observed_position) - bot_body.global_position))
	_dodge_direction = _choose_dodge_direction(bot_body, incoming)
	if _dodge_direction.length_squared() < 0.01:
		return
	_dodge_remaining = DODGE_DURATION
	_dodge_cooldown_remaining = DODGE_COOLDOWN
	_move_velocity = _dodge_direction * DODGE_SPEED


func _visible_player_threat(bot_body: Node3D, player: Node3D, target_visible: bool) -> bool:
	if target_visible and bool(_perception.get("target_charging", false)):
		var aim: Vector3 = _perception.get("target_aim_direction", Vector3.ZERO)
		var to_bot := bot_body.global_position - _last_observed_position
		to_bot.y = 0.0
		if aim.length_squared() < 0.01 or aim.normalized().dot(to_bot.normalized()) > 0.82:
			_threat_position = _last_observed_position
			return true
	_sense_projectile_threat(bot_body)
	if not _projectile_threat.is_empty():
		_threat_position = _projectile_threat.position
		return true
	return false


func _sense_projectile_threat(bot_body: Node3D) -> void:
	if is_equal_approx(_last_threat_scan_at, _elapsed):
		return
	_last_threat_scan_at = _elapsed
	_projectile_threat.clear()
	var latest: Dictionary = {}
	var best_time := INF
	var checked := 0
	for node in get_tree().get_nodes_in_group("prototype0_gameplay_projectiles"):
		var projectile := node as Node3D
		if projectile == null or not is_instance_valid(projectile):
			continue
		# Player flight metadata is public motion, never aim input or hidden actor state.
		if int(projectile.get_meta("ai_projectile_source", 0)) == bot_body.get_instance_id() or str(projectile.name).begins_with("DuelBot"):
			continue
		if not projectile.has_meta("ai_projectile_velocity") and not str(projectile.name) in ["BlasterProjectile", "ShotgunPellet", "JavelinProjectile"]:
			continue
		var position := projectile.global_position
		if Vector2(position.x - bot_body.global_position.x, position.z - bot_body.global_position.z).length() > 17.0 or not _duel_path_clear(bot_body, bot_body.global_position, position):
			continue
		checked += 1
		if checked > 64:
			break
		var id := projectile.get_instance_id()
		var previous: Dictionary = _projectile_previous.get(id, {})
		var first_seen := float(previous.get("since", _elapsed))
		var velocity: Vector3 = projectile.get_meta("ai_projectile_velocity", Vector3.ZERO)
		if not previous.is_empty() and _elapsed > float(previous.time) + 0.001:
			velocity = (position - Vector3(previous.position)) / (_elapsed - float(previous.time))
		velocity.y = 0.0
		latest[id] = {"position": position, "time": _elapsed, "since": first_seen}
		if _elapsed - first_seen < float(_tuning.get("reaction_delay", 0.22)):
			continue
		var relative_position := position - bot_body.global_position
		relative_position.y = 0.0
		var relative_velocity := velocity - _move_velocity
		if relative_velocity.length_squared() < 0.1:
			continue
		var impact_time := -relative_position.dot(relative_velocity) / relative_velocity.length_squared()
		if impact_time < 0.0 or impact_time > float(_tuning.get("dodge_horizon", 0.72)):
			continue
		var closest := relative_position + relative_velocity * impact_time
		var body_radius := 0.7 * maxf(absf(bot_body.scale.x), absf(bot_body.scale.z))
		var danger_radius := body_radius + float(projectile.get_meta("ai_projectile_radius", 0.18)) + 0.18
		if closest.length() > danger_radius:
			continue
		if projectile.has_meta("ai_projectile_endpoint"):
			var endpoint: Vector3 = projectile.get_meta("ai_projectile_endpoint")
			if position.distance_to(endpoint) + danger_radius < velocity.length() * impact_time:
				continue
		if impact_time < best_time:
			best_time = impact_time
			_projectile_threat = {"position": position, "velocity": velocity, "time": impact_time, "radius": danger_radius, "id": id}
	_projectile_previous = latest


func _choose_dodge_direction(bot_body: Node3D, incoming: Vector3) -> Vector3:
	incoming.y = 0.0
	if incoming.length_squared() < 0.01:
		return Vector3.ZERO
	var forward := incoming.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var best := Vector3.ZERO
	var best_score := -INF
	var arena_limit := SURVIVAL_ARENA_LIMIT if survival_role != "" else duel_arena_limit
	for index in range(8):
		var direction := side.rotated(Vector3.UP, TAU * float(index) / 8.0)
		var motion := direction * DODGE_SPEED * DODGE_DURATION
		var destination := bot_body.global_position + motion
		if absf(destination.x - survival_arena_center.x) > arena_limit or absf(destination.z - survival_arena_center.z) > arena_limit:
			continue
		var safe := _safe_bot_motion(bot_body, motion)
		if safe.length() < motion.length() * 0.92:
			continue
		var score := absf(direction.dot(side)) * 3.0 - _candidate_crowd_penalty(bot_body, destination)
		if not _projectile_threat.is_empty():
			var position: Vector3 = _projectile_threat.position
			position.y = 0.0
			var velocity: Vector3 = _projectile_threat.velocity
			var toward_destination := destination - position
			var nearest_time := clampf(toward_destination.dot(velocity) / maxf(0.01, velocity.length_squared()), 0.0, DODGE_DURATION + 0.2)
			var clearance := destination.distance_to(position + velocity * nearest_time)
			score += minf(clearance, 4.0)
		if _has_tactical_destination:
			score -= destination.distance_to(_tactical_destination) * 0.06
		if direction.dot(side) * _strafe_sign > 0.0:
			score += 0.15
		if score > best_score:
			best_score = score
			best = direction
	return best


func _can_attack(bot_body: Node3D, player: Node3D) -> bool:
	if ARENA_TRAVERSAL.attack_blocked(bot_body):
		return false
	if player.has_method("is_visible_to") and not bool(player.call("is_visible_to", bot_body)):
		return false
	if bot_body.global_position.distance_to(player.global_position) > ATTACK_RANGE:
		return false
	return _weapon_line_of_fire_clear(bot_body, player, player.global_position)


func execute_duel_offensive(module_id: String, bot_body: Node3D, player: Node3D, locked_position: Vector3, _visible: bool) -> void:
	if ARENA_TRAVERSAL.attack_blocked(bot_body):
		return
	if bot_body == null or player == null or not is_instance_valid(player):
		return
	var direction := locked_position - bot_body.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	direction = direction.normalized()
	_attack_serial += 1
	if module_id == "fulguro_punch":
		var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]
		var locked_distance := bot_body.global_position.distance_to(locked_position)
		var ratio := clampf(inverse_lerp(float(definition["range_min"]), float(definition["range_max"]), locked_distance - FULGURO.hit_radius(player)), 0.0, 1.0)
		var before := float(player.call("get_health")) if player.has_method("get_health") else 0.0
		var target := FULGURO.resolve_strike(
			bot_body as CollisionObject3D,
			[player],
			direction,
			lerpf(float(definition["damage_min"]), float(definition["damage_max"]), ratio),
			lerpf(float(definition["wall_damage_min"]), float(definition["wall_damage_max"]), ratio),
			float(definition["wall_stun"]),
			"duel_bot",
			"duel_bot:fulguro:%d" % _attack_serial,
			lerpf(float(definition["range_min"]), float(definition["range_max"]), ratio),
			float(definition["width"])
		)
		_fulguro_direction = direction
		_fulguro_charge_ratio = ratio
		_spawn_fulguro_strike_visual(bot_body, target as Node3D, lerpf(float(definition["range_min"]), float(definition["range_max"]), ratio))
		if _duel_equipment != null and player.has_method("get_health"):
			_duel_equipment.call("register_damage", bot_body, maxf(0.0, before - float(player.call("get_health"))))
	elif module_id == "pelto_smash":
		var wave := PELTO_SMASH.new()
		wave.name = "DuelBotPeltoWave"
		get_tree().current_scene.add_child(wave)
		wave.configure(bot_body, bot_body.global_position, direction, "duel_bot", "duel_bot:pelto:%d" % _attack_serial)


func intercept_duel_damage(amount: float, current_health: float) -> Dictionary:
	if _duel_equipment == null or not _duel_equipment.has_method("intercept_damage"):
		return {"effective": amount, "apply_to_health": true, "triggered_baroud": false, "real_death": false}
	return _duel_equipment.call("intercept_damage", amount, current_health)


func register_duel_damage(effective_damage: float) -> void:
	var body := get_parent() as Node3D
	if _duel_equipment != null and body != null:
		_duel_equipment.call("register_damage", body, effective_damage)


func _begin_attack(bot_body: Node3D, player: Node3D) -> void:
	if ARENA_TRAVERSAL.attack_blocked(bot_body):
		return
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]
	var pelto_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"]
	var to_player := player.global_position - bot_body.global_position
	to_player.y = 0.0
	var target_radius := FULGURO.hit_radius(player)
	var can_punch := _elapsed >= _next_fulguro_ready_at and to_player.length() <= float(definition.range_max) + target_radius
	var can_pelto := not can_punch and _elapsed >= _next_pelto_ready_at and to_player.length() <= float(pelto_definition.max_range) + target_radius
	_attack_mode = "fulguro" if can_punch else "pelto" if can_pelto else "ranged"
	var action_kind := ACTION_GATE.Kind.MODULE if can_punch or can_pelto else ACTION_GATE.Kind.WEAPON
	_attack_action_token = _action_gate.try_acquire(action_kind, _attack_mode)
	if _attack_action_token == 0:
		return
	_mark_bot_combat_event(bot_body)
	_windup_player = player
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


func _mark_bot_combat_event(bot_body: Node3D) -> void:
	if bot_body != null and bot_body.has_method("mark_combat_event"):
		bot_body.call("mark_combat_event")


func _resolve_attack(bot_body: Node3D, player: Node3D) -> void:
	if ARENA_TRAVERSAL.attack_blocked(bot_body):
		_action_gate.release(_attack_action_token)
		_attack_action_token = 0
		return
	var expected_kind := ACTION_GATE.Kind.MODULE if _attack_mode in ["fulguro", "pelto"] else ACTION_GATE.Kind.WEAPON
	if player == null or not is_instance_valid(player) or not _action_gate.owns(_attack_action_token, expected_kind, _attack_mode):
		_action_gate.release(_attack_action_token)
		_attack_action_token = 0
		return
	if _attack_mode == "fulguro":
		_resolve_fulguro_attack(bot_body, player)
	elif _attack_mode == "pelto":
		_resolve_pelto_attack(bot_body)
	elif _can_attack(bot_body, player):
		_attack_player(player)
	_action_gate.release(_attack_action_token)
	_attack_action_token = 0
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
	# A victim feels the pull direction; it need not know its hidden source.
	var pull: Vector3 = bot_body.get("_pelto_pull_direction") if bot_body.get("_pelto_pull_direction") is Vector3 else Vector3.ZERO
	var incoming := -pull if pull.length_squared() > 0.01 else _last_observed_position - bot_body.global_position if _has_last_observed_position else Vector3.RIGHT
	var side := _choose_dodge_direction(bot_body, incoming)
	if side.length_squared() > 0.01:
		bot_body.call("request_defensive_dodge", side)


func cancel_action() -> void:
	_action_gate.reset()
	_attack_action_token = 0
	if _duel_equipment != null and survival_role == "":
		_duel_equipment.call("cancel_action")
		var body := get_parent()
		if body != null and body.has_method("is_real_dead") and bool(body.call("is_real_dead")):
			_duel_equipment.call("reset_longshot_cycle")
	_windup_remaining = 0.0
	_windup_player = null
	_attack_mode = "ranged"
	_charge_remaining = 0.0
	_charge_hit = false
	_double_charge_pending = false
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
	var visible := (not player.has_method("is_visible_to") or bool(player.call("is_visible_to", bot_body))) and _line_of_sight_clear(bot_body, player)
	if not visible:
		return
	var duel := bot_body.has_method("is_duel_mode") and bool(bot_body.call("is_duel_mode")) and survival_role == ""
	if duel:
		if not bool(_perception.get("visible", false)) or not bool(_perception.get("target_charging", false)):
			return
	elif not bool(player.call("is_attack_committed")):
		return
	var incoming := _last_observed_position - bot_body.global_position if duel else player.global_position - bot_body.global_position
	var side := _choose_dodge_direction(bot_body, incoming)
	if side.length_squared() > 0.01:
		bot_body.call("request_defensive_dodge", side)


func _line_of_sight_clear(bot_body: Node3D, player: Node3D) -> bool:
	var world := bot_body.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(bot_body.global_position + Vector3.UP * 0.72, player.global_position + Vector3.UP * 0.72)
	# Magnetic fields absorb shots but remain transparent to vision, matching
	# actor visibility. Keep firing checks in _weapon_line_of_fire_clear.
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = MAGNETIC_WALL.owned_exclusions(self, [bot_body.get_rid(), player.get_rid()])
	return world.direct_space_state.intersect_ray(query).is_empty()


func _attack_player(player: Node3D) -> void:
	if not player.has_method("take_damage"):
		return
	_attack_serial += 1
	# Damage comes from the projectile crossing the player's current collision.
	_spawn_attack_visual(player, "training_bot:%d" % _attack_serial)


func _spawn_attack_visual(player: Node3D, attack_id: String, offset: Vector3 = Vector3.ZERO) -> void:
	if survival_role != "":
		attack_id = "%d:%s" % [get_instance_id(), attack_id]
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	if bot_body == null or scene == null:
		return
	if offset == Vector3.ZERO:
		get_node("/root/GameSfx").play_enemy("enemy_shot", bot_body.global_position, player.global_position)
	var locked_position := _charge_target if survival_role != "" else _last_observed_position if _has_last_observed_position else player.global_position
	if survival_role != "" and offset != Vector3.ZERO:
		var toward := (locked_position - bot_body.global_position).normalized()
		offset = Vector3(-toward.z, 0.0, toward.x).normalized() * offset.x
	var impact_position := locked_position + Vector3.UP * 0.92 + offset
	var shot_transform := Transform3D(Basis.IDENTITY, bot_body.global_position + Vector3.UP * 1.30)
	if bot_body.has_method("prepare_training_bot_shot"):
		shot_transform = bot_body.call("prepare_training_bot_shot", impact_position)
	var start_position := shot_transform.origin
	start_position.y = maxf(start_position.y, bot_body.global_position.y + 0.85)
	var tracer := LIVE_PROJECTILE.new()
	tracer.name = "TrainingBotProjectile"
	tracer.process_mode = Node.PROCESS_MODE_PAUSABLE
	scene.add_child(tracer)
	if scene.has_method("register_fx_node"):
		scene.call("register_fx_node", tracer, "projectile")
	tracer.global_position = start_position
	var direction := (impact_position - start_position).normalized()
	tracer.basis = Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y) > 0.98 else Vector3.UP)
	var excluded: Array[RID] = [bot_body.get_rid()]
	tracer.configure(direction, PROJECTILE_SPEED, PROJECTILE_MAX_RANGE, 1 | 4 | 8, excluded)
	tracer.set_meta("ai_projectile_source", bot_body.get_instance_id())
	tracer.set_meta("ai_projectile_velocity", direction * PROJECTILE_SPEED)
	tracer.set_meta("ai_projectile_endpoint", start_position + direction * PROJECTILE_MAX_RANGE)
	tracer.set_meta("ai_projectile_radius", 0.16)
	tracer.finished.connect(_resolve_projectile.bind(player, scene, attack_id))
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("projectile_visual", tracer, "enemy")
		var socket := bot_body.find_child("Muzzle", true, false) as Node3D
		if socket != null:
			vfx.call("muzzle", socket, "enemy")
		else:
			vfx.call("burst", start_position, direction, Color("#ffcf87"), 4, 2.8, 0.10, 0.03, 30.0)


func _resolve_projectile(hit: Dictionary, _distance: float, player: Node3D, scene: Node, attack_id: String) -> void:
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if is_instance_valid(collider) and collider.has_meta("survival_evolution_controller"):
		var controller: Node = collider.get_meta("survival_evolution_controller")
		if is_instance_valid(controller):
			controller.wall_absorb(training_attack_damage)
	if is_instance_valid(player) and hit.get("collider") == player and player.has_method("take_damage"):
		player.call("take_damage", training_attack_damage, "training_bot", attack_id)
	if not is_instance_valid(scene):
		return
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		var surface: String = vfx.call("surface_for", hit["collider"])
		vfx.call("impact", hit["position"], hit["normal"], surface, 1.0 if surface == "robot" else 0.75, Color("#ffbf83"))
		if surface == "shield" and hit["collider"].name == "MagneticField":
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
	var target_position := _charge_target if survival_role != "" else _last_observed_position if _has_last_observed_position else bot_position
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
