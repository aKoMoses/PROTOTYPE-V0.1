extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var target: Node = scene.get_node_or_null("TargetDummy")
	if target == null:
		_failures.append("TargetDummy introuvable")
	else:
		var initial_effects: Array = target.call("get_active_effect_types")
		if not initial_effects.is_empty():
			_failures.append("mannequin contaminé au démarrage: %s" % str(initial_effects))
		for visual_name in ["BurnVisual", "SlowVisual", "SlowRing", "StunHalo", "SpottedEye", "SpottedEmblem"]:
			var visual := target.get_node_or_null(visual_name)
			if visual != null and visual.visible:
				_failures.append("visuel d'effet actif au démarrage: " + visual_name)
		target.call("apply_burn", 3.5, 20.0, "integration")
		target.call("apply_slow", 1.0, 30.0, "integration")
		target.call("apply_stun", 0.5, "integration")
		target.call("apply_spotted", 1.0, "integration")
		var active: Array = target.call("get_active_effect_types")
		for effect_type in ["BURN", "SLOW", "STUN", "SPOTTED"]:
			if not active.has(effect_type):
				_failures.append("effet mannequin absent: " + effect_type)
		await process_frame
		for visual_name in ["BurnVisual", "SlowVisual", "SlowRing", "StunHalo", "SpottedEye", "SpottedEmblem"]:
			var visual := target.get_node_or_null(visual_name)
			if visual != null and not visual.visible:
				_failures.append("visuel d'effet absent pendant l'effet: " + visual_name)
		for _frame in range(3):
			await process_frame
		if float(target.call("get_health")) >= 1000.0:
			_failures.append("BURN mannequin non observé")
		target.call("reset_combat_state")
		await process_frame
		if absf(float(target.call("get_health")) - 1000.0) > 0.05:
			_failures.append("reset mannequin ne restaure pas les PV")
		if not (target.call("get_active_effect_types") as Array).is_empty():
			_failures.append("reset mannequin conserve un effet")

	if _failures.is_empty():
		print("P0-102 TARGET DUMMY TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-102 TARGET DUMMY TEST: FAIL (%d)" % _failures.size())
		quit(1)
