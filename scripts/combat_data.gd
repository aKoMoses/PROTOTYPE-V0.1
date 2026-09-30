class_name CombatData
extends RefCounted

## Shared, immutable starting data for Prototype 0.
## Runtime values belong to CombatState instances; these definitions are safe to
## reuse for the player, the bot and training mannequins.

const MAX_HEALTH := 1000.0
const MOVE_SPEED := 5.0
const DEFAULT_ROBOT := "polyvalent"
const ROBOT_DEFINITIONS := {
	"agile": {"max_health": 800.0, "move_speed": 6.0},
	"polyvalent": {"max_health": MAX_HEALTH, "move_speed": MOVE_SPEED},
	"puissant": {"max_health": 1200.0, "move_speed": 4.0},
}
## Presentation-only multiplier shared by the player and every bot visual root.
## Keep gameplay roots, collisions and camera settings outside this scale.
const CHARACTER_VISUAL_SCALE := 1.35
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
	"mekatana": {
		"display_name": "Mekatana",
		"damage": 65.0,
		"base_damage": [65.0, 75.0, 100.0],
		"preparation": [0.12, 0.14, 0.18],
		"active": [0.10, 0.10, 0.13],
		"recovery": [0.20, 0.23, 0.48],
		"dash_distance": [1.30, 1.90, 2.60],
		"melee_range": 2.0,
		"cleave_width": [2.3, 2.3, 2.5],
		"cleave_height": 1.8,
		"max_range": 4.6,
		"combo_window": 2.5,
		"second_bonus": 1.20,
		"third_bonus": 1.25,
		"third_full_bonus": 1.60,
	},
	"longshot": {
		"display_name": "Longshot",
		"damage": 36.0,
		"distance_start": 6.0,
		"distance_max": 18.0,
		"distance_multiplier_max": 1.75,
		"max_range": 32.0,
		"cooldown": 1.05,
		"attack_preparation": 0.08,
		"projectile_speed": 60.0,
		"projectile_radius": 0.075,
		"enhanced_size_multiplier": 1.50,
		"enhanced_speed_multiplier": 1.25,
		"enhanced_damage_multiplier": 1.40,
	},
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
	"fulguro_punch": {
		"category": "offensive",
		"charge_min": 0.35,
		"charge_max": 3.0,
		"range_min": 2.0,
		"range_max": 4.0,
		"damage_min": 200.0,
		"damage_max": 400.0,
		"wall_damage_min": 150.0,
		"wall_damage_max": 250.0,
		# Compatibility aliases used by generic module displays and older tests.
		"preparation": 0.35,
		"range": 2.0,
		"width": 0.9,
		"active_window": 0.10,
		"recovery": 0.20,
		"max_knockback_distance": 4.0,
		"max_knockback_duration": 0.35,
		# Prototype 0 uses 1 000 PV. These fixed values preserve the requested
		# 20/15 proportions from a 100-PV reference without percentage damage.
		"damage": 200.0,
		"wall_damage": 150.0,
		"wall_stun": 0.75,
		"cooldown": 8.0,
	},
	"pelto_smash": {
		"category": "offensive",
		"preparation": 0.45,
		"max_range": 7.0,
		"width": 2.5,
		"front_thickness": 0.7,
		"outbound_speed": 10.0,
		"return_pause": 0.12,
		"return_speed": 12.0,
		# Prototype 0 uses 1 000 PV. These values preserve the requested
		# 16 + 10 damage split from a 100-PV reference.
		"outbound_damage": 160.0,
		"outbound_slow_percent": 20.0,
		"outbound_slow_duration": 0.8,
		"return_damage": 100.0,
		"pull_distance": 0.9,
		"pull_duration": 0.15,
		"impact_duration": 0.10,
		"recovery": 0.25,
		"cooldown": 10.0,
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
