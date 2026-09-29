extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.get_node_or_null("Player") as Node3D
	var target := scene.get_node_or_null("TargetDummy") as Node3D
	if player == null or target == null:
		_failures.append("duel actors missing")
		_finish()
		return
	var bot := target.get_node("TrainingBot")
	target.call("set_duel_mode", true)
	bot.set("training_stationary", true)
	target.global_position = Vector3(0.0, 0.0, 5.0)
	player.global_position = Vector3(0.0, 0.0, 7.0)
	target.call("set_training_bot_enabled", true)
	for _frame in range(18):
		await physics_frame
	if not bool(bot.get("_has_last_observed_position")):
		_failures.append("bot did not observe a visible player")
	var last_seen: Vector3 = bot.get("_last_observed_position")
	target.global_position = Vector3(0.0, 0.0, 14.0)
	await physics_frame
	if bool(player.call("is_visible_to", target)):
		_failures.append("cover setup did not hide the player")
	if (bot.get("_last_observed_position") as Vector3).distance_to(last_seen) > 0.05:
		_failures.append("bot followed the live position through cover")
	for _frame in range(252):
		await physics_frame
	if bool(bot.get("_has_last_observed_position")):
		_failures.append("bot kept a lost player's position indefinitely")
	target.global_position = Vector3(0.0, 0.0, 5.0)
	for _frame in range(18):
		await physics_frame
	target.global_position = Vector3(0.0, 0.0, 14.0)
	bot.set("training_stationary", false)
	await physics_frame
	await physics_frame
	if not bool(bot.get("_has_angle_destination")):
		_failures.append("bot found no side route around center cover")
	else:
		var angle: Vector3 = bot.get("_angle_destination")
		if absf(angle.x) < 4.5 or not bool(bot.call("_duel_path_clear", target, angle, last_seen)):
			_failures.append("chosen side route does not expose the last known position")
	for _frame in range(228):
		await physics_frame
	if absf(target.global_position.x) < 4.5 or not bool(player.call("is_visible_to", target)):
		_failures.append("bot did not reach an opening around center cover")

	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(0.0, 0.0, 16.0)
	player.global_position = Vector3(0.0, 0.0, 23.0)
	player.call("set_weapon", "shotgun")
	player.set("_shotgun_ammo", 1)
	player.call("_start_shotgun_reload")
	bot.set("training_stationary", false)
	target.call("set_training_bot_enabled", true)
	for _frame in range(52):
		await physics_frame
	if not bool(player.call("is_shotgun_reloading")):
		_failures.append("shotgun reload ended before observation")
	if target.global_position.z < 16.45:
		_failures.append("bot did not close distance during a visible reload")
	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(0.0, 0.0, 14.0)
	player.global_position = Vector3(0.0, 0.0, 7.0)
	target.call("set_training_bot_enabled", true)
	await physics_frame
	if float(bot.get("_reload_observed_at")) >= 0.0:
		_failures.append("bot observed a reload through cover")
	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(0.0, 0.0, 16.0)
	player.global_position = Vector3(0.0, 0.0, 23.0)
	player.call("set_weapon", "blaster")
	target.call("set_training_bot_enabled", true)
	for _frame in range(18):
		await physics_frame
	player.call("_begin_blaster_charge")
	await physics_frame
	if bool(bot.call("is_dodging")):
		_failures.append("bot dodged before its duel reaction delay")
	for _frame in range(16):
		await physics_frame
	if not bool(bot.call("is_dodging")):
		_failures.append("bot did not react to a visible charged attack")
	player.call("_cancel_blaster_charge")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("DUEL BOT TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("DUEL BOT TEST: FAIL (%d)" % _failures.size())
		quit(1)
