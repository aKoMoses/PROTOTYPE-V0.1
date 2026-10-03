extends Control

const FONT := preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const CREAM := Color("#f3ddbb")
const ORANGE := Color("#ed5918")
const CYAN := Color("#42d9e5")
var flow: Node
var arena_title: Button
var arena_description: Label
var arena_number: Label
var loadouts: OptionButton
var launch: Button

class ArenaArrow extends Button:
	var direction := 1

	func _draw() -> void:
		var center := size * 0.5
		if button_pressed:
			center.y += 2.0
		var color := Color("#42d9e5") if is_hovered() or has_focus() else Color("#f3ddbb")
		draw_polyline(PackedVector2Array([
			center + Vector2(-direction * 5, -10),
			center + Vector2(direction * 5, 0),
			center + Vector2(-direction * 5, 10)
		]), color, 3.5, true)

func configure(owner_flow: Node) -> void:
	flow = owner_flow
	name = "SoloSetup"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.30, 0.50, 1.0])
	gradient.colors = PackedColorArray([Color("#071016fa"), Color("#071016aa"), Color("#07101644"), Color("#07101618")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	var backdrop := TextureRect.new()
	backdrop.texture = texture
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var content := Control.new()
	content.name = "Content"
	add_child(content)
	var layout := func() -> void:
		var factor := minf(size.y / 720.0, size.x / 1280.0)
		content.scale = Vector2.ONE * factor
		content.position = Vector2((size.x - 1280 * factor) * 0.5, (size.y - 720 * factor) * 0.5)
	resized.connect(layout)
	layout.call_deferred()
	_button(content, "←  Retour", Rect2(40, 24, 110, 36), flow._close_solo_setup)
	_text(content, "DUEL", Vector2(40, 80), 64, true)
	_text(content, "SOLO", Vector2(43, 150), 26, true, ORANGE)
	var rules := _text(content, "Premier à 3", Vector2(43, 192), 14)
	rules.tooltip_text = "Même adversaire jusqu’à la fin du match."
	_arena_arrow(content, Vector2(640, 620), -1)
	arena_title = _button(content, "", Rect2(712, 620, 425, 64), func() -> void: _cycle(1))
	arena_title.add_theme_font_override("font", FONT)
	arena_title.add_theme_font_size_override("font_size", 26)
	arena_title.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arena_arrow(content, Vector2(1147, 620), 1)
	arena_number = _text(content, "", Vector2(898, 692), 12)
	arena_description = _text(content, "", Vector2.ZERO, 12)
	arena_description.hide()
	var difficulty := HBoxContainer.new()
	difficulty.name = "SoloDifficulty"
	difficulty.position = Vector2(40, 244)
	difficulty.size = Vector2(320, 32)
	content.add_child(difficulty)
	var group := ButtonGroup.new()
	for index in 3:
		var button := _button(difficulty, ["Facile", "Normal", "Difficile"][index], Rect2(0, 0, 100, 32), func() -> void:
			flow._solo_options.difficulty = ["easy", "normal", "hard"][index]
			flow._store_solo_options())
		button.name = ["easy", "normal", "hard"][index]
		button.custom_minimum_size = Vector2(104, 32)
		button.toggle_mode = true
		button.button_group = group
		var selected := StyleBoxFlat.new()
		selected.bg_color = Color.TRANSPARENT
		selected.border_color = ORANGE
		selected.border_width_bottom = 3
		button.add_theme_stylebox_override("pressed", selected)
	var options_panel := Panel.new()
	options_panel.name = "SoloOptionsPanel"
	options_panel.position = Vector2(40, 327)
	options_panel.size = Vector2(352, 228)
	var option_style := StyleBoxFlat.new()
	option_style.bg_color = Color("#101b24f5")
	option_style.border_color = Color("#394850")
	option_style.set_border_width_all(1)
	options_panel.add_theme_stylebox_override("panel", option_style)
	content.add_child(options_panel)
	var options := Control.new()
	options.position = Vector2(16, 12)
	options_panel.add_child(options)
	_text(options, "OPTIONS", Vector2.ZERO, 14, true)
	options_panel.hide()
	_button(content, "Options  +", Rect2(40, 290, 120, 32), func() -> void: options_panel.visible = not options_panel.visible)
	visibility_changed.connect(func() -> void: options_panel.hide())
	for index in 2:
		var key: String = ["quick", "feedback"][index]
		_text(options, ["Présentations rapides", "Confirmations visuelles"][index], Vector2(0, 45 + index * 42), 13)
		var toggle := CheckButton.new()
		toggle.name = key.to_pascal_case() + "Option"
		toggle.position = Vector2(260, 38 + index * 42)
		toggle.size = Vector2(60, 30)
		toggle.tooltip_text = "Garage et précombat" if key == "quick" else "Actions réussies"
		toggle.toggled.connect(func(active: bool) -> void:
			flow._solo_options[key] = active
			flow._store_solo_options())
		options.add_child(toggle)
	_line(options, Vector2(0, 132), 320, Color("#455054"))
	_text(options, "Bannière de maîtrise", Vector2(0, 151), 12)
	var badge := _dropdown(options, "MasteryBadge", Rect2(200, 143, 120, 32))
	badge.item_selected.connect(func(index: int) -> void:
		flow._solo_options.badge = badge.get_item_metadata(index)
		flow._store_solo_options())
	_text(options, "Récompense cosmétique", Vector2(0, 185), 11, false, Color("#929caa"))
	_text(content, "M O N  L O A D O U T", Vector2(40, 569), 11)
	loadouts = _dropdown(content, "SoloLoadout", Rect2(40, 595, 320, 42))
	loadouts.item_selected.connect(func(_index: int) -> void: launch.disabled = false)
	launch = _button(content, "LANCER LE DUEL    →", Rect2(40, 656, 320, 44), flow._launch_solo)
	launch.name = "LaunchSolo"
	launch.add_theme_font_override("font", FONT)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = ORANGE.lightened(0.12) if state == "hover" else ORANGE
		launch.add_theme_stylebox_override(state, style)

func refresh_arena() -> void:
	var choices: Array = flow.ARENA_CATALOG.options()
	for index in choices.size():
		if choices[index].id != flow._arena_variant:
			continue
		arena_title.text = str(choices[index].title).replace("PAVILLON DES ÉCHOS", "PAVILLON\nDES ÉCHOS")
		arena_number.text = "%02d / %02d" % [index + 1, choices.size()]
		arena_description.text = str(choices[index].description)
		arena_title.tooltip_text = str(choices[index].description)

func _cycle(direction: int) -> void:
	var choices: Array = flow.ARENA_CATALOG.options()
	for index in choices.size():
		if choices[index].id == flow._arena_variant:
			flow._select_arena(choices[posmod(index + direction, choices.size())].id)
			refresh_arena()
			flow._preview_solo_arena()
			return

func _arena_arrow(parent: Node, at: Vector2, direction: int) -> Button:
	var button := ArenaArrow.new()
	button.name = "PreviousArena" if direction < 0 else "NextArena"
	button.direction = direction
	button.position = at
	button.size = Vector2(64, 64)
	button.tooltip_text = "Map précédente" if direction < 0 else "Map suivante"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#101b24ec")
		style.border_color = Color("#52616b")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		if state == "hover":
			style.bg_color = Color("#203a43")
			style.border_color = CYAN
		elif state == "pressed":
			style.bg_color = Color("#294e58")
			style.border_color = CYAN
		elif state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = CYAN
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func() -> void: _cycle(direction))
	for signal_name in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited", "button_down", "button_up"]:
		button.connect(signal_name, button.queue_redraw)
	parent.add_child(button)
	return button

func _text(parent: Node, value: String, at: Vector2, font_size: int, display := false, color := CREAM) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if display:
		label.add_theme_font_override("font", FONT)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CYAN)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _dropdown(parent: Node, node_name: String, rect: Rect2) -> OptionButton:
	var selector := OptionButton.new()
	selector.name = node_name
	selector.position = rect.position
	selector.size = rect.size
	selector.fit_to_longest_item = false
	selector.add_theme_font_size_override("font_size", 13)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#121c23dd")
	style.border_color = Color("#455054")
	style.set_border_width_all(1)
	style.content_margin_left = 10
	selector.add_theme_stylebox_override("normal", style)
	parent.add_child(selector)
	return selector

func _line(parent: Node, at: Vector2, width: float, color: Color) -> void:
	var line := ColorRect.new()
	line.position = at
	line.size = Vector2(width, 2)
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
