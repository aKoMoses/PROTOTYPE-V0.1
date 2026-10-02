extends "res://scripts/ui/industrial_screen.gd"

const PREFERENCES := preload("res://scripts/game_preferences.gd")
var _flow: Node
var _preferences: Node
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _bindings: Dictionary = {}
var _capture_action := ""
var _message: Label
var _shake: CheckButton
var _touch: HSlider
var _touch_value: Label
var _volumes: Dictionary = {}
var _zoom: HSlider
var _zoom_value: Label

func configure(flow: Node) -> void:
	_flow = flow
	_preferences = get_node("/root/GamePreferences")
	title_label.text = "RÉGLAGES"
	for i in range(3):
		var title: String = ["AUDIO ET CONFORT", "COMMANDES", "INTERFACE"][i]
		var tab := button(canvas, title, Rect2(175+i*307, 180, 295, 44), _select_page.bind(i))
		tab.set_meta("tab", true)
		tab.name = ["AudioTab", "CommandsTab", "InterfaceTab"][i]
		_tabs.append(tab)
		var page := Control.new()
		page.position = Vector2(170, 242)
		page.size = Vector2(950, 306)
		canvas.add_child(page)
		_pages.append(page)
	_build_audio()
	_build_commands()
	_build_interface(_pages[2])
	footer()
	_message = text(canvas, "Sauvegarde automatique", Rect2(185, 581, 620, 45), 16, MUTED)
	button(canvas, "RETOUR AU MENU", Rect2(860, 583, 246, 44), _flow._open_menu).name = "SettingsReturn"
	_preferences.bindings_changed.connect(_refresh_keys)
	visibility_changed.connect(_on_visibility)
	_select_page(0)
	_refresh_keys()

func _select_page(index: int) -> void:
	_cancel_capture()
	for i in range(_pages.size()):
		_pages[i].visible = i == index
		_tabs[i].add_theme_color_override("font_color", ORANGE if i == index else MUTED)
		_tabs[i].set_meta("selected", i == index)
		_tabs[i].queue_redraw()

func _build_audio() -> void:
	var page := _pages[0]
	var audio := section(page, "AUDIO", Rect2(0, 0, 450, 242))
	for entry in [["music", "Musique", 70], ["effects", "Effets sonores", 124]]:
		var kind: String = entry[0]
		var y: float = entry[2]
		text(audio, entry[1], Rect2(20, y, 147, 40), 17)
		var slider := HSlider.new()
		slider.name = kind.to_pascal_case()+"Volume"
		slider.position = Vector2(164, y)
		slider.size = Vector2(203, 40)
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = float(_preferences.get(kind+"_volume"))*100.0
		style_slider(slider)
		audio.add_child(slider)
		var value := text(audio, "%d %%" % int(slider.value), Rect2(375, y, 63, 40), 18)
		_volumes[kind] = {"slider": slider, "value": value}
		slider.value_changed.connect(func(amount: float) -> void:
			value.text = "%d %%" % int(amount)
			if int(_preferences.call("set_volume", kind, amount/100.0)) != OK:
				_message.text = "Volume appliqué. Sauvegarde indisponible."
		)
	var comfort := section(page, "CONFORT", Rect2(466, 0, 484, 242))
	text(comfort, "Secousses de caméra", Rect2(20, 70, 290, 40), 17)
	_shake = CheckButton.new()
	_shake.name = "CameraShake"
	_shake.position = Vector2(381, 72)
	_shake.size = Vector2(80, 40)
	_shake.tooltip_text = "Secousses de caméra"
	_shake.button_pressed = bool(_flow.get("_settings").camera_shake)
	style_toggle(_shake)
	comfort.add_child(_shake)
	_shake.toggled.connect(func(value: bool) -> void:
		_flow.get("_settings").camera_shake = value
		_flow.call("_save_settings")
		_flow.get("main").set_meta("camera_shake_enabled", value)
	)
	text(comfort, "Contrôles tactiles", Rect2(20, 124, 180, 40), 17)
	_touch = HSlider.new()
	_touch.name = "TouchScale"
	_touch.position = Vector2(202, 124)
	_touch.size = Vector2(200, 40)
	_touch.min_value = 0.85
	_touch.max_value = 1.15
	_touch.step = 0.05
	_touch.value = float(_flow.get("_settings").touch_scale)
	_touch.tooltip_text = "Taille des contrôles tactiles"
	style_slider(_touch)
	comfort.add_child(_touch)
	_touch_value = text(comfort, "%d %%" % roundi(_touch.value*100), Rect2(410, 124, 69, 40), 17)
	_touch.value_changed.connect(func(amount: float) -> void:
		_touch_value.text = "%d %%" % roundi(amount*100)
		_flow.get("_settings").touch_scale = amount
		_flow.call("_save_settings")
		var touch: Node = _flow.get("touch_controls")
		if touch != null:
			touch.call("set_control_scale", amount)
	)
	text(comfort, "Caméra de combat", Rect2(20, 178, 180, 40), 17)
	_zoom = HSlider.new()
	_zoom.name = "CombatZoom"
	_zoom.position = Vector2(202, 178)
	_zoom.size = Vector2(200, 40)
	_zoom.min_value = 100
	_zoom.max_value = 125
	_zoom.step = 1
	_zoom.value = float(_preferences.get("combat_zoom")) * 100.0
	_zoom.tooltip_text = "Rapproche le robot. 100 % conserve le champ de vision le plus large."
	style_slider(_zoom)
	comfort.add_child(_zoom)
	_zoom_value = text(comfort, "%d %%" % roundi(_zoom.value), Rect2(410, 178, 69, 40), 17)
	_zoom.value_changed.connect(func(amount: float) -> void:
		_zoom_value.text = "%d %%" % roundi(amount)
		if int(_preferences.call("set_combat_zoom", amount / 100.0)) != OK:
			_message.text = "Caméra appliquée. Sauvegarde indisponible."
	)
	var interface_row := plate(page, Rect2(0, 258, 950, 44))
	text(interface_row, "Personnaliser l’interface", Rect2(25, 2, 500, 40), 19)
	button(interface_row, "PERSONNALISER  ›", Rect2(689, 2, 236, 40), _flow._open_hud_editor).name = "CustomizeInterface"

