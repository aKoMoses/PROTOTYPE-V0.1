extends SceneTree

var failures: Array[String] = []
var checks := 0
var backups: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in ["user://prototype0_settings.cfg", "user://prototype0_loadout.cfg"]:
		backups[path] = {"exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}
	# Exercise actual canvas sizes, independent of the production window's
	# canvas_items stretch, which maps physical window pixels to logical pixels.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var settings := ConfigFile.new()
	settings.set_value("settings", "camera_shake", false)
	settings.set_value("settings", "touch_scale", 1.1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	_check(settings.save("user://prototype0_settings.cfg") == OK, "isolated settings fixture saves")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var touch: Control = scene.get_node("Interface/TouchControls") if scene.has_node("Interface/TouchControls") else scene.get_node("TouchControls")
	var player: Node = scene.get_node("Player")
	_check(scene.get_meta("camera_shake_enabled", true) == false, "saved camera comfort preference applies at startup")
	_check(is_equal_approx(float(touch.get("control_scale")), 1.1), "saved touch scale applies at startup")
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720), Vector2i(800, 600)]:
		root.size = dimensions
		for screen in ["_open_menu", "_open_equipment", "_open_settings"]:
			flow.call(screen)
			await process_frame
			await process_frame
			var panel: Control = flow.get("_menu_panel" if screen == "_open_menu" else "_forge_garage" if screen == "_open_equipment" else "_settings_panel")
			var bounds := panel.get_global_rect()
			_check(bounds.position.x >= -1 and bounds.position.y >= -1 and bounds.end.x <= root.size.x + 1 and bounds.end.y <= root.size.y + 1, "%s remains inside %s: %s" % [screen, dimensions, bounds])
			_check(not touch.visible, "navigation hides touch controls")
		flow.call("_open_equipment")
		var garage: Control = flow.get("_forge_garage")
		garage.call("_open_modules", "offensive")
		await process_frame
		await process_frame
		for button in garage.get("_module_options").get_children():
			_check(button.get_global_rect().end.y <= root.size.y + 1, "module choices remain inside the viewport")
	root.size = Vector2i(1280, 720)
	flow.call("_open_equipment")
	var official: Control = flow.get("_forge_garage")
	var loadout_script: Script = load("res://scripts/loadout_state.gd")
	var saved_before_selection: Dictionary = loadout_script.load_local()
	official.call("_navigate", "ARMES")
	(official.get("weapon_buttons")["shotgun"] as Button).pressed.emit()
	(official.get("equip_button") as Button).pressed.emit()
	if official.get("module_installation").active:
		official.get("module_installation").finish_now()
	var restored: Dictionary = loadout_script.load_local()
	_check(official.get("loadout").weapon == "shotgun" and restored == saved_before_selection, "weapon selection changes the draft without saving it")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	_check(int(flow.get("current_screen")) == 1 and official.get("_hub_mode"), "Escape returns from the catalog to the garage")
	root.push_input(escape, true)
	await process_frame
	_check(int(flow.get("current_screen")) == 0, "a second Escape returns from the garage to the menu")
	flow.call("_open_equipment")
	_check(official.get("loadout").weapon == "shotgun" and loadout_script.load_local() == saved_before_selection, "draft survives reopening and the combat build remains saved separately")
	flow.call("_return_menu")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	scene.get_node("TargetDummy").call("set_training_bot_enabled", false)
	touch.visible = true
	flow.call("_toggle_pause")
	_check(paused and not touch.visible, "pause hides and suspends touch controls")
	flow.call("_resume")
	_check(not paused and bool(player.call("is_gameplay_enabled")), "resume restores combat")
	flow.call("_return_menu")
	_check(not touch.visible, "return to menu cancels touch overlay")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	for path in backups:
		if backups[path].exists:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backups[path].bytes)
			file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("NAVIGATION RELIABILITY: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
