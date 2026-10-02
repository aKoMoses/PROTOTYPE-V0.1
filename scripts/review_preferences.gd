extends RefCounted

const PATH := "user://prototype0_experience.cfg"
const BADGES := {"recrue": "RECRUE", "duelliste": "DUELLISTE", "technicien": "TECHNICIEN", "survivant": "SURVIVANT", "arsenal": "MAÎTRE D’ARSENAL"}
const PRESETS := {
	"PRISE EN MAIN": {"robot": "polyvalent", "weapon": "blaster", "offensive": "rocket_basket", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "omnivamp"},
	"ASSAUT": {"robot": "agile", "weapon": "shotgun", "offensive": "fulguro_punch", "defensive": "projector", "mobility": "pyro_boots", "passive": "alternator"},
	"TECHNIQUE": {"robot": "polyvalent", "weapon": "longshot", "offensive": "javelin", "defensive": "counter", "mobility": "permutation", "passive": "tracker"},
}

static func read(path: String = PATH) -> Dictionary:
	var config := ConfigFile.new()
	config.load(path)
	var difficulty := str(config.get_value("experience", "difficulty", "normal"))
	var unlocked: Array = ["recrue"]
	var stored: Variant = config.get_value("mastery", "unlocked", [])
	if stored is Array:
		for id in stored:
			if BADGES.has(str(id)) and not str(id) in unlocked:
				unlocked.append(str(id))
	var badge := str(config.get_value("experience", "badge", "recrue"))
	return {"difficulty": difficulty if difficulty in ["easy", "normal", "hard"] else "normal", "quick": bool(config.get_value("experience", "quick", false)), "feedback": bool(config.get_value("experience", "feedback", true)), "badge": badge if badge in unlocked else "recrue", "unlocked": unlocked, "weapons": _known_list(config.get_value("mastery", "weapons", []), ["blaster", "shotgun", "longshot", "mekatana"]), "challenges": _known_list(config.get_value("mastery", "challenges", []), ["counter", "javelin", "fulguro_punch"])}

static func _known_list(stored: Variant, allowed: Array) -> Array[String]:
	var result: Array[String] = []
	if stored is Array:
		for id in stored:
			if str(id) in allowed and not str(id) in result:
				result.append(str(id))
	return result

static func write(values: Dictionary, path: String = PATH) -> Error:
	var config := ConfigFile.new()
	for key in ["difficulty", "quick", "feedback", "badge"]:
		config.set_value("experience", key, values[key])
	for key in ["unlocked", "weapons", "challenges"]:
		config.set_value("mastery", key, values[key])
	return config.save(path)

static func unlock(kind: String, id: String = "", path: String = PATH) -> Array[String]:
	var values := read(path)
	var candidates: Array[String] = []
	if kind == "duel":
		candidates.append("duelliste")
	elif kind == "survival":
		candidates.append("survivant")
		if not values.weapons is Array:
			values.weapons = []
		if id in ["blaster", "shotgun", "longshot", "mekatana"] and not id in values.weapons:
			values.weapons.append(id)
		if values.weapons.size() == 4:
			candidates.append("arsenal")
	elif kind == "challenge":
		if not values.challenges is Array:
			values.challenges = []
		if id in ["counter", "javelin", "fulguro_punch"] and not id in values.challenges:
			values.challenges.append(id)
		if values.challenges.size() == 3:
			candidates.append("technicien")
	var added: Array[String] = []
	for candidate in candidates:
		if not candidate in values.unlocked:
			values.unlocked.append(candidate)
			added.append(candidate)
	if write(values, path) != OK:
		return []
	return added
