extends Control

## Contrôles tactiles optionnels pour le futur build mobile.
## Le panneau reste invisible sur desktop et ne modifie pas les raccourcis PC.

var player: Node
var _joystick_touch := -1
var _aim_touch := -1
var _action_touches: Dictionary = {}
var _joystick_vector := Vector2.ZERO
var _aim_vector := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	queue_redraw()


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


func _joystick_center() -> Vector2:
	var size := _viewport_size()
	return Vector2(126.0, size.y - 128.0)


func _aim_center() -> Vector2:
	var size := _viewport_size()
	return Vector2(size.x - 318.0, size.y - 150.0)


func _action_centers() -> Dictionary:
	var size := _viewport_size()
	return {
		"attack": Vector2(size.x - 112.0, size.y - 126.0),
		"offensive": Vector2(size.x - 230.0, size.y - 70.0),
		"defensive": Vector2(size.x - 205.0, size.y - 238.0),
		"mobility": Vector2(size.x - 330.0, size.y - 278.0),
		"weapon": Vector2(size.x - 92.0, 94.0),
	}


func _draw() -> void:
	var size := _viewport_size()
	var joystick := _joystick_center()
	var aim := _aim_center()
	var actions := _action_centers()
	var base_color := Color(0.06, 0.10, 0.13, 0.40)
	var edge_color := Color(0.35, 0.85, 0.92, 0.58)
	draw_circle(joystick, 88.0, base_color)
	draw_arc(joystick, 88.0, 0.0, TAU, 48, edge_color, 3.0, true)
	draw_circle(joystick + _joystick_vector * 58.0, 30.0, Color(0.30, 0.85, 0.92, 0.76))
	draw_circle(aim, 78.0, base_color)
	draw_arc(aim, 78.0, 0.0, TAU, 48, Color(0.95, 0.62, 0.30, 0.55), 3.0, true)
	draw_circle(aim + _aim_vector * 48.0, 24.0, Color(0.96, 0.66, 0.30, 0.70))
	_draw_action(actions["attack"], 46.0, Color(0.92, 0.28, 0.22, 0.78), "ATK")
	_draw_action(actions["offensive"], 32.0, Color(0.35, 0.78, 0.96, 0.72), "A")
	_draw_action(actions["defensive"], 32.0, Color(0.38, 0.90, 0.62, 0.72), "E")
	_draw_action(actions["mobility"], 32.0, Color(0.92, 0.68, 0.30, 0.72), "R")
	_draw_action(actions["weapon"], 30.0, Color(0.70, 0.44, 0.80, 0.72), "G")
	var font := ThemeDB.fallback_font
	draw_string(font, joystick + Vector2(-28.0, 120.0), "MOVE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.82, 0.95, 0.97, 0.78))
	draw_string(font, aim + Vector2(-28.0, 108.0), "AIM", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1.0, 0.88, 0.70, 0.78))


func _draw_action(center: Vector2, radius: float, color: Color, label: String) -> void:
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.70), 2.0, true)
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16)
	draw_string(font, center - Vector2(text_size.x * 0.5, -5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)


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
	if position.distance_to(joystick) <= 116.0 and _joystick_touch == -1:
		_joystick_touch = index
		_update_joystick(position)
		return
	if position.distance_to(aim) <= 106.0 and _aim_touch == -1:
		_aim_touch = index
		_update_aim(position)
		return
	for action in actions.keys():
		var radius := 58.0 if action == "attack" else 45.0
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
	_joystick_vector = (position - _joystick_center()) / 88.0
	_joystick_vector = _joystick_vector.limit_length(1.0)
	if player.has_method("set_touch_move_vector"):
		player.call("set_touch_move_vector", _joystick_vector)


func _update_aim(position: Vector2) -> void:
	_aim_vector = (position - _aim_center()) / 78.0
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
