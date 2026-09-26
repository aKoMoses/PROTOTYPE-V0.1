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

# V0.1 starting definitions. Weapon values stay data-driven so future modules
# can modify them without rewriting the combat controller.
const WEAPON_DEFINITIONS := {
	"blaster": {
		"display_name": "Blaster",
		"damage": 20.0,
		"max_damage": 50.0,
		"cooldown": 0.45,
		"charge_time": 1.0,
		"max_range": 14.0,
		"projectile_speed": 24.0,
		"charge_slow_multiplier": 0.80,
		"projectile_radius": 0.16,
	},
	"shotgun": {
		"display_name": "Shotgun",
		"pellets_per_shot": 6,
		"pellet_damage": 20.0,
		"pellet_angles": [-14.0, -8.0, -3.0, 3.0, 8.0, 14.0],
		"hitbox_radius": 0.78,
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
	"magnetic_field": {
		"category": "defensive",
		"preparation": 0.15,
		"distance": 2.0,
		"width": 4.0,
		"height": 2.4,
		"duration": 2.5,
		"cooldown": 12.0,
	},
	"static_shield": {
		"category": "defensive",
		"duration": 1.5,
		"cooldown": 18.0,
	},
	"baroud": {"category": "passive"},
	"omnivamp": {"category": "passive"},
}


static func effect_definition(effect_type: String) -> Dictionary:
	return EFFECT_DEFINITIONS.get(effect_type, {})
