extends SceneTree

const CONTROLLER := preload("res://scripts/training_bot.gd")
const BUSH_STATE := preload("res://scripts/bush_state.gd")
const VISIBILITY := preload("res://scripts/visibility_state.gd")

class Actor extends StaticBody3D:
	var visibility_state := VISIBILITY.new()
	var health := 1000.0
	var duel := true
	var committed := false
	var commit_reads := 0
	var aim_direction := Vector3.FORWARD
	func get_health() -> float: return health
	func get_max_health() -> float: return 1000.0
	func is_real_dead() -> bool: return false
	func is_action_locked() -> bool: return false
	func is_duel_mode() -> bool: return duel
	func is_training_bot_enabled() -> bool: return true
	func get_slow_percent() -> float: return 0.0
	func is_revealed() -> bool: return visibility_state.is_revealed()
	func mark_combat_event() -> void: visibility_state.mark_combat_event()
	func is_visible_to(observer: Node3D) -> bool:
		return BUSH_STATE.visible_to(self, observer, is_revealed(), true)
	func is_shotgun_reloading() -> bool: return false
	func is_blaster_charging() -> bool: return committed
	func get_weapon_id() -> String: return "blaster"
	func is_attack_committed() -> bool:
		commit_reads += 1
		return committed
	func prepare_training_bot_shot(_point: Vector3) -> Transform3D:
		visibility_state.mark_combat_event()
		return Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.9)
	func take_damage(amount: float, _source: String, _attack: String) -> float:
		health -= amount
		visibility_state.mark_combat_event()
		return amount

var _failures: Array[String] = []
var _scene: Node3D
var _bot_body: Actor
var _player: Actor
var _bot: Node
var _bush: Node3D
var _shelter: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(20260930)
	_scene = Node3D.new()
	root.add_child(_scene)
	current_scene = _scene
	_bot_body = _actor("Bot", Vector3.ZERO)
	_player = _actor("Player", Vector3(10, 0, 0))
	_bush = _patch("ObservedPatch", Vector3(5, 0, 0), 1.5)
	_shelter = _patch("ShelterPatch", Vector3(-2, 0, 0), 1.8)
	_bot = CONTROLLER.new()
	_bot_body.add_child(_bot)
	_bot.call("set_enabled", true)
	_bot.set_physics_process(false)
	await physics_frame
	_bot.get("_navigation").invalidate(true)
	_test_no_unseen_occupancy()
	_test_entry_memory_and_hidden_motion()
	_test_hide_and_ambush()
	_test_full_concealment_loop()
	_test_hidden_charge_does_not_trigger_dodge()
	_test_diagnostic_visibility()
	if _failures.is_empty():
		print("BOT BUSH TACTICS TEST: PASS")
	else:
		for message in _failures:
			push_error(message)
		print("BOT BUSH TACTICS TEST: FAIL (%d)" % _failures.size())
	_scene.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _actor(actor_name: String, at: Vector3) -> Actor:
	var actor := Actor.new()
	actor.name = actor_name
	actor.position = at
	actor.collision_layer = 2
	actor.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.65
	capsule.height = 1.8
	shape_node.shape = capsule
	shape_node.position.y = 0.9
	actor.add_child(shape_node)
	_scene.add_child(actor)
	return actor


func _patch(patch_name: String, at: Vector3, radius: float) -> Node3D:
	var patch := Node3D.new()
	patch.name = patch_name
	patch.position = at
	patch.set_meta("bush_radius", radius)
	patch.set_meta("bush_height", 2.4)
	_scene.add_child(patch)
	patch.add_to_group("bush_placeholder")
	return patch


