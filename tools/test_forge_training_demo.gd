extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const DEMO := preload("res://scripts/forge_training_demo.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var garage = load("res://scenes/forge_garage_preview.tscn").instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	var preview = garage.get("_training_demo")
	check(not garage.get("_nav").has("INSPECTER"), "les onglets ouvrent les catalogues")
	for identifier in LOADOUT.ROBOTS:
		var button: Button = garage.robot_buttons[identifier]
		check(button.get_global_rect().end.x < preview.get_global_rect().position.x, "chassis a gauche de la fiche et de sa video : " + identifier)
		button.pressed.emit()
		check(garage.loadout.robot == identifier, "choix chassis conserve : " + identifier)
	check(preview.get_parent().name == "EquipmentDetail", "video dans la fiche a droite")
	check(preview.position.y > garage.get("_detail_description").get_parent().get_rect().end.y, "video sous la description")
	check(preview.video.volume_db <= -80, "demo silencieuse")
	var identifiers: Array = LOADOUT.WEAPONS + LOADOUT.OFFENSIVE + LOADOUT.DEFENSIVE + LOADOUT.MOBILITY + LOADOUT.PASSIVES
	for identifier in identifiers:
		preview.show_equipment(identifier)
		if not DEMO.CLIPS.has(identifier):
			check(preview.equipment_id == identifier and not preview.visible and preview.video.stream == null and not preview.video.is_playing(), "nouveau module sans ancienne demo : " + identifier)
			continue
		await create_timer(0.45).timeout
		check(preview.video.is_playing() and preview.video.get_stream_position() > 0, "video decodee et lue : " + identifier)
		check(preview.title.text == LOADOUT.display_name(identifier), "titre correspondant : " + identifier)
		check(preview.video.get_video_texture().get_width() >= 640, "image video chargee : " + identifier)
	for identifier in LOADOUT.WEAPONS:
		garage.weapon_buttons[identifier].pressed.emit()
		check(preview.equipment_id == identifier and garage.loadout.weapon == identifier, "selection arme actualise la demo : " + identifier)
	var equipped: Dictionary = garage.loadout.duplicate(true)
	garage.call("_open_weapon_info", "blaster")
	check(preview.equipment_id == "blaster" and garage.loadout == equipped, "fiche arme montre la demo sans changer le build")
	for category in ["offensive", "defensive", "mobility", "passive"]:
		garage.call("_open_modules", category)
		check(preview.equipment_id == garage.loadout[category], "ouverture montre le module equipe")
		var option: Button = garage.get("_module_options").get_child(1)
		option.mouse_entered.emit()
		check(garage.loadout == equipped, "survol module preserve le build")
		option.pressed.emit()
		check(preview.equipment_id == garage.loadout[category], "selection module actualise la demo")
		equipped = garage.loadout.duplicate(true)
	preview.show_equipment("blaster")
	preview.video.finished.emit()
	check(preview.video.is_playing(), "lecture en boucle")
	await check_enlarged(garage, preview)
	garage.hide()
	await process_frame
	check(not preview.video.is_playing(), "lecture suspendue hors forge")
	garage.show()
	await create_timer(0.12).timeout
	check(preview.video.is_playing(), "lecture reprise a la reouverture")
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1920, 1080)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		garage.size = dimensions
		await process_frame
		var bounds: Rect2 = preview.get_global_rect()
		check(bounds.position.x >= 0 and bounds.end.x <= dimensions.x and bounds.end.y <= dimensions.y, "video contenue a " + str(dimensions))
		for button in garage.robot_buttons.values():
			check(button.get_global_rect().end.x < bounds.position.x, "catalogue et video sans chevauchement")
		await click(bounds.get_center())
		check(preview._viewer.visible, "clic sur miniature a " + str(dimensions))
		var frame: Rect2 = preview._viewer_panel.get_global_rect()
		check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(frame), "video agrandie contenue a " + str(dimensions))
		check(is_equal_approx(preview.video.size.x / preview.video.size.y, 16.0 / 9.0), "proportions 16:9 conservees")
		check(preview.video.get_global_rect().size.x > bounds.size.x * 3.0, "video reellement agrandie")
		await click(preview._close_button.get_global_rect().get_center())
		check(not preview._viewer.visible and preview.video.get_parent() == preview._video_layer, "bouton ferme et rend la miniature")
	preview.show_enlarged()
	garage.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE TRAINING DEMO TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " echecs)")
	quit(0 if failures.is_empty() else 1)


