extends SceneTree

const PREFERENCES := preload("res://scripts/game_preferences.gd")
const PANEL := preload("res://scripts/comfort_settings.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var preferences = root.get_node_or_null("GamePreferences")
	if preferences == null:
		preferences = PREFERENCES.new()
		preferences.name = "GamePreferences"
		root.add_child(preferences)
	var path := "res://captures/comfort-test.cfg"
	var config := ConfigFile.new()
	config.set_value("settings", "camera_shake", false)
	config.set_value("settings", "touch_scale", 1.15)
	config.set_value("hud", "keep", "mobile layout")
	config.save(path)
	preferences.load_preferences(path)
	check(preferences.rebind("offensive", KEY_X, false) == "", "bind X")
	check(preferences.rebind("defensive", KEY_X, false) != "", "reject duplicate")
	check(preferences.rebind("defensive", KEY_ESCAPE, false) != "", "reserve Escape")
	var pressed := InputEventKey.new()
	pressed.keycode = KEY_X
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	check(Input.is_action_pressed("game_offensive"), "new key triggers action")
	var released := _key(KEY_X)
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame
	check(not Input.is_action_pressed("game_offensive"), "release triggers action release")
	check(not InputMap.event_is_action(_key(KEY_A), "game_offensive"), "old key removed")
	check(InputMap.event_is_action(_key(KEY_W), "game_move_up"), "default aliases preserved")
	preferences.set_volume("music", 0, false)
	preferences.set_volume("effects", 0.35, false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music mute")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "independent effects")
	var effect := AudioStreamPlayer3D.new()
	scene.add_child(effect)
	check(effect.bus == &"Effects", "route spatial effects")
	var music := AudioStreamPlayer.new()
	music.bus = &"Music"
	scene.add_child(music)
	check(music.bus == &"Music", "keep music routing")
	check(preferences.save_preferences(path) == OK, "save")
	preferences.reset_bindings(false)
	preferences.load_preferences(path)
	check(preferences.key_label("offensive") == "X", "key persistence")
	check(is_equal_approx(preferences.effects_volume, 0.35), "volume persistence")
	config.load(path)
	check(config.get_value("settings", "touch_scale") == 1.15 and config.get_value("hud", "keep") == "mobile layout", "keep existing settings and mobile layout")
	var panel := PANEL.new()
	panel.persist_changes = false
	root.add_child(panel)
	await process_frame
	panel.find_child("MusicVolume", true, false).value = 55
	check(is_equal_approx(preferences.music_volume, 0.55) and is_equal_approx(preferences.effects_volume, 0.35), "music slider controls only music")
	panel.find_child("EffectsVolume", true, false).value = 75
	check(is_equal_approx(preferences.effects_volume, 0.75) and is_equal_approx(preferences.music_volume, 0.55), "effects slider controls only effects")
	panel.call("_begin_capture", "offensive")
	panel.call("_input", _key(KEY_C))
	check(preferences.key_label("offensive") == "C", "UI capture")
	# Restore the real settings, never persist test bindings to the player's file.
	panel.queue_free()
	preferences.load_preferences()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("COMFORT SETTINGS TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _key(code: int) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
