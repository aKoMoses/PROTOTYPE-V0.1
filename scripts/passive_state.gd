class_name PassiveState
extends RefCounted

## Runtime state for the two mutually exclusive passive modules.
## The actor keeps its normal CombatState; Baroud owns only its temporary
## last-chance gauge and Omnivamp returns a heal amount from effective damage.

const BAROUD_MAX_HEALTH := 1000.0
const BAROUD_DURATION := 2.5
const BAROUD_DRAIN_PER_SECOND := 400.0
const OMNIVAMP_RATE := 0.15

var passive_id := "baroud"
var baroud_used := false
var baroud_active := false
var baroud_health := 0.0
var baroud_remaining := 0.0
var real_dead := false


func configure(next_passive_id: String) -> void:
	passive_id = "omnivamp" if next_passive_id == "omnivamp" else "baroud"


func reset() -> void:
	baroud_used = false
	baroud_active = false
	baroud_health = 0.0
	baroud_remaining = 0.0
	real_dead = false


func intercept_damage(amount: float, current_health: float, blocked: bool = false) -> Dictionary:
	var result := {"effective": 0.0, "triggered_baroud": false, "real_death": false}
	if blocked or amount <= 0.0 or real_dead:
		return result
	if baroud_active:
		var effective := minf(amount, baroud_health)
		baroud_health = maxf(0.0, baroud_health - effective)
		result["effective"] = effective
		if baroud_health <= 0.0:
			_end_baroud_as_death(result)
		return result
	if passive_id == "baroud" and not baroud_used and current_health > 0.0 and amount >= current_health:
		baroud_used = true
		baroud_active = true
		baroud_health = BAROUD_MAX_HEALTH
		baroud_remaining = BAROUD_DURATION
		result["triggered_baroud"] = true
		return result
	var effective_normal := minf(amount, maxf(0.0, current_health))
	result["effective"] = effective_normal
	if current_health - effective_normal <= 0.0:
		real_dead = true
		result["real_death"] = true
	return result


func process(delta: float) -> bool:
	if delta <= 0.0 or not baroud_active or real_dead:
		return false
	baroud_remaining = maxf(0.0, baroud_remaining - delta)
	baroud_health = maxf(0.0, baroud_health - BAROUD_DRAIN_PER_SECOND * delta)
	if baroud_remaining <= 0.0 or baroud_health <= 0.0:
		baroud_active = false
		baroud_health = 0.0
		real_dead = true
		return true
	return false


func can_heal() -> bool:
	return not baroud_active and not real_dead


func omnivamp_heal_for(effective_damage: float) -> float:
	if passive_id != "omnivamp" or effective_damage <= 0.0 or real_dead:
		return 0.0
	return effective_damage * OMNIVAMP_RATE


func _end_baroud_as_death(result: Dictionary) -> void:
	baroud_active = false
	baroud_health = 0.0
	baroud_remaining = 0.0
	real_dead = true
	result["real_death"] = true


static func resolve_simultaneous_death(left_dead: bool, right_dead: bool) -> String:
	if left_dead and right_dead:
		return "draw"
	if left_dead:
		return "right"
	if right_dead:
		return "left"
	return "none"
