extends Node

const DEFINITIONS := {
	"thermal": {"name": "Détonation thermique", "items": ["blaster", "pyro_boots"], "description": "Les tirs chargés explosent les cibles brûlées."},
	"double": {"name": "Double détente", "items": ["shotgun", "bio_injector"], "description": "Bio Injector déclenche une seconde salve de Shotgun."},
	"trail": {"name": "Sillage incandescent", "items": ["javelin", "pyro_boots"], "description": "Le rappel ou la téléportation du Javelin laisse une traînée brûlante."},
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

static func available_for(build: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in DEFINITIONS:
		var pair: Array = DEFINITIONS[id].items
		if pair[0] in build.values() and pair[1] in build.values() and not id in build.get("synergies", []):
			result.append(id)
	return result

static func active_for(build: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in build.get("synergies", []):
		if DEFINITIONS.has(id):
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
	for id in available_for(next):
		if not id in available_for(build):
			return "SYNERGIE DÉBLOQUABLE : " + str(DEFINITIONS[id].name)
	return ""

func configure(build: Dictionary) -> void:
	clear_effects()
	active = active_for(build)
	evolved = build.get("evolutions", {}).duplicate()

func clear_effects() -> void:
	generation += 1
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
