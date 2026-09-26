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
		if str(flow.call("get_round_phase_name")) != "COUNTDOWN":
			_failures.append("le décompte de manche n'est pas actif")
		if bool(player.call("is_gameplay_enabled")):
			_failures.append("joueur actif pendant le décompte")
		var countdown_before_pause := float(flow.get("_countdown_remaining"))
		flow.call("_toggle_pause")
		await process_frame
		if absf(float(flow.get("_countdown_remaining")) - countdown_before_pause) > 0.01:
			_failures.append("pause n'arrête pas le décompte")
		flow.call("_resume")
		if str(player.call("get_weapon_id")) != "shotgun":
			_failures.append("arme de départ non transmise")
		if str(player.call("get_offensive_module_id")) != "javelin":
			_failures.append("module offensif non transmis")
		flow.call("_begin_live_round")
		await process_frame
		if str(flow.call("get_round_phase_name")) != "LIVE" or not bool(player.call("is_gameplay_enabled")):
			_failures.append("la manche ne passe pas en combat actif")
		flow.call("_toggle_pause")
		if not bool(flow.get("_pause_active")):
			_failures.append("pause non activée")
		flow.call("_resume")
		if bool(flow.get("_pause_active")):
			_failures.append("pause non levée")
		flow.call("resolve_round", false, true)
		await process_frame
		if str(flow.call("get_round_phase_name")) != "ROUND_RESULT":
			_failures.append("résultat de manche absent après mort réelle")
		var score: Vector2i = flow.call("get_match_score")
		if score != Vector2i(1, 0):
			_failures.append("score de victoire incorrect: %s" % score)
		var result_before_pause := float(flow.get("_round_result_remaining"))
		flow.call("_toggle_pause")
		await process_frame
		if absf(float(flow.get("_round_result_remaining")) - result_before_pause) > 0.01:
			_failures.append("pause n'arrête pas le résultat de manche")
		flow.call("_resume")
		flow.call("resolve_round", false, true)
		var duplicate_score: Vector2i = flow.call("get_match_score")
		if duplicate_score != Vector2i(1, 0):
			_failures.append("un même résultat incrémente deux fois")
		flow.set("_round_result_remaining", 0.0)
		flow.call("_start_next_round")
		if str(flow.call("get_round_phase_name")) != "COUNTDOWN" or float(target.call("get_health")) < 999.0:
			_failures.append("la manche suivante ne réinitialise pas les PV")
		flow.call("_begin_live_round")
		flow.call("resolve_round", true, true)
		var tie_score: Vector2i = flow.call("get_match_score")
		if tie_score != Vector2i(1, 0):
			_failures.append("une égalité attribue un point")
		flow.set("player_round_score", 2)
		flow.set("bot_round_score", 0)
		flow.set("round_phase", 2)
		flow.set("_round_resolved", false)
		flow.call("resolve_round", false, true)
		flow.set("_round_result_remaining", 0.0)
		flow.call("_start_next_round")
		if str(flow.call("get_round_phase_name")) != "MATCH_RESULT" or int(flow.get("current_screen")) != 4:
			_failures.append("le match ne se termine pas à trois victoires")
	if _failures.is_empty():
		print("V02-02 MATCH FLOW TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-125 GAME FLOW TEST: FAIL (%d)" % _failures.size())
		quit(1)
