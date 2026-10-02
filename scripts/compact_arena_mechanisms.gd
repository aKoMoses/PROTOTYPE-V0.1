extends Node3D

## Live mechanisms for the three pocket arenas. All timers, including shader
## animation, use round time so countdowns, pauses and result screens freeze them.
signal sound_requested(event_id: String, at: Vector3)

const CATALOG := preload("res://scripts/compact_arena_catalog.gd")
const MAGNETIC_WALL := preload("res://scripts/magnetic_wall.gd")
const GRACE_SECONDS := 4.0
const PORTAL_RADIUS := 0.88
const PORTAL_LOCK_SECONDS := 1.7
const PORTAL_EXIT_DISTANCE := 1.55
const BOOST_RADIUS := 0.82
const BOOST_LOCK_SECONDS := 2.2
const BOOST_DURATION := 0.32
const BOOST_SPEED := 18.0
const AMBER := Color("#ffbf54")

const PORTAL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float clock = 0.0;
uniform float live = 0.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float spiral = pow(0.5 + 0.5 * sin(angle * 5.0 - r * 16.0 + clock * 3.0), 5.0);
	float rim = exp(-pow((r - 0.85) * 12.0, 2.0));
	float center = exp(-r * 3.2);
	float edge = 1.0 - smoothstep(0.87, 1.0, r);
	ALBEDO = tint.rgb * (0.45 + spiral * 0.85 + rim * 1.2);
	ALPHA = edge * (0.10 + spiral * 0.32 + center * 0.12 + rim * 0.45) * mix(0.24, 1.0, live);
}
"""

const LANE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform vec2 extent = vec2(1.6, 13.0);
uniform float clock = 0.0;
uniform float phase = 0.0;
void fragment() {
	vec2 p = UV * extent;
	vec2 nearest_edge = min(p, extent - p);
	float edge = 1.0 - smoothstep(0.025, 0.085, min(nearest_edge.x, nearest_edge.y));
	float along = extent.x > extent.y ? p.x : p.y;
	float dash = step(0.35, fract(along * 1.55));
	float scan = pow(0.5 + 0.5 * sin(along * 5.5 - clock * 5.0), 10.0);
	float pulse = 0.55 + 0.45 * sin(clock * 10.0);
	vec3 warning = vec3(1.0, 0.57, 0.19);
	vec3 color = phase > 1.5 ? tint.rgb : warning;
	float live = step(0.5, phase);
	float active = step(1.5, phase);
	ALBEDO = color * mix(0.6, 1.25, active);
	ALPHA = live * (0.035 + pulse * 0.025 + edge * dash * (0.40 + pulse * 0.22)
		+ active * (0.12 + scan * 0.18));
}
"""

const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0, 0.32, 0.07, 1.0);
uniform float clock = 0.0;
void fragment() {
	float strand = pow(0.5 + 0.5 * sin(UV.x * 50.0 - UV.y * 13.0 + clock * 12.0), 7.0);
	float cap = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
	ALBEDO = tint.rgb * (0.75 + strand * 0.8);
	ALPHA = cap * (0.055 + strand * 0.21);
}
"""

const WAVE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform float clock = 0.0;
uniform float offset = 0.0;
void vertex() {
	float swell = sin(UV.x * 26.0 + clock * 6.5 + offset);
	VERTEX.y *= 0.83 + swell * 0.18;
	VERTEX.z += UV.y * sin(UV.x * 21.0 - clock * 5.0 + offset) * 0.18;
}
void fragment() {
	float foam = smoothstep(0.79, 0.96, UV.y);
	float ripple = pow(0.5 + 0.5 * sin(UV.y * 18.0 - UV.x * 15.0 + clock * 7.0), 8.0);
	ALBEDO = mix(vec3(0.02, 0.43, 0.59), vec3(0.73, 1.0, 0.98), foam);
	ALBEDO += ripple * vec3(0.02, 0.10, 0.13);
	ALPHA = 0.30 + foam * 0.46 + ripple * 0.10;
}
"""

