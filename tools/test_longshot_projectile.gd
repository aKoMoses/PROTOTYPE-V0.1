extends SceneTree

const STATE := preload("res://scripts/longshot_state.gd")
const PROJECTILE := preload("res://scripts/longshot_projectile.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	var stage := Node3D.new()
	stage.name = "LongshotProjectileTest"
	root.add_child(stage)
	current_scene = stage
	call_deferred("_run")


func _run() -> void:
	_test_state()
	await _test_first_collision()
	await _test_enhanced_grazing()
	await _test_overlap_and_muzzle_guard()
	await _test_multiple_colliders()
	await _test_range_and_shooter_movement()
	await _test_magnetic_area()
	for failure in _failures:
		push_error("LONGSHOT: " + failure)
	print("LONGSHOT PROJECTILE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_state() -> void:
	var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS.get("longshot", {})
	_check(not definition.is_empty(), "centralized LONGSHOT definition exists")
	if definition.is_empty():
		return
	var state := STATE.new()
	var other := STATE.new()
	for shot in range(1, 16):
		_check(state.next_enhanced() == (shot % 5 == 0), "next projectile enhanced exactly at rank %d" % shot)
		_check(state.commit_shot() == (shot % 5 == 0), "emitted projectile enhanced exactly at rank %d" % shot)
	_check(state.normal_shots() == 0 and other.shots_fired == 0, "cycle wraps and belongs to its weapon instance")
	state.reset()
	_check(state.shots_fired == 0 and not state.is_enhanced_ready(), "explicit replacement/death reset clears cycle")
	var start := float(definition.distance_start)
	var maximum := float(definition.distance_max)
	var base := float(definition.damage)
	_check(is_equal_approx(STATE.damage_at_distance(0.0, false), base), "contact damage equals base")
	_check(is_equal_approx(STATE.distance_multiplier(start), 1.0), "distance bonus starts continuously")
	_check(is_equal_approx(STATE.damage_at_distance(-10.0, false), base), "negative distance cannot reduce base damage")
	_check(is_equal_approx(STATE.damage_at_distance(start - 0.001, false), base), "short-range damage remains unchanged")
	_check(is_equal_approx(STATE.distance_multiplier((start + maximum) * 0.5), 1.625), "medium distance uses linear progression")
	_check(is_equal_approx(STATE.distance_multiplier(maximum), 2.25), "maximum distance reaches 2.25")
	_check(is_equal_approx(STATE.distance_multiplier(maximum + 100.0), 2.25), "distance bonus remains capped")
	_check(is_equal_approx(STATE.damage_at_distance(maximum, true), base * 3.15), "enhanced maximum combines both multipliers")
	_check(is_equal_approx(STATE.damage_at_distance(maximum, true, definition, 2.0), base * 6.3), "power scales base once")
	_check(LOADOUT.stat_line("longshot").begins_with("36–81 dégâts"), "Forge stat line displays current distance damage")
	var description := LOADOUT.category_description("longshot")
	_check(description.contains("6 à 18 m") and description.contains("+125 %") and description.contains("projectile"), "Forge explains travelled distance and increased bonus")
	_check(absf(STATE.distance_multiplier(start + 0.001) - STATE.distance_multiplier(start)) < 0.001, "progression has no damage step")


func _test_first_collision() -> void:
	var front := _box(Vector3(0, 1, -4), Vector3(3, 2, 0.012))
	var rear := _box(Vector3(0, 1, -8), Vector3(3, 2, 0.2))
	await _settle()
	for speed in [60.0, 75.0]:
		var shot := _shot(Vector3(0, 1, 0), speed, 32, 0.1125 if speed > 60 else 0.075)
		var result := _record(shot)
		shot._physics_process(0.2)
		_check(int(result.count) == 1 and result.hit.get("collider") == front, "first thin wall wins at %.0f m/s and 5 Hz" % speed)
		_check(absf(float(result.distance) - 3.994) < 0.005, "damage distance ends at exact wall surface at %.0f m/s" % speed)
		_check(absf(float(result.hit.get("center_distance", -1)) - (3.994 - (0.1125 if speed > 60 else 0.075))) < 0.005, "sphere centre stops before wall surface at %.0f m/s" % speed)
		if not result.hit.is_empty():
			_check(absf(Vector3(result.hit.position).z + 3.994) < 0.005, "impact effect uses actual wall surface")
		shot._physics_process(1.0)
		_check(int(result.count) == 1, "completed projectile emits only one impact")
		await process_frame
	await _remove([front, rear])


func _test_enhanced_grazing() -> void:
	# Its near edge is 0.095 m from the centreline: normal radius misses,
	# enhanced radius reaches it. A centre-only ray would miss both shots.
	var edge := _box(Vector3(0.195, 1, -4), Vector3(0.2, 2, 0.05))
	await _settle()
	var normal := _shot(Vector3(0, 1, 0), 60, 8, 0.075)
	var normal_result := _record(normal)
	normal._physics_process(1.0)
	_check(int(normal_result.count) == 1 and normal_result.hit.is_empty(), "normal physical diameter misses a grazing edge")
	var enhanced := _shot(Vector3(0, 1, 0), 75, 8, 0.1125)
	var enhanced_result := _record(enhanced)
	enhanced._physics_process(1.0)
	_check(int(enhanced_result.count) == 1 and enhanced_result.hit.get("collider") == edge, "enhanced physical diameter catches the grazing edge at 1 Hz")
	await process_frame
	await _remove([edge])


func _test_overlap_and_muzzle_guard() -> void:
	var wall := _box(Vector3(0, 1, -1), Vector3(3, 2, 0.2))
	await _settle()
	var inside := _shot(Vector3(0, 1, -1), 60, 32, 0.075)
	var overlap_result := _record(inside)
	inside._physics_process(0.1)
	_check(overlap_result.hit.get("collider") == wall and is_zero_approx(float(overlap_result.distance)), "initial overlap ends at distance zero: %s" % overlap_result)
	var beyond := _shot(Vector3(0, 1, -1.8), 75, 32, 0.1125)
	var muzzle := beyond.global_position
	var guard_result := _record(beyond)
	beyond.resolve_muzzle_guard(Vector3(0, 1, 0))
	_check(guard_result.hit.get("collider") == wall and is_zero_approx(float(guard_result.distance)), "support-to-muzzle obstruction cannot shoot through cover")
	_check(beyond.global_position.is_equal_approx(muzzle), "muzzle guard preserves projectile origin")
	beyond._physics_process(0.5)
	_check(int(guard_result.count) == 1, "muzzle obstruction resolves once")
	await process_frame
	await _remove([wall])


func _test_multiple_colliders() -> void:
	var target := _box(Vector3(0, 1, -4), Vector3(0.7, 2, 0.7), 2)
	var duplicate := CollisionShape3D.new()
	var duplicate_shape := BoxShape3D.new()
	duplicate_shape.size = Vector3(0.72, 1.4, 0.72)
	duplicate.shape = duplicate_shape
	target.add_child(duplicate)
	await _settle()
	var shot := _shot(Vector3(0, 1, 0), 75, 32, 0.1125, [], 2)
	var result := _record(shot)
	shot._physics_process(0.4)
	shot._physics_process(0.4)
	_check(int(result.count) == 1 and result.hit.get("collider") == target, "multiple target colliders produce one damage event")
	await process_frame
	await _remove([target])


func _test_range_and_shooter_movement() -> void:
	var beyond := _box(Vector3(0, 1, -33), Vector3(3, 2, 0.2))
	var shooter := _box(Vector3(0, 1, 0), Vector3(1, 2, 1), 4)
	await _settle()
	for speed in [60.0, 75.0]:
		var excluded: Array[RID] = [shooter.get_rid()]
		var shot := _shot(Vector3(0, 1, 0), speed, 32, 0.1125 if speed > 60 else 0.075, excluded, 1 | 4)
		var result := _record(shot)
		shooter.position = Vector3(25, 1, 20)
		shot._physics_process(2.0)
		_check(int(result.count) == 1 and result.hit.is_empty(), "no wall hit beyond explicit range at %.0f m/s" % speed)
		_check(is_equal_approx(float(result.distance), 32.0) and shot.position.is_equal_approx(Vector3(0, 1, -32)), "normal and enhanced centre range stays exactly 32 m")
		await process_frame
	var target := _box(Vector3(0, 1, -14), Vector3(1, 2, 0.2), 2)
	await _settle()
	var flight := _shot(Vector3(0, 1, 0), 60, 32, 0.075, [], 2)
	var flight_result := _record(flight)
	flight._physics_process(0.1)
	shooter.position = Vector3(-100, 1, 100)
	flight._physics_process(0.2)
	_check(absf(float(flight_result.distance) - 13.9) < 0.005, "shooter movement leaves accumulated projectile travel unchanged")
	_check(STATE.damage_at_distance(float(flight_result.distance), false) > STATE.damage_at_distance(6.0, false), "impact damage uses travel after shooter movement")
	await process_frame
	await _remove([beyond, shooter, target])


func _test_magnetic_area() -> void:
	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 2, 0.14)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3(0, 1, -3)
	current_scene.add_child(area)
	await _settle()
	var shot := _shot(Vector3(0, 1, 0), 75, 32, 0.1125, [], 8)
	var result := _record(shot)
	shot._physics_process(0.5)
	_check(int(result.count) == 1 and result.hit.get("collider") == area, "magnetic Area3D intercepts the sphere sweep")
	await process_frame
	await _remove([area])


func _shot(at: Vector3, speed: float, maximum: float, radius: float, excluded: Array[RID] = [], mask: int = 1) -> Node3D:
	var shot := PROJECTILE.new()
	current_scene.add_child(shot)
	shot.global_position = at
	shot.configure(Vector3.FORWARD, speed, maximum, mask, excluded, radius)
	shot.set_physics_process(false)
	return shot


func _record(shot: Node3D) -> Dictionary:
	var result := {"count": 0, "hit": {}, "distance": -1.0}
	shot.finished.connect(func(hit: Dictionary, distance: float) -> void:
		result.count = int(result.count) + 1
		result.hit = hit
		result.distance = distance)
	return result


func _box(at: Vector3, dimensions: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	current_scene.add_child(body)
	return body


func _settle() -> void:
	await physics_frame
	await process_frame


func _remove(nodes: Array) -> void:
	for node in nodes:
		node.queue_free()
	await _settle()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
