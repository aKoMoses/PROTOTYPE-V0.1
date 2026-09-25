extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player ou TargetDummy introuvable")
	else:
		await _test_drone_hit(player, target)
		await _test_drone_absorption(player, target, scene)
		await _test_drone_cooldown(player, target)
		await _test_javelin_mark_and_recast(player, target)
		await _test_javelin_blocked_recast(player, target, scene)
	if _failures.is_empty():
		print("P0-105 OFFENSIVE MODULES TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-105 OFFENSIVE MODULES TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node, target: Node, target_position: Vector3) -> void:
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("reset_combat_state")
	target.global_position = target_position
	target.rotation = Vector3.ZERO
	target.call("reset_combat_state")


func _test_drone_hit(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -3.0))
	player.call("_perform_modulo_drone")
	await _wait_for_module(player)
	await create_timer(0.10, true, false, false).timeout
	var health := float(target.call("get_health"))
	if health > 900.0 or health < 875.0:
		_failures.append("Drone : %.2f PV, dégâts/BURN incohérents" % health)
	var effects: Array = target.call("get_active_effect_types")
	if not effects.has("BURN") or not effects.has("SPOTTED"):
		_failures.append("Drone : BURN ou SPOTTED absent")


func _test_drone_absorption(player: Node, target: Node, scene: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -3.0))
	var blocker := StaticBody3D.new()
	blocker.name = "TestDroneBlocker"
	blocker.position = Vector3(0.0, 0.6, -1.2)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.2, 0.24)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	await process_frame
	player.call("_perform_modulo_drone")
	await _wait_for_module(player)
	await create_timer(0.10, true, false, false).timeout
	if absf(float(target.call("get_health")) - 1000.0) > 0.05:
		_failures.append("Drone absorption : dégâts derrière obstacle")
	var effects: Array = target.call("get_active_effect_types")
	if effects.has("BURN") or effects.has("SPOTTED"):
		_failures.append("Drone absorption : effet derrière obstacle")
	blocker.queue_free()
	await process_frame


func _test_drone_cooldown(player: Node, target: Node) -> void:
	# The previous launch has engaged the 10 s cooldown; no reset is performed.
	target.global_position = Vector3(0.0, 0.0, -3.0)
	target.call("reset_combat_state")
	player.call("_perform_modulo_drone")
	await process_frame
	if bool(player.call("is_module_busy")):
		_failures.append("Drone cooldown : second lancement accepté trop tôt")
	if float(player.call("get_module_cooldown", "modulo_drone")) <= 9.0:
		_failures.append("Drone cooldown : durée restante incorrecte")


func _test_javelin_mark_and_recast(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -2.0))
	player.call("_perform_javelin")
	await _wait_for_module(player)
	if absf(float(target.call("get_health")) - 860.0) > 1.0:
		_failures.append("Javelin : dégâts %.2f au lieu de 140" % (1000.0 - float(target.call("get_health"))))
	if not bool(target.call("has_javelin_mark")):
		_failures.append("Javelin : marque absente")
	var cooldown_before := float(player.call("get_module_cooldown", "javelin"))
	var position_before: Vector3 = player.global_position
	player.call("_perform_javelin")
	await process_frame
	if absf(float(target.call("get_health")) - 860.0) > 1.0:
		_failures.append("Javelin recast : dégâts additionnels")
	if bool(target.call("has_javelin_mark")):
		_failures.append("Javelin recast : marque non consommée")
	if player.global_position.distance_to(position_before) < 0.5:
		_failures.append("Javelin recast : téléportation non effectuée")
	if float(player.call("get_module_cooldown", "javelin")) > cooldown_before + 0.1:
		_failures.append("Javelin recast : second cooldown déclenché")


func _test_javelin_blocked_recast(player: Node, target: Node, scene: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -2.0))
	player.call("_perform_javelin")
	await _wait_for_module(player)
	var blocker := StaticBody3D.new()
	blocker.name = "TestJavelinBlocker"
	blocker.position = Vector3(0.0, 0.6, -0.6)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.2, 0.22)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	await process_frame
	player.call("_perform_javelin")
	await process_frame
	if not bool(target.call("has_javelin_mark")):
		_failures.append("Javelin destination bloquée : marque perdue")
	blocker.queue_free()
	await process_frame


func _wait_for_module(player: Node) -> void:
	for _frame in range(240):
		await process_frame
		if not bool(player.call("is_module_busy")):
			return
