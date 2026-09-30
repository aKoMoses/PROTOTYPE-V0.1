extends SceneTree

## Exercise the rendered cover field against real physics, in fixed world
## coordinates. Radius/fade are held constant so the corner tests measure
## occlusion presentation rather than the independent distance falloff.
const FOG_SCRIPT := preload("res://scripts/fog_of_war.gd")
const FIXED_DELTA := 1.0 / 60.0

class ObserverProbe extends Node3D:
	var vision_radius := 30.0
	var vision_fade_width := 0.0
	var visibility_epoch := 0
	func get_vision_radius() -> float:
		return vision_radius
	func get_vision_fade_width() -> float:
		return vision_fade_width
	func get_visibility_epoch() -> int:
		return visibility_epoch

var _scene: Node3D
var _observer: ObserverProbe
var _camera: Camera3D
var _fog: Node3D
var _probes: Array[Vector3] = []
var _checks := 0
var _failures: Array[String] = []
var _profile_costs := PackedFloat64Array()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	current_scene = _scene
	_observer = ObserverProbe.new()
	_scene.add_child(_observer)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 25.0, 18.0)
	_scene.add_child(_camera)
	var wall := StaticBody3D.new()
	wall.position = Vector3(8.0, 0.7, 0.0)
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.4, 4.0)
	collision.shape = box
	wall.add_child(collision)
	_scene.add_child(wall)
	_fog = _create_fog()
	for x in [6.0, 10.0, 14.0, 18.0]:
		for index in range(33):
			_probes.append(Vector3(x, 0.0, -8.0 + float(index) * 0.5))
	await physics_frame
	_snap()
	_test_spatial_penumbra()
	_test_stationary_stability()
	_test_world_anchored_history()
	_test_corner_traverse()
	_test_history_resets()
	_test_zero_parameters()
	current_scene = null
	_scene.queue_free()
	await process_frame
	_report()


func _create_fog() -> Node3D:
	var fog: Node3D = FOG_SCRIPT.new()
	_scene.add_child(fog)
	fog.call("configure", _observer, _camera)
	fog.set_process(false)
	fog.set_physics_process(false)
	return fog


func _snap() -> void:
	_fog.call("refresh_vision")
	_tick(1.0)


func _tick(delta: float) -> void:
	var previous: Dictionary = _fog.call("get_debug_snapshot")
	_fog.call("_physics_process", delta)
	_fog.call("_process", delta)
	var current: Dictionary = _fog.call("get_debug_snapshot")
	if int(current.profile_updates) > int(previous.profile_updates):
		_profile_costs.append(float(current.last_update_ms))


func _sample(point: Vector3) -> float:
	return float(_fog.call("sample_world_visibility", point))


func _samples(fog: Node3D = null) -> PackedFloat32Array:
	if fog == null:
		fog = _fog
	var result := PackedFloat32Array()
	for point in _probes:
		result.append(float(fog.call("sample_world_visibility", point)))
	return result


func _max_difference(first: PackedFloat32Array, second: PackedFloat32Array) -> float:
	var maximum := 0.0
	for index in range(first.size()):
		maximum = maxf(maximum, absf(first[index] - second[index]))
	return maximum


func _test_spatial_penumbra() -> void:
	_check(_sample(Vector3(5.0, 0.0, 0.0)) > 0.99, "floor in front of the cover remains clear")
	_check(_sample(Vector3(14.0, 0.0, 0.0)) < 0.01, "the centre of the cover shadow remains concealed")
	_check(_sample(Vector3(14.0, 0.0, 7.0)) > 0.99, "floor beside the cover remains clear")
	var previous := _sample(Vector3(14.0, 0.0, 1.0))
	var largest_step := 0.0
	var intermediate_samples := 0
	var reversals := 0
	for index in range(1, 41):
		var weight := _sample(Vector3(14.0, 0.0, 1.0 + float(index) * 0.15))
		largest_step = maxf(largest_step, absf(weight - previous))
		if weight > 0.05 and weight < 0.95:
			intermediate_samples += 1
		if weight < previous - 0.015:
			reversals += 1
		previous = weight
	_check(intermediate_samples >= 7, "a cover edge has a broad penumbra rather than a hard ray boundary")
	_check(largest_step < 0.16 and reversals == 0, "0.15-unit spatial probes cross the corner smoothly (max step %.4f)" % largest_step)


func _test_stationary_stability() -> void:
	var baseline := _samples()
	var maximum_drift := 0.0
	for _frame in range(36):
		_tick(FIXED_DELTA)
		maximum_drift = maxf(maximum_drift, _max_difference(baseline, _samples()))
	_check(maximum_drift < 0.002, "stationary cover and its penumbra do not shimmer across repeated refreshes (drift %.6f)" % maximum_drift)


