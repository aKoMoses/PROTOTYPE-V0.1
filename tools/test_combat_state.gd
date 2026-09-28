extends SceneTree

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const COMBAT_STATE := preload("res://scripts/combat_state.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var state := COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH)
	var healing_events: Array[float] = []
	state.healing_applied.connect(func(amount: float, _source_id: String) -> void: healing_events.append(amount))
	_assert_close(state.health, 1000.0, "initial PV")
	_assert_close(state.apply_damage(200.0, "test", "attack-1"), 200.0, "damage effective")
	_assert_close(state.health, 800.0, "damage reduces PV")
	_assert_close(state.apply_damage(200.0, "test", "attack-1"), 0.0, "duplicate attack ignored")
	_assert_close(state.apply_damage(1000.0, "test", "attack-overkill"), 800.0, "overkill clamped")
	_assert_close(state.health, 0.0, "PV reaches zero")
	state.reset()
	_assert_close(state.health, 1000.0, "reset restores PV")
	_assert_close(state.heal(0.0), 0.0, "zero heal ignored")
	_assert_close(state.heal(100.0, "full-health-kit"), 0.0, "full health heal ignored")
	state.apply_damage(500.0)
	_assert_close(state.heal(400.0, "health-kit"), 400.0, "effective heal")
	_assert_close(state.heal(400.0, "health-kit"), 100.0, "overheal clamped")
	_assert_close(state.health, state.max_health, "healing never exceeds maximum")
	if healing_events.size() != 2 or not is_equal_approx(healing_events[0], 400.0) or not is_equal_approx(healing_events[1], 100.0):
		_failures.append("healing signal emitted more than once or at full health")

	state.reset()
	state.apply_burn(3.5, 20.0, "burn-a")
	for _step in range(35):
		state.update(0.1)
	_assert_close(state.health, 930.0, "isolated BURN deals 70")
	state.apply_burn(3.5, 20.0, "burn-b")
	for _step in range(35):
		state.update(0.1)
	_assert_close(state.health, 860.0, "BURN refresh does not double DPS")

	state.reset()
	state.apply_slow(0.4, 30.0, "strong")
	state.apply_slow(1.0, 10.0, "weak")
	_assert_close(state.get_slow_percent(), 30.0, "strongest slow applies")
	state.update(0.5)
	_assert_close(state.get_slow_percent(), 10.0, "weaker slow resumes")
	state.update(0.6)
	_assert_close(state.get_slow_percent(), 0.0, "slow expires")

	state.apply_stun(0.5, "stun")
	state.apply_spotted(0.8, "spot")
	if not state.is_stunned() or not state.is_spotted():
		_failures.append("STUN/SPOTTED activation")
	state.update(0.6)
	if state.is_stunned() or not state.is_spotted():
		_failures.append("STUN/SPOTTED expiration ordering")
	state.update(0.3)
	if state.is_spotted():
		_failures.append("SPOTTED expiration")

	state.reset()
	state.apply_burn(1.0, 20.0, "stasis")
	state.update(0.75, true)
	_assert_close(state.health, 1000.0, "stasis blocks BURN damage")
	state.update(0.25, false)
	_assert_close(state.health, 995.0, "blocked BURN time is not banked")

	if _failures.is_empty():
		print("P0-101/102 COMBAT STATE TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-101/102 COMBAT STATE TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.05:
		_failures.append("%s: expected %.3f, got %.3f" % [label, expected, actual])
