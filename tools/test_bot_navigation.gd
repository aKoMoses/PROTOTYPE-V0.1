extends SceneTree

const NAVIGATION := preload("res://scripts/bot_navigation.gd")

var failures: Array[String] = []
var world: Node3D
var actor: StaticBody3D
var navigator = NAVIGATION.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	actor = _actor(Vector3(-8.0, 0.0, 0.0))
	await physics_frame
	_check(navigator.is_segment_clear(actor, actor.position, Vector3(8.0, 0.0, 0.0)), "empty terrain has a clear direct route")
	_check(is_equal_approx(navigator.route_distance(actor, Vector3(8.0, 0.0, 0.0), 0.0), 16.0), "direct route reports its actual distance")
	_check(not navigator.is_destination_clear(actor, Vector3(28.0, 0.0, 0.0)), "goals beyond the arena boundary are rejected")
	_check(is_inf(navigator.route_distance(actor, Vector3(28.0, 0.0, 0.0), 0.0)), "unplayable goals have no route cost")

	# A thin, long wall cannot be solved by the old local left/right sidestep.
	var wall := _wall(Vector3.ZERO, Vector3(0.20, 2.0, 38.0))
	await physics_frame
	navigator.invalidate(true)
	var before := Time.get_ticks_usec()
	var distance := navigator.route_distance(actor, Vector3(8.0, 0.0, 0.0), 1.0, 21.0)
	print("Long-wall first route: %.2f ms / %.2f m" % [float(Time.get_ticks_usec() - before) / 1000.0, distance])
	_check(not is_inf(distance) and distance > 40.0, "whole-map route goes around a long wall near the survival boundary")
	await _walk(Vector3(8.0, 0.0, 0.0), 21.0, 360, "long-wall detour")
	# The factory has its own world-space centre. Retained grids and waypoints
	# must follow that centre while collision queries keep world coordinates.
	var factory_center := Vector3(54.0, 0.0, -10.0)
	actor.position = factory_center + Vector3(-8.0, 0.0, 0.0)
	wall.position = factory_center
	navigator.arena_center = factory_center
	await physics_frame
	var factory_goal := factory_center + Vector3(8.0, 0.0, 0.0)
	_check(navigator.is_destination_clear(actor, factory_goal, 21.0), "shifted factory goal is playable")
	_check(not navigator.is_destination_clear(actor, factory_center + Vector3(22.0, 0.0, 0.0), 21.0), "shifted factory boundary rejects outside goals")
	var factory_route: float = navigator.route_distance(actor, factory_goal, 1.0, 21.0)
	_check(not is_inf(factory_route) and factory_route > 40.0, "shifted grid preserves the long-wall detour")
	await _walk(factory_goal, 21.0, 360, "shifted-factory detour")
	wall.position = Vector3.ZERO
	navigator.arena_center = Vector3.ZERO
	await physics_frame
	actor.position = Vector3(-0.88, 0.0, 0.0)
	navigator.invalidate()
	var close_to_cover: Vector3 = navigator.get_direction(actor, Vector3(8.0, 0.0, 0.0), 0.0, 21.0)
	_check(close_to_cover.length_squared() > 0.5, "actor pushed inside route padding can safely depart a cover edge")
	_check(not navigator.is_segment_clear(actor, actor.position, Vector3(8.0, 0.0, 0.0), 21.0), "initial padding overlap cannot hide the wall from a sweep")
	_check(navigator.is_segment_clear(actor, actor.position, actor.position + close_to_cover * 0.15, 21.0), "tight departure motion stays clear of the actual wall")
	wall.queue_free()
	await physics_frame

	# The exit of this U is opposite the objective. A competent route initially
	# increases its distance to the objective and retains that detour.
	actor.position = Vector3(0.0, 0.0, 2.0)
	var u_walls: Array[StaticBody3D] = [
		_wall(Vector3(-5.0, 0.0, 0.0), Vector3(0.4, 2.0, 8.0)),
		_wall(Vector3(5.0, 0.0, 0.0), Vector3(0.4, 2.0, 8.0)),
		_wall(Vector3(0.0, 0.0, 4.0), Vector3(10.0, 2.0, 0.4)),
	]
	await physics_frame
	navigator.invalidate(true)
	var exit_direction: Vector3 = navigator.get_direction(actor, Vector3(0.0, 0.0, 10.0), 1.0)
	_check(exit_direction.z < -0.1, "U-shaped cover chooses the rear exit instead of pressing against its base")
	_check(int(navigator.get_debug_state().expansions) <= NAVIGATION.MAX_SEARCH_EXPANSIONS, "route search has a fixed expansion budget")
	await _walk(Vector3(0.0, 0.0, 10.0), 27.0, 300, "U-shaped-cover escape")
	for u_wall in u_walls:
		u_wall.queue_free()
	await physics_frame

	# Full-sized and boss-sized robots must not share an occupancy map when the
	# same doorway is wide enough for only the smaller capsule.
	actor.position = Vector3(0.0, 0.0, -4.0)
	var gate_a := _wall(Vector3(-5.5, 0.0, 0.0), Vector3(9.0, 2.0, 0.3))
	var gate_b := _wall(Vector3(5.5, 0.0, 0.0), Vector3(9.0, 2.0, 0.3))
	var big := _actor(Vector3(0.0, 0.0, -4.0))
	big.scale = Vector3.ONE * 1.5
	await physics_frame
	navigator.invalidate(true)
	_check(navigator.is_segment_clear(actor, actor.position, Vector3(0.0, 0.0, 4.0)), "normal robot fits a two-metre doorway")
	_check(not navigator.is_segment_clear(big, big.position, Vector3(0.0, 0.0, 4.0)), "scaled boss capsule cannot cut through the narrow doorway")
	var big_nav = NAVIGATION.new()
	var big_distance: float = big_nav.route_distance(big, Vector3(0.0, 0.0, 4.0), 0.0)
	_check(not is_inf(big_distance) and big_distance > 20.0, "scaled robot receives a wide detour around the gate")
	_check(not navigator.is_destination_clear(actor, Vector3(5.5, 0.0, 0.0)), "embedded destination is inaccessible")
	_check(is_inf(navigator.route_distance(actor, Vector3(5.5, 0.0, 0.0), 0.0)), "embedded destination is never marked reachable")
	gate_a.queue_free()
	gate_b.queue_free()
	big.queue_free()
	await physics_frame

	# Permanent terrain can be changed by a map script. A fresh obstruction on
	# a retained route must refresh the shared grid without explicit invalidation.
	actor.position = Vector3(-8.0, 0.0, 0.0)
	var original_wall := _wall(Vector3.ZERO, Vector3(0.4, 2.0, 6.0))
	await physics_frame
	navigator.invalidate(true)
	navigator.get_direction(actor, Vector3(8.0, 0.0, 0.0), 0.0)
	var original_path: Array = navigator.get("_path")
	_check(not original_path.is_empty(), "dynamic-geometry fixture has an initial retained route")
	var new_blocker := _wall(original_path[0], Vector3(2.0, 2.0, 2.0))
	await physics_frame
	var replanned: Vector3 = navigator.get_direction(actor, Vector3(8.0, 0.0, 0.0), 0.1)
	_check(replanned.length_squared() > 0.5, "new permanent cover triggers a usable replacement route")
	var refreshed_path: Array = navigator.get("_path")
	var all_waypoints_clear := true
	for waypoint in refreshed_path:
		all_waypoints_clear = all_waypoints_clear and navigator.is_destination_clear(actor, waypoint)
	_check(all_waypoints_clear, "automatic geometry refresh removes newly occupied grid cells")
	await _walk(Vector3(8.0, 0.0, 0.0), 27.0, 240, "updated-cover detour")
	original_wall.queue_free()
	new_blocker.queue_free()
	await physics_frame

	# An inaccessible pocket must terminate without producing an unsafe route.
	actor.position = Vector3(-8.0, 0.0, 0.0)
	_wall(Vector3(0.0, 0.0, 3.0), Vector3(6.4, 2.0, 0.4))
	_wall(Vector3(0.0, 0.0, -3.0), Vector3(6.4, 2.0, 0.4))
	_wall(Vector3(3.0, 0.0, 0.0), Vector3(0.4, 2.0, 6.4))
	_wall(Vector3(-3.0, 0.0, 0.0), Vector3(0.4, 2.0, 6.4))
	await physics_frame
	navigator.invalidate(true)
	_check(is_inf(navigator.route_distance(actor, Vector3.ZERO, 0.0)), "sealed pocket has no route")
	_check(navigator.get_direction(actor, Vector3.ZERO, 0.0) == Vector3.ZERO, "unreachable objective does not steer through a wall")
	world.queue_free()
	await process_frame
	await _test_authored_arena()
	if failures.is_empty():
		print("BOT NAVIGATION TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BOT NAVIGATION TEST: FAIL (%d)" % failures.size())
		quit(1)


