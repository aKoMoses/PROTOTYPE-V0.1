class_name LongshotState
extends RefCounted

## Two successful normal shots prepare EXECUTION. Misses preserve progress.
const COMBAT_DATA := preload("res://scripts/combat_data.gd")

var shots_fired: int = 0
var hits: int = 0
var speed_remaining := 0.0
var generation := 0
var _credited_shots: Dictionary = {}


func normal_shots() -> int:
	return hits


func is_enhanced_ready() -> bool:
	return hits >= 2


func next_enhanced() -> bool:
	return is_enhanced_ready()


func commit_shot() -> bool:
	var enhanced := next_enhanced()
	shots_fired += 1
	if enhanced:
		hits = 0
	return enhanced


func register_hit(shot_id: String, enhanced: bool, definition: Dictionary = {}) -> bool:
	if _credited_shots.has(shot_id):
		return false
	_credited_shots[shot_id] = true
	# Bound history without dropping any of the recent in-flight attacks.
	if _credited_shots.size() > 64:
		_credited_shots.erase(_credited_shots.keys()[0])
	if not enhanced:
		hits = mini(2, hits + 1)
	var settings: Dictionary = definition if not definition.is_empty() else COMBAT_DATA.WEAPON_DEFINITIONS.longshot
	speed_remaining = float(settings.hit_speed_duration)
	return true


func tick(delta: float) -> void:
	speed_remaining = maxf(0.0, speed_remaining - delta)


func movement_multiplier() -> float:
	return float(COMBAT_DATA.WEAPON_DEFINITIONS.longshot.hit_speed_multiplier) if speed_remaining > 0.0 else 1.0


func reset() -> void:
	shots_fired = 0
	hits = 0
	speed_remaining = 0.0
	generation += 1
	_credited_shots.clear()


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
