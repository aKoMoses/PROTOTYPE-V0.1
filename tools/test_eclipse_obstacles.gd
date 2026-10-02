extends "res://tools/test_eclipse.gd"

var obstacles: Array[StaticBody3D] = []

func box(arena: Node3D, center: Vector3, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	arena.add_child(body)
	body.position = center + Vector3.UP
	body.rotation.y = yaw
	obstacles.append(body)
	return body

func clear_obstacles(player: CharacterBody3D) -> void:
	prepare(player)
	for obstacle in obstacles:
		obstacle.queue_free()
	obstacles.clear()
	await physics_frame
	await physics_frame

func run() -> void:
	var arena := Arena.new()
	root.add_child(arena)
	current_scene = arena
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 5
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(44, 0.2, 44)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	arena.add_child(floor_body)
	floor_body.position.y = -0.1
	var player := PLAYER.new()
	arena.add_child(player)
	prepare(player)
	await physics_frame

	box(arena, Vector3(4.4, 0, 0), Vector3(2, 2, 6))
	await physics_frame
	check(player.begin_touch_action("mobility"), "visée devant un obstacle refusée")
	player.set_eclipse_touch_vector(Vector2(1.0 / 3.0, 0))
	var preview: Vector3 = player._eclipse.destination
	check(preview.distance_to(Vector3(2.835, 0, 0)) < 0.025, "la sortie proche ne réduit pas la portée")
	check(player._eclipse._caption.text == "ÉCLIPSE · RELÂCHER", "obstacle marqué bloquant dans la présélection")
	player.end_touch_action("mobility")
	check(player.is_eclipse_travelling(), "relâchement sur obstacle refusé")
	player._eclipse.update(player, 0.3)
	check(player.global_position.distance_to(preview) < 0.01, "arrivée différente de la sortie annoncée")
	check(player._eclipse.fits(player, player.global_position, false), "corps dans le couvert après arrivée")
	await clear_obstacles(player)

	box(arena, Vector3(4.6, 0, 0), Vector3(2, 2, 6))
	await physics_frame
	check(player._perform_eclipse(Vector3(5, 0, 0)), "sortie au-delà du point visé refusée")
	player._eclipse.update(player, 0.3)
	check(player.global_position.distance_to(Vector3(6.165, 0, 0)) < 0.025, "la sortie proche n'augmente pas la portée")
	await clear_obstacles(player)

	box(arena, Vector3(11.6, 0, 0), Vector3(2, 2, 6))
	var victim := Victim.new()
	arena.add_child(victim)
	victim.position = Vector3(16, 0, 0)
	arena.targets = [victim]
	await physics_frame
	player.begin_touch_action("mobility")
	player.set_eclipse_touch_vector(Vector2.RIGHT)
	preview = player._eclipse.destination
	check(preview.x > 12.0, "sortie au-delà des 12 m invisible dans la visée")
	player.end_touch_action("mobility")
	check(player.is_eclipse_travelling(), "sortie au-delà des 12 m rejetée au relâchement")
	var network_script = load("res://scripts/network_player.gd")
	var remote = network_script.new()
	remote.authoritative = false
	remote.remote_controlled = true
	arena.add_child(remote)
	prepare(remote)
	remote._eclipse.receive_snapshot(remote, player._eclipse.snapshot())
	check(remote.is_eclipse_travelling() and remote._eclipse.destination.distance_to(preview) < 0.01, "snapshot rejette la sortie au-delà de portée")
	player._eclipse.update(player, 0.3)
	check(player.global_position.distance_to(Vector3(13.165, 0, 0)) < 0.025, "limite de portée ramène le joueur au départ")
	check(victim.health == 880.0 and victim.burn_duration == 3.5, "explosion et burn centrés sur la visée plutôt que sur la sortie")
	victim.queue_free()
	arena.targets = []
	remote._eclipse.cancel(remote)
	remote.queue_free()
	await clear_obstacles(player)
	check(not player._perform_eclipse(Vector3(13, 0, 0)) and not player._perform_eclipse(Vector3.INF), "visée hors portée ou non finie autorisée")

	var rotated := box(arena, Vector3(6, 0, 0), Vector3(2, 2, 6), PI / 6.0)
	await physics_frame
	var axis: Vector3 = rotated.global_basis.x
	var requested := Vector3(6, 0, 0) + axis * 0.7
	var exit: Vector3 = player._eclipse.resolve_destination(player, requested)
	check(exit.distance_to(Vector3(6, 0, 0) + axis * 1.565) < 0.025, "obstacle tourné : mauvais bord de sortie")
	await clear_obstacles(player)

	box(arena, Vector3(6, 0, 0), Vector3(6, 2, 2))
	await physics_frame
	exit = player._eclipse.resolve_destination(player, Vector3(6, 0, 0.7))
	check(exit.distance_to(Vector3(6, 0, 1.565)) < 0.025, "sortie latérale la plus proche ignorée")
	await clear_obstacles(player)

	box(arena, Vector3(6, 0, 0), Vector3(2, 2, 2))
	await physics_frame
	requested = Vector3(7.2, 0, 1.2)
	exit = player._eclipse.resolve_destination(player, requested)
	check(exit.distance_to(Vector3(7, 0, 1) + Vector3(1, 0, 1).normalized() * 0.565) < 0.025, "coin de couvert : sortie diagonale la plus proche ignorée")
	await clear_obstacles(player)

	box(arena, Vector3(4.2, 0, 0), Vector3(2, 2, 6))
	box(arena, Vector3(5.4, 0, 0), Vector3(2, 2, 6))
	await physics_frame
	exit = player._eclipse.resolve_destination(player, Vector3(4.7, 0, 0))
	check(exit.distance_to(Vector3(2.635, 0, 0)) < 0.025 and player._eclipse.fits(player, exit, false), "couverts superposés : sortie encore obstruée ou trop éloignée")
	await clear_obstacles(player)

	box(arena, Vector3(21.5, 0, 0), Vector3(2, 2, 6))
	await physics_frame
	exit = player._eclipse.resolve_destination(player, Vector3(21, 0, 0))
	check(exit.distance_to(Vector3(19.935, 0, 0)) < 0.025, "sortie choisie hors de l'arène")
	await clear_obstacles(player)

	check(player._perform_eclipse(Vector3(4, 0, 0)), "départ du cas d'obstacle tardif refusé")
	box(arena, Vector3(4.4, 0, 0), Vector3(2, 2, 6))
	await physics_frame
	player._eclipse.update(player, 0.3)
	check(player.global_position.distance_to(Vector3(2.835, 0, 0)) < 0.025 and player.visible, "obstacle tardif : retour au départ ou corps perdu")
	await clear_obstacles(player)

	var cylinder := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = 2.0
	cylinder_shape.height = 2.0
	collision.shape = cylinder_shape
	cylinder.add_child(collision)
	arena.add_child(cylinder)
	cylinder.position = Vector3(6, 1, 0)
	obstacles.append(cylinder)
	await physics_frame
	var started := Time.get_ticks_usec()
	exit = player._eclipse.resolve_destination(player, Vector3(6.8, 0, 0))
	print("ECLIPSE cylinder resolution: %d us" % (Time.get_ticks_usec() - started))
	check(exit.distance_to(Vector3(8.55, 0, 0)) < 0.03 and player._eclipse.fits(player, exit, false), "obstacle cylindrique ne rejoint pas la sortie proche")
	await clear_obstacles(player)

	current_scene = null
	root.get_node("GameSfx").call("clear")
	arena.queue_free()
	await process_frame
	await process_frame
	for failure in failures:
		push_error(failure)
	print("ECLIPSE OBSTACLES TEST: PASS" if failures.is_empty() else "ECLIPSE OBSTACLES TEST: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
