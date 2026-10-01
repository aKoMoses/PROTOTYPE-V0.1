extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var actor: Node = load("res://scripts/player.gd").new()
	actor.name = "Player"
	scene.add_child(actor)
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	if player == null:
		_failures.append("Player introuvable")
	else:
		await _test_pyro_dash(player)
		await _test_pyro_charges(player)
		await _test_survival_charges(player)
		_test_bot_charges()
		await _test_dash_obstacle(player, scene)
		await _test_dash_stun(player)
		await _test_bio_injector(player)
	scene.queue_free()
	await process_frame
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
	if absf(float(player.global_position.x) - 5.0) > 0.25:
		_failures.append("Pyro Boots : distance %.2f au lieu de 5 m" % player.global_position.x)
	if bool(player.call("is_dash_active")):
		_failures.append("Pyro Boots : dash encore actif après 0,18 s")
	var cooldown := float(player.call("get_module_cooldown", "pyro_boots"))
	if cooldown < 5.2 or cooldown > 6.0:
		_failures.append("Pyro Boots : cooldown %.2f incorrect" % cooldown)


func _test_pyro_charges(player: Node) -> void:
	_prepare(player)
	player.set_physics_process(false)
	if int(player.call("get_pyro_charges")) != 2:
		_failures.append("Pyro Boots : deux charges initiales absentes")
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	var ignition: Node = current_scene.get_node_or_null("PyroBootsIgnition")
	if ignition == null or ignition.get_node_or_null("BurningBoots") == null:
		_failures.append("Pyro Boots : explosion et bottes enflammées absentes")
	player.call("_update_dash", 0.5)
	if absf(float(player.global_position.x) - 5.0) > 0.02:
		_failures.append("Pyro Boots : un long pas dépasse la portée de 5 m")
	player.call("_update_module_cooldowns", 1.0)
	await physics_frame
	player.call("_perform_pyro_boots", Vector3.BACK)
	if not bool(player.call("is_dash_active")) or int(player.call("get_pyro_charges")) != 0:
		_failures.append("Pyro Boots : seconde charge indisponible pendant la recharge")
	player.call("_cancel_dash")
	await physics_frame
	var token := int(player.get("_dash_token"))
	player.call("_perform_pyro_boots", Vector3.LEFT)
	if bool(player.call("is_dash_active")) or int(player.get("_dash_token")) != token:
		_failures.append("Pyro Boots : troisième activation acceptée sans charge")
	player.call("_update_module_cooldowns", 5.0)
	if int(player.call("get_pyro_charges")) != 1:
		_failures.append("Pyro Boots : première charge non rendue après 6 s")
	player.call("_update_module_cooldowns", 1.0)
	if int(player.call("get_pyro_charges")) != 2:
		_failures.append("Pyro Boots : deuxième charge non rendue après sa recharge")
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	player.call("reset_combat_state")
	if int(player.call("get_pyro_charges")) != 2:
		_failures.append("Pyro Boots : reset ne restaure pas les charges")
	player.call("_start_module_cooldown", "pyro_boots", 6.0)
	player.call("_start_module_cooldown", "pyro_boots", 6.0)
	player.set("_bio_remaining", 3.0)
	player.call("_update_module_cooldowns", 1.0)
	if float(player.call("get_module_cooldown", "pyro_boots")) > 4.6:
		_failures.append("Pyro Boots : Bio Injector n'accélère pas les deux recharges")
	player.call("set_training_options", false, true, false)
	if int(player.call("get_pyro_charges")) != 2:
		_failures.append("Pyro Boots : recharge instantanée ne restaure pas les charges")
	player.call("set_training_options", false, false, false)
	player.set_physics_process(true)
	await process_frame


func _test_survival_charges(player: Node) -> void:
	for aspect in ["trail", "thruster"]:
		_prepare(player)
		player.call("configure_survival_build", {"weapon": "blaster", "offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "", "aspects": {"mobility": {"path": aspect, "rank": 1}}})
		player.set_physics_process(false)
		var expected := 3 if aspect == "thruster" else 2
		var effects: Node = player.get("survival_evolution_effects")
		if int(effects.call("dash_charges")) != expected:
			_failures.append("Survie : compteur de charges incorrect pour " + aspect)
		for charge in range(expected):
			await physics_frame
			player.call("_perform_pyro_boots", Vector3.RIGHT)
			if not bool(player.call("is_dash_active")):
				_failures.append("Survie : charge %d indisponible pour %s" % [charge + 1, aspect])
			player.call("_cancel_dash")
		await physics_frame
		player.call("_perform_pyro_boots", Vector3.RIGHT)
		if bool(player.call("is_dash_active")) or int(effects.call("dash_charges")) != 0:
			_failures.append("Survie : activation sans charge pour " + aspect)
	player.call("apply_loadout", {"weapon": "blaster", "mobility": "pyro_boots"})
	player.set_physics_process(true)
	await process_frame


func _test_bot_charges() -> void:
	var equipment: Node = load("res://scripts/duel_bot_equipment.gd").new()
	equipment.call("_start_module_cooldown", "pyro_boots")
	if not bool(equipment.call("_module_ready", "pyro_boots")):
		_failures.append("Bot : deuxième charge Pyro indisponible")
	equipment.call("_start_module_cooldown", "pyro_boots")
	if bool(equipment.call("_module_ready", "pyro_boots")):
		_failures.append("Bot : troisième charge Pyro autorisée")
	equipment.call("reset")
	if not bool(equipment.call("_module_ready", "pyro_boots")):
		_failures.append("Bot : reset des charges Pyro absent")
	equipment.free()


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
	player.call("_start_module_cooldown", "javelin", 10.0)
	player.call("_perform_mobility_module")
	if float(player.call("get_bio_remaining")) < 2.9:
		_failures.append("Bio Injector : buff de 3 s absent")
	if absf(float(player.call("get_current_move_speed")) - 7.0) > 0.15:
		_failures.append("Bio Injector : vitesse %.2f au lieu de 7" % player.call("get_current_move_speed"))
	if absf(float(player.call("get_attack_speed_multiplier")) - 1.5) > 0.01:
		_failures.append("Bio Injector : multiplicateur d'attaque absent")
	await create_timer(0.20, true, false, false).timeout
	var remaining := float(player.call("get_module_cooldown", "javelin"))
	if remaining >= 9.8:
		_failures.append("Bio Injector : cooldowns externes non accélérés")
	player.call("apply_slow", 1.0, 30.0, "integration")
	if absf(float(player.call("get_current_move_speed")) - 4.9) > 0.15:
		_failures.append("Bio Injector + SLOW : vitesse %.2f au lieu de 4,9" % player.call("get_current_move_speed"))
