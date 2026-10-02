extends RefCounted

## Shared authoring contract for the small duel arenas.
const IDS := ["heliostat", "tideglass", "clockwork", "gyre", "resonance"]
const DEFINITIONS := {
	"heliostat": {
		"id": "heliostat", "title": "HÉLIOSTAT", "subtitle": "Le soleil en cage",
		"description": "22 × 18 m · miroirs solaires, téléporteurs et couloirs de surchauffe.",
		"half_size": Vector2(11, 9), "color": Color("#f1b653"),
		"floor": Color("#c9b995"), "metal": Color("#775535"), "accent": Color("#55d7d1"),
		"spawns": [Vector3(-7, 0, 5), Vector3(7, 0, -5)],
		"portals": [Vector3(-8, 0, -5.5), Vector3(8, 0, 5.5)],
		"repairs": [Vector3(0, 0, -7), Vector3(0, 0, 7)],
		"covers": [
			{"position": Vector3(-4, 0.95, -1), "size": Vector3(2.5, 1.9, 1.3), "yaw": -24.0},
			{"position": Vector3(4, 0.95, 1), "size": Vector3(2.5, 1.9, 1.3), "yaw": -24.0},
			{"position": Vector3(0, 0.85, -4), "size": Vector3(3, 1.7, 1.2), "yaw": 0.0},
			{"position": Vector3(0, 0.85, 4), "size": Vector3(3, 1.7, 1.2), "yaw": 0.0}],
		"hazards": [
			{"position": Vector3(-1.8, 0, 0), "size": Vector2(1.6, 13), "kind": "solar", "damage": 70.0},
			{"position": Vector3(1.8, 0, 0), "size": Vector2(1.6, 13), "kind": "solar", "damage": 70.0}],
		"boosts": [Vector3(-7, 0, 0), Vector3(7, 0, 0)],
		"period": 8.0, "warning": 1.8, "active": 0.7,
	},
	"tideglass": {
		"id": "tideglass", "title": "SERRE DES MARÉES", "subtitle": "Le jardin submergé",
		"description": "20 × 20 m · canaux de marée, verrières, téléporteurs et courants.",
		"half_size": Vector2(10, 10), "color": Color("#53d3c1"),
		"floor": Color("#91aaa3"), "metal": Color("#376965"), "accent": Color("#91e1b1"),
		"spawns": [Vector3(-6.5, 0, 6), Vector3(6.5, 0, -6)],
		"portals": [Vector3(-7, 0, -6), Vector3(7, 0, 6)],
		"repairs": [Vector3(0, 0, -8), Vector3(0, 0, 8)],
		"covers": [
			{"position": Vector3(-4, 0.9, -3), "size": Vector3(2.8, 1.8, 1.5), "yaw": 0.0},
			{"position": Vector3(4, 0.9, 3), "size": Vector3(2.8, 1.8, 1.5), "yaw": 0.0},
			{"position": Vector3(-4, 0.9, 3), "size": Vector3(1.5, 1.8, 2.8), "yaw": 0.0},
			{"position": Vector3(4, 0.9, -3), "size": Vector3(1.5, 1.8, 2.8), "yaw": 0.0}],
		"hazards": [
			{"position": Vector3(0, 0, -1.3), "size": Vector2(16, 1.6), "kind": "tide", "damage": 55.0},
			{"position": Vector3(0, 0, 1.3), "size": Vector2(16, 1.6), "kind": "tide", "damage": 55.0}],
		"boosts": [Vector3(-7, 0, 0), Vector3(7, 0, 0)],
		"period": 7.5, "warning": 2.0, "active": 0.85,
	},
	"clockwork": {
		"id": "clockwork", "title": "CŒUR D’HORLOGE", "subtitle": "La treizième heure",
		"description": "18 × 18 m · rouages, cadran électrique, portes rythmiques et téléporteurs.",
		"half_size": Vector2(9, 9), "color": Color("#bda4ef"),
		"floor": Color("#58556f"), "metal": Color("#a57b45"), "accent": Color("#bca4ef"),
		"spawns": [Vector3(-6, 0, 5.5), Vector3(6, 0, -5.5)],
		"portals": [Vector3(-6, 0, -5.5), Vector3(6, 0, 5.5)],
		"repairs": [Vector3(0, 0, -7), Vector3(0, 0, 7)],
		"covers": [
			{"position": Vector3(-3.3, 0.95, 0), "size": Vector3(1.4, 1.9, 3), "yaw": 0.0},
			{"position": Vector3(3.3, 0.95, 0), "size": Vector3(1.4, 1.9, 3), "yaw": 0.0},
			{"position": Vector3(0, 0.8, -3.6), "size": Vector3(2.2, 1.6, 1.2), "yaw": 0.0},
			{"position": Vector3(0, 0.8, 3.6), "size": Vector3(2.2, 1.6, 1.2), "yaw": 0.0}],
		"hazards": [
			{"position": Vector3(0, 0, 0), "size": Vector2(3.7, 3.7), "kind": "clock", "damage": 65.0},
			{"position": Vector3(0, 0, 0), "size": Vector2(12, 1.2), "kind": "clock", "damage": 65.0}],
		"boosts": [Vector3(-6.5, 0, 0), Vector3(6.5, 0, 0)],
		"period": 7.0, "warning": 1.8, "active": 0.7,
	},
	"gyre": {
		"id": "gyre", "title": "FORGE SIDÉRALE", "subtitle": "Le métal en orbite",
		"description": "20 × 18 m · deux plateaux tournants à contre-sens et inversions progressives.",
		"half_size": Vector2(10, 9), "corner_cut": 3.0, "mechanism": "open",
		"color": Color("#ff8955"), "floor": Color("#454b50"), "metal": Color("#525f67"), "accent": Color("#ff965f"),
		"spawns": [Vector3(-5.7, 0, 4.6), Vector3(5.7, 0, -4.6)],
		"portals": [], "repairs": [], "covers": [], "hazards": [], "boosts": [],
		"period": 18.0, "warning": 1.2, "active": 4.0,
	},
	"resonance": {
		"id": "resonance", "title": "PAVILLON DES ÉCHOS", "subtitle": "Les pierres qui répondent",
		"description": "20 × 16 m · cristaux réactifs aux tirs, ondes de pression et résonances en chaîne.",
		"half_size": Vector2(10, 8), "corner_cut": 3.0, "mechanism": "open",
		"color": Color("#e8a7d9"), "floor": Color("#acb1b7"), "metal": Color("#676985"), "accent": Color("#f0afe4"),
		"spawns": [Vector3(-6, 0, 4.5), Vector3(6, 0, -4.5)],
		"resonators": [Vector3(-5, 0, -3.5), Vector3(5, 0, 3.5), Vector3(-5, 0, 3.5), Vector3(5, 0, -3.5)],
		"portals": [], "repairs": [], "covers": [], "hazards": [], "boosts": [],
		"period": 8.5, "warning": 1.4, "active": 4.0,
	},
}

static func is_compact(identifier: String) -> bool:
	return DEFINITIONS.has(identifier)

static func sanitize(identifier: String) -> String:
	return identifier if identifier in ["classic", "hazards", "test"] or is_compact(identifier) else "classic"

static func definition(identifier: String) -> Dictionary:
	return (DEFINITIONS.get(identifier, {}) as Dictionary).duplicate(true)

static func footprint(identifier: String) -> PackedVector2Array:
	var entry := definition(identifier)
	if entry.is_empty():
		return PackedVector2Array()
	var half: Vector2 = entry.half_size
	var cut: float = entry.get("corner_cut", 0.0)
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