var arena_id := "heliostat"
var enabled := false
var running := false
var elapsed := 0.0
var _definition: Dictionary = {}
var _actors: Array[Node3D] = []
var _fixtures: Array[Dictionary] = []
var _portals: Array[Dictionary] = []
var _boosts: Array[Dictionary] = []
var _shutters: Array[Dictionary] = []
var _portal_locks: Dictionary = {}
var _boost_locks: Dictionary = {}
var _boost_motion: Dictionary = {}
var _next_event_at := GRACE_SECONDS
var _event_index := 0
var _serial := 0
var _round_serial := 0
var _teleports := 0
var _boost_count := 0
var _shader: Shader


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Move mechanisms after both combatants' normal movement has been resolved.
	process_physics_priority = 20
	add_to_group("arena_hazards")
	_definition = CATALOG.definition(arena_id)
	if _definition.is_empty():
		arena_id = "heliostat"
		_definition = CATALOG.definition(arena_id)
	_build_fixtures()
	_build_portals()
	_build_boosts()
	if arena_id == "clockwork":
		_build_shutters()
	visible = enabled
	_reset_visuals()


func configure(player: Node3D, bot: Node3D) -> void:
	_actors.assign([player, bot])


func set_enabled(value: bool) -> void:
	reset_round()
	enabled = value
	visible = value


func reset_round() -> void:
	running = false
	elapsed = 0.0
	_next_event_at = GRACE_SECONDS
	_event_index = 0
	_round_serial += 1
	_teleports = 0
	_boost_count = 0
	_portal_locks.clear()
	_boost_locks.clear()
	_boost_motion.clear()
	for fixture in _fixtures:
		fixture.phase = "idle"
		fixture.remaining = 0.0
		fixture.hit.clear()
	_reset_visuals()


func start_round() -> void:
	running = enabled
	for portal in _portals:
		(portal.swirl as ShaderMaterial).set_shader_parameter("live", 1.0 if running else 0.0)


func stop_round() -> void:
	running = false
	_boost_motion.clear()
	for fixture in _fixtures:
		fixture.phase = "idle"
		fixture.remaining = 0.0
	_reset_visuals()


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not enabled or not running or not is_inside_tree() or get_tree().paused or delta <= 0.0:
		return
	elapsed += delta
	for fixture in _fixtures:
		if fixture.phase != "idle":
			fixture.remaining = maxf(0.0, float(fixture.remaining) - delta)
			if fixture.phase == "warning" and float(fixture.remaining) <= 0.0:
				fixture.phase = "active"
				fixture.remaining = float(_definition.active)
				_request_sound("trap_tile_discharge", fixture.position)
			elif fixture.phase == "active" and float(fixture.remaining) <= 0.0:
				fixture.phase = "idle"
		if fixture.phase == "active":
			_damage_fixture(fixture)
		_update_fixture_visual(fixture)
	if elapsed >= _next_event_at:
		_warn_fixture(_event_index % _fixtures.size())
		_event_index += 1
		_next_event_at = GRACE_SECONDS + float(_event_index) * float(_definition.period)
	_advance_portals()
	_advance_boosts(delta)
	_advance_shutters(delta)


func _warn_fixture(index: int) -> void:
	var fixture: Dictionary = _fixtures[index]
	_serial += 1
	fixture.serial = _serial
	fixture.phase = "warning"
	fixture.remaining = float(_definition.warning)
	fixture.hit.clear()
	_update_fixture_visual(fixture)
	_request_sound("trap_tile_warning", fixture.position)


