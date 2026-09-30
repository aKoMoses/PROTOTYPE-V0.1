extends Node

const LOADOUT := preload("res://scripts/loadout_state.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const LIVE_PROJECTILE := preload("res://scripts/live_projectile.gd")
const LONGSHOT_STATE := preload("res://scripts/longshot_state.gd")
const LONGSHOT_PROJECTILE := preload("res://scripts/longshot_projectile.gd")
const PASSIVE_STATE := preload("res://scripts/passive_state.gd")
const ACTION_GATE := preload("res://scripts/action_gate.gd")
const MEKATANA_ATTACK := preload("res://scripts/mekatana_attack.gd")

var profile := "blaster"
var robot_id := COMBAT_DATA.DEFAULT_ROBOT
var build_title := "ADVERSAIRE"
var offensive_id := "modulo_drone"
var defensive_id := "magnetic_field"
var mobility_id := "bio_injector"
var passive_id := "omnivamp"
var ammo := 0
var reload_remaining := 0.0
var charge_remaining := 0.0
var charge_duration := 0.0
var next_attack_at := 1.0
var pyro_cooldown := 0.0
var bio_cooldown := 0.0
var bio_remaining := 0.0
var dash_remaining := 0.0
var dash_direction := Vector3.ZERO
var _generation := 0
var _shot_serial := 0
var _decision_serial := 0
var _aim_position := Vector3.ZERO
var _aim_error_angle := 0.0
var _last_visible_at := -100.0
var module_cooldowns: Dictionary = {}
var static_remaining := 0.0
var module_remaining := 0.0
var pending_module := ""
var last_module_reason := ""
var _module_aim_position := Vector3.ZERO
var _module_serial := 0
var _next_module_at := 1.2
var _charge_lost_time := 0.0
var _javelin_mark_remaining := 0.0
var _javelin_marked_player: Node3D
var _magnetic_wall: Area3D
var _passive_state = PASSIVE_STATE.new()
var _latest_tuning: Dictionary = {}
var _last_tick_elapsed := 0.0
var _action_gate = ACTION_GATE.new()
var _weapon_action_token := 0
var _module_action_token := 0
var _pending_module_serial := 0
var longshot_state = LONGSHOT_STATE.new()
var _longshot_generation := 0
var _longshot_next_attack_at := 0.0
var _mekatana
var _mekatana_body: Node3D
var _mekatana_controller: Node
var _mekatana_movement_owned_this_tick := false


func set_action_gate(shared_gate) -> void:
	if shared_gate != null:
		_action_gate = shared_gate


func set_profile(value: String) -> void:
	var weapon := value if value in ["blaster", "shotgun", "mekatana", "longshot"] else "blaster"
	var retained_longshot_shots: int = longshot_state.shots_fired
	var retained_longshot_generation := _longshot_generation
	var retained_longshot_recovery := _longshot_next_attack_at
	var close_weapon := weapon in ["shotgun", "mekatana"]
	set_loadout({
		"weapon": weapon,
		"offensive": "pelto_smash" if close_weapon else "modulo_drone",
		"defensive": "static_shield" if close_weapon else "magnetic_field",
		"mobility": "pyro_boots" if close_weapon else "bio_injector",
		"passive": "baroud" if close_weapon else "omnivamp",
	})
	# A selection change equips the existing instance. A full set_loadout or
	# round reset below replaces it and starts a fresh cycle.
	longshot_state.shots_fired = retained_longshot_shots
	_longshot_generation = retained_longshot_generation
	_longshot_next_attack_at = retained_longshot_recovery
	_update_readout()


func set_loadout(value: Dictionary) -> void:
	robot_id = str(LOADOUT.sanitize(value).robot)
	build_title = str(value.get("title", "ADVERSAIRE"))
	var requested_weapon := str(value.get("weapon", profile))
	profile = requested_weapon if requested_weapon in ["blaster", "shotgun", "mekatana", "longshot"] else "blaster"
	offensive_id = str(value.get("offensive", "pelto_smash" if profile == "shotgun" else "modulo_drone"))
	if not offensive_id in ["modulo_drone", "javelin", "fulguro_punch", "pelto_smash"]:
		offensive_id = "modulo_drone"
	defensive_id = str(value.get("defensive", "static_shield" if profile == "shotgun" else "magnetic_field"))
	if not defensive_id in ["magnetic_field", "static_shield"]:
		defensive_id = "magnetic_field"
	mobility_id = str(value.get("mobility", "pyro_boots" if profile == "shotgun" else "bio_injector"))
	if not mobility_id in ["pyro_boots", "bio_injector"]:
		mobility_id = "pyro_boots"
	passive_id = str(value.get("passive", "baroud" if profile == "shotgun" else "omnivamp"))
	if not passive_id in ["baroud", "omnivamp"]:
		passive_id = "baroud"
	reset()


func get_loadout() -> Dictionary:
	return {"robot": robot_id, "title": build_title, "weapon": profile, "offensive": offensive_id, "defensive": defensive_id, "mobility": mobility_id, "passive": passive_id}


func reset() -> void:
	longshot_state.reset()
	_longshot_generation += 1
	_longshot_next_attack_at = 0.0
	_cancel_mekatana()
	_generation += 1
	_action_gate.reset()
	_weapon_action_token = 0
	_module_action_token = 0
	_pending_module_serial = 0
	ammo = int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"])
	reload_remaining = 0.0
	charge_remaining = 0.0
	charge_duration = 0.0
	next_attack_at = 1.0
	pyro_cooldown = 0.0
	bio_cooldown = 0.0
	bio_remaining = 0.0
	dash_remaining = 0.0
	dash_direction = Vector3.ZERO
	_shot_serial = 0
	_decision_serial = 0
	_aim_position = Vector3.ZERO
	_aim_error_angle = 0.0
	_last_visible_at = -100.0
	module_cooldowns.clear()
	static_remaining = 0.0
	module_remaining = 0.0
	pending_module = ""
	last_module_reason = ""
	_module_serial = 0
	_next_module_at = 1.2
	_charge_lost_time = 0.0
	_javelin_mark_remaining = 0.0
	_javelin_marked_player = null
	_passive_state.configure(passive_id)
	_passive_state.reset()
	if _magnetic_wall != null and is_instance_valid(_magnetic_wall):
		_magnetic_wall.queue_free()
	_magnetic_wall = null
	var body := get_parent().get_parent() as Node3D if get_parent() != null else null
	if body != null:
		body.remove_meta("duel_static_shield")
	_update_readout()


func get_speed_multiplier() -> float:
	if static_remaining > 0.0:
		return 0.0
	var multiplier := float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["speed_multiplier"]) if bio_remaining > 0.0 else 1.0
	if profile == "blaster" and charge_remaining > 0.0:
		multiplier *= float(COMBAT_DATA.WEAPON_DEFINITIONS["blaster"]["charge_slow_multiplier"])
	return multiplier


func is_dashing() -> bool:
	return dash_remaining > 0.0


func is_reloading() -> bool:
	return reload_remaining > 0.0


func is_action_locked() -> bool:
	return static_remaining > 0.0


func owns_mekatana_movement() -> bool:
	return _mekatana_movement_owned_this_tick or (_mekatana != null and _mekatana.is_direction_locked())


func get_mekatana_direction() -> Vector3:
	return _mekatana.direction if _mekatana != null and _mekatana.is_direction_locked() else Vector3.ZERO


