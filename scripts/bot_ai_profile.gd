class_name BotAIProfile
extends RefCounted

## Behaviour-only difficulty tuning. None of these profiles changes health,
## damage, projectile speed, range, ammunition or module cooldowns.

const DEFAULT_PROFILE := "normal"
const PROFILES := {
	"easy": {
		"reaction_delay": 0.38,
		"aim_error_degrees": 8.0,
		"prediction_quality": 0.28,
		"aggression": 0.38,
		"caution": 0.72,
		"position_quality": 0.42,
		"module_skill": 0.34,
		"decision_interval": 0.34,
		"intent_minimum_duration": 0.85,
		"intent_switch_margin": 0.90,
		"candidate_count": 4,
		"dodge_horizon": 0.48,
	},
	"normal": {
		"reaction_delay": 0.22,
		"aim_error_degrees": 3.6,
		"prediction_quality": 0.74,
		"aggression": 0.68,
		"caution": 0.58,
		"position_quality": 0.76,
		"module_skill": 0.76,
		"decision_interval": 0.23,
		"intent_minimum_duration": 1.10,
		"intent_switch_margin": 0.62,
		"candidate_count": 8,
		"dodge_horizon": 0.72,
	},
	"hard": {
		"reaction_delay": 0.14,
		"aim_error_degrees": 1.8,
		"prediction_quality": 0.91,
		"aggression": 0.78,
		"caution": 0.70,
		"position_quality": 0.94,
		"module_skill": 0.95,
		"decision_interval": 0.16,
		"intent_minimum_duration": 1.25,
		"intent_switch_margin": 0.42,
		"candidate_count": 12,
		"dodge_horizon": 0.90,
	},
}


static func sanitize(profile_name: String) -> String:
	return profile_name if PROFILES.has(profile_name) else DEFAULT_PROFILE


static func values(profile_name: String) -> Dictionary:
	return PROFILES[sanitize(profile_name)].duplicate(true)
