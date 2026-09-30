class_name LongshotState
extends RefCounted

## One cycle per carried weapon instance. Input and cooldowns never advance it.
const COMBAT_DATA := preload("res://scripts/combat_data.gd")

var shots_fired: int = 0


func normal_shots() -> int:
	return posmod(shots_fired, 5)


func is_enhanced_ready() -> bool:
	return normal_shots() == 4


func next_enhanced() -> bool:
	return is_enhanced_ready()


func commit_shot() -> bool:
	var enhanced := next_enhanced()
	shots_fired += 1
	return enhanced


func reset() -> void:
	shots_fired = 0


static func distance_multiplier(distance: float, definition: Dictionary = {}) -> float:
	var settings: Dictionary = definition if not definition.is_empty() else COMBAT_DATA.WEAPON_DEFINITIONS.get("longshot", {})
	var start := maxf(0.0, float(settings.get("distance_start", 0.0)))
	var maximum_distance := maxf(start + 0.001, float(settings.get("distance_max", start + 0.001)))
	var maximum := maxf(1.0, float(settings.get("distance_multiplier_max", 1.0)))
	var progress := clampf((maxf(0.0, distance) - start) / (maximum_distance - start), 0.0, 1.0)
	return lerpf(1.0, maximum, progress)


static func damage_at_distance(distance: float, enhanced: bool, definition: Dictionary = {}, power: float = 1.0) -> float:
	var settings: Dictionary = definition if not definition.is_empty() else COMBAT_DATA.WEAPON_DEFINITIONS.get("longshot", {})
	var enhanced_multiplier := maxf(0.0, float(settings.get("enhanced_damage_multiplier", 1.0))) if enhanced else 1.0
	return maxf(0.0, float(settings.get("damage", 0.0))) * distance_multiplier(distance, settings) * enhanced_multiplier * maxf(0.0, power)