func get_mekatana_phase() -> String:
	return str(_mekatana.phase) if _mekatana != null else ""


func get_mekatana_next_step() -> int:
	if _mekatana == null:
		return 0
	if _mekatana.is_direction_locked():
		return int(_mekatana.step)
	return int(_mekatana.next_step) if _mekatana.combo_remaining > 0.0 else 0


func get_mekatana_dash_distance() -> float:
	var values: Dictionary = _mekatana.definition if _mekatana != null else COMBAT_DATA.WEAPON_DEFINITIONS["mekatana"]
	return float(values.dash_distance[get_mekatana_next_step()])


func get_mekatana_engagement_range() -> Vector2:
	var values: Dictionary = _mekatana.definition if _mekatana != null else COMBAT_DATA.WEAPON_DEFINITIONS["mekatana"]
	var dash := get_mekatana_dash_distance()
	# Admit the complete dash only with the observed target still ahead at its
	# end. Each rank uses its own reach instead of the third rank's maximum.
	return Vector2(dash + 0.25, minf(dash + float(values.melee_range), float(values.max_range)))


func get_action_owner() -> String:
	return _action_gate.get_owner_id()


func _begin_weapon_action() -> bool:
	var token: int = _action_gate.try_acquire(ACTION_GATE.Kind.WEAPON, profile)
	if token == 0:
		return false
	_weapon_action_token = token
	_mark_combat_event()
	return true


func _begin_module_action(module_id: String) -> bool:
	if _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		return false
	var token: int = _action_gate.replace_weapon_with_module(module_id) if _action_gate.is_kind(ACTION_GATE.Kind.WEAPON) else _action_gate.try_acquire(ACTION_GATE.Kind.MODULE, module_id)
	if token == 0:
		return false
	_weapon_action_token = 0
	_cancel_mekatana()
	_module_action_token = token
	charge_remaining = 0.0
	charge_duration = 0.0
	_charge_lost_time = 0.0
	# Recast placement is validated after acquiring its action token. A failed
	# teleport must not reveal an actor that stayed quietly inside the grass.
	if module_id != "javelin_recast":
		_mark_combat_event()
	return true


func _mark_combat_event(body: Node3D = null) -> void:
	if body == null:
		var controller := get_parent()
		body = controller.get_parent() as Node3D if controller != null else null
	if body != null and body.has_method("mark_combat_event"):
		body.call("mark_combat_event")


func _module_action_valid(module_id: String, token: int = 0) -> bool:
	var expected := _module_action_token if token == 0 else token
	return _action_gate.owns(expected, ACTION_GATE.Kind.MODULE, module_id)


func _release_weapon_action() -> void:
	_action_gate.release(_weapon_action_token)
	_weapon_action_token = 0


func _release_module_action(module_id: String, token: int = 0) -> void:
	var expected := _module_action_token if token == 0 else token
	if _action_gate.owns(expected, ACTION_GATE.Kind.MODULE, module_id):
		_action_gate.release(expected)
	if _module_action_token == expected:
		_module_action_token = 0


func cancel_action(reason: String = "action interrompue") -> void:
	_cancel_mekatana()
	_action_gate.reset()
	_weapon_action_token = 0
	_module_action_token = 0
	_pending_module_serial += 1
	charge_remaining = 0.0
	charge_duration = 0.0
	module_remaining = 0.0
	pending_module = ""
	dash_remaining = 0.0
	dash_direction = Vector3.ZERO
	_charge_lost_time = 0.0
	last_module_reason = reason
	_update_readout()


func tick(delta: float, elapsed: float, visible: bool, observed: Vector3, body: Node3D, player: Node3D, controller: Node, perception: Dictionary = {}, tuning: Dictionary = {}) -> void:
	_latest_tuning = tuning
	_last_tick_elapsed = elapsed
	_mekatana_movement_owned_this_tick = false
	if profile == "mekatana":
		_ensure_mekatana(body, controller)
		_update_mekatana(delta)
	var cooldown_rate := float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["other_cooldown_rate"]) if bio_remaining > 0.0 else 1.0
	pyro_cooldown = maxf(0.0, pyro_cooldown - delta * cooldown_rate)
	bio_cooldown = maxf(0.0, bio_cooldown - delta)
	bio_remaining = maxf(0.0, bio_remaining - delta)
	for module_id_value in module_cooldowns.keys():
		module_cooldowns[module_id_value] = maxf(0.0, float(module_cooldowns[module_id_value]) - delta * cooldown_rate)
	_javelin_mark_remaining = maxf(0.0, _javelin_mark_remaining - delta)
	if _javelin_mark_remaining <= 0.0:
		_javelin_marked_player = null
	if static_remaining > 0.0:
		static_remaining = maxf(0.0, static_remaining - delta)
		body.set_meta("duel_static_shield", static_remaining > 0.0)
		charge_remaining = 0.0
		module_remaining = 0.0
		pending_module = ""
		controller.set("_windup_remaining", 0.0)
		controller.call("_update_telegraph")
		if static_remaining <= 0.0:
			body.remove_meta("duel_static_shield")
		return
	if visible:
		_last_visible_at = elapsed
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			ammo = int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"])
		_update_readout()
	if profile == "shotgun" and ammo <= 0 and reload_remaining <= 0.0:
		_start_reload()
	var distance := body.global_position.distance_to(observed) if observed.is_finite() else INF
	# Module choices use exactly the same delayed observation as locomotion and
	# aiming. In particular, retreat/repair mobility does not need a visible foe.
	var decision_perception := perception.duplicate()
	decision_perception["visible"] = visible
	decision_perception["position"] = observed
	if not decision_perception.has("line_of_fire"):
		decision_perception["line_of_fire"] = visible and player != null and (bool(controller.call("_weapon_line_of_fire_clear", body, player, observed)) if controller.has_method("_weapon_line_of_fire_clear") else bool(controller.call("_line_of_sight_clear", body, player)))
	if module_remaining > 0.0:
		module_remaining = maxf(0.0, module_remaining - delta)
		controller.set("_windup_remaining", module_remaining)
		controller.call("_update_telegraph")
		if module_remaining <= 0.0:
			_resolve_pending_module(body, player, controller, visible)
			controller.set("_windup_remaining", 0.0)
			controller.call("_update_telegraph")
		return
	if elapsed >= _next_module_at and _consider_survival_module_use(elapsed, distance, body, controller, decision_perception, tuning):
		return
	if profile == "mekatana" and _mekatana != null and _mekatana.is_busy():
		return
	if charge_remaining > 0.0:
		if not visible or not bool(decision_perception.get("line_of_fire", false)):
			_charge_lost_time += delta
		else:
			_charge_lost_time = 0.0
		if _charge_lost_time > 0.22:
			_cancel_weapon_charge(controller, elapsed, "charge annulée : ligne perdue")
			return
		if visible and bool(decision_perception.get("line_of_fire", false)):
			_update_charge_aim(delta, body, observed, decision_perception, tuning)
		charge_remaining = maxf(0.0, charge_remaining - delta)
		controller.set("_windup_remaining", charge_remaining)
		controller.call("_update_telegraph")
		_update_readout()
		if charge_remaining <= 0.0:
			if profile == "longshot" and (not visible or not bool(decision_perception.get("line_of_fire", false))):
				_cancel_weapon_charge(controller, elapsed, "tir annulé : ligne perdue")
				return
			_fire(body, player)
			var recovery := float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["attack_recovery"]) if profile == "shotgun" else float(COMBAT_DATA.WEAPON_DEFINITIONS["blaster"]["cooldown"])
			if profile == "longshot":
				var longshot_definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS["longshot"]
				recovery = maxf(0.0, float(longshot_definition.cooldown) - float(longshot_definition.attack_preparation))
			next_attack_at = elapsed + recovery / (float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["attack_speed_multiplier"]) if bio_remaining > 0.0 else 1.0)
			controller.set("_windup_remaining", 0.0)
			controller.call("_update_telegraph")
		return
	var legacy_tick := perception.is_empty() and tuning.is_empty()
	if (elapsed >= _next_module_at or legacy_tick) and _consider_module_use(elapsed, distance, body, player, controller, decision_perception, tuning):
		return
	if profile == "mekatana":
		if elapsed >= next_attack_at and visible and observed.is_finite() and bool(decision_perception.get("line_of_fire", false)) and dash_remaining <= 0.0 and not _mekatana_movement_owned_this_tick:
			# The melee resolver owns its exact hit volume. This only decides when
			# to engage, using the same delayed observation as every other weapon.
			var engagement := get_mekatana_engagement_range()
			if distance >= engagement.x and distance <= engagement.y:
				_begin_mekatana(body, observed, decision_perception, tuning)
		return
	if profile == "shotgun" and _should_reload_tactically(visible, distance, decision_perception):
		_start_reload()
		return
	if elapsed < next_attack_at or reload_remaining > 0.0 or not visible:
		return
	if profile == "longshot" and elapsed < _longshot_next_attack_at:
		return
	var maximum := float(COMBAT_DATA.WEAPON_DEFINITIONS[profile]["max_range"])
	if distance > maximum or not bool(decision_perception.get("line_of_fire", false)):
		next_attack_at = elapsed + 0.2
		return
	var target_vulnerable := bool(perception.get("target_reloading", false)) or float(perception.get("target_health_fraction", 1.0)) < 0.16
	if profile == "shotgun" and distance > (6.0 if target_vulnerable else 5.1):
		return
	_decision_serial += 1
	# Sometimes the bot fails to use a short opening even when its weapon is ready.
	var skill := float(tuning.get("position_quality", 0.68))
	if randf() < lerpf(0.12, 0.015, clampf(skill, 0.0, 1.0)):
		next_attack_at = elapsed + 0.18
		return
	if profile == "blaster":
		var favorable_charge := distance >= 4.5 and distance <= 12.5 and Vector3(perception.get("velocity", Vector3.ZERO)).length() < 6.0 and not bool(perception.get("projectile_threat", false))
		var long_opening := bool(perception.get("target_reloading", false)) or Vector3(perception.get("velocity", Vector3.ZERO)).length() < 1.5
		charge_duration = clampf((0.87 if long_opening else 0.66) + randf_range(-0.09, 0.10), 0.50, float(COMBAT_DATA.WEAPON_DEFINITIONS["blaster"]["charge_time"])) if favorable_charge and _decision_serial % 4 != 0 else 0.05
	elif profile == "longshot":
		charge_duration = float(COMBAT_DATA.WEAPON_DEFINITIONS["longshot"]["attack_preparation"]) / (float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["attack_speed_multiplier"]) if bio_remaining > 0.0 else 1.0)
	else:
		charge_duration = float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["attack_preparation"])
	var aim_error := deg_to_rad(float(tuning.get("aim_error_degrees", 4.5)) * (1.15 if profile == "shotgun" else 1.0))
	_aim_error_angle = randf_range(-aim_error, aim_error)
	_aim_position = _predicted_aim(body, observed, decision_perception, tuning, charge_duration)
	if not _begin_weapon_action():
		return
	charge_remaining = charge_duration
	_charge_lost_time = 0.0
	controller.set("_windup_remaining", charge_remaining)
	controller.call("_update_telegraph")
	_update_readout()


