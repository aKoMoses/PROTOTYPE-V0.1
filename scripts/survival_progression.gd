class_name SurvivalProgression
extends RefCounted

const TOTAL_WAVES := 12
const LOADOUT := preload("res://scripts/loadout_state.gd")
const REWARD_ORDER := ["offensive", "defensive", "mobility", "passive", "weapon", "offensive", "defensive", "mobility", "passive", "weapon", "offensive"]
const CATEGORY_OPTIONS := {
	"offensive": ["modulo_drone", "javelin", "fulguro_punch", "pelto_smash"],
	"defensive": ["magnetic_field", "static_shield"],
	"mobility": ["pyro_boots", "bio_injector"],
	"passive": ["baroud", "omnivamp"],
}

var weapon := ""
var equipment := {"offensive": "", "defensive": "", "mobility": "", "passive": ""}
var upgrades := {"weapon": {"power": 0, "tempo": 0}, "offensive": {"power": 0, "tempo": 0}, "defensive": {"power": 0, "tempo": 0}, "mobility": {"power": 0, "tempo": 0}, "passive": {"power": 0, "tempo": 0}}
var evolutions := {"weapon": false, "offensive": false, "defensive": false, "mobility": false, "passive": false}

func choose_weapon(identifier: String) -> bool:
	if weapon != "" or not identifier in LOADOUT.WEAPONS:
		return false
	weapon = identifier
	return true

func reward_category(completed_wave: int) -> String:
	if completed_wave < 1 or completed_wave >= TOTAL_WAVES:
		return ""
	return REWARD_ORDER[completed_wave - 1]

func reward_choices(completed_wave: int) -> Array[Dictionary]:
	var category := reward_category(completed_wave)
	if category == "":
		return []
	if category != "weapon" and str(equipment[category]) == "":
		var identifiers: Array = CATEGORY_OPTIONS[category]
		return [
			{"category": category, "kind": "item", "id": identifiers[0], "title": LOADOUT.display_name(identifiers[0]), "description": LOADOUT.category_description(identifiers[0])},
			{"category": category, "kind": "item", "id": identifiers[1], "title": LOADOUT.display_name(identifiers[1]), "description": LOADOUT.category_description(identifiers[1])},
		]
	var item_id: String = weapon if category == "weapon" else str(equipment[category])
	if not bool(evolutions[category]):
		return [
			{"category": category, "kind": "evolution", "id": item_id, "title": "ÉVOLUTION · %s" % LOADOUT.display_name(item_id), "description": "%s  %s" % [_power_description(category), _evolution_description(item_id)]},
			{"category": category, "kind": "tempo", "id": item_id, "title": "RYTHME · %s" % LOADOUT.display_name(item_id), "description": _tempo_description(category)},
		]
	if category == "passive":
		return [
			{"category": category, "kind": "power", "id": item_id, "title": "PUISSANCE · %s" % LOADOUT.display_name(item_id), "description": "Renforce l'effet du passif."},
			{"category": category, "kind": "tempo", "id": item_id, "title": "ENDURANCE · %s" % LOADOUT.display_name(item_id), "description": _tempo_description(category)},
		]
	return [
		{"category": category, "kind": "power", "id": item_id, "title": "PUISSANCE · %s" % LOADOUT.display_name(item_id), "description": _power_description(category)},
		{"category": category, "kind": "tempo", "id": item_id, "title": "RYTHME · %s" % LOADOUT.display_name(item_id), "description": _tempo_description(category)},
	]

func _evolution_description(item_id: String) -> String:
	return {
		"blaster": "Le tir traverse la cible et frappe un ennemi aligné derrière à 60 % des dégâts.",
		"shotgun": "+2 projectiles extérieurs par tir (6 → 8).",
		"modulo_drone": "L'impact rebondit sur un second ennemi proche à 50 % des dégâts.",
		"javelin": "L'impact inflige 45 % des dégâts aux ennemis dans un rayon de 3 m.",
		"magnetic_field": "Le mur électrocute les ennemis à 3 m : 35 dégâts toutes les 0,8 s.",
		"static_shield": "La fin du bouclier émet une onde de 70 dégâts dans un rayon de 4 m.",
		"pyro_boots": "Le dash laisse une traînée brûlante qui blesse les ennemis traversés.",
		"fulguro_punch": "La décharge libère une onde de feu incandescent autour de la cible projetée.",
		"pelto_smash": "Le retour arrache une secousse qui blesse les ennemis proches de la cible.",
		"bio_injector": "L'activation libère une onde de 70 dégâts dans un rayon de 4 m.",
		"baroud": "Le déclenchement de Baroud repousse les ennemis avec une onde de 90 dégâts.",
		"omnivamp": "Chaque ennemi éliminé rend 35 PV supplémentaires.",
	}.get(item_id, "Nouvel effet de combat.")

func _power_description(category: String) -> String:
	var current := int(upgrades[category]["power"])
	var base := 0.70 if category in ["defensive", "mobility"] else 0.65
	var step := 0.55 if category in ["defensive", "mobility"] else 0.60
	return "Effet : %d %% → %d %% de la valeur normale." % [roundi((base + step * current) * 100.0), roundi((base + step * (current + 1)) * 100.0)]

func _tempo_description(category: String) -> String:
	if category == "passive":
		return "+250 PV maximum pendant cette partie."
	var current := int(upgrades[category]["tempo"])
	var base := 1.20 if category == "weapon" else 1.25
	var factor := 0.72 if category == "weapon" else 0.65
	return "Temps de recharge : %d %% → %d %% de la valeur normale." % [roundi(base * pow(factor, current) * 100.0), roundi(base * pow(factor, current + 1) * 100.0)]

func apply_reward(completed_wave: int, choice: Dictionary) -> bool:
	var valid := false
	for offered in reward_choices(completed_wave):
		if offered == choice:
			valid = true
			break
	if not valid:
		return false
	var category: String = choice.category
	if str(choice.kind) == "item":
		equipment[category] = str(choice.id)
	elif str(choice.kind) == "evolution":
		evolutions[category] = true
		upgrades[category]["power"] += 1
	else:
		upgrades[category][str(choice.kind)] += 1
	return true

func build() -> Dictionary:
	return {"weapon": weapon, "offensive": equipment.offensive, "defensive": equipment.defensive, "mobility": equipment.mobility, "passive": equipment.passive, "upgrades": upgrades.duplicate(true), "evolutions": evolutions.duplicate(true)}
