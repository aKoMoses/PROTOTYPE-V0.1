extends RefCounted

## Shared authoring contract for the small duel arenas.
const IDS := ["heliostat", "tideglass", "clockwork", "gyre", "resonance"]
const LAYOUT_SCALE := 1.25
const DEFINITIONS := {
	"heliostat": {
		"id": "heliostat", "title": "HÉLIOSTAT", "subtitle": "Le soleil en cage",
		"description": "22 × 18 m · soleil mobile, ombres protectrices et miroirs à orienter par un impact.",
		"half_size": Vector2(11, 9), "color": Color("#f1b653"),
		"floor": Color("#c9b995"), "metal": Color("#775535"), "accent": Color("#55d7d1"),
		"spawns": [Vector3(-7, 0, 5), Vector3(7, 0, -5)],
		"portals": [], "repairs": [],
		"mirrors": [Vector3(-7.5, 0, -5), Vector3(7.5, 0, 5)],
		"covers": [
			{"position": Vector3(-3.8, 1, -2.5), "size": Vector3(0.9, 2, 4.2), "yaw": -18.0},
			{"position": Vector3(3.8, 1, 1.7), "size": Vector3(0.9, 2, 4.2), "yaw": 18.0},
			{"position": Vector3(-1.4, 1, 5.4), "size": Vector3(3.0, 2, 0.9), "yaw": 0.0}],
		"hazards": [], "boosts": [],
		"period": 8.0, "warning": 1.8, "active": 0.7,
	},
	"tideglass": {
		"id": "tideglass", "title": "SERRE ENGLOUTIE", "subtitle": "Le jardin submergé",
		"description": "20 × 20 m · trois îlots et soins dans le bassin. Dans l'eau : déplacement, sans attaque.",
		"half_size": Vector2(10, 10), "corner_cut": 3.0, "color": Color("#53d3c1"),
		"floor": Color("#91aaa3"), "metal": Color("#376965"), "accent": Color("#91e1b1"),
		"spawns": [Vector3(-5.8, 1.35, -6), Vector3(5.8, 1.35, -6)],
		"portals": [], "boosts": [], "covers": [], "hazards": [],
		"repairs": [Vector3(-6.5, 0, 5.4), Vector3(6.5, 0, 5.4)],
		"period": 24.0, "warning": 3.0, "active": 8.0,
	},
	"clockwork": {
		"id": "clockwork", "title": "CŒUR D’HORLOGE", "subtitle": "La treizième heure",
		"description": "18 × 18 m · balancier annoncé sans dégâts et abris pivotants entre les balayages.",
		"half_size": Vector2(9, 9), "corner_cut": 4.0, "color": Color("#bda4ef"),
		"floor": Color("#58556f"), "metal": Color("#a57b45"), "accent": Color("#bca4ef"),
		"spawns": [Vector3(-6, 0, 5.5), Vector3(6, 0, -5.5)],
		"portals": [],
		"repairs": [Vector3(0, 0, -7), Vector3(0, 0, 7)],
		"covers": [], "hazards": [], "boosts": [],
		"period": 7.0, "warning": 1.8, "active": 0.7,
	},
	"gyre": {
		"id": "gyre", "title": "FORGE SIDÉRALE", "subtitle": "Le métal en orbite",
		"description": "20 × 18 m · plateforme surélevée, deux rampes, couverts et anneaux tournants.",
		"half_size": Vector2(10, 9), "corner_cut": 3.0, "mechanism": "open",
		"color": Color("#ff8955"), "floor": Color("#454b50"), "metal": Color("#525f67"), "accent": Color("#ff965f"),
		"spawns": [Vector3(-5.7, 0, 4.6), Vector3(5.7, 0, -4.6)],
		"portals": [], "repairs": [], "covers": [], "hazards": [], "boosts": [],
		"period": 18.0, "warning": 1.2, "active": 4.0,
	},
	"resonance": {
		"id": "resonance", "title": "PAVILLON DES ÉCHOS", "subtitle": "Les pierres qui répondent",
		"description": "20 × 16 m · murs refuges, cristaux à forte poussée et résonances en chaîne.",
		"half_size": Vector2(10, 8), "corner_cut": 3.0, "mechanism": "open",
		"color": Color("#e8a7d9"), "floor": Color("#acb1b7"), "metal": Color("#676985"), "accent": Color("#f0afe4"),
		"spawns": [Vector3(-6, 0, 4.5), Vector3(6, 0, -4.5)],
		"resonators": [Vector3(-5, 0, -3.5), Vector3(5, 0, 3.5), Vector3(-5, 0, 3.5), Vector3(5, 0, -3.5)],
		"portals": [], "repairs": [], "covers": [], "hazards": [], "boosts": [],
		"period": 22.0, "warning": 1.4, "active": 4.0,
	},
}

