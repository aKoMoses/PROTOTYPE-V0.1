extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var saved: Dictionary = LOADOUT.load_local().duplicate(true)
	var garage = load("res://scenes/forge_garage_preview.tscn").instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	var stage = garage.stage
	var focus = garage.focus
	stage.set_process(false)
	focus.set_process(false)
	garage.module_installation.set_process(false)
	var original_camera: Transform3D = stage.camera.global_transform
	check(focus.zone == "robot", "entree en vue generale")
	(garage.weapon_buttons["blaster"] as Button).pressed.emit()
	check(focus.zone == "robot" and focus.category == "weapon" and not stage._equipment_focused, "le catalogue conserve le robot entier lors du choix d'arme")
	check(stage.camera.global_transform.is_equal_approx(original_camera), "la selection ne teleporte pas la camera")
	focus.advance(0.60)
	check(stage.camera.global_transform.is_equal_approx(original_camera), "le catalogue conserve le cadrage general apres la selection")
	# Weapons keep the overview; the standalone inspection API also remains available.
	focus.show_equipment("weapon", "blaster")
	focus.advance(0.26)
	var halfway: Transform3D = stage.camera.global_transform
	check(halfway.origin.distance_to(original_camera.origin) > 0.2, "la camera avance pendant la transition")
	focus.advance(0.30)
	check(halfway.origin.distance_to(stage.camera.global_position) > 0.2, "la transition a un etat intermediaire")
	focus.show_overview(false)
	for identifier in LOADOUT.WEAPONS:
		(garage.weapon_buttons[identifier] as Button).pressed.emit()
		focus.advance(0.60)
		check(stage.weapon_id == identifier and garage.loadout.weapon == identifier and focus.equipment_id == identifier, "modele et choix synchronises : " + identifier)
		check_framing(focus, stage, identifier)
	for chassis in ["agile", "puissant"]:
		(garage.robot_buttons[chassis] as Button).pressed.emit()
		check(focus.zone == "robot", "changement de chassis rend la vue generale : " + chassis)
		(garage.weapon_buttons["longshot"] as Button).pressed.emit()
		focus.advance(0.60)
		check_framing(focus, stage, "longshot " + chassis)
		garage._open_modules("mobility")
		(garage._module_options.get_child(0) as Button).pressed.emit()
		focus.advance(0.60)
		check_framing(focus, stage, "jambes " + chassis)
	(garage.robot_buttons["polyvalent"] as Button).pressed.emit()
	(garage.weapon_buttons["longshot"] as Button).pressed.emit()
	focus.advance(0.60)
	garage._open_weapon_info("blaster")
	focus.advance(0.60)
	check(garage.loadout.weapon == "longshot" and focus.equipment_id == "longshot", "l'information sur une autre arme ne l'equipe pas")
	check_framing(focus, stage, "longshot avec informations")
	var with_picker: Transform3D = stage.camera.global_transform
	garage._module_panel.hide()
	check(stage.camera.global_transform.is_equal_approx(with_picker), "fermeture du panneau sans saut de camera")
	focus.advance(0.60)
	var categories := {"offensive": LOADOUT.OFFENSIVE, "defensive": LOADOUT.DEFENSIVE, "mobility": LOADOUT.MOBILITY, "passive": LOADOUT.PASSIVES}
	for category in categories:
		garage._open_modules(category)
		focus.advance(0.60)
		check(focus.zone == "robot" and garage._category == category, "categorie ouverte en vue generale : " + category)
		check_framing(focus, stage, category + " avec choix")
		var before: Dictionary = garage.loadout.duplicate(true)
		var camera_before: Transform3D = stage.camera.global_transform
		(garage._module_options.get_child(1) as Button).mouse_entered.emit()
		check(garage.loadout == before and stage.camera.global_transform.is_equal_approx(camera_before), "survol de demo sans changement d'equipement ni de camera")
		for index in categories[category].size():
			garage._open_modules(category)
			(garage._module_options.get_child(index) as Button).pressed.emit()
			garage.module_installation.set_process(false)
			focus.advance(0.65)
			check(focus.equipment_id == garage.loadout[category], "inspection du module choisi : " + str(garage.loadout[category]))
			if garage.loadout[category] in ["pyro_boots", "bio_injector"]:
				check(garage.module_installation.active and not focus._effects.visible, "accessoire physique et intervention du bras : " + str(garage.loadout[category]))
			else:
				check(focus._effects.visible and not focus._holders.is_empty(), "effet local visible : " + str(garage.loadout[category]))
			check_framing(focus, stage, str(garage.loadout[category]))
	garage._open_modules("mobility")
	(garage._module_options.get_child(0) as Button).pressed.emit()
	garage.module_installation.set_process(false)
	check(focus.zone == "legs" and garage.module_installation.active and stage.module_visuals.mounts.pyro_left.visible and stage.module_visuals.mounts.pyro_right.visible, "Pyro-Bottes zoome sur les deux accessoires de cheville")
	garage._open_modules("mobility")
	(garage._module_options.get_child(1) as Button).pressed.emit()
	garage.module_installation.set_process(false)
	check(focus.zone == "core" and garage.module_installation.active and stage.module_visuals.mounts.bio.visible, "Bio-Injecteur zoome sur ses cartouches")
	# Exercise the separate effect API while the module work test covers the arm.
	garage.module_installation.cancel(false)
	focus.show_equipment("mobility", "bio_injector")
	focus.advance(0.65)
	var holder: Node3D = focus._holders[0]
	var effect_before := holder.global_position
	var yaw_before: float = stage.robot.rotation.y
	stage.begin_robot_rotation()
	stage.rotate_robot(0.8)
	stage.end_robot_rotation()
	focus.advance(0.01)
	check(is_equal_approx(stage.robot.rotation.y, yaw_before + 0.8), "l'inspection conserve la rotation manuelle")
	check(holder.global_position.distance_to(effect_before) > 0.1, "l'effet suit la piece pendant la rotation")
	check_framing(focus, stage, "noyau tourne")
	var point: Vector2 = stage.camera.unproject_position(focus.anchor("Spine1")) * stage.size / Vector2(stage.viewport.size)
	var yaw_gui: float = stage.robot.rotation.y
	await mouse_button(point, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(40, 0)
	motion.relative = Vector2(40, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	focus.advance(0.01)
	await mouse_button(point + Vector2(40, 0), false)
	check(absf(angle_difference(yaw_gui, stage.robot.rotation.y)) > 0.2, "le vrai glisser GUI tourne le robot entier dans le catalogue")
	check_framing(focus, stage, "rotation GUI en inspection")
	stage._next_gesture = -1.0
	stage.begin_robot_rotation()
	stage._advance_robot_animation(0.1)
	check(stage._gesture_clip == &"", "pas de salut pendant la rotation du robot")
	stage.end_robot_rotation()
	focus.advance(2.0)
	check(not focus._effects.visible, "l'effet disparait apres son impulsion")
	check(garage.find_child("GarageScanner", true, false) == null, "le catalogue ne presente plus de commande Scanner")
	for dimensions in [Vector2i(800, 600), Vector2i(1280, 720), Vector2i(2340, 1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		focus.set_process(false)
		for identifier in LOADOUT.WEAPONS:
			(garage.weapon_buttons[identifier] as Button).pressed.emit()
			focus.advance(0.60)
			check_framing(focus, stage, identifier + " " + str(dimensions))
		garage._open_modules("mobility")
		focus.advance(0.60)
		check_framing(focus, stage, "module avec choix " + str(dimensions))
	(garage._nav["ROBOT"] as Button).pressed.emit()
	focus.advance(0.60)
	check(stage.camera.global_transform.is_equal_approx(original_camera) and not stage._equipment_focused, "ROBOT retrouve la vue generale et les animations")
	(garage.weapon_buttons["shotgun"] as Button).pressed.emit()
	focus.advance(0.65)
	garage.hide()
	await process_frame
	check(not focus.is_processing() and focus.zone == "robot", "inspection suspendue hors du garage")
	check(stage.camera.global_transform.is_equal_approx(original_camera), "sortie remet la camera en vue generale")
	garage.show()
	await process_frame
	check(focus.is_processing(), "inspection reactivee a la reouverture")
	check(LOADOUT.load_local() == saved, "le controleur n'ecrit aucune sauvegarde")
	garage.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE FOCUS TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func check_framing(focus: Node, stage: Node, label: String) -> void:
	var bounds: AABB = focus.region_bounds()
	var rect: Rect2 = focus.frame_rect().grow(1.0)
	var fits := true
	for corner in 8:
		var point := bounds.get_endpoint(corner)
		var screen: Vector2 = stage.camera.unproject_position(point) * stage.size / Vector2(stage.viewport.size)
		fits = fits and not stage.camera.is_position_behind(point) and rect.has_point(screen)
	check(fits, "piece contenue entre les panneaux : " + label)
	check(stage.camera.global_position.is_finite(), "camera valide : " + label)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame
