extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var targets: Array = scene.call("get_training_targets")
	var meter: Control = scene.get_node("TrainingUI/TrainingRoot/TrainingMeter")
	_check(is_equal_approx(float(meter.call("get_total_damage")), 0.0), "mesure vide au depart")
	targets[0].call("take_damage", 100.0, "player", "blaster:meter-test")
	targets[0].call("take_damage", 50.0, "player", "modulo_drone:meter-test")
	targets[0].call("take_damage", 40.0, "test", "not-player")
	_check(is_equal_approx(float(meter.call("get_total_damage")), 150.0), "seuls les degats joueur sont comptes")
	_check(is_equal_approx(float(meter.call("get_source_damage", "Blaster")), 100.0), "blaster classe")
	_check(is_equal_approx(float(meter.call("get_source_damage", "Drone")), 50.0), "drone classe")
	targets[0].call("apply_burn", 0.3, 100.0, "player:modulo_drone")
	await create_timer(0.35, true, false, false).timeout
	_check(float(meter.call("get_source_damage", "Brûlure")) > 0.0, "brulure reelle classee")
	targets[1].call("take_damage", 80.0, "player", "shotgun:meter-test")
	var all_damage := float(meter.call("get_total_damage"))
	meter.call("set_target_filter", targets[1])
	_check(is_equal_approx(float(meter.call("get_recent_dps")), 80.0), "dps filtre par cible")
	_check(is_equal_approx(float(meter.call("get_total_damage", targets[1])), 80.0), "total de la cible")
	meter.call("set_target_filter")
	_check(float(meter.call("get_recent_dps")) > 80.0, "dps toutes cibles")
	scene.call("_toggle_menu")
	_check(paused and not meter.visible, "menu masque le kikimetre")
	var paused_elapsed := float(meter.call("get_elapsed"))
	await create_timer(0.2, true, false, false).timeout
	_check(absf(float(meter.call("get_elapsed")) - paused_elapsed) < 0.01, "temps de mesure fige en pause")
	scene.call("_toggle_menu")
	_check(not paused and meter.visible, "kikimetre revient en jeu")
	var expanded := bool(meter.call("is_expanded"))
	_press_key(scene, KEY_K)
	_check(bool(meter.call("is_expanded")) != expanded, "raccourci K masque ou ouvre")
	_press_key(scene, KEY_K)
	targets[0].call("take_damage", 2000.0, "player", "shotgun:ko-test")
	_check(is_equal_approx(float(targets[0].call("get_health")), 0.0), "KO du mannequin")
	var after_ko := float(meter.call("get_total_damage"))
	_check(after_ko > all_damage, "degats effectifs du KO comptes")
	await create_timer(0.9, true, false, false).timeout
	_check(is_equal_approx(float(targets[0].call("get_health")), 1000.0), "mannequin regenere apres KO")
	_check(is_equal_approx(float(meter.call("get_total_damage")), after_ko), "regen ne vide pas la mesure")
	scene.call("_reset_trial")
	_check(is_equal_approx(float(meter.call("get_total_damage")), 0.0), "F5 vide la mesure")
	_check(is_equal_approx(float(meter.call("get_elapsed")), 0.0), "F5 remet le temps a zero")
	if failures.is_empty():
		print("TRAINING METER TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		print("TRAINING METER TEST: FAIL (%d)" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _press_key(scene: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	scene.call("_input", event)
