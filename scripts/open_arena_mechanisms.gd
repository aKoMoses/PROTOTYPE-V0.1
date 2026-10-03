extends "res://scripts/compact_arena_mechanisms.gd"

## Two open arenas: mechanical floor transport and shot-reactive pressure waves.
## The stage owns solid cover; this layer builds only the arena mechanisms.
const PUSH_MOTION := preload("res://scripts/knockback_motion.gd")
const TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const RING_INNER_RADIUS := 0.9 * CATALOG.LAYOUT_SCALE
const RING_SEAM_RADIUS := 4.0 * CATALOG.LAYOUT_SCALE
const RING_OUTER_RADIUS := 7.6 * CATALOG.LAYOUT_SCALE
const INNER_ANGULAR_SPEED := 0.22
const OUTER_ANGULAR_SPEED := -0.14
const ORBIT_RAMP := 1.2
const RESONATOR_COOLDOWN := 3.0
const SHOT_WARNING := 0.8
const WAVE_START_RADIUS := 0.5
const WAVE_END_RADIUS := 12.5
const WAVE_SPEED := 4.8
const WAVE_HALF_WIDTH := 0.25
const WAVE_PUSH_DISTANCE := 4.2
const WAVE_PUSH_DURATION := 0.38
const WAVE_SEGMENTS := 128
const MAX_WAVES := 4
const MAX_PHYSICAL_STEP := 1.0 / 60.0

const CRYSTAL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.72, 0.63, 1.0, 1.0);
uniform float clock = 0.0;
uniform float excitation = 0.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.7);
	float stripe = pow(0.5 + 0.5 * sin(UV.y * 23.0 - clock * 2.3), 17.0);
	float breath = 0.5 + 0.5 * sin(clock * 1.7);
	float cut = smoothstep(0.0, 1.0, abs(NORMAL.x * 0.7 + NORMAL.z * 0.3));
	ALBEDO = mix(tint.rgb * (0.48 + cut * 0.29), vec3(1.0, 0.75, 0.35), excitation * 0.45);
	ROUGHNESS = 0.19;
	METALLIC = 0.14;
	EMISSION = tint.rgb * (0.12 + rim * 0.35 + stripe * 0.22 + breath * 0.06 + excitation * 1.6);
	ALPHA = 0.68 + rim * 0.09 + breath * 0.025 + excitation * 0.12;
}
"""

const PRESSURE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.78, 0.58, 1.0, 1.0);
uniform float clock = 0.0;
uniform float strength = 1.0;
void vertex() {
	VERTEX.y *= 0.87 + sin(UV.x * 31.0 - clock * 9.0) * 0.13;
}
void fragment() {
	float foot = 1.0 - smoothstep(0.0, 0.19, UV.y);
	float crest = smoothstep(0.76, 0.96, UV.y);
	float silk = pow(0.5 + 0.5 * sin(UV.y * 22.0 + UV.x * 52.0 - clock * 7.0), 13.0);
	float overtone = exp(-pow((UV.y - 0.46) * 27.0, 2.0));
	ALBEDO = mix(tint.rgb * 0.52, vec3(0.89, 0.84, 1.0), crest * 0.43);
	ALPHA = (0.06 + foot * 0.65 + crest * 0.85 + silk * 0.16 + overtone * 0.24) * strength;
}
"""

class CrystalReceiver extends Area3D:
	var mechanisms: Node
	var resonator_index := 0

	func projectile_impact(at: Vector3) -> void:
		if is_instance_valid(mechanisms):
			mechanisms.call("_resonator_projectile_impact", resonator_index, at)

	# Legacy weapon callbacks can safely discover this node. Without health or
	# max-health methods it is neither a combat target nor a healing opportunity.
	func take_damage(_amount: float, _source: String = "", _attack: String = "") -> float:
		return 0.0


