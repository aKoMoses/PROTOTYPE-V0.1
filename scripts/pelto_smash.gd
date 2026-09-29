class_name PeltoSmashWave
extends Node3D

## Shared PELTO SMASH wave used by players and bots. The wave owns its locked
## origin/direction, performs swept hit tests, and never follows its caster.

signal finished

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const SCRAPE_SOUND: AudioStream = preload("res://art/audio/shotgun-cycle-a.wav")
const OBSTACLE_MASK := 1
const TARGET_MASK := 2 | 4
const SAMPLE_HEIGHT := 0.72
const HITBOX_HEIGHT := 1.45
const WALL_MARGIN := 0.045
const DUST_STEP := 0.55

var caster: Node3D
var source_id := ""
var attack_id := ""
var damage_multiplier := 1.0
var start_position := Vector3.ZERO
var direction := Vector3.FORWARD
var travel_distance := 0.0
var phase := "outbound"

var _definition: Dictionary
var _max_distance := 0.0
var _pause_remaining := 0.0
var _outbound_hits: Dictionary = {}
var _return_hits: Dictionary = {}
var _front_root: Node3D
var _plates: Array[MeshInstance3D] = []
var _fragments: Array[MeshInstance3D] = []
var _trace: MeshInstance3D
var _trace_mesh: BoxMesh
var _endpoint_ring: MeshInstance3D
var _scrape_audio: AudioStreamPlayer3D
var _visual_clock := 0.0
var _dust_accumulator := 0.0
var _finishing := false


static func definition() -> Dictionary:
	return COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"]


static func flat_direction(value: Vector3) -> Vector3:
	var flat := value
	flat.y = 0.0
	return flat.normalized() if flat.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)


func configure(p_caster: Node3D, origin: Vector3, locked_direction: Vector3, p_source_id: String, p_attack_id: String, p_damage_multiplier: float = 1.0) -> void:
	caster = p_caster
	start_position = origin
	start_position.y = 0.0
	direction = flat_direction(locked_direction)
	source_id = p_source_id
	attack_id = p_attack_id
	damage_multiplier = maxf(0.0, p_damage_multiplier)
	_definition = definition()
	_max_distance = _compute_allowed_distance(float(_definition.max_range))
	_pause_remaining = float(_definition.return_pause)
	_build_visuals()
	_update_visuals()


func _ready() -> void:
	process_physics_priority = 5


func _physics_process(delta: float) -> void:
	if _finishing or delta <= 0.0:
		return
	_visual_clock += delta
	var remaining := minf(delta, 1.0)
	var transitions := 0
	while remaining > 0.000001 and transitions < 6 and not _finishing:
		transitions += 1
		match phase:
			"outbound":
				var speed := maxf(0.001, float(_definition.outbound_speed))
				var available_distance := maxf(0.0, _max_distance - travel_distance)
				var step_distance := minf(available_distance, speed * remaining)
				var consumed := step_distance / speed
				var previous := travel_distance
				travel_distance += step_distance
				_detect_hits(previous, travel_distance, false)
				_emit_moving_dust(step_distance, false)
				remaining -= consumed
				if travel_distance >= _max_distance - 0.0001:
					phase = "pause"
					_spawn_pause_cue()
			"pause":
				var consumed := minf(remaining, _pause_remaining)
				_pause_remaining -= consumed
				remaining -= consumed
				if _pause_remaining <= 0.0001:
					phase = "return"
					_begin_return()
			"return":
				var speed := maxf(0.001, float(_definition.return_speed))
				var step_distance := minf(travel_distance, speed * remaining)
				var consumed := step_distance / speed
				var previous := travel_distance
				travel_distance -= step_distance
				_detect_hits(previous, travel_distance, true)
				_emit_moving_dust(step_distance, true)
				remaining -= consumed
				if travel_distance <= 0.0001:
					_finish_wave()
			_:
				_finish_wave()
	_update_visuals()


