class_name MekatanaAttack
extends RefCounted

## Shared melee timeline. The controller owns action priority and collision
## movement; this object owns accepted hits and the current combo only.
signal slash_started(step: int)
signal hit(target: Node3D, applied: float, multiplier: float)
signal finished

const DATA := preload("res://scripts/combat_data.gd")
var definition: Dictionary = DATA.WEAPON_DEFINITIONS["mekatana"].duplicate(true)
var phase := ""
var step := 0
var direction := Vector3.FORWARD
var next_step := 0
var combo_remaining := 0.0
var damage_enabled := true
var target_mask := 2 | 4
var _actor: Node3D
var _source_id := ""
var _move_callback: Callable
var _elapsed := 0.0
var _damage_scale := 1.0
var _tempo_scale := 1.0
var _serial := 0
var _history: Dictionary = {}
var _swing_hits: Dictionary = {}
var _targets: Dictionary = {}
var _previous_positions: Dictionary = {}
var _registry_clock := 0.0


func configure(actor: Node3D, source_id: String, move_callback: Callable = Callable()) -> void:
	_actor = actor
	_source_id = source_id
	_move_callback = move_callback
	cancel()
	_refresh_targets()
	_cache_positions()


func start(aim: Vector3, damage_scale: float = 1.0, tempo_scale: float = 1.0) -> bool:
	if is_busy() or not is_instance_valid(_actor) or not _actor.is_inside_tree():
		return false
	step = next_step if combo_remaining > 0.0 else 0
	if step == 0:
		_history.clear()
	# Admission freezes the rank and history even if the old window would expire
	# during this preparation. A new window starts when this slash resolves.
	combo_remaining = 0.0
	aim.y = 0.0
	if not aim.is_finite() or aim.length_squared() < 0.001:
		aim = -_actor.global_basis.z
		aim.y = 0.0
	direction = aim.normalized() if aim.is_finite() and aim.length_squared() > 0.001 else Vector3.FORWARD
	_damage_scale = maxf(0.0, damage_scale)
	_tempo_scale = maxf(0.1, tempo_scale)
	_elapsed = 0.0
	phase = "preparation"
	_serial += 1
	_swing_hits.clear()
	_refresh_targets()
	_cache_positions()
	return true


func update(delta: float) -> void:
	if not is_instance_valid(_actor) or not _actor.is_inside_tree():
		cancel()
		return
	var frame_delta := maxf(0.0, delta)
	_registry_clock -= frame_delta
	if _registry_clock <= 0.0:
		_refresh_targets()
		_registry_clock = 0.25
	var remaining := frame_delta
	var consumed := 0.0
	while remaining > 0.000001:
		if phase == "":
			_tick_window(remaining)
			break
		var duration := _duration(phase)
		var portion := minf(remaining, maxf(0.0, duration - _elapsed))
		if phase == "preparation" and portion > 0.0:
			var motion := direction * float(definition.dash_distance[step]) * portion / duration
			if _move_callback.is_valid():
				_move_callback.call(motion)
			elif _actor is CharacterBody3D:
				(_actor as CharacterBody3D).move_and_collide(motion)
		if phase == "active" and damage_enabled:
			_sweep(consumed / maxf(frame_delta, 0.000001), (consumed + portion) / maxf(frame_delta, 0.000001))
			if phase == "":
				break # A damage callback may interrupt or kill the attacker.
		if phase == "recovery":
			_tick_window(portion)
		_elapsed += portion
		consumed += portion
		remaining -= portion
		if _elapsed + 0.000001 < duration:
			break
		_elapsed = 0.0
		if phase == "preparation":
			phase = "active"
			slash_started.emit(step)
		elif phase == "active":
			phase = "recovery"
			if step < 2:
				next_step = step + 1
				combo_remaining = float(definition.combo_window)
			else:
				next_step = 0
				combo_remaining = 0.0
				_history.clear()
		else:
			phase = ""
			finished.emit()
	_cache_positions()


func cancel() -> void:
	_serial += 1
	phase = ""
	step = 0
	next_step = 0
	combo_remaining = 0.0
	_elapsed = 0.0
	_history.clear()
	_swing_hits.clear()


func is_busy() -> bool:
	return phase != ""


func is_direction_locked() -> bool:
	return phase in ["preparation", "active"]


func progress() -> float:
	return clampf(_elapsed / _duration(phase), 0.0, 1.0) if is_busy() else 0.0


func presentation_snapshot() -> Dictionary:
	return {"phase": phase, "step": step, "next_step": next_step,
		"combo_remaining": combo_remaining, "elapsed": _elapsed,
		"direction": direction, "tempo": _tempo_scale}


func restore_presentation(value: Dictionary) -> void:
	# Only a non-damaging replica may restore timing. Accepted hit history remains
	# exclusively on the host and is never supplied by the remote player.
	if damage_enabled:
		return
	var received_phase := str(value.get("phase", ""))
	phase = received_phase if received_phase in ["preparation", "active", "recovery"] else ""
	step = clampi(int(value.get("step", 0)), 0, 2)
	next_step = clampi(int(value.get("next_step", 0)), 0, 2)
	combo_remaining = clampf(float(value.get("combo_remaining", 0.0)), 0.0, float(definition.combo_window))
	_tempo_scale = clampf(float(value.get("tempo", 1.0)), 0.1, 10.0)
	_elapsed = clampf(float(value.get("elapsed", 0.0)), 0.0, _duration(phase)) if is_busy() else 0.0
	var facing: Vector3 = value.get("direction", direction)
	facing.y = 0.0
	if facing.is_finite() and facing.length_squared() > 0.001:
		direction = facing.normalized()


