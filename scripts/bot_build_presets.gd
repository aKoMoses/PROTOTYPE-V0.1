class_name BotBuildPresets
extends RefCounted

## Coherent equipment families, drawn from a shuffled bag for each opponent.
## Randomness changes a play style and its utility slots, never combat stats.
## The duel target currently uses the shared Polyvalent chassis (1 000 PV / 5 m/s).

const PRESETS := [
	{
		"id": "marksman", "name": "TIREUR", "style": "Placement lointain, deux impacts puis EXÉCUTION traversante",
		"weapon": "longshot", "offensive": "javelin",
		"defensive": ["magnetic_field"], "mobility": ["pyro_boots"], "passive": ["omnivamp", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.43, "caution": 0.82, "ideal_range": 17.5, "strafe_period": 1.75, "flank_bias": 0.77, "heal_threshold": 0.60},
	},
	{
		"id": "mechanist", "name": "SABREUR", "style": "Combo de mêlée et dashes au Mekatana",
		"weapon": "mekatana", "offensive": "fulguro_punch",
		"defensive": ["magnetic_field", "static_shield", "counter"], "mobility": ["bio_injector"], "passive": ["omnivamp", "baroud", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.86, "caution": 0.54, "ideal_range": 2.0, "strafe_period": 1.25, "flank_bias": 0.72, "heal_threshold": 0.43},
	},
	{
		"id": "harasser", "name": "HARCELEUR", "style": "Usure à distance et sustain",
		"weapon": "blaster", "offensive": "rocket_basket",
		"defensive": ["magnetic_field"], "mobility": ["bio_injector", "pyro_boots"], "passive": ["omnivamp", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.58, "caution": 0.74, "ideal_range": 9.0, "strafe_period": 1.45, "flank_bias": 0.62, "heal_threshold": 0.57},
	},
	{
		"id": "tracker", "name": "TRAQUEUR", "style": "Angles et repositionnement au Javelin",
		"weapon": "blaster", "offensive": "javelin",
		"defensive": ["magnetic_field", "static_shield", "counter"], "mobility": ["pyro_boots", "permutation"], "passive": ["omnivamp", "baroud", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.78, "caution": 0.56, "ideal_range": 6.4, "strafe_period": 1.15, "flank_bias": 0.92, "heal_threshold": 0.45},
	},
	{
		"id": "sentinel", "name": "SENTINELLE", "style": "Contrôle des couloirs et contre-attaque",
		"weapon": "blaster", "offensive": "pelto_smash",
		"defensive": ["magnetic_field"], "mobility": ["bio_injector"], "passive": ["omnivamp", "baroud", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.47, "caution": 0.90, "ideal_range": 7.1, "strafe_period": 1.85, "flank_bias": 0.48, "heal_threshold": 0.63},
	},
	{
		"id": "duelist", "name": "DUELLISTE", "style": "Tirs courts puis punition au Fulguro",
		"weapon": "blaster", "offensive": "fulguro_punch",
		"defensive": ["static_shield"], "mobility": ["pyro_boots", "bio_injector"], "passive": ["baroud", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.83, "caution": 0.53, "ideal_range": 4.3, "strafe_period": 1.30, "flank_bias": 0.71, "heal_threshold": 0.41},
	},
	{
		"id": "assault", "name": "ASSAILLANT", "style": "Entrée explosive Shotgun / Fulguro",
		"weapon": "shotgun", "offensive": "fulguro_punch",
		"defensive": ["static_shield"], "mobility": ["pyro_boots"], "passive": ["baroud", "omnivamp", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.94, "caution": 0.42, "ideal_range": 2.7, "strafe_period": 1.05, "flank_bias": 0.68, "heal_threshold": 0.35},
	},
	{
		"id": "trapper", "name": "RABATTEUR", "style": "Ralentissement et rappel dans le Shotgun",
		"weapon": "shotgun", "offensive": "pelto_smash",
		"defensive": ["magnetic_field", "static_shield", "counter"], "mobility": ["pyro_boots"], "passive": ["omnivamp", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.76, "caution": 0.64, "ideal_range": 3.4, "strafe_period": 1.50, "flank_bias": 0.67, "heal_threshold": 0.50},
	},
	{
		"id": "skirmisher", "name": "VOLTIGEUR", "style": "Flanc rapide et rapprochement au Javelin",
		"weapon": "shotgun", "offensive": "javelin",
		"defensive": ["static_shield"], "mobility": ["pyro_boots"], "passive": ["baroud", "omnivamp", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.86, "caution": 0.51, "ideal_range": 3.0, "strafe_period": 0.90, "flank_bias": 0.96, "heal_threshold": 0.43},
	},
	{
		"id": "sustainer", "name": "ÉCORCHEUR", "style": "Javelin puis rafale sous Bio Injector",
		"weapon": "shotgun", "offensive": "javelin",
		"defensive": ["static_shield", "magnetic_field"], "mobility": ["bio_injector"], "passive": ["omnivamp", "auxiliary_reactor", "tracker", "alternator", "inertia"],
		"personality": {"aggression": 0.80, "caution": 0.62, "ideal_range": 3.7, "strafe_period": 1.35, "flank_bias": 0.59, "heal_threshold": 0.53},
	},
]

var _rng := RandomNumberGenerator.new()
var _bag: Array[int] = []
var _last_index := -1


func _init() -> void:
	_rng.randomize()


func set_seed(value: int) -> void:
	_rng.seed = value
	_bag.clear()
	_last_index = -1


static func definitions() -> Array:
	return PRESETS.duplicate(true)


func next_preset() -> Dictionary:
	if _bag.is_empty():
		_refill_bag()
	var index: int = _bag.pop_back()
	_last_index = index
	var definition: Dictionary = PRESETS[index]
	var loadout := {
		"robot": "polyvalent",
		"weapon": str(definition.weapon),
		"offensive": str(definition.offensive),
	}
	for slot in ["defensive", "mobility", "passive"]:
		var options: Array = definition[slot]
		loadout[slot] = str(options[_rng.randi_range(0, options.size() - 1)])
	var personality: Dictionary = definition.personality.duplicate(true)
	# Small seeded variation prevents the same family from becoming a script.
	for trait_name in ["aggression", "caution", "flank_bias"]:
		personality[trait_name] = clampf(float(personality[trait_name]) + _rng.randf_range(-0.055, 0.055), 0.20, 0.98)
	personality.strafe_period = float(personality.strafe_period) + _rng.randf_range(-0.12, 0.12)
	return {
		"id": str(definition.id),
		"name": str(definition.name),
		"style": str(definition.style),
		"loadout": loadout,
		"personality": personality,
	}


func _refill_bag() -> void:
	for index in range(PRESETS.size()):
		_bag.append(index)
	for index in range(_bag.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var value := _bag[index]
		_bag[index] = _bag[swap_index]
		_bag[swap_index] = value
	# pop_back draws next: avoid repeats even across two complete bags.
	if _bag.size() > 1 and _bag.back() == _last_index:
		var swap_index := _rng.randi_range(0, _bag.size() - 2)
		var value := _bag[_bag.size() - 1]
		_bag[_bag.size() - 1] = _bag[swap_index]
		_bag[swap_index] = value
