extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node_or_null("Interface")
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if flow == null or player == null or target == null:
		_failures.append("flow ou acteur manquant")
	else:
		if int(flow.get("current_screen")) != 0:
			_failures.append("écran menu absent au démarrage")
		var selected := {"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"}
		flow.set("loadout", selected)
		flow.call("_start_duel")
		await process_frame
		if int(flow.get("current_screen")) != 3:
			_failures.append("le duel ne démarre pas depuis l'équipement")
		if not bool(player.call("is_gameplay_enabled")):
			_failures.append("joueur encore verrouillé en duel")
		if str(player.call("get_weapon_id")) != "shotgun":
			_failures.append("arme de départ non transmise")
		if str(player.call("get_offensive_module_id")) != "javelin":
			_failures.append("module offensif non transmis")
		flow.call("_toggle_pause")
		if not paused:
			_failures.append("pause non activée")
		flow.call("_resume")
		if paused:
			_failures.append("pause non levée")
		target.call("take_damage", 1000.0, "test", "flow_death")
		await process_frame
		await process_frame
		if int(flow.get("current_screen")) != 4:
			_failures.append("écran résultat absent après mort réelle")
		flow.call("_restart")
		await process_frame
		if int(flow.get("current_screen")) != 3 or float(target.call("get_health")) < 999.0:
			_failures.append("rejouer ne réinitialise pas la manche")
	if _failures.is_empty():
		print("P0-125 GAME FLOW TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-125 GAME FLOW TEST: FAIL (%d)" % _failures.size())
		quit(1)
