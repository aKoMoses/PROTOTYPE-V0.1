extends Control

## Contrôles tactiles optionnels pour le futur build mobile.
## Le panneau reste invisible sur desktop et ne modifie pas les raccourcis PC.

var player: Node
var _joystick_touch := -1
var _aim_touch := -1
var _action_touches: Dictionary = {}
var _joystick_vector := Vector2.ZERO
var _aim_vector := Vector2.ZERO
var _control_scale := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested()
	queue_redraw()


func _touch_preview_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "touch_preview":
			return true
	return false


func set_player(value: Node) -> void:
	player = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return
	queue_redraw()


func _viewport_size() -> Vector2:
	return get_viewport_rect().size


func _safe_rect() -> Rect2:
	var viewport := get_viewport_rect()
	var viewport_rect := Rect2(Vector2(viewport.position), Vector2(viewport.size))
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return viewport_rect
	var window_size := DisplayServer.window_get_size()
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return viewport_rect
	var scale := Vector2(viewport_rect.size) / Vector2(window_size)
	var scaled_safe := Rect2(Vector2(safe.position) * scale, Vector2(safe.size) * scale)
	var clipped := scaled_safe.intersection(viewport_rect)
	return clipped if clipped.size.x > 0.0 and clipped.size.y > 0.0 else viewport_rect


func _layout_scale() -> float:
	var size := _safe_rect().size
	return clampf(minf(size.x, size.y) / 720.0, 0.72, 1.20) * _control_scale


func set_control_scale(value: float) -> void:
	_control_scale = clampf(value, 0.85, 1.15)
	queue_redraw()


func reset_inputs() -> void:
	_joystick_touch = -1
	_aim_touch = -1
	_action_touches.clear()
	_joystick_vector = Vector2.ZERO
	_aim_vector = Vector2.ZERO
	if player != null and is_instance_valid(player):
		if player.has_method("clear_touch_inputs"):
			player.call("clear_touch_inputs")
		else:
			if player.has_method("set_touch_move_vector"):
				player.call("set_touch_move_vector", Vector2.ZERO)
			if player.has_method("set_touch_aim_vector"):
				player.call("set_touch_aim_vector", Vector2.ZERO)
			if player.has_method("set_touch_attack_held"):
				player.call("set_touch_attack_held", false)
	queue_redraw()


func _joystick_radius() -> float:
	return 88.0 * _layout_scale()


func _aim_radius() -> float:
	return 78.0 * _layout_scale()


func _joystick_center() -> Vector2:
	var safe := _safe_rect()
	var radius := _joystick_radius()
	var margin := 18.0 * _layout_scale()
	return Vector2(safe.position.x + margin + radius, safe.end.y - margin - radius)


func _aim_center() -> Vector2:
	var safe := _safe_rect()
	var scale := _layout_scale()
	return Vector2(safe.end.x - 318.0 * scale, safe.end.y - 150.0 * scale)


func _action_centers() -> Dictionary:
	var safe := _safe_rect()
	var scale := _layout_scale()
	return {
		"attack": Vector2(safe.end.x - 112.0 * scale, safe.end.y - 126.0 * scale),
		"offensive": Vector2(safe.end.x - 230.0 * scale, safe.end.y - 70.0 * scale),
		"defensive": Vector2(safe.end.x - 205.0 * scale, safe.end.y - 238.0 * scale),
		"mobility": Vector2(safe.end.x - 330.0 * scale, safe.end.y - 278.0 * scale),
		"weapon": Vector2(safe.end.x - 92.0 * scale, safe.position.y + 94.0 * scale),
	}


