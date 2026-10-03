extends Control

## One purpose per menu page; all existing modes keep their original callbacks.
const GARAGE_LAYOUT := preload("res://scripts/ui/forge_garage_layout.gd")
var page := "home"
var safe_area_override := Rect2()
var title_label: Label
var _flow
var _frame: Control
var _subtitle: Label
var _back: Button
var _divider: ColorRect
var _buttons: Array[Control] = []


func configure(flow) -> void:
	_flow = flow


func _ready() -> void:
	name = "MainMenuPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	var plate := TextureRect.new()
	plate.name = "GeneratedMenuPlate"
	plate.texture = _flow.MENU_PANEL_TEXTURE
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(plate)
	title_label = _flow._label("PROTOTYPE 0", 40, _flow.CREAM)
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.add_theme_font_override("font", _flow.MENU_DISPLAY_FONT)
	_frame.add_child(title_label)
	_subtitle = _flow._label("COMBAT DE ROBOTS", 16, _flow.CYAN)
	_frame.add_child(_subtitle)
	_divider = ColorRect.new()
	_divider.color = Color("#3a4244")
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_divider)
	_back = _flow._button("‹", back, 48)
	_back.custom_minimum_size = Vector2(48, 48)
	_frame.add_child(_back)
	resized.connect(layout_navigation)
	show_page("home")


func show_page(value: String) -> void:
	page = value
	for button in _buttons:
		button.hide()
		button.queue_free()
	_buttons.clear()
	var entries: Array = []
	match page:
		"home":
			title_label.text = "PROTOTYPE 0"
			_subtitle.text = "COMBAT DE ROBOTS"
			entries = [["JOUER", show_page.bind("play")], ["GARAGE", _flow._open_equipment], ["ENTRAÎNEMENT", show_page.bind("training")]]
		"play":
			title_label.text = "JOUER"
			_subtitle.text = "CHOISIS TON MODE"
			entries = [["DUEL SOLO", _flow._open_solo_setup], ["MULTIJOUEUR", _flow._open_lobby], ["SURVIE", _flow._open_survival]]
		"training":
			title_label.text = "ENTRAÎNEMENT"
			_subtitle.text = "PRÉPARE TON ROBOT"
			entries = [["TERRAIN LIBRE", _flow._open_training_ground], ["TUTORIEL", _flow._open_beginner_tutorial]]
	for index in entries.size():
		var texture: Texture2D = _flow.MENU_BUTTON_PRIMARY_TEXTURE if index == 0 else _flow.MENU_BUTTON_SECONDARY_TEXTURE
		var button: Control = _flow._menu_art_button(entries[index][0], entries[index][1], texture, 78)
		button.name = str(entries[index][0]).to_pascal_case().replace(" ", "")
		_frame.add_child(button)
		_buttons.append(button)
	_back.visible = page != "home"
	layout_navigation()


func back() -> void:
	show_page("home")


func layout_navigation() -> void:
	if _frame == null or size.y < 1:
		return
	var safe := GARAGE_LAYOUT.safe_rect(self)
	var window := Vector2(get_window().size)
	var compact := OS.has_feature("mobile") or window.x < 1050 or window.y < 600
	var unit := minf(size.y / 390, size.x / 600) if compact else minf(1.25, minf(size.y / 720, size.x / 1280))
	unit = maxf(unit, 0.01)
	var available := safe.size / unit
	var frame_size := Vector2(minf(350, available.x * 0.57), available.y - 26) if compact else Vector2(590, 640)
	_frame.scale = Vector2.ONE * unit
	_frame.position = safe.position + Vector2(12, (available.y - frame_size.y) * 0.5) * unit
	_frame.size = frame_size
	var x := frame_size.x * 0.22
	var width := frame_size.x * 0.68
	var y := frame_size.y * 0.14
	title_label.position = Vector2(x, y)
	title_label.size = Vector2(width, 34 if compact else 55)
	title_label.add_theme_font_size_override("font_size", 21 if compact else 40)
	_subtitle.position = Vector2(x, y + (35 if compact else 57))
	_subtitle.size = Vector2(width, 24)
	_subtitle.add_theme_font_size_override("font_size", 12 if compact else 16)
	_divider.position = Vector2(x, y + (65 if compact else 94))
	_divider.size = Vector2(width, 2)
	var button_height := 52.0 if compact else 78.0
	var start := y + (80 if compact else 120)
	for index in _buttons.size():
		var button := _buttons[index]
		button.position = Vector2(x, start + index * (button_height + (12 if compact else 18)))
		button.custom_minimum_size = Vector2.ZERO
		button.size = Vector2(width, button_height)
		(button.get_child(1) as Button).add_theme_font_size_override("font_size", 16 if compact else (26 if index == 0 else 23))
	_back.position = Vector2(frame_size.x - 62, 8)
	_back.size = Vector2(48, 48)
	if _flow._menu_settings_button != null:
		_flow._menu_settings_button.scale = Vector2.ONE * unit
		_flow._menu_settings_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_flow._menu_settings_button.position = safe.position + Vector2(12, available.y - 60) * unit
		_flow._menu_settings_button.size = Vector2(48, 48)
