extends Control

## First playable workshop. All selections use the existing loadout contract.
signal equipment_selected(category: String, identifier: String)
signal back_requested
signal start_requested
signal arena_selected(identifier: String)

const STAGE := preload("res://scripts/forge_garage_stage.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const DATA := preload("res://scripts/combat_data.gd")
const ICONS := preload("res://scripts/equipment_icons.gd")
const DISPLAY_FONT := preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const BODY_FONT := preload("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
const DESIGN_SIZE := Vector2(1280, 720)
const AMBER := Color("#f5b844")
const CREAM := Color("#eee5ce")
const CYAN := Color("#69e0e8")

var loadout: Dictionary = LOADOUT.defaults()
var stage
var robot_buttons: Dictionary = {}
var weapon_buttons: Dictionary = {}
var module_buttons: Dictionary = {}
var arena_buttons: Dictionary = {}
var _icons := ICONS.new()
var _ui: Control
var _stat_name: Label
var _health: Label
var _speed: Label
var _health_bar: ProgressBar
var _speed_bar: ProgressBar
var _status: Label
var _inspect: Button
var _module_panel: PanelContainer
var _module_options: VBoxContainer
var _module_title: Label
var _module_category := "offensive"
var _nav: Dictionary = {}
var _arena_label: Label
var _weapon_info_id := ""


func _ready() -> void:
	name = "ForgeGarage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var custom_theme := Theme.new()
	custom_theme.default_font = BODY_FONT
	custom_theme.default_font_size = 16
	theme = custom_theme
	stage = STAGE.new()
	stage.name = "GarageStage"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	_build_interface()
	resized.connect(_layout)
	visibility_changed.connect(_sync_visibility)
	_layout()
	_refresh()
	_sync_visibility()


func _process(_delta: float) -> void:
	if stage.arm != null:
		_status.text = stage.arm.phase_name()
		_inspect.disabled = stage.arm.active


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _module_panel.visible:
			_module_panel.hide()
		else:
			back_requested.emit()
		get_viewport().set_input_as_handled()


func set_loadout(value: Dictionary) -> void:
	loadout = LOADOUT.sanitize(value)
	if _ui != null:
		_refresh()


func set_arena_options(enabled: bool, selected: String = "classic") -> void:
	_arena_label.visible = enabled
	for identifier in arena_buttons:
		var button: Button = arena_buttons[identifier]
		button.visible = enabled
		var frame := _style(identifier == selected)
		frame.content_margin_top = 4
		frame.content_margin_bottom = 4
		button.add_theme_stylebox_override("normal", frame)


func _choose_arena(identifier: String) -> void:
	set_arena_options(true, identifier)
	arena_selected.emit(identifier)


func _select_equipment(category: String, identifier: String) -> void:
	loadout[category] = identifier
	loadout = LOADOUT.sanitize(loadout)
	_refresh()
	equipment_selected.emit(category, str(loadout[category]))


func _sync_visibility() -> void:
	set_process(is_visible_in_tree())
	set_process_unhandled_key_input(is_visible_in_tree())
	if not is_visible_in_tree() and _module_panel != null:
		_module_panel.hide()


func _layout() -> void:
	if _ui == null:
		return
	var ratio := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_ui.scale = Vector2.ONE * ratio
	_ui.position = (size - DESIGN_SIZE * ratio) * 0.5
	_ui.size = DESIGN_SIZE


func _style(active: bool = false, strong: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.085, 0.067, 0.92) if not active else Color(0.23, 0.16, 0.075, 0.95)
	style.border_color = AMBER if active else Color("#74604a")
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12 if strong else 5
	if active:
		style.shadow_color = Color(1, 0.52, 0.1, 0.12)
	return style


func _label(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color = CREAM, display: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if display:
		label.add_theme_font_override("font", DISPLAY_FONT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, pos: Vector2, dimensions: Vector2, callback: Callable, active: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = dimensions
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", DISPLAY_FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_stylebox_override("normal", _style(active))
	button.add_theme_stylebox_override("hover", _style(true))
	button.add_theme_stylebox_override("pressed", _style(true))
	button.add_theme_stylebox_override("focus", _style(true))
	button.add_theme_stylebox_override("disabled", _style(false))
	button.add_theme_color_override("font_disabled_color", Color("#baa989"))
	button.pressed.connect(callback)
	_ui.add_child(button)
	return button


func _build_interface() -> void:
	_ui = Control.new()
	_ui.name = "GarageInterface"
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	# A transparent edge gradient helps the interface without covering the robot.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.025, 0.018, 0.010, 0.72))
	gradient.set_color(1, Color(0.025, 0.018, 0.010, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0.36, 0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.size = DESIGN_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	_ui.add_child(_label("FORGE", Vector2(38, 30), Vector2(265, 67), 49, CREAM, true))
	_ui.add_child(_label("BAIE 01  /  ATELIER", Vector2(40, 98), Vector2(250, 25), 12, AMBER, true))
	var titles := ["ROBOT", "ARMES", "MODULES", "INSPECTER"]
	var icons := ["polyvalent", "blaster", "magnetic_field", "fulguro_punch"]
	for index in range(titles.size()):
		var title: String = titles[index]
		var button := _button(title, Vector2(32, 150 + index * 78), Vector2(224, 68), _navigate.bind(title), index == 0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.content_margin_left = 71
			button.add_theme_stylebox_override(state, style)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = _icons.get_icon(icons[index])
		icon.position = Vector2(13, 11)
		icon.size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(44, 44)
		button.add_child(icon)
		icon.set_deferred("size", Vector2(44, 44))
		_nav[title] = button
		if title == "INSPECTER":
			_inspect = button
	_ui.add_child(_label("CHÂSSIS", Vector2(34, 488), Vector2(218, 25), 12, AMBER, true))
	for index in range(LOADOUT.ROBOTS.size()):
		var identifier: String = LOADOUT.ROBOTS[index]
		var button := _button(LOADOUT.display_name(identifier), Vector2(32, 519 + index * 36), Vector2(224, 30), _select_equipment.bind("robot", identifier))
		button.add_theme_font_size_override("font_size", 12)
		for state in ["normal", "hover", "pressed", "focus"]:
			var compact := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			compact.content_margin_top = 3
			compact.content_margin_bottom = 3
			button.add_theme_stylebox_override(state, compact)
		button.size = Vector2(224, 30)
		button.tooltip_text = LOADOUT.stat_line(identifier)
		robot_buttons[identifier] = button
	_button("RETOUR", Vector2(32, 660), Vector2(145, 35), func() -> void: back_requested.emit())
	_build_stats()
	_arena_label = _label("ARÈNE", Vector2(978, 42), Vector2(264, 22), 12, AMBER, true)
	_ui.add_child(_arena_label)
	for index in range(2):
		var identifier: String = ["classic", "hazards"][index]
		var title: String = ["CLASSIQUE", "PIÉGÉE"][index]
		var button := _button(title, Vector2(975 + index * 138, 74), Vector2(130, 36), _choose_arena.bind(identifier))
		button.add_theme_font_size_override("font_size", 12)
		for state in ["normal", "hover", "pressed", "focus"]:
			var frame := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			frame.content_margin_top = 4
			frame.content_margin_bottom = 4
			button.add_theme_stylebox_override(state, frame)
		button.size = Vector2(130, 36)
		arena_buttons[identifier] = button
	set_arena_options(false)
	_build_module_slots()
	var compact_weapons := LOADOUT.WEAPONS.size() > 2
	var icon_size := Vector2(108, 45) if compact_weapons else Vector2(108, 78)
	for index in range(LOADOUT.WEAPONS.size()):
		var identifier: String = LOADOUT.WEAPONS[index]
		var card_pos := Vector2(975 + (index % 2) * 138, 441 + floorf(index / 2.0) * 86) if compact_weapons else Vector2(975 + index * 138, 454)
		var card_size := Vector2(130, 78) if compact_weapons else Vector2(130, 140)
		var button := _button("", card_pos, card_size, _select_equipment.bind("weapon", identifier))
		button.name = "Garage%s" % identifier.to_pascal_case()
		button.tooltip_text = LOADOUT.category_description(identifier)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = _icons.get_icon(identifier)
		icon.position = Vector2(11, 5) if compact_weapons else Vector2(11, 13)
		icon.size = icon_size
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		icon.set_deferred("size", icon_size)
		var label_pos := Vector2(5, 51) if compact_weapons else Vector2(5, 99)
		var name_label := _label(LOADOUT.display_name(identifier), label_pos, Vector2(101, 24), 12 if compact_weapons else 15, CREAM, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(name_label)
		var info := Button.new()
		info.name = "Info"
		info.text = "i"
		info.position = Vector2(108, 53) if compact_weapons else Vector2(108, 105)
		info.size = Vector2(18, 20)
		info.add_theme_color_override("font_color", CYAN)
		for state in ["normal", "hover", "pressed", "focus"]:
			var frame := _style(state != "normal")
			frame.set_content_margin_all(0)
			frame.shadow_size = 0
			info.add_theme_stylebox_override(state, frame)
		info.pressed.connect(_open_weapon_info.bind(identifier))
		button.add_child(info)
		weapon_buttons[identifier] = button
	var start := _button("JOUER   ›", Vector2(975, 620), Vector2(268, 64), func() -> void: start_requested.emit(), true)
	start.name = "GarageStart"
	start.add_theme_font_size_override("font_size", 25)
	start.add_theme_color_override("font_color", Color("#292017"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := _style(true, true)
		style.bg_color = AMBER if state == "normal" else Color("#ffd484")
		style.set_border_width_all(2)
		style.border_color = Color("#ffdf93")
		start.add_theme_stylebox_override(state, style)
	_build_module_picker()


func _build_stats() -> void:
	var panel := Panel.new()
	panel.position = Vector2(975, 131)
	panel.size = Vector2(268, 180)
	panel.add_theme_stylebox_override("panel", _style(false, true))
	_ui.add_child(panel)
	_stat_name = _label("POLYVALENT", Vector2(19, 15), Vector2(238, 37), 22, CREAM, true)
	panel.add_child(_stat_name)
	_health = _label("1000 PV", Vector2(20, 58), Vector2(230, 28), 18)
	panel.add_child(_health)
	_health_bar = _bar(Vector2(21, 91), 1200.0)
	panel.add_child(_health_bar)
	_speed = _label("5.0 m/s", Vector2(20, 112), Vector2(230, 28), 18)
	panel.add_child(_speed)
	_speed_bar = _bar(Vector2(21, 146), 6.0)
	panel.add_child(_speed_bar)
	_status = _label("ATELIER OPÉRATIONNEL", Vector2(977, 321), Vector2(270, 25), 12, CYAN, true)
	_ui.add_child(_status)


func _bar(pos: Vector2, maximum: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = Vector2(223, 5)
	bar.max_value = maximum
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = CYAN
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#514b3f")
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	bar.size = Vector2(223, 5)
	bar.set_deferred("size", Vector2(223, 5))
	return bar


func _build_module_slots() -> void:
	for index in range(4):
		var category: String = ["offensive", "defensive", "mobility", "passive"][index]
		var button := _button("", Vector2(975 + index * 69, 361), Vector2(61, 59), _open_modules.bind(category))
		var icon := TextureRect.new()
		icon.name = "ModuleIcon"
		icon.position = Vector2(8, 8)
		icon.size = Vector2(45, 43)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(45, 43)
		button.add_child(icon)
		module_buttons[category] = button


func _build_module_picker() -> void:
	_module_panel = PanelContainer.new()
	_module_panel.name = "GarageModulePicker"
	_module_panel.position = Vector2(285, 152)
	_module_panel.size = Vector2(305, 350)
	_module_panel.add_theme_stylebox_override("panel", _style(false, true))
	_ui.add_child(_module_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_module_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_module_title = Label.new()
	_module_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_title.add_theme_font_override("font", DISPLAY_FONT)
	_module_title.add_theme_color_override("font_color", AMBER)
	header.add_child(_module_title)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(35, 35)
	close.add_theme_font_size_override("font_size", 22)
	close.add_theme_color_override("font_color", CREAM)
	for state in ["normal", "hover", "pressed", "focus"]:
		var frame := _style(state != "normal")
		frame.content_margin_top = 0
		frame.content_margin_bottom = 0
		frame.content_margin_left = 5
		frame.content_margin_right = 5
		close.add_theme_stylebox_override(state, frame)
	close.pressed.connect(_module_panel.hide)
	header.add_child(close)
	_module_options = VBoxContainer.new()
	_module_options.add_theme_constant_override("separation", 8)
	column.add_child(_module_options)
	_module_panel.hide()


func _open_modules(category: String) -> void:
	_weapon_info_id = ""
	_module_category = category
	_module_title.text = {"offensive": "OFFENSIF", "defensive": "DÉFENSIF", "mobility": "MOBILITÉ", "passive": "PASSIF"}[category]
	for child in _module_options.get_children():
		child.free()
	var identifiers: Array = {"offensive": LOADOUT.OFFENSIVE, "defensive": LOADOUT.DEFENSIVE, "mobility": LOADOUT.MOBILITY, "passive": LOADOUT.PASSIVES}[category]
	for identifier in identifiers:
		var button := Button.new()
		button.text = LOADOUT.display_name(str(identifier))
		button.custom_minimum_size = Vector2(268, 53)
		button.tooltip_text = LOADOUT.category_description(str(identifier))
		button.add_theme_stylebox_override("normal", _style(str(loadout[category]) == identifier))
		button.add_theme_stylebox_override("hover", _style(true))
		button.add_theme_stylebox_override("pressed", _style(true))
		button.add_theme_stylebox_override("focus", _style(true))
		button.add_theme_color_override("font_color", CREAM)
		button.pressed.connect(func() -> void:
			_select_equipment(category, str(identifier))
			_module_panel.hide()
		)
		_module_options.add_child(button)
	_module_panel.show()


func _open_weapon_info(identifier: String) -> void:
	_weapon_info_id = identifier
	_module_title.text = LOADOUT.display_name(identifier)
	for child in _module_options.get_children():
		child.free()
	for text in [LOADOUT.category_description(identifier), LOADOUT.stat_line(identifier)]:
		var detail := Label.new()
		detail.text = text
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 268
		detail.add_theme_color_override("font_color", CREAM)
		_module_options.add_child(detail)
	_module_panel.show()


func _navigate(title: String) -> void:
	if title == "INSPECTER":
		stage.inspect_robot()
		return
	if title == "MODULES":
		_open_modules(_module_category)
	else:
		_module_panel.hide()
	for key in _nav:
		var style := _style(key == title)
		style.content_margin_left = 71
		(_nav[key] as Button).add_theme_stylebox_override("normal", style)


func _refresh() -> void:
	var identifier: String = loadout.robot
	var definition: Dictionary = DATA.ROBOT_DEFINITIONS[identifier]
	_stat_name.text = LOADOUT.display_name(identifier)
	_health.text = "%d PV" % int(definition.max_health)
	_speed.text = "%.1f m/s" % float(definition.move_speed)
	_health_bar.value = float(definition.max_health)
	_speed_bar.value = float(definition.move_speed)
	for key in robot_buttons:
		var compact := _style(key == identifier)
		compact.content_margin_top = 3
		compact.content_margin_bottom = 3
		(robot_buttons[key] as Button).add_theme_stylebox_override("normal", compact)
	for key in weapon_buttons:
		(weapon_buttons[key] as Button).add_theme_stylebox_override("normal", _style(key == str(loadout.weapon)))
	for category in module_buttons:
		var button: Button = module_buttons[category]
		(button.get_node("ModuleIcon") as TextureRect).texture = _icons.get_icon(str(loadout[category]))
		button.tooltip_text = LOADOUT.display_name(str(loadout[category])) + "\n" + LOADOUT.category_description(str(loadout[category]))
	if stage.chassis_id != identifier:
		stage.set_chassis(identifier)
	if stage.weapon_id != str(loadout.weapon):
		stage.set_weapon(str(loadout.weapon))
