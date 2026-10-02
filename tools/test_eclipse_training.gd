extends SceneTree

const ECLIPSE := preload("res://scripts/eclipse.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func prepare(player: CharacterBody3D, at: Vector3) -> void:
	player.call("reset_combat_state")
	player.call("apply_loadout", {"mobility": "eclipse", "chassis": "balanced"})
	player.call("set_training_options", true, false, true)
	player.call("set_gameplay_enabled", true)
	player.global_position = at
	player.set_physics_process(false)


func run() -> void:
	var scene: Node3D = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Player")
	# Keep the actual training floor, camera and cover, without autonomous shots.
	for target in scene.call("get_training_targets"):
		target.process_mode = Node.PROCESS_MODE_DISABLED
	prepare(player, Vector3(0, 0, 24))
	await physics_frame
	await physics_frame
	check(ECLIPSE.fits(player, Vector3(4, 0, 24)), "sol de l'accueil bloque une arrivée libre")
	check(player.call("begin_touch_action", "mobility"), "visée tactile refusée en entraînement")
	player.call("set_eclipse_touch_vector", Vector2(1.0 / 3.0, 0))
	var destination: Vector3 = player.get("_eclipse").destination
	player.call("end_touch_action", "mobility")
	check(player.call("is_eclipse_travelling"), "relâchement tactile ne lance pas Eclipse en entraînement")
	player.get("_eclipse").update(player, 0.3)
	check(player.global_position.distance_to(destination) < 0.01, "arrivée tactile annulée par le sol")
	check(player.visible and player.collision_layer == 4 and player.collision_mask == 1, "corps non restauré après arrivée")

	prepare(player, Vector3(0, 0, 24))
	await physics_frame
	Input.action_press("game_mobility")
	player.call("_update_debug_effects")
	check(player.call("is_eclipse_aiming"), "maintien clavier refusé en entraînement")
	destination = player.get("_eclipse").destination
	Input.action_release("game_mobility")
	player.call("_update_debug_effects")
	check(player.call("is_eclipse_travelling"), "relâchement clavier ne lance pas Eclipse en entraînement")
	player.get("_eclipse").update(player, 0.3)
	check(player.global_position.distance_to(destination) < 0.01, "arrivée clavier annulée par le sol")

	# Exercise the real floor beyond the duel arena's default bounds as well.
	for start in [Vector3(-33, 0, 4), Vector3(0, 0, -30), Vector3(24, 0, 4)]:
		prepare(player, start)
		await physics_frame
		var at: Vector3 = start + Vector3(3, 0, 0)
		check(player.call("_perform_eclipse", at), "départ refusé dans une zone libre : %s" % start)
		player.get("_eclipse").update(player, 0.3)
		check(player.global_position.distance_to(at) < 0.01, "arrivée refusée dans une zone libre : %s" % start)

	prepare(player, Vector3(0, 0, 7.5))
	await physics_frame
	check(not ECLIPSE.fits(player, Vector3(7, 0, 7.5)), "séparation solide ignorée")
	prepare(player, Vector3(32, 0, 4))
	await physics_frame
	check(not ECLIPSE.fits(player, Vector3(32, 0, -2)), "caisse solide ignorée")
	prepare(player, Vector3(40, 0, 0))
	await physics_frame
	check(not ECLIPSE.fits(player, Vector3(44, 0, 0)), "limite du terrain ignorée")
	player.call("reset_combat_state")
	current_scene = null
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	await process_frame
	for failure in failures:
		push_error(failure)
	print("ECLIPSE TRAINING TEST: PASS" if failures.is_empty() else "ECLIPSE TRAINING TEST: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