var inner_angle := 0.0
var outer_angle := 0.0
var inner_rate := 0.0
var outer_rate := 0.0
var _stage: Node3D
var _orbit_cue: StandardMaterial3D
var _resonators: Array[Dictionary] = []
var _waves: Array[Dictionary] = []
var _shoves: Array[Dictionary] = []
var _actor_previous: Dictionary = {}
var _actor_transport: Dictionary = {}
var _transport_distance := 0.0
var _pulse_count := 0
var _wave_hits := 0
var _shot_triggers := 0
var _periodic_triggers := 0
var _chain_triggers := 0
var _next_self_resonance := GRACE_SECONDS
var _next_self_source := 0
var _pressure_shader: Shader


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Later than normal actor/projectile movement; own action state stays intact.
	process_physics_priority = 30
	add_to_group("arena_hazards")
	_definition = CATALOG.definition(arena_id)
	if arena_id == "gyre":
		_build_orbit_cues()
	elif arena_id == "resonance":
		_build_resonators()
	visible = enabled
	_reset_visuals()


func set_stage(stage: Node3D) -> void:
	_stage = stage
	_sync_orbit_stage()


func reset_round() -> void:
	_clear_waves()
	_shoves.clear()
	_actor_previous.clear()
	_actor_transport.clear()
	inner_angle = 0.0
	outer_angle = 0.0
	inner_rate = 0.0
	outer_rate = 0.0
	_transport_distance = 0.0
	_pulse_count = 0
	_wave_hits = 0
	_shot_triggers = 0
	_periodic_triggers = 0
	_chain_triggers = 0
	_next_self_resonance = GRACE_SECONDS + float(_definition.get("period", 22.0))
	_next_self_source = 0
	for resonator in _resonators:
		resonator.cooldown_until = 0.0
		resonator.activations = 0
		resonator.impacts = 0
		resonator.last_impact = -100.0
	super.reset_round()
	_sync_orbit_stage()


func start_round() -> void:
	super.start_round()
	_update_resonators()


func stop_round() -> void:
	_clear_waves()
	_shoves.clear()
	inner_rate = 0.0
	outer_rate = 0.0
	super.stop_round()
	_sync_orbit_stage()


func advance(delta: float) -> void:
	if not _simulation_live() or delta <= 0.0:
		return
	# Fixed-size slices preserve wave crossings and collision sweeps even when
	# a diagnostic call advances a large amount of simulation time at once.
	var remaining := delta
	while remaining > 0.000001:
		var step := minf(remaining, MAX_PHYSICAL_STEP)
		elapsed += step
		if arena_id == "gyre":
			_advance_orbits(step)
		elif arena_id == "resonance":
			_advance_resonance(step)
		for actor in _actors:
			if is_instance_valid(actor):
				_actor_previous[actor.get_instance_id()] = actor.global_position
		remaining -= step
	_sync_orbit_stage()
	_update_resonators()
	for wave in _waves:
		_update_wave_visual(wave)


func _simulation_live() -> bool:
	return enabled and running and is_inside_tree() and not get_tree().paused


func _can_transport(actor: Node3D) -> bool:
	if not _live_actor(actor):
		return false
	if "_stasis_remaining" in actor and float(actor.get("_stasis_remaining")) > 0.0:
		return false
	if actor.has_method("is_eclipse_travelling") and bool(actor.call("is_eclipse_travelling")):
		return false
	if actor.has_method("is_fulguro_projected") and bool(actor.call("is_fulguro_projected")):
		return false
	if actor.has_method("is_pelto_pulled") and bool(actor.call("is_pelto_pulled")):
		return false
	if "_dash_active" in actor and bool(actor.get("_dash_active")):
		return false
	if "_mekatana_movement_owned" in actor and bool(actor.get("_mekatana_movement_owned")):
		return false
	var bot := actor.get_node_or_null("TrainingBot")
	if bot != null:
		var equipment = bot.get("_duel_equipment")
		if equipment != null:
			if bool(equipment.call("is_action_locked")) or bool(equipment.call("is_dashing")) or bool(equipment.call("owns_mekatana_movement")):
				return false
	return true


