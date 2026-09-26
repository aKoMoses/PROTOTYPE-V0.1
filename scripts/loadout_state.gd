class_name PrototypeLoadout
extends RefCounted

## Small, persistent build object used by the menu and by the duel bootstrap.
## The combat scripts remain the source of truth for numbers and behavior.

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const SAVE_PATH := "user://prototype0_loadout.cfg"

const WEAPONS := ["blaster", "shotgun"]
const OFFENSIVE := ["modulo_drone", "javelin"]
const DEFENSIVE := ["magnetic_field", "static_shield"]
const MOBILITY := ["pyro_boots", "bio_injector"]
const PASSIVES := ["baroud", "omnivamp"]

static func defaults() -> Dictionary:
	return {
		"weapon": "blaster",
		"offensive": "modulo_drone",
		"defensive": "magnetic_field",
		"mobility": "pyro_boots",
		"passive": "baroud",
	}

static func sanitize(value: Dictionary) -> Dictionary:
	var result := defaults()
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

static func load_local() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return defaults()
	var raw := {
		"weapon": config.get_value("loadout", "weapon", "blaster"),
		"offensive": config.get_value("loadout", "offensive", "modulo_drone"),
		"defensive": config.get_value("loadout", "defensive", "magnetic_field"),
		"mobility": config.get_value("loadout", "mobility", "pyro_boots"),
		"passive": config.get_value("loadout", "passive", "baroud"),
	}
	return sanitize(raw)

static func save_local(value: Dictionary) -> bool:
	var normalized := sanitize(value)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var config := ConfigFile.new()
	for key in normalized.keys():
		config.set_value("loadout", key, normalized[key])
	return config.save(SAVE_PATH) == OK

static func display_name(identifier: String) -> String:
	var names := {
		"blaster": "BLASTER",
		"shotgun": "SHOTGUN",
		"modulo_drone": "MODULO DRONE",
		"javelin": "JAVELIN",
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
		"blaster": "Tir précis ou tir chargé jusqu’à 50 dégâts.",
		"shotgun": "6 plombs coniques, 3 salves, recharge automatique.",
		"modulo_drone": "Projectile guidé : dégâts, BURN et SPOTTED.",
		"javelin": "Lance un javelot puis permet un recast de téléportation.",
		"magnetic_field": "Mur magnétique : absorbe les projectiles pendant 2,5 s.",
		"static_shield": "Stase 1,5 s : invulnérable, mais toutes actions bloquées.",
		"pyro_boots": "Dash de 3 m, arrêt aux obstacles, recharge 6 s.",
		"bio_injector": "Buff 3 s : déplacement et attaques accélérés.",
		"baroud": "Premier coup létal : jauge de survie temporaire.",
		"omnivamp": "Récupère 15 % des dégâts effectivement infligés.",
	}
	return str(descriptions.get(identifier, "Équipement Prototype 0."))

static func stat_line(identifier: String) -> String:
	var weapon: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS.get(identifier, {})
	var module: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get(identifier, {})
	if not weapon.is_empty():
		if identifier == "blaster":
			return "20–50 dégâts   •   PORTÉE 14 m   •   CHARGE 1 s"
		return "6×20 dégâts • 3 salves"
	if not module.is_empty():
		if module.has("cooldown"):
			return "CD %.1f s" % float(module.cooldown)
		return "PASSIF EXCLUSIF"
	return ""