func _ensure_mekatana(body: Node3D, controller: Node) -> void:
	if _mekatana == null or _mekatana_body != body:
		_cancel_mekatana()
		_mekatana = MEKATANA_ATTACK.new()
		_mekatana.target_mask = 4 # Preserve bot weapon filtering: only player hurtboxes.
		_mekatana_body = body
		_mekatana.configure(body, "duel_bot", Callable(self, "_move_mekatana"))
		_mekatana.slash_started.connect(_on_mekatana_slash_started)
		_mekatana.hit.connect(_on_mekatana_hit)
		_mekatana.finished.connect(_on_mekatana_finished)
	_mekatana_controller = controller


func _begin_mekatana(body: Node3D, observed: Vector3, perception: Dictionary = {}, tuning: Dictionary = {}) -> bool:
	if profile != "mekatana" or body == null or not is_instance_valid(body):
		return false
	if body.has_method("is_action_locked") and bool(body.call("is_action_locked")):
		return false
	if static_remaining > 0.0 or dash_remaining > 0.0:
		return false
	_ensure_mekatana(body, _mekatana_controller)
	if _mekatana.is_busy() or not _begin_weapon_action():
		return false
	var direction: Vector3 = observed - body.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = -body.global_basis.z
	# Short, bounded anticipation uses observed velocity, never the hidden live
	# target. Once the swing starts this direction remains committed.
	var velocity: Vector3 = perception.get("velocity", Vector3.ZERO)
	velocity.y = 0.0
	var anticipation: Vector3 = (velocity * minf(0.16, float(tuning.get("reaction_delay", 0.22))) * float(tuning.get("prediction_quality", 0.62))).limit_length(0.55)
	direction += anticipation
	var aim_error := deg_to_rad(float(tuning.get("aim_error_degrees", 3.6)))
	direction = direction.normalized().rotated(Vector3.UP, randf_range(-aim_error, aim_error))
	var tempo := float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"].attack_speed_multiplier) if bio_remaining > 0.0 else 1.0
	if not _mekatana.start(direction, 1.0, tempo):
		_release_weapon_action()
		return false
	_mekatana_movement_owned_this_tick = true
	_aim_position = body.global_position + _mekatana.direction * 3.0
	_sync_mekatana_pose()
	return true


func _update_mekatana(delta: float) -> void:
	if _mekatana == null:
		return
	if not is_instance_valid(_mekatana_body) or (_mekatana_body.has_method("is_action_locked") and bool(_mekatana_body.call("is_action_locked"))):
		_cancel_mekatana()
		return
	if _mekatana.is_busy() and not _action_gate.owns(_weapon_action_token, ACTION_GATE.Kind.WEAPON, "mekatana"):
		_cancel_mekatana()
		return
	_mekatana_movement_owned_this_tick = _mekatana.is_direction_locked()
	_mekatana.update(delta)
	_mekatana_movement_owned_this_tick = _mekatana_movement_owned_this_tick or _mekatana.is_direction_locked()
	_sync_mekatana_pose()


func _move_mekatana(motion: Vector3) -> Vector3:
	if _mekatana_body == null or not is_instance_valid(_mekatana_body):
		return Vector3.ZERO
	var safe := Vector3(_mekatana_controller.call("_safe_bot_motion", _mekatana_body, motion)) if is_instance_valid(_mekatana_controller) and _mekatana_controller.has_method("_safe_bot_motion") else _safe_dash_motion(_mekatana_body, motion)
	var previous := _mekatana_body.global_position
	var destination := previous + safe
	destination.x = clampf(destination.x, -27.0, 27.0)
	destination.z = clampf(destination.z, -27.0, 27.0)
	destination.y = 0.0
	_mekatana_body.global_position = destination
	return destination - previous


