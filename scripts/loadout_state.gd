class_name PrototypeLoadout
extends RefCounted

## Small, persistent build object used by the menu and by the duel bootstrap.
## The combat scripts remain the source of truth for numbers and behavior.

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const SAVE_PATH := "user://prototype0_loadout.cfg"

const ROBOTS := ["agile", "polyvalent", "puissant"]
const WEAPONS := ["blaster", "shotgun"]
const OFFENSIVE := ["modulo_drone", "javelin", "fulguro_punch", "pelto_smash"]
const DEFENSIVE := ["magnetic_field", "static_shield"]
const MOBILITY := ["pyro_boots", "bio_injector"]
const PASSIVES := ["baroud", "omnivamp"]

static func defaults() -> Dictionary:
	return {
		"robot": COMBAT_DATA.DEFAULT_ROBOT,
		"weapon": "blaster",
		"offensive": "modulo_drone",
		"defensive": "magnetic_field",
		"mobility": "pyro_boots",
		"passive": "baroud",
	}

static func sanitize(value: Dictionary) -> Dictionary:
	var result := defaults()
	if value.has("robot") and ROBOTS.has(str(value.robot)):
		result.robot = str(value.robot)
	if value.has("weapon") and WEAPONS.has(str(value.weapon)):
		result.weapon = str(value.weapon)
	if value.has("offensive") and OFFENSIVE.has(str(value.offensive)):
		result.offensive = str(value.offensive)
	if value.has("defensive") and DEFENSIVE.has(str(value.defensive)):
		result.defensive = str(value.defensive)
	if value.has("mobility") and MOBILITY.has(str(value.mobility)):
		result.mobility = str(value.mobility)
	if value.has("passive") and PASSIVES.has(str(value.passive)):
		result.passive = str(value.passive)
	return result

static func is_valid(value: Dictionary) -> bool:
	var normalized := sanitize(value)
	for key in defaults().keys():
		if str(value.get(key, "")) != str(normalized[key]):
			return false
	return true

static func load_local(path: String = SAVE_PATH) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return defaults()
	var raw := {
		"robot": config.get_value("loadout", "robot", COMBAT_DATA.DEFAULT_ROBOT),
		"weapon": config.get_value("loadout", "weapon", "blaster"),
		"offensive": config.get_value("loadout", "offensive", "modulo_drone"),
		"defensive": config.get_value("loadout", "defensive", "magnetic_field"),
		"mobility": config.get_value("loadout", "mobility", "pyro_boots"),
		"passive": config.get_value("loadout", "passive", "baroud"),
	}
	return sanitize(raw)

static func save_local(value: Dictionary, path: String = SAVE_PATH) -> bool:
	var normalized := sanitize(value)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var config := ConfigFile.new()
	for key in normalized.keys():
		config.set_value("loadout", key, normalized[key])
	return config.save(path) == OK

static func display_name(identifier: String) -> String:
	var names := {
		"agile": "AGILE",
		"polyvalent": "POLYVALENT",
		"puissant": "PUISSANT",
		"blaster": "BLASTER",
		"shotgun": "SHOTGUN",
		"modulo_drone": "MODULO DRONE",
		"javelin": "JAVELIN",
		"fulguro_punch": "FULGURO PUNCH",
		"pelto_smash": "PELTO SMASH",
		"magnetic_field": "MAGNETIC FIELD",
		"static_shield": "STATIC SHIELD",
		"pyro_boots": "PYRO BOOTS",
		"bio_injector": "BIO INJECTOR",
		"baroud": "BAROUD D’HONNEUR",
		"omnivamp": "OMNIVAMP",
	}
	return str(names.get(identifier, identifier.capitalize()))

static func category_description(identifier: String) -> String:
	var descriptions := {
		"agile": "Déplacements rapides, châssis léger et moins de PV.",
		"polyvalent": "Un équilibre entre mobilité et résistance.",
		"puissant": "Châssis renforcé : plus de PV, déplacement plus lent.",
		"blaster": "Tir précis ou tir chargé jusqu’à 50 dégâts.",
		"shotgun": "6 plombs coniques, 3 salves, recharge automatique.",
		"modulo_drone": "Projectile guidé : dégâts, BURN et SPOTTED.",
		"javelin": "Lance un javelot puis permet un recast de téléportation.",
		"fulguro_punch": "Poing incandescent : maintenir pour amplifier portée et dégâts, puis relâcher.",
		"pelto_smash": "Frappe le sol : vague de terre à l’aller, puis retour tractant.",
		"magnetic_field": "Mur magnétique : absorbe les projectiles pendant 2,5 s.",
		"static_shield": "Stase 1,5 s : invulnérable, mais toutes actions bloquées.",
		"pyro_boots": "Dash de 3 m, arrêt aux obstacles, recharge 6 s.",
		"bio_injector": "Buff 3 s : déplacement et attaques accélérés.",
		"baroud": "Premier coup létal : jauge de survie temporaire.",
		"omnivamp": "Récupère 15 % des dégâts effectivement infligés.",
	}
	return str(descriptions.get(identifier, "Équipement Prototype 0."))

static func stat_line(identifier: String) -> String:
	if COMBAT_DATA.ROBOT_DEFINITIONS.has(identifier):
		var robot: Dictionary = COMBAT_DATA.ROBOT_DEFINITIONS[identifier]
		return "%d PV • vitesse %.1f m/s" % [int(robot.max_health), float(robot.move_speed)]
	var weapon: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS.get(identifier, {})
	var module: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get(identifier, {})
	if not weapon.is_empty():
		if identifier == "blaster":
			return "%d–%d dégâts • portée %.0f m • charge %.1f s • CD %.2f s" % [int(weapon.get("damage", 0.0)), int(weapon.get("max_damage", weapon.get("damage", 0.0))), float(weapon.get("max_range", 0.0)), float(weapon.get("charge_time", 0.0)), float(weapon.get("cooldown", 0.0))]
		return "%d×%d dégâts • %d salves • portée %.0f m" % [int(weapon.get("pellets_per_shot", 0)), int(weapon.get("pellet_damage", 0.0)), int(weapon.get("magazine_size", 0)), float(weapon.get("max_range", 0.0))]
	if not module.is_empty():
		if identifier == "fulguro_punch":
			return "%d–%d dégâts • +%d–%d mur • %.1f–%.1f m • charge %.2f–%.1f s" % [int(module.damage_min), int(module.damage_max), int(module.wall_damage_min), int(module.wall_damage_max), float(module.range_min), float(module.range_max), float(module.charge_min), float(module.charge_max)]
		if identifier == "pelto_smash":
			return "%d + %d dégâts • %.1f m × %.1f m • slow %d%% • traction %.1f m" % [int(module.outbound_damage), int(module.return_damage), float(module.max_range), float(module.width), int(module.outbound_slow_percent), float(module.pull_distance)]
		if module.has("cooldown"):
			return "CD %.1f s" % float(module.cooldown)
		return "PASSIF EXCLUSIF"
	return ""
