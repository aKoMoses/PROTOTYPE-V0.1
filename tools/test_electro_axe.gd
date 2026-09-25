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
		await _test_combo_damage(player, target, 0.8, 320.0, "combo centre")
		await _test_combo_damage(player, target, 2.0, 215.0, "combo onde")
		await _test_obstacle_blocks(player, target, scene)
		await _test_stun_interrupt(player, target)

	if _failures.is_empty():
		print("P0-103 ELECTRO AXE TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-103 ELECTRO AXE TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _test_combo_damage(player: Node, target: Node, target_distance: float, expected_damage: float, label: String) -> void:
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -target_distance)
	target.call("reset_combat_state")
	player.call("reset_axe_state")
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	for index in range(3):
		player.call("_perform_axe_attack")
		await _wait_for_attack(player)
	var actual_damage := 1000.0 - float(target.call("get_health"))
	if absf(actual_damage - expected_damage) > 0.6:
		_failures.append("%s: %.2f dégâts au lieu de %.2f" % [label, actual_damage, expected_damage])


func _test_obstacle_blocks(player: Node, target: Node, scene: Node) -> void:
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -2.0)
	target.call("reset_combat_state")
	player.call("reset_axe_state")
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	var blocker := StaticBody3D.new()
	blocker.name = "TestAxeBlocker"
	blocker.position = Vector3(0.0, 0.6, -1.0)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.2, 0.24)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	await process_frame
	player.call("_perform_axe_attack")
	await _wait_seconds(0.36)
	if absf(float(target.call("get_health")) - 1000.0) > 0.05:
		_failures.append("obstacle : l'estoc traverse un mur")
	blocker.queue_free()
	await process_frame


func _test_stun_interrupt(player: Node, target: Node) -> void:
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -0.8)
	target.call("reset_combat_state")
	player.call("reset_combat_state")
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("apply_stun", 0.5, "integration")
	player.call("_perform_axe_attack")
	await _wait_seconds(0.45)
	if absf(float(target.call("get_health")) - 1000.0) > 0.05:
		_failures.append("stun : préparation d'Electro Axe non interrompue")


func _wait_seconds(seconds: float) -> void:
	var frames := maxi(1, int(ceil(seconds * 60.0)))
	for _frame in range(frames):
		await process_frame


func _wait_for_attack(player: Node) -> void:
	for _frame in range(240):
		await process_frame
		if not bool(player.get("_axe_attack_busy")):
			return
