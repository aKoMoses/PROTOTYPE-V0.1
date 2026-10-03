extends "res://scripts/compact_arena_mechanisms.gd"

## One CPU-owned footprint supplies both the floor mesh and exposure queries.
## Sampling clips narrow parallel strips against the authored OBBs. Renderer
## shadow maps and real-world clocks never decide combat outcomes.
const MIRROR := preload("res://scripts/solar_mirror.gd")
const SOLAR_GRACE := 4.0
const SOLAR_WARNING := 1.5
const SWEEP_SECONDS := 12.0
const BEAM_WIDTH := 3.2
const STRIPS := 48
const HEAT_RATE := 0.5
const COOL_RATE := 0.32
const BURN_INTERVAL := 0.25
const BURN_HP_FRACTION := 0.045
const FOOT_RADIUS := 0.32

var phase := "grace"
var mirrors: Array[StaticBody3D] = []
var light_polygons: Array[PackedVector2Array] = []
var shadow_polygons: Array[PackedVector2Array] = []
var preview_polygons: Array[PackedVector2Array] = []
var core_polygons: Array[PackedVector2Array] = []
var _pending_footprints: Dictionary = {}
var heat: Dictionary = {}
var _burn_clock: Dictionary = {}
var _readouts: Dictionary = {}
var _thermal_warned: Dictionary = {}
var _burn_serial := 0
var _threat_serial := 1
var _active_mirror := -1
var _stage: Node3D
var _sun: Node3D
var _feed: MeshInstance3D
var _light_mesh: MeshInstance3D
var _shadow_mesh: MeshInstance3D
var _preview_mesh: MeshInstance3D
var _core_mesh: MeshInstance3D
var _light_material: StandardMaterial3D
var _half := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 30
	add_to_group("arena_hazards")
	_definition = CATALOG.definition("heliostat")
	_half = _definition.half_size
	_light_material = _solar_material(Color(1.0, 0.69, 0.12, 0.56), 1.1)
	_light_mesh = _surface("SolarExposure", _light_material)
	_shadow_mesh = _surface("SolarRefuges", _solar_material(Color(0.055, 0.24, 0.55, 0.58), 0.0))
	_preview_mesh = _surface("MirrorTrajectoryPreview", _solar_material(Color(1.0, 0.76, 0.27, 0.22), 0.6))
	_core_mesh = _surface("SolarWhiteCore", _solar_material(Color(1.0, 0.94, 0.65, 0.88), 1.6))
	for index in range(_definition.mirrors.size()):
		var mirror := MIRROR.new()
		mirror.controller = self
		mirror.mirror_index = index
		mirror.position = _definition.mirrors[index]
		add_child(mirror)
		mirrors.append(mirror)
	_feed = _cylinder(self, Vector3.ZERO, 0.085, 1.0, _solar_material(Color(1.0, 0.82, 0.3, 0.72), 1.0))
	_feed.name = "ReactorSolarProjection"
	_feed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reset_round()
	visible = enabled

func set_stage(stage: Node3D) -> void:
	_stage = stage
	_sun = stage.get_node_or_null("ExpandedArchitecture/SolarArmillary")
	# Pedestals are true navigation obstacles, command receivers are not covers.
	var scene := get_parent()
	if scene != null and scene.get("_arena_blockers") != null:
		for mirror in mirrors:
			(scene.get("_arena_blockers") as Array).append(mirror.get_node("MirrorPedestal"))

func configure(player: Node3D, bot: Node3D) -> void:
	super.configure(player, bot)
	for actor in _actors:
		if not is_instance_valid(actor):
			continue
		var readout := Label3D.new()
		readout.name = "SolarHeatReadout"
		readout.font_size = 24
		readout.pixel_size = 0.008
		readout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		readout.no_depth_test = true
		readout.outline_size = 5
		readout.modulate = Color("#ffba54")
		readout.visible = false
		add_child(readout)
		_readouts[actor.get_instance_id()] = readout

func reset_round() -> void:
	running = false
	elapsed = 0.0
	phase = "grace"
	_round_serial += 1
	_burn_serial = 0
	_threat_serial = 1
	_active_mirror = -1
	heat.clear()
	_burn_clock.clear()
	_thermal_warned.clear()
	for mirror in mirrors:
		mirror.call("reset_round")
	_clear_radiation()
	for readout in _readouts.values():
		if is_instance_valid(readout):
			readout.visible = false
	if is_instance_valid(_sun):
		_sun.rotation.z = 0.0

