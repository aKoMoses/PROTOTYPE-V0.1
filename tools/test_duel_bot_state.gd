extends SceneTree

const STATE := preload("res://scripts/duel_bot_state.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var state := STATE.new(800.0)
	state.passive.configure("baroud")
	check(state.apply_damage(900, "player", "lethal") == 0 and state.passive.baroud_active and not state.is_dead(), "lethal damage triggers Baroud")
	var before: float = state.passive.baroud_health
	state.apply_damage(900, "player", "lethal")
	check(state.passive.baroud_health == before, "duplicate lethal hit ignored")
	check(state.heal(100) == 0, "Baroud rejects healing")
	check(state.apply_damage(40, "player", "gauge") == 40, "Baroud damage uses gauge")
	state.blocked = func() -> bool: return true
	check(state.apply_damage(80, "player", "blocked") == 0, "stasis blocks damage")
	state.update(2.6)
	check(state.is_dead(), "stasis does not extend Baroud")
	state.blocked = Callable()
	state.reset()
	state.apply_burn(10, 1000, "player")
	state.update(0.9)
	check(state.passive.baroud_active and not state.is_dead(), "burn triggers Baroud")
	state.reset()
	state.passive.configure("omnivamp")
	state.apply_damage(100)
	check(state.passive.omnivamp_heal_for(20) == 3, "Omnivamp rate")
	check(state.heal(900) == 100 and state.health == 800, "healing uses effective health")
	if failures.is_empty():
		print("DUEL BOT STATE TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
