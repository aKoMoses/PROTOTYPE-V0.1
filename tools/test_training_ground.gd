extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player := scene.get_node("Player")
	var spell_bar := scene.get_node_or_null("TrainingUI/TrainingRoot/SpellBar")
	_check(spell_bar != null, "barre de sorts presente dans le terrain")
	if spell_bar != null:
		_check(spell_bar.visible, "barre de sorts visible pendant l'essai")
		_check(spell_bar.get_node("OffensiveSlot/ModuleName").text == preload("res://scripts/loadout_state.gd").display_name(str(player.call("get_offensive_module_id"))), "sort offensif du build affiche")
		player.call("_start_module_cooldown", str(player.call("get_offensive_module_id")), 2.0)
		scene.call("_update_spell_bar")
		_check(spell_bar.get_node("OffensiveSlot/Status").text != "PRÊT", "cooldown offensif affiche")
		player.call("reset_combat_state")
		scene.call("_update_spell_bar")
		_check(spell_bar.get_node("OffensiveSlot/Status").text == "PRÊT", "sort pret apres reset")
	var targets: Array = scene.call("get_training_targets")
	_check(targets.size() == 5, "trois mannequins fixes, un mobile et un tireur")
	_check(scene.get_node_or_null("FixedZone") != null and scene.get_node_or_null("MovingZone") != null and scene.get_node_or_null("ShooterZone") != null and scene.get_node_or_null("PlacementZone") != null, "quatre zones de travail identifiables")
	if targets.size() == 5:
		for index in range(4):
			for other in range(index + 1, 5):
				_check(targets[index].global_position.distance_to(targets[other].global_position) >= 8.0, "mannequins espaces %d/%d" % [index, other])
		_check(is_equal_approx(float(targets[0].call("get_training_hit_radius")), 0.78 * 0.65), "petite hitbox")
		_check(is_equal_approx(float(targets[2].call("get_training_hit_radius")), 0.78 * 1.5), "grande hitbox")
		var shooter: Node = targets[4]
		_check(bool(shooter.call("is_training_bot_enabled")), "tireur actif")
		_check(bool(shooter.get_node("TrainingBot").get("training_stationary")), "tireur fixe")
		var shooter_position: Vector3 = shooter.global_position
		var mover_position: Vector3 = targets[3].global_position
		var spawn_position: Vector3 = player.global_position
		player.global_position = shooter_position + Vector3(0.0, 0.0, 6.5)
		await create_timer(2.8, true, false, false).timeout
		_check(shooter.global_position.distance_to(shooter_position) < 0.01, "tireur immobile")
		_check(targets[3].global_position.distance_to(mover_position) > 0.2, "mannequin mobile se déplace")
		_check(float(player.call("get_health")) < float(player.call("get_max_health")), "tireur inflige des dégâts")
		player.global_position = targets[0].global_position + Vector3(0.0, 0.0, 7.0)
		player.set("aim_direction", (targets[0].global_position - player.global_position).normalized())
		_check(player.call("_module_target") == targets[0], "ciblage de plusieurs mannequins")
		player.global_position = spawn_position
		var split_salvo := {"id": 9001, "hits_by_target": {}, "credited": {}}
		for pellet in range(6):
			player.call("_resolve_shotgun_projectile", split_salvo, pellet, true, targets[0] if pellet < 3 else targets[1], 2.0)
		_check(not ("BURN" in targets[0].call("get_active_effect_types")) and not ("BURN" in targets[1].call("get_active_effect_types")), "six plombs répartis ne déclenchent pas le critique")
		targets[0].call("reset_combat_state")
		targets[1].call("reset_combat_state")
		targets[0].call("take_damage", 80.0, "test", "one")
		scene.call("_toggle_option", "invulnerable")
		_check(float(player.call("take_damage", 50.0, "test", "blocked")) == 0.0, "option invulnérable")
		scene.call("_toggle_option", "instant_cooldowns")
		player.call("_start_module_cooldown", "javelin", 12.0)
		_check(float(player.call("get_module_cooldown", "javelin")) == 0.0, "option cooldown instantané")
		scene.call("_toggle_option", "unlimited_ammo")
		_check(bool(player.get("training_unlimited_ammo")), "option munitions illimitées")
		scene.call("_half_health")
		_check(is_equal_approx(float(player.call("get_health")), 500.0), "mise à 50 % PV")
		scene.call("_toggle_menu")
		var menu := scene.get_node("TrainingUI/TrainingRoot/TrainingMenu")
		_check(paused and menu.visible, "sous-menu pause le terrain")
		_check(not spell_bar.visible, "barre masquee sous le menu")
		_press_key(scene, KEY_TAB)
		_check(not paused, "fermeture du sous-menu")
		_check(spell_bar.visible, "barre restauree apres le menu")
		scene.call("_toggle_menu")
		menu.find_child("SmallSizeButton", true, false).emit_signal("pressed")
		_check(int(scene.get("_place_size_index")) == 0, "taille choisie depuis le sous-menu")
		menu.find_child("PlaceButton", true, false).emit_signal("pressed")
		_check(not paused and not menu.visible and str(scene.get("_tool_mode")) == "place", "placer active l'outil depuis le sous-menu")
		scene.call("_cancel_tool")
		_press_key(scene, KEY_F5)
		_check(is_equal_approx(float(player.call("get_health")), 1000.0), "reset des PV joueur")
		_check(is_equal_approx(float(targets[0].call("get_health")), 1000.0), "reset des mannequins")
		_check((scene.call("get_training_targets") as Array).size() == 5, "reset conserve les mannequins")
		scene.call("_remove_all_fixed")
		_check((scene.call("get_training_targets") as Array).size() == 2, "suppression des mannequins fixes")
		var spot := Vector3(0.0, 0.0, 11.0)
		_check(scene.call("_valid_placement", spot, 1.0), "placement libre valide")
		_check(not scene.call("_valid_placement", Vector3(-28.5, 0.0, -12.0), 1.0), "placement sur separation refuse")
		_check(not scene.call("_valid_placement", player.global_position, 1.0), "placement sur le joueur refusé")
		var camera := scene.get_viewport().get_camera_3d()
		scene.call("_start_tool", "place")
		scene.call("_use_tool", camera.unproject_position(spot))
		_check((scene.call("get_training_targets") as Array).size() == 3, "placement par clic")
		_check(is_equal_approx(float((scene.call("get_training_targets") as Array)[0].call("get_training_hit_radius")), 0.78 * 0.65), "taille choisie appliquee au nouveau mannequin")
		await physics_frame
		scene.call("_start_tool", "remove")
		scene.call("_use_tool", camera.unproject_position(spot + Vector3.UP * 0.9))
		_check((scene.call("get_training_targets") as Array).size() == 2, "suppression individuelle par clic")
	if failures.is_empty():
		print("TRAINING GROUND TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		print("TRAINING GROUND TEST: FAIL (%d)" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _press_key(scene: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	scene.call("_input", event)
