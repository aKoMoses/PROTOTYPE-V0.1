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
		player.call("set_weapon", "shotgun")
		await _test_six_of_six(player, target)
		await _test_five_of_six(player, target)
		await _test_absorption(player, target, scene)
		await _test_magazine_and_reload(player, target)

	if _failures.is_empty():
		print("P0-104 SHOTGUN TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-104 SHOTGUN TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node, target: Node, target_position: Vector3) -> void:
	player.global_position = Vector3.ZERO
	# Keep a real input source active through the delayed emission. The shotgun
	# intentionally re-samples live aim after its 100 ms preparation window.
	player.call("set_touch_aim_vector", Vector2.UP)
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("reset_combat_state")
	player.call("set_weapon", "shotgun")
	target.global_position = target_position
	target.call("reset_combat_state")


func _test_six_of_six(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -2.0))
	player.call("_perform_shotgun_attack")
	await _wait_for_shotgun(player)
	await _wait_seconds(0.40)
	var health := float(target.call("get_health"))
	if health > 820.0 or health < 790.0:
		_failures.append("6/6 : %.2f PV, dégâts critiques/BURN incohérents" % health)
	if not (target.call("get_active_effect_types") as Array).has("BURN"):
		_failures.append("6/6 : BURN absent")


func _test_five_of_six(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.20, 0.0, -2.98))
	player.call("_perform_shotgun_attack")
	await _wait_for_shotgun(player)
	await _wait_seconds(0.40)
	var health := float(target.call("get_health"))
	if absf(health - 900.0) > 1.2:
		_failures.append("5/6 : %.2f PV au lieu de 900" % health)
	if (target.call("get_active_effect_types") as Array).has("BURN"):
		_failures.append("5/6 : BURN appliqué à tort")


func _test_absorption(player: Node, target: Node, scene: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -2.0))
	var blocker := StaticBody3D.new()
	blocker.name = "TestShotgunBlocker"
	blocker.position = Vector3(0.0, 0.6, -1.0)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.2, 0.24)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	await process_frame
	player.call("_perform_shotgun_attack")
	await _wait_for_shotgun(player)
	await _wait_seconds(0.40)
	if absf(float(target.call("get_health")) - 1000.0) > 0.05:
		_failures.append("absorption : un plomb traverse le mur")
	if (target.call("get_active_effect_types") as Array).has("BURN"):
		_failures.append("absorption : BURN appliqué malgré le mur")
	blocker.queue_free()
	await process_frame


func _test_magazine_and_reload(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(12.0, 0.0, 0.0))
	for _shot in range(3):
		player.call("_perform_shotgun_attack")
		await _wait_for_shotgun(player)
	if int(player.call("get_shotgun_ammo")) != 0 or not bool(player.call("is_shotgun_reloading")):
		_failures.append("chargeur : recharge automatique non démarrée")
	await _wait_seconds(1.95)
	if int(player.call("get_shotgun_ammo")) != 3 or bool(player.call("is_shotgun_reloading")):
		_failures.append("chargeur : recharge 1,80 s incorrecte")


func _wait_for_shotgun(player: Node) -> void:
	for _frame in range(180):
		await process_frame
		if not bool(player.get("_shotgun_attack_busy")):
			return


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true, false, false).timeout