func start_round() -> void:
	running = enabled

func set_enabled(value: bool) -> void:
	reset_round()
	enabled = value
	visible = value
	for mirror in mirrors:
		mirror.collision_layer = 8 if value else 0
		(mirror.get_node("MirrorPedestal") as StaticBody3D).collision_layer = 1 if value else 0

func stop_round() -> void:
	running = false
	_clear_radiation()
	for readout in _readouts.values():
		if is_instance_valid(readout):
			readout.visible = false

func solar_controls_live() -> bool:
	return enabled and running and phase != "grace" and is_inside_tree() and not get_tree().paused

func advance(delta: float) -> void:
	if not enabled or not running or not is_inside_tree() or get_tree().paused or delta <= 0.0:
		return
	# Bounded steps preserve heating/burning and telegraph transitions under lag.
	var remaining := delta
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 30.0)
		remaining -= step
		elapsed += step
		var previous := phase
		phase = "grace" if elapsed < SOLAR_GRACE else ("warning" if elapsed < SOLAR_GRACE + SOLAR_WARNING else "active")
		if previous != phase:
			_threat_serial += 1
			_request_sound("trap_tile_warning" if phase == "warning" else "trap_tile_discharge", Vector3.ZERO)
		for mirror in mirrors:
			mirror.call("advance", step)
		_update_radiation()
		_update_heat(step)

func mirror_turn_announced(mirror: Node3D) -> void:
	_request_sound("trap_tile_warning", mirror.global_position)

func mirror_turn_completed(mirror: Node3D) -> void:
	_threat_serial += 1
	_request_sound("trap_tile_discharge", mirror.global_position)

func beam_direction(at_time: float = -1.0) -> Vector2:
	var time := elapsed if at_time < 0.0 else at_time
	var progress := maxf(0.0, time - SOLAR_GRACE - SOLAR_WARNING) / SWEEP_SECONDS
	# Smooth ping-pong: the solar head visibly turns, changing each cover shadow.
	var angle := -0.98 * cos(progress * PI)
	return Vector2(sin(angle), cos(angle))

func beam_origin() -> Vector2:
	return Vector2(0, -_half.y - 2.3)