func _reset() -> void:
	_bot.call("set_enabled", true)
	_bot.set_physics_process(false)
	_bot_body.visibility_state.reset()
	_player.visibility_state.reset()
	_bot_body.position = Vector3.ZERO
	_player.position = Vector3(10, 0, 0)
	_bot_body.health = 1000.0
	_bot_body.duel = true
	_player.committed = false
	_player.commit_reads = 0
	_bot.call("set_duel_loadout", {"weapon": "blaster", "offensive": "modulo_drone", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"})
	_bot.get("_navigation").invalidate(true)


func _test_no_unseen_occupancy() -> void:
	_reset()
	_player.position = BUSH_STATE.center(_bush)
	_bot.set("_elapsed", 1.0)
	_bot.call("_observe_bush_knowledge", _bot_body, _player, false)
	_bot.call("_update_duel_perception", _bot_body, _player, false)
	_bot.call("_update_duel_decision", _bot_body, _player)
	_check(_bot.call("get_suspected_bush") == null, "a never observed hidden enemy does not disclose its occupied bush")
	_check(not bool(_bot.get("_has_last_observed_position")), "an unseen occupant supplies no exact position memory")


func _test_entry_memory_and_hidden_motion() -> void:
	_reset()
	for sample in [{"time": 0.5, "x": 3.1}, {"time": 0.85, "x": 3.15}, {"time": 0.9, "x": 3.4}]:
		_player.position = Vector3(float(sample.x), 0, 0)
		_bot.set("_elapsed", float(sample.time))
		_bot.call("_observe_bush_knowledge", _bot_body, _player, true)
		_bot.call("_update_duel_perception", _bot_body, _player, true)
	var last_seen: Vector3 = _bot.get("_last_observed_position")
	_player.position = Vector3(3.7, 0, 0)
	_bot.set("_elapsed", 0.95)
	_bot.call("_observe_bush_knowledge", _bot_body, _player, false)
	_bot.call("_update_duel_perception", _bot_body, _player, false)
	_bot.call("_update_duel_decision", _bot_body, _player)
	_check(_bot.call("get_suspected_bush") == _bush, "witnessed movement across the border remembers the entered patch")
	_check(str(_bot.call("get_current_intent")) == "search_bush", "losing the enemy in observed grass initiates a bush inspection")
	_check(Vector3(_bot.get("_last_observed_position")) == last_seen, "bush loss freezes the delayed last seen position")
	var first_goal: Vector3 = _bot.get("_bush_search_goal")
	_player.position = Vector3(6.2, 0, 0.6)
	_bot.set("_elapsed", 1.0)
	_bot.call("_observe_bush_knowledge", _bot_body, _player, false)
	_bot.call("_update_duel_perception", _bot_body, _player, false)
	var after_move: Vector3 = _bot.call("_select_bush_search_destination", _bot_body)
	_check(after_move == first_goal, "hidden relocation cannot move the chosen inspection point")
	_check(Vector3(_bot.get("_last_observed_position")) == last_seen, "hidden relocation cannot refresh position memory")
	_check(Vector3(_bot.get("_observed_velocity")) == Vector3.ZERO, "lost grass vision stops live movement extrapolation")
	var previous_goal := after_move
	_bot_body.position = after_move
	var next_goal: Vector3 = _bot.call("_select_bush_search_destination", _bot_body)
	_check(next_goal != previous_goal and BUSH_STATE.contains(_bush, next_goal), "an inspected point advances the sweep to another interior point")
	_check(_player.is_visible_to(_bot_body), "entering the same patch restores vision for both occupants")
	_bot_body.position = Vector3.ZERO
	_bot.set("_elapsed", 9.1)
	_bot.call("_observe_bush_knowledge", _bot_body, _player, false)
	_bot.call("_update_duel_perception", _bot_body, _player, false)
	_check(_bot.call("get_suspected_bush") == null, "grass occupancy memory expires instead of becoming permanent tracking")
	_check(not bool(_bot.get("_has_last_observed_position")), "exact memory also expires after losing sight")


func _test_hide_and_ambush() -> void:
	_reset()
	_bot.set("_elapsed", 1.0)
	_bot.set("_last_observed_position", _player.position)
	_bot.set("_has_last_observed_position", true)
	_bot.set("_perception", {"known": true, "visible": true, "distance": 10.0, "position": _player.position, "line_of_fire": true, "bot_health_fraction": 1.0, "target_health_fraction": 1.0, "bot_reloading": true})
	_bot.call("_update_duel_decision", _bot_body, _player)
	_check(str(_bot.call("get_current_intent")) == "hide_bush", "reloading bot chooses a reachable grass retreat")
	_check(_bot.get("_tactical_bush") == _shelter, "grass retreat avoids a patch closer to the enemy")
	var holding := bool(_bot.call("_should_hold_bush_fire", _bot_body))
	_check(holding, "bot holds fire while approaching concealment")
	var equipment: Node = _bot.get("_duel_equipment")
	equipment.call("set_loadout", {"weapon": "shotgun", "offensive": "pelto_smash", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"})
	equipment.set("ammo", 0)
	equipment.call("tick", 0.05, 1.0, not holding, _player.position, _bot_body, _player, _bot, _bot.get("_perception"), _bot.get("_tuning"))
	_check(bool(equipment.call("is_reloading")), "holding fire still advances the production equipment reload path")
	_check(str(equipment.get("pending_module")).is_empty() and is_zero_approx(float(equipment.get("charge_remaining"))), "concealment starts neither an offensive module nor a weapon charge")
	_bot_body.position = _bot.get("_tactical_destination")
	_bot_body.visibility_state.mark_combat_event()
	_check(bool(_bot.call("_should_hold_bush_fire", _bot_body)), "active combat reveal cannot trigger a concealment shot")
	_bot_body.visibility_state.update(3.1)
	_bot.set("_elapsed", 2.0)
	_check(bool(_bot.call("_should_hold_bush_fire", _bot_body)), "concealed retreat holds its fire after reveal expires")
	_bot.set("_elapsed", 7.1)
	_bot.set("_next_tactical_decision_at", 0.0)
	_bot.call("_update_duel_decision", _bot_body, _player)
	_check(str(_bot.call("get_current_intent")) != "hide_bush", "concealment has a finite deadline even when reload observation is stale")
	_reset()
	_bot.set("_elapsed", 1.0)
	_bot.set("_last_observed_position", _player.position)
	_bot.set("_has_last_observed_position", true)
	_bot.set("_perception", {"known": true, "visible": true, "distance": 10.0, "position": _player.position, "line_of_fire": true, "bot_health_fraction": 1.0, "target_health_fraction": 1.0})
	_bot.call("_update_duel_decision", _bot_body, _player)
	_check(str(_bot.call("get_current_intent")) == "ambush_bush", "healthy bot can take nearby grass for a delayed attack")
	_bot.set("_elapsed", 5.2)
	_bot.set("_next_tactical_decision_at", 0.0)
	_bot.call("_update_duel_decision", _bot_body, _player)
	_check(str(_bot.call("get_current_intent")) != "ambush_bush", "an ambush times out instead of indefinitely camping a patch")


func _test_hidden_charge_does_not_trigger_dodge() -> void:
	_reset()
	_bot_body.duel = false
	_player.position = BUSH_STATE.center(_bush)
	_player.committed = true
	_bot.call("_try_dodge", _bot_body, _player, false, false)
	_check(_player.commit_reads == 0 and is_zero_approx(float(_bot.get("_dodge_remaining"))), "training AI cannot read or dodge an unobserved hidden charge")


func _test_full_concealment_loop() -> void:
	_reset()
	_bot_body.health = 450.0
	_bot_body.visibility_state.mark_combat_event()
	_bot.call("set_duel_loadout", {"weapon": "shotgun", "offensive": "pelto_smash", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"})
	var equipment: Node = _bot.get("_duel_equipment")
	equipment.set("ammo", 0)
	var reached_grass := false
	var became_hidden := false
	var attack_during_hold := false
	var mobility_started_during_hold := false
	var concealed_intent := false
	for _step in range(90):
		var previous_bio := float(equipment.get("bio_remaining"))
		_bot_body.visibility_state.update(0.05)
		_bot.call("_physics_process", 0.05)
		concealed_intent = concealed_intent or str(_bot.call("get_current_intent")) == "hide_bush"
		reached_grass = reached_grass or BUSH_STATE.find_bush(_bot_body) == _shelter
		became_hidden = became_hidden or not _bot_body.is_visible_to(_player)
		if bool(_bot.get("_holding_bush_fire")):
			attack_during_hold = attack_during_hold or float(equipment.get("charge_remaining")) > 0.0 or not str(equipment.get("pending_module")).is_empty()
			mobility_started_during_hold = mobility_started_during_hold or float(equipment.get("bio_remaining")) > previous_bio + 0.001
	_check(concealed_intent and reached_grass, "production physics loop moves an injured reloading bot fully inside its chosen shelter")
	_check(became_hidden, "holding fire in the full loop lets combat reveal actually expire")
	_check(not attack_during_hold and not bool(equipment.call("is_reloading")), "concealment finishes the real reload without restarting offense during the hold")
	_check(not mobility_started_during_hold, "concealment does not repeatedly activate retreat mobility and reset its own plan")


func _test_diagnostic_visibility() -> void:
	_reset()
	_bot.call("set_diagnostics_enabled", true)
	_bot_body.position = BUSH_STATE.center(_shelter)
	_bot.call("_update_diagnostic_label")
	_check(not bool(_bot.get("_diagnostic_label").visible), "debug labels cannot disclose a hidden bot's position")
	_bot_body.visibility_state.mark_combat_event()
	_bot.call("_update_diagnostic_label")
	_check(bool(_bot.get("_diagnostic_label").visible), "revealed bot diagnostics remain usable")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