func _advance_orbits(delta: float) -> void:
	var local_clock := maxf(0.0, elapsed - GRACE_SECONDS)
	var period := float(_definition.get("period", 18.0))
	var clock := fposmod(local_clock, period)
	var direction := 1.0 if int(local_clock / period) % 2 == 0 else -1.0
	var envelope := smoothstep(0.0, ORBIT_RAMP, clock) * smoothstep(0.0, ORBIT_RAMP, period - clock)
	if elapsed <= GRACE_SECONDS:
		envelope = 0.0
	inner_rate = INNER_ANGULAR_SPEED * direction * envelope
	outer_rate = OUTER_ANGULAR_SPEED * direction * envelope
	inner_angle += inner_rate * delta
	outer_angle += outer_rate * delta
	if _orbit_cue != null:
		var warning := elapsed > GRACE_SECONDS and (clock < ORBIT_RAMP or clock > period - ORBIT_RAMP)
		_orbit_cue.albedo_color = AMBER if warning else (_definition.get("accent", Color("#ff965f")) as Color)
		_orbit_cue.emission = _orbit_cue.albedo_color
		_orbit_cue.emission_energy_multiplier = 0.25 + (0.25 + sin(elapsed * 7.0) * 0.20 if warning else 0.0)
	for actor in _actors:
		if not _can_transport(actor):
			continue
		var origin := actor.global_position
		if TRAVERSAL.height(actor, origin) > 0.02:
			continue
		var radius := Vector2(origin.x, origin.z).length()
		if radius < RING_INNER_RADIUS or radius > RING_OUTER_RADIUS:
			continue
		var seam := smoothstep(RING_SEAM_RADIUS - 0.14, RING_SEAM_RADIUS + 0.14, radius)
		var rate := lerpf(inner_rate, outer_rate, seam)
		rate *= smoothstep(RING_INNER_RADIUS, RING_INNER_RADIUS + 0.18, radius)
		rate *= 1.0 - smoothstep(RING_OUTER_RADIUS - 0.18, RING_OUTER_RADIUS, radius)
		var destination := origin.rotated(Vector3.UP, rate * delta)
		var movement := _bounded_motion(actor, destination - origin)
		actor.global_position += movement
		TRAVERSAL.snap(actor)
		_record_transport(actor, movement.length())


func _sync_orbit_stage() -> void:
	if arena_id == "gyre" and is_instance_valid(_stage) and _stage.has_method("set_orbit_angles"):
		_stage.call("set_orbit_angles", inner_angle, outer_angle)
		# The inlaid chevrons belong to the visual rotor roots. Their direction
		# follows the actual reversal while the simulation and transport are unchanged.
		for entry in _stage.get_meta("open_orbit_direction_cues", []):
			var rate := inner_rate if int(entry.index) == 0 else outer_rate
			var positive: Node3D = entry.positive
			var negative: Node3D = entry.negative
			if absf(rate) > 0.00001:
				positive.visible = rate > 0.0
				negative.visible = rate < 0.0
			elif elapsed <= GRACE_SECONDS:
				positive.visible = int(entry.index) == 0
				negative.visible = int(entry.index) != 0


func _resonator_projectile_impact(index: int, _at: Vector3) -> void:
	if index < 0 or index >= _resonators.size() or not _simulation_live():
		return
	var resonator: Dictionary = _resonators[index]
	resonator.impacts = int(resonator.impacts) + 1
	resonator.last_impact = elapsed
	trigger_resonator(index)


func trigger_resonator(index: int) -> bool:
	return _trigger_resonator(index, SHOT_WARNING, "shot", {})


