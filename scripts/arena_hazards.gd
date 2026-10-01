extends Node3D

## Optional solo layer: visual fixtures preserve all arena collisions.
## Time advances only during a live, unpaused round.
signal sound_requested(event_id: String, at: Vector3)

const GRACE_SECONDS := 12.0
const WARNING_SECONDS := 1.6
const TILE_HALF_SIZE := 1.6
const TILE_DAMAGE := 65.0
const BOLT_DAMAGE := 35.0
const BOLT_SPEED := 14.0
const TILE_POSITIONS := [Vector3(-3.5, 0, -1), Vector3(3.5, 0, 3.5), Vector3(-13, 0, 2), Vector3(13, 0, 0)]
const CANNON_POSITIONS := [Vector3(-26.5, 0.85, -13), Vector3(26.5, 0.85, 13)]
const HazardVisuals = preload("res://scripts/arena_hazard_visuals.gd")

var enabled := false
var running := false
var elapsed := 0.0
var _next_event_at := GRACE_SECONDS
var _event_index := 0
var _serial := 0
var _round_serial := 0
var _actors: Array[Node3D] = []
var _fixtures: Array[Dictionary] = []


class HazardBolt extends CharacterBody3D:
	var direction := Vector3.RIGHT
	var speed := 14.0
	var damage := 35.0
	var attack_id := ""
	var age := 0.0

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1 | 2 | 4 | 8
		add_to_group("arena_hazard_bolts")
		add_to_group("prototype0_gameplay_projectiles")
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.18
		collision.shape = sphere
		add_child(collision)
		var visual := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		visual.mesh = mesh
		visual.scale = Vector3(0.6, 0.6, 1.9)
		visual.rotation.y = atan2(direction.x, direction.z)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#ffe0a0")
		material.emission_enabled = true
		material.emission = Color("#ff852e")
		material.emission_energy_multiplier = 0.6
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		visual.material_override = material
		add_child(visual)

	func _physics_process(delta: float) -> void:
		age += delta
		if age >= 4.2:
			queue_free()
			return
		var hit := move_and_collide(direction * speed * delta)
		if hit != null:
			var actor := hit.get_collider()
			if actor != null and actor.has_method("take_damage"):
				actor.call("take_damage", damage, "arena_hazard", attack_id)
			queue_free()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("arena_hazards")
	_build_fixtures()
	visible = enabled


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
	for fixture in _fixtures:
		fixture.phase = "idle"
		fixture.remaining = 0.0
		fixture.hit.clear()
		fixture.visual.reset_visual()
	_clear_bolts()


func start_round() -> void:
	running = enabled


func stop_round() -> void:
	running = false
	for fixture in _fixtures:
		fixture.phase = "idle"
		fixture.visual.reset_visual()
	_clear_bolts()


func _clear_bolts() -> void:
	for child in get_children():
		if child is HazardBolt:
			child.set_physics_process(false)
			child.queue_free()


func get_tier() -> int:
	return 1 if elapsed < 35.0 else (2 if elapsed < 65.0 else 3)


func get_interval() -> float:
	return [7.5, 5.0, 3.7][get_tier() - 1]


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not enabled or not running or get_tree().paused:
		return
	elapsed += delta
	for fixture in _fixtures:
		if fixture.phase == "idle":
			_update_visual(fixture, delta)
			continue
		fixture.remaining = maxf(0.0, float(fixture.remaining) - delta)
		if fixture.phase == "warning" and fixture.remaining <= 0.0:
			fixture.phase = "active"
			fixture.remaining = 0.65 if fixture.kind == "tile" else 0.9
			if fixture.kind == "cannon":
				fixture.shots = 0
				fixture.shot_clock = 0.0
			_request_sound("trap_tile_discharge" if fixture.kind == "tile" else "trap_cannon_salvo", fixture.position)
		elif fixture.phase == "active" and fixture.remaining <= 0.0:
			fixture.phase = "idle"
		_update_visual(fixture, delta)
		if fixture.phase == "active":
			if fixture.kind == "tile":
				_damage_tile(fixture)
			else:
				fixture.shot_clock = float(fixture.shot_clock) - delta
				if fixture.shot_clock <= 0.0 and int(fixture.shots) < int(fixture.salvo):
					_spawn_bolt(fixture)
					fixture.shots = int(fixture.shots) + 1
					fixture.shot_clock = 0.24
	if elapsed >= _next_event_at and _busy_count() == 0 and _bolt_count() == 0:
		# Late pairs occupy separate lanes and leave escape routes available.
		var sequence := [0, 4, 1, 2, 5, 3]
		var index: int = sequence[_event_index % sequence.size()]
		warn_fixture(index)
		if get_tier() == 3 and index >= 4:
			warn_fixture(2 if index == 4 else 3)
		_event_index += 1
		_next_event_at = elapsed + get_interval()


func warn_fixture(index: int) -> void:
	if not running or not enabled or index < 0 or index >= _fixtures.size():
		return
	var fixture: Dictionary = _fixtures[index]
	if fixture.phase != "idle":
		return
	_serial += 1
	fixture.serial = _serial
	fixture.phase = "warning"
	fixture.remaining = WARNING_SECONDS
	fixture.salvo = 3 if get_tier() == 3 else 2
	fixture.hit.clear()
	if fixture.kind == "cannon":
		fixture.length = _lane_length(fixture.position, fixture.direction)
	_update_visual(fixture)
	_request_sound("trap_tile_warning" if fixture.kind == "tile" else "trap_cannon_warning", fixture.position)


