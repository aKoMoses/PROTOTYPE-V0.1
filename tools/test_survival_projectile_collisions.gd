extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	scene.set("records_path", "user://test_survival_projectile_collisions.json")
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player := scene.get_node("Player") as PhysicsBody3D
	var center := PhysicsRayQueryParameters3D.create(Vector3(-2.0, 0.9, 0.0), Vector3(2.0, 0.9, 0.0))
	center.collision_mask = 1 | 2 | 8
	center.exclude = [player.get_rid()]
	if not player.get_world_3d().direct_space_state.intersect_ray(center).is_empty():
		_failures.append("le centre vide de l'arène intercepte un projectile")
	scene.call("_choose_weapon", "blaster")
	scene.call("_begin_wave_combat")
	scene.call("_clear_enemies")
	await physics_frame
	scene.call("_spawn_enemy", Vector3(0.0, 0.0, -4.0), "shooter")
	scene.call("_spawn_enemy", Vector3(0.0, 0.0, -7.0), "shooter")
	var enemies: Array = scene.get("_enemies")
	var front := enemies[0] as StaticBody3D
	var rear := enemies[1] as StaticBody3D
	front.call("set_training_bot_enabled", false)
	rear.call("set_training_bot_enabled", false)
	await physics_frame
	var line := PhysicsRayQueryParameters3D.create(Vector3(0.0, 0.9, 0.0), Vector3(0.0, 0.9, -10.0))
	line.collision_mask = 1 | 2 | 8
	line.exclude = [player.get_rid()]
	if player.get_world_3d().direct_space_state.intersect_ray(line).get("collider") != front:
		_failures.append("l'ennemi vivant devant n'est pas la première cible")
	front.call("take_damage", 5000.0, "test", "corpse_front")
	await physics_frame
	if player.get_world_3d().direct_space_state.intersect_ray(line).get("collider") != rear:
		_failures.append("le cadavre intercepte encore la trajectoire")
	var rear_health := float(rear.call("get_health"))
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	await create_timer(0.6, true, false, false).timeout
	if float(rear.call("get_health")) >= rear_health:
		_failures.append("le projectile ne traverse pas le cadavre vers l'ennemi vivant")
	front.call("reset_combat_state")
	if front.collision_layer != 2:
		_failures.append("une cible réinitialisée n'est plus touchable")
	if _failures.is_empty():
		print("SURVIVAL PROJECTILE COLLISIONS: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("SURVIVAL PROJECTILE COLLISIONS: FAIL (%d)" % _failures.size())
		quit(1)
