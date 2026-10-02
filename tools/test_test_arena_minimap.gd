extends SceneTree

const ARENA := preload("res://scripts/test_arena.gd")
const TRACKER := preload("res://scripts/sight_tracker.gd")
const REPAIR := preload("res://scenes/repair_kit.tscn")

class MapFixture extends Node3D:
	var arena_variant := "test"
	var duel_active := true
	var _arena_blockers: Array = []

class ActorProbe extends Node3D:
	var observed := false
	var aim_direction := Vector3.FORWARD
	func get_visibility_weight(_observer: Node3D) -> float:
		return 1.0 if observed else 0.0
	func is_gameplay_enabled() -> bool:
		return true

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func _run() -> void:
	# Real terrain shapes and the production tracker, independent of concurrent
	# robot-material changes. Actors only expose the observed/hidden contract.
	var world := MapFixture.new()
	root.add_child(world)
	current_scene = world
	var arena := ARENA.new()
	arena.name = "TestArena"
	world.add_child(arena)
	for x in [-3.5, 3.5]:
		arena._box("Platform", Vector3(x, 1.2, 0.6), Vector3(3.8, 2.4, 5.8), null)
		arena._ramp("NorthRamp", x, -8.6, -2.3, 0, 2.4, null)
		arena._ramp("SouthRamp", x, 3.5, 9.8, 2.4, 0, null)
	arena._box("Bridge", Vector3(0, 2.22, 0.6), Vector3(3.2, 0.36, 2.8), null)
	world._arena_blockers.assign(arena.surfaces)
	arena._bush("SideBush", Vector3(13, 0, 5), 1.6, 2.15)
	var kit := REPAIR.instantiate()
	kit.position = Vector3(14, 0, 0)
	arena.add_child(kit)
	kit.call("set_collection_active", false)
	var player := ActorProbe.new()
	var opponent := ActorProbe.new()
	opponent.position = Vector3(3.5, 2.4, 0.6)
	world.add_child(player)
	world.add_child(opponent)
	var tracker := TRACKER.new()
	world.add_child(tracker)
	tracker.configure(world, player, opponent)
	await process_frame
	var ramps: Array = tracker.get("_ramp_markers")
	for ramp in ramps:
		var uphill: Vector2 = ramp.direction
		_check(uphill.dot(Vector2.DOWN if ramp.position.z < 0 else Vector2.UP) > 0.99, "ramp arrow points uphill at z=%.1f" % ramp.position.z)
	var dimensions := Vector2(182, 182)
	var rect: Rect2 = tracker.call("_map_rect", dimensions)
	var centre: Vector2 = tracker.call("_map_point", Vector3.ZERO, dimensions)
	_check(centre.is_equal_approx(rect.get_center()), "terrain centre stays centred on the rectangular minimap")
	var x_step: Vector2 = tracker.call("_map_point", Vector3.RIGHT * 5, dimensions)
	var z_step: Vector2 = tracker.call("_map_point", Vector3.BACK * 5, dimensions)
	_check(is_equal_approx(centre.distance_to(x_step), centre.distance_to(z_step)), "bush footprints and terrain use the same world scale on both axes")
	var bush: Dictionary = (tracker.get("_bush_markers") as Array)[0]
	_check(bush.position == Vector3(13, 0, 5) and is_equal_approx(bush.radius, 1.6), "bush marker matches its world concealment footprint")
	var repair_positions: Array = (tracker.get("_repair_positions") as Array).duplicate()
	kit.call("set_point_enabled", false)
	tracker.call("_cache_obstacles")
	_check(tracker.get("_repair_positions") == repair_positions, "fixed heal locations do not reveal pickup availability")
	tracker.call("_process", 0.016)
	_check(not tracker.get_tracking_state().known, "fixed landmarks do not reveal an initially hidden opponent")
	opponent.observed = true
	tracker.call("_process", 0.016)
	var observed_position: Vector3 = tracker.get_tracking_state().last_position
	opponent.observed = false
	opponent.position = Vector3(-14, 0, -8)
	tracker.call("_cache_obstacles")
	tracker.call("_process", 0.2)
	_check(tracker.get_tracking_state().last_position == observed_position and not tracker.get_tracking_state().visible, "refreshing landmarks never follows hidden opponent movement")
	world.arena_variant = "classic"
	tracker.call("_cache_obstacles")
	_check((tracker.get("_walkable_polygons") as Array).is_empty() and (tracker.get("_ramp_markers") as Array).is_empty() and (tracker.get("_bush_markers") as Array).is_empty() and (tracker.get("_repair_positions") as Array).is_empty(), "changing maps clears every test-map landmark")
	world.arena_variant = "test"
	tracker.call("_cache_obstacles")
	_check(tracker.get("_repair_positions") == repair_positions, "returning to the test map restores heal locations without stale duplicates")
	print("TEST ARENA MINIMAP: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	current_scene = null
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
