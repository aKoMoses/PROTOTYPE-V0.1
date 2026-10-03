extends SceneTree

const TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const PROJECTILE := preload("res://scripts/live_projectile.gd")
var failures: Array[String] = []
var scene: Node3D
var player: CharacterBody3D
var bot: StaticBody3D
var hit_result: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_select_arena", "gyre")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	player = scene.get("player")
	bot = scene.get("target")
	player.set_physics_process(false)
	bot.call("set_training_bot_enabled", false)
	var mechanisms := scene.get_node("ArenaHazards")
	mechanisms.set_physics_process(false)
	var platform := TRAVERSAL.terrain(player)
	check(platform != null and platform.get("surfaces").size() == 3, "deck and both ramps expose walking surfaces")
	await physics_frame
	await physics_frame
	for side in [-1.0, 1.0]:
		player.global_position = Vector3(0, 0, side * 7.1)
		for tick in range(90):
			var motion := TRAVERSAL.motion(player, Vector3(0, 0, -side * 0.06))
			player.velocity = motion * 60
			player.move_and_slide()
			TRAVERSAL.snap(player)
			check(is_equal_approx(player.global_position.y, platform.call("height_at", player.global_position)), "player stays on the ramp height")
		check(is_equal_approx(player.global_position.y, 1.8), "player really climbs the deck from either ramp")
		for tick in range(90):
			player.velocity = TRAVERSAL.motion(player, Vector3(0, 0, side * 0.06)) * 60
			player.move_and_slide()
			TRAVERSAL.snap(player)
		check(is_zero_approx(player.global_position.y), "player really descends to the ground")
	check(not platform.call("segment_walkable", Vector3(3.4, 0, 1), Vector3(2, 1.8, 1)), "a vertical deck side cannot be climbed or dashed through")
	player.global_position = Vector3(0, 1.8, 0)
	var at := player.global_position
	mechanisms.call("advance", 7.0)
	check(player.global_position.is_equal_approx(at), "rotating floor does not pull elevated fighters down")
	player.global_position = Vector3(4, 0, 0)
	mechanisms.call("advance", 0.7)
	check(player.global_position.distance_to(Vector3(4, 0, 0)) > 0.1, "surrounding ring still transports grounded fighters")
	var controller := bot.get_node("TrainingBot")
	var navigation = controller.get("_navigation")
	player.global_position = Vector3(0, 1.8, 0)
	bot.global_position = Vector3(5.5, 0, 5.5)
	navigation.call("invalidate", true)
	var reached := false
	for tick in range(600):
		var time := float(tick) / 60
		controller.set("_elapsed", time)
		var direction: Vector3 = navigation.call("get_direction", bot, player.global_position, time, 11.5)
		controller.set("_move_velocity", direction * 5)
		controller.call("_move_bot", bot, 1.0 / 60)
		if bot.global_position.y > 1.7 and bot.global_position.distance_to(player.global_position) < 1.5:
			reached = true
			break
	check(reached, "actual bot movement finds a ramp and reaches an elevated opponent")
	await shot_between(Vector3(0, 1.8, 0), Vector3(0, 0, 7.5))
	await shot_between(Vector3(0, 0, 7.5), Vector3(0, 1.8, 0))
	var shield_ray := PhysicsRayQueryParameters3D.create(Vector3(1.8, 2.4, 0), Vector3(3.1, 2.4, 0), 1)
	check(not scene.get_world_3d().direct_space_state.intersect_ray(shield_ray).is_empty(), "deck shields genuinely block shots")
	flow.call("_select_arena", "resonance")
	await process_frame
	check(TRAVERSAL.terrain(player) == null and is_zero_approx(player.global_position.y) and is_zero_approx(bot.global_position.y), "leaving Forge restores flat movement and clears platform surfaces")
	print("GYRE PLATFORM TEST: %s (%d failures; player ramps, ledges, bot ascent, actual uphill/downhill projectiles, shield collision, rotors, map switch)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func shot_between(from: Vector3, to: Vector3) -> void:
	player.global_position = from
	bot.global_position = to
	await physics_frame
	var start := from + Vector3.UP * 0.9
	var flat := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
	var direction := TRAVERSAL.shot_direction(player, start, flat)
	check(signf(direction.y) == signf(to.y - from.y), "aim pitches toward an opponent at another height")
	hit_result = {}
	var shot := PROJECTILE.new()
	scene.add_child(shot)
	shot.global_position = start
	shot.configure(direction, 40, 20, 1 | 2 | 4, [player.get_rid()])
	shot.finished.connect(func(hit: Dictionary, _distance: float) -> void: hit_result = hit)
	for tick in range(80):
		await physics_frame
		if not is_instance_valid(shot):
			break
	check(hit_result.get("collider") == bot, "actual projectile hits opponent across the height difference")
