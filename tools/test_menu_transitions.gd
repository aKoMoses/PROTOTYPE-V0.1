extends SceneTree

var failures: Array[String] = []
var checks := 0
var destinations: Array[String] = []
var changes := 0
var service: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while service.call("is_busy") and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(service.call("is_busy")), "loading overlay must finish")

func _expect_cached(message: String) -> void:
	_check(bool(service.call("is_busy")), message + " displays the overlay")
	var overlay: Node = service.get("_overlay")
	if overlay != null:
		_check(bool(overlay.get("presentation_only")), message + " uses a cached-menu transition")
		_check(not (overlay.get("_percent") as Label).visible, message + " does not invent a loading percentage")
		_check((overlay.get("_sweep") as Control).visible, message + " keeps a visible animated indicator")
	await _wait_idle()

func _run() -> void:
	service = root.get_node("MenuTransition")
	service.connect("transition_started", func(destination: String) -> void: destinations.append(destination))
	scene_changed.connect(func() -> void: changes += 1)
	var boot: Node = load(str(ProjectSettings.get_setting("application/run/main_scene"))).instantiate()
	root.add_child(boot)
	current_scene = boot
	_check(bool(service.call("is_busy")), "real application entry point is covered immediately")
	await _wait_idle()
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn", "boot reaches the real menu")
	_check(changes == 1, "boot emits the standard scene_changed signal")
	if current_scene == null or current_scene.get_node_or_null("Interface") == null:
		_finish()
		return
	var flow: Node = current_scene.get_node("Interface")
	flow.call("_open_equipment")
	await _expect_cached("garage")
	var garage: Node = flow.get("_forge_garage")
	var original: Dictionary = garage.get("loadout").duplicate(true)
	for tab in ["ARMES", "ROBOT", "MODULES"]:
		garage.call("_navigate", tab)
		await _expect_cached("garage tab " + tab)
	garage.call("_open_modules", "defensive")
	await _expect_cached("defensive module station")
	garage.call("_show_garage")
	await _expect_cached("garage hub")
	_check(garage.get("loadout") == original, "navigation preserves the unsaved garage build")
	flow.call("_open_settings")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_check(int(flow.get("current_screen")) == 2, "keyboard cannot navigate through the active loading screen")
	var click := InputEventMouseButton.new()
	click.position = Vector2(1000, 605)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	click.pressed = false
	root.push_input(click, true)
	_check(int(flow.get("current_screen")) == 2, "pointer cannot activate controls behind the loading screen")
	await _expect_cached("settings")
	var settings: Node = flow.get("_settings_panel")
	for index in [1, 2, 0]:
		settings.call("_select_page", index)
		await _expect_cached("settings tab %d" % index)
		_check((settings.get("_pages")[index] as Control).visible, "correct settings page remains visible")
	# Programmatic navigation updates one overlay; real users cannot double-click through it.
	flow.call("_open_menu")
	var first_overlay: Node = service.get("_overlay")
	flow.call("_open_settings")
	_check(service.get("_overlay") == first_overlay, "rapid requests do not stack overlays")
	await _wait_idle()
	_check(int(flow.get("current_screen")) == 2, "rapid navigation keeps the final requested menu")
	flow.call("_open_menu")
	await _wait_idle()
	flow.call("_open_solo_setup")
	await _expect_cached("solo setup")
	flow.call("_close_solo_setup")
	await _expect_cached("return from solo setup")
	flow.call("_open_lobby")
	await _expect_cached("multiplayer browser")
	var lobby: Node = flow.get("_lobby_panel")
	lobby.call("_on_room_changed", {"title": "Local test", "host_id": 999, "guest_id": 0})
	await _expect_cached("joined lobby")
	lobby.call("_on_room_changed", {})
	await _expect_cached("return to lobby browser")
	flow.call("_open_menu")
	await _wait_idle()
	# Real scene change from a garage trial and restoration of its draft on return.
	flow.call("_open_equipment")
	await _wait_idle()
	garage = flow.get("_forge_garage")
	var draft: Dictionary = garage.get("loadout").duplicate(true)
	draft.weapon = "shotgun" if str(draft.weapon) != "shotgun" else "blaster"
	garage.call("set_loadout", draft)
	var before_trial: Node = current_scene
	flow.call("_on_garage_test_requested", draft)
	_check(bool(service.call("is_busy")), "training trial has a real loading screen")
	_check(before_trial.process_mode == Node.PROCESS_MODE_DISABLED, "old world stops while the next scene loads")
	await _wait_idle()
	_check(current_scene.scene_file_path == "res://scenes/training_ground.tscn", "training scene becomes current")
	_check(not is_instance_valid(before_trial), "old scene is released after successful loading")
	current_scene.call("_toggle_menu")
	_check(paused, "training menu pauses gameplay")
	await _expect_cached("paused training menu")
	_check(paused, "animated transition does not unpause the training menu")
	current_scene.call("_return_to_main_menu")
	await _wait_idle()
	flow = current_scene.get_node("Interface")
	_check(int(flow.get("current_screen")) == 1, "training returns directly to the garage")
	_check((flow.get("_forge_garage") as Node).get("loadout") == draft, "scene changes preserve the unsaved garage draft")
	_check(not paused, "return from training releases scene pause")
	flow.call("_open_survival")
	await _wait_idle()
	_check(current_scene.scene_file_path == "res://scenes/survival.tscn", "survival opens through the same loader")
	var before_restart: Node = current_scene
	current_scene.call("_restart")
	await _wait_idle()
	_check(current_scene.scene_file_path == "res://scenes/survival.tscn" and not is_instance_valid(before_restart), "survival restart replaces its old world")
	current_scene.call("_return_menu")
	await _wait_idle()
	flow = current_scene.get_node("Interface")
	flow.call("_open_beginner_tutorial")
	await _wait_idle()
	_check(current_scene.scene_file_path == "res://scenes/beginner_tutorial.tscn", "tutorial opens through the loader")
	current_scene.call("_open_free_training")
	await _wait_idle()
	_check(current_scene.scene_file_path == "res://scenes/training_ground.tscn", "tutorial can load free training")
	current_scene.call("_return_to_main_menu")
	await _wait_idle()
	# A missing target never discards the source menu and offers a safe return.
	var previous: Node = current_scene
	var previous_mode := previous.process_mode
	service.call("change_scene", "res://scenes/missing-menu-transition-test.tscn", "Test…")
	for frame in 8:
		await process_frame
	var failed: Node = service.get("_overlay")
	_check(bool(failed.get("loading_failed")), "missing destination exposes failure")
	_check((failed.get("_back") as Button).visible, "failed scene loading offers a return")
	failed.call("cancel_loading")
	await _wait_idle()
	_check(current_scene == previous and previous.process_mode == previous_mode, "cancel restores the original menu")
	_check(changes >= 8, "all loaded scenes notify scene_changed observers")
	_check(destinations.size() >= 20, "navigation routes consistently use the shared screen")
	if OS.get_cmdline_user_args().has("capture-menu-transition"):
		service.call("present", "Ouverture des réglages…")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/startup-branding/menu-transition.png")
		await _wait_idle()
	current_scene.queue_free()
	for frame in 10:
		await process_frame
	_finish()

func _finish() -> void:
	for failure in failures:
		push_error("MENU TRANSITIONS: " + failure)
	print("MENU TRANSITIONS: %s (%d checks, %d destinations, %d scene changes)" % ["PASS" if failures.is_empty() else "FAIL", checks, destinations.size(), changes])
	quit(0 if failures.is_empty() else 1)