func _trigger_resonator(index: int, warning: float, source: String, family: Dictionary) -> bool:
	if arena_id != "resonance" or not _simulation_live() or elapsed < GRACE_SECONDS - 0.000001:
		return false
	if index < 0 or index >= _resonators.size() or _waves.size() >= MAX_WAVES:
		return false
	var resonator: Dictionary = _resonators[index]
	if elapsed < float(resonator.cooldown_until) - 0.000001:
		return false
	if family.has(index):
		return false
	family[index] = true
	resonator.cooldown_until = elapsed + RESONATOR_COOLDOWN
	resonator.activations = int(resonator.activations) + 1
	_pulse_count += 1
	_serial += 1
	var color: Color = resonator.color
	var root := Node3D.new()
	root.name = "PressureWave%d" % _serial
	root.position = resonator.position
	add_child(root)
	var curtain := _mesh(root, Vector3(0, 0.035, 0), _pressure_curtain(), _pressure_material(color))
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var edge_material := _material(AMBER, 0.3, AMBER, 0.32)
	var edge := _torus(root, Vector3(0, 0.048, 0), 0.95, 1.05, edge_material)
	edge.scale.y = 0.20
	var limits := PackedFloat32Array()
	for segment in range(WAVE_SEGMENTS + 1):
		var angle := TAU * float(segment) / WAVE_SEGMENTS
		var end: Vector3 = resonator.position + Vector3(cos(angle), 0, sin(angle)) * WAVE_END_RADIUS
		limits.append(_pressure_reach(resonator.position, end))
	var wave := {"id": _serial, "index": index, "source": source, "position": resonator.position, "limits": limits,
		"phase": "warning", "remaining": warning, "active_at": elapsed + warning, "radius": WAVE_START_RADIUS,
		"previous_radius": WAVE_START_RADIUS, "hit": {}, "family": family,
		"root": root, "curtain": curtain, "edge": edge, "edge_material": edge_material, "color": color}
	_waves.append(wave)
	_update_wave_visual(wave)
	if source == "shot":
		_shot_triggers += 1
		_next_self_resonance = elapsed + float(_definition.get("period", 8.5))
	elif source == "periodic":
		_periodic_triggers += 1
	else:
		_chain_triggers += 1
	_play_pressure_sound("projector_charge", resonator.position)
	_update_resonators()
	return true


func _advance_resonance(delta: float) -> void:
	if _resonators.is_empty():
		return
	if elapsed >= _next_self_resonance - 0.000001:
		if _trigger_resonator(_next_self_source % _resonators.size(), float(_definition.get("warning", 1.4)), "periodic", {}):
			_next_self_source += 1
			_next_self_resonance = elapsed + float(_definition.get("period", 8.5))
		else:
			_next_self_resonance = elapsed + 0.25
	for wave in _waves.duplicate():
		wave.previous_radius = float(wave.radius)
		wave.remaining = maxf(0.0, float(wave.active_at) - elapsed)
		if elapsed >= float(wave.active_at) - 0.000001:
			if wave.phase == "warning":
				wave.phase = "active"
				_play_pressure_sound("projector_wave", wave.position)
			wave.radius = minf(WAVE_END_RADIUS, WAVE_START_RADIUS + maxf(0.0, elapsed - float(wave.active_at)) * WAVE_SPEED)
		if wave.phase == "active":
			_hit_wave(wave)
			_chain_wave(wave)
		if float(wave.radius) >= WAVE_END_RADIUS - 0.000001:
			(wave.root as Node3D).queue_free()
			_waves.erase(wave)
	_advance_shoves(delta)


func _hit_wave(wave: Dictionary) -> void:
	for actor in _actors:
		if not _can_transport(actor):
			continue
		var key := actor.get_instance_id()
		if wave.hit.has(key):
			continue
		var position := actor.global_position
		var previous: Vector3 = _actor_previous.get(key, position)
		var before := _flat_distance(previous, wave.position) - float(wave.previous_radius)
		var after := _flat_distance(position, wave.position) - float(wave.radius)
		var skin := WAVE_HALF_WIDTH + _actor_radius(actor)
		if minf(before, after) > skin or maxf(before, after) < -skin:
			continue
		if not _pressure_visible(wave.position, position):
			continue
		wave.hit[key] = true
		_wave_hits += 1
		var direction: Vector3 = position - (wave.position as Vector3)
		direction.y = 0.0
		if direction.length_squared() <= 0.000001:
			direction = Vector3.RIGHT
		_shoves.append({"actor": weakref(actor), "direction": direction.normalized(),
			"distance": WAVE_PUSH_DISTANCE, "remaining": WAVE_PUSH_DURATION, "wave": int(wave.id)})
		_play_pressure_sound("projector_push", position)


