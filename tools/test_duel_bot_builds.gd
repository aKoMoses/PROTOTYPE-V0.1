extends SceneTree
const BUILDS := preload("res://scripts/duel_bot_builds.gd")
const DATA := preload("res://scripts/combat_data.gd")
const STATE := preload("res://scripts/duel_bot_state.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.set("menu_mode", false)
	var player: Node3D = scene.get("player")
	var actor: Node3D = scene.get("target")
	var bot := actor.get_node("TrainingBot")
	var equipment := bot.get_node("DuelEquipment")
	actor.call("set_duel_mode", true)
	actor.call("set_training_bot_enabled", false)
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	for build in BUILDS.BUILDS:
		actor.call("set_duel_loadout", build)
		actor.call("reset_combat_state")
		actor.global_position = Vector3(0, 0, 5)
		player.global_position = Vector3(0, 0, 7)
		player.call("reset_combat_state")
		var definition: Dictionary = DATA.ROBOT_DEFINITIONS[build.robot]
		_check(is_equal_approx(float(actor.call("get_max_health")), float(definition.max_health)), "robot HP " + build.title)
		_check(actor.call("get_duel_loadout") == build, "complete loadout " + build.title)
		actor.call("take_damage", 40.0, "fixture")
		await physics_frame
		await physics_frame
		var before := float(player.call("get_health"))
		_check(bool(equipment.call("_begin_module_action", build.offensive)), "offense reserved " + build.title)
		equipment.set("pending_module", build.offensive)
		equipment.set("_module_aim_position", player.global_position)
		equipment.set("_pending_module_serial", 100)
		equipment.call("_resolve_pending_module", actor, player, bot, true)
		await create_timer(1.5).timeout
		_check(float(player.call("get_health")) < before, "offense deals damage " + build.title)
		if build.passive == "omnivamp":
			_check(float(actor.call("get_health")) > float(definition.max_health) - 40.0, "omnivamp heals " + build.title)
		actor.call("reset_combat_state")
		scene.call("clear_transient_fx")
		await physics_frame
	actor.call("set_duel_loadout", BUILDS.BUILDS[1])
	actor.call("reset_combat_state")
	equipment.call("_activate_static_shield", actor)
	_check(is_zero_approx(float(actor.call("take_damage", 60.0, "stasis"))), "stasis blocks damage")
	_check(is_zero_approx(float(actor.call("heal", 10.0, "stasis"))), "stasis blocks heal")
	equipment.call("reset")
	actor.call("take_damage", 9999.0, "baroud", "lethal")
	_check(actor.get("combat_state").passive.baroud_active and not actor.call("is_real_dead"), "Baroud delays death")
	actor.get("combat_state").update(9.0)
	_check(actor.call("is_real_dead"), "Baroud expires while bot disabled")
	actor.set("network_proxy", true)
	actor.call("set_duel_mode", false)
	_check(actor.get("combat_state").get_script() != STATE, "network proxy has no bot passive")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("DUEL BOT BUILDS TEST: PASS")
	else:
		for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _check(condition: bool, message: String) -> void:
	if not condition:failures.append(message)
