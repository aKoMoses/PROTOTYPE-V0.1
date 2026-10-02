extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	scene.set("records_path", "user://test_survival_records.json")
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player: Node = scene.get_node_or_null("Player")
	_check(player != null, "joueur présent")
	player.call("set_robot", "polyvalent")
	_check(str(scene.get("_state")) == "selection", "choix de l'arme au départ")
	_check(not bool(player.call("is_gameplay_enabled")), "combat désactivé avant le choix")
	var start_overlay: Control = scene.get("_reward_overlay")
	_check(start_overlay.is_visible_in_tree() and start_overlay.find_child("RewardChoice1", true, false) != null and start_overlay.find_child("RewardChoice2", true, false) != null, "Blaster et Shotgun présentés en cartes")
	_check(not (start_overlay.find_child("RewardChoice1", true, false) as Button).disabled, "cartes de départ sélectionnables")
	scene.call("_choose_weapon", "blaster")
	await physics_frame
	_check(not start_overlay.visible, "cartes de départ fermées après le choix")
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
	_check(float(player.get("_blaster_damage")) >= 20.0 and float(player.get("_blaster_charge_time")) < 1.0, "Blaster de départ renforcé et charge plus rapide")
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
	var blaster_projectile := scene.get_node_or_null("BlasterProjectile")
	# A tap emits after the final skeleton pose; its update can follow this frame.
	var blaster_deadline := Time.get_ticks_msec() + 1000
	while blaster_projectile == null and Time.get_ticks_msec() < blaster_deadline:
		await process_frame
		blaster_projectile = scene.get_node_or_null("BlasterProjectile")
	_check(blaster_projectile != null and blaster_projectile.get_node_or_null("ProjectileCore") != null, "projectile du Blaster visible en Survie")
	await create_timer(0.5).timeout
	_check(float(first_targets[0].call("get_health")) < health_before, "tir atteint l'ennemi de la vague")
	for completed_wave in range(1, 13):
		scene.call("_spawn_reinforcements")
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
			_check(scene.get("stats").kills == 76, "les 76 ennemis des douze vagues sont comptabilisés")
			_check(str(scene.get("_state")) == "result", "résultat après la douzième vague")
			_check(scene.get("summary").title.text.begins_with("VICTOIRE"), "victoire finale affichée")
			break
		_check(str(scene.get("_state")) == "reward" and paused, "choix de récompense après la vague %d" % completed_wave)
		var reward_overlay: Control = scene.get("_reward_overlay")
		_check(reward_overlay.is_visible_in_tree() and reward_overlay.find_child("RewardChoice1", true, false) != null and reward_overlay.find_child("RewardChoice2", true, false) != null and reward_overlay.find_child("RewardChoice3", true, false) != null, "trois cartes de récompense visibles")
		var first_card := reward_overlay.find_child("RewardChoice1", true, false) as Button
		_check(first_card.disabled, "cartes bloquées au moment où la vague se termine")
		if completed_wave == 1:
			var held_click := InputEventMouseButton.new()
			held_click.button_index = MOUSE_BUTTON_LEFT
			held_click.pressed = true
			Input.parse_input_event(held_click)
			await create_timer(0.7).timeout
			await process_frame
			_check(first_card.disabled, "clic maintenu ne sélectionne pas une carte")
			held_click.pressed = false
			Input.parse_input_event(held_click)
			await process_frame
			await process_frame
			_check(not first_card.disabled, "cartes sélectionnables après le délai de sécurité")
		var progression: SurvivalProgression = scene.get("progression")
		var choices := progression.reward_choices(completed_wave)
		_check(choices.size() == 3, "trois propositions à la vague %d" % completed_wave)
		for choice in choices:
			_check(not str(scene.call("_reward_card_description", choice)).contains("%"), "description de carte sans pourcentage")
		_check(not progression.apply_reward(completed_wave, {"category": "invalid"}), "récompense non proposée refusée")
		if completed_wave == 3:
			player.get("combat_state").health = 500.0
		var picked: Dictionary = choices[0]
		scene.call("_choose_reward", picked)
		if completed_wave == 3:
			_check(is_equal_approx(float(player.call("get_health")), 600.0), "soin de 100 PV au troisième palier")
		if completed_wave == 6:
			_check(str(scene.get("_state")) == "transition" and int(scene.get("wave")) == 6, "vague 7 attend la traversée")
			player.position = Vector3(35, 0, 0)
			scene.call("_enter_factory")
		await physics_frame
		_check(int(scene.get("wave")) == completed_wave + 1, "vague suivante après choix")
		scene.call("_begin_wave_combat")
		await physics_frame
		if completed_wave == 1:
			var next_targets: Array = scene.call("get_training_targets")
			_check(str(next_targets[1].get_node("TrainingBot").get("survival_role")) == "charger", "chargeur présent à la deuxième vague")
			_check(str(progression.build().get(str(picked.category), "")) == str(picked.id) if picked.kind == "item" else true, "nouvel équipement appliqué après choix")
			for enemy in next_targets:
				enemy.call("set_training_bot_enabled", false)
			var charger: Node3D = next_targets[1]
			var charger_bot: Node = charger.get_node("TrainingBot")
			charger.global_position = player.global_position + Vector3(0.0, 0.0, -8.0)
			charger.call("set_training_bot_enabled", true)
			charger_bot.set("_next_attack_at", 0.0)
			await physics_frame
			await physics_frame
			_check(float(charger_bot.get("_windup_remaining")) <= 0.0, "chargeur ne prépare pas une charge à 8 m")
			charger.global_position = player.global_position + Vector3(0.0, 0.0, -5.0)
			await physics_frame
			await physics_frame
			_check(float(charger_bot.get("_windup_remaining")) > 0.0, "chargeur prépare une charge à 5 m")
			for _charge_frame in range(75):
				await physics_frame
			_check(charger.global_position.distance_to(player.global_position) < 0.5, "charge s'arrête à la cible sans oscillation")
			charger.call("set_training_bot_enabled", false)
			charger.global_position = Vector3(4.0, 0.0, -4.5)
			charger_bot.set("_charge_target", Vector3(11.0, 0.0, -4.5))
			charger_bot.set("_charge_remaining", 0.8)
			for _charge_frame in range(30):
				charger_bot.call("_advance_charge", charger, 1.0 / 60.0)
			_check(charger.global_position.x < 5.5 and float(charger_bot.get("_charge_remaining")) <= 0.0, "charge stoppée par le couvert")
			charger.global_position = Vector3(20.0, 0.0, 0.0)
			charger_bot.set("_move_velocity", Vector3(18.0, 0.0, 0.0))
			charger_bot.call("_move_bot", charger, 0.3)
			_check(charger.global_position.x <= 21.01, "ennemi reste dans les murs de Survie")
		if completed_wave == 5 and progression.aspects.weapon.path == "rail":
			var pierce_targets: Array = scene.call("get_training_targets")
			for enemy in pierce_targets:
				enemy.call("set_training_bot_enabled", false)
			pierce_targets[0].position = Vector3(0, 0, -4)
			pierce_targets[1].position = Vector3(0, 0, -7)
			await physics_frame
			player.set("aim_direction", Vector3(0, 0, -1))
			player.set("_blaster_next_attack_ready_at", -10.0)
			var rear_health := float(pierce_targets[1].call("get_health"))
			player.call("_fire_blaster_projectile", float(player.get("_blaster_max_damage")), 1.0, Vector3(0, 0, -1))
			await create_timer(0.5).timeout
			_check(float(pierce_targets[1].call("get_health")) < rear_health, "Blaster évolué traverse et touche une deuxième cible")
		if completed_wave == 4:
			_check(progression.build().weapon == "blaster", "arme de départ conservée après quatre choix")
	paused = false
	scene.queue_free()
	await process_frame
	var shotgun_scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	shotgun_scene.set("records_path", "user://test_survival_records.json")
	root.add_child(shotgun_scene)
	current_scene = shotgun_scene
	await physics_frame
	shotgun_scene.get_node("Player").call("set_robot", "polyvalent")
	shotgun_scene.call("_choose_weapon", "shotgun")
	shotgun_scene.call("_begin_wave_combat")
	var shotgun_player := shotgun_scene.get_node("Player")
	_check(str(shotgun_player.call("get_weapon_id")) == "shotgun", "départ au Shotgun")
	_check(float(shotgun_player.get("_shotgun_pellet_damage")) < 20.0, "Shotgun affaibli au départ")
	# Emission waits for the final skeleton pose after preparation. Observe each
	# actual projectile after its initialization, rather than one platform-specific
	# instant or its name (Godot renames the second and subsequent siblings).
	var visible_pellets: Dictionary = {}
	var source_id := shotgun_player.get_instance_id()
	var observe_pellet := func(reference: WeakRef) -> void:
		var pellet := reference.get_ref() as Node3D
		if pellet == null or pellet.get_parent() != shotgun_scene or int(pellet.get_meta("ai_projectile_source", 0)) != source_id:
			return
		var core := pellet.get_node_or_null("ProjectileCore") as MeshInstance3D
		if core != null and core.mesh != null and core.is_visible_in_tree():
			visible_pellets[pellet.get_instance_id()] = true
	var observe_added := func(node: Node) -> void:
		if node is Node3D and node.get_parent() == shotgun_scene:
			observe_pellet.call_deferred(weakref(node))
	node_added.connect(observe_added)
	shotgun_player.call("set_touch_aim_vector", Vector2.UP)
	shotgun_player.call("_perform_shotgun_attack")
	var emission_deadline := Time.get_ticks_msec() + 2000
	while visible_pellets.size() < 6 and Time.get_ticks_msec() < emission_deadline:
		await process_frame
	node_added.disconnect(observe_added)
	_check(visible_pellets.size() == 6, "les six projectiles du Shotgun sont visibles dès leur émission en Survie")
	shotgun_player.call("set_weapon", "blaster")
	_check(str(shotgun_player.call("get_weapon_id")) == "shotgun", "Shotgun verrouillé pendant la partie")
	var alternate: SurvivalProgression = shotgun_scene.get("progression")
	for completed_wave in range(1, 12):
		var offer := alternate.reward_choices(completed_wave)
		_check(offer.size() == 3, "trois secondes propositions disponibles vague %d" % completed_wave)
		_check(alternate.apply_reward(completed_wave, offer[1]), "seconde proposition acceptée vague %d" % completed_wave)
	alternate.equipment.passive = "omnivamp"
	alternate.upgrades.weapon.tempo = 3
	alternate.upgrades.passive.tempo = 1
	shotgun_player.call("configure_survival_build", alternate.build())
	_check(float(shotgun_player.get("_shotgun_recovery")) < 0.60, "voie rythme du Shotgun plus rapide que le duel")
	_check(float(shotgun_player.call("get_max_health")) == 1250.0, "endurance du passif augmente les PV maximum")
	var evolved: SurvivalProgression = load("res://scripts/survival_progression.gd").new()
	evolved.choose_weapon("shotgun")
	evolved.equipment.mobility = "bio_injector"
	evolved.aspects.weapon = {"path": "sweeper", "rank": 3}
	evolved.aspects.mobility = {"path": "overdrive", "rank": 3}
	evolved.evolutions.weapon = true
	evolved.evolutions.mobility = true
	shotgun_player.call("configure_survival_build", evolved.build())
	_check(shotgun_player.get("_shotgun_pellet_angles").size() == 12, "Éventail ultime tire douze projectiles")
	_check(bool(evolved.evolutions.mobility), "Bio Injector évolué acquis")
	var pulse_target: Node3D = shotgun_scene.call("get_training_targets")[0]
	pulse_target.call("set_training_bot_enabled", false)
	pulse_target.global_position = shotgun_player.global_position + Vector3(2, 0, 0)
	var pulse_health := float(pulse_target.call("get_health"))
	shotgun_player.call("_perform_bio_injector")
	_check(is_equal_approx(float(pulse_target.call("get_health")), pulse_health) and float(shotgun_player.call("get_attack_speed_multiplier")) > 1.5, "Survoltage accélère les attaques sans onde artificielle")
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
