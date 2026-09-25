extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player ou TargetDummy introuvable")
	else:
		if player.get_node_or_null("WorldUIAnchor/PlayerHealthBarFill") == null or player.get_node_or_null("WorldUIAnchor/PlayerHealthLabel") == null:
			_failures.append("barre de PV joueur absente")
		if bool(target.call("is_training_bot_enabled")):
			_failures.append("bot actif au démarrage")
		if not (target.call("get_active_effect_types") as Array).is_empty():
			_failures.append("effets actifs au démarrage du bot")
		var start_position := (target as Node3D).global_position
		target.call("set_training_bot_enabled", true)
		if not bool(target.call("is_training_bot_enabled")):
			_failures.append("activation du bot refusée")
		player.call("_perform_axe_attack")
		var dodge_seen := false
		for _dodge_step in range(8):
			await physics_frame
			if bool(target.get_node("TrainingBot").call("is_dodging")):
				dodge_seen = true
				break
		if not dodge_seen:
			_failures.append("bot n'esquive pas une attaque engagée")
		var telegraph_seen := false
		for _step in range(24):
			await create_timer(0.10, true, false, false).timeout
			if bool(target.get_node("TrainingBot").call("is_telegraph_active")):
				telegraph_seen = true
				break
		if not telegraph_seen:
			_failures.append("télégraphe absent avant l'attaque")
		else:
			await create_timer(0.70, true, false, false).timeout
		var moved_distance := start_position.distance_to((target as Node3D).global_position)
		if moved_distance < 0.03:
			_failures.append("bot immobile après activation")
		if float(player.call("get_health")) >= float(player.call("get_max_health")):
			_failures.append("bot n'inflige aucun dégât lisible")
		var health_fill := player.get_node_or_null("WorldUIAnchor/PlayerHealthBarFill")
		if health_fill != null and float(health_fill.scale.x) >= 2.8:
			_failures.append("barre de PV joueur non synchronisée")
		if not (target.call("get_active_effect_types") as Array).is_empty():
			_failures.append("bot applique un effet de statut automatiquement")
		if bool(target.get_node("TrainingBot").call("is_telegraph_active")):
			_failures.append("télégraphe encore actif après résolution")
		target.call("set_training_bot_enabled", false)
		player.call("reset_combat_state")
		target.call("reset_combat_state")

	if _failures.is_empty():
		print("P0-114 TRAINING BOT TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-114 TRAINING BOT TEST: FAIL (%d)" % _failures.size())
		quit(1)
