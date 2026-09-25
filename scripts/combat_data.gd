class_name CombatData
extends RefCounted

## Shared, immutable starting data for Prototype 0.
## Runtime values belong to CombatState instances; these definitions are safe to
## reuse for the player, the bot and training mannequins.

const MAX_HEALTH := 1000.0
const MOVE_SPEED := 5.0
const CRIT_MULTIPLIER := 1.5
const BURN_DAMAGE_PER_SECOND := 20.0
const BURN_DURATION := 3.5
const COMBAT_REVEAL_DURATION := 3.0

const EFFECT_BURN := "BURN"
const EFFECT_SLOW := "SLOW"
const EFFECT_STUN := "STUN"
const EFFECT_SPOTTED := "SPOTTED"

const EFFECT_DEFINITIONS := {
	EFFECT_BURN: {"display_name": "BURN", "color": Color("#ff7347")},
	EFFECT_SLOW: {"display_name": "SLOW", "color": Color("#8fd7ff")},
	EFFECT_STUN: {"display_name": "STUN", "color": Color("#ffe16a")},
	EFFECT_SPOTTED: {"display_name": "SPOTTED", "color": Color("#9ffaff")},
}

# V0.1 starting definitions. P0-103/P0-104 will connect these values to the
# complete weapon implementations; keeping them here prevents future systems
# from inventing separate copies of the rules.
const WEAPON_DEFINITIONS := {
	"electro_axe": {
		"display_name": "Electro Axe",
		"combo_damage": [80.0, 90.0, 150.0],
		"combo_ranges": [3.0, 2.2, 1.2],
		"combo_preparation": [0.20, 0.20, 0.35],
		"combo_active": [0.10, 0.10, 0.25],
		"combo_recovery": [0.25, 0.30, 0.25],
		"combo_slow_duration": [0.25, 0.25, 0.50],
		"combo_slow_percent": 30.0,
		"combo_stun_duration": 0.50,
		"combo_estoc_width": 0.65,
		"combo_sweep_half_angle": 50.0,
		"combo_wave_inner_radius": 1.2,
		"combo_wave_outer_radius": 3.5,
		"combo_cycle": 2.0,
	},
	"shotgun": {
		"display_name": "Shotgun",
		"pellets_per_shot": 6,
		"pellet_damage": 20.0,
		"pellet_angles": [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0],
		"pellet_speed": 22.0,
		"max_range": 7.0,
		"falloff_start": 3.0,
		"minimum_damage": 8.0,
		"attack_preparation": 0.10,
		"attack_recovery": 0.60,
		"magazine_size": 3,
		"reload_duration": 1.80,
	},
}

const MODULE_DEFINITIONS := {
	"modulo_drone": {
		"category": "offensive",
		"preparation": 0.18,
		"max_range": 9.0,
		"speed": 10.0,
		"collision_radius": 0.15,
		"damage": 100.0,
		"burn_duration": BURN_DURATION,
		"spotted_duration": 5.0,
		"cone_half_angle": 20.0,
		"max_turn_rate": 90.0,
		"cooldown": 10.0,
	},
	"javelin": {
		"category": "offensive",
		"preparation": 0.12,
		"max_range": 8.0,
		"speed": 20.0,
		"collision_radius": 0.12,
		"damage": 140.0,
		"mark_duration": 2.5,
		"teleport_distance": 1.4,
		"cooldown": 12.0,
	},
	"pyro_boots": {
		"category": "mobility",
		"dash_distance": 3.0,
		"dash_duration": 0.18,
		"cooldown": 6.0,
	},
	"bio_injector": {
		"category": "mobility",
		"duration": 3.0,
		"speed_multiplier": 1.40,
		"attack_speed_multiplier": 1.50,
		"other_cooldown_rate": 1.0 / 0.70,
		"cooldown": 18.0,
	},
	"magnetic_field": {"category": "defensive", "cooldown": 12.0},
	"static_shield": {"category": "defensive", "cooldown": 18.0},
	"baroud": {"category": "passive"},
	"omnivamp": {"category": "passive"},
}


static func effect_definition(effect_type: String) -> Dictionary:
	return EFFECT_DEFINITIONS.get(effect_type, {})
