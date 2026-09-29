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
	await process_frame
	var robot_views: Array[Node] = []
	var initial_angles: Array[float] = []
	var initial_times: Array[float] = []
	var worlds: Array[World3D] = []
	var source_model := load("res://art/player_mecha_animated.glb").instantiate() as Node3D
	var source_animator := source_model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for identifier in LOADOUT.ROBOTS:
		var view := (choices[identifier] as Button).find_child("RobotPreview", true, false)
		_check(view != null, "aperçu 3D présent : " + identifier)
		if view == null:
			continue
		robot_views.append(view)
		var model := view.get("_model") as Node3D
		var turntable := view.get("_turntable") as Node3D
		var animator := view.get("_animation_player") as AnimationPlayer
		var viewport := view.get("_viewport") as SubViewport
		_check(model.scene_file_path == "res://art/player_mecha_animated.glb", "vrai modèle de combat : " + identifier)
		_check(viewport.own_world_3d and viewport.find_world_3d() not in worlds, "monde 3D propre à la carte : " + identifier)
		worlds.append(viewport.find_world_3d())
		_check(view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "aperçu laisse passer la sélection : " + identifier)
		_check(is_equal_approx(turntable.scale.x, float(view.get("CHASSIS_VISUALS").SCALE_FACTORS[identifier])), "taille du châssis conservée : " + identifier)
		_check(view.get("_clips").size() >= 3 and animator.is_playing(), "plusieurs animations démarrées : " + identifier)
		initial_angles.append(turntable.rotation.y)
		initial_times.append(animator.current_animation_position)
		for clip_name in view.get("_clips"):
			_check(animator.get_animation(clip_name) != source_animator.get_animation(clip_name), "clips propres à la carte : " + identifier)
			if String(clip_name).ends_with("walk") or String(clip_name).ends_with("run"):
				var clip := animator.get_animation(clip_name)
				for track in range(clip.get_track_count()):
					if clip.track_get_type(track) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(track)).to_lower().contains("hips"):
						var first: Vector3 = clip.track_get_key_value(track, 0)
						for key in range(clip.track_get_key_count(track)):
							var position: Vector3 = clip.track_get_key_value(track, key)
							_check(is_equal_approx(position.x, first.x) and is_equal_approx(position.z, first.z), "marche/course reste sur le socle : " + identifier)
	await create_timer(0.25).timeout
	for index in range(robot_views.size()):
		var view := robot_views[index]
		_check(not is_equal_approx((view.get("_turntable") as Node3D).rotation.y, initial_angles[index]), "rotation avance réellement")
		_check((view.get("_animation_player") as AnimationPlayer).current_animation_position > initial_times[index], "animation avance réellement")
		var previous_clip: StringName = (view.get("_animation_player") as AnimationPlayer).current_animation
		view.call("_process", float(view.get("_clip_duration")))
		_check((view.get("_animation_player") as AnimationPlayer).current_animation != previous_clip, "enchaînement automatique des animations")
	flow.call("_open_menu")
	var stopped_angle := (robot_views[0].get("_turntable") as Node3D).rotation.y
	var stopped_time := (robot_views[0].get("_animation_player") as AnimationPlayer).current_animation_position
	await create_timer(0.1).timeout
	_check((robot_views[0].get("_viewport") as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED, "rendu coupé hors de la forge")
	_check(is_equal_approx((robot_views[0].get("_turntable") as Node3D).rotation.y, stopped_angle), "rotation suspendue hors de la forge")
	_check(is_equal_approx((robot_views[0].get("_animation_player") as AnimationPlayer).current_animation_position, stopped_time), "animation suspendue hors de la forge")
	flow.call("_open_equipment")
	source_model.free()
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
	for view in robot_views:
		_check(not is_instance_valid(view), "aperçu libéré au changement d'onglet")
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
