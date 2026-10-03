extends SceneTree

const LIBRARY := preload("res://scripts/garage_build_library.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const OUTPUT := "res://captures/garage-build-journey/"
var capture_enabled := false
var failures: Array[String] = []
var checks := 0
var garage
var launches := 0
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var originals: Dictionary = {}
	for path in [LIBRARY.SAVE_PATH, LOADOUT.SAVE_PATH]:
		originals[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	if capture_enabled:
		root.get_node("FramePacing")._panel.hide()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).store_string("\n")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle()
	var flow = scene.get_node("Interface")
	flow._open_equipment()
	await _settle()
	garage = flow._forge_garage
	check(garage._view == "entry", "production opening shows the entry screen")
	await _click(garage._back_button)
	check(not garage.visible, "entry back exits to the main menu")
	flow._open_equipment()
	garage.start_requested.disconnect(flow._start_duel)
	garage.start_requested.connect(func(): launches += 1)
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://garage-journey-" + suffix + ".cfg", "user://garage-journey-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	garage._library = LIBRARY.load_local(paths[0], paths[1])
	garage._select_build(0)
	garage._show_entry(false)
	_pause()
	check(garage._view == "entry", "garage starts with the entry choice")
	check(garage._entry_choices.size() == 2 and not garage._save_button.visible, "entry exposes only edit and create")
	await _frame("pc-entry")
	await _click(garage._entry_choices["MODIFIER UN BUILD"])
	check(garage._view == "hub" and garage._edit_choices.size() == 5, "edit opens five equipment categories")
	for kind in garage.BUILD_STEPS:
		check(garage._edit_choices[kind].get_node("HubIcon").texture == garage._icons.get_icon(str(garage.loadout[kind])), "edit uses existing equipped icon: " + kind)
	await _frame("pc-edit")
	for kind in garage.BUILD_STEPS:
		await _click(garage._edit_choices[kind])
		garage.focus.advance(1.0)
		_pause()
		check(garage._category == kind and garage.focus.zone == "station" and garage.focus.station_category == kind, "edit reaches physical rack: " + kind)
		check(garage._equipment_display == null or not garage._equipment_display.visible, "rack replaces isolated equipment zoom: " + kind)
		check(not garage._detail_panel.visible, "description stays closed on rack arrival: " + kind)
		var rack_rect: Rect2 = garage._ui.get_meta("preview_rect")
		check(rack_rect.size.x >= garage._ui.size.x * 0.65 and rack_rect.size.y >= garage._ui.size.y * 0.7, "rack receives most of the desktop view: " + kind)
		await _frame("pc-rack-" + kind)
		await _click(garage._back_button)
		check(garage._view == "hub", "rack back returns to five categories: " + kind)
	await _click(garage._edit_choices.weapon)
	await _click(garage._choices.weapon.shotgun)
	check(garage._view == "detail" and garage._detail_panel.visible and not garage._grids.weapon.visible, "desktop click opens description and hides the choice list")
	await _frame("pc-weapon-detail")
	await _click(garage._back_button)
	check(garage._view == "catalog" and not garage._detail_panel.visible, "desktop back closes description")
	await _click(garage._choices.weapon.shotgun)
	await _click(garage.equip_button)
	check(garage.module_installation.active, "edit starts a real weapon installation")
	garage.module_installation.finish_now()
	_pause()
	check(garage.loadout.weapon == "shotgun" and garage._view == "hub", "editing returns to categories after installation")
	garage._show_entry(false)
	await _click(garage._entry_choices["CRÉER UN BUILD"])
	check(garage._creating and garage._journey_step == 0 and garage._category == "weapon", "creation begins with weapons")
	await _frame("pc-create-weapon")
	var defaults: Dictionary = garage.loadout.duplicate(true)
	var library_before: Dictionary = garage._library.duplicate(true)
	garage._save_build()
	check(not garage.installation.active and garage._library == library_before and not FileAccess.file_exists(paths[0]), "incomplete creation cannot save")
	garage._open_station("passive")
	check(garage._category == "weapon", "guided creation cannot bypass a step")
	await _click(garage._choices.weapon.shotgun)
	check(garage.loadout == defaults and not garage.module_installation.active, "preview changes no equipment")
	await _click(garage.equip_button)
	check(garage.module_installation.active and garage._journey_step == 0, "step waits for installation completion")
	garage.module_installation.cancel()
	_pause()
	check(garage._journey_step == 0 and garage.loadout == defaults, "cancel before mounting preserves the current step and build")
	garage._preview_equipment("weapon", str(defaults.weapon))
	await _click(garage.equip_button)
	check(garage._journey_step == 1 and garage._category == "offensive", "validating the default weapon advances")
	await _click(garage._back_button)
	check(garage._journey_step == 0 and garage._category == "weapon", "back revisits the preceding creation step")
	garage._preview_equipment("weapon", "shotgun")
	await _click(garage.equip_button)
	garage.module_installation.finish_now()
	_pause()
	check(garage._journey_step == 1 and garage._category == "offensive", "new weapon advances after mounting")
	check(not garage._detail_panel.visible, "next creation step starts with description closed")
	await _frame("pc-create-offensive")
	var draft: Dictionary = garage.draft_state()
	garage._show_entry(false)
	garage.restore_draft(draft)
	check(garage._creating and garage._journey_step == 1 and garage._category == "offensive", "training return restores the creation step")
	var picks := {"offensive": "rocket_basket", "defensive": "projector", "mobility": "eclipse", "passive": "inertia"}
	for kind in picks:
		check(garage._category == kind, "creation follows the required order: " + kind)
		garage._preview_equipment(kind, picks[kind])
		await _click(garage.equip_button)
		check(garage.module_installation.active, "real module installs: " + kind)
		garage.module_installation.finish_now()
		_pause()
		check(garage.loadout[kind] == picks[kind], "selected module mounts: " + kind)
	check(garage._journey_step == 5 and garage._view == "summary", "fifth validation reaches the completed build")
	await _frame("pc-summary")
	garage._summary_name.text = "PARCOURS TEST"
	garage._summary_name.text_changed.emit("PARCOURS TEST")
	await _click(garage._save_button)
	check(garage.installation.active and launches == 0, "Save starts saving without launching combat")
	garage._skip_installation()
	_pause()
	var saved: Dictionary = LIBRARY.load_local(paths[0], paths[1])
	check(saved.builds.size() == 2 and saved.builds[1].name == "PARCOURS TEST", "new named build persists without replacing original")
	check(saved.builds[1].loadout == garage.loadout and not garage.is_dirty(), "saved equipment round-trips and clears draft state")
	check(launches == 0 and garage._view == "hub" and not garage._creating, "save leaves the player in the garage editor")
	check(flow.loadout == garage.loadout, "Save synchronizes the build used by combat")
	garage._select_build(0)
	check(garage.loadout == library_before.builds[0].loadout, "original saved build remains intact")
	garage._select_build(1)
	check(garage.loadout == saved.builds[1].loadout, "saved build selector restores the new build")
	for profile in ["compact", "safe-mobile", "stretched-mobile"]:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if profile == "stretched-mobile" else Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i(1280, 720) if profile == "stretched-mobile" else Vector2i.ZERO
		root.size = Vector2i(667, 375) if profile == "compact" else Vector2i(844, 390)
		await create_timer(0.2).timeout
		await _settle()
		garage.safe_area_override = Rect2(59, 0, 726, 369) if profile == "safe-mobile" else Rect2()
		garage._select_build(1)
		garage._show_entry(false)
		await _frame(profile + "-entry")
		await _click(garage._entry_choices["MODIFIER UN BUILD"], true)
		await _frame(profile + "-edit")
		await _click(garage._edit_choices.weapon, true)
		check(garage._view == "catalog" and garage.focus.zone == "station", "touch opens the rack: " + profile)
		check(not garage._detail_panel.visible, "touch rack starts without description: " + profile)
		await _frame(profile + "-rack")
		await _click(garage._choices.weapon.blaster, true)
		check(garage._view == "detail", "touch opens equipment validation: " + profile)
		await _frame(profile + "-detail")
		await _click(garage._back_button, true)
		check(garage._view == "catalog" and not garage._detail_panel.visible, "touch back closes description: " + profile)
		garage._show_entry(false)
		await _click(garage._entry_choices["CRÉER UN BUILD"], true)
		await _frame(profile + "-create")
		for kind in garage.BUILD_STEPS:
			var expected_step: int = garage.BUILD_STEPS.find(kind) + 1
			check(garage._category == kind, "touch preserves creation order: " + profile + "/" + kind)
			garage._preview_equipment(kind, str(garage.loadout[kind]))
			await _click(garage.equip_button, true)
			check(garage._journey_step == expected_step, "one touch validates one step: " + profile + "/" + kind)
		check(garage._view == "summary", "touch validates all five default equipment slots: " + profile)
		await _frame(profile + "-summary")
	for path in originals:
		var bytes = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(bytes == originals[path], "verification preserves the actual player's save: " + path)
	scene.queue_free()
	await _settle()
	await create_timer(0.3).timeout
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("GARAGE BUILD JOURNEY: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks; ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _frame(filename: String) -> void:
	garage.focus.advance(1.0)
	_pause()
	await _settle()
	var screen := Rect2(Vector2.ZERO, Vector2(root.size))
	for button: BaseButton in garage._ui.find_children("*", "BaseButton", true, false):
		if not button.is_visible_in_tree():
			continue
		var rect := root.get_final_transform() * button.get_global_transform() * Rect2(Vector2.ZERO, button.size)
		check(screen.grow(1).encloses(rect), "button fits " + filename + "/" + str(button.name))
		check(rect.size.x >= 43.5 and rect.size.y >= 43.5, "touch target " + filename + "/" + str(button.name))
		if garage.safe_area_override.has_area():
			check(garage.safe_area_override.grow(1).encloses(rect), "safe inset " + filename + "/" + str(button.name))
	if capture_enabled:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OUTPUT + filename + ".png") == OK, "capture " + filename)
		print("JOURNEY CAPTURE: ", filename, " window=", root.size, " compact=", garage._compact_layout, " view=", garage._view, " step=", garage._journey_step)


func _click(button: BaseButton, touch: bool = false) -> void:
	await _settle()
	var point: Vector2 = button.get_global_transform() * (button.size * 0.5)
	for pressed in [true, false]:
		if touch:
			var finger := InputEventScreenTouch.new()
			finger.position = point
			finger.pressed = pressed
			root.push_input(finger, true)
		# Viewport input emulates the mouse from touch in both rendered and
		# headless runs. An explicit counterpart would validate two steps.
		if not touch:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			event.pressed = pressed
			root.push_input(event, true)
		await _settle()
	_pause()
	if capture_enabled:
		print("JOURNEY INPUT: ", button.name, " view=", garage._view, " step=", garage._journey_step)


func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage.installation.set_process(false)


func _settle() -> void:
	for frame in 4:
		await process_frame


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