func _build_commands() -> void:
	var page := _pages[1]
	for i in range(PREFERENCES.ACTIONS.size()):
		var action: String = PREFERENCES.ACTIONS[i]
		var x := 0.0 if i < 5 else 484.0
		var y := float(i%5)*49
		plate(page, Rect2(x, y, 466, 44))
		text(page, PREFERENCES.LABELS[action], Rect2(x+14, y+3, 270, 38), 16)
		var binding := button(page, "", Rect2(x+282, y+3, 170, 38), _begin_capture.bind(action))
		binding.name = action.to_pascal_case()+"Binding"
		binding.add_theme_font_size_override("font_size", 14)
		if action == "attack":
			binding.tooltip_text = "Le clic gauche reste disponible pour tirer."
		_bindings[action] = binding
	button(page, "RÉTABLIR LES TOUCHES", Rect2(327, 258, 296, 42), _reset_bindings)

func _build_interface(page: Control) -> void:
	var panel := section(page, "INTERFACE DE COMBAT", Rect2(0, 0, 950, 240))
	text(panel, "Place les commandes et les éléments du HUD à ta convenance.", Rect2(28, 82, 850, 45), 21)
	button(panel, "PERSONNALISER L’INTERFACE", Rect2(235, 145, 480, 46), _flow._open_hud_editor, true)

func _on_visibility() -> void:
	if not is_visible_in_tree():
		_cancel_capture()
		return
	for kind in _volumes:
		var amount := float(_preferences.get(kind+"_volume"))*100.0
		_volumes[kind].slider.set_value_no_signal(amount)
		_volumes[kind].value.text = "%d %%" % roundi(amount)
	_zoom.set_value_no_signal(float(_preferences.get("combat_zoom")) * 100.0)
	_zoom_value.text = "%d %%" % roundi(_zoom.value)
	_refresh_keys()

func _refresh_keys() -> void:
	for action in _bindings:
		_bindings[action].text = _preferences.call("keys_label", action)

func _begin_capture(action: String) -> void:
	_cancel_capture()
	_capture_action = action
	_bindings[action].text = "…"
	_message.text = "Appuie sur une touche. Échap annule."

func _cancel_capture() -> void:
	_capture_action = ""
	if _preferences != null:
		_refresh_keys()
	if _message != null:
		_message.text = "Sauvegarde automatique"

func _reset_bindings() -> void:
	_cancel_capture()
	_preferences.call("reset_bindings")

func _input(event: InputEvent) -> void:
	if _capture_action.is_empty() or not is_visible_in_tree() or not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_cancel_capture()
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed or event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		_message.text = "Choisis une touche seule, sans modificateur."
		return
	var problem := str(_preferences.call("rebind", _capture_action, event.keycode))
	if not problem.is_empty():
		_message.text = problem
		return
	_cancel_capture()
	_message.text = "Raccourci enregistré."
	get_viewport().gui_release_focus()
