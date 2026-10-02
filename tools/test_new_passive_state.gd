extends SceneTree

const PASSIVE := preload("res://scripts/passive_state.gd")
const COMBAT := preload("res://scripts/combat_state.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []

class Target extends Node3D:
	var state = preload("res://scripts/combat_state.gd").new()
	func get_max_health() -> float:
		return state.max_health
	func apply_spotted(duration: float, source: String) -> void:
		state.apply_spotted(duration, source)
	func apply_slow(duration: float, percent: float, source: String) -> void:
		state.apply_slow(duration, percent, source)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	var a := Target.new()
	var b := Target.new()
	root.add_child(a)
	root.add_child(b)
	_test_reactor(a, b)
	_test_tracker(a, b)
	_test_alternator()
	_test_inertia(a, b)
	_test_lifecycle(a)
	_test_catalog()
	for failure in failures:
		push_error(failure)
	print("FOUR PASSIVE STATE: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_reactor(a: Node, b: Node) -> void:
	var state := PASSIVE.new()
	state.configure("auxiliary_reactor")
	var volley := state.emit_weapon()
	check(is_equal_approx(state.weapon_hit(a, 10.0, volley, 5.0), 0.60), "Reactor: active cooldown")
	state.process(1.0)
	check(state.weapon_hit(b, 10.0, volley, 4.0) == 0.0, "Reactor: one proc per multi-target volley")
	check(state.weapon_hit(a, 10.0, state.emit_weapon(), 4.0) == 0.60, "Reactor: interval expires")
	check(state.weapon_hit(a, 10.0, state.emit_weapon(), 4.0) == 0.0, "Reactor: interval blocks new attacks")
	state.process(0.75)
	var ready_hit := state.emit_weapon()
	check(state.weapon_hit(a, 10.0, ready_hit, 0.0) == 0.0 and state.reactor_remaining == 0.0, "Reactor: no banked credit")
	check(state.weapon_hit(b, 10.0, ready_hit, 3.0) == 0.0, "Reactor: no delayed proc when module becomes unavailable")
	check(is_equal_approx(state.weapon_hit(a, 10.0, state.emit_weapon(), 0.1), 0.1), "Reactor: clamps at zero")
	state.reset()
	check(state.weapon_hit(a, 0.0, state.emit_weapon(), 2.0) == 0.0, "Reactor: invulnerability / counter / rejected impact")
	check(state.weapon_hit(a, 10.0, {}, 2.0) == 0.0, "Reactor: secondary damage has no attack context")


func _test_tracker(a: Target, b: Target) -> void:
	a.state.reset()
	var state := PASSIVE.new()
	state.configure("tracker")
	var volley := state.emit_weapon()
	for pellet in 6:
		state.weapon_hit(a, 10.0, volley, 0.0)
	check(state.tracker_count == 1, "Tracker: six pellets are one attack")
	state.weapon_hit(b, 10.0, state.emit_weapon(), 0.0)
	check(state.tracker_count == 1, "Tracker: target switch restarts")
	state.weapon_hit(a, 10.0, volley, 0.0)
	check(state.tracker_count == 1, "Tracker: repeated collision cannot restart old attack")
	state.process(4.01)
	check(state.tracker_count == 0, "Tracker: gap expiry")
	a.state.apply_spotted(8.0, "other")
	for hit in 2:
		state.weapon_hit(a, 10.0, state.emit_weapon(), 0.0)
	check(state.tracker_count == 0 and state.reveal_remaining() == 6.0, "Tracker: two distinct attacks reveal and reset")
	check(a.state.get_remaining("SPOTTED") >= 8.0, "Tracker: longer SPOTTED preserved")
	state.process(1.0)
	state.weapon_hit(a, 10.0, state.emit_weapon(), 0.0)
	check(state.tracker_count == 0 and state.reveal_remaining() == 5.0, "Tracker: no accumulation or extension while revealed")
	state.process(5.01)
	state.weapon_hit(a, 10.0, state.emit_weapon(), 0.0)
	check(state.tracker_count == 1, "Tracker: new sequence after own reveal expiry")
	state.process(3.0) # A miss does not call weapon_hit and does not erase progress.
	check(state.tracker_count == 1, "Tracker: missed input keeps gap running")
	state.weapon_hit(a, 10.0, state.emit_weapon(), 0.0)
	check(state.reveal_remaining() == 6.0, "Tracker: second successful hit reveals")
	state.reset()
	state.weapon_hit(a, 10.0, state.emit_weapon(), 0.0)
	state.process(4.0)
	state.weapon_hit(a, 10.0, state.emit_weapon(), 0.0)
	check(state.reveal_remaining() == 6.0, "Tracker: exactly four seconds remains admissible")


func _test_alternator() -> void:
	var state := PASSIVE.new()
	state.configure("alternator")
	var old := state.emit_weapon()
	state.register_module("wave:1")
	state.module_hit("wave:1", 10.0)
	state.process(1.0)
	state.module_hit("wave:1", 10.0)
	check(state.alternator_remaining == 2.0, "Alternator: outbound/return do not refresh same activation")
	check(float(old.multiplier) == 1.0, "Alternator: old projectile unchanged")
	# No emission on rejected/cancelled input.
	check(state.alternator_remaining > 0.0, "Alternator: rejected input preserves readiness")
	var shot := state.emit_weapon()
	check(is_equal_approx(float(shot.multiplier), 1.30) and state.alternator_remaining == 0.0, "Alternator: emission consumes bonus")
	state.process(4.0)
	check(is_equal_approx(float(shot.multiplier), 1.30), "Alternator: in-flight bonus frozen")
	state.module_hit("wave:1", 10.0)
	check(state.alternator_remaining == 0.0, "Alternator: consumed activation never rearms")
	state.register_module("wave:2")
	state.module_hit("wave:2", 0.0)
	check(state.alternator_remaining == 0.0, "Alternator: blocked module hit excluded")
	state.module_hit("wave:2", 10.0)
	state.process(1.0)
	state.register_module("wave:3")
	state.module_hit("wave:3", 10.0)
	check(state.alternator_remaining == 3.0, "Alternator: new activation refreshes without stacking")
	state.process(3.01)
	check(float(state.emit_weapon().multiplier) == 1.0, "Alternator: expiry")


func _test_inertia(a: Target, b: Target) -> void:
	a.state.reset()
	b.state.reset()
	var state := PASSIVE.new()
	state.configure("inertia")
	state.dash_finished(false)
	check(state.inertia_remaining == 0.0, "Inertia: refused/interrupted dash")
	var old := state.emit_weapon()
	state.dash_finished(true)
	state.process(1.0)
	state.dash_finished(true)
	check(state.inertia_remaining == 2.5, "Inertia: refresh without charges")
	var shot := state.emit_weapon()
	check(bool(shot.slow) and not bool(old.slow) and state.inertia_remaining == 0.0, "Inertia: snapshot and consumption")
	a.state.apply_slow(4.0, 50.0, "stronger")
	state.weapon_hit(a, 10.0, shot, 0.0)
	check(a.state.get_slow_percent() == 50.0, "Inertia: stronger slow preserved")
	state.weapon_hit(b, 10.0, shot, 0.0)
	check(b.state.get_slow_percent() == 25.0, "Inertia: cleave applies to every accepted target")
	b.state.update(1.3)
	state.weapon_hit(b, 10.0, shot, 0.0)
	check(b.state.get_remaining("SLOW") < 0.21, "Inertia: repeated pellet does not refresh slow")
	state.dash_finished(true)
	state.process(2.51)
	check(not bool(state.emit_weapon().slow), "Inertia: execution window expires")
	b.state.reset()
	state.dash_finished(true)
	var frozen := state.emit_weapon()
	state.tuning.slow_percent = 80.0
	state.process(3.0)
	state.real_dead = true
	state.clear_triggers()
	state.weapon_hit(b, 10.0, frozen, 0.0)
	check(b.state.get_slow_percent() == 25.0, "Inertia: emitted effect is frozen across expiry and owner death")


func _test_lifecycle(a: Node) -> void:
	var state := PASSIVE.new()
	state.configure("inertia")
	state.dash_finished(true)
	var pending := state.emit_weapon()
	state.reset()
	check(state.weapon_hit(a, 10.0, pending, 1.0) == 0.0, "Lifecycle: old attacks cannot trigger after respawn")
	state.dash_finished(true)
	state.configure("tracker")
	check(state.inertia_remaining == 0.0 and state.tracker_count == 0, "Lifecycle: equipment change clears state")
	state.real_dead = true
	state.register_module("dead")
	state.module_hit("dead", 10.0)
	check(state.alternator_remaining == 0.0, "Lifecycle: dead actors cannot trigger")


func _test_catalog() -> void:
	for id in ["auxiliary_reactor", "tracker", "alternator", "inertia"]:
		var build := LOADOUT.defaults()
		build.passive = id
		check(LOADOUT.is_valid(build), "Catalog: " + id)
		check(LOADOUT.save_local(build, "user://test_four_passives.cfg"), "Save: " + id)
		check(LOADOUT.load_local("user://test_four_passives.cfg").passive == id, "Load: " + id)
		check(LOADOUT.category_description(id).length() > 50, "Description: " + id)
	check(LOADOUT.sanitize({"passive": "omnivamp"}).passive == "omnivamp", "Old save compatibility")
	check(LOADOUT.sanitize({"passive": "invalid"}).passive == "baroud", "Invalid save fallback")
