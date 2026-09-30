extends RefCounted

const LOADOUT := preload("res://scripts/loadout_state.gd")
const BUILDS := [
	{"title": "HARCELEUR", "robot": "agile", "weapon": "blaster", "offensive": "modulo_drone", "defensive": "magnetic_field", "mobility": "bio_injector", "passive": "omnivamp"},
	{"title": "ASSAILLANT", "robot": "polyvalent", "weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "baroud"},
	{"title": "BRISEUR", "robot": "puissant", "weapon": "shotgun", "offensive": "fulguro_punch", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"},
	{"title": "GARDIEN", "robot": "puissant", "weapon": "blaster", "offensive": "pelto_smash", "defensive": "static_shield", "mobility": "bio_injector", "passive": "baroud"},
]

static func choose(previous_title: String = "") -> Dictionary:
	var available: Array = []
	for build in BUILDS:
		if build.title != previous_title:
			available.append(build)
	return available.pick_random().duplicate(true)

static func describe(build: Dictionary) -> String:
	var parts: PackedStringArray = []
	for category in ["robot", "weapon", "offensive", "defensive", "mobility", "passive"]:
		parts.append(LOADOUT.display_name(str(build.get(category, ""))))
	return " · ".join(parts)