func _live_actor(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return false
	if actor.has_method("is_real_dead") and bool(actor.call("is_real_dead")):
		return false
	if "_gameplay_enabled" in actor and not bool(actor.get("_gameplay_enabled")):
		return false
	if "_duel_paused" in actor and bool(actor.get("_duel_paused")):
		return false
	return true


func _damage_fixture(fixture: Dictionary) -> void:
	var half: Vector2 = fixture.size * 0.5
	for actor in _actors:
		if not _live_actor(actor) or not actor.has_method("take_damage"):
			continue
		var offset := actor.global_position - (fixture.position as Vector3)
		if absf(offset.x) > half.x + 0.35 or absf(offset.z) > half.y + 0.35:
			continue
		var key := actor.get_instance_id()
		if fixture.hit.has(key):
			continue
		fixture.hit[key] = true
		actor.call("take_damage", float(fixture.damage), "arena_hazard", "compact_arena:%s:%d:%d" % [arena_id, _round_serial, int(fixture.serial)])


func get_threats() -> Array[Dictionary]:
	var threats: Array[Dictionary] = []
	if not running or not enabled:
		return threats
	for fixture in _fixtures:
		if fixture.phase == "idle":
			continue
		threats.append({"id": int(fixture.serial), "kind": "tile", "position": fixture.position,
			"size": fixture.size, "direction": Vector3.ZERO, "length": 0.0,
			"half_width": float(fixture.size.x) * 0.5, "remaining": fixture.remaining, "phase": fixture.phase})
	for index in range(_shutters.size()):
		var shutter: Dictionary = _shutters[index]
		if shutter.phase in ["warning", "closed"]:
			threats.append({"id": 10000 + index + int(elapsed / 7.0) * 2, "kind": "tile", "position": shutter.position,
				"size": Vector2(3.4, 0.45), "direction": Vector3.ZERO, "length": 0.0,
				"half_width": 1.7, "remaining": 0.0, "phase": "warning" if shutter.phase == "warning" else "active"})
	return threats


func threat_at(point: Vector3, margin: float = 0.0, known_threats: Array[Dictionary] = []) -> Dictionary:
	var threats := known_threats if not known_threats.is_empty() else get_threats()
	for threat in threats:
		var offset := point - (threat.position as Vector3)
		var half: Vector2 = threat.size * 0.5
		if absf(offset.x) <= half.x + margin and absf(offset.z) <= half.y + margin:
			return threat
	return {}


func get_snapshot() -> Dictionary:
	var phases: Array[String] = []
	var shutters: Array[String] = []
	var busy := 0
	for fixture in _fixtures:
		phases.append(str(fixture.phase))
		if fixture.phase != "idle":
			busy += 1
	for shutter in _shutters:
		shutters.append(str(shutter.phase))
	return {"arena_id": arena_id, "enabled": enabled, "running": running, "elapsed": elapsed,
		"tier": 1, "busy": busy, "bolts": 0, "events": _event_index, "phases": phases,
		"portals": _portals.size(), "teleports": _teleports, "boosts": _boost_count, "shutters": shutters}


func _advance_portals() -> void:
	for portal in _portals:
		(portal.swirl as ShaderMaterial).set_shader_parameter("clock", elapsed)
		var ring: MeshInstance3D = portal.ring
		ring.rotation.z = elapsed * 0.24
		var strength := 0.48 + sin(elapsed * 2.4) * 0.10
		(portal.light as OmniLight3D).light_energy = strength
		var sparkles: Node3D = portal.sparkles
		sparkles.rotation.z = -elapsed * 0.75
	for actor in _actors:
		if not _live_actor(actor):
			continue
		var key := actor.get_instance_id()
		if elapsed < float(_portal_locks.get(key, -1.0)):
			continue
		for index in range(_portals.size()):
			var at: Vector3 = _portals[index].position
			if _flat_distance(actor.global_position, at) > PORTAL_RADIUS:
				continue
			var destination := _safe_portal_exit(actor, _portals[1 - index].position)
			if destination == Vector3.INF:
				# Retry while occupied; a failed portal does not spend its cooldown.
				continue
			actor.global_position = destination
			_clear_actor_velocity(actor)
			_boost_motion.erase(key)
			_portal_locks[key] = elapsed + PORTAL_LOCK_SECONDS
			_teleports += 1
			if actor.has_method("on_permutation_relocated"):
				actor.call("on_permutation_relocated")
			if actor.has_method("refresh_permutation_sweeps"):
				actor.call("refresh_permutation_sweeps")
			if actor == _actors[0]:
				var camera := get_parent().get_node_or_null("CameraRig")
				if camera != null and camera.has_method("set_target"):
					camera.call("set_target", actor)
			_request_sound("javelin_teleport", destination)
			break


func _safe_portal_exit(actor: Node3D, portal: Vector3) -> Vector3:
	var inward := Vector3(-portal.x, 0.0, -portal.z).normalized()
	var side := Vector3(-inward.z, 0.0, inward.x)
	for forward in [PORTAL_EXIT_DISTANCE, PORTAL_EXIT_DISTANCE + 0.7]:
		for lateral in [0.0, -0.9, 0.9]:
			var start := portal + side * float(lateral)
			var candidate := start + inward * float(forward)
			candidate.y = 0.0
			if not _position_is_clear(actor, start) or not _position_is_clear(actor, candidate):
				continue
			var swept := _safe_motion(actor, candidate - start, start)
			if swept.distance_to(candidate - start) <= 0.04:
				return candidate
	return Vector3.INF


func _advance_boosts(delta: float) -> void:
	for pad in _boosts:
		var arrows: Array = pad.arrows
		for index in range(arrows.size()):
			var arrow: Node3D = arrows[index]
			arrow.position.y = 0.10 + (0.5 + 0.5 * sin(elapsed * 7.0 - float(index) * 1.6)) * 0.055
			arrow.scale = Vector3.ONE * (0.91 + 0.09 * sin(elapsed * 7.0 - float(index) * 1.6))
	for actor in _actors:
		if not _live_actor(actor):
			if is_instance_valid(actor):
				_boost_motion.erase(actor.get_instance_id())
			continue
		var key := actor.get_instance_id()
		if not _boost_motion.has(key) and elapsed >= float(_boost_locks.get(key, -1.0)):
			for pad in _boosts:
				if _flat_distance(actor.global_position, pad.position) <= BOOST_RADIUS:
					_boost_locks[key] = elapsed + BOOST_LOCK_SECONDS
					_boost_motion[key] = {"direction": pad.direction, "remaining": BOOST_DURATION}
					_boost_count += 1
					_clear_actor_velocity(actor)
					_request_sound("javelin_teleport", actor.global_position)
					break
		if not _boost_motion.has(key):
			continue
		var burst: Dictionary = _boost_motion[key]
		var step := minf(delta, float(burst.remaining))
		var requested: Vector3 = burst.direction * BOOST_SPEED * step
		var travel := _safe_motion(actor, requested)
		actor.global_position += travel
		actor.global_position.y = 0.0
		_clear_actor_velocity(actor)
		burst.remaining = maxf(0.0, float(burst.remaining) - delta)
		if float(burst.remaining) <= 0.0 or travel.length() < requested.length() - 0.04:
			_boost_motion.erase(key)


func _clear_actor_velocity(actor: Node3D) -> void:
	if actor is CharacterBody3D:
		(actor as CharacterBody3D).velocity = Vector3.ZERO
	var controller := actor.get_node_or_null("TrainingBot")
	if controller != null:
		controller.set("_move_velocity", Vector3.ZERO)
		controller.set("_avoid_direction", Vector3.ZERO)
		controller.set("_has_tactical_destination", false)
		var navigation = controller.get("_navigation")
		if navigation != null and navigation.has_method("invalidate"):
			navigation.call("invalidate")


func _shape_query(actor: Node3D, at: Vector3) -> PhysicsShapeQueryParameters3D:
	if not actor is CollisionObject3D:
		return null
	for child in actor.get_children():
		if not child is CollisionShape3D or (child as CollisionShape3D).disabled:
			continue
		var collision := child as CollisionShape3D
		if collision.shape == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collision.shape
		query.transform = collision.global_transform
		query.transform.origin += at - actor.global_position
		# Lift by a small skin so a capsule resting on the arena floor does not
		# report the floor as an obstruction to every horizontal movement.
		query.transform.origin.y += 0.035
		query.collision_mask = 1 | 2 | 4 | 8 | MAGNETIC_WALL.SOLID_LAYER
		query.collide_with_areas = false
		query.exclude = MAGNETIC_WALL.owned_exclusions(self, [(actor as CollisionObject3D).get_rid()])
		query.margin = 0.01
		return query
	return null


func _position_is_clear(actor: Node3D, at: Vector3) -> bool:
	var half: Vector2 = _definition.half_size
	if absf(at.x) > half.x - 0.8 or absf(at.z) > half.y - 0.8:
		return false
	for other in _actors:
		if other == actor or not _live_actor(other):
			continue
		if _flat_distance(at, other.global_position) < 1.45:
			return false
	var query := _shape_query(actor, at)
	return query != null and get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _safe_motion(actor: Node3D, motion: Vector3, from: Vector3 = Vector3.INF) -> Vector3:
	var origin := actor.global_position if from == Vector3.INF else from
	var query := _shape_query(actor, origin)
	if query == null or motion.length_squared() < 0.000001:
		return Vector3.ZERO
	query.motion = motion
	var cast := get_world_3d().direct_space_state.cast_motion(query)
	if cast.size() < 2:
		return Vector3.ZERO
	return motion.normalized() * maxf(0.0, motion.length() * float(cast[0]) - (0.06 if float(cast[0]) < 1.0 else 0.0))


func _advance_shutters(delta: float) -> void:
	for index in range(_shutters.size()):
		var shutter: Dictionary = _shutters[index]
		var clock := fposmod(elapsed - GRACE_SECONDS + float(index) * 3.5, 7.0)
		var phase := "open"
		if elapsed >= GRACE_SECONDS:
			if clock < 1.2:
				phase = "warning"
			elif clock < 3.2:
				phase = "closed" if not _shutter_is_occupied(shutter.position) else "warning"
		shutter.phase = phase
		var collision: CollisionShape3D = shutter.collision
		var desired_opening := 0.0 if phase == "closed" else 1.0
		shutter.opening = move_toward(float(shutter.opening), desired_opening, delta * 3.5)
		var opening := float(shutter.opening)
		# Occupancy is checked throughout the visible slide; the gate only
		# becomes solid after both leaves have arrived at the center.
		collision.disabled = phase != "closed" or opening > 0.04
		var leaves: Array = shutter.leaves
		for leaf_index in range(leaves.size()):
			var leaf: Node3D = leaves[leaf_index]
			var side := -1.0 if leaf_index == 0 else 1.0
			leaf.position.x = side * (0.82 + opening * 1.72)
		var lamp_material: StandardMaterial3D = shutter.lamp_material
		lamp_material.albedo_color = AMBER if phase == "warning" else (Color("#f063a7") if phase == "closed" else Color("#b6a4ec"))
		lamp_material.emission = lamp_material.albedo_color
		lamp_material.emission_energy_multiplier = 0.7 + 0.4 * sin(elapsed * 10.0) if phase == "warning" else 0.4


func _shutter_is_occupied(at: Vector3) -> bool:
	for actor in _actors:
		if not _live_actor(actor):
			continue
		var offset := actor.global_position - at
		if absf(offset.x) < 2.55 and absf(offset.z) < 1.1:
			return true
	return false


func _request_sound(event_id: String, at: Vector3) -> void:
	sound_requested.emit(event_id, at)
	var sounds := get_node_or_null("/root/GameSfx")
	if sounds != null and (sounds.get("STREAMS") as Dictionary).has(event_id):
		sounds.call("play_event", event_id)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _build_fixtures() -> void:
	var definitions: Array = _definition.hazards
	var field_shader := Shader.new()
	field_shader.code = LANE_SHADER
	var shaft_shader := Shader.new()
	shaft_shader.code = SHAFT_SHADER
	var wave_shader := Shader.new()
	wave_shader.code = WAVE_SHADER
	for index in range(definitions.size()):
		var spec: Dictionary = definitions[index]
		var root := Node3D.new()
		root.name = "PulseLane%d" % (index + 1)
		root.position = spec.position
		add_child(root)
		var size: Vector2 = spec.size
		var color := Color("#ff6438") if spec.kind == "solar" else (Color("#52e2e4") if spec.kind == "tide" else Color("#e89bff"))
		var energy := ShaderMaterial.new()
		energy.shader = field_shader
		energy.set_shader_parameter("tint", color)
		energy.set_shader_parameter("extent", size)
		var field := MeshInstance3D.new()
		var field_mesh := QuadMesh.new()
		field_mesh.size = size
		field.mesh = field_mesh
		field.rotation.x = -PI * 0.5
		field.position.y = 0.060
		field.material_override = energy
		field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(field)
		var trim := _material(_definition.metal.lightened(0.15), 0.30)
		var inset := _material(_definition.metal.darkened(0.65), 0.65)
		# A machined open grate preserves the stone, mosaic or clock dial below.
		# Two inset rails and sparse cross ribs replace the former opaque slab.
		for side in [-1.0, 1.0]:
			_box(root, Vector3(side * size.x * 0.5, 0.041, 0), Vector3(0.032, 0.035, size.y), trim)
			_box(root, Vector3(0, 0.041, side * size.y * 0.5), Vector3(size.x, 0.035, 0.032), trim)
			if size.x >= size.y:
				_box(root, Vector3(0, 0.016, side * size.y * 0.29), Vector3(size.x - 0.12, 0.015, 0.10), inset)
			else:
				_box(root, Vector3(side * size.x * 0.29, 0.016, 0), Vector3(0.10, 0.015, size.y - 0.12), inset)
		var sparks := Node3D.new()
		sparks.name = "Discharge"
		root.add_child(sparks)
		var bright := _material(color.lightened(0.35), 0.1, color, 0.85)
		var animated: Array[ShaderMaterial] = []
		var length := maxf(size.x, size.y)
		var segments := maxi(3, int(length / 1.3))
		if spec.kind == "tide":
			for ribbon in range(2):
				var wave := ShaderMaterial.new()
				wave.shader = wave_shader
				wave.set_shader_parameter("offset", float(ribbon) * PI)
				var surface := _mesh(sparks, Vector3(0, 0.02, (-0.29 if ribbon == 0 else 0.29) * size.y), _wave_surface(size.x - 0.1, 1.02), wave)
				surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				animated.append(wave)
		for segment in range(segments):
			var travel := (float(segment) + 0.5) / float(segments) - 0.5
			var at := Vector3(travel * size.x, 0.03, 0) if size.x >= size.y else Vector3(0, 0.03, travel * size.y)
			var rib_size := Vector3(0.036, 0.015, size.y - 0.16) if size.x >= size.y else Vector3(size.x - 0.16, 0.015, 0.036)
			_box(root, at, rib_size, inset)
			if spec.kind == "solar":
				_cylinder(root, at, 0.11, 0.035, trim)
				_cylinder(root, at + Vector3.UP * 0.012, 0.066, 0.03, inset)
				var shaft := ShaderMaterial.new()
				shaft.shader = shaft_shader
				shaft.set_shader_parameter("tint", color)
				var halo := _cylinder(sparks, at + Vector3.UP * 0.84, 0.21, 1.7, shaft)
				halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_cylinder(sparks, at + Vector3.UP * 0.84, 0.012, 1.7, bright)
				animated.append(shaft)
			elif spec.kind == "clock":
				var coupler := _torus(root, at, 0.11, 0.14, trim)
				coupler.scale.y = 0.35
				_energy_arc(sparks, at, 1.55, float(segment) + float(index) * 2.0, bright)
		var marks: Array[MeshInstance3D] = []
		var warning_material := _material(AMBER, 0.4, AMBER, 0.35)
		for segment in range(segments):
			var travel := (float(segment) + 0.5) / float(segments) - 0.5
			for side in [-1.0, 1.0]:
				var at := Vector3(travel * size.x, 0.067, side * (size.y * 0.5 - 0.14)) if size.x >= size.y else Vector3(side * (size.x * 0.5 - 0.14), 0.067, travel * size.y)
				for wing in [-1.0, 1.0]:
					var offset := Vector3(wing * 0.065, 0, 0) if size.x < size.y else Vector3(0, 0, wing * 0.065)
					var wing_size := Vector3(0.035, 0.016, 0.17) if size.x < size.y else Vector3(0.17, 0.016, 0.035)
					var mark := _box(root, at + offset, wing_size, warning_material)
					mark.rotation.y = wing * PI * 0.25
					marks.append(mark)
		_fixtures.append({"kind": spec.kind, "position": spec.position, "size": size, "damage": spec.damage,
			"phase": "idle", "remaining": 0.0, "serial": 0, "hit": {}, "root": root,
			"energy": energy, "warning_material": warning_material, "sparks": sparks,
			"marks": marks, "color": color, "animated": animated})


func _update_fixture_visual(fixture: Dictionary) -> void:
	var energy: ShaderMaterial = fixture.energy
	var warning_material: StandardMaterial3D = fixture.warning_material
	var sparks: Node3D = fixture.sparks
	sparks.visible = fixture.phase == "active"
	energy.set_shader_parameter("clock", elapsed)
	energy.set_shader_parameter("phase", 1.0 if fixture.phase == "warning" else (2.0 if fixture.phase == "active" else 0.0))
	for animated in fixture.animated:
		(animated as ShaderMaterial).set_shader_parameter("clock", elapsed)
	if fixture.phase == "warning":
		var pulse := 0.55 + 0.45 * sin(elapsed * 10.0)
		warning_material.emission_energy_multiplier = 0.18 + pulse * 0.42
	elif fixture.phase == "active":
		warning_material.emission_energy_multiplier = 0.12
		sparks.scale.y = 0.92 + sin(elapsed * 25.0) * 0.08
	else:
		warning_material.emission_energy_multiplier = 0.0
	for mark in fixture.marks:
		(mark as MeshInstance3D).visible = fixture.phase != "idle"


func _build_portals() -> void:
	_shader = Shader.new()
	_shader.code = PORTAL_SHADER
	var positions: Array = _definition.portals
	var metal := _material(_definition.metal, 0.27)
	for index in range(positions.size()):
		var at: Vector3 = positions[index]
		var inward := Vector3(-at.x, 0, -at.z).normalized()
		var root := Node3D.new()
		root.name = "Passage%d" % (index + 1)
		root.position = at
		root.rotation.y = atan2(inward.x, inward.z)
		add_child(root)
		var color: Color = _definition.accent if index == 0 else _definition.color
		var luminous := _material(color, 0.2, color, 1.0)
		var dark := _material(_definition.metal.darkened(0.40), 0.3)
		var circle := _torus(root, Vector3(0, 1.25, 0), 0.92, 1.07, metal)
		circle.rotation.x = PI * 0.5
		var ring := _torus(root, Vector3(0, 1.25, 0.035), 0.855, 0.90, luminous)
		ring.rotation.x = PI * 0.5
		for side in [-1.0, 1.0]:
			_box(root, Vector3(side * 0.9, 0.35, 0), Vector3(0.22, 0.7, 0.30), dark)
			_box(root, Vector3(side * 0.9, 0.45, 0.19), Vector3(0.08, 0.40, 0.04), luminous)
			_box(root, Vector3(side * 0.9, 0.12, 0), Vector3(0.40, 0.18, 0.42), metal)
		var sparkles := Node3D.new()
		sparkles.position.y = 1.25
		root.add_child(sparkles)
		for segment in range(12):
			var angle := float(segment) * TAU / 12.0
			var mark := _box(sparkles, Vector3(sin(angle), cos(angle), 0.06) * 1.12, Vector3(0.045, 0.13, 0.04), luminous)
			mark.rotation.z = -angle
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(1.78, 1.78)
		quad.mesh = mesh
		quad.position = Vector3(0, 1.25, 0.02)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var swirl := ShaderMaterial.new()
		swirl.shader = _shader
		swirl.set_shader_parameter("tint", color)
		quad.material_override = swirl
		root.add_child(quad)
		var light := OmniLight3D.new()
		light.position = Vector3(0, 1.35, 0.15)
		light.light_color = color
		light.light_energy = 0.28
		light.omni_range = 3.1
		light.omni_attenuation = 2.0
		root.add_child(light)
		_portals.append({"position": at, "root": root, "ring": ring, "sparkles": sparkles, "swirl": swirl, "light": light})


func _build_boosts() -> void:
	var metal := _material(_definition.metal.darkened(0.35), 0.4)
	var color: Color = _definition.accent
	var glow := _material(color.lightened(0.2), 0.25, color, 0.8)
	var positions: Array = _definition.boosts
	for at_value in positions:
		var at: Vector3 = at_value
		var direction := Vector3.FORWARD if at.x < 0.0 else Vector3.BACK
		var root := Node3D.new()
		root.name = "SlipstreamLeft" if at.x < 0.0 else "SlipstreamRight"
		root.position = at
		root.rotation.y = 0.0 if at.x < 0.0 else PI
		add_child(root)
		_box(root, Vector3(0, 0.04, 0), Vector3(1.35, 0.08, 1.80), metal)
		for side in [-1.0, 1.0]:
			_box(root, Vector3(side * 0.58, 0.08, 0), Vector3(0.06, 0.03, 1.60), glow)
		var arrows: Array[Node3D] = []
		for index in range(3):
			var arrow := Node3D.new()
			arrow.position = Vector3(0, 0.11, 0.5 - float(index) * 0.47)
			root.add_child(arrow)
			for side in [-1.0, 1.0]:
				var bar := _box(arrow, Vector3(side * 0.15, 0, 0), Vector3(0.08, 0.024, 0.43), glow)
				bar.rotation.y = side * PI * 0.25
			arrows.append(arrow)
		_boosts.append({"position": at, "direction": direction, "arrows": arrows})


func _build_shutters() -> void:
	var metal := _material(_definition.metal, 0.3)
	var dark := _material(_definition.floor.darkened(0.28), 0.4)
	for index in range(2):
		var at := Vector3(0, 0, -5.3 if index == 0 else 5.3)
		var root := Node3D.new()
		root.name = "RhythmicShutter%d" % (index + 1)
		root.position = at
		add_child(root)
		var lamp := _material(Color("#b6a4ec"), 0.35, Color("#b6a4ec"), 0.45)
		for side in [-1.0, 1.0]:
			_box(root, Vector3(side * 2.02, 1.15, 0), Vector3(0.15, 2.3, 0.28), metal)
		_box(root, Vector3(0, 2.32, 0), Vector3(4.2, 0.16, 0.30), metal)
		_box(root, Vector3(0, 2.24, 0.17), Vector3(3.70, 0.055, 0.03), lamp)
		_box(root, Vector3(0, 0.036, 0), Vector3(5.4, 0.025, 0.08), metal)
		var leaves: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var leaf := Node3D.new()
			leaf.position = Vector3(side * 2.54, 0, 0)
			root.add_child(leaf)
			_box(leaf, Vector3(0, 1.05, 0), Vector3(1.62, 2.02, 0.22), dark)
			for segment in range(5):
				_box(leaf, Vector3(0, 0.25 + float(segment) * 0.40, 0.14), Vector3(1.57, 0.07, 0.03), metal)
			_box(leaf, Vector3(-side * 0.68, 1.05, 0.14), Vector3(0.04, 1.70, 0.03), lamp)
			leaves.append(leaf)
		var body := StaticBody3D.new()
		body.name = "GateCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.4, 2.1, 0.40)
		collision.shape = box
		collision.position.y = 1.06
		collision.disabled = true
		body.add_child(collision)
		_shutters.append({"position": at, "phase": "open", "opening": 1.0, "collision": collision, "leaves": leaves, "lamp_material": lamp})


func _reset_visuals() -> void:
	for fixture in _fixtures:
		_update_fixture_visual(fixture)
	for portal in _portals:
		(portal.swirl as ShaderMaterial).set_shader_parameter("clock", elapsed)
		(portal.swirl as ShaderMaterial).set_shader_parameter("live", 0.0)
		(portal.ring as Node3D).rotation.z = elapsed * 0.24
		(portal.sparkles as Node3D).rotation.z = -elapsed * 0.75
		(portal.light as OmniLight3D).light_energy = 0.28
	for pad in _boosts:
		for arrow in pad.arrows:
			(arrow as Node3D).position.y = 0.11
			(arrow as Node3D).scale = Vector3.ONE
	for shutter in _shutters:
		shutter.phase = "open"
		shutter.opening = 1.0
		(shutter.collision as CollisionShape3D).disabled = true
		var lamp: StandardMaterial3D = shutter.lamp_material
		lamp.albedo_color = Color("#b6a4ec")
		lamp.emission = lamp.albedo_color
		lamp.emission_energy_multiplier = 0.4
		var leaves: Array = shutter.leaves
		for index in range(leaves.size()):
			(leaves[index] as Node3D).position.x = -2.54 if index == 0 else 2.54


func _material(color: Color, roughness: float, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.65 if energy == 0.0 else 0.15
	material.emission_enabled = energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = energy
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _mesh(parent: Node3D, at: Vector3, shape: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _wave_surface(width: float, height: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 64
	for index in range(SEGMENTS + 1):
		var progress := float(index) / float(SEGMENTS)
		var x := (progress - 0.5) * width
		vertices.append(Vector3(x, 0, 0))
		vertices.append(Vector3(x, height, 0))
		uv.append(Vector2(progress, 0))
		uv.append(Vector2(progress, 1))
		normals.append(Vector3.FORWARD)
		normals.append(Vector3.FORWARD)
		if index < SEGMENTS:
			var start := index * 2
			indices.append_array(PackedInt32Array([start, start + 1, start + 3, start, start + 3, start + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _energy_arc(parent: Node3D, at: Vector3, height: float, seed: float, material: Material) -> void:
	var previous := at
	for index in range(1, 7):
		var point := at + Vector3(sin(seed + float(index) * 3.3) * 0.19, height * float(index) / 6.0, sin(seed * 1.7 + float(index) * 2.6) * 0.10)
		var direction := point - previous
		var segment := _cylinder(parent, (point + previous) * 0.5, 0.023, direction.length(), material)
		segment.quaternion = Quaternion(Vector3.UP, direction.normalized())
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		previous = point


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _mesh(parent, at, shape, material)


func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 12
	return _mesh(parent, at, shape, material)


func _torus(parent: Node3D, at: Vector3, inner: float, outer: float, material: Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	shape.rings = 40
	shape.ring_segments = 12
	return _mesh(parent, at, shape, material)