func _update_radiation() -> void:
	light_polygons.clear()
	shadow_polygons.clear()
	preview_polygons.clear()
	core_polygons.clear()
	_pending_footprints.clear()
	_active_mirror = -1
	for mirror in mirrors:
		mirror.set("illuminated", false)
	if phase == "grace":
		_clear_radiation()
		return
	var origin := beam_origin()
	var dir := beam_direction()
	var next_capture := -1
	var best_capture := INF
	# Only a directly lit mirror may capture the primary beam. The reflected
	# strip stops on covers/bounds; it can never bounce through another mirror.
	for index in range(mirrors.size()):
		var point := Vector2(mirrors[index].position.x, mirrors[index].position.z)
		var offset := point - origin
		var distance := offset.dot(dir)
		var side := absf(offset.cross(dir))
		if distance <= 0 or side > BEAM_WIDTH * 0.5 + 0.70:
			continue
		if not _cover_between(origin, point) and distance < best_capture:
			best_capture = distance
			next_capture = index
	_active_mirror = next_capture
	if next_capture >= 0:
		var mirror := mirrors[next_capture]
		var point := Vector2(mirror.position.x, mirror.position.z)
		_trace_strip(origin, dir, BEAM_WIDTH, best_capture, light_polygons, shadow_polygons)
		var unused: Array[PackedVector2Array] = []
		_trace_strip(origin, dir, 0.16, best_capture, core_polygons, unused)
		mirror.set("illuminated", true)
		_trace_strip(point, mirror.call("get_direction"), BEAM_WIDTH, INF, light_polygons, shadow_polygons)
		_trace_strip(point, mirror.call("get_direction"), 0.16, INF, core_polygons, unused)
	else:
		_trace_strip(origin, dir, BEAM_WIDTH, INF, light_polygons, shadow_polygons)
		var unused: Array[PackedVector2Array] = []
		_trace_strip(origin, dir, 0.16, INF, core_polygons, unused)
	for mirror in mirrors:
		var point := Vector2(mirror.position.x, mirror.position.z)
		# Narrow outlines announce every eligible command's NEXT direction. A
		# pending turn displays its destination for the entire 0.8 s transition.
		if mirror.get("pending") >= 0 or bool(mirror.call("can_turn")):
			var preview_dir: Vector2 = mirror.call("direction_for", mirror.get("pending")) if mirror.get("pending") >= 0 else mirror.call("next_direction")
			var unused_shadows: Array[PackedVector2Array] = []
			var announced: Array[PackedVector2Array] = []
			_trace_strip(point, preview_dir, BEAM_WIDTH if mirror.get("pending") >= 0 else 0.10, INF, announced, unused_shadows)
			preview_polygons.append_array(announced)
			if mirror.get("pending") >= 0 and mirror.get("illuminated"):
				_pending_footprints[mirror.get("mirror_index")] = announced
	_light_material.albedo_color.a = 0.25 if phase == "warning" else 0.58
	_light_mesh.mesh = _polygon_mesh(light_polygons, 0.035)
	_shadow_mesh.mesh = _polygon_mesh(shadow_polygons, 0.026)
	_preview_mesh.mesh = _polygon_mesh(preview_polygons, 0.055)
	_core_mesh.mesh = _polygon_mesh(core_polygons, 0.065)
	_light_mesh.visible = true
	_shadow_mesh.visible = true
	_preview_mesh.visible = true
	_core_mesh.visible = true
	var reactor := _sun.global_position if is_instance_valid(_sun) else Vector3(0, 4.1, -16.5)
	var tip := Vector3(origin.x, 0.45, origin.y)
	var feed_direction := tip - reactor
	_feed.visible = true
	_feed.position = (reactor + tip) * 0.5
	_feed.scale.y = feed_direction.length()
	_feed.quaternion = Quaternion(Vector3.UP, feed_direction.normalized())
	if is_instance_valid(_sun):
		_sun.rotation.z = atan2(dir.x, dir.y) * -0.23

func _trace_strip(origin: Vector2, dir: Vector2, width: float, maximum: float, lit: Array[PackedVector2Array], shadows: Array[PackedVector2Array]) -> void:
	var normal := Vector2(-dir.y, dir.x)
	var strip_width := width / STRIPS
	for index in range(STRIPS):
		var offset := -width * 0.5 + (index + 0.5) * strip_width
		var ray_start := origin + normal * offset
		var arena := _box_interval(ray_start, dir, Vector2.ZERO, _half, 0.0)
		if arena.x > arena.y or arena.y <= 0.0:
			continue
		var begin := maxf(0, arena.x)
		var finish := minf(arena.y, maximum)
		var blocked := false
		for cover in _definition.covers:
			var point: Vector3 = cover.position
			var size: Vector3 = cover.size
			var interval := _box_interval(ray_start, dir, Vector2(point.x, point.z), Vector2(size.x, size.z) * 0.5, deg_to_rad(float(cover.yaw)))
			if interval.x <= interval.y and interval.y > begin and interval.x < finish:
				finish = maxf(begin, interval.x)
				blocked = true
		if finish > begin + 0.001:
			lit.append(_quad(ray_start + dir * begin, ray_start + dir * finish, normal * strip_width * 0.5))
		if blocked and arena.y > finish:
			# Extrude beyond the far face, not over the physical cover itself.
			var shadow_start := finish
			for cover in _definition.covers:
				var point: Vector3 = cover.position
				var size: Vector3 = cover.size
				var interval := _box_interval(ray_start, dir, Vector2(point.x, point.z), Vector2(size.x, size.z) * 0.5, deg_to_rad(float(cover.yaw)))
				if interval.x <= interval.y and absf(interval.x - finish) < 0.02:
					shadow_start = interval.y
			if arena.y > shadow_start:
				shadows.append(_quad(ray_start + dir * shadow_start, ray_start + dir * arena.y, normal * strip_width * 0.5))