func _test_authored_arena() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame
	# Preserve active world collisions while manually stepping the controller.
	# process_mode = DISABLED removes inherited CollisionObject3D bodies.
	scene.set_process(false)
	scene.set_physics_process(false)
	for node in scene.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	var target := scene.get_node("TargetDummy") as CollisionObject3D
	var controller := target.get_node("TrainingBot")
	target.call("set_training_bot_enabled", false)
	for name in ["HealthPadNorth", "HealthPadSouth", "HealthPadWest", "HealthPadEast"]:
		target.position = Vector3.ZERO
		controller.call("reset_clock")
		var destination: Vector3 = (scene.get_node(name) as Node3D).global_position
		var route: float = controller.get("_navigation").route_distance(target, destination, 0.0)
		_check(route > target.position.distance_to(destination) + 1.0, "%s regression retains active cover and requires an actual detour" % name)
		var reached := false
		var stayed_clear := true
		for step in range(600):
			controller.set("_elapsed", float(step) * 0.05)
			controller.call("_update_duel_movement", target, destination, true, 0.05)
			var query: PhysicsShapeQueryParameters3D = controller.call("_bot_shape_query", target)
			if not target.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				stayed_clear = false
				break
			if target.global_position.distance_to(destination) < 0.70:
				reached = true
				break
			if step % 12 == 0:
				await physics_frame
		_check(stayed_clear, "production acceleration toward %s never overlaps terrain" % name)
		_check(reached, "production bot routes around authored covers to %s (ended %s)" % [name, target.global_position])
	scene.queue_free()
	await process_frame


