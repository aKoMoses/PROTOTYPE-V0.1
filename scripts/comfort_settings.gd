extends VBoxContainer

const PREFERENCES := preload("res://scripts/game_preferences.gd")

var _preferences: Node
var _buttons: Dictionary = {}
var _capture_action := ""
var _message: Label
var persist_changes := true

func _ready() -> void:
	_preferences = get_node("/root/GamePreferences")
	add_theme_constant_override("separation", 8)
	for entry in [["music", "Musique"], ["effects", "Effets sonores"]]:
		var kind: String = entry[0]
		var row := HBoxContainer.new()
		add_child(row)
		var title := Label.new()
		title.text = entry[1]
		title.custom_minimum_size.x = 160
		row.add_child(title)
		var slider := HSlider.new()
		slider.name = kind.to_pascal_case() + "Volume"
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = float(_preferences.get(kind + "_volume")) * 100.0
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 55
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.text = "%d %%" % int(slider.value)
		row.add_child(value)
		slider.value_changed.connect(func(amount: float) -> void:
			value.text = "%d %%" % int(amount)
			var error := int(_preferences.call("set_volume", kind, amount / 100.0, persist_changes))
			if error != OK:
				_message.text = "Volume appliqué, mais la sauvegarde a échoué."
		)
	var camera_row := HBoxContainer.new()
	add_child(camera_row)
	var camera_title := Label.new()
	camera_title.text = "Caméra de combat"
	camera_title.custom_minimum_size.x = 160
	camera_row.add_child(camera_title)
	var zoom := HSlider.new()
	zoom.name = "CombatZoom"
	zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom.min_value = 100
	zoom.max_value = 125
	zoom.step = 1
	zoom.value = float(_preferences.get("combat_zoom")) * 100.0
	zoom.tooltip_text = "Rapproche le robot. 100 % conserve le champ de vision le plus large."
	camera_row.add_child(zoom)
	var zoom_value := Label.new()
	zoom_value.custom_minimum_size.x = 55
	zoom_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_value.text = "%d %%" % int(zoom.value)
	camera_row.add_child(zoom_value)
	zoom.value_changed.connect(func(amount: float) -> void:
		zoom_value.text = "%d %%" % int(amount)
		if _preferences.call("set_combat_zoom", amount / 100.0, persist_changes) != OK:
			_message.text = "Caméra appliquée, mais la sauvegarde a échoué."
	)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 12)
	add_child(_message)
	if OS.has_feature("mobile"):
		return
	var toggle := Button.new()
	toggle.text = "RACCOURCIS CLAVIER"
	toggle.toggle_mode = true
	toggle.custom_minimum_size.y = 38
	add_child(toggle)
	var keys := VBoxContainer.new()
	keys.visible = false
	add_child(keys)
	toggle.toggled.connect(func(open: bool) -> void:
		keys.visible = open
		if not open:
			_cancel_capture()
	)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	keys.add_child(grid)
	for action in PREFERENCES.ACTIONS:
		var label := Label.new()
		label.text = PREFERENCES.LABELS[action]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12)
		grid.add_child(label)
		var button := Button.new()
		button.name = str(action).to_pascal_case() + "Binding"
		if action == "attack":
			label.tooltip_text = "Le clic gauche reste disponible pour tirer."
		button.custom_minimum_size = Vector2(86, 36)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func() -> void: _begin_capture(action))
		grid.add_child(button)
		_buttons[action] = button
	var reset := Button.new()
	reset.text = "RÉTABLIR LES TOUCHES"
	reset.pressed.connect(func() -> void:
		_cancel_capture()
		_preferences.call("reset_bindings", persist_changes)
		_message.text = "Touches d’origine rétablies."
	)
	keys.add_child(reset)
	_preferences.connect("bindings_changed", _refresh_keys)
	_refresh_keys()

func _refresh_keys() -> void:
	for action in _buttons:
		_buttons[action].text = _preferences.call("keys_label", action)
		_buttons[action].tooltip_text = _preferences.call("keys_label", action)

func _begin_capture(action: String) -> void:
	_cancel_capture()
	_capture_action = action
	_buttons[action].text = "…"
	_message.text = "Appuie sur une touche pour « %s ». Échap annule." % PREFERENCES.LABELS[action]

func _cancel_capture() -> void:
	_capture_action = ""
	if _preferences != null:
		_refresh_keys()

func _input(event: InputEvent) -> void:
	if _capture_action == "" or not is_visible_in_tree() or not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_cancel_capture()
		_message.text = "Modification annulée."
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed or event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		_message.text = "Choisis une touche seule, sans Ctrl, Alt ou Maj."
		return
	var problem := str(_preferences.call("rebind", _capture_action, event.keycode, persist_changes))
	if problem != "":
		_message.text = problem
		return
	_cancel_capture()
	_message.text = "Raccourci enregistré."
	get_viewport().gui_release_focus()
