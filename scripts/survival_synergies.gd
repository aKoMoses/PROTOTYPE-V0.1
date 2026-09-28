extends Node

const DEFINITIONS := {
	"thermal": {"name": "Détonation thermique", "items": ["blaster", "pyro_boots"]},
	"relay": {"name": "Relais électrique", "items": ["modulo_drone", "magnetic_field"]},
	"double": {"name": "Double détente", "items": ["shotgun", "bio_injector"]},
	"trail": {"name": "Sillage incandescent", "items": ["javelin", "pyro_boots"]},
}
var player: Node3D
var active: Array[String] = []
var evolved: Dictionary = {}
var armed := false
var zones: Array[Dictionary] = []
var marked: Dictionary = {}
var clock := 0.0
var next_trail := 0.0
var next_explosion := 0.0
var serial := 0
var generation := 0
var flights: Array[Dictionary] = []

static func active_for(build: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in DEFINITIONS:
		var pair: Array = DEFINITIONS[id].items
		if pair[0] in build.values() and pair[1] in build.values():
			result.append(id)
	return result

static func names(build: Dictionary) -> String:
	var result := PackedStringArray()
	for id in active_for(build):
		result.append(DEFINITIONS[id].name)
	return "  ·  ".join(result)

static func preview(build: Dictionary, choice: Dictionary) -> String:
	var next := build.duplicate(true)
	if choice.kind == "item":
		next[choice.category] = choice.id
	var current := active_for(build)
	for id in active_for(next):
		if not id in current:
			return "ACTIVE : " + str(DEFINITIONS[id].name)
	return ""

func configure(build: Dictionary) -> void:
	clear_effects()
	active = active_for(build)
	evolved = build.get("evolutions", {}).duplicate()

func clear_effects() -> void:
	generation += 1
	flights.clear()
	for zone in zones:
		if is_instance_valid(zone.visual):
			zone.visual.queue_free()
	zones.clear()
	marked.clear()
	armed = false
	next_trail = 0.0
	next_explosion = 0.0

func _physics_process(delta: float) -> void:
	if player == null or not player.is_gameplay_enabled():
		return
	clock += delta
	for index in range(flights.size() - 1, -1, -1):
		if not is_instance_valid(flights[index].drone):
			flights.remove_at(index)
		else:
			update_flight(flights[index])
	if float(player.get("_bio_remaining")) <= 0.0:
		armed = false
	for key in marked.keys():
		if float(marked[key]) <= clock:
			marked.erase(key)
	for index in range(zones.size() - 1, -1, -1):
		var zone := zones[index]
		if float(zone.until) <= clock:
			if is_instance_valid(zone.visual):
				zone.visual.queue_free()
			zones.remove_at(index)
			continue
		if float(zone.next) > clock:
			continue
		zone.next = clock + 0.4
		for enemy in player._survival_targets():
			if enemy.global_position.distance_to(zone.position) <= 1.45:
				var duration := 3.5 if bool(evolved.get("mobility", false)) else 2.0
				marked[enemy.get_instance_id()] = clock + duration
				enemy.apply_burn(duration, 26.0 if zone.source == "trail" and bool(evolved.get("offensive", false)) else 16.0, "player:" + str(zone.source))

func pyro_step(at: Vector3) -> void:
	if not "thermal" in active or clock < next_trail:
		return
	next_trail = clock + 0.12
	add_zone(at, "thermal")

func add_zone(at: Vector3, source: String) -> void:
	# Bounded persistent ground effects, independent of the general FX budget.
	if zones.size() >= 48:
		var oldest: Dictionary = zones.pop_front()
		if is_instance_valid(oldest.visual):
			oldest.visual.queue_free()
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.035
	visual.mesh = mesh
	visual.top_level = true
	visual.material_override = player._create_fx_material(Color("#ff752b"), 0.38)
	add_child(visual)
	visual.global_position = at + Vector3.UP * 0.06
	zones.append({"position": at, "until": clock + (3.5 if bool(evolved.get("mobility", false)) else 2.0), "next": clock, "source": source, "visual": visual})

func blaster_hit(target: Node3D, charge: float) -> void:
	if not "thermal" in active or charge < 0.7 or clock < next_explosion or not marked.has(target.get_instance_id()):
		return
	marked.erase(target.get_instance_id())
	next_explosion = clock + 0.35
	var radius := 4.0 if bool(evolved.get("weapon", false)) else 2.7
	player._survival_pulse_fx(target.global_position, radius, Color("#ff872f"))
	serial += 1
	for enemy in player._survival_targets():
		if enemy.global_position.distance_to(target.global_position) <= radius and player._solid_path_clear(target.global_position, enemy.global_position):
			enemy.take_damage(55.0, "player", "thermal:%d" % serial)
	cue("_blaster_charged_shot_audio", 0.7)

func arm_double() -> void:
	armed = "double" in active

func consume_double() -> bool:
	if not armed:
		return false
	armed = false
	return true

func teleport_trail(origin: Vector3, destination: Vector3) -> void:
	if not "trail" in active:
		return
	var steps := maxi(1, ceili(origin.distance_to(destination) / 1.1))
	for index in range(steps + 1):
		add_zone(origin.lerp(destination, float(index) / steps), "trail")
	cue("_shotgun_cycle_audio", 0.65)
	player._create_lightning_arc(origin + Vector3.UP * 0.2, destination + Vector3.UP * 0.2, Color("#ff873b"), 0.15, 0.35)

func drone_exclusions() -> Array[RID]:
	var result: Array[RID] = []
	var wall: Area3D = player.get("_magnetic_wall")
	if "relay" in active and is_instance_valid(wall):
		result.append(wall.get_rid())
	return result

func crosses_field(origin: Vector3, endpoint: Vector3) -> bool:
	var wall: Area3D = player.get("_magnetic_wall")
	if not "relay" in active or not is_instance_valid(wall):
		return false
	var shape_node := wall.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return false
	var a := shape_node.to_local(origin + Vector3.UP * 0.72)
	var b := shape_node.to_local(endpoint + Vector3.UP * 0.72)
	if a.z * b.z > 0.0 or absf(a.z - b.z) < 0.001:
		return false
	var crossing := a.lerp(b, a.z / (a.z - b.z))
	var size: Vector3 = shape_node.shape.size
	return absf(crossing.x) <= size.x * 0.5 and absf(crossing.y) <= size.y * 0.5

func drone_hit(primary: Node3D, damage: float) -> void:
	var remaining := 2 if bool(evolved.get("offensive", false)) else 1
	var radius := 6.0 if bool(evolved.get("defensive", false)) else 4.0
	serial += 1
	for enemy in player._survival_targets():
		if enemy == primary or enemy.global_position.distance_to(primary.global_position) > radius:
			continue
		if not player._solid_path_clear(primary.global_position, enemy.global_position):
			continue
		player._create_lightning_arc(primary.global_position + Vector3.UP, enemy.global_position + Vector3.UP, Color("#a3f8ff"), 0.1, 0.3)
		enemy.take_damage(damage * 0.45, "player", "relay:%d:%d" % [serial, enemy.get_instance_id()])
		remaining -= 1
		if remaining <= 0:
			break

func track_drone(drone: MeshInstance3D) -> Dictionary:
	var flight := {"drone": drone, "previous": drone.global_position, "charged": false}
	flights.append(flight)
	return flight

func update_flight(flight: Dictionary) -> void:
	if not is_instance_valid(flight.drone) or bool(flight.charged):
		return
	var drone: MeshInstance3D = flight.drone
	if crosses_field(flight.previous - Vector3.UP * 0.72, drone.global_position - Vector3.UP * 0.72):
		flight.charged = true
		drone.material_override = player._create_fx_material(Color("#e7ffff"), 1.0)
		player._survival_pulse_fx(drone.global_position, 0.65, Color("#a3f8ff"))
		cue("_blaster_ready_audio", 1.4)
	flight.previous = drone.global_position

func cue(source_name: String, pitch: float) -> void:
	var source: AudioStreamPlayer = player.get(source_name)
	if source == null or source.stream == null:
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = source.stream
	sound.pitch_scale = pitch
	sound.volume_db = source.volume_db - 8.0
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