func _sync_mekatana_pose() -> void:
	if _mekatana_body == null or not is_instance_valid(_mekatana_body):
		return
	if _mekatana != null and _mekatana.is_busy() and _mekatana_body.has_method("set_mekatana_pose"):
		if _mekatana_body.has_method("set_mekatana_direction"):
			_mekatana_body.call("set_mekatana_direction", _mekatana.direction)
		_mekatana_body.call("set_mekatana_pose", _mekatana.step, _mekatana.phase, _mekatana.progress())
	elif _mekatana_body.has_method("clear_mekatana_pose"):
		_mekatana_body.call("clear_mekatana_pose")


func _on_mekatana_slash_started(rank: int) -> void:
	# Phase boundaries can be crossed inside one slow simulation frame. Publish
	# the active transition before recovery so the weapon emits its slash sound.
	if is_instance_valid(_mekatana_body) and _mekatana_body.has_method("set_mekatana_pose"):
		_mekatana_body.call("set_mekatana_pose", rank, "active", 0.0)


func _on_mekatana_hit(target: Node, applied: float, multiplier: float) -> void:
	if applied <= 0.0:
		return
	_register_damage(_mekatana_body, applied)
	if target is Node3D and is_instance_valid(_mekatana_body) and _mekatana_body.has_method("set_mekatana_impact"):
		_mekatana_body.call("set_mekatana_impact", target, multiplier)


func _on_mekatana_finished() -> void:
	_release_weapon_action()
	_sync_mekatana_pose()


func _cancel_mekatana() -> void:
	if _mekatana != null:
		_mekatana.cancel()
	if _action_gate.owns(_weapon_action_token, ACTION_GATE.Kind.WEAPON, "mekatana"):
		_release_weapon_action()
	_mekatana_movement_owned_this_tick = false
	if is_instance_valid(_mekatana_body) and _mekatana_body.has_method("clear_mekatana_pose"):
		_mekatana_body.call("clear_mekatana_pose")


func _predicted_aim(body: Node3D, observed: Vector3, perception: Dictionary, tuning: Dictionary, release_delay: float, projectile_speed: float = 0.0) -> Vector3:
	var speed := projectile_speed
	if speed <= 0.0:
		speed = float(COMBAT_DATA.WEAPON_DEFINITIONS[profile].get("pellet_speed" if profile == "shotgun" else "projectile_speed", 24.0))
		if profile == "longshot" and longshot_state.next_enhanced():
			speed *= float(COMBAT_DATA.WEAPON_DEFINITIONS["longshot"]["enhanced_speed_multiplier"])
	var velocity := Vector3(perception.get("velocity", Vector3.ZERO))
	velocity.y = 0.0
	velocity = velocity.limit_length(10.0)
	var quality := clampf(float(tuning.get("prediction_quality", 0.62)), 0.0, 0.95)
	# Extrapolate the delayed sample, then estimate travel once more. Both are
	# bounded: a sudden dodge still breaks this estimate until it is perceived.
	var delay := minf(0.5, float(tuning.get("reaction_delay", 0.22))) + maxf(0.0, release_delay)
	var travel := body.global_position.distance_to(observed) / maxf(1.0, speed)
	var lead := (velocity * (delay + travel) * quality).limit_length(4.0)
	travel = body.global_position.distance_to(observed + lead) / maxf(1.0, speed)
	lead = (velocity * (delay + travel) * quality).limit_length(4.0)
	var direction := observed + lead - body.global_position
	direction.y = 0.0
	return body.global_position + direction.rotated(Vector3.UP, _aim_error_angle)


func _update_charge_aim(delta: float, body: Node3D, observed: Vector3, perception: Dictionary, tuning: Dictionary) -> void:
	# Commit the last instants of the shot instead of snapping to a new sample
	# on the release frame. A consistent per-shot error prevents perfect aim.
	if charge_remaining <= (0.035 if profile == "shotgun" else 0.055):
		return
	var desired := _predicted_aim(body, observed, perception, tuning, charge_remaining)
	var current_direction := _aim_position - body.global_position
	var desired_direction := desired - body.global_position
	current_direction.y = 0.0
	desired_direction.y = 0.0
	if current_direction.length_squared() < 0.001 or desired_direction.length_squared() < 0.001:
		return
	var quality := clampf(float(tuning.get("position_quality", 0.68)), 0.0, 1.0)
	var turn_limit := deg_to_rad(lerpf(72.0, 150.0, quality)) * maxf(0.0, delta)
	var turn := current_direction.signed_angle_to(desired_direction, Vector3.UP)
	current_direction = current_direction.normalized().rotated(Vector3.UP, clampf(turn, -turn_limit, turn_limit))
	_aim_position = body.global_position + current_direction * desired_direction.length()


func _should_reload_tactically(visible: bool, distance: float, perception: Dictionary) -> bool:
	var magazine := int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"])
	if ammo <= 0 or ammo >= magazine or reload_remaining > 0.0 or charge_remaining > 0.0:
		return false
	# Top up a partial magazine while traversing cover, rather than discovering
	# an empty weapon when the next close-range opportunity appears.
	var hidden := not visible and float(perception.get("memory_age", 0.0)) > 0.55
	var retreating := str(perception.get("intent", "maintain")) in ["seek_heal", "seek_repair", "retreat", "break_line"]
	var safe_range := distance > 7.5 or not bool(perception.get("line_of_fire", false))
	return hidden or (retreating and safe_range) or (ammo == 1 and distance > 10.0)