func _compute_allowed_distance(requested_distance: float) -> float:
	if caster == null or caster.get_world_3d() == null or requested_distance <= 0.0:
		return maxf(0.0, requested_distance)
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(_definition.width), HITBOX_HEIGHT, float(_definition.front_thickness))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.looking_at(direction, Vector3.UP), start_position + Vector3.UP * SAMPLE_HEIGHT)
	query.motion = direction * requested_distance
	query.margin = 0.02
	query.collision_mask = OBSTACLE_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if caster is CollisionObject3D:
		query.exclude = [(caster as CollisionObject3D).get_rid()]
	var cast := caster.get_world_3d().direct_space_state.cast_motion(query)
	if cast.is_empty():
		return requested_distance
	var safe_fraction := clampf(float(cast[0]), 0.0, 1.0)
	return maxf(0.0, requested_distance * safe_fraction - WALL_MARGIN)


func _detect_hits(previous_distance: float, next_distance: float, returning: bool) -> void:
	if caster == null or caster.get_world_3d() == null:
		return
	var front_thickness := float(_definition.front_thickness)
	var swept_length := absf(next_distance - previous_distance) + front_thickness
	var center_distance := (previous_distance + next_distance) * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(_definition.width), HITBOX_HEIGHT, maxf(front_thickness, swept_length))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.looking_at(direction, Vector3.UP), start_position + direction * center_distance + Vector3.UP * SAMPLE_HEIGHT)
	query.margin = 0.025
	query.collision_mask = TARGET_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if caster is CollisionObject3D:
		query.exclude = [(caster as CollisionObject3D).get_rid()]
	for result in caster.get_world_3d().direct_space_state.intersect_shape(query, 64):
		var target := result.get("collider") as Node
		if not _is_valid_target(target) or not _path_clear(target):
			continue
		var instance_id := target.get_instance_id()
		var hit_set := _return_hits if returning else _outbound_hits
		if hit_set.has(instance_id):
			continue
		hit_set[instance_id] = true
		_apply_hit(target, returning)


func _is_valid_target(target: Node) -> bool:
	if target == null or target == caster or not is_instance_valid(target) or not target is Node3D:
		return false
	if not target.has_method("take_damage"):
		return false
	if target.has_method("is_real_dead") and bool(target.call("is_real_dead")):
		return false
	return not target.has_method("get_health") or float(target.call("get_health")) > 0.0