func check_enlarged(garage, preview) -> void:
	var original_build: Dictionary = garage.loadout.duplicate(true)
	var back_requests := [0]
	garage.back_requested.connect(func() -> void: back_requests[0] += 1)
	preview.show_equipment("mekatana")
	await create_timer(0.6).timeout
	var original_video: VideoStreamPlayer = preview.video
	var position_before: float = original_video.get_stream_position()
	garage.get("_module_panel").show()
	await click(preview.video.get_global_rect().get_center())
	check(preview._viewer.visible, "clic GUI ouvre la video")
	check(preview.video == original_video and preview.video.get_stream_position() >= position_before, "agrandissement sans redemarrer la lecture")
	check(preview._viewer_title.text == LOADOUT.display_name("mekatana"), "titre de la video agrandie")
	check(preview.video.is_playing() and preview.video.volume_db <= -80, "grande video en lecture silencieuse")
	await click(preview.video.get_global_rect().get_center())
	check(preview._viewer.visible, "clic dans la video ne ferme pas la vue")
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == preview._close_button, "focus clavier reste dans la vue")
	await key(KEY_ESCAPE)
	check(not preview._viewer.visible and garage.get("_module_panel").visible and back_requests[0] == 0, "Echap ferme seulement la video")
	garage.get("_module_panel").hide()
	check(preview.video.get_parent() == preview._video_layer and preview.video.is_playing(), "lecture rendue a la miniature")
	await click(preview.video.get_global_rect().get_center())
	await click(Vector2(4, 4))
	check(not preview._viewer.visible and back_requests[0] == 0, "clic hors cadre ferme sans atteindre le garage")
	preview.grab_focus()
	await key(KEY_ENTER)
	check(preview._viewer.visible, "ouverture au clavier")
	await click(preview._close_button.get_global_rect().get_center())
	check(not preview._viewer.visible, "bouton de fermeture via GUI")
	var point: Vector2 = preview.video.get_global_rect().get_center()
	await touch(point, true)
	check(preview._viewer.visible, "toucher ouvre la video")
	await mouse_button(point, true, InputEvent.DEVICE_ID_EMULATION)
	check(preview._viewer.visible, "clic synthetique ne referme pas apres le toucher")
	await mouse_button(point, false, InputEvent.DEVICE_ID_EMULATION)
	await touch(point, false)
	var return_point: Vector2 = garage.get("_ui").get_global_transform() * Vector2(50, 675)
	await touch(return_point, true)
	await mouse_button(return_point, true, InputEvent.DEVICE_ID_EMULATION)
	await touch(return_point, false)
	await mouse_button(return_point, false, InputEvent.DEVICE_ID_EMULATION)
	check(not preview._viewer.visible, "toucher hors cadre ferme la video")
	check(back_requests[0] == 0, "toucher hors cadre ne clique pas Retour derriere")
	preview.show_enlarged()
	preview.video.finished.emit()
	check(preview.video.is_playing(), "grande video boucle")
	garage.hide()
	await process_frame
	check(not preview._viewer.visible and not preview.video.is_playing() and preview.video.get_parent() == preview._video_layer, "fermer la forge retire aussi la grande video")
	garage.show()
	await process_frame
	check(not preview._viewer.visible and preview.video.is_playing(), "reouverture avec la miniature")
	check(garage.loadout == original_build and back_requests[0] == 0, "agrandir preserve le build et la forge")


func click(point: Vector2) -> void:
	await mouse_button(point, true)
	await mouse_button(point, false)


func mouse_button(point: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.device = device
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