static func is_compact(identifier: String) -> bool:
	return DEFINITIONS.has(identifier)

static func sanitize(identifier: String) -> String:
	return identifier if identifier in ["classic", "hazards", "test"] or is_compact(identifier) else "classic"

static func definition(identifier: String) -> Dictionary:
	var entry := (DEFINITIONS.get(identifier, {}) as Dictionary).duplicate(true)
	if entry.is_empty():
		return entry
	if identifier in ["gyre", "resonance"]:
		entry.covers = [{"position": Vector3(0, 1, -6 if identifier == "gyre" else 0), "size": Vector3(4.2, 2, 0.7), "yaw": 0.0}]
	if identifier == "gyre":
		entry.covers = [
			{"position": Vector3(-5.8, 0.85, -1.8), "size": Vector3(0.8, 1.7, 2.8), "yaw": 0.0},
			{"position": Vector3(5.8, 0.85, 1.8), "size": Vector3(0.8, 1.7, 2.8), "yaw": 0.0}]
	if identifier == "resonance":
		entry.covers = [
			{"position": Vector3(-2.8, 1, -1.6), "size": Vector3(3.4, 2, 0.9), "yaw": -30.0},
			{"position": Vector3(2.8, 1, -1.6), "size": Vector3(3.4, 2, 0.9), "yaw": 30.0},
			{"position": Vector3(0, 1, 3.2), "size": Vector3(3.4, 2, 0.9), "yaw": 0.0}]
	entry.half_size *= LAYOUT_SCALE
	if entry.has("corner_cut"):
		entry.corner_cut *= LAYOUT_SCALE
	for key in ["spawns", "portals", "repairs", "boosts", "resonators", "mirrors"]:
		for index in (entry.get(key, []) as Array).size():
			entry[key][index] *= Vector3(LAYOUT_SCALE, 1, LAYOUT_SCALE)
	for cover in entry.covers:
		cover.position *= Vector3(LAYOUT_SCALE, 1, LAYOUT_SCALE)
		cover.size *= Vector3(LAYOUT_SCALE, 1, LAYOUT_SCALE)
	for hazard in entry.hazards:
		hazard.position *= Vector3(LAYOUT_SCALE, 1, LAYOUT_SCALE)
		hazard.size *= LAYOUT_SCALE
	var dimensions := "%s × %s m" % [entry.half_size.x * 2, entry.half_size.y * 2]
	entry.description = dimensions + str(entry.description).substr(str(entry.description).find(" ·"))
	return entry

static func footprint(identifier: String) -> PackedVector2Array:
	var entry := definition(identifier)
	if entry.is_empty():
		return PackedVector2Array()
	var half: Vector2 = entry.half_size
	var cut: float = entry.get("corner_cut", 0.0)
	if entry.get("shape", "") == "hexagon":
		return PackedVector2Array([Vector2(-half.x, 0), Vector2(-half.x + cut, -half.y), Vector2(half.x - cut, -half.y), Vector2(half.x, 0), Vector2(half.x - cut, half.y), Vector2(-half.x + cut, half.y)])
	if cut <= 0.0:
		return PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	return PackedVector2Array([Vector2(-half.x + cut, -half.y), Vector2(half.x - cut, -half.y), Vector2(half.x, -half.y + cut), Vector2(half.x, half.y - cut), Vector2(half.x - cut, half.y), Vector2(-half.x + cut, half.y), Vector2(-half.x, half.y - cut), Vector2(-half.x, -half.y + cut)])

static func options() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id": "classic", "title": "CLASSIQUE", "description": "Cour de récupération · sans pièges."},
		{"id": "hazards", "title": "PIÉGÉE", "description": "Cour de récupération · dalles et canons progressifs."},
		{"id": "test", "title": "MAP TEST", "description": "Plateformes à 2,4 m · quatre rampes et passerelle centrale."}]
	for identifier in IDS:
		result.append(definition(identifier))
	return result
