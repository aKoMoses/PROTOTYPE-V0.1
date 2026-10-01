extends Control

const SCANNER := preload("res://scripts/forge_manual_scanner.gd")
const CYAN := Color("#77e5ee")

var garage
var scanner: SCANNER
var button: Button
var hint: Label
var _touch_index := -1
var _mouse_tracking := false
var _mouse_held := false


func configure(garage_control: Control) -> void:
	garage = garage_control


func _ready() -> void:
	name = "ManualScannerInterface"
	process_priority = 3
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = garage.DESIGN_SIZE
	scanner = SCANNER.new()
	scanner.name = "ManualScanner"
	scanner.configure(garage.stage)
	garage.stage.world.add_child(scanner)
	scanner.enabled_changed.connect(_mode_changed)
	button = garage._button("SCANNER", Vector2(285, 40), Vector2(150, 38), _toggle)
	button.name = "GarageScanner"
	button.add_theme_font_size_override("font_size", 13)
	button.tooltip_text = "Piloter le bras de maintenance sur le torse et les épaules."
	for state in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = garage._style(false)
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		button.add_theme_stylebox_override(state, style)
	hint = garage._label("Torse / épaules · Maintiens pour scanner · Échap : quitter", Vector2(293, 662), Vector2(650, 32), 13, CYAN)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	garage._ui.add_child(hint)
	hint.hide()
	garage.visibility_changed.connect(_sync_visibility)
	_sync_visibility()


func _toggle() -> void:
	if not scanner.enabled:
		garage._stop_robot_rotation()
		garage._module_panel.hide()
		garage.focus.show_overview(false)
	scanner.set_enabled(not scanner.enabled)
	button.release_focus()


func stop() -> void:
	if scanner != null:
		scanner.set_enabled(false)


func _mode_changed(value: bool) -> void:
	_touch_index = -1
	_mouse_tracking = false
	_mouse_held = false
	hint.visible = value
	button.text = "QUITTER SCANNER" if value else "SCANNER"
	button.add_theme_color_override("font_color", CYAN if value else garage.CREAM)
	var style: StyleBoxFlat = garage._style(false)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.border_color = CYAN if value else Color("#74604a")
	button.add_theme_stylebox_override("normal", style)
	garage.mouse_default_cursor_shape = Control.CURSOR_CROSS if value else Control.CURSOR_ARROW
	queue_redraw()


func _sync_visibility() -> void:
	var active: bool = garage.is_visible_in_tree()
	if not active:
		stop()
	set_process(active)
	set_process_input(active)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		stop()


func _input(event: InputEvent) -> void:
	if scanner == null or not scanner.enabled:
		return
	# Releases over buttons/outside the robot must also extinguish the scan.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _touch_index < 0:
		_mouse_tracking = false
		_mouse_held = false
		scanner.retract()
	elif event is InputEventScreenTouch and event.index == _touch_index and (not event.pressed or event.canceled):
		_touch_index = -1
		scanner.retract()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		stop()
		get_viewport().set_input_as_handled()


func handle_event(event: InputEvent) -> bool:
	if not scanner.enabled:
		return false
	if event is InputEventMouse and event.device == -1:
		return true
	if event is InputEventMouseMotion and _touch_index < 0:
		_mouse_tracking = true
		_mouse_held = bool(event.button_mask & MOUSE_BUTTON_MASK_LEFT)
		scanner.point_at(event.position, _mouse_held)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _touch_index < 0:
		_mouse_tracking = event.pressed
		_mouse_held = event.pressed
		if event.pressed:
			scanner.point_at(event.position, true)
		else:
			scanner.retract()
	elif event is InputEventScreenTouch:
		if event.pressed and not event.canceled and _touch_index < 0:
			_touch_index = event.index
			_mouse_tracking = false
			scanner.point_at(event.position, true)
		elif event.index == _touch_index:
			_touch_index = -1
			scanner.retract()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		scanner.point_at(event.position, true)
	# Explicit mode owns the robot gesture, including misses outside scan zones.
	return event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag


func _process(_delta: float) -> void:
	if scanner.enabled and _mouse_tracking and _touch_index < 0:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != garage:
			_mouse_tracking = false
			_mouse_held = false
			scanner.retract()
	if scanner.enabled:
		queue_redraw()


func _draw() -> void:
	if scanner == null or not scanner.enabled or scanner.target_zone == "":
		return
	var point: Vector2 = garage.stage.camera.unproject_position(scanner.surface_point)
	point = point * garage.stage.size / Vector2(garage.stage.viewport.size)
	point = get_global_transform().affine_inverse() * (garage.get_global_transform() * point)
	var color := CYAN if scanner.target_valid else Color("#f5b844")
	var radius := 13.0 if not scanner.scanning else 16.0
	draw_arc(point, radius, 0, TAU, 36, Color(color, 0.6), 1.0, true)
	for axis in [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]:
		draw_line(point + axis * (radius + 3), point + axis * (radius + 9), color, 1.5, true)
	if scanner.scanning:
		draw_arc(point, radius + 5, -PI / 2, -PI / 2 + fmod(scanner.scan_elapsed, 1.5) / 1.5 * TAU, 36, CYAN, 2.0, true)
