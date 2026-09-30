extends Node

signal bindings_changed
signal audio_changed

const SAVE_PATH := "user://prototype0_settings.cfg"
const ACTIONS := ["move_up", "move_down", "move_left", "move_right", "attack", "offensive", "defensive", "mobility", "weapon", "reload"]
const LABELS := {"move_up": "Avancer", "move_down": "Reculer", "move_left": "Gauche", "move_right": "Droite", "attack": "Tirer / charger", "offensive": "Module offensif", "defensive": "Module défensif", "mobility": "Module de mobilité", "weapon": "Changer d’arme", "reload": "Recharger"}
const DEFAULT_KEYS := {"move_up": [KEY_Z, KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "move_left": [KEY_Q, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "attack": [KEY_SPACE], "offensive": [KEY_A], "defensive": [KEY_E], "mobility": [KEY_R], "weapon": [KEY_G], "reload": [KEY_T]}
const RESERVED := [KEY_ESCAPE, KEY_TAB, KEY_K, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]
var bindings: Dictionary = {}
var music_volume := 1.0
var effects_volume := 1.0

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_preferences()
	get_tree().node_added.connect(_route_audio)

func _route_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.get("bus") == &"Master":
			node.set("bus", &"Effects")

func action_name(action: String) -> StringName:
	return StringName("game_" + action)

func load_preferences(path: String = SAVE_PATH) -> void:
	var config := ConfigFile.new()
	config.load(path)
	bindings = DEFAULT_KEYS.duplicate(true)
	# Apply saved keys in action order, rejecting corrupted or conflicting values.
	for action in ACTIONS:
		var key := int(config.get_value("bindings", action, 0))
		if key > 0 and not RESERVED.has(key):
			bindings[action] = [key]
	var used: Dictionary = {}
	for action in ACTIONS:
		for key in bindings[action]:
			if used.has(key):
				bindings = DEFAULT_KEYS.duplicate(true)
				break
			used[key] = action
	music_volume = clampf(float(config.get_value("audio", "music", 1.0)), 0.0, 1.0)
	effects_volume = clampf(float(config.get_value("audio", "effects", 1.0)), 0.0, 1.0)
	apply_bindings()
	apply_audio()

func save_preferences(path: String = SAVE_PATH) -> Error:
	var config := ConfigFile.new()
	config.load(path)
	for action in ACTIONS:
		if bindings[action] == DEFAULT_KEYS[action]:
			if config.has_section_key("bindings", action):
				config.erase_section_key("bindings", action)
		else:
			config.set_value("bindings", action, int(bindings[action][0]))
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	return config.save(path)

func apply_bindings() -> void:
	for action in ACTIONS:
		var mapped := action_name(action)
		if not InputMap.has_action(mapped):
			InputMap.add_action(mapped)
		Input.action_release(mapped)
		InputMap.action_erase_events(mapped)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.keycode = key
			InputMap.action_add_event(mapped, event)
		if action == "attack":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			InputMap.action_add_event(mapped, mouse)
	bindings_changed.emit()

func binding_problem(action: String, key: int) -> String:
	if not ACTIONS.has(action) or key <= 0:
		return "Touche non reconnue."
	if RESERVED.has(key):
		return "Cette touche est réservée aux menus ou à l’entraînement."
	for other in ACTIONS:
		if other != action and bindings[other].has(key):
			return "Touche déjà utilisée : " + str(LABELS[other]) + "."
	return ""

func rebind(action: String, key: int, persist: bool = true) -> String:
	var problem := binding_problem(action, key)
	if problem != "":
		return problem
	bindings[action] = [key]
	apply_bindings()
	if persist and save_preferences() != OK:
		return "Raccourci appliqué, mais la sauvegarde a échoué."
	return ""

func reset_bindings(persist: bool = true) -> void:
	bindings = DEFAULT_KEYS.duplicate(true)
	apply_bindings()
	if persist:
		save_preferences()

func key_label(action: String) -> String:
	var key := int(bindings.get(action, DEFAULT_KEYS[action])[0])
	var compact := {KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓", KEY_SPACE: "ESP", KEY_ENTER: "ENT", KEY_KP_ENTER: "ENT", KEY_BACKSPACE: "RET", KEY_DELETE: "SUP", KEY_INSERT: "INS", KEY_HOME: "ORI", KEY_END: "FIN", KEY_PAGEUP: "PG↑", KEY_PAGEDOWN: "PG↓"}
	return str(compact.get(key, OS.get_keycode_string(key).left(3)))

func keys_label(action: String) -> String:
	var labels: PackedStringArray = []
	for key in bindings[action]:
		var names := {KEY_LEFT: "\u2190", KEY_RIGHT: "\u2192", KEY_UP: "\u2191", KEY_DOWN: "\u2193", KEY_SPACE: "Espace", KEY_ENTER: "Entr\u00e9e", KEY_BACKSPACE: "Retour", KEY_DELETE: "Suppr"}
		labels.append(str(names.get(int(key), OS.get_keycode_string(int(key)))))
	return " / ".join(labels)

func apply_audio() -> void:
	for bus_name in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		var volume := music_volume if bus_name == "Music" else effects_volume
		var index := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_mute(index, volume <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	audio_changed.emit()

func set_volume(kind: String, value: float, persist: bool = true) -> Error:
	if kind == "music":
		music_volume = clampf(value, 0.0, 1.0)
	elif kind == "effects":
		effects_volume = clampf(value, 0.0, 1.0)
	else:
		return ERR_INVALID_PARAMETER
	apply_audio()
	return save_preferences() if persist else OK
