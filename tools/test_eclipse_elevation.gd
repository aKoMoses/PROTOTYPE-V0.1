extends SceneTree

const ECLIPSE := preload("res://scripts/eclipse.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func prepare(player: CharacterBody3D, point: Vector3) -> void:
	player.call("reset_combat_state")
	player.call("apply_loadout", {"mobility": "eclipse", "passive": "omnivamp"})
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.global_position = point


func check_surface(mesh: Mesh, terrain: Node3D, lift: float, message: String) -> void:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var matched := not vertices.is_empty()
	var lowest := INF
	var highest := -INF
	for point in vertices:
		matched = matched and absf(point.y - float(terrain.call("height_at", point)) - lift) < 0.002
		lowest = minf(lowest, point.y)
		highest = maxf(highest, point.y)
	check(matched, message)
	check(highest - lowest > 1.5, message + " covers both elevations")


func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("set_menu_showcase_enabled", false)
	scene.call("set_arena_variant", "test")
	scene.get("game_flow").set_process(false)
	var player: CharacterBody3D = scene.get("player")
	var bot: Node3D = scene.get("target")
	bot.call("set_training_bot_enabled", false)
	bot.position = Vector3(-12, 0, -12)
	var terrain := scene.get_node("TestArena")
	prepare(player, Vector3(0, 0, -5))
	await physics_frame
	await physics_frame
	check(player.call("begin_touch_action", "mobility"), "Eclipse targeting starts on the test map")
	player.call("set_eclipse_touch_vector", Vector2(3.5, 5.6) / 12.0)
	var eclipse = player.get("_eclipse")
	var expected := Vector3(3.5, 2.4, 0.6)
	check(eclipse.destination.distance_to(expected) < 0.01, "touch destination selects the upper platform")
	check(eclipse._caption.global_position.y > 3.1, "caption follows the destination floor")
	check_surface(eclipse._target_ring.mesh, terrain, 0.08, "destination outline follows the platforms and ground")
	check_surface(eclipse._target_disc.mesh, terrain, 0.06, "destination fill follows the platforms and ground")
	check_surface(eclipse._range_ring.mesh, terrain, 0.045, "range outline follows the ramps and ground")
	player.call("end_touch_action", "mobility")
	check(eclipse.travelling and eclipse.destination.distance_to(expected) < 0.01, "release preserves the previewed upper destination")
	eclipse.update(player, 0.12)
	var rising_particle := false
	for particle in eclipse._particles:
		rising_particle = rising_particle or particle.global_position.y > 1.5
	check(rising_particle and player.position == Vector3(0, 0, -5), "particles rise while the actor remains at departure")
	eclipse.update(player, 0.2)
	check(player.global_position.distance_to(expected) < 0.01 and player.visible, "Eclipse arrives on the platform")
	prepare(player, expected)
	await physics_frame
	player.call("begin_touch_action", "mobility")
	player.call("set_eclipse_touch_vector", Vector2(5.0, 0) / 12.0)
	var lower: Vector3 = eclipse.destination
	check(is_zero_approx(lower.y) and absf(lower.x - 8.5) < 0.01, "targeting from a platform selects the lower floor")
	player.call("end_touch_action", "mobility")
	eclipse.update(player, 0.3)
	check(player.global_position.distance_to(lower) < 0.01, "Eclipse arrives at the indicated lower floor")
	prepare(player, Vector3(0, 0, -5))
	await physics_frame
	for point in [Vector3(3.5, 2.4, 0.6), Vector3(-3.5, 1.2, -5.45), Vector3(0, 2.4, 0.6), Vector3(8.5, 0, 0.6)]:
		var camera := player.get_viewport().get_camera_3d()
		var screen := camera.unproject_position(point)
		var picked := ECLIPSE.pointer_destination(player, camera.project_ray_origin(screen), camera.project_ray_normal(screen))
		check(picked.distance_to(point) < 0.015, "mouse ray picks the visible surface at %s" % point)
	var ramp := ECLIPSE.resolve_destination(player, Vector3(-3.5, 0, -5.45))
	check(ramp.distance_to(Vector3(-3.5, 1.2, -5.45)) < 0.01, "ramp destination uses its exact slope height")
	check(ECLIPSE.fits(player, Vector3(3.5, 0, 0.6)), "platform arrival stays valid despite the supporting slab")
	check(not ECLIPSE.fits(player, Vector3(15, 0, 0)), "compact map boundaries reject outside arrivals")
	prepare(player, Vector3(3.5, 2.4, -2.3))
	await physics_frame
	check(player.call("_perform_eclipse", Vector3(3.5, 0, 9.7)), "12 m horizontal range works across elevation changes")
	eclipse.update(player, 0.3)
	check(absf(player.global_position.z - 9.7) < 0.01 and player.global_position.y < 0.05, "maximum range arrival follows the ramp foot")
	prepare(player, Vector3.ZERO)
	scene.call("set_arena_variant", "classic")
	await physics_frame
	player.call("begin_touch_action", "mobility")
	player.call("set_eclipse_touch_vector", Vector2.RIGHT / 3.0)
	check(eclipse._target_ring.mesh is TorusMesh and is_zero_approx(eclipse.destination.y), "classic map retains its flat targeting")
	player.call("cancel_touch_action", "mobility")
	print("ECLIPSE ELEVATION TEST: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
