extends SceneTree

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
	flow.set("round_number", 1)
	scene.call("prepare_round", {})
	if str(target.call("get_duel_profile")) != "blaster":
		_failures.append("round one did not select the blaster harasser")
	flow.set("round_number", 2)
	scene.call("prepare_round", {})
	if str(target.call("get_duel_profile")) != "shotgun":
		_failures.append("round two did not select the shotgun assaulter")
	target.call("set_duel_mode", true)
	target.global_position = Vector3(0.0, 0.0, 5.0)
	player.global_position = Vector3(0.0, 0.0, 7.0)
	player.call("set_gameplay_enabled", false)
	player.call("reset_combat_state")
	target.call("set_duel_profile", "blaster")
	target.call("set_training_bot_enabled", true)
	bot.set("training_stationary", true)
	equipment.set("next_attack_at", 100.0)
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
	player.global_position = Vector3(0.0, 0.0, 12.0)
	await create_timer(0.25, true, false, false).timeout
	if float(player.call("get_health")) < before:
		_failures.append("blaster projectile followed a moving target")
	player.global_position = Vector3(0.0, 0.0, 7.0)
	target.call("set_training_bot_enabled", false)
	target.call("set_duel_profile", "shotgun")
	target.call("set_training_bot_enabled", true)
	equipment.set("next_attack_at", 100.0)
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
	if int(equipment.get("ammo")) != 3 or bool(equipment.call("is_reloading")):
		_failures.append("shotgun did not finish its shared-duration reload")
	# The assaulter spends Pyro Boots to enter, then has to wait for its cooldown.
	player.global_position = Vector3(0.0, 0.0, 9.0)
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
	var projectile := Node3D.new()
	projectile.name = "BlasterProjectile"
	scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = target.global_position + Vector3(0.0, 0.9, 1.5)
	bot.call("_visible_player_threat", target, player, false)
	projectile.global_position += Vector3(0.0, 0.0, -0.5)
	if not bool(bot.call("_visible_player_threat", target, player, false)):
		_failures.append("bot ignored an incoming visible projectile")
	projectile.queue_free()
	if _failures.is_empty():
		print("DUEL EQUIPMENT TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("DUEL EQUIPMENT TEST: FAIL (%d)" % _failures.size())
		quit(1)
