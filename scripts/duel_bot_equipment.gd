extends Node

const LOADOUT := preload("res://scripts/loadout_state.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const LIVE_PROJECTILE := preload("res://scripts/live_projectile.gd")
const PASSIVE_STATE := preload("res://scripts/passive_state.gd")
const ACTION_GATE := preload("res://scripts/action_gate.gd")

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


func set_action_gate(shared_gate) -> void:
	if shared_gate != null:
		_action_gate = shared_gate


func set_profile(value: String) -> void:
	var weapon := "shotgun" if value == "shotgun" else "blaster"
	set_loadout({
		"weapon": weapon,
		"offensive": "pelto_smash" if weapon == "shotgun" else "modulo_drone",
		"defensive": "static_shield" if weapon == "shotgun" else "magnetic_field",
		"mobility": "pyro_boots" if weapon == "shotgun" else "bio_injector",
		"passive": "baroud" if weapon == "shotgun" else "omnivamp",
	})


func set_loadout(value: Dictionary) -> void:
	robot_id = str(LOADOUT.sanitize(value).robot)
	build_title = str(value.get("title", "ADVERSAIRE"))
	profile = "shotgun" if str(value.get("weapon", profile)) == "shotgun" else "blaster"
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


func get_action_owner() -> String:
	return _action_gate.get_owner_id()


func _begin_weapon_action() -> bool:
	var token: int = _action_gate.try_acquire(ACTION_GATE.Kind.WEAPON, profile)
	if token == 0:
		return false
	_weapon_action_token = token
	return true


func _begin_module_action(module_id: String) -> bool:
	if _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		return false
	var token: int = _action_gate.replace_weapon_with_module(module_id) if _action_gate.is_kind(ACTION_GATE.Kind.WEAPON) else _action_gate.try_acquire(ACTION_GATE.Kind.MODULE, module_id)
	if token == 0:
		return false
	_weapon_action_token = 0
	_module_action_token = token
	charge_remaining = 0.0
	charge_duration = 0.0
	_charge_lost_time = 0.0
	return true


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
	if module_remaining > 0.0:
		module_remaining = maxf(0.0, module_remaining - delta)
		controller.set("_windup_remaining", module_remaining)
		controller.call("_update_telegraph")
		if module_remaining <= 0.0:
			_resolve_pending_module(body, player, controller, visible)
			controller.set("_windup_remaining", 0.0)
			controller.call("_update_telegraph")
		return
	if charge_remaining > 0.0:
		if not visible or not bool(perception.get("line_of_fire", true)):
			_charge_lost_time += delta
		else:
			_charge_lost_time = 0.0
		if _charge_lost_time > 0.22:
			_cancel_weapon_charge(controller, elapsed, "charge annulée : ligne perdue")
			return
		charge_remaining = maxf(0.0, charge_remaining - delta)
		controller.set("_windup_remaining", charge_remaining)
		controller.call("_update_telegraph")
		_update_readout()
		if charge_remaining <= 0.0:
			_fire(body, player)
			var recovery := float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["attack_recovery"]) if profile == "shotgun" else float(COMBAT_DATA.WEAPON_DEFINITIONS["blaster"]["cooldown"])
			next_attack_at = elapsed + recovery / (float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["attack_speed_multiplier"]) if bio_remaining > 0.0 else 1.0)
			controller.set("_windup_remaining", 0.0)
			controller.call("_update_telegraph")
		return
	var legacy_tick := perception.is_empty() and tuning.is_empty()
	if (elapsed >= _next_module_at or legacy_tick) and visible and _consider_module_use(elapsed, distance, body, player, controller, perception, tuning):
		return
	if elapsed < next_attack_at or reload_remaining > 0.0 or not visible:
		return
	var maximum := float(COMBAT_DATA.WEAPON_DEFINITIONS[profile]["max_range"])
	if distance > maximum or not bool(perception.get("line_of_fire", bool(controller.call("_line_of_sight_clear", body, player)))):
		next_attack_at = elapsed + 0.2
		return
	if profile == "shotgun" and distance > 4.8:
		return
	_decision_serial += 1
	# Sometimes the bot fails to use a short opening even when its weapon is ready.
	var skill := float(tuning.get("position_quality", 0.68))
	var hesitation_cycle := maxi(4, int(round(4.0 + skill * 3.0)))
	if _decision_serial % hesitation_cycle == 0:
		next_attack_at = elapsed + 0.4
		return
	var projectile_speed := float(COMBAT_DATA.WEAPON_DEFINITIONS[profile]["pellet_speed" if profile == "shotgun" else "projectile_speed"])
	var travel_time := distance / maxf(1.0, projectile_speed)
	var lead := Vector3(perception.get("velocity", Vector3.ZERO)) * travel_time * float(tuning.get("prediction_quality", 0.62))
	lead = lead.limit_length(3.0)
	var predicted := observed + lead
	var direction := predicted - body.global_position
	direction.y = 0.0
	var aim_error := deg_to_rad(float(tuning.get("aim_error_degrees", 4.5)) * (1.25 if profile == "shotgun" else 1.0))
	direction = direction.normalized().rotated(Vector3.UP, randf_range(-aim_error, aim_error))
	_aim_position = body.global_position + direction * body.global_position.distance_to(predicted)
	if profile == "blaster":
		var favorable_charge := distance >= 5.5 and distance <= 12.5 and Vector3(perception.get("velocity", Vector3.ZERO)).length() < 6.0 and bool(perception.get("line_of_fire", true))
		charge_duration = clampf(0.68 + randf_range(-0.10, 0.22), 0.50, float(COMBAT_DATA.WEAPON_DEFINITIONS["blaster"]["charge_time"])) if favorable_charge and _decision_serial % 3 != 0 else 0.05
	else:
		charge_duration = float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["attack_preparation"])
	if not _begin_weapon_action():
		return
	charge_remaining = charge_duration
	_charge_lost_time = 0.0
	controller.set("_windup_remaining", charge_remaining)
	controller.call("_update_telegraph")
	_update_readout()


