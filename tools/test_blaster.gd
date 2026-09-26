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
		target.call("set_training_bot_enabled", false)
		player.call("set_weapon", "blaster")
		await _test_normal_shot(player, target)
		await _test_cooldown(player, target)
		await _test_charge_damage(player, target, 0.50, 35.0, "charge 50%")
		await _test_charge_damage(player, target, 1.15, 50.0, "charge maximale")
		await _test_charge_cap(player)
		await _test_charge_speed(player)
		await _test_cancel_on_weapon_change(player)
		await _test_cancel_on_death(player, target)
	if _failures.is_empty():
		print("P0-127 BLASTER TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-127 BLASTER TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node, target: Node) -> void:
	player.call("set_gameplay_enabled", true)
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("set_weapon", "blaster")
	player.call("reset_combat_state")
	target.global_position = Vector3(0.0, 0.0, -4.0)
	target.call("reset_combat_state")
	await process_frame


func _test_normal_shot(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.35)
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - 20.0) > 0.6:
		_failures.append("tir normal : %.2f dégâts au lieu de 20" % damage)


func _test_cooldown(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.35)
	var first_damage := 1000.0 - float(target.call("get_health"))
	if absf(first_damage - 20.0) > 0.6:
		_failures.append("cooldown : second tir immédiat accepté")
	await _wait_seconds(0.20)
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.35)
	if float(target.call("get_health")) >= 981.0:
		_failures.append("cooldown : tir après 0,45 s refusé")


func _test_charge_damage(player: Node, target: Node, hold_time: float, expected: float, label: String) -> void:
	await _prepare(player, target)
	player.call("_begin_blaster_charge")
	await _wait_seconds(hold_time)
	var ratio := float(player.call("get_blaster_charge_ratio"))
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("_release_blaster_charge")
	await _wait_seconds(0.40)
	var damage := 1000.0 - float(target.call("get_health"))
	var expected_damage := expected if hold_time < 1.0 else 50.0
	if absf(damage - expected_damage) > 1.2:
		_failures.append("%s : %.2f dégâts au lieu de %.2f (ratio %.2f)" % [label, damage, expected_damage, ratio])


func _test_charge_cap(player: Node) -> void:
	await _prepare(player, current_scene.get_node("TargetDummy"))
	player.call("_begin_blaster_charge")
	await _wait_seconds(1.35)
	if float(player.call("get_blaster_charge_ratio")) > 1.001:
		_failures.append("charge prolongée : ratio supérieur à 1")
	player.call("_cancel_blaster_charge")


func _test_charge_speed(player: Node) -> void:
	if absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("déplacement : vitesse initiale incorrecte")
	player.call("_begin_blaster_charge")
	await physics_frame
	if absf(float(player.call("get_current_move_speed")) - 4.0) > 0.05:
		_failures.append("déplacement pendant charge : vitesse différente de 80%")
	player.call("_cancel_blaster_charge")
	if absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("déplacement après charge : vitesse non restaurée")


func _test_cancel_on_weapon_change(player: Node) -> void:
	player.call("_begin_blaster_charge")
	await physics_frame
	player.call("set_weapon", "shotgun")
	if bool(player.call("is_blaster_charging")) or absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("changement d'arme : charge non annulée")
	player.call("set_weapon", "blaster")


func _test_cancel_on_death(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("set_passive", "omnivamp")
	player.call("_begin_blaster_charge")
	player.call("take_damage", 1000.0, "test", "blaster_death")
	await process_frame
	if bool(player.call("is_blaster_charging")) or absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("mort pendant charge : état de charge bloqué")
	player.call("set_gameplay_enabled", true)
	player.call("reset_combat_state")


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true, false, false).timeout
