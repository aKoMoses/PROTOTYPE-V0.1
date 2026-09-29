extends SceneTree

const ACTION_GATE := preload("res://scripts/action_gate.gd")
const DUEL_EQUIPMENT := preload("res://scripts/duel_bot_equipment.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_action_gate_atomicity()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player ou TargetDummy introuvable")
	else:
		target.call("set_training_bot_enabled", false)
		await _test_touch_charge_is_canceled_without_discharge(player, target)
		await _test_desktop_rearm_after_cast(player, target)
		await _test_shotgun_preparation_is_canceled(player, target)
		await _test_two_modules_and_spam(player, target)
		await _test_fulguro_during_dash(player, target)
		await _test_interruption_invalidates_old_callback(player, target)
		await _test_bot_uses_same_exclusion()
	current_scene = null
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CAST ACTION LOCK TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("CAST ACTION LOCK TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_action_gate_atomicity() -> void:
	var gate = ACTION_GATE.new()
	var weapon_token: int = gate.try_acquire(ACTION_GATE.Kind.WEAPON, "blaster", 100)
	_check(weapon_token != 0, "arbitre : arme non réservée")
	_check(gate.replace_weapon_with_module("fulguro_punch", 100) == 0 and gate.owns(weapon_token), "arbitre : deux actions acceptées dans la même frame")
	var module_token: int = gate.replace_weapon_with_module("fulguro_punch", 101)
	_check(module_token != 0 and not gate.owns(weapon_token) and gate.owns(module_token, ACTION_GATE.Kind.MODULE, "fulguro_punch"), "arbitre : remplacement atomique arme/module incorrect")
	gate.release(module_token)
	_check(gate.try_acquire(ACTION_GATE.Kind.MODULE, "pelto_smash", 101) == 0, "arbitre : deuxième action acceptée dans la même frame")
	var next_token: int = gate.try_acquire(ACTION_GATE.Kind.MODULE, "pelto_smash", 102)
	_check(next_token != 0, "arbitre : action suivante refusée après changement de frame")
	gate.reset()
	_check(not gate.release(next_token) and not gate.is_busy(), "arbitre : ancien callback a libéré un nouvel état")


func _prepare(player: Node, target: Node, weapon: String = "blaster") -> void:
	await _set_desktop_attack(false)
	player.call("set_gameplay_enabled", true)
	player.call("apply_loadout", {
		"weapon": weapon,
		"offensive": "fulguro_punch",
		"defensive": "magnetic_field",
		"mobility": "pyro_boots",
		"passive": "omnivamp",
	})
	player.call("reset_combat_state")
	player.set("training_instant_cooldowns", false)
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3.FORWARD)
	player.set("_last_move_direction", Vector3.FORWARD)
	target.call("reset_combat_state")
	target.global_position = Vector3(0.0, 0.0, 12.0)
	await physics_frame