func _consider_module_use(elapsed: float, distance: float, body: Node3D, player: Node3D, controller: Node, perception: Dictionary, tuning: Dictionary) -> bool:
	var module_skill := float(tuning.get("module_skill", 0.66))
	var intent := str(perception.get("intent", "maintain"))
	var threatened := bool(perception.get("target_charging", false))
	var health := float(perception.get("bot_health_fraction", 1.0))
	if _javelin_marked_player == player and _javelin_mark_remaining > 0.0 and visible_and_valid(player, perception):
		if _begin_module_action("javelin_recast"):
			var recast_succeeded := _try_javelin_recast(body, player, perception)
			_release_module_action("javelin_recast")
			if not recast_succeeded:
				return false
			last_module_reason = "javelin réactivé pour prendre l'angle"
			_next_module_at = elapsed + 0.75
			return true
	if threatened and _module_ready(defensive_id) and (health < 0.72 or module_skill >= 0.75):
		if not _begin_module_action(defensive_id):
			return false
		if defensive_id == "static_shield":
			_activate_static_shield(body)
			last_module_reason = "stase avant un impact télégraphié"
		else:
			_activate_magnetic_field(body, Vector3(perception.get("position", player.global_position)) - body.global_position)
			last_module_reason = "mur magnétique sur la ligne de tir"
		_release_module_action(defensive_id)
		_next_module_at = elapsed + 0.90
		return true
	if mobility_id == "pyro_boots" and _module_ready("pyro_boots") and not is_dashing():
		var closing_intent := intent in ["pressure", "engage"] or (profile == "shotgun" and intent == "maintain")
		if closing_intent and distance > (3.8 if profile == "shotgun" else 9.5):
			if not _begin_module_action("pyro_boots"):
				return false
			_start_dash((Vector3(perception.get("position", player.global_position)) - body.global_position).normalized())
			_start_module_cooldown("pyro_boots")
			_release_module_action("pyro_boots")
			last_module_reason = "dash pour exploiter la distance"
			_next_module_at = elapsed + 0.65
			return true
		if intent in ["retreat", "break_line"] and distance < 6.0:
			if not _begin_module_action("pyro_boots"):
				return false
			_start_dash((body.global_position - Vector3(perception.get("position", player.global_position))).normalized())
			_start_module_cooldown("pyro_boots")
			_release_module_action("pyro_boots")
			last_module_reason = "dash défensif hors de l'angle adverse"
			_next_module_at = elapsed + 0.65
			return true
	if mobility_id == "bio_injector" and _module_ready("bio_injector") and bio_remaining <= 0.0 and intent in ["pressure", "engage", "maintain"] and distance < 11.0:
		if not _begin_module_action("bio_injector"):
			return false
		bio_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["duration"])
		bio_cooldown = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["cooldown"])
		_start_module_cooldown("bio_injector")
		_release_module_action("bio_injector")
		last_module_reason = "fenêtre d'attaque prolongée"
		_next_module_at = elapsed + 0.75
		return true
	if not _module_ready(offensive_id) or not bool(perception.get("line_of_fire", false)):
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
			if distance <= float(definition["range_max"]) + 0.7:
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


func _try_javelin_recast(body: Node3D, player: Node3D, perception: Dictionary) -> bool:
	if body.global_position.distance_to(player.global_position) > float(COMBAT_DATA.MODULE_DEFINITIONS["javelin"]["max_range"]):
		return false
	var away := body.global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	var destination := player.global_position + side * float(COMBAT_DATA.MODULE_DEFINITIONS["javelin"]["teleport_distance"])
	destination.y = 0.0
	if absf(destination.x) > 23.0 or absf(destination.z) > 23.0:
		return false
	var motion := destination - body.global_position
	if _safe_dash_motion(body, motion).length_squared() < motion.length_squared() * 0.96:
		return false
	body.global_position = destination
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
	if effective_damage <= 0.0 or passive_id != "omnivamp" or body == null or not is_instance_valid(body):
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


func advance_dash(body: Node3D, _controller: Node, delta: float) -> void:
	if dash_remaining <= 0.0:
		return
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]
	var step := float(definition["dash_distance"]) * minf(delta, dash_remaining) / float(definition["dash_duration"])
	var safe_step := _safe_dash_motion(body, dash_direction * step)
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
		muzzle = shot_transform.origin
		muzzle_direction = -shot_transform.basis.z.normalized()
	if muzzle_direction.length_squared() < 0.01:
		_release_weapon_action()
		return
	muzzle_direction = muzzle_direction.normalized()
	if profile == "shotgun":
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
	var readout := body.get_node_or_null("TargetHealthReadout")
	if readout == null:
		return
	readout.call("update_actor_identity", Color("#ee6b4e"), build_title + " · " + LOADOUT.display_name(robot_id))
	readout.call("set_shotgun_ammo", profile == "shotgun", ammo, int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"]), reload_remaining > 0.0, 1.0 - reload_remaining / float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["reload_duration"]))
	readout.call("set_blaster_charge", profile == "blaster", charge_remaining > 0.0, 1.0 - charge_remaining / maxf(0.01, charge_duration))
