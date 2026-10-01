extends Control

## Shared shell for the approved settings, lobby and loadout-reveal screens.
## Only the empty frame/backdrop is baked; every label/control stays interactive.
const DISPLAY_FONT := preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const SHELL := preload("res://art/ui/industrial/screen-shell.png")
const KNOB := preload("res://art/ui/industrial/slider-knob.svg")
const TOGGLE_ON := preload("res://art/ui/industrial/toggle-on.svg")
const TOGGLE_OFF := preload("res://art/ui/industrial/toggle-off.svg")
const CREAM := Color("#f3ddbb")
const CYAN := Color("#42d9e5")
const ORANGE := Color("#ff741b")
const MUTED := Color("#9caaa9")
const DESIGN_SIZE := Vector2(1280, 720)

var canvas: Control
var title_label: Label
var subtitle_label: Label

class Plate extends Control:
	var fill := Color("#1b2125")
	var border := Color("#414a4d")
	var hardware := false
	var underline := Color.TRANSPARENT
	func _draw() -> void:
		var cut := 8.0
		var points := PackedVector2Array([Vector2(cut, 0), Vector2(size.x-cut, 0), Vector2(size.x, cut), Vector2(size.x, size.y-cut), Vector2(size.x-cut, size.y), Vector2(cut, size.y), Vector2(0, size.y-cut), Vector2(0, cut)])
		draw_colored_polygon(points, fill)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, border, 1.5, true)
		draw_line(Vector2(10, 3), Vector2(size.x-10, 3), Color(1, 1, 1, 0.07), 2)
		draw_line(Vector2(10, size.y-3), Vector2(size.x-10, size.y-3), Color(0, 0, 0, 0.35), 2)
		if underline.a > 0.0:
			draw_line(Vector2(14, size.y-2), Vector2(size.x-14, size.y-2), underline, 3)
		if hardware:
			for point in [Vector2(8, 9), Vector2(size.x-8, 9)]:
				draw_circle(point, 2.2, Color("#303739"))
				draw_line(point-Vector2(1, 0), point+Vector2(1, 0), Color("#62696b"), 1)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("#11191d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	canvas = Control.new()
	canvas.name = "IndustrialCanvas"
	canvas.size = DESIGN_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var art := TextureRect.new()
	art.texture = SHELL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = DESIGN_SIZE
	canvas.add_child(art)
	text(canvas, "PROTOTYPE", Rect2(174, 77, 145, 28), 21, CREAM, true)
	text(canvas, "0", Rect2(320, 77, 26, 28), 21, CYAN, true)
	title_label = text(canvas, "", Rect2(174, 108, 790, 49), 39, CREAM, true)
	subtitle_label = text(canvas, "", Rect2(730, 124, 380, 26), 16, MUTED, true)
	line(canvas, Rect2(155, 164, 970, 1))
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if canvas == null:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - DESIGN_SIZE * factor) * 0.5

func text(parent: Node, value: String, rect: Rect2, font_size := 18, color := CREAM, display := false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if display:
		label.add_theme_font_override("font", DISPLAY_FONT)
	parent.add_child(label)
	return label

func line(parent: Node, rect: Rect2, color := Color("#394347")) -> ColorRect:
	var result := ColorRect.new()
	result.position = rect.position
	result.size = rect.size
	result.color = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func plate(parent: Node, rect: Rect2, border := Color("#414a4d")) -> Control:
	var result := Plate.new()
	result.position = rect.position
	result.size = rect.size
	result.border = border
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func section(parent: Node, value: String, rect: Rect2) -> Control:
	var result := plate(parent, rect)
	line(result, Rect2(14, 16, 4, 26), ORANGE)
	text(result, value, Rect2(29, 10, rect.size.x-42, 40), 23, CREAM, true)
	line(result, Rect2(16, 57, rect.size.x-32, 1))
	return result

func button(parent: Node, value: String, rect: Rect2, callback: Callable, primary := false) -> Button:
	var result := Button.new()
	result.text = value
	result.position = rect.position
	result.size = rect.size
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_override("font", DISPLAY_FONT)
	result.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	result.add_theme_color_override("font_color", CREAM)
	result.add_theme_color_override("font_hover_color", Color.WHITE)
	result.add_theme_color_override("font_pressed_color", Color.WHITE)
	result.add_theme_color_override("font_disabled_color", Color("#788083"))
	var decoration := Plate.new()
	decoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.show_behind_parent = true
	decoration.hardware = primary
	result.add_child(decoration)
	var update := func() -> void:
		var active := result.is_hovered() or result.has_focus()
		decoration.fill = Color("#bd4b0c") if primary and result.button_pressed else ORANGE if primary and not result.disabled else Color("#323c42") if active else Color("#272f34")
		decoration.border = CYAN if active else Color("#586267") if result.disabled else Color("#ff953f") if primary else Color("#8b623e")
		if result.get_meta("tab", false):
			decoration.fill = Color("#20272b")
			decoration.border = Color("#20272b")
			decoration.underline = ORANGE if result.get_meta("selected", false) else Color.TRANSPARENT
		decoration.queue_redraw()
	for event in [result.mouse_entered, result.mouse_exited, result.focus_entered, result.focus_exited, result.button_down, result.button_up, result.draw]:
		event.connect(update)
	result.pressed.connect(callback)
	parent.add_child(result)
	update.call()
	return result

func style_slider(slider: HSlider) -> void:
	for item in ["slider", "grabber_area", "grabber_area_highlight"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#3d454a") if item == "slider" else CYAN
		style.set_corner_radius_all(4)
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		slider.add_theme_stylebox_override(item, style)
	for item in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(item, KNOB)

func style_toggle(toggle: CheckButton) -> void:
	for item in ["checked", "checked_disabled", "unchecked", "unchecked_disabled"]:
		toggle.add_theme_icon_override(item, TOGGLE_OFF if item.begins_with("unchecked") else TOGGLE_ON)
	for state in ["normal", "hover", "pressed", "disabled"]:
		toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = CYAN
	focus.set_border_width_all(1)
	toggle.add_theme_stylebox_override("focus", focus)

func icon(parent: Node, texture: Texture2D, rect: Rect2) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.position = rect.position
	result.size = rect.size
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func footer() -> void:
	line(canvas, Rect2(155, 562, 970, 1))
