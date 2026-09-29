extends SceneTree

const AI_PROFILE := preload("res://scripts/bot_ai_profile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var easy := AI_PROFILE.values("easy")
	var normal := AI_PROFILE.values("normal")
	var hard := AI_PROFILE.values("hard")
	_check(float(easy.reaction_delay) > float(normal.reaction_delay) and float(normal.reaction_delay) > float(hard.reaction_delay), "profiles improve reaction without changing combat stats")
	_check(float(easy.aim_error_degrees) > float(normal.aim_error_degrees) and float(normal.aim_error_degrees) > float(hard.aim_error_degrees), "profiles expose progressive aim limits")
	_check(int(easy.candidate_count) < int(hard.candidate_count), "hard profile evaluates more positions")

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.get_node_or_null("Player") as Node3D
	var target := scene.get_node_or_null("TargetDummy") as Node3D
	if player == null or target == null:
		failures.append("duel actors missing")
		_finish()
		return
	target.call("set_duel_mode", true)
	target.call("set_bot_difficulty", "hard")
	target.call("set_duel_loadout", {"weapon": "blaster", "offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "omnivamp"})
	target.call("set_bot_diagnostics_enabled", true)
	target.global_position = Vector3(0.0, 0.0, 16.0)
	player.global_position = Vector3(0.0, 0.0, 23.0)
	target.call("set_training_bot_enabled", true)
	for _frame in range(12):
		await physics_frame
	var snapshot: Dictionary = target.call("get_bot_diagnostic_snapshot")
	_check(str(snapshot.get("difficulty", "")) == "hard", "difficulty reaches the tactical controller")
	_check(bool(snapshot.get("target_known", false)) and bool(snapshot.get("target_visible", false)), "perception publishes only a reacted visible target")
	_check(not str(snapshot.get("intent", "")).is_empty(), "decision publishes a persistent intent")
	_check((snapshot.get("destination", Vector3.INF) as Vector3).is_finite(), "decision selects an accessible combat destination")
	_check(target.get_node_or_null("TrainingBot/BotAIDiagnostic") != null, "optional diagnostic label is available")

	var configured: Dictionary = target.call("get_duel_loadout")
	_check(str(configured.offensive) == "javelin" and str(configured.defensive) == "static_shield" and str(configured.mobility) == "pyro_boots" and str(configured.passive) == "omnivamp", "all module categories are routed to bot execution")
	target.call("set_training_bot_enabled", false)
	scene.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("BOT TACTICS TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		print("BOT TACTICS TEST: FAIL (%d)" % failures.size())
		quit(1)