func _draw() -> void:
	var joystick := _joystick_center()
	var aim := _aim_center()
	var actions := _action_centers()
	var scale := _layout_scale()
	var joystick_radius := _joystick_radius()
	var aim_radius := _aim_radius()
	var base_color := Color(0.06, 0.10, 0.13, 0.40)
	var edge_color := Color(0.35, 0.85, 0.92, 0.58)
	draw_circle(joystick, joystick_radius, base_color)
	draw_arc(joystick, joystick_radius, 0.0, TAU, 48, edge_color, 3.0 * scale, true)
	draw_circle(joystick + _joystick_vector * joystick_radius * 0.66, 30.0 * scale, Color(0.30, 0.85, 0.92, 0.76))
	draw_circle(aim, aim_radius, base_color)
	draw_arc(aim, aim_radius, 0.0, TAU, 48, Color(0.95, 0.62, 0.30, 0.55), 3.0 * scale, true)
	draw_circle(aim + _aim_vector * aim_radius * 0.62, 24.0 * scale, Color(0.96, 0.66, 0.30, 0.70))
	_draw_action(actions["attack"], 46.0 * scale, Color(0.92, 0.28, 0.22, 0.78), "ATK")
	_draw_action(actions["offensive"], 32.0 * scale, Color(0.35, 0.78, 0.96, 0.72), "A")
	_draw_action(actions["defensive"], 32.0 * scale, Color(0.38, 0.90, 0.62, 0.72), "E")
	_draw_action(actions["mobility"], 32.0 * scale, Color(0.92, 0.68, 0.30, 0.72), "R")
	_draw_action(actions["weapon"], 30.0 * scale, Color(0.70, 0.44, 0.80, 0.72), "G")
	var font := ThemeDB.fallback_font
	draw_string(font, joystick + Vector2(-28.0 * scale, -joystick_radius - 12.0 * scale), "MOVE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(15.0 * scale), Color(0.82, 0.95, 0.97, 0.78))
	draw_string(font, aim + Vector2(-28.0 * scale, aim_radius + 24.0 * scale), "AIM", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(15.0 * scale), Color(1.0, 0.88, 0.70, 0.78))


func _draw_action(center: Vector2, radius: float, color: Color, label: String) -> void:
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.70), 2.0, true)
	var font := ThemeDB.fallback_font
	var font_size := int(16.0 * _layout_scale())
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, center - Vector2(text_size.x * 0.5, -5.0 * _layout_scale()), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)


func _input(event: InputEvent) -> void:
	if not visible or player == null or not is_instance_valid(player):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_touch(touch.index, touch.position)
		else:
			_end_touch(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_update_touch(drag.index, drag.position)


func _begin_touch(index: int, position: Vector2) -> void:
	var joystick := _joystick_center()
	var aim := _aim_center()
	var actions := _action_centers()
	if position.distance_to(joystick) <= _joystick_radius() * 1.32 and _joystick_touch == -1:
		_joystick_touch = index
		_update_joystick(position)
		return
	if position.distance_to(aim) <= _aim_radius() * 1.36 and _aim_touch == -1:
		_aim_touch = index
		_update_aim(position)
		return
	for action in actions.keys():
		var radius := (58.0 if action == "attack" else 45.0) * _layout_scale()
		if position.distance_to(actions[action]) <= radius:
			_action_touches[index] = action
			_press_action(action)
			return


func _update_touch(index: int, position: Vector2) -> void:
	if index == _joystick_touch:
		_update_joystick(position)
	elif index == _aim_touch:
		_update_aim(position)


func _end_touch(index: int) -> void:
	if index == _joystick_touch:
		_joystick_touch = -1
		_joystick_vector = Vector2.ZERO
		if player.has_method("set_touch_move_vector"):
			player.call("set_touch_move_vector", Vector2.ZERO)
	if index == _aim_touch:
		_aim_touch = -1
		_aim_vector = Vector2.ZERO
		if player.has_method("set_touch_aim_vector"):
			player.call("set_touch_aim_vector", Vector2.ZERO)
	if _action_touches.has(index):
		var action: String = _action_touches[index]
		_action_touches.erase(index)
		_release_action(action)


func _update_joystick(position: Vector2) -> void:
	_joystick_vector = (position - _joystick_center()) / _joystick_radius()
	_joystick_vector = _joystick_vector.limit_length(1.0)
	if player.has_method("set_touch_move_vector"):
		player.call("set_touch_move_vector", _joystick_vector)


func _update_aim(position: Vector2) -> void:
	_aim_vector = (position - _aim_center()) / _aim_radius()
	_aim_vector = _aim_vector.limit_length(1.0)
	if player.has_method("set_touch_aim_vector"):
		player.call("set_touch_aim_vector", _aim_vector)


func _press_action(action: String) -> void:
	if action == "attack":
		if player.has_method("set_touch_attack_held"):
			player.call("set_touch_attack_held", true)
	elif player.has_method("trigger_touch_action"):
		player.call("trigger_touch_action", action)


func _release_action(action: String) -> void:
	if action == "attack" and player.has_method("set_touch_attack_held"):
		player.call("set_touch_attack_held", false)
