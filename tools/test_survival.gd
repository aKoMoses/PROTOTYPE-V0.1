extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player: Node = scene.get_node_or_null("Player")
	_check(player != null, "joueur présent")
	_check(str(scene.get("_state")) == "selection", "choix de l'arme au départ")
	_check(not bool(player.call("is_gameplay_enabled")), "combat désactivé avant le choix")
	scene.call("_choose_weapon", "blaster")
	await physics_frame
	_check(int(scene.get("wave")) == 1, "première vague lancée")
	_check(str(scene.get("_state")) == "incoming" and scene.get("_arrival_markers").size() == 2, "arrivée de vague annoncée")
	scene.call("_begin_wave_combat")
	await physics_frame
	await process_frame
	_check(scene.get_node_or_null("VFXManager") != null, "effets de tirs disponibles en Survie")
	var spell_bar: Control = scene.get("_spell_bar")
	_check(spell_bar != null and spell_bar.is_visible_in_tree(), "barre de sorts visible en combat")
	_check(str(player.call("get_weapon_id")) == "blaster", "arme sélectionnée")
	_check(str(player.call("get_offensive_module_id")) == "", "aucun module au départ")
	_check(str(player.call("get_passive_id")) == "", "aucun passif au départ")
	_check(float(player.get("_blaster_damage")) < 20.0, "blaster affaibli au départ")
	player.call("set_weapon", "shotgun")
	_check(str(player.call("get_weapon_id")) == "blaster", "arme de départ verrouillée")
	var first_targets: Array = scene.call("get_training_targets")
	_check(bool(first_targets[0].call("is_training_bot_enabled")), "ennemis actifs pendant la vague")
	_check(str(first_targets[0].get_node("TrainingBot").get("survival_role")) == "chaser" and str(first_targets[1].get_node("TrainingBot").get("survival_role")) == "shooter", "rôles distincts dès la première vague")
	var initial_distance: float = first_targets[0].global_position.distance_to(player.global_position)
	for _frame in range(120):
		await physics_frame
	_check(first_targets[0].global_position.distance_to(player.global_position) < initial_distance - 1.5, "poursuivant avance vers le joueur malgré les couverts")
	first_targets[0].call("apply_stun", 1.0, "test")
	var stunned_position: Vector3 = first_targets[0].global_position
	for _frame in range(20):
		await physics_frame
	_check(first_targets[0].global_position.distance_to(stunned_position) < 0.05, "étourdissement interrompt le poursuivant")
	for enemy in first_targets:
		enemy.call("set_training_bot_enabled", false)
	first_targets[0].position = Vector3(0, 0, -4)
	first_targets[1].position = Vector3(15, 0, 15)
	await physics_frame
	player.set("aim_direction", Vector3(0, 0, -1))
	_check(player.call("_module_target") == first_targets[0], "visée sélectionne un ennemi de la vague")
	var health_before := float(first_targets[0].call("get_health"))
	player.call("_fire_blaster_projectile", float(player.get("_blaster_damage")), 0.0, Vector3(0, 0, -1))
	await process_frame
	var blaster_projectile := scene.get_node_or_null("BlasterProjectile")
	_check(blaster_projectile != null and blaster_projectile.get_node_or_null("ProjectileCore") != null, "projectile du Blaster visible en Survie")
	await create_timer(0.5).timeout
	_check(float(first_targets[0].call("get_health")) < health_before, "tir atteint l'ennemi de la vague")
	for completed_wave in range(1, 13):
		var enemies: Array = scene.call("get_training_targets")
		_check(not enemies.is_empty(), "ennemis présents vague %d" % completed_wave)
		if completed_wave == 12:
			var boss: Node3D = enemies[enemies.size() - 1]
			var boss_bot: Node = boss.get_node("TrainingBot")
			_check(str(boss_bot.get("survival_role")) == "boss", "broyeur final présent")
			var boss_distance := boss.global_position.distance_to(player.global_position)
			boss_bot.set("_next_attack_at", 0.0)
			for _frame in range(100):
				await physics_frame
			_check(boss.global_position.distance_to(player.global_position) < boss_distance - 1.0, "charge annoncée du broyeur se déplace vers le joueur")
		for enemy in enemies:
			enemy.call("take_damage", 5000.0, "test", "test_%d_%s" % [completed_wave, enemy.name])
		await physics_frame
		await process_frame
		if completed_wave == 12:
			_check(str(scene.get("_state")) == "result", "résultat après la douzième vague")
			_check(scene.get("_choice_content").get_child(0).text.begins_with("VICTOIRE"), "victoire finale affichée")
			break
		_check(str(scene.get("_state")) == "reward" and paused, "choix de récompense après la vague %d" % completed_wave)
		var progression: SurvivalProgression = scene.get("progression")
		var choices := progression.reward_choices(completed_wave)
		_check(choices.size() == 2, "deux propositions à la vague %d" % completed_wave)
		_check(not progression.apply_reward(completed_wave, {"category": "invalid"}), "récompense non proposée refusée")
		scene.call("_choose_reward", choices[0])
		await physics_frame
		_check(int(scene.get("wave")) == completed_wave + 1, "vague suivante après choix")
		scene.call("_begin_wave_combat")
		await physics_frame
		if completed_wave == 1:
			var next_targets: Array = scene.call("get_training_targets")
			_check(str(next_targets[1].get_node("TrainingBot").get("survival_role")) == "charger", "chargeur présent à la deuxième vague")
		if completed_wave == 5:
			var pierce_targets: Array = scene.call("get_training_targets")
			for enemy in pierce_targets:
				enemy.call("set_training_bot_enabled", false)
			pierce_targets[0].position = Vector3(0, 0, -4)
			pierce_targets[1].position = Vector3(0, 0, -7)
			await physics_frame
			player.set("aim_direction", Vector3(0, 0, -1))
			player.set("_blaster_next_attack_ready_at", -10.0)
			var rear_health := float(pierce_targets[1].call("get_health"))
			player.call("_fire_blaster_projectile", float(player.get("_blaster_damage")), 0.0, Vector3(0, 0, -1))
			await create_timer(0.5).timeout
			_check(float(pierce_targets[1].call("get_health")) < rear_health, "Blaster évolué traverse et touche une deuxième cible")
		if completed_wave == 4:
			_check(str(player.call("get_offensive_module_id")) != "" and str(player.call("get_defensive_module_id")) != "" and str(player.call("get_mobility_module_id")) != "" and str(player.call("get_passive_id")) != "", "build acquis en quatre choix")
		if completed_wave == 10:
			_check(float(player.get("_blaster_damage")) > 20.0, "arme plus puissante que dans le duel")
			_check(bool(progression.evolutions.weapon), "évolution du Blaster acquise")
	paused = false
	scene.queue_free()
	await process_frame
	var shotgun_scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	root.add_child(shotgun_scene)
	current_scene = shotgun_scene
	await physics_frame
	shotgun_scene.call("_choose_weapon", "shotgun")
	shotgun_scene.call("_begin_wave_combat")
	var shotgun_player := shotgun_scene.get_node("Player")
	_check(str(shotgun_player.call("get_weapon_id")) == "shotgun", "départ au Shotgun")
	_check(float(shotgun_player.get("_shotgun_pellet_damage")) < 20.0, "Shotgun affaibli au départ")
	shotgun_player.call("set_touch_aim_vector", Vector2.UP)
	shotgun_player.call("_perform_shotgun_attack")
	await create_timer(0.16).timeout
	var visible_pellets := 0
	for pellet in get_nodes_in_group("prototype0_gameplay_projectiles"):
		if pellet.name == "ShotgunPellet" and pellet.get_node_or_null("ProjectileCore") != null:
			visible_pellets += 1
	_check(visible_pellets > 0, "projectiles du Shotgun visibles en Survie")
	shotgun_player.call("set_weapon", "blaster")
	_check(str(shotgun_player.call("get_weapon_id")) == "shotgun", "Shotgun verrouillé pendant la partie")
	var alternate: SurvivalProgression = shotgun_scene.get("progression")
	for completed_wave in range(1, 12):
		var offer := alternate.reward_choices(completed_wave)
		_check(alternate.apply_reward(completed_wave, offer[1]), "seconde proposition acceptée vague %d" % completed_wave)
	_check(str(alternate.equipment.offensive) == "javelin" and str(alternate.equipment.defensive) == "static_shield" and str(alternate.equipment.mobility) == "bio_injector" and str(alternate.equipment.passive) == "omnivamp", "secondes options d'équipement")
	shotgun_player.call("configure_survival_build", alternate.build())
	_check(float(shotgun_player.get("_shotgun_recovery")) < 0.60, "voie rythme du Shotgun plus rapide que le duel")
	_check(float(shotgun_player.call("get_max_health")) == 1250.0, "endurance du passif augmente les PV maximum")
	var evolved: SurvivalProgression = load("res://scripts/survival_progression.gd").new()
	evolved.choose_weapon("shotgun")
	for completed_wave in range(1, 9):
		var offer := evolved.reward_choices(completed_wave)
		_check(evolved.apply_reward(completed_wave, offer[1] if completed_wave <= 4 or completed_wave in [6, 7] else offer[0]), "build évolué vague %d" % completed_wave)
	shotgun_player.call("configure_survival_build", evolved.build())
	_check(shotgun_player.get("_shotgun_pellet_angles").size() == 8, "Shotgun évolué tire huit projectiles")
	_check(bool(evolved.evolutions.mobility), "Bio Injector évolué acquis")
	var pulse_target: Node3D = shotgun_scene.call("get_training_targets")[0]
	pulse_target.call("set_training_bot_enabled", false)
	pulse_target.global_position = shotgun_player.global_position + Vector3(2, 0, 0)
	var pulse_health := float(pulse_target.call("get_health"))
	shotgun_player.call("_perform_bio_injector")
	_check(float(pulse_target.call("get_health")) < pulse_health, "onde du Bio Injector évolué inflige des dégâts")
	shotgun_scene.call("_pause_run")
	_check(paused and str(shotgun_scene.get("_state")) == "pause", "pause suspend la vague")
	shotgun_scene.call("_resume_run")
	_check(not paused and str(shotgun_scene.get("_state")) == "combat", "reprise de la vague")
	shotgun_player.call("take_damage", 5000.0, "test", "fatal")
	await process_frame
	_check(str(shotgun_scene.get("_state")) == "result", "défaite à la mort du joueur")
	shotgun_scene.queue_free()
	paused = false
	current_scene = null
	await process_frame
	for failure in failures:
		push_error(failure)
	print("SURVIVAL TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