func _consider_survival_module_use(elapsed: float, distance: float, body: Node3D, controller: Node, perception: Dictionary, tuning: Dictionary) -> bool:
	var skill := float(tuning.get("module_skill", 0.66))
	var intent := str(perception.get("intent", "maintain"))
	var health := float(perception.get("bot_health_fraction", 1.0))
	var incoming := bool(perception.get("projectile_threat", false))
	var impact_time := float(perception.get("threat_time", INF))
	var charged_threat := bool(perception.get("target_charging", false)) and bool(perception.get("target_aiming_at_bot", true)) and bool(perception.get("line_of_fire", false))
	var urgent := incoming and impact_time < 0.65
	var escape_direction := Vector3(perception.get("dodge_direction", Vector3.ZERO))
	if urgent and impact_time > 0.12 and skill >= 0.45 and mobility_id == "pyro_boots" and _try_tactical_dash(body, controller, escape_direction):
		last_module_reason = "dash latéral pour éviter le projectile perçu"
		_next_module_at = elapsed + 0.45
		return true
	var use_defense := (urgent and (impact_time < 0.35 or health < 0.70)) or (charged_threat and (health < 0.52 or skill >= 0.75))
	# Stasis roots its user. Reserve it for an actual impact or an exposed
	# charge when escape is unavailable, rather than freezing on every windup.
	if defensive_id == "static_shield":
		use_defense = (incoming and impact_time < 0.30) or (charged_threat and health < 0.40 and distance < 9.0)
	elif incoming and impact_time < 0.10:
		use_defense = false
	if use_defense and _module_ready(defensive_id) and _begin_module_action(defensive_id):
		if defensive_id == "static_shield":
			_activate_static_shield(body)
			last_module_reason = "stase avant le projectile imminent"
		else:
			var toward := -Vector3(perception.get("threat_direction", Vector3.ZERO)) if incoming else Vector3(perception.get("position", body.global_position)) - body.global_position
			_activate_magnetic_field(body, toward)
			last_module_reason = "mur magnétique face à la menace perçue"
		_release_module_action(defensive_id)
		_next_module_at = elapsed + 0.60
		return true
	var retreating := intent in ["retreat", "break_line", "seek_heal", "seek_repair"]
	var destination := Vector3(perception.get("destination", body.global_position))
	var toward_destination := destination - body.global_position
	toward_destination.y = 0.0
	if retreating and toward_destination.length_squared() < 0.25 and bool(perception.get("known", false)):
		toward_destination = body.global_position - Vector3(perception.get("position", body.global_position))
	var repair_trip := intent in ["seek_heal", "seek_repair"] and toward_destination.length() > 4.5
	var escape_needed := retreating and (distance < 7.0 or health < 0.38 or repair_trip)
	if mobility_id == "pyro_boots" and escape_needed and toward_destination.length() > 2.2 and _try_tactical_dash(body, controller, toward_destination):
		last_module_reason = "dash vers le soin" if repair_trip else "dash vers un couvert sûr"
		_next_module_at = elapsed + 0.65
		return true
	var flank_trip := intent in ["flank", "control_repair"] and toward_destination.length() > 6.0
	if mobility_id == "bio_injector" and _module_ready("bio_injector") and bio_remaining <= 0.0 and (escape_needed or flank_trip):
		if _begin_module_action("bio_injector"):
			bio_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["duration"])
			_start_module_cooldown("bio_injector")
			_release_module_action("bio_injector")
			last_module_reason = "accélération vers le soin ou le couvert" if retreating else "accélération pour prendre l'angle"
			_next_module_at = elapsed + 0.75
			return true
	return false


func _try_tactical_dash(body: Node3D, controller: Node, requested: Vector3) -> bool:
	if mobility_id != "pyro_boots" or not _module_ready("pyro_boots") or is_dashing():
		return false
	requested.y = 0.0
	if requested.length_squared() < 0.01:
		return false
	var dash_length := float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["dash_distance"])
	for angle in [0.0, 25.0, -25.0, 50.0, -50.0]:
		var direction := requested.normalized().rotated(Vector3.UP, deg_to_rad(float(angle)))
		var motion := direction * dash_length
		var destination := body.global_position + motion
		if absf(destination.x) > 26.0 or absf(destination.z) > 26.0:
			continue
		var safe := Vector3(controller.call("_safe_bot_motion", body, motion)) if controller.has_method("_safe_bot_motion") else _safe_dash_motion(body, motion)
		if safe.length_squared() < motion.length_squared() * 0.96:
			continue
		if not _begin_module_action("pyro_boots"):
			return false
		_start_dash(direction)
		_start_module_cooldown("pyro_boots")
		_release_module_action("pyro_boots")
		return true
	return false


func _consider_module_use(elapsed: float, distance: float, body: Node3D, player: Node3D, controller: Node, perception: Dictionary, tuning: Dictionary) -> bool:
	var module_skill := float(tuning.get("module_skill", 0.66))
	var intent := str(perception.get("intent", "maintain"))
	var visible := bool(perception.get("visible", false))
	if _consider_survival_module_use(elapsed, distance, body, controller, perception, tuning):
		return true
	if _javelin_marked_player == player and _javelin_mark_remaining > 0.0 and visible_and_valid(player, perception):
		if _begin_module_action("javelin_recast"):
			var recast_succeeded := _try_javelin_recast(body, player, perception, controller)
			_release_module_action("javelin_recast")
			if not recast_succeeded:
				return false
			last_module_reason = "javelin réactivé pour prendre l'angle"
			_next_module_at = elapsed + 0.75
			return true
	if visible and mobility_id == "pyro_boots" and _module_ready("pyro_boots") and not is_dashing():
		var closing_intent := intent in ["pressure", "engage"] or (profile == "shotgun" and intent == "maintain")
		# Save the escape while vulnerable, and never dash across a wall just
		# because the target is visible through another firing angle.
		var healthy := float(perception.get("bot_health_fraction", 1.0)) > 0.40
		if closing_intent and healthy and reload_remaining <= 0.0 and distance > (3.8 if profile == "shotgun" else 9.5):
			var direction := Vector3(perception.get("position", body.global_position)) - body.global_position
			if _try_tactical_dash(body, controller, direction):
				last_module_reason = "dash pour exploiter la distance"
				_next_module_at = elapsed + 0.65
				return true
	if visible and mobility_id == "bio_injector" and _module_ready("bio_injector") and bio_remaining <= 0.0 and intent in ["pressure", "engage", "maintain"] and distance < 11.0:
		if not _begin_module_action("bio_injector"):
			return false
		bio_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["duration"])
		bio_cooldown = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["cooldown"])
		_start_module_cooldown("bio_injector")
		_release_module_action("bio_injector")
		last_module_reason = "fenêtre d'attaque prolongée"
		_next_module_at = elapsed + 0.75
		return true
	if not visible or not _module_ready(offensive_id) or not bool(perception.get("line_of_fire", false)) or intent in ["retreat", "break_line", "seek_heal", "seek_repair"]:
		return false
	if module_skill < 0.50 and (_module_serial + 1) % 3 != 0:
		_module_serial += 1
		return false
	match offensive_id:
		"modulo_drone":
			if distance <= float(COMBAT_DATA.MODULE_DEFINITIONS[offensive_id]["max_range"]):
				if _begin_pending_module(offensive_id, float(COMBAT_DATA.MODULE_DEFINITIONS[offensive_id]["preparation"]), perception, controller):
					last_module_reason = "drone pendant une ligne de tir stable"
					_next_module_at = elapsed + 0.70
					return true
		"javelin":
			if distance <= float(COMBAT_DATA.MODULE_DEFINITIONS[offensive_id]["max_range"]):
				if _begin_pending_module(offensive_id, float(COMBAT_DATA.MODULE_DEFINITIONS[offensive_id]["preparation"]), perception, controller):
					last_module_reason = "javelin pour dégâts et repositionnement"
					_next_module_at = elapsed + 0.70
					return true
		"fulguro_punch":
			var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS[offensive_id]
			var punish_window := bool(perception.get("target_reloading", false)) or bool(perception.get("target_charging", false)) or Vector3(perception.get("velocity", Vector3.ZERO)).length() < 2.5
			if distance <= float(definition["range_max"]) + 0.5 and (distance < 2.6 or punish_window):
				var ratio := clampf(inverse_lerp(float(definition["range_min"]), float(definition["range_max"]), distance - 0.7), 0.0, 1.0)
				if _begin_pending_module(offensive_id, lerpf(float(definition["charge_min"]), float(definition["charge_max"]), ratio), perception, controller):
					last_module_reason = "fulguro à portée de projection"
					_next_module_at = elapsed + 0.85
					return true
		"pelto_smash":
			var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS[offensive_id]
			if distance <= float(definition["max_range"]):
				if _begin_pending_module(offensive_id, float(definition["preparation"]), perception, controller):
					last_module_reason = "pelto pour ralentir et préparer le tir"
					_next_module_at = elapsed + 0.85
					return true
	return false


func visible_and_valid(player: Node3D, perception: Dictionary) -> bool:
	return bool(perception.get("visible", false)) and player != null and is_instance_valid(player) and (not player.has_method("is_real_dead") or not bool(player.call("is_real_dead")))


