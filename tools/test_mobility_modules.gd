extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	if player == null:
		_failures.append("Player introuvable")
	else:
		await _test_pyro_dash(player)
		await _test_dash_obstacle(player, scene)
		await _test_dash_stun(player)
		await _test_bio_injector(player)
	if _failures.is_empty():
		print("P0-106 MOBILITY MODULES TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-106 MOBILITY MODULES TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node) -> void:
	player.global_position = Vector3.ZERO
	player.call("reset_combat_state")
	player.set("_last_move_direction", Vector3(1.0, 0.0, 0.0))
	player.set("_mobility_module_id", "pyro_boots")


func _test_pyro_dash(player: Node) -> void:
	_prepare(player)
	player.call("_perform_mobility_module")
	await create_timer(0.50, true, false, false).timeout
	if absf(float(player.global_position.x) - 3.0) > 0.25:
		_failures.append("Pyro Boots : distance %.2f au lieu de 3 m" % player.global_position.x)
	if bool(player.call("is_dash_active")):
		_failures.append("Pyro Boots : dash encore actif après 0,18 s")
	var cooldown := float(player.call("get_module_cooldown", "pyro_boots"))
	if cooldown < 5.2 or cooldown > 6.0:
		_failures.append("Pyro Boots : cooldown %.2f incorrect" % cooldown)


func _test_dash_obstacle(player: Node, scene: Node) -> void:
	_prepare(player)
	var blocker := StaticBody3D.new()
	blocker.name = "TestDashBlocker"
	blocker.position = Vector3(1.35, 0.6, 0.0)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.30, 1.2, 2.0)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	await process_frame
	player.call("_perform_mobility_module")
	await create_timer(0.50, true, false, false).timeout
	if float(player.global_position.x) > 1.0:
		_failures.append("Pyro Boots : traverse un obstacle")
	blocker.queue_free()
	await process_frame


func _test_dash_stun(player: Node) -> void:
	_prepare(player)
	player.call("apply_stun", 0.5, "integration")
	player.call("_perform_mobility_module")
	await create_timer(0.25, true, false, false).timeout
	if player.global_position.length() > 0.15 or bool(player.call("is_dash_active")):
		_failures.append("Pyro Boots : activation malgré STUN")


func _test_bio_injector(player: Node) -> void:
	_prepare(player)
	player.set("_mobility_module_id", "bio_injector")
	player.call("_start_module_cooldown", "modulo_drone", 10.0)
	player.call("_perform_mobility_module")
	if float(player.call("get_bio_remaining")) < 2.9:
		_failures.append("Bio Injector : buff de 3 s absent")
	if absf(float(player.call("get_current_move_speed")) - 7.0) > 0.15:
		_failures.append("Bio Injector : vitesse %.2f au lieu de 7" % player.call("get_current_move_speed"))
	if absf(float(player.call("get_attack_speed_multiplier")) - 1.5) > 0.01:
		_failures.append("Bio Injector : multiplicateur d'attaque absent")
	await create_timer(0.20, true, false, false).timeout
	var remaining := float(player.call("get_module_cooldown", "modulo_drone"))
	if remaining >= 9.8:
		_failures.append("Bio Injector : cooldowns externes non accélérés")
	player.call("apply_slow", 1.0, 30.0, "integration")
	if absf(float(player.call("get_current_move_speed")) - 4.9) > 0.15:
		_failures.append("Bio Injector + SLOW : vitesse %.2f au lieu de 4,9" % player.call("get_current_move_speed"))