func _test_world_anchored_history() -> void:
	var before := _samples()
	_observer.position.z = 2.0
	_fog.call("_physics_process", 0.1)
	_fog.call("_process", 0.0)
	var onset := _samples()
	_check(_max_difference(before, onset) < 0.002, "moving the observer preserves the previous shadow at fixed world points when a dissolve starts")
	_fog.call("_process", 0.09)
	var midpoint := _samples()
	_fog.call("_process", 0.2)
	var after := _samples()
	var envelope_violation := 0.0
	var broad_change := 0.0
	var intermediate_changes := 0
	for index in range(before.size()):
		var low := minf(before[index], after[index])
		var high := maxf(before[index], after[index])
		envelope_violation = maxf(envelope_violation, maxf(low - midpoint[index], midpoint[index] - high))
		broad_change = maxf(broad_change, absf(after[index] - before[index]))
		if absf(after[index] - before[index]) > 0.3 and midpoint[index] > low + 0.03 and midpoint[index] < high - 0.03:
			intermediate_changes += 1
	_check(broad_change > 0.65 and intermediate_changes >= 4, "the fixture actually changes substantial corner coverage and passes through intermediate opacity")
	_check(envelope_violation < 0.002, "the midpoint creates no swept wedge beyond either endpoint's fixed-world opacity (violation %.6f)" % envelope_violation)


func _test_corner_traverse() -> void:
	var previous := _samples()
	var maximum_frame_change := 0.0
	var minimum := 1.0
	var maximum := 0.0
	for frame_index in range(180):
		_observer.position.z = 2.0 * cos(float(frame_index + 1) * TAU / 180.0)
		_tick(FIXED_DELTA)
		var current := _samples()
		maximum_frame_change = maxf(maximum_frame_change, _max_difference(previous, current))
		for weight in current:
			minimum = minf(minimum, weight)
			maximum = maxf(maximum, weight)
		previous = current
	_check(maximum_frame_change < 0.15, "60 Hz movement around the corner bounds every fixed-world opacity step (max %.4f)" % maximum_frame_change)
	_check(minimum >= 0.0 and maximum <= 1.0, "moving cover remains a finite, bounded visibility field")


func _fresh_samples() -> PackedFloat32Array:
	var fresh := _create_fog()
	fresh.call("_physics_process", 1.0)
	fresh.call("_process", 0.0)
	var result := _samples(fresh)
	fresh.free()
	return result


func _test_history_resets() -> void:
	_observer.position = Vector3.ZERO
	_snap()
	var before_teleport := _samples()
	_observer.position = Vector3(0.0, 0.0, 9.0)
	_fog.call("_physics_process", 0.001)
	_fog.call("_process", 0.0)
	var teleported := _samples()
	_check(_max_difference(before_teleport, teleported) > 0.8, "teleport fixture reveals a region previously behind cover")
	_check(_max_difference(teleported, _fresh_samples()) < 0.002, "teleport immediately discards stale cover and matches a fresh profile")
	_observer.position = Vector3.ZERO
	_snap()
	_observer.position.z = 2.0
	_fog.call("_physics_process", 0.1)
	_fog.call("_process", 0.04)
	var during_transition := _samples()
	_observer.visibility_epoch += 1
	_fog.call("_physics_process", 0.001)
	_fog.call("_process", 0.0)
	var after_epoch := _samples()
	_check(_max_difference(during_transition, after_epoch) > 0.45, "epoch reset fixture contains an unfinished cover transition")
	_check(_max_difference(after_epoch, _fresh_samples()) < 0.002, "visibility epoch reset immediately removes previous-round opacity history")


func _test_zero_parameters() -> void:
	_fog.set("cover_transition_duration", 0.0)
	_observer.position = Vector3.ZERO
	_snap()
	_observer.position.z = 2.0
	_fog.call("_physics_process", 0.1)
	_fog.call("_process", 0.0)
	_check(_max_difference(_samples(), _fresh_samples()) < 0.002, "zero-duration transitions apply the new cover field without division or stale history")
	_observer.vision_radius = 0.0
	_fog.call("_physics_process", 0.001)
	_fog.call("_process", 0.0)
	var all_hidden := true
	for point in [Vector3.ZERO, _observer.position, Vector3(10.0, 0.0, 10.0)]:
		var weight := _sample(point)
		all_hidden = all_hidden and is_finite(weight) and is_zero_approx(weight)
	_check(all_hidden, "zero vision radius safely conceals the field including the observer origin")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)
		push_error("FAIL: " + label)


func _report() -> void:
	_profile_costs.sort()
	var total := 0.0
	for cost in _profile_costs:
		total += cost
	if not _profile_costs.is_empty():
		print("FOG PROFILE CPU: mean=%.3f ms p95=%.3f ms max=%.3f ms (%d updates; informational only)" % [total / float(_profile_costs.size()), _profile_costs[int(float(_profile_costs.size() - 1) * 0.95)], _profile_costs[-1], _profile_costs.size()])
	print("FOG ORGANIC: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
