extends "res://scripts/combat_state.gd"

## Only the host advances health. Clients keep the same presentation and timers.
var authoritative := true


func apply_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	return super.apply_damage(amount, source_id, attack_id) if authoritative else 0.0


func heal(amount: float, source_id: String = "") -> float:
	return super.heal(amount, source_id) if authoritative else 0.0


func grant_shield(amount: float, duration: float) -> void:
	if authoritative:
		super.grant_shield(amount, duration)


func absorb_shield_damage(amount: float) -> float:
	return super.absorb_shield_damage(amount) if authoritative else amount


func snapshot() -> Dictionary:
	var effects := _effects.duplicate(true)
	for effect in effects.values():
		effect.end_time = maxf(0.0, float(effect.end_time) - simulation_time)
		effect.erase("next_damage_time")
	var slows := _slow_effects.duplicate(true)
	for slow in slows:
		slow.end_time = maxf(0.0, float(slow.end_time) - simulation_time)
	return {"health": health, "maximum": max_health, "dead": _dead, "effects": effects, "slows": slows, "shield_health": shield_health, "shield_remaining": shield_remaining,
		"stun_repeats": _stun_repeats, "stun_chain": maxf(0.0, _stun_chain_until - simulation_time),
		"stun_recovery": maxf(0.0, _stun_recovery_until - simulation_time), "stun_limit": maxf(0.0, _stun_continuous_limit - simulation_time)}


func receive_snapshot(value: Dictionary) -> void:
	if authoritative:
		return
	var previous := health
	max_health = float(value.maximum)
	health = float(value.health)
	_dead = bool(value.dead)
	_stun_repeats = int(value.get("stun_repeats", 0))
	_stun_chain_until = simulation_time + float(value.get("stun_chain", 0.0))
	_stun_recovery_until = simulation_time + float(value.get("stun_recovery", 0.0))
	_stun_continuous_limit = simulation_time + float(value.get("stun_limit", 0.0))
	shield_health = maxf(0.0, float(value.get("shield_health", 0.0))) if not _dead else 0.0
	shield_remaining = maxf(0.0, float(value.get("shield_remaining", 0.0))) if shield_health > 0.0 else 0.0
	if shield_remaining <= 0.0:
		shield_health = 0.0
	shield_changed.emit(shield_health, shield_remaining)
	_effects = value.effects.duplicate(true)
	for effect in _effects.values():
		effect.end_time = simulation_time + float(effect.end_time)
		effect.next_damage_time = simulation_time
	_slow_effects = value.slows.duplicate(true)
	for slow in _slow_effects:
		slow.end_time = simulation_time + float(slow.end_time)
	health_changed.emit(health, max_health)
	if previous > health:
		damage_applied.emit(previous - health, "network", "")
	elif health > previous:
		healing_applied.emit(health - previous, "network")