func _request_sound(event_id: String, at: Vector3) -> void:
	sound_requested.emit(event_id, at)
	# Selected events may be added by the separate audio pass.
	var sounds := get_node_or_null("/root/GameSfx")
	if sounds != null and (sounds.get("STREAMS") as Dictionary).has(event_id):
		sounds.call("play_event", event_id)


func _damage_tile(fixture: Dictionary) -> void:
	for actor in _actors:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		var offset := actor.global_position - (fixture.position as Vector3)
		if absf(offset.x) > TILE_HALF_SIZE + 0.35 or absf(offset.z) > TILE_HALF_SIZE + 0.35:
			continue
		var actor_id := actor.get_instance_id()
		if fixture.hit.has(actor_id):
			continue
		fixture.hit[actor_id] = true
		actor.call("take_damage", TILE_DAMAGE, "arena_hazard", "arena_hazard:%d:%d:tile" % [_round_serial, int(fixture.serial)])


func _spawn_bolt(fixture: Dictionary) -> void:
	var bolt := HazardBolt.new()
	bolt.direction = fixture.direction
	bolt.speed = BOLT_SPEED
	bolt.damage = BOLT_DAMAGE
	bolt.attack_id = "arena_hazard:%d:%d:bolt:%d" % [_round_serial, int(fixture.serial), int(fixture.shots)]
	add_child(bolt)
	bolt.global_position = fixture.visual.get_muzzle_world()
	fixture.visual.kick()
	_update_visual(fixture)


func _lane_length(origin: Vector3, direction: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 54.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return origin.distance_to(hit.position) if not hit.is_empty() else 54.0


func get_threats() -> Array[Dictionary]:
	var threats: Array[Dictionary] = []
	if not running or not enabled:
		return threats
	for fixture in _fixtures:
		if fixture.phase == "idle":
			continue
		threats.append({"id": int(fixture.serial), "kind": fixture.kind, "position": fixture.position,
			"direction": fixture.direction, "length": fixture.length, "half_width": 0.55,
			"remaining": fixture.remaining, "phase": fixture.phase})
	for child in get_children():
		if child is HazardBolt and not child.is_queued_for_deletion():
			threats.append({"id": int(child.get_instance_id()), "kind": "cannon", "position": child.global_position,
				"direction": child.direction, "length": minf(8.0, _lane_length(child.global_position, child.direction)), "half_width": 0.4,
				"remaining": 0.0, "phase": "active"})
	return threats


func threat_at(point: Vector3, margin: float = 0.65, known_threats: Array[Dictionary] = []) -> Dictionary:
	var threats := known_threats if not known_threats.is_empty() else get_threats()
	for threat in threats:
		var offset := point - (threat.position as Vector3)
		if threat.kind == "tile":
			if absf(offset.x) <= TILE_HALF_SIZE + margin and absf(offset.z) <= TILE_HALF_SIZE + margin:
				return threat
		else:
			var forward := offset.dot(threat.direction)
			var lateral := absf(offset.z)
			if forward >= -margin and forward <= float(threat.length) + margin and lateral <= float(threat.half_width) + margin:
				return threat
	return {}


func _busy_count() -> int:
	var count := 0
	for fixture in _fixtures:
		if fixture.phase != "idle":
			count += 1
	return count


func _bolt_count() -> int:
	var count := 0
	for child in get_children():
		if child is HazardBolt and not child.is_queued_for_deletion():
			count += 1
	return count


func get_snapshot() -> Dictionary:
	return {"enabled": enabled, "running": running, "elapsed": elapsed, "tier": get_tier(),
		"busy": _busy_count(), "bolts": _bolt_count(), "events": _event_index}


func _build_fixtures() -> void:
	for index in range(TILE_POSITIONS.size()):
		var visual := HazardVisuals.new()
		visual.name = "ElectricTile%d" % (index + 1)
		visual.position = TILE_POSITIONS[index]
		add_child(visual)
		visual.configure("tile", Vector3.ZERO)
		_fixtures.append(_fixture("tile", visual.position, Vector3.ZERO, visual))
	for index in range(CANNON_POSITIONS.size()):
		var visual := HazardVisuals.new()
		visual.name = "WallCannon%d" % (index + 1)
		visual.position = CANNON_POSITIONS[index]
		add_child(visual)
		var direction := Vector3.RIGHT if index == 0 else Vector3.LEFT
		visual.configure("cannon", direction)
		_fixtures.append(_fixture("cannon", visual.position, direction, visual))


func _fixture(kind: String, at: Vector3, direction: Vector3, visual: Node3D) -> Dictionary:
	return {"kind": kind, "position": at, "direction": direction, "length": 54.0, "visual": visual,
		"phase": "idle", "remaining": 0.0, "serial": 0, "salvo": 2, "shots": 0, "shot_clock": 0.0, "hit": {}}


func _update_visual(fixture: Dictionary, delta: float = 0.0) -> void:
	var progress := clampf(1.0 - float(fixture.remaining) / WARNING_SECONDS, 0.0, 1.0)
	fixture.visual.update_visual(fixture.phase, progress, delta, elapsed, float(fixture.length))
