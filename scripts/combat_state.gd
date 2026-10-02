class_name CombatState
extends RefCounted

signal health_changed(current: float, maximum: float)
signal damage_applied(amount: float, source_id: String, attack_id: String)
signal healing_applied(amount: float, source_id: String)
signal effect_changed(effect_type: String, active: bool)
signal died
signal reset_completed
signal shield_changed(current: float, remaining: float)

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const SLOW_EPSILON := 0.001
const STUN_REPEAT_WINDOW := 2.0
const STUN_RECOVERY_GRACE := 0.18
const STUN_MAX_EXTENSION := 0.35

var max_health: float
var health: float
var simulation_time := 0.0
var shield_health := 0.0
var shield_remaining := 0.0

var _effects: Dictionary = {}
var _slow_effects: Array = []
var _processed_attack_ids: Dictionary = {}
var _dead := false
var _burn_serial := 0
var _stun_chain_until := 0.0
var _stun_recovery_until := 0.0
var _stun_continuous_limit := 0.0
var _stun_repeats := 0
var processing_burn := false


func _init(health_max: float = COMBAT_DATA.MAX_HEALTH) -> void:
	max_health = maxf(1.0, health_max)
	health = max_health


func reset() -> void:
	clear_shield()
	simulation_time = 0.0
	health = max_health
	_dead = false
	_effects.clear()
	_slow_effects.clear()
	_processed_attack_ids.clear()
	_burn_serial = 0
	_stun_chain_until = 0.0
	_stun_recovery_until = 0.0
	_stun_continuous_limit = 0.0
	_stun_repeats = 0
	health_changed.emit(health, max_health)
	for effect_type in [COMBAT_DATA.EFFECT_BURN, COMBAT_DATA.EFFECT_SLOW, COMBAT_DATA.EFFECT_STUN, COMBAT_DATA.EFFECT_SPOTTED]:
		effect_changed.emit(effect_type, false)
	reset_completed.emit()


func apply_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if _dead or amount <= 0.0:
		return 0.0
	if attack_id != "":
		if _processed_attack_ids.has(attack_id):
			return 0.0
		_processed_attack_ids[attack_id] = true
	var effective := minf(absorb_shield_damage(amount), health)
	if effective <= 0.0:
		return 0.0
	health -= effective
	health_changed.emit(health, max_health)
	damage_applied.emit(effective, source_id, attack_id)
	if health <= 0.0:
		_dead = true
		clear_shield()
		died.emit()
	return effective


func grant_shield(amount: float, duration: float) -> void:
	if _dead or amount <= 0.0 or duration <= 0.0:
		return
	# Refresh protection without accumulating a pool on repeated activations.
	shield_health = maxf(shield_health, amount)
	shield_remaining = maxf(shield_remaining, duration)
	shield_changed.emit(shield_health, shield_remaining)


func clear_shield() -> void:
	shield_health = 0.0
	shield_remaining = 0.0
	shield_changed.emit(0.0, 0.0)


func absorb_shield_damage(amount: float) -> float:
	if amount <= 0.0 or shield_health <= 0.0 or shield_remaining <= 0.0:
		return amount
	var absorbed := minf(amount, shield_health)
	shield_health -= absorbed
	if shield_health <= 0.0:
		shield_remaining = 0.0
	shield_changed.emit(shield_health, shield_remaining)
	return amount - absorbed


func heal(amount: float, source_id: String = "") -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var effective := minf(amount, max_health - health)
	if effective <= 0.0:
		return 0.0
	health += effective
	health_changed.emit(health, max_health)
	healing_applied.emit(effective, source_id)
	return effective