func _module_ready(module_id: String) -> bool:
	return module_id != "" and float(module_cooldowns.get(module_id, 0.0)) <= 0.0


func get_module_cooldown(module_id: String) -> float:
	return maxf(0.0, float(module_cooldowns.get(module_id, 0.0)))


func _start_module_cooldown(module_id: String) -> void:
	module_cooldowns[module_id] = float(COMBAT_DATA.MODULE_DEFINITIONS[module_id].get("cooldown", 0.0))
	if module_id == "pyro_boots":
		pyro_cooldown = float(module_cooldowns[module_id])
	elif module_id == "bio_injector":
		bio_cooldown = float(module_cooldowns[module_id])


func _begin_pending_module(module_id: String, duration: float, perception: Dictionary, controller: Node) -> bool:
	if not _begin_module_action(module_id):
		return false
	pending_module = module_id
	module_remaining = maxf(0.01, duration)
	_module_aim_position = Vector3(perception.get("position", Vector3.ZERO))
	var body := get_parent().get_parent() as Node3D if get_parent() != null else null
	if body != null:
		var error := deg_to_rad(float(_latest_tuning.get("aim_error_degrees", 4.5)))
		_aim_error_angle = randf_range(-error, error)
		var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS[module_id]
		var speed := float(definition.get("speed", definition.get("outbound_speed", 16.0)))
		_module_aim_position = _predicted_aim(body, _module_aim_position, perception, _latest_tuning, duration, speed)
	_module_serial += 1
	_pending_module_serial = _module_serial
	_start_module_cooldown(module_id)
	charge_remaining = 0.0
	controller.set("_windup_remaining", module_remaining)
	controller.call("_update_telegraph")
	return true


func _resolve_pending_module(body: Node3D, player: Node3D, controller: Node, visible: bool) -> void:
	var module_id := pending_module
	var action_token := _module_action_token
	var attack_serial := _pending_module_serial
	pending_module = ""
	if module_id == "" or not _module_action_valid(module_id, action_token):
		return
	if module_id in ["modulo_drone", "javelin"]:
		_fire_module_projectile(module_id, body, player, _module_aim_position, attack_serial)
	elif controller.has_method("execute_duel_offensive"):
		controller.call("execute_duel_offensive", module_id, body, player, _module_aim_position, visible)
	_release_module_action(module_id, action_token)
	next_attack_at = maxf(next_attack_at, _last_tick_elapsed + 0.25)


func _cancel_weapon_charge(controller: Node, elapsed: float, reason: String) -> void:
	charge_remaining = 0.0
	charge_duration = 0.0
	_charge_lost_time = 0.0
	_release_weapon_action()
	next_attack_at = elapsed + 0.18
	last_module_reason = reason
	controller.set("_windup_remaining", 0.0)
	controller.call("_update_telegraph")
	_update_readout()


func _activate_static_shield(body: Node3D) -> void:
	static_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["static_shield"]["duration"])
	body.set_meta("duel_static_shield", true)
	_start_module_cooldown("static_shield")
	charge_remaining = 0.0
	# Match the player's stasis interruption: a dash cannot resume from an
	# obsolete escape direction when the shield ends.
	dash_remaining = 0.0
	dash_direction = Vector3.ZERO
	module_remaining = 0.0
	pending_module = ""
	var visual := MeshInstance3D.new()
	visual.name = "BotStaticShield"
	var mesh := SphereMesh.new()
	mesh.radius = 1.12
	mesh.height = 2.05
	visual.mesh = mesh
	visual.position = Vector3(0.0, 0.95, 0.0)
	visual.material_override = _fx_material(Color("#b18dff"), 0.22)
	body.add_child(visual)
	var tween := visual.create_tween()
	tween.tween_property(visual, "transparency", 1.0, static_remaining)
	tween.tween_callback(visual.queue_free)


func _activate_magnetic_field(body: Node3D, toward: Vector3) -> void:
	var direction := toward
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["magnetic_field"]
	var wall := Area3D.new()
	wall.name = "MagneticField"
	wall.collision_layer = 8
	wall.collision_mask = 0
	wall.monitoring = false
	wall.monitorable = true
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(definition["width"]), float(definition["height"]), 0.14)
	collision.shape = shape
	collision.position.y = float(definition["height"]) * 0.5
	wall.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(definition["width"]), float(definition["height"]), 0.10)
	visual.mesh = mesh
	visual.position.y = float(definition["height"]) * 0.5
	visual.material_override = _fx_material(Color("#53d9e5"), 0.38)
	wall.add_child(visual)
	get_tree().current_scene.add_child(wall)
	wall.global_position = body.global_position + direction * float(definition["distance"])
	wall.rotation.y = atan2(direction.x, direction.z)
	_magnetic_wall = wall
	_start_module_cooldown("magnetic_field")
	get_tree().create_timer(float(definition["duration"]), false, false, false).timeout.connect(func() -> void:
		if is_instance_valid(wall):
			wall.queue_free()
		if _magnetic_wall == wall:
			_magnetic_wall = null
	)


