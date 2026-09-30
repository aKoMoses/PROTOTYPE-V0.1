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
		await _test_reveal_timers(player)
		await _test_bush_and_spotted(player, target)
		await _test_obstacle_reveal(player, target, scene)
		await _test_refused_activation(player, scene)
	if _failures.is_empty():
		print("P0-111 VISIBILITY TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-109 VISIBILITY TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _test_reveal_timers(player: Node) -> void:
	player.call("reset_combat_state")
	player.call("_begin_blaster_charge")
	player.call("_cancel_blaster_charge")
	if float(player.call("get_combat_reveal_remaining")) < 2.9:
		_failures.append("Combat : attaque engagée ne révèle pas pendant 3 s")
	player.call("reset_combat_state")
	await create_timer(2.10, true, false, false).timeout
	if float(player.call("get_combat_reveal_remaining")) > 0.95:
		_failures.append("Combat : délai individuel ne s'écoule pas correctement")
	await create_timer(1.10, true, false, false).timeout
	if float(player.call("get_combat_reveal_remaining")) > 0.05:
		_failures.append("Combat : sortie après 3 s absente")


func _test_bush_and_spotted(player: Node, target: Node) -> void:
	player.call("reset_combat_state")
	target.call("reset_combat_state")
	var bushes := get_nodes_in_group("bush_placeholder")
	if bushes.is_empty():
		_failures.append("Bush : aucun volume de test présent")
		return
	var bush: Node3D = bushes[0] as Node3D
	player.global_position = bush.global_position
	await physics_frame
	if not bool(player.call("is_in_bush")):
		_failures.append("Bush joueur : entrée dans les hautes herbes non détectée")
	if str(player.call("get_current_bush_name")) != str(bush.name):
		_failures.append("Bush joueur : nom du volume actif incorrect")
	if float(player.call("get_bush_transition_clock")) <= 0.0:
		_failures.append("Bush joueur : transition d'entrée absente")
	player.global_position = bush.global_position + Vector3(4.0, 0.0, 0.0)
	await physics_frame
	if bool(player.call("is_in_bush")) or str(player.call("get_current_bush_name")) != "":
		_failures.append("Bush joueur : sortie des hautes herbes non détectée")
	target.global_position = bush.global_position
	await process_frame
	if not bool(target.call("is_in_bush")) or bool(target.call("is_visible_to", player)):
		_failures.append("Bush : cible hors combat visible dans les hautes herbes")
	target.call("apply_spotted", 0.35, "test")
	if not bool(target.call("is_visible_to", player)):
		_failures.append("SPOTTED : cible cachée non révélée")
	if float(target.call("get_combat_reveal_remaining")) > 0.05:
		_failures.append("SPOTTED : l'œil crée à tort un état EN COMBAT")
	await create_timer(0.50, true, false, false).timeout
	if bool(target.call("is_visible_to", player)):
		_failures.append("SPOTTED : cible encore visible après expiration")
	target.call("take_damage", 1.0, "test", "visibility_damage")
	if not bool(target.call("is_visible_to", player)):
		_failures.append("Combat : dégâts reçus ne révèlent pas la cible")


func _test_obstacle_reveal(player: Node, target: Node, scene: Node) -> void:
	player.call("reset_combat_state")
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -3.0)
	target.call("reset_combat_state")
	var blocker := StaticBody3D.new()
	blocker.name = "TestVisibilityBlocker"
	blocker.position = Vector3(0.0, 0.6, -1.0)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.2, 0.25)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	await physics_frame
	if bool(target.call("is_visible_to", player)):
		_failures.append("Obstacle : ligne de vue non occultée")
	target.call("apply_spotted", 0.5, "test")
	if bool(target.call("is_visible_to", player)):
		_failures.append("Obstacle : SPOTTED révèle à tort une cible derrière le mur")
	target.call("reset_combat_state")
	target.call("take_damage", 1.0, "test", "visibility_wall_combat")
	if bool(target.call("is_visible_to", player)):
		_failures.append("Obstacle : EN COMBAT révèle à tort une cible derrière le mur")
	target.call("apply_spotted", 0.5, "test")
	if bool(target.call("is_visible_to", player)):
		_failures.append("Obstacle : combat et SPOTTED combinés traversent à tort le mur")
	player.call("_mark_combat_event")
	player.call("apply_spotted", 0.5, "test")
	if bool(player.call("is_visible_to", target)):
		_failures.append("Obstacle joueur : combat/SPOTTED traversent à tort le mur")
	target.call("_update_visibility_presentation")
	for node_name in ["VisualRoot", "TargetHealthReadout", "StatusReadout"]:
		var presentation := target.get_node_or_null(node_name) as Node3D
		if presentation == null or presentation.visible:
			_failures.append("Obstacle : %s divulgue la cible révélée hors de vue" % node_name)
	blocker.queue_free()
	await physics_frame
	if not bool(target.call("is_visible_to", player)) or not bool(player.call("is_visible_to", target)):
		_failures.append("Obstacle : la vision ne revient pas quand le mur disparaît")


func _test_refused_activation(player: Node, scene: Node) -> void:
	player.call("reset_combat_state")
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	var blocker := StaticBody3D.new()
	blocker.name = "TestRefusedVisibilityBlocker"
	blocker.position = Vector3(0.0, 0.6, -0.8)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.2, 0.25)
	collision.shape = shape
	collision.position = Vector3.ZERO
	blocker.add_child(collision)
	scene.add_child(blocker)
	await process_frame
	player.set("_defensive_module_id", "magnetic_field")
	player.call("_perform_defensive_module")
	if float(player.call("get_combat_reveal_remaining")) > 0.05:
		_failures.append("Activation refusée : placement invalide révèle le joueur")
	blocker.queue_free()
	await process_frame