func _path_clear(target: Node) -> bool:
	if caster == null or caster.get_world_3d() == null or not target is Node3D:
		return false
	var target_position := (target as Node3D).global_position
	var side := Vector3(-direction.z, 0.0, direction.x)
	var relative := target_position - start_position
	var lateral := clampf(side.dot(relative), -float(_definition.width) * 0.5, float(_definition.width) * 0.5)
	var ray_start := start_position + side * lateral + Vector3.UP * SAMPLE_HEIGHT
	var ray_end := target_position + Vector3.UP * SAMPLE_HEIGHT
	var ray := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	ray.collision_mask = OBSTACLE_MASK
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	var excluded: Array[RID] = []
	if caster is CollisionObject3D:
		excluded.append((caster as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		excluded.append((target as CollisionObject3D).get_rid())
	ray.exclude = excluded
	return caster.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _apply_hit(target: Node, returning: bool) -> void:
	var suffix := "return" if returning else "outbound"
	var damage := float(_definition.return_damage if returning else _definition.outbound_damage) * damage_multiplier
	var applied := float(target.call("take_damage", damage, source_id, "%s:%s" % [attack_id, suffix]))
	if applied <= 0.0:
		return
	if caster != null and is_instance_valid(caster) and caster.has_method("_on_damage_dealt"):
		caster.call("_on_damage_dealt", applied)
	if caster != null and is_instance_valid(caster) and caster.has_method("_on_pelto_hit"):
		caster.call("_on_pelto_hit", target, returning, applied)
	if returning:
		if target.has_method("start_pelto_pull"):
			target.call("start_pelto_pull", -direction, float(_definition.pull_distance), float(_definition.pull_duration), source_id, "%s:pull" % attack_id)
	else:
		if target.has_method("apply_slow"):
			target.call("apply_slow", float(_definition.outbound_slow_duration), float(_definition.outbound_slow_percent), "%s:pelto_smash" % source_id)
	_spawn_hit_fx(target as Node3D, returning)


func _build_visuals() -> void:
	_front_root = Node3D.new()
	_front_root.name = "EarthFront"
	add_child(_front_root)
	var plate_count := 6
	var segment_width := float(_definition.width) / float(plate_count)
	for index in range(plate_count):
		var plate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(maxf(0.12, segment_width - 0.045), 0.18, float(_definition.front_thickness) * 0.82)
		plate.mesh = mesh
		plate.position.x = -float(_definition.width) * 0.5 + segment_width * (float(index) + 0.5)
		plate.position.z = (0.08 if index % 2 == 0 else -0.08)
		plate.material_override = _earth_material(Color("#9b5835") if index % 2 == 0 else Color("#b66d3e"), 1.0)
		_front_root.add_child(plate)
		_plates.append(plate)
	for index in range(5):
		var fragment := MeshInstance3D.new()
		var fragment_mesh := BoxMesh.new()
		var scale_factor := 0.08 + float(index % 3) * 0.025
		fragment_mesh.size = Vector3(scale_factor, scale_factor * 0.75, scale_factor * 1.35)
		fragment.mesh = fragment_mesh
		fragment.position = Vector3(-float(_definition.width) * 0.38 + float(index) * float(_definition.width) * 0.19, 0.22, 0.0)
		fragment.set_meta("pelto_base", fragment.position)
		fragment.material_override = _earth_material(Color("#cf8750"), 1.0)
		_front_root.add_child(fragment)
		_fragments.append(fragment)
	_trace = MeshInstance3D.new()
	_trace.name = "TemporaryGroundTrace"
	_trace.top_level = true
	_trace_mesh = BoxMesh.new()
	_trace_mesh.size = Vector3(float(_definition.width) * 0.92, 0.025, 0.05)
	_trace.mesh = _trace_mesh
	_trace.material_override = _earth_material(Color("#70452f"), 0.38)
	add_child(_trace)
	_endpoint_ring = MeshInstance3D.new()
	_endpoint_ring.name = "ReturnCue"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = float(_definition.width) * 0.34
	ring_mesh.outer_radius = float(_definition.width) * 0.42
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 28
	_endpoint_ring.mesh = ring_mesh
	_endpoint_ring.material_override = _earth_material(Color("#f0b66a"), 0.82)
	_endpoint_ring.visible = false
	_endpoint_ring.top_level = true
	add_child(_endpoint_ring)
	_scrape_audio = AudioStreamPlayer3D.new()
	_scrape_audio.name = "PeltoReturnScrape"
	_scrape_audio.stream = SCRAPE_SOUND
	_scrape_audio.volume_db = -8.0
	_scrape_audio.pitch_scale = 0.52
	_scrape_audio.max_distance = 24.0
	_front_root.add_child(_scrape_audio)


func _update_visuals() -> void:
	if _front_root == null:
		return
	_front_root.global_position = start_position + direction * travel_distance + Vector3.UP * 0.07
	_front_root.global_basis = Basis.looking_at(direction, Vector3.UP)
	var motion_sign := -1.0 if phase == "return" else 1.0
	for index in range(_plates.size()):
		var plate := _plates[index]
		plate.position.y = 0.08 + sin(_visual_clock * 15.0 + float(index) * 0.9) * 0.045
		plate.rotation.x = motion_sign * (0.20 + float(index % 2) * 0.08)
		plate.rotation.z = sin(_visual_clock * 8.0 + float(index)) * 0.07
	for index in range(_fragments.size()):
		var fragment := _fragments[index]
		var base: Vector3 = fragment.get_meta("pelto_base", fragment.position)
		fragment.position = base + Vector3(0.0, absf(sin(_visual_clock * 12.0 + float(index))) * 0.18, motion_sign * -0.16)
		fragment.rotation = Vector3(_visual_clock * (2.0 + index * 0.12) * motion_sign, float(index), _visual_clock * 1.7)
	var trace_length := maxf(0.05, _max_distance if phase in ["pause", "return"] else travel_distance)
	_trace_mesh.size = Vector3(float(_definition.width) * 0.92, 0.025, trace_length)
	_trace.global_position = start_position + direction * (trace_length * 0.5) + Vector3.UP * 0.018
	_trace.global_basis = Basis.looking_at(direction, Vector3.UP)
	_endpoint_ring.global_position = start_position + direction * _max_distance + Vector3.UP * 0.055
	if phase == "pause":
		var pulse := 1.0 + sin(_visual_clock * 28.0) * 0.12
		_front_root.scale = Vector3.ONE * pulse
		_endpoint_ring.scale = Vector3.ONE * pulse
	else:
		_front_root.scale = Vector3.ONE


func _emit_moving_dust(step_distance: float, returning: bool) -> void:
	_dust_accumulator += step_distance
	if _dust_accumulator < DUST_STEP:
		return
	_dust_accumulator = fmod(_dust_accumulator, DUST_STEP)
	var side := Vector3(-direction.z, 0.0, direction.x)
	for side_sign in [-1.0, 1.0]:
		var puff := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.16
		mesh.height = 0.18
		mesh.radial_segments = 7
		mesh.rings = 4
		puff.mesh = mesh
		var material := _earth_material(Color("#b98a68"), 0.30)
		puff.material_override = material
		var scene := get_tree().current_scene if get_tree() != null else null
		if scene == null:
			puff.free()
			continue
		scene.add_child(puff)
		puff.global_position = start_position + direction * travel_distance + side * float(side_sign) * float(_definition.width) * 0.32 + Vector3.UP * 0.09
		var drift := (-direction if not returning else direction) * 0.28 + side * float(side_sign) * 0.10
		var tween := puff.create_tween()
		tween.set_parallel(true)
		tween.tween_property(puff, "global_position", puff.global_position + drift + Vector3.UP * 0.12, 0.24)
		tween.tween_property(puff, "scale", Vector3(2.2, 0.55, 2.2), 0.24)
		tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.30, 0.0, 0.24)
		tween.set_parallel(false)
		tween.tween_callback(puff.queue_free)


func _spawn_pause_cue() -> void:
	_endpoint_ring.visible = true
	for fragment in _fragments:
		fragment.position.y += 0.14


func _begin_return() -> void:
	_endpoint_ring.visible = false
	_dust_accumulator = DUST_STEP
	if _scrape_audio != null:
		_scrape_audio.play()


func _spawn_hit_fx(target: Node3D, returning: bool) -> void:
	if target == null:
		return
	var scene := get_tree().current_scene if get_tree() != null else null
	var vfx := scene.get_node_or_null("VFXManager") if scene != null else null
	if vfx != null:
		vfx.call("impact", target.global_position + Vector3.UP * 0.68, direction if returning else -direction, "robot", 0.72, Color("#d99355") if not returning else Color("#f0b66a"))


func _finish_wave() -> void:
	if _finishing:
		return
	_finishing = true
	phase = "finished"
	set_physics_process(false)
	if _scrape_audio != null:
		_scrape_audio.stop()
	finished.emit()
	var tween := create_tween()
	tween.set_parallel(true)
	# Keep the wave alive until the last detached dust tween has finished using
	# our shared material-alpha callback (dust lifetime is 0.24 seconds).
	tween.tween_property(_front_root, "scale", Vector3(0.85, 0.05, 0.85), 0.30)
	tween.tween_property(_trace, "scale", Vector3(1.0, 0.05, 1.0), 0.30)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func _earth_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.92
	if alpha < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color.darkened(0.45)
	material.emission_energy_multiplier = 0.20
	return material


func _set_material_alpha(alpha: float, material: StandardMaterial3D) -> void:
	if material != null:
		material.albedo_color.a = alpha
