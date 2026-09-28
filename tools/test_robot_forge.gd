extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
var _failures: Array[String] = []
var _save_existed := false
var _saved_bytes := PackedByteArray()

func _initialize() -> void:
	_save_existed = FileAccess.file_exists(LOADOUT.SAVE_PATH)
	if _save_existed:
		_saved_bytes = FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH)
	LOADOUT.save_local(LOADOUT.defaults())
	var legacy := LOADOUT.sanitize({"weapon": "shotgun", "passive": "omnivamp"})
	_check(legacy.robot == "polyvalent" and legacy.weapon == "shotgun" and legacy.passive == "omnivamp", "ancienne sauvegarde migrée sans perdre l'équipement")
	_check(LOADOUT.sanitize({"robot": "unknown"}).robot == "polyvalent", "robot invalide remplacé par Polyvalent")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var player: Node = scene.get_node("Player")
	flow.call("_open_equipment")
	_check(flow.get("_equipment_category") == "robot", "la forge présente les robots en premier")
	var choices: Dictionary = flow.get("_selection_buttons")["robot"]
	_check(choices.size() == 3, "trois choix dans la forge")
	for entry in [["agile", 800.0, 6.0], ["polyvalent", 1000.0, 5.0], ["puissant", 1200.0, 4.0]]:
		var identifier: String = entry[0]
		var button: Button = choices[identifier]
		_check(flow.call("_equipment_icon", identifier) != null, "portrait présent : " + identifier)
		var stats := button.find_child("RobotStats", true, false) as Label
		_check(stats != null and stats.text.contains(str(int(entry[1]))), "PV visibles sur la carte : " + identifier)
		button.pressed.emit()
		_check(LOADOUT.load_local().robot == identifier, "choix sauvegardé immédiatement : " + identifier)
		var markers: Dictionary = flow.get("_selection_markers")["robot"]
		for other in markers:
			_check((markers[other] as Label).text.contains("ÉQUIPÉ") == (other == identifier), "sélection exclusive : " + identifier)
		player.call("apply_loadout", flow.get("loadout"))
		player.call("reset_combat_state")
		_check(player.call("get_robot_id") == identifier, "robot transmis au joueur : " + identifier)
		_check(is_equal_approx(float(player.call("get_health")), entry[1]), "PV de départ : " + identifier)
		_check(is_equal_approx(float(player.call("get_current_move_speed")), entry[2]), "vitesse appliquée : " + identifier)
		player.call("take_damage", 100.0, "test", "robot_hit_" + identifier)
		player.call("reset_combat_state")
		_check(is_equal_approx(float(player.call("get_health")), entry[1]), "reset conserve le châssis : " + identifier)
	var previews: Dictionary = flow.get("_equipment_preview_buttons")
	(previews["weapon"] as Button).pressed.emit()
	(previews["robot"] as Button).pressed.emit()
	_check(flow.get("loadout").robot == "puissant", "choix conservé entre les onglets")
	flow.call("_start_duel")
	await process_frame
	_check(float(player.call("get_max_health")) == 1200.0 and float(player.call("get_health")) == 1200.0, "PV du Puissant au départ du duel")
	var health_label := player.get_node("WorldUIAnchor/PlayerHealthReadout/HealthBarViewport/HealthBarUI/HealthNumber") as Label
	_check(health_label.text == "1200", "barre de vie synchronisée avec le robot")
	scene.call("prepare_round", flow.get("loadout"))
	_check(float(player.call("get_health")) == 1200.0 and float(player.call("get_current_move_speed")) == 4.0, "châssis conservé à la manche suivante")
	player.call("take_damage", 600.0, "test", "half_health")
	player.call("set_robot", "agile")
	_check(float(player.call("get_health")) == 400.0, "changement de châssis conserve le pourcentage de PV")
	player.call("set_robot", "unknown")
	_check(player.call("get_robot_id") == "polyvalent" and float(player.call("get_current_move_speed")) == 5.0, "fallback du joueur")
	flow.set_process(false)
	for audio_node in scene.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	await create_timer(0.1).timeout
	scene.queue_free()
	await process_frame
	var training: Node = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(training)
	current_scene = training
	await process_frame
	var trainee: Node = training.get("player")
	_check(trainee.call("get_robot_id") == "puissant" and float(trainee.call("get_max_health")) == 1200.0, "entraînement utilise le robot sauvegardé")
	training.queue_free()
	await process_frame
	var survival: Node = load("res://scenes/survival.tscn").instantiate()
	root.add_child(survival)
	current_scene = survival
	await process_frame
	survival.call("_choose_weapon", "blaster")
	var survivor: Node = survival.get("player")
	_check(survivor.call("get_robot_id") == "puissant" and float(survivor.call("get_health")) == 1200.0, "survie utilise le robot sauvegardé")
	var survival_build: Dictionary = survival.get("progression").build()
	survival_build.upgrades["passive"] = {"tempo": 1}
	survivor.call("configure_survival_build", survival_build)
	_check(float(survivor.call("get_max_health")) == 1450.0 and float(survivor.call("get_current_move_speed")) == 4.0, "bonus de survie ajouté aux PV du robot")
	(survival.get("_music") as AudioStreamPlayer).stop()
	await create_timer(0.1).timeout
	survival.queue_free()
	await process_frame
	if _save_existed:
		var file := FileAccess.open(LOADOUT.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_saved_bytes)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOADOUT.SAVE_PATH))
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("ROBOT FORGE TEST: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
