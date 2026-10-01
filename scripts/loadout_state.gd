class_name PrototypeLoadout
extends RefCounted

## Small, persistent build object used by the menu and by the duel bootstrap.
## The combat scripts remain the source of truth for numbers and behavior.

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const SAVE_PATH := "user://prototype0_loadout.cfg"

const ROBOTS := ["agile", "polyvalent", "puissant"]
const WEAPONS := ["blaster", "shotgun", "mekatana", "longshot"]
const OFFENSIVE := ["rocket_basket", "javelin", "fulguro_punch", "pelto_smash"]
const DEFENSIVE := ["magnetic_field", "static_shield", "projector", "counter"]
const MOBILITY := ["pyro_boots", "bio_injector", "permutation", "eclipse"]
const PASSIVES := ["baroud", "omnivamp", "auxiliary_reactor", "tracker", "alternator", "inertia"]

static func defaults() -> Dictionary:
	return {
		"robot": COMBAT_DATA.DEFAULT_ROBOT,
		"weapon": "blaster",
		"offensive": "javelin",
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
		"offensive": config.get_value("loadout", "offensive", "javelin"),
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
		"rocket_basket": "PANIER ROQUETTES",
		"agile": "AGILE",
		"polyvalent": "POLYVALENT",
		"puissant": "PUISSANT",
		"blaster": "BLASTER",
		"shotgun": "SHOTGUN",
		"longshot": "LONGSHOT",
		"mekatana": "MEKATANA",
		"javelin": "JAVELIN",
		"fulguro_punch": "FULGURO PUNCH",
		"pelto_smash": "PELTO SMASH",
		"magnetic_field": "MAGNETIC FIELD",
		"static_shield": "STATIC SHIELD",
		"projector": "PROJECTOR",
		"counter": "COUNTER",
		"pyro_boots": "PYRO BOOTS",
		"bio_injector": "BIO INJECTOR",
		"permutation": "PERMUTATION",
		"eclipse": "ÉCLIPSE",
		"baroud": "BAROUD D’HONNEUR",
		"omnivamp": "OMNIVAMP",
		"auxiliary_reactor": "RÉACTEUR AUXILIAIRE",
		"tracker": "TRAQUEUR",
		"alternator": "ALTERNATEUR",
		"inertia": "INERTIE",
	}
	return str(names.get(identifier, identifier.capitalize()))

