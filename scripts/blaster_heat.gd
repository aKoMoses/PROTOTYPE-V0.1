extends RefCounted

# Shared by players and bots. Delta time keeps cooling frozen during a pause.
const DEFINITION: Dictionary = preload("res://scripts/combat_data.gd").WEAPON_DEFINITIONS.blaster
var heat := 0.0
var cooling_delay := 0.0
var overheated := false

func reset() -> void:
	heat = 0.0
	cooling_delay = 0.0
	overheated = false

func commit_shot(charge_ratio: float) -> bool:
	if overheated or not is_finite(charge_ratio):
		return false
	heat = minf(float(DEFINITION.heat_capacity), heat + lerpf(float(DEFINITION.heat_per_shot), float(DEFINITION.heat_per_charged_shot), clampf(charge_ratio, 0.0, 1.0)))
	overheated = heat >= float(DEFINITION.heat_capacity) - 0.001
	# The last shot is emitted; full cooling starts immediately after overload.
	cooling_delay = 0.0 if overheated else float(DEFINITION.heat_cooling_delay)
	return true

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var cooling_time := maxf(0.0, delta - cooling_delay)
	cooling_delay = maxf(0.0, cooling_delay - delta)
	heat = maxf(0.0, heat - cooling_time * float(DEFINITION.heat_cooling_per_second))
	if heat <= 0.001:
		reset()

func fraction() -> float:
	return heat / float(DEFINITION.heat_capacity)

func remaining() -> float:
	return heat / float(DEFINITION.heat_cooling_per_second) if overheated else 0.0

func snapshot() -> Dictionary:
	return {"heat": heat, "delay": cooling_delay, "overheated": overheated}

func restore(value: Dictionary) -> void:
	var incoming_heat := float(value.get("heat", 0.0))
	var incoming_delay := float(value.get("delay", 0.0))
	if not is_finite(incoming_heat) or not is_finite(incoming_delay):
		return
	heat = clampf(incoming_heat, 0.0, float(DEFINITION.heat_capacity))
	overheated = heat > 0.001 and (bool(value.get("overheated", false)) or heat >= float(DEFINITION.heat_capacity))
	cooling_delay = 0.0 if overheated else clampf(incoming_delay, 0.0, float(DEFINITION.heat_cooling_delay))
