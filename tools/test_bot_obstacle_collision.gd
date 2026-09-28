extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var scene := load("res://scenes/survival.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var enemy := StaticBody3D.new()
	enemy.set_script(load("res://scripts/target_dummy.gd"))
	enemy.position = Vector3(4.0, 0.0, -4.5)
	scene.add_child(enemy)
	var bot := enemy.get_node("TrainingBot")
	bot.set("survival_role", "charger")
	bot.set("_move_velocity", Vector3(18.0, 0.0, 0.0))
	bot.call("_move_bot", enemy, 0.4)
	_check(enemy.global_position.x < 6.0, "déplacement rapide arrêté par l'épave")
	_check(_outside_cover(enemy, bot), "déplacement normal hors de la collision du décor")

	enemy.global_position = Vector3(4.0, 0.0, -4.5)
	enemy.scale = Vector3.ONE * 1.5
	bot.set("_charge_target", Vector3(11.0, 0.0, -4.5))
	bot.set("_charge_remaining", 0.8)
	bot.call("_advance_charge", enemy, 0.4)
	_check(enemy.global_position.x < 5.5, "charge du grand robot arrêtée par l'épave")
	_check(float(bot.get("_charge_remaining")) <= 0.0, "charge interrompue au contact")
	_check(_outside_cover(enemy, bot), "grand robot hors de la collision du décor")

	enemy.global_position = Vector3(7.5, 0.0, -4.5)
	bot.set("_move_velocity", Vector3.ZERO)
	bot.call("_move_bot", enemy, 1.0 / 60.0)
	_check(enemy.global_position.distance_to(Vector3(7.5, 0.0, -4.5)) > 0.5, "robot dégagé d'un obstacle préexistant")
	_check(_outside_cover(enemy, bot), "robot dégagé sans rester dans le décor")

	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("BOT OBSTACLE COLLISION TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BOT OBSTACLE COLLISION TEST: FAIL (%d)" % failures.size())
		quit(1)


func _outside_cover(enemy: StaticBody3D, bot: Node) -> bool:
	var query: PhysicsShapeQueryParameters3D = bot.call("_bot_shape_query", enemy)
	return query != null and enemy.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
