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
		await _test_audio(player, target)
		await _test_six_of_six(player, target)
		await _test_four_of_six(player, target)
		await _test_absorption(player, target, scene)
		await _test_moving_target(player, target)
		await _test_magazine_and_reload(player, target)
	current_scene = null
	scene.queue_free()
	await process_frame

	if _failures.is_empty():
		print("P0-104 SHOTGUN TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-104 SHOTGUN TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node, target: Node, target_position: Vector3) -> void:
	current_scene.call("clear_transient_fx")
	player.call("set_gameplay_enabled", true)
	target.call("set_training_bot_enabled", false)
	player.global_position = Vector3.ZERO
	player.call("reset_combat_state")
	player.call("set_weapon", "shotgun")
	# Keep a real input source active through the delayed emission. The shotgun
	# intentionally re-samples live aim after its 100 ms preparation window. Set
	# it after reset because reset now cancels every in-flight mobile gesture.
	player.call("set_touch_aim_vector", Vector2.UP)
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	target.global_position = target_position
	target.call("reset_combat_state")


func _test_audio(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(12.0, 0.0, 0.0))
	var shot_audio := player.get_node_or_null("ShotgunShotAudio") as AudioStreamPlayer
	var cycle_audio := player.get_node_or_null("ShotgunCycleAudio") as AudioStreamPlayer
	var reload_audio := player.get_node_or_null("ShotgunReloadAudio") as AudioStreamPlayer
	if shot_audio == null or cycle_audio == null or reload_audio == null:
		_failures.append("audio : lecteurs shotgun introuvables")
		return
	if shot_audio.stream.resource_path != "res://art/audio/shotgun-shot-a.wav" or cycle_audio.stream.resource_path != "res://art/audio/shotgun-cycle-a.wav" or reload_audio.stream.resource_path != "res://art/audio/shotgun-reload-a.wav":
		_failures.append("audio : fichiers shotgun incorrects")
	player.call("_perform_shotgun_attack")
	await _wait_seconds(0.16)
	if not shot_audio.playing:
		_failures.append("audio : tir non joué à l'émission")
	await _wait_seconds(0.28)
	if not cycle_audio.playing:
		_failures.append("audio : réarmement non joué après le tir")
	player.call("set_weapon", "blaster")
	if shot_audio.playing or cycle_audio.playing:
		_failures.append("audio : tir ou réarmement persiste après changement d'arme")
	player.call("set_weapon", "shotgun")
	player.set("_shotgun_ammo", 2)
	player.call("_start_shotgun_reload")
	if not reload_audio.playing:
		_failures.append("audio : recharge non jouée")
	player.call("set_weapon", "blaster")
	if reload_audio.playing:
		_failures.append("audio : recharge persiste après changement d'arme")


func _test_six_of_six(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -2.0))
	player.call("_perform_shotgun_attack")
	await _wait_for_shotgun(player)
	await _wait_seconds(0.40)
	var health := float(target.call("get_health"))
	if health > 748.0 or health < 718.0:
		_failures.append("6/6 : %.2f PV, dégâts critiques/BURN incohérents" % health)
	if not (target.call("get_active_effect_types") as Array).has("BURN"):
		_failures.append("6/6 : BURN absent")


func _test_four_of_six(player: Node, target: Node) -> void:
	# Offset target: the two leftmost pellets miss the new barrel-centred cone.
	_prepare(player, target, Vector3(0.80, 0.0, -2.98))
	player.call("_perform_shotgun_attack")
	await _wait_for_shotgun(player)
	await _wait_seconds(0.40)
	var health := float(target.call("get_health"))
	if absf(health - 888.0) > 1.2:
		_failures.append("4/6 : %.2f PV au lieu de 888" % health)
	if (target.call("get_active_effect_types") as Array).has("BURN"):
		_failures.append("4/6 : BURN appliqué à tort")


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


func _test_moving_target(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -5.0))
	player.call("_perform_shotgun_attack")
	await _wait_for_pellet()
	target.global_position.x = 3.0
	await _wait_seconds(0.45)
	if float(target.call("get_health")) < 999.9:
		_failures.append("cible mobile : des plombs esquivés infligent encore des dégâts")
	_prepare(player, target, Vector3(3.0, 0.0, -3.0))
	player.call("_perform_shotgun_attack")
	await _wait_for_pellet()
	var pellet: Node3D
	for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
		if projectile.name == "ShotgunPellet":
			pellet = projectile
			break
	if pellet == null:
		_failures.append("cible mobile : plomb absent après lancement")
		return
	var direction: Vector3 = pellet.get("_direction")
	var distance: float = (target.global_position.z - pellet.global_position.z) / direction.z
	target.global_position.x = pellet.global_position.x + direction.x * distance
	await _wait_seconds(0.45)
	if float(target.call("get_health")) >= 999.9:
		_failures.append("cible mobile : des plombs traversant la cible ne la touchent pas")


func _wait_for_pellet() -> void:
	for _frame in range(30):
		await physics_frame
		for projectile in current_scene.get_tree().get_nodes_in_group("prototype0_gameplay_projectiles"):
			if projectile.name == "ShotgunPellet":
				return


func _test_magazine_and_reload(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(12.0, 0.0, 0.0))
	for _shot in range(3):
		player.call("_perform_shotgun_attack")
		await _wait_for_shotgun(player)
	if int(player.call("get_shotgun_ammo")) != 0 or not bool(player.call("is_shotgun_reloading")):
		_failures.append("chargeur : recharge automatique non démarrée")
	await _wait_seconds(1.95)
	if int(player.call("get_shotgun_ammo")) != 3 or bool(player.call("is_shotgun_reloading")):
		_failures.append("chargeur : recharge 1,40 s incorrecte")


func _wait_for_shotgun(player: Node) -> void:
	for _frame in range(180):
		await process_frame
		if not bool(player.get("_shotgun_attack_busy")):
			return


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true, false, false).timeout
