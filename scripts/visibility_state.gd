class_name VisibilityState
extends RefCounted

## Shared reveal timers. Combat and SPOTTED are intentionally independent:
## combat reveals without drawing the SPOTTED eye, while SPOTTED can reveal a
## robot that has already left combat.

const COMBAT_DURATION := 3.0

var combat_remaining := 0.0
var spotted_remaining := 0.0


func reset() -> void:
	combat_remaining = 0.0
	spotted_remaining = 0.0


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	combat_remaining = maxf(0.0, combat_remaining - delta)
	spotted_remaining = maxf(0.0, spotted_remaining - delta)


func mark_combat_event() -> void:
	combat_remaining = COMBAT_DURATION


func mark_spotted(duration: float) -> void:
	spotted_remaining = maxf(spotted_remaining, maxf(0.0, duration))


func is_in_combat() -> bool:
	return combat_remaining > 0.0


func is_spotted() -> bool:
	return spotted_remaining > 0.0


func is_revealed() -> bool:
	return is_in_combat() or is_spotted()


static func visible_to_observer(revealed: bool, in_bush: bool, line_of_sight: bool) -> bool:
	if revealed:
		return true
	if in_bush:
		return false
	return line_of_sight