func _fire_module_projectile(module_id: String, body: Node3D, player: Node3D, target_position: Vector3, attack_serial: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS[module_id]
	var muzzle := body.global_position + Vector3.UP * 0.90
	if body.has_method("prepare_training_bot_shot"):
		muzzle = (body.call("prepare_training_bot_shot", target_position + Vector3.UP * 0.90) as Transform3D).origin
	var direction := target_position + Vector3.UP * 0.90 - muzzle
	if direction.length_squared() < 0.001:
		return
	direction = direction.normalized()
	var maximum := float(definition["max_range"])
	var generation := _generation
	var projectile := LIVE_PROJECTILE.new()
	projectile.name = "DuelBotModuloDrone" if module_id == "modulo_drone" else "DuelBotJavelin"
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = muzzle
	projectile.configure(direction, float(definition.speed), maximum, 1 | 4 | 8, [body.get_rid()])
	projectile.set_meta("ai_projectile_source", body.get_instance_id())
	projectile.set_meta("ai_projectile_velocity", direction * float(definition.speed))
	projectile.set_meta("ai_projectile_endpoint", muzzle + direction * maximum)
	projectile.set_meta("ai_projectile_radius", 0.16 if module_id == "modulo_drone" else 0.10)
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16 if module_id == "modulo_drone" else 0.10
	mesh.height = mesh.radius * 2.0
	visual.mesh = mesh
	visual.material_override = _fx_material(Color("#45ddff") if module_id == "modulo_drone" else Color("#ffe48b"), 0.96)
	projectile.add_child(visual)
	projectile.finished.connect(func(hit: Dictionary, _distance: float) -> void:
		if generation == _generation and hit.get("collider") == player:
			_resolve_module_projectile(module_id, body, player, hit.position, attack_serial)
	)


func _resolve_module_projectile(module_id: String, body: Node3D, player: Node3D, endpoint: Vector3, attack_serial: int) -> void:
	if player == null or not is_instance_valid(player) or body == null or not is_instance_valid(body):
		return
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS[module_id]
	var dealt := float(player.call("take_damage", float(definition["damage"]), "duel_bot", "duel_bot:%s:%d" % [module_id, attack_serial]))
	_register_damage(body, dealt)
	if dealt <= 0.0:
		return
	if module_id == "modulo_drone":
		if player.has_method("apply_burn"):
			player.call("apply_burn", float(definition["burn_duration"]), COMBAT_DATA.BURN_DAMAGE_PER_SECOND, "duel_bot:modulo_drone")
		if player.has_method("apply_spotted"):
			player.call("apply_spotted", float(definition["spotted_duration"]), "duel_bot:modulo_drone")
	else:
		_javelin_marked_player = player
		_javelin_mark_remaining = float(definition["mark_duration"])


func _try_javelin_recast(body: Node3D, _player: Node3D, perception: Dictionary, controller: Node = null) -> bool:
	var observed := Vector3(perception.get("position", body.global_position))
	if body.global_position.distance_to(observed) > float(COMBAT_DATA.MODULE_DEFINITIONS["javelin"]["max_range"]):
		return false
	var away := body.global_position - observed
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	var destination := observed + side * float(COMBAT_DATA.MODULE_DEFINITIONS["javelin"]["teleport_distance"])
	destination.y = 0.0
	if absf(destination.x) > 23.0 or absf(destination.z) > 23.0:
		return false
	var motion := destination - body.global_position
	var safe := Vector3(controller.call("_safe_bot_motion", body, motion)) if controller != null and controller.has_method("_safe_bot_motion") else _safe_dash_motion(body, motion)
	if safe.length_squared() < motion.length_squared() * 0.96:
		return false
	body.global_position = destination
	_mark_combat_event(body)
	_javelin_mark_remaining = 0.0
	_javelin_marked_player = null
	return true


func intercept_damage(amount: float, current_health: float) -> Dictionary:
	var was_baroud_active: bool = bool(_passive_state.baroud_active)
	var result: Dictionary = _passive_state.intercept_damage(amount, current_health)
	var apply_to_health: bool = not was_baroud_active and not bool(result.get("triggered_baroud", false))
	if was_baroud_active and bool(result.get("real_death", false)):
		apply_to_health = true
	return {
		"effective": float(result.get("effective", 0.0)),
		"triggered_baroud": bool(result.get("triggered_baroud", false)),
		"real_death": bool(result.get("real_death", false)),
		"apply_to_health": apply_to_health,
	}


func _register_damage(body: Node3D, effective_damage: float) -> void:
	if effective_damage <= 0.0 or body == null or not is_instance_valid(body):
		return
	_mark_combat_event(body)
	if passive_id != "omnivamp":
		return
	if body.has_method("heal"):
		body.call("heal", body.combat_state.passive.omnivamp_heal_for(effective_damage) if body.combat_state.get("passive") != null else _passive_state.omnivamp_heal_for(effective_damage), "duel_bot:omnivamp")


func register_damage(body: Node3D, effective_damage: float) -> void:
	_register_damage(body, effective_damage)


func _fx_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.32
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.1
	return material


func advance_dash(body: Node3D, controller: Node, delta: float) -> void:
	if dash_remaining <= 0.0:
		return
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]
	var step := float(definition["dash_distance"]) * minf(delta, dash_remaining) / float(definition["dash_duration"])
	var safe_step := Vector3(controller.call("_safe_bot_motion", body, dash_direction * step)) if controller != null and controller.has_method("_safe_bot_motion") else _safe_dash_motion(body, dash_direction * step)
	body.global_position += safe_step
	body.global_position.y = 0.0
	dash_remaining = maxf(0.0, dash_remaining - delta)
	if safe_step.length_squared() + 0.0001 < step * step:
		dash_remaining = 0.0


func _safe_dash_motion(body: Node3D, motion: Vector3) -> Vector3:
	var world := body.get_world_3d()
	if world == null:
		return motion
	var collision: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D:
			collision = child as CollisionShape3D
			break
	if collision == null or collision.shape == null:
		return Vector3.ZERO
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.motion = motion
	query.margin = 0.04
	query.collision_mask = 1 | 8
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [body.get_rid()]
	var cast := world.direct_space_state.cast_motion(query)
	return motion * cast[0] if cast.size() >= 2 else Vector3.ZERO


func _start_dash(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	dash_direction = direction.normalized()
	dash_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["dash_duration"])
	pyro_cooldown = float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["cooldown"])


func _start_reload() -> void:
	reload_remaining = float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["reload_duration"])
	_update_readout()


func _fire(body: Node3D, player: Node3D) -> void:
	if profile == "longshot" and (_last_tick_elapsed < maxf(next_attack_at, _longshot_next_attack_at) or static_remaining > 0.0 or not is_instance_valid(body) or not is_instance_valid(player)):
		return
	if not _action_gate.owns(_weapon_action_token, ACTION_GATE.Kind.WEAPON, profile):
		if _action_gate.is_busy():
			return
		_weapon_action_token = _action_gate.try_acquire(ACTION_GATE.Kind.WEAPON, profile, Engine.get_physics_frames(), true)
		if _weapon_action_token == 0:
			return
	if profile == "shotgun":
		if ammo <= 0:
			_release_weapon_action()
			return
		ammo -= 1
	_shot_serial += 1
	var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS[profile]
	var aim_target := _aim_position + Vector3.UP * 0.9
	if aim_target.distance_squared_to(body.global_position) < 0.01:
		_release_weapon_action()
		return
	var muzzle := body.global_position + Vector3.UP * 0.9
	var muzzle_direction := (aim_target - muzzle).normalized()
	if body.has_method("prepare_training_bot_shot"):
		var shot_transform: Transform3D = body.call("prepare_training_bot_shot", aim_target)
		if profile == "longshot" and body.has_method("get_training_bot_muzzle_transform"):
			# Keep the GLB muzzle as distance origin; its volume guard owns contact.
			shot_transform = body.call("get_training_bot_muzzle_transform")
		muzzle = shot_transform.origin
		muzzle_direction = -shot_transform.basis.z.normalized()
	if muzzle_direction.length_squared() < 0.01:
		_release_weapon_action()
		return
	muzzle_direction = muzzle_direction.normalized()
	if profile == "longshot":
		_launch_longshot(body, player, muzzle, muzzle_direction)
	elif profile == "shotgun":
		var volley := {"hits": 0, "base": 0.0}
		var angles: Array = definition["pellet_angles"]
		for index in range(angles.size()):
			_launch_projectile(body, player, muzzle, muzzle_direction.rotated(Vector3.UP, deg_to_rad(float(angles[index]))), index, volley)
		if ammo <= 0:
			_start_reload()
	else:
		_launch_projectile(body, player, muzzle, muzzle_direction, 0, {})
	_release_weapon_action()
	_update_readout()


