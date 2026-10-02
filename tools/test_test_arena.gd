extends SceneTree

const NAV := preload("res://scripts/bot_navigation.gd")
const TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const BUSH_STATE := preload("res://scripts/bush_state.gd")
var failures := 0
var scene: Node3D
var player: CharacterBody3D
var bot: StaticBody3D


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	player = scene.get("player")
	bot = scene.get("target")
	var flow := scene.get("game_flow") as CanvasLayer
	flow.call("_select_arena", "test")
	flow.call("_start_duel")
	player.call("set_gameplay_enabled", false)
	bot.call("set_training_bot_enabled", false)
	await physics_frame
	await physics_frame
	_check(scene.get("arena_variant") == "test", "Duel solo starts the selected test map")
	var arena := scene.get_node("TestArena")
	var ground: MeshInstance3D = arena.get_node("Ground")
	_check(is_equal_approx((ground.mesh as PlaneMesh).size.x * ground.scale.x, 36.0) and is_equal_approx((ground.mesh as PlaneMesh).size.y * ground.scale.z, 30.0), "test map is 36 m wide and 30 m deep")
	_check(arena.get_node("NorthLimit").position.z == -14.5, "base perimeter is halved")
	_check(is_equal_approx(arena.get_node("EastLimit").position.x, 17.4), "horizontal perimeter follows the longer rectangle")
	var ground_cover_count := 0
	for body in arena.find_children("*", "StaticBody3D", true, false):
		if str(body.name).ends_with("LaneCover"):
			ground_cover_count += 1
	_check(ground_cover_count == 4 and not arena.has_node("NorthWestBlock") and not arena.has_node("WestPocketLong") and not arena.has_node("NorthWestAngle"), "only four short ground covers replace the twelve old obstacles")
	_check(get_nodes_in_group("repair_kits").size() == 4, "only four active repair kits")
	_check(get_nodes_in_group("bush_placeholder").size() == 8, "eight large test bushes conceal actors")
	var bush_centres_match := true
	for bush in get_nodes_in_group("bush_placeholder"):
		var visual: Node3D = bush.get_node("GroundedVegetation")
		var centre: Vector3 = bush.get_meta("bush_center")
		bush_centres_match = bush_centres_match and Vector2(centre.x, centre.z).distance_to(Vector2(visual.global_position.x, visual.global_position.z)) < 0.01
		bush_centres_match = bush_centres_match and is_equal_approx(float(bush.get_meta("bush_radius")), float(visual.get_meta("foliage_radius")))
	_check(bush_centres_match, "test concealment matches the scaled visible foliage")
	_check(not scene.get_node("Ground").visible and scene.get_node("WestSpine").collision_layer == 0, "classic geometry is disabled")
	print("Spawns: ", player.position, " / ", bot.position)
	_check(absf(player.position.z - 11.8) < 0.05 and absf(bot.position.z + 11.8) < 0.05, "opposite spawns inside the compact map")
	var garage: Control = flow.get("_forge_garage")
	if garage == null:
		flow.call("_open_equipment")
		garage = flow.get("_forge_garage")
	_check(garage != null and garage.get("arena_buttons").has("test"), "MAP TEST is available in the Garage")
	flow.call("_start_duel")
	flow.set_process(false)
	player.call("set_gameplay_enabled", false)
	player.set_physics_process(false)
	bot.call("set_training_bot_enabled", false)
	# Keep movement assertions independent of saved chassis and menu camera poses.
	player.call("set_robot", "polyvalent")
	scene.get_node("CameraRig").set_process(false)
	var movement_camera := root.get_camera_3d()
	movement_camera.global_position = Vector3(0, 30, 24)
	movement_camera.look_at(Vector3.ZERO)
	for x in [-3.5, 3.5]:
		for direction in [-1.0, 1.0]:
			player.position = Vector3(x, 0, 11.0 if direction < 0 else -9.8)
			var highest := 0.0
			for frame in range(255):
				player.call("set_touch_move_vector", Vector2(0, direction))
				player.call("_update_movement", 1.0 / 60.0)
				highest = maxf(highest, player.position.y)
				await physics_frame
			print("Player ramp: ", player.position, " peak=", highest)
			_check(highest > 2.39 and player.position.y < 0.05, "player crosses platform via both ramps at x=%.1f direction=%.0f" % [x, direction])
	player.position = Vector3(-3.5, 2.4, 0.6)
	for frame in range(90):
		player.call("set_touch_move_vector", Vector2.RIGHT)
		player.call("_update_movement", 1.0 / 60.0)
		await physics_frame
	print("Player bridge: ", player.position)
	_check(player.position.x > 3 and is_equal_approx(player.position.y, 2.4), "player crosses the elevated bridge")
	for side in [-1.0, 1.0]:
		var cover: StaticBody3D = arena.get_node("WestDeckCover" if side < 0 else "EastDeckCover")
		_check(not (arena.get("surfaces") as Array).has(cover) and not TRAVERSAL.exclusions(player).has(cover.get_rid()), "deck cover remains solid to actors on side %.0f" % side)
		for z in [-1.5, 0.6, 2.7]:
			var shot_start := Vector3(side * 3.0, 3.3, z)
			var shot_end := Vector3(side * 6.5, 3.3, z)
			var shot_query := PhysicsRayQueryParameters3D.create(shot_start, shot_end, 1)
			var shot_hit := player.get_world_3d().direct_space_state.intersect_ray(shot_query)
			_check(shot_hit.get("collider") == cover if z == 0.6 else shot_hit.is_empty(), "deck cover stops torso shots but leaves both ends exposed on side %.0f z=%.1f" % [side, z])
		var high_query := PhysicsRayQueryParameters3D.create(Vector3(side * 3.0, 4.0, 0.6), Vector3(side * 6.5, 4.0, 0.6), 1)
		_check(player.get_world_3d().direct_space_state.intersect_ray(high_query).is_empty(), "deck cover leaves a firing line above its cap on side %.0f" % side)
		player.position = Vector3(side * 3.2, 2.4, 0.6)
		for frame in range(40):
			player.call("set_touch_move_vector", Vector2(side, 0))
			player.call("_update_movement", 1.0 / 60.0)
			await physics_frame
		print("Player cover: ", player.position)
		_check(absf(player.position.x) > 3.25 and absf(player.position.x) < 3.9 and is_equal_approx(player.position.y, 2.4), "player cannot pass through the deck cover on side %.0f" % side)
	player.position = Vector3(6.5, 0, 0.6)
	for frame in range(40):
		player.call("set_touch_move_vector", Vector2.LEFT)
		player.call("_update_movement", 1.0 / 60.0)
		await physics_frame
	_check(player.position.x >= 5.35 and is_zero_approx(player.position.y), "vertical platform edges cannot be climbed")
	var navigation := NAV.new()
	bot.position = Vector3(3.5, 0, -10.0)
	var controller := bot.get_node("TrainingBot")
	var highest := 0.0
	for frame in range(520):
		var direction := navigation.get_direction(bot, Vector3(3.5, 0, 10.8), float(frame) / 60.0, 13.4)
		controller.set("_move_velocity", direction * 3.0)
		controller.call("_move_bot", bot, 1.0 / 60.0)
		highest = maxf(highest, bot.position.y)
		await physics_frame
	print("Bot traversal: ", bot.position, " peak=", highest, " navigation=", navigation.get_debug_state())
	_check(highest > 2.39 and bot.position.z > 10.0 and bot.position.y < 0.05, "bot navigates up and down the platform")
	player.position = Vector3(0, 0, 12)
	for side in [-1.0, 1.0]:
		navigation.invalidate()
		bot.position = Vector3(side * 4.65, 2.4, -1.5)
		var destination := Vector3(side * 4.65, 2.4, 2.7)
		_check(not navigation.is_segment_clear(bot, bot.position, destination, 13.4), "bot rejects a route through deck cover on side %.0f" % side)
		var inner_x := absf(bot.position.x)
		for frame in range(360):
			if Vector2(bot.position.x - destination.x, bot.position.z - destination.z).length() < 0.15:
				break
			var direction := navigation.get_direction(bot, destination, float(frame) / 60.0, 13.4)
			controller.set("_move_velocity", direction * 3.0)
			controller.call("_move_bot", bot, 1.0 / 60.0)
			inner_x = minf(inner_x, absf(bot.position.x))
			await physics_frame
		_check(bot.position.distance_to(destination) < 0.25 and inner_x < 3.8 and is_equal_approx(bot.position.y, 2.4), "bot goes around deck cover through the inner lane on side %.0f" % side)
	bot.position = Vector3(7, 0, 0.6)
	_check(not navigation.is_segment_clear(bot, bot.position, Vector3(3.5, 2.4, 0.6), 13.4), "bot rejects a shortcut through a vertical ledge")
	for side in [-1.0, 1.0]:
		bot.position = Vector3(side * 14.0, 0, -9)
		var destination := Vector3(side * 14.0, 0, 9)
		_check(navigation.is_segment_clear(bot, bot.position, destination), "extended outer lane remains open beyond the old square on side %.0f" % side)
		_check(is_finite(navigation.route_distance(bot, Vector3(side * 14, 0, 0), 0)), "bot can plan a route to the side heal on side %.0f" % side)
		_check(not navigation.is_destination_clear(bot, Vector3(side * 14, 0, 14)), "bot rejects destinations beyond the shorter north-south boundary on side %.0f" % side)
		var bush: Node3D = arena.get_node(("West" if side < 0 else "East") + "NorthLaneBush")
		bot.position = BUSH_STATE.center(bush)
		player.position = bot.position + Vector3(0, 0, 3.0)
		_check(BUSH_STATE.find_bush(bot) == bush and not BUSH_STATE.visible_to(bot, player, false, true), "side bush hides an actor from an outside observer on side %.0f" % side)
		_check(navigation.is_destination_clear(bot, bot.position), "bush conceals without blocking movement on side %.0f" % side)
	player.position = Vector3(5.2, 2.4, 0.6)
	bot.position = Vector3(9, 0, 0.6)
	await physics_frame
	await physics_frame
	var start := Vector3(5.65, 3.3, 0.6)
	var direction := TRAVERSAL.shot_direction(player, start, Vector3.RIGHT)
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * 8, 1 | 2, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	print("Downward shot: ", direction, " hit=", hit, " visible=", bot.call("is_visible_to", player))
	_check(direction.y < -0.1 and hit.get("collider") == bot, "player can aim down from the platform to the bot")
	start = bot.position + Vector3(-0.6, 0.9, 0)
	direction = TRAVERSAL.shot_direction(bot, start, Vector3.LEFT)
	query = PhysicsRayQueryParameters3D.create(start, start + direction * 8, 1 | 4, [bot.get_rid()])
	hit = bot.get_world_3d().direct_space_state.intersect_ray(query)
	_check(direction.y > 0.1 and hit.get("collider") == player, "bot can aim up to the player on the platform")
	var tracker: CanvasLayer = scene.get("sight_tracker")
	_check(tracker.call("_map_half_extents") == Vector2(17.4, 14.5), "minimap uses rectangular arena dimensions")
	var map_rect: Rect2 = tracker.call("_map_rect", Vector2(200, 200))
	_check(is_equal_approx(map_rect.size.x / map_rect.size.y, 1.2), "minimap preserves the rectangle aspect ratio")
	_check(tracker.call("_map_point", Vector3(17.4, 0, 14.5), Vector2(200, 200)) == map_rect.end, "minimap places the east-south corner on the rectangle boundary")
	for kit in get_nodes_in_group("repair_kits"):
		_check(kit.find_children("*", "CollisionShape3D", true, false).size() == 1, "repair kit has one collection volume: " + str(kit.name))
		kit.call("reset_for_round", false)
		player.call("reset_combat_state")
		player.position = kit.global_position
		player.call("take_damage", 300.0, "map_test", "test_repair")
		kit.call("set_collection_active", true)
		_check(float(kit.call("try_collect", player)) > 0.0, "each exposed repair point heals the player: " + str(kit.name))
		_check(BUSH_STATE.find_bush(player) == null, "healing requires leaving the bushes: " + str(kit.name))
	scene.call("prepare_round", flow.get("loadout"))
	_check(player.position == Vector3(-3.5, 0, 11.8) and bot.position == Vector3(3.5, 0, -11.8), "round reset restores test spawns")
	scene.call("set_arena_variant", "classic")
	await physics_frame
	_check(scene.get_node("Ground").visible and scene.get_node("WestSpine").collision_layer == 1, "classic arena restores its geometry")
	_check(not arena.visible and get_nodes_in_group("repair_kits").size() == 4, "test arena and its repairs retire cleanly")
	_check(arena.get_node("WestDeckCover").collision_layer == 0 and arena.get_node("EastDeckCover").collision_layer == 0, "deck covers retire with the test map")
	scene.call("set_arena_variant", "test")
	_check(arena.get_node("WestDeckCover").collision_layer == 1 and arena.get_node("EastDeckCover").collision_layer == 1, "deck covers restore when the test map returns")
	scene.call("set_arena_variant", "hazards")
	_check(scene.get("arena_variant") == "hazards" and not arena.visible, "hazard variant retains the classic map")
	print("TEST ARENA: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
