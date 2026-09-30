extends SceneTree

const BUILD_PRESETS := preload("res://scripts/bot_build_presets.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	var bot := target.get_node("TrainingBot")
	var equipment := bot.get_node("DuelEquipment")
	var flow := scene.get_node("Interface")
	scene.call("set_bot_build_seed", 49271)
	var build_ids := {}
	var weapons := {}
	for round_index in range(BUILD_PRESETS.PRESETS.size()):
		flow.set("round_number", round_index + 1)
		scene.call("prepare_round", {})
		var build: Dictionary = scene.call("get_current_bot_build")
		var equipped: Dictionary = scene.call("get_bot_build")
		for category in ["robot", "weapon", "offensive", "defensive", "mobility", "passive"]:
			if not equipped.has(category):
				_failures.append("bot build missing " + category)
		if str(equipped.get("title", "")) != str(build.name) or equipped != target.call("get_duel_loadout"):
			_failures.append("pause build differs from the chosen opponent")
		build_ids[str(build.id)] = true
		weapons[str(target.call("get_duel_profile"))] = true
		scene.call("prepare_round", {})
		if str(target.get_meta("bot_build_id", "")) != str(build.id):
			_failures.append("preparing the same round drew another build")
		if equipped != scene.call("get_bot_build"):
			_failures.append("preparing the same round changed the exposed build")
	if build_ids.size() != BUILD_PRESETS.PRESETS.size() or not weapons.has("blaster") or not weapons.has("shotgun"):
		_failures.append("a seeded bag did not visit distinct builds with both weapon families")
	var last: Dictionary = scene.call("get_bot_build")
	scene.call("start_duel", {})
	if last.title == scene.call("get_bot_build").title:
		_failures.append("new match repeated the same preset")
	target.call("set_duel_mode", true)
	target.global_position = Vector3(0.0, 0.0, 5.0)
	player.global_position = Vector3(0.0, 0.0, 7.0)
	player.call("set_gameplay_enabled", false)
	player.call("reset_combat_state")
	target.call("set_duel_profile", "blaster")
	target.call("set_training_bot_enabled", true)
	# Keep the real damage lifecycle enabled while isolating manual equipment
	# commands from autonomous decisions during these asynchronous assertions.
	bot.set_physics_process(false)
	bot.set("training_stationary", true)
	equipment.set("next_attack_at", 100.0)
	equipment.set("_next_module_at", 100.0)
	await physics_frame
	await physics_frame
	equipment.set("charge_duration", 1.0)
	equipment.set("_aim_position", player.global_position)
	var before := float(player.call("get_health"))
	equipment.call("_fire", target, player)
	await create_timer(0.2, true, false, false).timeout
	if float(player.call("get_health")) >= before:
		_failures.append("blaster projectile did not damage the visible target")
	if equipment.get("profile") != "blaster":
		_failures.append("blaster profile was not selected")
	# The shot is committed to its original line. Moving after launch must evade it.
	before = float(player.call("get_health"))
	equipment.set("_aim_position", player.global_position)
	equipment.call("_fire", target, player)
	player.global_position = Vector3(4.0, 0.0, 7.0)
	await create_timer(0.25, true, false, false).timeout
	if float(player.call("get_health")) < before:
		_failures.append("blaster projectile followed a moving target")
	player.global_position = Vector3(0.0, 0.0, 7.0)
	target.call("set_training_bot_enabled", false)
	target.call("set_duel_profile", "shotgun")
	target.call("set_training_bot_enabled", true)
	bot.set_physics_process(false)
	equipment.set("next_attack_at", 100.0)
	equipment.set("_next_module_at", 100.0)
	bot.set("training_stationary", true)
	await physics_frame
	await physics_frame
	if int(equipment.get("ammo")) != 3:
		_failures.append("shotgun did not start with a full magazine")
	before = float(player.call("get_health"))
	for shot in range(3):
		equipment.set("_aim_position", player.global_position)
		equipment.call("_fire", target, player)
	if int(equipment.get("ammo")) != 0 or not bool(equipment.call("is_reloading")):
		_failures.append("shotgun did not consume three shells and start reload")
	await create_timer(0.4, true, false, false).timeout
	if float(player.call("get_health")) >= before:
		_failures.append("shotgun pellets did not damage at close range")
	await create_timer(1.5, true, false, false).timeout
	equipment.call("tick", 1.9, 1.9, false, player.global_position, target, player, bot)
	if int(equipment.get("ammo")) != 3 or bool(equipment.call("is_reloading")):
		_failures.append("shotgun did not finish its shared-duration reload")
	before = float(player.call("get_health"))
	equipment.set("_aim_position", player.global_position)
	equipment.call("_fire", target, player)
	player.global_position = Vector3(4.0, 0.0, 7.0)
	await create_timer(0.25, true, false, false).timeout
	if float(player.call("get_health")) < before:
		_failures.append("shotgun pellets damaged a target that dodged after firing")
	player.global_position = Vector3(0.0, 0.0, 7.0)
	# The assaulter spends Pyro Boots to enter, then has to wait for its cooldown.
	player.global_position = Vector3(0.0, 0.0, 9.0)
	equipment.call("reset")
	equipment.set("next_attack_at", 100.0)
	await physics_frame
	equipment.call("tick", 0.02, 0.5, true, player.global_position, target, player, bot)
	if not bool(equipment.call("is_dashing")) or float(equipment.get("pyro_cooldown")) < 5.9:
		_failures.append("assaulter did not spend Pyro Boots on a close approach")
	var dash_start := target.global_position
	equipment.call("advance_dash", target, bot, 0.18)
	if target.global_position.distance_to(dash_start) < 2.5:
		_failures.append("Pyro Boots dash did not move the assaulter")
	# The harasser's mobility choice uses the same Bio Injector duration and speed.
	target.call("set_duel_profile", "blaster")
	equipment.call("tick", 0.02, 0.5, true, target.global_position + Vector3.FORWARD * 3.0, target, player, bot)
	if float(equipment.get("bio_remaining")) < 2.9 or float(equipment.call("get_speed_multiplier")) < 1.39:
		_failures.append("harasser did not trigger Bio Injector to disengage")
	# A hidden player cannot announce a charge, but a moving projectile can.
	target.global_position = Vector3(0.0, 0.0, 16.0)
	bot.set("_elapsed", 10.0)
	bot.set("_move_velocity", Vector3.ZERO)
	bot.set("_last_threat_scan_at", -1.0)
	bot.set("_projectile_previous", {})
	bot.set("_projectile_threat", {})
	bot.set("_dodge_remaining", 0.0)
	bot.set("_dodge_cooldown_remaining", 0.0)
	var projectile := Node3D.new()
	projectile.name = "BlasterProjectile"
	scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = target.global_position + Vector3(0.0, 0.9, 7.0)
	projectile.set_meta("ai_projectile_velocity", Vector3(0.0, 0.0, -10.0))
	projectile.set_meta("ai_projectile_endpoint", target.global_position + Vector3(0.0, 0.9, -2.0))
	projectile.set_meta("ai_projectile_radius", 0.16)
	bot.call("_sense_projectile_threat", target)
	bot.call("_try_dodge", target, player, false, true)
	if not Dictionary(bot.get("_projectile_threat")).is_empty() or float(bot.get("_dodge_remaining")) > 0.0:
		_failures.append("bot dodged a newly seen projectile before its reaction delay")
	var tuning: Dictionary = bot.get("_tuning")
	var reaction := float(tuning.get("reaction_delay", 0.22))
	var sample_count := int(ceil((reaction + 0.05) / 0.05))
	for sample in range(sample_count):
		bot.set("_elapsed", 10.0 + float(sample + 1) * 0.05)
		projectile.global_position += Vector3(0.0, 0.0, -0.5)
		bot.call("_sense_projectile_threat", target)
	if not bool(bot.call("_visible_player_threat", target, player, false)):
		_failures.append("bot ignored an incoming visible projectile after its reaction delay")
	bot.call("_try_dodge", target, player, false, true)
	if float(bot.get("_dodge_remaining")) <= 0.0:
		_failures.append("bot did not evade a reacted incoming projectile")
	projectile.queue_free()
	target.call("set_training_bot_enabled", false)
	current_scene = null
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("DUEL EQUIPMENT TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("DUEL EQUIPMENT TEST: FAIL (%d)" % _failures.size())
		quit(1)