func _launch_longshot(body: Node3D, player: Node3D, muzzle_position: Vector3, direction: Vector3) -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS["longshot"].duplicate(true)
	var enhanced: bool = longshot_state.next_enhanced()
	var speed := float(definition.projectile_speed) * (float(definition.enhanced_speed_multiplier) if enhanced else 1.0)
	var radius := float(definition.projectile_radius) * (float(definition.enhanced_size_multiplier) if enhanced else 1.0)
	var projectile := LONGSHOT_PROJECTILE.new()
	projectile.name = "DuelBotLongshot"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = muzzle_position
	projectile.look_at(muzzle_position + direction, Vector3.UP)
	var excluded: Array[RID] = [body.get_rid()]
	projectile.configure(direction, speed, float(definition.max_range), 1 | 4 | 8, excluded, radius)
	projectile.set_meta("longshot_enhanced", enhanced)
	projectile.set_meta("ai_projectile_source", body.get_instance_id())
	projectile.set_meta("ai_projectile_velocity", direction * speed)
	projectile.set_meta("ai_projectile_endpoint", muzzle_position + direction * float(definition.max_range))
	projectile.set_meta("ai_projectile_radius", radius)
	var attack_id := "duel_bot:longshot:%d:%d:%d" % [body.get_instance_id(), _longshot_generation, longshot_state.shots_fired + 1]
	projectile.finished.connect(_resolve_longshot.bind(player, body, enhanced, definition, attack_id, _longshot_generation))
	# Count only an actual projectile, before an immediate muzzle impact resolves.
	longshot_state.commit_shot()
	var recovery := maxf(0.0, float(definition.cooldown) - float(definition.attack_preparation))
	next_attack_at = _last_tick_elapsed + recovery / (float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["attack_speed_multiplier"]) if bio_remaining > 0.0 else 1.0)
	_longshot_next_attack_at = next_attack_at
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("projectile_visual", projectile, "longshot", float(enhanced))
		vfx.call("burst", muzzle_position, direction, Color("#68e9ef"), 5 if enhanced else 3, 3.2, 0.10, 0.035, 30.0)
	_update_readout()
	projectile.resolve_muzzle_guard(body.global_position + Vector3.UP * 0.9)
	return true


func _resolve_longshot(hit: Dictionary, distance: float, player: Node3D, body: Node3D, enhanced: bool, definition: Dictionary, attack_id: String, generation: int) -> void:
	if generation != _longshot_generation or hit.is_empty() or not is_instance_valid(body) or not is_instance_valid(player):
		return
	var scene := get_tree().current_scene
	var vfx := scene.get_node_or_null("VFXManager") if scene != null else null
	if vfx != null:
		vfx.call("impact", hit.position, hit.normal, vfx.call("surface_for", hit.collider), 1.1 if enhanced else 0.7, Color("#68e9ef"))
	var collider := hit.get("collider") as Node
	while collider != null and collider != player:
		collider = collider.get_parent()
	if collider != player or not player.has_method("take_damage") or not body.has_method("is_duel_mode") or not bool(body.call("is_duel_mode")) or not bool(get_parent().get("enabled")):
		return
	var damage: float = LONGSHOT_STATE.damage_at_distance(distance, enhanced, definition)
	var dealt := float(player.call("take_damage", damage, "duel_bot", attack_id))
	_register_damage(body, dealt)
	if dealt > 0.0 and player.has_method("flash_impact"):
		player.call("flash_impact", enhanced)


func reset_longshot_cycle() -> void:
	longshot_state.reset()
	_longshot_generation += 1
	_update_readout()


func _launch_projectile(body: Node3D, player: Node3D, muzzle: Vector3, direction: Vector3, pellet: int, volley: Dictionary) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS[profile]
	var maximum := float(definition["max_range"])
	var speed := float(definition["pellet_speed"] if profile == "shotgun" else definition["projectile_speed"])
	var projectile := LIVE_PROJECTILE.new()
	projectile.name = "DuelBotPellet" if profile == "shotgun" else "DuelBotBlaster"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = muzzle
	projectile.look_at(muzzle + direction, Vector3.UP)
	var excluded: Array[RID] = [body.get_rid()]
	projectile.configure(direction, speed, maximum, 1 | 4 | 8, excluded)
	projectile.set_meta("ai_projectile_source", body.get_instance_id())
	projectile.set_meta("ai_projectile_velocity", direction * speed)
	projectile.set_meta("ai_projectile_endpoint", muzzle + direction * maximum)
	projectile.set_meta("ai_projectile_radius", 0.16)
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("projectile_visual", projectile, "enemy")
		vfx.call("burst", muzzle, direction, Color("#ffbf83"), 4, 2.8, 0.10, 0.03, 30.0)
	var shot_profile := profile
	var shot_damage := float(definition["pellet_damage"]) if profile == "shotgun" else lerpf(float(definition["damage"]), float(definition["max_damage"]), clampf(charge_duration / float(definition["charge_time"]), 0.0, 1.0))
	var shot_id := "duel_bot:%d:%d" % [_shot_serial, pellet]
	projectile.finished.connect(_resolve_projectile.bind(player, body, shot_profile, shot_damage, shot_id, volley))


func _resolve_projectile(hit: Dictionary, distance: float, player: Node3D, body: Node3D, shot_profile: String, base_damage: float, shot_id: String, volley: Dictionary) -> void:
	if not is_instance_valid(player) or not is_instance_valid(body) or not player.has_method("take_damage"):
		return
	if not hit.is_empty():
		var scene := get_tree().current_scene
		var vfx := scene.get_node_or_null("VFXManager") if scene != null else null
		if vfx != null:
			vfx.call("impact", hit["position"], hit["normal"], vfx.call("surface_for", hit["collider"]), 0.75, Color("#ffbf83"))
	if hit.is_empty() or hit.get("collider") != player:
		return
	if not body.has_method("is_duel_mode") or not bool(body.call("is_duel_mode")) or not bool(get_parent().get("enabled")):
		return
	var damage := base_damage
	if shot_profile == "shotgun":
		var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]
		var ratio := clampf((distance - float(definition["falloff_start"])) / (float(definition["max_range"]) - float(definition["falloff_start"])), 0.0, 1.0)
		damage = lerpf(base_damage, float(definition["minimum_damage"]), ratio)
	var dealt := float(player.call("take_damage", damage, "duel_bot", shot_id))
	_register_damage(body, dealt)
	if dealt <= 0.0:
		return
	if shot_profile == "shotgun":
		volley["hits"] = int(volley["hits"]) + 1
		volley["base"] = float(volley["base"]) + damage
		if int(volley["hits"]) == int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["pellets_per_shot"]):
			var critical_dealt := float(player.call("take_damage", float(volley["base"]) * (COMBAT_DATA.CRIT_MULTIPLIER - 1.0), "duel_bot", shot_id + ":critical"))
			_register_damage(body, critical_dealt)
			if player.has_method("apply_burn"):
				player.call("apply_burn", COMBAT_DATA.BURN_DURATION, COMBAT_DATA.BURN_DAMAGE_PER_SECOND, "duel_bot:shotgun")


func _update_readout() -> void:
	var body := get_parent().get_parent() as Node3D if get_parent() != null else null
	if body == null or not body.has_method("is_duel_mode") or not bool(body.call("is_duel_mode")):
		return
	var visual := body.get_node_or_null("VisualRoot")
	if visual != null and visual.has_method("set_longshot_cycle"):
		visual.call("set_longshot_cycle", longshot_state.normal_shots(), longshot_state.is_enhanced_ready())
	var readout := body.get_node_or_null("TargetHealthReadout")
	if readout == null:
		return
	readout.call("update_actor_identity", Color("#ee6b4e"), build_title + " · " + LOADOUT.display_name(robot_id))
	readout.call("set_shotgun_ammo", profile == "shotgun", ammo, int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"]), reload_remaining > 0.0, 1.0 - reload_remaining / float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["reload_duration"]))
	readout.call("set_blaster_charge", profile == "blaster", charge_remaining > 0.0, 1.0 - charge_remaining / maxf(0.01, charge_duration))
	if readout.has_method("set_longshot_cycle"):
		readout.call("set_longshot_cycle", profile == "longshot", longshot_state.normal_shots(), longshot_state.is_enhanced_ready())
