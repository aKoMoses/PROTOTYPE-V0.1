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
	var garage: Control = flow.get("_forge_garage")
	var choices: Dictionary = garage.get("robot_buttons")
	_check(garage.visible and choices.size() == 3, "trois chassis dans le garage officiel")
	var stage = garage.get("stage")
	_check(stage.robot_model.scene_file_path == "res://art/player_mecha_animated.glb", "vrai modele de combat au centre")
	_check(stage.viewport.own_world_3d, "monde 3D du garage isole")
	var source_model := load("res://art/player_mecha_animated.glb").instantiate() as Node3D
	var source_animator := source_model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_check(stage.robot_animator.get_animation(stage.idle_clip) != source_animator.get_animation(stage.idle_clip), "animation propre au garage")
	var initial_time: float = stage.robot_animator.current_animation_position
	await create_timer(0.25).timeout
	_check(stage.robot_animator.current_animation_position > initial_time, "animation du robot avance reellement")
	flow.call("_open_menu")
	var stopped_time: float = stage.robot_animator.current_animation_position
	await create_timer(0.1).timeout
	_check(stage.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "rendu coupe hors de la forge")
	_check(is_equal_approx(stage.robot_animator.current_animation_position, stopped_time), "animation suspendue hors de la forge")
	flow.call("_open_equipment")
	source_model.free()
	for entry in [["agile", 800.0, 6.0], ["polyvalent", 1000.0, 5.0], ["puissant", 1200.0, 4.0]]:
		var identifier: String = entry[0]
		var button: Button = choices[identifier]
		_check(flow.call("_equipment_icon", identifier) != null, "portrait présent : " + identifier)
		button.pressed.emit()
		_check(garage.get("_health").text.contains(str(int(entry[1]))), "PV visibles dans le garage : " + identifier)
		_check(stage.chassis_id == identifier and garage.get("loadout").robot == identifier, "selection du chassis central : " + identifier)
		_check(LOADOUT.load_local().robot == identifier, "choix sauvegardé immédiatement : " + identifier)
		player.call("apply_loadout", flow.get("loadout"))
		player.call("reset_combat_state")
		_check(player.call("get_robot_id") == identifier, "robot transmis au joueur : " + identifier)
		_check(is_equal_approx(float(player.call("get_health")), entry[1]), "PV de départ : " + identifier)
		_check(is_equal_approx(float(player.call("get_current_move_speed")), entry[2]), "vitesse appliquée : " + identifier)
		player.call("take_damage", 100.0, "test", "robot_hit_" + identifier)
		player.call("reset_combat_state")
		_check(is_equal_approx(float(player.call("get_health")), entry[1]), "reset conserve le châssis : " + identifier)
	(garage.get("_nav")["ARMES"] as Button).pressed.emit()
	(garage.get("_nav")["ROBOT"] as Button).pressed.emit()
	_check(flow.get("loadout").robot == "puissant", "choix conserve entre les categories")
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