func _box_interval(origin: Vector2, dir: Vector2, center: Vector2, half: Vector2, yaw: float) -> Vector2:
	# Godot's Y rotation becomes a negative rotation in the X/Z plane.
	var p := (origin - center).rotated(yaw)
	var d := dir.rotated(yaw)
	var near := -INF
	var far := INF
	for axis in range(2):
		if absf(d[axis]) < 0.000001:
			if absf(p[axis]) > half[axis]:
				return Vector2(INF, -INF)
		else:
			var first := (-half[axis] - p[axis]) / d[axis]
			var second := (half[axis] - p[axis]) / d[axis]
			near = maxf(near, minf(first, second))
			far = minf(far, maxf(first, second))
	return Vector2(near, far)

func _cover_between(a: Vector2, b: Vector2) -> bool:
	var distance := a.distance_to(b)
	var dir := (b - a).normalized()
	for cover in _definition.covers:
		var point: Vector3 = cover.position
		var size: Vector3 = cover.size
		var interval := _box_interval(a, dir, Vector2(point.x, point.z), Vector2(size.x, size.z) * 0.5, deg_to_rad(float(cover.yaw)))
		if interval.x <= interval.y and interval.y > 0 and interval.x < distance:
			return true
	return false

func exposure_at(point: Vector3, margin: float = 0.0) -> bool:
	if phase == "grace" or point.y > 2.4:
		return false
	return _in_polygons(Vector2(point.x, point.z), margin, light_polygons)