static func category_description(identifier: String) -> String:
	var data: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get(identifier, {})
	match identifier:
		"auxiliary_reactor":
			return "Impact direct d’arme : −%.2f s au cooldown offensif actif, une fois par attaque et toutes les %.2f s. Aucun crédit accumulé." % [float(data.reduction), float(data.interval)]
		"tracker":
			return "%d attaques d’arme distinctes sur la même cible, espacées de %.0f s maximum : SPOTTED %.0f s. Aucun cumul pendant cette révélation." % [int(data.hits), float(data.gap), float(data.duration)]
		"alternator":
			return "Impact direct offensif : prochaine attaque d’arme +%d %% de dégâts directs, à exécuter sous %.0f s. Une fois par activation, consommé même si elle rate." % [roundi(float(data.damage_bonus) * 100.0), float(data.duration)]
		"inertia":
			return "Fin de dash réussi : prochaine attaque d’arme sous %.1f s applique SLOW %d %% pendant %.0f s. Consommé même si elle rate." % [float(data.window), int(data.slow_percent), float(data.slow_duration)]
	var descriptions := {
		"rocket_basket": "5 roquettes autoguidées destructibles, 40 PV chacune. Cast 0,3 s, vitesse −15 %. Chaque impact : SLOW +5 % pendant 3 s. Les 5 sur une cible : BURN et cooldown −40 %. Détruites contre les murs ; recherche continue. Nom provisoire.",
		"agile": "Déplacements rapides, châssis léger et moins de PV.",
		"polyvalent": "Un équilibre entre mobilité et résistance.",
		"puissant": "Châssis renforcé : plus de PV, déplacement plus lent.",
		"blaster": "Tir précis ou tir chargé jusqu’à 50 dégâts.",
		"shotgun": "6 plombs coniques, 3 salves, recharge automatique.",
		"longshot": "Fusil précis : dégâts croissants avec la distance. Chaque cinquième tir est amélioré.",
		"mekatana": "Katana électrique : trois cleaves avec dash croissant. Enchaîner sous 2,5 s ; les touches précédentes renforcent les dégâts sur la même cible.",
		"javelin": "Maintiens pour charger un trident électrique (max 1,74 s). La cible touchée est marquée et SPOTTED ; réappuie pour te téléporter devant elle.",
		"fulguro_punch": "Poing incandescent : maintenir pour amplifier portée et dégâts, puis relâcher.",
		"pelto_smash": "Frappe le sol : vague de terre à l’aller, puis retour tractant.",
		"magnetic_field": "Wall : bloque les adversaires et leurs tirs pendant 2,5 s. Tes tirs traversent.",
		"counter": "Garde à 360° après 0,08 s. Intercepte une attaque directe ; SURCHARGE renforce la prochaine attaque émise pendant 3 s. Pelto et burn traversent la garde.",
		"static_shield": "Stase 1,5 s : invulnérable, mais toutes actions bloquées.",
		"projector": "Après une brève préparation, une onde circulaire repousse progressivement et ralentit les ennemis, plus fortement près du centre. Passif instantané au passage sous 25 % de PV, avec une recharge indépendante de 25 s. Nom provisoire.",
		"pyro_boots": "2 charges : dash enflammé de 5 m, explosion au départ, arrêt aux obstacles. Recharge : 6 s par charge.",
		"bio_injector": "Buff 3 s : déplacement et attaques accélérés.",
		"eclipse": "Maintenir pour choisir une destination, relâcher pour disparaître en particules. Intangible pendant le trajet ; explosion à l'arrivée qui brûle les cibles touchées et accorde un bouclier si elle touche un ennemi. Nom provisoire.",
		"permutation": "Échange les positions avec l'ennemi à l'arrivée d'une ombre électrique traversant les obstacles. Aucun cast ennemi interrompu ; vitesse +35 % et bouclier de 150 points pendant 3 s après réussite.",
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
		if identifier == "longshot":
			var base := float(weapon.get("damage", 0.0))
			var distance_bonus := float(weapon.get("distance_multiplier_max", 1.0))
			return "%d–%d dégâts • 5e tir ×%.2f • portée %.0f m • CD %.2f s" % [roundi(base), roundi(base * distance_bonus), float(weapon.get("enhanced_damage_multiplier", 1.0)), float(weapon.get("max_range", 0.0)), float(weapon.get("cooldown", 0.0))]
		if identifier == "mekatana":
			var damage: Array = weapon.get("base_damage", [])
			var dash: Array = weapon.get("dash_distance", [])
			if damage.size() < 3 or dash.size() < 3:
				return "MÊLÉE • combo de 3 coups"
			return "%d / %d / %d dégâts • cleave %.1f m • dash %.2f–%.2f m • combo %.1f s" % [int(damage[0]), int(damage[1]), int(damage[2]), float(weapon.get("melee_range", 0.0)), float(dash[0]), float(dash[2]), float(weapon.get("combo_window", 0.0))]
		if identifier == "blaster":
			return "%d–%d dégâts • portée %.0f m • charge %.1f s • CD %.2f s" % [int(weapon.get("damage", 0.0)), int(weapon.get("max_damage", weapon.get("damage", 0.0))), float(weapon.get("max_range", 0.0)), float(weapon.get("charge_time", 0.0)), float(weapon.get("cooldown", 0.0))]
		return "%d×%d dégâts • %d salves • portée %.0f m" % [int(weapon.get("pellets_per_shot", 0)), int(weapon.get("pellet_damage", 0.0)), int(weapon.get("magazine_size", 0)), float(weapon.get("max_range", 0.0))]
	if not module.is_empty():
		if identifier == "rocket_basket":
			return "%d × %d dégâts • %d PV / roquette • cast %.1f s • SLOW +%d%% • CD %.0f s (−40%% si 5 impacts)" % [int(module.projectiles), int(module.damage), int(module.health), float(module.preparation), int(module.slow_percent), float(module.cooldown)]
		if identifier == "eclipse":
			return "Portée %.0f m • explosion %d / %.0f m • burn %d/s / %.1f s • bouclier %d / %.0f s si touche • CD %.0f s" % [float(module.max_range), int(module.damage), float(module.explosion_radius), int(module.burn_damage_per_second), float(module.burn_duration), int(module.shield_amount), float(module.shield_duration), float(module.cooldown)]
		if identifier == "counter":
			return "Garde %.1f s • vitesse 50%% • SURCHARGE +%d / %.1f m • 3 s • CD %.0f s" % [float(module.guard_duration), int(module.surcharge_damage), float(module.surcharge_radius), float(module.cooldown)]
		if identifier == "projector":
			return "Cast %.2f s • rayon %.0f m • poussée %.2f–%.1f m • slow %d–%d%% / %.1f s • CD actif %.0f s • passif < %d%% PV / %.0f s" % [float(module.cast_duration), float(module.radius), float(module.push_min), float(module.push_max), int(module.slow_min), int(module.slow_max), float(module.slow_duration), float(module.cooldown), roundi(float(module.health_threshold) * 100.0), float(module.passive_cooldown)]
		if identifier == "permutation":
			return "Portée %.0f m • marque %.0f m/s • vitesse +%d%% / %.0f s • bouclier %d / %.0f s • CD %.0f s" % [float(module.activation_range), float(module.mark_speed), roundi((float(module.speed_multiplier) - 1.0) * 100.0), float(module.duration), int(module.shield_amount), float(module.shield_duration), float(module.cooldown)]
		if identifier == "fulguro_punch":
			return "%d–%d dégâts • +%d–%d mur • %.1f–%.1f m • charge %.2f–%.1f s" % [int(module.damage_min), int(module.damage_max), int(module.wall_damage_min), int(module.wall_damage_max), float(module.range_min), float(module.range_max), float(module.charge_min), float(module.charge_max)]
		if identifier == "pelto_smash":
			return "%d + %d dégâts • %.1f m × %.1f m • slow %d%% • traction %.1f m" % [int(module.outbound_damage), int(module.return_damage), float(module.max_range), float(module.width), int(module.outbound_slow_percent), float(module.pull_distance)]
		if module.has("cooldown"):
			return "CD %.1f s" % float(module.cooldown)
		return "PASSIF EXCLUSIF"
	return ""
