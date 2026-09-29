extends "res://scripts/combat_state.gd"

const PASSIVE := preload("res://scripts/passive_state.gd")
var passive = PASSIVE.new()
var blocked: Callable

func reset() -> void:
	passive.reset()
	super.reset()

func apply_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if _dead or amount <= 0.0 or (blocked.is_valid() and bool(blocked.call())):
		return 0.0
	if attack_id != "" and _processed_attack_ids.has(attack_id):
		return 0.0
	var result: Dictionary = passive.intercept_damage(amount, health)
	if bool(result.triggered_baroud):
		if attack_id != "":
			_processed_attack_ids[attack_id] = true
		health_changed.emit(passive.baroud_health, passive.baroud_max_health)
		return 0.0
	var effective := float(result.effective)
	if passive.baroud_active or (passive.baroud_used and passive.real_dead and health > 0.0):
		if attack_id != "":
			_processed_attack_ids[attack_id] = true
		if effective > 0.0:
			damage_applied.emit(effective, source_id, attack_id)
		health_changed.emit(passive.baroud_health, passive.baroud_max_health)
		if passive.real_dead:
			_finalize_baroud()
		return effective
	return super.apply_damage(amount, source_id, attack_id)

func heal(amount: float, source_id: String = "") -> float:
	if not passive.can_heal() or (blocked.is_valid() and bool(blocked.call())):
		return 0.0
	return super.heal(amount, source_id)

func update(delta: float, burn_blocked: bool = false) -> void:
	var stasis := blocked.is_valid() and bool(blocked.call())
	super.update(delta, burn_blocked or stasis)
	if passive.process(delta):
		_finalize_baroud()
	elif passive.baroud_active:
		health_changed.emit(passive.baroud_health, passive.baroud_max_health)

func _finalize_baroud() -> void:
	if _dead:
		return
	health = 0.0
	_dead = true
	health_changed.emit(0.0, max_health)
	died.emit()

func display_health() -> float:
	return passive.baroud_health if passive.baroud_active else health

func display_max_health() -> float:
	return passive.baroud_max_health if passive.baroud_active else max_health
