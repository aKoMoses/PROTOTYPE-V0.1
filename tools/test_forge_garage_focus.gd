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
	check(focus.zone == "garage" and garage._hub_mode, "entrée en vue des rangements du garage")
	check(not garage._module_panel.visible and not garage._detail_panel.visible, "les catalogues laissent les rangements visibles à l'entrée")
	var original_camera: Transform3D = focus._base
	garage._navigate("ARMES")
	focus.set_process(false)
	focus.advance(0.95)
	var rack_camera: Transform3D = stage.camera.global_transform
	check(focus.zone == "station" and focus.station_category == "weapon" and stage._equipment_focused, "le catalogue d'armes cadre le râtelier distinct")
	check_framing(focus, stage, "râtelier d'armes")
	var before_preview: Dictionary = garage.loadout.duplicate(true)
	(garage.weapon_buttons["blaster"] as Button).pressed.emit()
	check(focus.zone == "station" and focus.category == "weapon" and garage._preview_id == "blaster", "le choix d'arme conserve la vue du râtelier")
	check(garage.loadout == before_preview and not garage.module_installation.active, "l'aperçu d'arme n'équipe pas le robot")
	check(stage.camera.global_transform.is_equal_approx(rack_camera), "la sélection d'arme ne téléporte pas la caméra")
	focus.advance(0.60)
	check(stage.camera.global_transform.is_equal_approx(rack_camera), "la caméra reste sur le râtelier après le choix d'arme")
	# Standalone inspection retains a smooth, bone-aware camera independent of the catalog.
	focus.show_equipment("weapon", "blaster")
	focus.advance(0.26)
	var halfway: Transform3D = stage.camera.global_transform
	check(halfway.origin.distance_to(rack_camera.origin) > 0.2, "la caméra avance pendant la transition d'inspection")
	focus.advance(0.30)
	check(halfway.origin.distance_to(stage.camera.global_position) > 0.2, "l'inspection possède un cadrage intermédiaire")
	focus.show_overview(false)
	for identifier in LOADOUT.WEAPONS:
		equip_weapon(garage, identifier)
		focus.show_equipment("weapon", identifier, false)
		focus.advance(0.60)
		check(stage.weapon_id == identifier and garage.loadout.weapon == identifier and focus.equipment_id == identifier, "modèle et inspection synchronisés : " + identifier)
		check_framing(focus, stage, identifier)
	for chassis in ["agile", "puissant"]:
		(garage.robot_buttons[chassis] as Button).pressed.emit()
		check(focus.zone == "robot", "changement de châssis rend la vue générale : " + chassis)
		equip_weapon(garage, "longshot")
		focus.show_equipment("weapon", "longshot", false)
		focus.advance(0.60)
		check_framing(focus, stage, "longshot " + chassis)
		stage.set_mobility_module("pyro_boots")
		focus.show_equipment("mobility", "pyro_boots", false)
		focus.advance(0.60)
		check_framing(focus, stage, "jambes " + chassis)
	(garage.robot_buttons["polyvalent"] as Button).pressed.emit()
	equip_weapon(garage, "longshot")
	focus.show_equipment("weapon", "longshot", false)
	focus.advance(0.60)
	garage._open_weapon_info("blaster")
	check(garage.loadout.weapon == "longshot" and focus.equipment_id == "longshot", "l'information sur une autre arme ne l'équipe pas")
	var categories := {"offensive": LOADOUT.OFFENSIVE, "defensive": LOADOUT.DEFENSIVE, "mobility": LOADOUT.MOBILITY, "passive": LOADOUT.PASSIVES}
	for category in categories:
		var prior_camera: Transform3D = stage.camera.global_transform
		garage._open_modules(category)
		focus.set_process(false)
		check(stage.camera.global_transform.is_equal_approx(prior_camera), "ouvrir un rangement commence sans saut de caméra : " + category)
		focus.advance(0.95)
		check(focus.zone == "station" and focus.station_category == category and garage._category == category, "la catégorie cadre son rangement physique : " + category)
		check_framing(focus, stage, category + " avec choix")
		var before: Dictionary = garage.loadout.duplicate(true)
		var camera_before: Transform3D = stage.camera.global_transform
		var option: Button = garage._module_options.get_child(1)
		option.mouse_entered.emit()
		option.pressed.emit()
		check(garage.loadout == before and not garage.module_installation.active and stage.camera.global_transform.is_equal_approx(camera_before), "survol et aperçu préservent équipement et caméra : " + category)
		check(garage._preview_id == str(categories[category][1]), "la carte sélectionne la fiche attendue : " + category)
		for identifier in categories[category]:
			if identifier in ["pyro_boots", "bio_injector"]:
				stage.set_mobility_module(identifier)
			focus.show_equipment(category, identifier)
			focus.advance(0.65)
			check(focus.equipment_id == identifier and not focus._holders.is_empty() and focus._effects.visible, "inspection et effet local autonomes : " + identifier)
			check_framing(focus, stage, identifier)
	garage._navigate("ROBOT")
	stage.set_mobility_module("bio_injector")
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
	check(holder.global_position.distance_to(effect_before) > 0.1, "l'effet suit la pièce pendant la rotation")
	check_framing(focus, stage, "noyau tourné")
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
	check(absf(angle_difference(yaw_gui, stage.robot.rotation.y)) > 0.2, "le vrai glisser GUI tourne le robot en inspection")
	check_framing(focus, stage, "rotation GUI en inspection")
	stage._next_gesture = -1.0
	stage.begin_robot_rotation()
	stage._advance_robot_animation(0.1)
	check(stage._gesture_clip == &"", "pas de salut pendant la rotation du robot")
	stage.end_robot_rotation()
	focus.advance(2.0)
	check(not focus._effects.visible, "l'effet disparaît après son impulsion")
	check(garage.find_child("GarageScanner", true, false) == null, "le catalogue ne présente plus de commande Scanner")
	for dimensions in [Vector2i(800, 600), Vector2i(1280, 720), Vector2i(2340, 1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		focus.set_process(false)
		garage._navigate("ARMES")
		for identifier in LOADOUT.WEAPONS:
			equip_weapon(garage, identifier)
			focus.show_equipment("weapon", identifier, false)
			focus.advance(0.60)
			check_framing(focus, stage, identifier + " " + str(dimensions))
		for category in categories:
			garage._open_modules(category)
			focus.set_process(false)
			focus.advance(0.95)
			check_framing(focus, stage, category + " rangement " + str(dimensions))
	(garage._nav["ROBOT"] as Button).pressed.emit()
	focus.advance(0.60)
	check(stage.camera.global_transform.is_equal_approx(original_camera) and not stage._equipment_focused, "ROBOT retrouve la vue générale et les animations")
	(garage._nav["MODULES"] as Button).pressed.emit()
	focus.advance(0.95)
	check(focus.zone == "station" and focus.station_category == garage._module_category and garage._module_panel.visible, "MODULES retrouve la dernière catégorie choisie")
	garage._garage_return.pressed.emit()
	focus.advance(0.95)
	check(focus.zone == "garage" and garage._hub_mode and not garage._module_panel.visible, "retour garage retrouve tous les rangements")
	garage.hide()
	await process_frame
	check(not focus.is_processing() and focus.zone == "robot", "inspection suspendue hors du garage")
	check(stage.camera.global_transform.is_equal_approx(original_camera), "sortie remet la caméra en vue générale")
	garage.show()
	await process_frame
	check(focus.is_processing(), "inspection réactivée à la réouverture")
	check(LOADOUT.load_local() == saved, "le contrôleur n'écrit aucune sauvegarde")
	garage.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE FOCUS TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func check_framing(focus: Node, stage: Node, label: String) -> void:
	var provider = stage.weapon_rack if focus.station_category == "weapon" else stage.module_stations
	var bounds: AABB = provider.bounds(focus.station_category) if focus.zone == "station" else focus.region_bounds()
	var rect: Rect2 = focus.frame_rect().grow(1.0)
	var fits := true
	for corner in 8:
		var point := bounds.get_endpoint(corner)
		var screen: Vector2 = stage.camera.unproject_position(point) * stage.size / Vector2(stage.viewport.size)
		fits = fits and not stage.camera.is_position_behind(point) and rect.has_point(screen)
	check(fits, "piece contenue entre les panneaux : " + label)
	check(stage.camera.global_position.is_finite(), "camera valide : " + label)


func equip_weapon(garage: Control, identifier: String) -> void:
	garage._navigate("ARMES")
	garage.focus.set_process(false)
	var before: Dictionary = garage.loadout.duplicate(true)
	(garage.weapon_buttons[identifier] as Button).pressed.emit()
	check(garage.loadout == before and not garage.module_installation.active, "la carte d'arme reste un aperçu : " + identifier)
	if str(before.weapon) != identifier:
		garage._equip_preview()
		garage.module_installation.set_process(false)
		check(garage.module_installation.active and garage.loadout == before, "Équiper l'arme attend la fixation : " + identifier)
		garage.module_installation.finish_now()
	check(not garage.module_installation.active and str(garage.loadout.weapon) == identifier and garage.stage.weapon_id == identifier, "la vraie arme est fixée en main : " + identifier)
	garage.focus.set_process(false)


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