func _in_polygons(point: Vector2, margin: float, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
		if margin > 0:
			for index in range(polygon.size()):
				var closest := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
				if closest.distance_squared_to(point) < margin * margin:
					return true
	return false

func _update_heat(delta: float) -> void:
	for actor in _actors:
		if not is_instance_valid(actor):
			continue
		var id := actor.get_instance_id()
		var readout: Label3D = _readouts.get(id)
		if not _live_actor(actor):
			heat.erase(id)
			_burn_clock.erase(id)
			if is_instance_valid(readout):
				readout.visible = false
			continue
		var exposed := phase == "active" and exposure_at(actor.global_position, FOOT_RADIUS)
		var previous_heat := float(heat.get(id, 0.0))
		var value := clampf(previous_heat + (HEAT_RATE if exposed else -COOL_RATE) * delta, 0.0, 1.0)
		heat[id] = value
		if value >= 0.7 and not _thermal_warned.get(id, false):
			_thermal_warned[id] = true
			_request_sound("trap_tile_warning", actor.global_position)
		elif value < 0.4:
			_thermal_warned[id] = false
		# No damage during wind-up or after reaching shelter, even if still hot.
		if exposed and value >= 1.0 and actor.has_method("take_damage"):
			var clock := float(_burn_clock.get(id, 0.0)) + delta
			if clock >= BURN_INTERVAL:
				clock -= BURN_INTERVAL
				_burn_serial += 1
				var max_hp := float(actor.call("get_max_health")) if actor.has_method("get_max_health") else 1000.0
				actor.call("take_damage", max_hp * BURN_HP_FRACTION * BURN_INTERVAL, "arena_hazard", "solar:%d:%d:%d" % [_round_serial, id, _burn_serial])
			_burn_clock[id] = clock
		else:
			_burn_clock[id] = 0.0
		if is_instance_valid(readout):
			readout.global_position = actor.global_position + Vector3(2.1, 3.65, 0)
			var known := actor == _actors[0] or not actor.has_method("is_visible_to") or bool(actor.call("is_visible_to", _actors[0]))
			readout.visible = value > 0.04 and known
			readout.text = "♨ %d%%" % roundi(value * 100)
			readout.modulate = Color("#ff6438") if value >= 0.95 else Color("#ffca64")

func get_heat(actor: Node3D) -> float:
	return float(heat.get(actor.get_instance_id(), 0.0)) if is_instance_valid(actor) else 0.0

func get_threats() -> Array[Dictionary]:
	if not enabled or not running or phase == "grace":
		return []
	var threats: Array[Dictionary] = [{"id": 100 + _threat_serial, "kind": "solar", "phase": phase, "position": Vector3.ZERO, "remaining": maxf(0.0, SOLAR_GRACE + SOLAR_WARNING - elapsed), "size": _half * 2, "half_width": BEAM_WIDTH * 0.5, "direction": Vector3.ZERO, "length": 0.0}]
	for index in _pending_footprints:
		threats.append({"id": 1000 + _threat_serial * 10 + int(index), "kind": "solar", "phase": "warning", "mirror_index": index, "remaining": mirrors[index].get("turn_remaining"), "position": mirrors[index].position, "size": Vector2(BEAM_WIDTH, BEAM_WIDTH), "half_width": BEAM_WIDTH * 0.5, "direction": Vector3.ZERO, "length": 0.0})
	return threats

func threat_at(point: Vector3, margin: float = 0.0, known_threats: Array[Dictionary] = []) -> Dictionary:
	var threats := known_threats if not known_threats.is_empty() else get_threats()
	if not enabled or not running or threats.is_empty():
		return {}
	if exposure_at(point, margin):
		return threats[0]
	for threat in threats:
		var index := int(threat.get("mirror_index", -1))
		if index >= 0 and _in_polygons(Vector2(point.x, point.z), margin, _pending_footprints.get(index, [])):
			return threat
	return {}

func get_bot_mirror_target(body: Node3D, observed_enemy: Vector3, difficulty: String) -> Node3D:
	if not solar_controls_live() or phase != "active" or get_heat(body) > 0.55 or not observed_enemy.is_finite():
		return null
	# Difficulty controls the cadence of opportunities, not hidden knowledge.
	var cadence := 12.0 if difficulty == "easy" else (6.0 if difficulty == "hard" else 9.0)
	if fmod(elapsed, cadence) > 2.5:
		return null
	for mirror in mirrors:
		if not mirror.call("can_turn") or not mirror.get("illuminated"):
			continue
		var distance := body.global_position.distance_to(mirror.global_position)
		if distance > 16.0 or distance < 1.8:
			continue
		var a := body.global_position + Vector3.UP * 0.9
		var b := mirror.global_position + Vector3.UP * 0.9
		var ray := PhysicsRayQueryParameters3D.create(a, b, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var point := Vector2(mirror.position.x, mirror.position.z)
		var dir: Vector2 = mirror.call("next_direction")
		var enemy_offset := Vector2(observed_enemy.x, observed_enemy.z) - point
		var self_offset := Vector2(body.global_position.x, body.global_position.z) - point
		if enemy_offset.dot(dir) > 0 and absf(enemy_offset.cross(dir)) < BEAM_WIDTH * 0.5 + 1.0 and not _cover_between(point, Vector2(observed_enemy.x, observed_enemy.z)):
			if self_offset.dot(dir) <= 0 or absf(self_offset.cross(dir)) > BEAM_WIDTH * 0.5 + 0.8:
				return mirror
	return null

func get_snapshot() -> Dictionary:
	var states: Array[Dictionary] = []
	for mirror in mirrors:
		states.append({"preset": mirror.get("preset"), "pending": mirror.get("pending"), "turn_remaining": mirror.get("turn_remaining"), "lock_remaining": mirror.get("locked_remaining"), "rotations": mirror.get("rotations"), "illuminated": mirror.get("illuminated")})
	return {"arena_id": "heliostat", "enabled": enabled, "running": running, "elapsed": elapsed, "phase": phase, "heat": heat.duplicate(), "mirrors": states, "active_mirror": _active_mirror, "lit_strips": light_polygons.size(), "shadow_strips": shadow_polygons.size(), "burns": _burn_serial, "tier": 1, "busy": 1 if phase != "grace" else 0, "bolts": 0, "portals": 0, "teleports": 0, "boosts": 0, "shutters": []}

func _clear_radiation() -> void:
	light_polygons.clear()
	shadow_polygons.clear()
	preview_polygons.clear()
	core_polygons.clear()
	_pending_footprints.clear()
	for surface in [_light_mesh, _shadow_mesh, _preview_mesh, _core_mesh, _feed]:
		if is_instance_valid(surface):
			surface.visible = false

func _solar_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.6, Color(color.r, color.g, color.b), energy)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material

func _surface(label: String, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	return mesh

func _quad(a: Vector2, b: Vector2, side: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a - side, a + side, b + side, b - side])

func _polygon_mesh(polygons: Array[PackedVector2Array], y: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if polygons.is_empty():
		return mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for polygon in polygons:
		var base := vertices.size()
		for point in polygon:
			vertices.append(Vector3(point.x, y, point.y))
			normals.append(Vector3.UP)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
