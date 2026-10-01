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
		await _test_javelin_mark_and_recast(player, target)
		await _test_javelin_live_collision(player, target)
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


func _test_javelin_mark_and_recast(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -2.0))
	player.call("_perform_javelin")
	await _wait_for_module(player)
	if absf(float(target.call("get_health")) - 860.0) > 1.0:
		_failures.append("Javelin : dégâts %.2f au lieu de 140" % (1000.0 - float(target.call("get_health"))))
	if not bool(target.call("has_javelin_mark")):
		_failures.append("Javelin : marque absente")
	if float(player.call("get_javelin_recast_fraction")) <= 0.0:
		_failures.append("Javelin : fenêtre de réactivation absente du HUD")
	var cooldown_before := float(player.call("get_module_cooldown", "javelin"))
	var position_before: Vector3 = player.global_position
	player.call("_perform_javelin")
	await process_frame
	if absf(float(target.call("get_health")) - 860.0) > 1.0:
		_failures.append("Javelin recast : dégâts additionnels")
	if bool(target.call("has_javelin_mark")):
		_failures.append("Javelin recast : marque non consommée")
	if float(player.call("get_javelin_recast_fraction")) > 0.0:
		_failures.append("Javelin recast : fenêtre encore affichée après consommation")
	if player.global_position.distance_to(position_before) < 0.5:
		_failures.append("Javelin recast : téléportation non effectuée")
	if float(player.call("get_module_cooldown", "javelin")) > cooldown_before + 0.1:
		_failures.append("Javelin recast : second cooldown déclenché")


func _test_javelin_live_collision(player: Node, target: Node) -> void:
	_prepare(player, target, Vector3(0.0, 0.0, -5.0))
	player.call("_perform_javelin")
	var projectile := await _wait_for_projectile("JavelinProjectile")
	if projectile == null:
		_failures.append("Javelin : projectile non lancé")
		return
	target.global_position = Vector3(4.0, 0.0, -5.0)
	await _wait_for_module(player)
	if float(target.call("get_health")) < 999.95 or bool(target.call("has_javelin_mark")):
		_failures.append("Javelin : touche ou marque une cible qui a esquivé")
	_prepare(player, target, Vector3(4.0, 0.0, -5.0))
	player.call("_perform_javelin")
	projectile = await _wait_for_projectile("JavelinProjectile")
	if projectile == null:
		_failures.append("Javelin : second projectile non lancé")
		return
	target.global_position = Vector3(projectile.global_position.x, 0.0, -5.0)
	await _wait_for_module(player)
	if float(target.call("get_health")) >= 999.95 or not bool(target.call("has_javelin_mark")):
		_failures.append("Javelin : ignore une cible entrée dans sa trajectoire")


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
		# The cast lock ends at projectile emission; the already-emitted gameplay
		# projectile is deliberately allowed to finish without owning the actor.
		if not bool(player.call("is_module_busy")) and get_nodes_in_group("prototype0_gameplay_projectiles").is_empty():
			return


func _wait_for_projectile(projectile_name: String) -> Node3D:
	for _frame in range(90):
		await physics_frame
		for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
			if projectile.name == projectile_name:
				return projectile as Node3D
	return null