func _set_desktop_attack(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	await physics_frame
	await process_frame


func _test_touch_charge_is_canceled_without_discharge(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("begin_touch_fire")
	await create_timer(0.28, true, false, false).timeout
	_check(bool(player.call("is_blaster_charging")), "tactile : charge blaster non amorcée")
	var shot_serial := int(player.get("_blaster_attack_token"))
	player.call("begin_touch_action", "offensive")
	_check(str(player.call("get_action_owner")) == "fulguro_punch", "charge -> cast : FULGURO n'a pas réservé l'action")
	_check(not bool(player.call("is_blaster_charging")) and not bool(player.get("_touch_fire_active")), "charge -> cast : charge tactile non annulée")
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.FORWARD)
	player.call("_activate_defensive_module")
	_check(int(player.get("_blaster_attack_token")) == shot_serial, "cast : une tentative de tir a créé un projectile")
	_check(is_zero_approx(float(player.call("get_module_cooldown", "magnetic_field"))), "cast : module concurrent a consommé son cooldown")
	player.call("_cancel_fulguro_attack", "test")
	player.call("begin_touch_fire")
	_check(not bool(player.get("_touch_fire_active")), "tactile : maintien repris automatiquement après le cast")
	_check(not bool(player.call("end_touch_fire")), "tactile : relâchement de réarmement interprété comme un tir")
	await physics_frame
	player.call("begin_touch_fire")
	_check(bool(player.get("_touch_fire_active")), "tactile : nouvelle activation refusée après relâchement")
	player.call("cancel_touch_fire")


func _test_desktop_rearm_after_cast(player: Node, target: Node) -> void:
	await _prepare(player, target)
	await _set_desktop_attack(true)
	_check(bool(player.call("is_blaster_charging")), "PC : charge non amorcée avant le cast")
	var shot_serial := int(player.get("_blaster_attack_token"))
	await physics_frame
	player.call("_begin_fulguro_charge")
	_check(not bool(player.call("is_blaster_charging")), "PC : charge non annulée à l'entrée en cast")
	player.call("_cancel_fulguro_attack", "test")
	await create_timer(0.55, true, false, false).timeout
	_check(not bool(player.call("is_blaster_charging")) and int(player.get("_blaster_attack_token")) == shot_serial, "PC : maintien interdit relancé automatiquement après le cast")
	await _set_desktop_attack(false)
	await _set_desktop_attack(true)
	_check(bool(player.call("is_blaster_charging")), "PC : nouvelle activation refusée après relâchement")
	player.call("_cancel_blaster_charge")
	await _set_desktop_attack(false)


func _test_shotgun_preparation_is_canceled(player: Node, target: Node) -> void:
	await _prepare(player, target, "shotgun")
	var ammo_before := int(player.call("get_shotgun_ammo"))
	player.call("set_touch_attack_held", true)
	player.call("_update_attack")
	_check(bool(player.get("_shotgun_attack_busy")), "shotgun : préparation non démarrée")
	await physics_frame
	player.call("begin_touch_action", "offensive")
	_check(str(player.call("get_action_owner")) == "fulguro_punch", "shotgun -> cast : FULGURO refusé")
	_check(not bool(player.get("_shotgun_attack_busy")), "shotgun -> cast : salve différée non annulée")
	_check(int(player.call("get_shotgun_ammo")) == ammo_before, "shotgun -> cast : cartouche consommée avant émission")
	player.call("_cancel_fulguro_attack", "test")
	player.call("set_touch_attack_held", false)


func _test_two_modules_and_spam(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_begin_fulguro_charge")
	var owner_before := str(player.call("get_action_owner"))
	var fulguro_token := int(player.get("_active_module_action_token"))
	player.call("_perform_magnetic_field")
	player.call("_perform_bio_injector")
	player.call("_begin_fulguro_charge")
	player.call("_perform_shotgun_attack")
	_check(owner_before == "fulguro_punch" and str(player.call("get_action_owner")) == owner_before, "modules simultanés : propriétaire du cast remplacé")
	_check(int(player.get("_active_module_action_token")) == fulguro_token, "modules simultanés : seconde activation acceptée")
	_check(is_zero_approx(float(player.call("get_module_cooldown", "magnetic_field"))) and is_zero_approx(float(player.call("get_module_cooldown", "bio_injector"))), "cast : spam module a consommé un cooldown")
	player.call("_cancel_fulguro_attack", "test")


func _test_fulguro_during_dash(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_perform_pyro_boots", Vector3.FORWARD)
	await physics_frame
	_check(bool(player.call("is_dash_active")), "dash : non actif avant FULGURO")
	player.call("_begin_fulguro_charge")
	_check(str(player.call("get_action_owner")) == "fulguro_punch", "dash : FULGURO ne démarre pas pendant le déplacement")
	_check(bool(player.call("is_dash_active")), "dash : FULGURO a annulé le dash engagé")
	player.call("_cancel_fulguro_attack", "test")


func _test_interruption_invalidates_old_callback(player: Node, target: Node) -> void:
	await _prepare(player, target)
	var old_action: int = player.call("_try_begin_module_action", "magnetic_field")
	player.set("_module_busy", true)
	player.set("_module_token", int(player.get("_module_token")) + 1)
	var old_module_token := int(player.get("_module_token"))
	player.call("apply_stun", 0.10, "cast_lock_test")
	_check(str(player.call("get_action_owner")) == "", "interruption : verrou de cast non libéré")
	var player_combat_state: Object = player.get("combat_state")
	player_combat_state.call("reset")
	await physics_frame
	player.call("_begin_fulguro_charge")
	var fresh_action := int(player.get("_active_module_action_token"))
	player.call("_create_magnetic_wall", old_module_token, old_action, Vector3(0.0, 0.0, 2.0), Vector3.FORWARD)
	_check(str(player.call("get_action_owner")) == "fulguro_punch" and int(player.get("_active_module_action_token")) == fresh_action, "interruption : ancien callback a exécuté ou libéré le nouveau cast")
	player.call("_cancel_fulguro_attack", "test")
	_check(float(player.call("get_module_cooldown", "fulguro_punch")) > 0.0, "interruption : cooldown du cast accepté perdu")
	player.call("_start_module_cooldown", "fulguro_punch", 0.0)
	await physics_frame
	player.call("_begin_fulguro_charge")
	_check(str(player.call("get_action_owner")) == "fulguro_punch", "interruption : nouvelle activation impossible")
	player.call("_cancel_fulguro_attack", "test")


func _test_bot_uses_same_exclusion() -> void:
	var equipment: Node = DUEL_EQUIPMENT.new()
	root.add_child(equipment)
	equipment.call("reset")
	equipment.set("charge_remaining", 0.4)
	_check(bool(equipment.call("_begin_weapon_action")), "bot : arme non réservée")
	await physics_frame
	_check(bool(equipment.call("_begin_module_action", "fulguro_punch")), "bot : module ne préempte pas la charge")
	_check(is_zero_approx(float(equipment.get("charge_remaining"))), "bot : charge non annulée à l'entrée en cast")
	var serial_before := int(equipment.get("_shot_serial"))
	equipment.call("_fire", null, null)
	_check(int(equipment.get("_shot_serial")) == serial_before, "bot : tir accepté pendant le cast")
	_check(not bool(equipment.call("_begin_module_action", "pelto_smash")) and str(equipment.call("get_action_owner")) == "fulguro_punch", "bot : second module accepté pendant le cast")
	equipment.call("cancel_action", "test")
	equipment.queue_free()
	await process_frame