func apply_burn(duration: float = COMBAT_DATA.BURN_DURATION, damage_per_second: float = COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	if _dead:
		return
	var existing: Dictionary = _effects.get(COMBAT_DATA.EFFECT_BURN, {})
	_burn_serial += 1
	var next_damage_time := simulation_time
	if not existing.is_empty():
		# Reapplication refreshes the end date but never grants a free tick or
		# moves the next tick earlier.
		next_damage_time = float(existing.get("next_damage_time", simulation_time))
	_effects[COMBAT_DATA.EFFECT_BURN] = {
		"end_time": maxf(float(existing.get("end_time", simulation_time)), simulation_time + maxf(0.0, duration)),
		"damage_per_second": maxf(0.0, damage_per_second),
		"next_damage_time": next_damage_time,
		"source_id": source_id,
		"serial": _burn_serial,
	}
	effect_changed.emit(COMBAT_DATA.EFFECT_BURN, true)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	if _dead or duration <= 0.0 or percent <= 0.0:
		return
	var clamped_percent := clampf(percent, 0.0, 100.0)
	var refreshed := false
	for slow in _slow_effects:
		if str(slow.get("source_id", "")) == source_id and absf(float(slow.get("percent", 0.0)) - clamped_percent) <= SLOW_EPSILON:
			slow["end_time"] = maxf(float(slow.get("end_time", simulation_time)), simulation_time + duration)
			refreshed = true
			break
	if not refreshed:
		_slow_effects.append({"end_time": simulation_time + duration, "percent": clamped_percent, "source_id": source_id})
	effect_changed.emit(COMBAT_DATA.EFFECT_SLOW, true)


func cleanse_burn_and_slow() -> void:
	# Purify only these ailments; shields, visibility and attack deduplication survive.
	if _effects.erase(COMBAT_DATA.EFFECT_BURN):
		effect_changed.emit(COMBAT_DATA.EFFECT_BURN, false)
	if not _slow_effects.is_empty():
		_slow_effects.clear()
		effect_changed.emit(COMBAT_DATA.EFFECT_SLOW, false)


func apply_stun(duration: float, source_id: String = "") -> void:
	if not can_receive_stun(duration):
		return
	if simulation_time >= _stun_chain_until:
		_stun_repeats = 0
	var adjusted := duration * pow(0.5, mini(_stun_repeats, 2))
	var existing_end := simulation_time + get_remaining(COMBAT_DATA.EFFECT_STUN)
	if not is_stunned():
		_stun_continuous_limit = simulation_time + adjusted + STUN_MAX_EXTENSION
	var end_time := minf(maxf(existing_end, simulation_time + adjusted), _stun_continuous_limit)
	_effects[COMBAT_DATA.EFFECT_STUN] = {"end_time": end_time, "source_id": source_id}
	_stun_repeats += 1
	_stun_chain_until = end_time + STUN_REPEAT_WINDOW
	_stun_recovery_until = end_time + STUN_RECOVERY_GRACE
	effect_changed.emit(COMBAT_DATA.EFFECT_STUN, true)


func can_receive_stun(duration: float) -> bool:
	return not _dead and duration > 0.0 and (is_stunned() or simulation_time >= _stun_recovery_until - SLOW_EPSILON)


func apply_spotted(duration: float, source_id: String = "") -> void:
	_apply_single_timed_effect(COMBAT_DATA.EFFECT_SPOTTED, duration, source_id)


func _apply_single_timed_effect(effect_type: String, duration: float, source_id: String) -> void:
	if _dead or duration <= 0.0:
		return
	var existing: Dictionary = _effects.get(effect_type, {})
	_effects[effect_type] = {
		"end_time": maxf(float(existing.get("end_time", simulation_time)), simulation_time + duration),
		"source_id": source_id,
	}
	effect_changed.emit(effect_type, true)


func update(delta: float, burn_blocked: bool = false) -> void:
	if delta <= 0.0:
		return
	var previous_time := simulation_time
	# Split a long frame at expiry so burn after expiry reaches normal health.
	var protected_delta := minf(delta, shield_remaining) if shield_health > 0.0 else 0.0
	if protected_delta > 0.0:
		simulation_time += protected_delta
		_process_burn(previous_time, burn_blocked)
		shield_remaining = maxf(0.0, shield_remaining - protected_delta)
		if shield_remaining <= 0.0:
			clear_shield()
		previous_time = simulation_time
	if delta > protected_delta:
		simulation_time += delta - protected_delta
		_process_burn(previous_time, burn_blocked)
	_process_slow_expiration()
	_process_single_expiration(COMBAT_DATA.EFFECT_STUN)
	_process_single_expiration(COMBAT_DATA.EFFECT_SPOTTED)


func _process_burn(previous_time: float, burn_blocked: bool) -> void:
	if not _effects.has(COMBAT_DATA.EFFECT_BURN):
		return
	var burn: Dictionary = _effects[COMBAT_DATA.EFFECT_BURN]
	var end_time := float(burn.get("end_time", simulation_time))
	var from_time := maxf(previous_time, float(burn.get("next_damage_time", previous_time)))
	var until_time := minf(simulation_time, end_time)
	if until_time > from_time:
		var elapsed := until_time - from_time
		if not burn_blocked:
			processing_burn = true
			apply_damage(float(burn.get("damage_per_second", 0.0)) * elapsed, str(burn.get("source_id", "")))
			processing_burn = false
		burn["next_damage_time"] = until_time
	if simulation_time >= end_time - SLOW_EPSILON:
		_effects.erase(COMBAT_DATA.EFFECT_BURN)
		effect_changed.emit(COMBAT_DATA.EFFECT_BURN, false)


func _process_slow_expiration() -> void:
	var had_slow := not _slow_effects.is_empty()
	var kept: Array = []
	for slow in _slow_effects:
		if simulation_time < float(slow.get("end_time", 0.0)) - SLOW_EPSILON:
			kept.append(slow)
	_slow_effects = kept
	if had_slow and _slow_effects.is_empty():
		effect_changed.emit(COMBAT_DATA.EFFECT_SLOW, false)


func _process_single_expiration(effect_type: String) -> void:
	if not _effects.has(effect_type):
		return
	if simulation_time >= float(_effects[effect_type].get("end_time", 0.0)) - SLOW_EPSILON:
		_effects.erase(effect_type)
		effect_changed.emit(effect_type, false)


func has_effect(effect_type: String) -> bool:
	if effect_type == COMBAT_DATA.EFFECT_SLOW:
		return not _slow_effects.is_empty()
	return _effects.has(effect_type)


func is_stunned() -> bool:
	return has_effect(COMBAT_DATA.EFFECT_STUN)


func is_spotted() -> bool:
	return has_effect(COMBAT_DATA.EFFECT_SPOTTED)


func get_slow_percent() -> float:
	var strongest := 0.0
	var rocket_stacks := 0.0
	for slow in _slow_effects:
		if str(slow.get("source_id", "")).begins_with("rocket_stack:"):
			rocket_stacks += float(slow.get("percent", 0.0))
		else:
			strongest = maxf(strongest, float(slow.get("percent", 0.0)))
	return clampf(maxf(strongest, rocket_stacks), 0.0, 100.0)


func get_active_effect_types() -> Array[String]:
	var active: Array[String] = []
	for effect_type in [COMBAT_DATA.EFFECT_BURN, COMBAT_DATA.EFFECT_SLOW, COMBAT_DATA.EFFECT_STUN, COMBAT_DATA.EFFECT_SPOTTED]:
		if has_effect(effect_type):
			active.append(effect_type)
	return active


func get_remaining(effect_type: String) -> float:
	if effect_type == COMBAT_DATA.EFFECT_SLOW:
		var longest := 0.0
		for slow in _slow_effects:
			longest = maxf(longest, float(slow.get("end_time", simulation_time)) - simulation_time)
		return maxf(0.0, longest)
	if not _effects.has(effect_type):
		return 0.0
	return maxf(0.0, float(_effects[effect_type].get("end_time", simulation_time)) - simulation_time)


func is_dead() -> bool:
	return _dead