func _duration(value: String) -> float:
	return maxf(0.001, float(definition.get(value, [0.01, 0.01, 0.01])[step]) / _tempo_scale)


func _tick_window(delta: float) -> void:
	if combo_remaining <= 0.0:
		return
	combo_remaining = maxf(0.0, combo_remaining - delta)
	if combo_remaining <= 0.000001:
		combo_remaining = 0.0
		next_step = 0
		_history.clear()


func _refresh_targets() -> void:
	if not is_instance_valid(_actor) or not _actor.is_inside_tree():
		return
	var scene := _actor.get_tree().current_scene
	if scene == null:
		scene = _actor.get_tree().root
	_collect_targets(scene)
	for id in _targets.keys():
		if not is_instance_valid(_targets[id].get_ref()):
			_targets.erase(id)
			_previous_positions.erase(id)
			_history.erase(id)


func _collect_targets(node: Node) -> void:
	if node != _actor and node is Node3D and node.has_method("take_damage"):
		_targets[node.get_instance_id()] = weakref(node)
		return # Child hurtboxes share their actor's history and one swing hit.
	for child in node.get_children():
		_collect_targets(child)


func _cache_positions() -> void:
	for id in _targets:
		var target = _targets[id].get_ref()
		if is_instance_valid(target) and target.is_inside_tree():
			_previous_positions[id] = target.global_position


func _sweep(from_fraction: float, to_fraction: float) -> void:
	var serial := _serial
	# Sweep each target's relative segment through the complete short cleave.
	# This catches a fast target crossing between physics frames, including a
	# frame which consumes preparation, active and recovery in one update.
	var origin := _actor.global_position
	var right := direction.cross(Vector3.UP).normalized()
	var half_width := float(definition.cleave_width[step]) * 0.5
	var reach := float(definition.melee_range)
	for id in _targets:
		if _swing_hits.has(id):
			continue
		var target = _targets[id].get_ref()
		if not is_instance_valid(target) or not target.is_inside_tree() or not _has_target_collision(target):
			continue
		var current: Vector3 = target.global_position
		var previous: Vector3 = _previous_positions.get(id, current)
		var start_point := previous.lerp(current, from_fraction)
		var end_point := previous.lerp(current, to_fraction)
		var radius := _target_radius(target)
		var a := start_point - origin
		var b := end_point - origin
		var local_a := Vector3(a.dot(right), a.y, a.dot(direction))
		var local_b := Vector3(b.dot(right), b.y, b.dot(direction))
		var lower := Vector3(-half_width - radius, -float(definition.cleave_height) * 0.5, -radius)
		var upper := Vector3(half_width + radius, float(definition.cleave_height) * 0.5, reach + radius)
		var fraction := _segment_box_entry(local_a, local_b, lower, upper)
		if fraction < 0.0:
			continue
		var contact := start_point.lerp(end_point, fraction)
		if not _has_clear_path(target, origin, contact):
			continue
		var mask := int(_history.get(id, 0))
		var multiplier := 1.0
		if step == 1 and mask & 1:
			multiplier = float(definition.second_bonus)
		elif step == 2 and mask & 2:
			multiplier = float(definition.third_full_bonus if mask & 1 else definition.third_bonus)
		var attack_id := "%s:mekatana:%d:%d" % [_source_id, _actor.get_instance_id(), _serial]
		var result = target.call("take_damage", float(definition.base_damage[step]) * multiplier * _damage_scale, _source_id, attack_id)
		if serial != _serial or phase != "active":
			return
		var applied := float(result) if result is float or result is int else 0.0
		if applied > 0.0:
			_swing_hits[id] = true
			_history[id] = mask | (1 << step)
			hit.emit(target, applied, multiplier)


func _target_radius(target: Node3D) -> float:
	if target.has_method("get_fulguro_hit_radius"):
		return clampf(float(target.call("get_fulguro_hit_radius")), 0.0, 0.8)
	return 0.45


func _has_target_collision(node: Node) -> bool:
	if node is CollisionObject3D and (node as CollisionObject3D).collision_layer & target_mask:
		return true
	for child in node.get_children():
		if _has_target_collision(child):
			return true
	return false


func _has_clear_path(target: Node3D, origin: Vector3, contact: Vector3) -> bool:
	var excluded: Array[RID] = []
	_collect_rids(_actor, excluded)
	_collect_rids(target, excluded)
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.85, contact + Vector3.UP * 0.85, 1 | 8, excluded)
	query.collide_with_areas = true
	return _actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _collect_rids(node: Node, output: Array[RID]) -> void:
	if node is CollisionObject3D:
		output.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_rids(child, output)


static func _segment_box_entry(a: Vector3, b: Vector3, lower: Vector3, upper: Vector3) -> float:
	var entry := 0.0
	var exit_fraction := 1.0
	var motion := b - a
	for axis in range(3):
		if absf(motion[axis]) < 0.000001:
			if a[axis] < lower[axis] or a[axis] > upper[axis]:
				return -1.0
		else:
			var first := (lower[axis] - a[axis]) / motion[axis]
			var last := (upper[axis] - a[axis]) / motion[axis]
			entry = maxf(entry, minf(first, last))
			exit_fraction = minf(exit_fraction, maxf(first, last))
			if entry > exit_fraction:
				return -1.0
	return entry
