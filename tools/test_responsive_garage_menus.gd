extends SceneTree

const LIBRARY := preload("res://scripts/garage_build_library.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const OUTPUT := "res://captures/responsive-garage/"
const PROFILES := [
	{"id": "pc", "size": Vector2i(1280, 720), "side": 0, "bottom": 0},
	{"id": "pc-wide", "size": Vector2i(1920, 1080), "side": 0, "bottom": 0},
	{"id": "compact", "size": Vector2i(667, 375), "side": 0, "bottom": 0},
	{"id": "iphone", "size": Vector2i(844, 390), "side": 59, "bottom": 21},
	{"id": "iphone-large", "size": Vector2i(932, 430), "side": 59, "bottom": 21},
]
var capture_enabled := false
var failures: Array[String] = []
var checks := 0
var frames: Array[Dictionary] = []
var garage
var flow
var paths: Array[String] = []
var original_files: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in [LIBRARY.SAVE_PATH, LOADOUT.SAVE_PATH]:
		original_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	if capture_enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).store_string("\n")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle()
	flow = scene.get_node("Interface")
	var menu = flow._menu_panel
	check(menu._buttons.size() == 3, "home has three primary entries")
	await _click(menu._buttons[0].get_child(1))
	check(menu.page == "play" and menu._buttons.size() == 3, "Jouer exposes solo, multiplayer and survival")
	await _click(menu._buttons[0].get_child(1))
	check(flow._solo_setup.visible, "solo entry opens the existing arena and loadout setup")
	flow._close_solo_setup()
	menu.back()
	await _click(menu._buttons[2].get_child(1))
	check(menu.page == "training" and menu._buttons.size() == 2, "training keeps free ground and tutorial")
	menu.back()
	flow._open_equipment()
	await _settle()
	garage = flow._forge_garage
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://responsive-garage-" + suffix + ".cfg", "user://responsive-garage-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	garage._library = LIBRARY.load_local(paths[0], paths[1])
	garage._select_build(0)
	_pause()
	for profile: Dictionary in PROFILES:
		root.size = profile.size
		await _settle()
		var safe := Rect2(profile.side, 0, profile.size.x - profile.side * 2, profile.size.y - profile.bottom)
		garage.safe_area_override = safe
		menu.safe_area_override = safe
		garage._select_build(0)
		flow._open_menu()
		await _settle()
		await _check_view(profile.id, "home", menu)
		menu.show_page("play")
		await _check_view(profile.id, "modes", menu)
		menu.show_page("training")
		await _check_view(profile.id, "training", menu)
		flow._open_equipment()
		garage._show_garage(false)
		garage.focus.advance(0)
		_pause()
		await _check_view(profile.id, "garage", garage._ui)
		check(not garage._build_selector.is_visible_in_tree(), "build management leaves the atelier: " + str(profile.id))
		for category in ["weapon", "passive", "offensive", "defensive", "mobility", "robot"]:
			garage._navigate("ROBOT") if category == "robot" else garage._open_station(category)
			garage.focus.advance(1)
			_pause()
			await _check_view(profile.id, category + "-catalog", garage._ui)
			var before: Dictionary = garage.loadout.duplicate(true)
			var identifier: String = "shotgun" if category == "weapon" else ("omnivamp" if category == "passive" else str(garage._options(category)[0]))
			await _click(garage._choices[category][identifier], true)
			garage.focus.advance(1)
			_pause()
			if category != "robot":
				check(garage.loadout == before and not garage.module_installation.active, "preview preserves the build: " + str(profile.id) + "/" + category)
				check(garage._detail_panel.is_visible_in_tree(), "selection exposes readable detail: " + str(profile.id) + "/" + category)
				check(not garage._training_demo.video.is_playing(), "video remains stopped until requested")
				if garage._compact_layout:
					check(not garage._grids[category].visible and garage._view == "detail", "compact selection opens its own detail screen")
					await _check_view(profile.id, category + "-detail", garage._ui)
					await _click(garage._back_button, true)
					check(garage._view == "catalog" and garage._category == category, "back restores the same family")
				else:
					check(garage._grids[category].visible, "PC retains catalog next to detail")
			elif garage._compact_layout:
				await _check_view(profile.id, "robot-detail", garage._ui)
		garage._show_builds()
		garage.focus.advance(1)
		await _check_view(profile.id, "builds", garage._ui)
		await _click(garage._build_actions[0], true)
		check(garage._rename_panel.visible, "rename opens from build management")
		garage._name_input.text = "TEST UI"
		garage._finish_rename()
		check(garage.build_name == "TEST UI" and garage._save_state.text == "BROUILLON •", "rename updates the draft indicator")
	# A real installation and persistent round-trip on isolated files.
	garage._open_station("passive")
	garage._preview_equipment("passive", "omnivamp")
	garage._equip_preview()
	check(garage.module_installation.active, "Install starts the real service arm")
	garage.module_installation.finish_now()
	check(garage.loadout.passive == "omnivamp", "the mounting commits only the selected passive")
	garage._open_demo()
	check(garage._training_demo._viewer.visible and garage._training_demo.video.is_playing(), "requested demo opens and plays")
	garage._training_demo.close_enlarged()
	check(not garage._training_demo.visible and not garage._training_demo.video.is_playing(), "closing the demo stops decoding")
	garage._show_builds()
	garage._save_build()
	garage._skip_installation()
	check(LIBRARY.load_local(paths[0], paths[1]).builds[0].loadout.passive == "omnivamp", "build save persists equipment on isolated files")
	check(not garage.is_dirty(), "saved state clears the draft indicator")
	garage._duplicate_build()
	garage._name_input.text = "COPIE UI"
	garage._finish_rename()
	garage._save_build()
	garage._skip_installation()
	check(LIBRARY.load_local(paths[0], paths[1]).builds.size() == 2, "duplicate preserves the original and adds a build")
	garage._select_build(0)
	check(garage.build_name == "TEST UI", "saved build selection restores the first name")
	# Observe launch signals without starting a match or writing the real loadout.
	garage.start_requested.disconnect(flow._start_duel)
	var launches := [0]
	garage.start_requested.connect(func(): launches[0] += 1)
	garage._save_then_play()
	check(garage.installation.active and launches[0] == 0, "switching the active build saves before launching")
	garage._skip_installation()
	check(launches[0] == 1 and flow.loadout == garage.loadout, "save completes before the launch signal and synchronizes the selected build")
	garage._save_then_play()
	check(launches[0] == 2 and not garage.installation.active, "a saved active build launches without another service sequence")
	garage._rename_build()
	garage._name_input.text = "BUILD JOUER"
	garage._finish_rename()
	garage._save_then_play()
	check(garage.installation.active and launches[0] == 2, "a draft launches only after its save")
	garage._skip_installation()
	check(launches[0] == 3 and not garage.is_dirty(), "a saved draft launches exactly once")
	check(LIBRARY.load_local(paths[0], paths[1]).builds[0].name == "BUILD JOUER", "Jouer persists the selected build before launching")
	# Verify the production canvas-items stretch, not only unscaled captures.
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(844, 390)
	garage.safe_area_override = Rect2()
	await _settle()
	garage._show_garage(false)
	garage.focus.advance(0)
	await _check_view("iphone-stretched", "garage", garage._ui)
	garage._open_station("weapon")
	await _settle()
	check(garage._compact_layout and not garage._detail_panel.visible, "real game stretch still selects the compact layout")
	await _check_view("iphone-stretched", "weapons", garage._ui)
	garage.hide()
	check(garage.stage.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not garage.focus.is_processing(), "hidden garage suspends rendering and camera")
	for path in original_files:
		var bytes = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(bytes == original_files[path], "verification preserves the player's actual save: " + path)
	if capture_enabled:
		FileAccess.open(OUTPUT + "verification.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "frames": frames}, "\t"))
	scene.queue_free()
	await _settle()
	await create_timer(0.3).timeout
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("RESPONSIVE GARAGE MENUS: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks; ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _check_view(profile: String, view: String, control: Control) -> void:
	await _settle()
	var scale: float = root.get_final_transform().get_scale().y
	var screen := Rect2(Vector2.ZERO, Vector2(root.size))
	for button: BaseButton in control.find_children("*", "BaseButton", true, false):
		if not button.is_visible_in_tree():
			continue
		var rect := root.get_final_transform() * button.get_global_transform() * Rect2(Vector2.ZERO, button.size)
		check(screen.grow(1).encloses(rect), "button fits: " + profile + "/" + view + "/" + str(button.name))
		check(rect.size.x >= 43.5 and rect.size.y >= 43.5, "comfortable target: " + profile + "/" + view + "/" + str(button.name))
		var safe: Rect2 = garage.safe_area_override if garage != null else Rect2()
		if safe.has_area():
			check(safe.grow(1).encloses(rect), "safe inset: " + profile + "/" + view + "/" + str(button.name))
	if control == garage._ui and garage._detail_panel.visible:
		check(garage._detail_description.get_theme_font_size("font_size") * garage._ui.scale.y * scale >= 11, "readable body text: " + profile + "/" + view)
		if garage._compact_layout:
			check(garage._detail_description.text.contains(LOADOUT.stat_line(garage._preview_id)), "compact detail retains the complete equipment values: " + profile + "/" + view)
	if capture_enabled:
		await RenderingServer.frame_post_draw
		var filename := profile + "-" + view + ".png"
		check(root.get_texture().get_image().save_png(OUTPUT + filename) == OK, "saved " + filename)
		frames.append({"profile": profile, "view": view, "file": filename, "window": [root.size.x, root.size.y]})


func _click(button: BaseButton, touch: bool = false) -> void:
	var point: Vector2 = button.get_global_transform() * (button.size * 0.5)
	for pressed in [true, false]:
		if touch:
			var finger := InputEventScreenTouch.new()
			finger.index = 0
			finger.position = point
			finger.pressed = pressed
			root.push_input(finger, true)
		# Windows push_input does not synthesize the OS mouse-from-touch event.
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.device = InputEvent.DEVICE_ID_EMULATION if touch else 0
		root.push_input(event, true)
		await _settle()


func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)


func _settle() -> void:
	for frame in 4:
		await process_frame


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