func _walk(destination: Vector3, limit: float, max_steps: int, label: String) -> void:
	var was_clear := true
	var reached := false
	var furthest_z := 0.0
	for step in range(max_steps):
		var direction: Vector3 = navigator.get_direction(actor, destination, float(step) * 0.05 + 2.0, limit)
		var motion := direction * minf(0.25, actor.position.distance_to(destination))
		if not navigator.is_segment_clear(actor, actor.position, actor.position + motion, limit):
			print("Blocked %s step %d at %s direction %s route %s" % [label, step, actor.position, direction, navigator.get_debug_state()])
			was_clear = false
			break
		actor.position += motion
		furthest_z = maxf(furthest_z, absf(actor.position.z))
		if actor.position.distance_to(destination) < 0.45:
			reached = true
			break
		# Refresh broadphase after each handful of synthetic movement steps.
		if step % 8 == 0:
			await physics_frame
	_check(was_clear, "%s never clips or cuts an obstacle corner" % label)
	_check(reached, "%s reaches its objective" % label)
	if label == "long-wall detour":
		_check(furthest_z > 19.5 and furthest_z <= limit, "long detour uses the entire legal map")


func _actor(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 2
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.7
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	body.add_child(collision)
	world.add_child(body)
	return body


func _wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.position = at + Vector3.UP * size.y * 0.5
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	return wall


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