func _chain_wave(wave: Dictionary) -> void:
	for index in range(_resonators.size()):
		if (wave.family as Dictionary).has(index):
			continue
		var distance := _flat_distance(wave.position, _resonators[index].position)
		if distance >= float(wave.previous_radius) - 0.10 and distance <= float(wave.radius) + 0.10:
			if _pressure_visible(wave.position, _resonators[index].position):
				_trigger_resonator(index, SHOT_WARNING, "chain", wave.family)


func _pressure_reach(from: Vector3, to: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.9, to + Vector3.UP * 0.9, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return from.distance_to((hit.position as Vector3) - Vector3.UP * 0.9) if not hit.is_empty() else from.distance_to(to)


func _pressure_visible(from: Vector3, to: Vector3) -> bool:
	return _pressure_reach(from, to) >= _flat_distance(from, to) - 0.03


func _advance_shoves(delta: float) -> void:
	for shove in _shoves.duplicate():
		var actor := (shove.actor as WeakRef).get_ref() as Node3D
		if not _can_transport(actor):
			_shoves.erase(shove)
			continue
		var distance := PUSH_MOTION.step(float(shove.distance), float(shove.remaining), delta)
		var requested: Vector3 = shove.direction * distance
		var movement := _bounded_motion(actor, requested)
		actor.global_position += movement
		actor.global_position.y = 0.0
		_record_transport(actor, movement.length())
		shove.distance = maxf(0.0, float(shove.distance) - distance)
		shove.remaining = maxf(0.0, float(shove.remaining) - delta)
		if float(shove.remaining) <= 0.000001 or movement.length() < distance - 0.01:
			_shoves.erase(shove)


func _actor_radius(actor: Node3D) -> float:
	for child in actor.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			var collision := child as CollisionShape3D
			var scale: Vector3 = collision.global_basis.get_scale()
			return (collision.shape as CapsuleShape3D).radius * maxf(absf(scale.x), absf(scale.z))
	return 0.65


func _inside_footprint(point: Vector3, radius: float) -> bool:
	var half: Vector2 = _definition.half_size
	var skin := radius + 0.04
	if absf(point.x) > half.x - skin or absf(point.z) > half.y - skin:
		return false
	var cut := float(_definition.get("corner_cut", 0.0))
	return cut <= 0.0 or absf(point.x) + absf(point.z) <= half.x + half.y - cut - skin * sqrt(2.0)


func _bounded_motion(actor: Node3D, motion: Vector3) -> Vector3:
	motion.y = 0.0
	var origin := actor.global_position
	var radius := _actor_radius(actor)
	if not _inside_footprint(origin + motion, radius):
		var low := 0.0
		var high := 1.0
		for iteration in range(12):
			var middle := (low + high) * 0.5
			if _inside_footprint(origin + motion * middle, radius):
				low = middle
			else:
				high = middle
		motion *= low
	return _safe_motion(actor, TRAVERSAL.motion(actor, motion))


func _shape_query(actor: Node3D, at: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := super._shape_query(actor, at)
	if query != null:
		var excluded := query.exclude
		excluded.append_array(TRAVERSAL.exclusions(actor))
		query.exclude = excluded
	return query


func _record_transport(actor: Node3D, distance: float) -> void:
	_transport_distance += distance
	var key := actor.get_instance_id()
	_actor_transport[key] = float(_actor_transport.get(key, 0.0)) + distance


func get_threats() -> Array[Dictionary]:
	var threats: Array[Dictionary] = []
	if not running or not enabled or arena_id != "resonance":
		return threats
	for wave in _waves:
		threats.append({"id": int(wave.id), "kind": "pressure_ring", "position": wave.position,
			"radius": float(wave.radius), "half_width": WAVE_HALF_WIDTH,
			"speed": WAVE_SPEED if wave.phase == "active" else 0.0,
			"direction": Vector3.ZERO, "length": 0.0, "remaining": wave.remaining, "phase": wave.phase})
	return threats


func threat_at(point: Vector3, margin: float = 0.0, known_threats: Array[Dictionary] = []) -> Dictionary:
	var threats := known_threats if not known_threats.is_empty() else get_threats()
	for threat in threats:
		if not _pressure_visible(threat.position, point):
			continue
		var distance := _flat_distance(point, threat.position)
		var skin := float(threat.half_width) + margin
		var radius := float(threat.radius)
		# Include the short distance the crest will cover during the bot's normal
		# reaction delay, rather than marking the whole disk as dangerous.
		var prediction := float(threat.get("speed", 0.0)) * 0.22
		if distance >= radius - skin and distance <= radius + prediction + skin:
			return threat
	return {}


func get_snapshot() -> Dictionary:
	var resonators: Array[Dictionary] = []
	var waves: Array[Dictionary] = []
	for index in range(_resonators.size()):
		var resonator: Dictionary = _resonators[index]
		resonators.append({"index": index, "position": resonator.position,
			"cooldown": maxf(0.0, float(resonator.cooldown_until) - elapsed),
			"activations": int(resonator.activations), "impacts": int(resonator.impacts)})
	for wave in _waves:
		waves.append({"id": int(wave.id), "source": wave.source, "position": wave.position,
			"phase": wave.phase, "remaining": wave.remaining, "radius": wave.radius,
			"previous_radius": wave.previous_radius, "hits": (wave.hit as Dictionary).size()})
	return {"arena_id": arena_id, "enabled": enabled, "running": running, "elapsed": elapsed,
		"tier": 1, "busy": _waves.size(), "bolts": 0, "events": _pulse_count,
		"portals": 0, "teleports": 0, "boosts": 0, "shutters": [], "phases": [],
		"inner_angle": inner_angle, "outer_angle": outer_angle,
		"inner_rate": inner_rate, "outer_rate": outer_rate,
		"transport_distance": _transport_distance, "actor_transport": _actor_transport.duplicate(),
		"resonators": resonators, "waves": waves, "pulse_count": _pulse_count,
		"wave_hits": _wave_hits, "shoves": _shoves.size(), "shot_triggers": _shot_triggers,
		"periodic_triggers": _periodic_triggers, "chain_triggers": _chain_triggers}


func _clear_waves() -> void:
	for wave in _waves:
		if is_instance_valid(wave.root):
			(wave.root as Node3D).queue_free()
	_waves.clear()


func _reset_visuals() -> void:
	if _orbit_cue != null:
		_orbit_cue.albedo_color = _definition.get("accent", Color("#ff965f"))
		_orbit_cue.emission = _orbit_cue.albedo_color
		_orbit_cue.emission_energy_multiplier = 0.15
	_update_resonators()
	_sync_orbit_stage()


func _build_orbit_cues() -> void:
	_orbit_cue = _material(_definition.accent, 0.30, _definition.accent, 0.25)
	for radius in [RING_SEAM_RADIUS, RING_OUTER_RADIUS + 0.12]:
		var seam := _torus(self, Vector3(0, 0.026, 0), float(radius) - 0.018, float(radius) + 0.018, _orbit_cue)
		seam.scale.y = 0.20
		seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_resonators() -> void:
	var crystal_shader := Shader.new()
	crystal_shader.code = CRYSTAL_SHADER
	_pressure_shader = Shader.new()
	_pressure_shader.code = PRESSURE_SHADER
	var positions: Array = _definition.get("resonators", [])
	var colors := [Color("#79bae1"), Color("#d786c7"), Color("#a395e6"), Color("#79cbbb")]
	var metal := _material(_definition.metal, 0.3)
	for index in range(positions.size()):
		var area := CrystalReceiver.new()
		area.name = "CrystalResonator%d" % (index + 1)
		area.position = positions[index]
		area.mechanisms = self
		area.resonator_index = index
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("non_blocking_projectile_receiver", true)
		area.add_to_group("arena_resonators")
		add_child(area)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.30
		shape.height = 1.75
		collision.shape = shape
		collision.position.y = 0.93
		area.add_child(collision)
		var material := ShaderMaterial.new()
		material.shader = crystal_shader
		material.set_shader_parameter("tint", colors[index % colors.size()])
		var crystal := _mesh(area, Vector3(0, 0.04, 0), _crystal_shape(), material)
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var edge_material := _material((colors[index % colors.size()] as Color).lightened(0.22), 0.3, colors[index % colors.size()], 0.55)
		_crystal_outline(crystal, edge_material)
		var foot := _torus(area, Vector3(0, 0.036, 0), 0.25, 0.31, metal)
		foot.scale.y = 0.25
		foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var socket_material := _material(Color("#273b46"), 0.31)
		var socket := _cylinder(area, Vector3(0, 0.012, 0), 0.36, 0.021, socket_material)
		socket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.position.y = 0.9
		light.light_color = colors[index % colors.size()]
		light.light_energy = 0.12
		light.omni_range = 1.7
		area.add_child(light)
		_resonators.append({"position": positions[index], "area": area, "crystal": crystal,
			"material": material, "edge_material": edge_material, "light": light, "color": colors[index % colors.size()],
			"cooldown_until": 0.0, "activations": 0, "impacts": 0, "last_impact": -100.0})


func _update_resonators() -> void:
	for index in range(_resonators.size()):
		var resonator: Dictionary = _resonators[index]
		(resonator.area as Area3D).collision_layer = (2 | 4) if enabled and running else 0
		var excitation := maxf(0.0, 1.0 - (elapsed - float(resonator.last_impact)) / 0.8)
		for wave in _waves:
			if int(wave.index) == index and wave.phase == "warning":
				excitation = 0.95 + 0.35 * sin(elapsed * 12.0)
		var material: ShaderMaterial = resonator.material
		material.set_shader_parameter("clock", elapsed)
		material.set_shader_parameter("excitation", excitation if running else 0.0)
		var edge_material: StandardMaterial3D = resonator.edge_material
		edge_material.emission_energy_multiplier = 0.46 + (0.09 * sin(elapsed * 1.7 + float(index)) + excitation * 0.30 if running else 0.0)
		(resonator.crystal as Node3D).position.y = 0.04 + (sin(elapsed * 1.7 + float(index) * 1.8) * 0.025 if running else 0.0)
		(resonator.light as OmniLight3D).omni_range = 3.2
		(resonator.light as OmniLight3D).light_energy = 0.28 + excitation * 1.4 if running else 0.12


func _update_wave_visual(wave: Dictionary) -> void:
	var radius := float(wave.radius)
	var curtain: MeshInstance3D = wave.curtain
	curtain.visible = wave.phase == "active"
	curtain.mesh = _clipped_wave_mesh(wave.limits, radius, false)
	curtain.scale = Vector3.ONE
	var material := curtain.material_override as ShaderMaterial
	material.set_shader_parameter("clock", elapsed)
	material.set_shader_parameter("strength", minf(1.0, (WAVE_END_RADIUS - radius) / 0.8))
	var edge: MeshInstance3D = wave.edge
	var edge_radius: float = 1.6 + 0.45 * sin(elapsed * 10.0) if wave.phase == "warning" else radius
	edge.mesh = _clipped_wave_mesh(wave.limits, edge_radius, true)
	edge.scale = Vector3.ONE
	var edge_material: StandardMaterial3D = wave.edge_material
	edge_material.albedo_color = AMBER if wave.phase == "warning" else wave.color
	edge_material.emission = edge_material.albedo_color
	edge_material.emission_energy_multiplier = 1.3 + sin(elapsed * 11.0) * 0.4 if wave.phase == "warning" else 1.6


func _clipped_wave_mesh(limits: PackedFloat32Array, radius: float, flat: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for segment in range(WAVE_SEGMENTS):
		# Drop occluded arcs instead of drawing a ring through a protecting wall.
		if radius > minf(limits[segment], limits[segment + 1]):
			continue
		var start := vertices.size()
		for endpoint in [segment, segment + 1]:
			var angle := TAU * float(endpoint) / WAVE_SEGMENTS
			var direction := Vector3(cos(angle), 0, sin(angle))
			vertices.append(direction * (radius - 0.10 if flat else radius))
			vertices.append(direction * (radius + 0.10) if flat else direction * radius + Vector3.UP * 1.2)
			uv.append(Vector2(float(endpoint) / WAVE_SEGMENTS, 0))
			uv.append(Vector2(float(endpoint) / WAVE_SEGMENTS, 1))
		indices.append_array(PackedInt32Array([start, start + 2, start + 1, start + 1, start + 2, start + 3]))
	var result := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _pressure_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _pressure_shader
	material.set_shader_parameter("tint", color)
	return material


func _crystal_shape() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var next := TAU * float(index + 1) / 8.0
		var a := Vector3(cos(angle) * 0.265, 0.64, sin(angle) * 0.265)
		var b := Vector3(cos(next) * 0.265, 0.64, sin(next) * 0.265)
		var c := Vector3(cos(angle) * 0.275, 0.89, sin(angle) * 0.275)
		var d := Vector3(cos(next) * 0.275, 0.89, sin(next) * 0.275)
		_crystal_triangle(surface, Vector3(0, 1.64, 0), d, c)
		_crystal_triangle(surface, a, c, d)
		_crystal_triangle(surface, a, d, b)
		_crystal_triangle(surface, Vector3(0, 0.04, 0), a, b)
	return surface.commit()


func _crystal_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x + 0.5, point.y / 1.64))
		surface.add_vertex(point)


func _crystal_outline(parent: Node3D, material: Material) -> void:
	# All facet ribs for one crystal share a single small mesh. The silhouette
	# is larger and more sharply cut, while the physical receiver is untouched.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var next := TAU * float(index + 1) / 8.0
		var low := Vector3(cos(angle) * 0.265, 0.64, sin(angle) * 0.265)
		var high := Vector3(cos(angle) * 0.275, 0.89, sin(angle) * 0.275)
		var neighbor := Vector3(cos(next) * 0.275, 0.89, sin(next) * 0.275)
		for endpoints in [[high, Vector3(0, 1.64, 0)], [low, Vector3(0, 0.04, 0)], [low, high], [high, neighbor]]:
			_append_crystal_rib(surface, endpoints[0], endpoints[1])
	surface.generate_normals()
	var edge := _mesh(parent, Vector3.ZERO, surface.commit(), material)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _append_crystal_rib(surface: SurfaceTool, from: Vector3, to: Vector3) -> void:
	var basis := Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	for index in range(4):
		var a := TAU * float(index) / 4.0
		var b := TAU * float(index + 1) / 4.0
		var radial_a := basis * Vector3(cos(a) * 0.010, 0, sin(a) * 0.010)
		var radial_b := basis * Vector3(cos(b) * 0.010, 0, sin(b) * 0.010)
		for point in [from + radial_a, to + radial_a, to + radial_b, from + radial_a, to + radial_b, from + radial_b]:
			surface.add_vertex(point)


func _pressure_curtain() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 128
	for index in range(SEGMENTS + 1):
		var progress := float(index) / float(SEGMENTS)
		var direction := Vector3(cos(progress * TAU), 0, sin(progress * TAU))
		vertices.append(direction)
		vertices.append(direction + Vector3.UP * 0.85)
		uv.append(Vector2(progress, 0))
		uv.append(Vector2(progress, 1))
		if index < SEGMENTS:
			var start := index * 2
			indices.append_array(PackedInt32Array([start, start + 1, start + 3, start, start + 3, start + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _play_pressure_sound(event: String, at: Vector3) -> void:
	sound_requested.emit(event, at)
	var sounds := get_node_or_null("/root/GameSfx")
	if sounds != null and sounds.has_method("play_module_event"):
		sounds.call("play_module_event", event, at)
