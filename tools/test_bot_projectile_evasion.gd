extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.set_physics_process(false)
	target.call("set_duel_mode", true)
	target.call("set_training_bot_enabled", true)
	var bot := target.get_node("TrainingBot")
	bot.set_physics_process(false)
	target.global_position = Vector3(0, 0, 16)
	player.global_position = Vector3(0, 0, 24)
	await physics_frame

	var incoming := _flight(scene, player, Vector3(0, 0.9, 27), Vector3(0, 0, -24), Vector3(0, 0.9, 14))
	_sample(bot, target, incoming, 1.0)
	_check((bot.get("_projectile_threat") as Dictionary).is_empty(), "a newly visible projectile cannot cause an instant dodge")
	for index in range(1, 7):
		incoming.global_position = Vector3(0, 0.9, 27 - 24 * float(index) * 0.05)
		_sample(bot, target, incoming, 1.0 + float(index) * 0.05)
	_check(not (bot.get("_projectile_threat") as Dictionary).is_empty(), "incoming collision trajectory is recognized after reaction time")
	bot.call("_try_dodge", target, player, false, true)
	_check(bool(bot.call("is_dodging")), "a visible projectile can be evaded even with its shooter hidden")
	var dodge: Vector3 = bot.get("_dodge_direction")
	_check(absf(dodge.x) > 0.6, "dodge crosses the incoming trajectory")
	var motion := dodge * float(bot.DODGE_SPEED) * float(bot.DODGE_DURATION)
	var safe: Vector3 = bot.call("_safe_bot_motion", target, motion)
	_check(safe.length() >= motion.length() * 0.92, "chosen dodge has a clear swept corridor")
	incoming.queue_free()
	await process_frame

	for grazing in [true, false]:
		bot.call("reset_clock")
		bot.set_physics_process(false)
		var start := Vector3(4 if grazing else 0, 0.9, 21)
		var velocity := Vector3(0, 0, -10 if grazing else 10)
		var harmless := _flight(scene, player, start, velocity, start + velocity * 2.0)
		_sample(bot, target, harmless, 2.0)
		harmless.global_position += velocity * 0.3
		_sample(bot, target, harmless, 2.3)
		_check((bot.get("_projectile_threat") as Dictionary).is_empty(), "grazing and outgoing shots do not waste dodge cooldown")
		harmless.queue_free()
		await process_frame

	bot.call("reset_clock")
	bot.set_physics_process(false)
	var occluded := _flight(scene, player, Vector3(0, 0.9, 7), Vector3(0, 0, 24), Vector3(0, 0.9, 18))
	_sample(bot, target, occluded, 3.0)
	_sample(bot, target, occluded, 3.3)
	_check((bot.get("_projectile_threat") as Dictionary).is_empty(), "cover prevents seeing and reacting to a flying shot")
	occluded.queue_free()
	await process_frame

	# A player's weapon keeps its normal damage on a stationary opponent, but
	# cannot deliver its launch-time hit after that opponent leaves the impact.
	target.call("set_training_bot_enabled", false)
	for weapon in ["blaster", "shotgun"]:
		for evade in [false, true]:
			player.call("reset_combat_state")
			player.set_physics_process(false)
			target.call("reset_combat_state")
			target.global_position = Vector3(0, 0, 22)
			player.global_position = Vector3(0, 0, 16)
			var start := Vector3(0, 0.9, 16)
			var endpoint := Vector3(0, 0.9, 22)
			if weapon == "blaster":
				player.call("_spawn_blaster_projectile", start, 20.0, 0.0, 800 + int(evade), Vector3.BACK)
			else:
				var salvo := {"id": 900 + int(evade), "credited": {}, "hits_by_target": {}}
				player.call("_spawn_shotgun_projectile", start, endpoint, salvo, 0)
			if evade:
				target.global_position.x = 3.0
			await create_timer(0.40).timeout
			var damage := float(target.call("get_max_health")) - float(target.call("get_health"))
			_check(is_zero_approx(damage) if evade else damage > 0.0, "%s impact respects an actual sidestep and retains stationary hits" % weapon)

	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("BOT PROJECTILE EVASION TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BOT PROJECTILE EVASION TEST: FAIL (%d)" % failures.size())
		quit(1)


func _flight(scene: Node3D, player: Node3D, position: Vector3, velocity: Vector3, endpoint: Vector3) -> Node3D:
	var projectile := Node3D.new()
	projectile.name = "BlasterProjectile"
	scene.add_child(projectile)
	projectile.global_position = position
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.set_meta("ai_projectile_source", player.get_instance_id())
	projectile.set_meta("ai_projectile_velocity", velocity)
	projectile.set_meta("ai_projectile_endpoint", endpoint)
	projectile.set_meta("ai_projectile_radius", 0.16)
	return projectile


func _sample(bot: Node, body: Node3D, _projectile: Node3D, at: float) -> void:
	bot.set("_elapsed", at)
	bot.call("_sense_projectile_threat", body)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
