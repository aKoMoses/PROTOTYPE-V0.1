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
		"counter_trigger": true,
		"display_name": "Mekatana",
		"damage": 90.0,
		"base_damage": [90.0, 100.0, 150.0],
		"preparation": [0.12, 0.14, 0.18],
		"active": [0.10, 0.10, 0.13],
		"recovery": [0.20, 0.23, 0.35],
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
		"counter_trigger": true,
		"display_name": "Longshot",
		"damage": 90.0,
		"distance_start": 6.0,
		"distance_max": 18.0,
		"distance_multiplier_max": 2.25,
		"max_range": 32.0,
		"cooldown": 0.85,
		"attack_preparation": 0.08,
		"projectile_speed": 120.0,
		"projectile_radius": 0.09,
		"enhanced_size_multiplier": 1.50,
		"enhanced_speed_multiplier": 1.25,
		"enhanced_damage_multiplier": 1.80,
		"hit_speed_multiplier": 1.20,
		"hit_speed_duration": 0.70,
	},
	"blaster": {
		"counter_trigger": true,
		"display_name": "Blaster",
		"damage": 100.0,
		"max_damage": 360.0,
		"cooldown": 0.20,
		"charge_time": 0.45,
		"max_range": 24.0,
		"projectile_speed": 57.6,
		"charged_speed_multiplier": 2.0,
		"charged_size_multiplier": 3.2,
		"charge_slow_multiplier": 1.0,
		"projectile_radius": 0.16,
	},
	"shotgun": {
		"counter_trigger": true,
		"display_name": "Shotgun",
		"pellets_per_shot": 6,
		"pellet_damage": 28.0,
		"pellet_angles": [-14.0, -8.0, -3.0, 3.0, 8.0, 14.0],
		"hitbox_radius": 0.78,
		"pellet_speed": 22.0,
		"max_range": 7.0,
		"falloff_start": 3.0,
		"minimum_damage": 8.0,
		"attack_preparation": 0.10,
		"attack_recovery": 0.60,
		"magazine_size": 3,
		"reload_duration": 1.40,
	},
}

const MODULE_DEFINITIONS := {
	"rocket_basket": {
		"category": "offensive", "preparation": 0.30, "cast_move_multiplier": 0.85,
		"projectiles": 5, "damage": 35.0, "health": 40.0,
		"speed": 10.0, "turn_rate": 12.0, "collision_radius": 0.18,
		"launch_half_angle": 30.0, "homing_delay": 0.28, "homing_ramp": 0.18,
		"slow_percent": 7.0, "slow_duration": 3.0,
		"cooldown": 10.0, "cooldown_refund": 0.40, "burn_duration": BURN_DURATION,
	},
	"counter": {
		"category": "defensive", "preparation": 0.08, "guard_duration": 1.1,
		"move_multiplier": 0.5, "success_recovery": 0.12, "failure_recovery": 0.2,
		"cooldown": 8.0, "surcharge_duration": 3.0,
		# Player capsule diameter 1.1 m: two widths.
		"surcharge_radius": 2.2, "surcharge_damage": 80.0,
	},
	"javelin": {
		"category": "offensive",
		"preparation": 0.35,
		"charge_max": 1.20,
		"max_range": 8.0,
		"charged_range": 16.0,
		"speed": 20.0,
		"charged_speed": 36.0,
		"collision_radius": 0.12,
		"damage": 140.0,
		"charged_damage": 280.0,
		"mark_duration": 2.5,
		"charged_mark_duration": 5.0,
		"teleport_distance": 1.4,
		"recast_slow_percent": 25.0,
		"recast_slow_duration": 0.8,
		"cooldown": 12.0,
	},
	"fulguro_punch": {
		"counter_trigger": true,
		"category": "offensive",
		"charge_min": 0.35,
		"charge_max": 1.8,
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
		"wall_stun": 1.0,
		"cooldown": 8.0,
	},
	"pelto_smash": {
		"counter_trigger": false,
		"category": "offensive",
		"preparation": 0.28,
		"max_aim_hold": 3.0,
		"max_range": 9.0,
		"width": 2.5,
		"front_thickness": 0.7,
		"outbound_speed": 13.0,
		"return_pause": 0.08,
		"return_speed": 18.0,
		# Prototype 0 uses 1 000 PV. These values preserve the requested
		# 16 + 10 damage split from a 100-PV reference.
		"outbound_damage": 160.0,
		"outbound_slow_percent": 20.0,
		"outbound_slow_duration": 0.8,
		"return_damage": 100.0,
		"return_slow_percent": 25.0,
		"return_slow_duration": 1.1,
		"pull_distance": 1.5,
		"pull_duration": 0.15,
		"impact_duration": 0.10,
		"recovery": 0.16,
		"cooldown": 10.0,
	},
	"pyro_boots": {
		"category": "mobility",
		"charges": 2,
		"dash_distance": 5.0,
		"dash_duration": 0.18,
		"departure_damage": 60.0,
		"departure_radius": 2.0,
		"cooldown": 6.0,
	},
	"bio_injector": {
		"category": "mobility",
		"duration": 4.0,
		"speed_multiplier": 1.40,
		"attack_speed_multiplier": 1.50,
		"other_cooldown_rate": 1.0 / 0.70,
		"cooldown": 15.0,
	},
	"permutation": {
		"category": "mobility",
		"preparation": 0.18,
		"activation_range": 20.0,
		"mark_speed": 65.0,
		"minimum_travel_time": 0.12,
		"shield_amount": 150.0,
		"shield_duration": 3.0,
		"duration": 3.0,
		"speed_multiplier": 1.35,
		"cooldown": 12.0,
	},
	"eclipse": {
		"category": "mobility",
		"max_range": 12.0,
		"travel_duration": 0.25,
		"explosion_radius": 3.0,
		"damage": 120.0,
		"burn_duration": BURN_DURATION,
		"burn_damage_per_second": BURN_DAMAGE_PER_SECOND,
		"shield_amount": 150.0,
		"shield_duration": 3.0,
		"cooldown": 10.0,
	},
	"magnetic_field": {
		"category": "defensive",
		"preparation": 0.15,
		"distance": 2.0,
		"width": 4.0,
		"height": 2.4,
		"duration": 3.0,
		"cooldown": 12.0,
	},
	"static_shield": {
		"category": "defensive",
		"duration": 1.5,
		"minimum_duration": 0.5,
		"cooldown": 12.0,
	},
	"projector": {
		"category": "defensive",
		"automatic_passive": true,
		"passive_cooldown": 25.0,
		"health_threshold": 0.25,
		"radius": 6.0,
		"cast_duration": 0.18,
		"push_duration": 0.42,
		"push_min": 1.25,
		"push_max": 5.5,
		"slow_min": 15.0,
		"slow_max": 65.0,
		"slow_duration": 2.5,
		"cooldown": 6.0,
	},
	"baroud": {"category": "passive"},
	"omnivamp": {"category": "passive"},
	"auxiliary_reactor": {"category": "passive", "reduction": 0.60, "interval": 0.75},
	"tracker": {"category": "passive", "hits": 2, "gap": 4.0, "duration": 6.0},
	"alternator": {"category": "passive", "damage_bonus": 0.30, "duration": 3.0},
	"inertia": {"category": "passive", "slow_percent": 25.0, "slow_duration": 1.5, "window": 2.5},
}


static func effect_definition(effect_type: String) -> Dictionary:
	return EFFECT_DEFINITIONS.get(effect_type, {})
