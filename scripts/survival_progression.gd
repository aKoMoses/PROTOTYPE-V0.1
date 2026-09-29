class_name SurvivalProgression
extends RefCounted

const TOTAL_WAVES := 12
const LOADOUT := preload("res://scripts/loadout_state.gd")
const SYNERGIES := preload("res://scripts/survival_synergies.gd")
const ASPECTS := preload("res://scripts/survival_aspects.gd")
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
var unlocked_synergies: Array[String] = []
var aspects := {"weapon": {"path": "", "rank": 0}, "offensive": {"path": "", "rank": 0}, "defensive": {"path": "", "rank": 0}, "mobility": {"path": "", "rank": 0}, "passive": {"path": "", "rank": 0}}
var _offers: Dictionary = {}
var _claimed: Dictionary = {}
var _last_choice: Dictionary = {}
var _random := RandomNumberGenerator.new()

func _init() -> void:
	_random.randomize()

func choose_weapon(identifier: String) -> bool:
	if weapon != "" or not identifier in LOADOUT.WEAPONS:
		return false
	weapon = identifier
	return true

func reward_choices(completed_wave: int) -> Array[Dictionary]:
	if weapon == "" or completed_wave < 1 or completed_wave >= TOTAL_WAVES or _claimed.has(completed_wave):
		return []
	if _offers.has(completed_wave):
		return _offers[completed_wave].duplicate(true)
	var new_items: Array[Dictionary] = []
	var improvements: Array[Dictionary] = []
	var transformations: Array[Dictionary] = []
	for category in CATEGORY_OPTIONS:
		if str(equipment[category]) == "":
			for identifier in CATEGORY_OPTIONS[category]:
				new_items.append({"category": category, "kind": "item", "id": identifier, "title": LOADOUT.display_name(identifier), "description": LOADOUT.category_description(identifier)})
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		var item_id: String = weapon if category == "weapon" else str(equipment[category])
		if item_id == "":
			continue
		transformations.append_array(ASPECTS.choices(build(), category, item_id))
		if int(upgrades[category].power) < 3 and not (_last_choice.get("kind", "") == "power" and _last_choice.get("category", "") == category):
			improvements.append({"category": category, "kind": "power", "id": item_id, "title": "PUISSANCE · %s" % LOADOUT.display_name(item_id), "description": _power_description(category)})
		if int(upgrades[category].tempo) < 2:
			improvements.append({"category": category, "kind": "tempo", "id": item_id, "title": "RYTHME · %s" % LOADOUT.display_name(item_id), "description": _tempo_description(category)})
	var synergy_cards: Array[Dictionary] = []
	for id in SYNERGIES.available_for(build()):
		synergy_cards.append({"category": "synergy", "kind": "synergy", "id": id, "title": SYNERGIES.DEFINITIONS[id].name, "description": SYNERGIES.DEFINITIONS[id].description})
	var choices: Array[Dictionary] = []
	if not synergy_cards.is_empty():
		_take_random(synergy_cards, choices)
	if not transformations.is_empty():
		_take_random(transformations, choices)
	if not new_items.is_empty() and (synergy_cards.is_empty() or improvements.is_empty() or _random.randf() < 0.5):
		_take_random(new_items, choices)
	if choices.size() < 3 and not improvements.is_empty():
		_take_random(improvements, choices)
	while choices.size() < 3:
		var pool := new_items + improvements
		pool.append_array(transformations)
		pool.append_array(synergy_cards)
		pool = pool.filter(func(card: Dictionary) -> bool: return not choices.any(func(picked: Dictionary) -> bool: return picked.kind == card.kind and picked.id == card.id and picked.get("path", "") == card.get("path", "")))
		if pool.is_empty():
			break
		_take_random(pool, choices)
	choices.shuffle()
	_offers[completed_wave] = choices.duplicate(true)
	return choices

func _take_random(pool: Array[Dictionary], choices: Array[Dictionary]) -> void:
	choices.append(pool[_random.randi_range(0, pool.size() - 1)])

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
	elif str(choice.kind) == "synergy":
		unlocked_synergies.append(str(choice.id))
	elif str(choice.kind) == "evolution":
		aspects[category] = {"path": str(choice.path), "rank": int(choice.rank)}
		evolutions[category] = int(choice.rank) == ASPECTS.MAX_RANK
	else:
		upgrades[category][str(choice.kind)] += 1
	_offers.erase(completed_wave)
	_claimed[completed_wave] = true
	_last_choice = choice.duplicate(true)
	return true

func build() -> Dictionary:
	return {"weapon": weapon, "offensive": equipment.offensive, "defensive": equipment.defensive, "mobility": equipment.mobility, "passive": equipment.passive, "upgrades": upgrades.duplicate(true), "evolutions": evolutions.duplicate(true), "aspects": aspects.duplicate(true), "synergies": unlocked_synergies.duplicate()}
