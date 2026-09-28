extends Control

## Contrôles tactiles paysage. Chaque doigt reste propriétaire du contrôle qu'il
## a activé ; la visée et la demande de tir partagent le joystick droit.

@export_category("Ergonomie mobile")
@export_range(0.85, 1.15, 0.01) var control_scale := 1.0
@export_range(14.0, 42.0, 1.0) var safe_edge_margin := 24.0
@export_range(72.0, 104.0, 1.0) var move_joystick_radius := 88.0
@export_range(72.0, 104.0, 1.0) var aim_joystick_radius := 86.0
@export_range(32.0, 44.0, 1.0) var module_button_radius := 36.0
@export_range(8.0, 22.0, 1.0) var touch_target_padding := 12.0

var player: Node
var _joystick_touch := -1
var _aim_touch := -1
var _action_touches: Dictionary = {}
var _joystick_vector := Vector2.ZERO
var _aim_vector := Vector2.ZERO
var _fire_feedback_remaining := 0.0
var _inputs_suspended := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_inputs()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		reset_inputs()


func _exit_tree() -> void:
	reset_inputs()


func _process(delta: float) -> void:
	var suspended := not visible or get_tree().paused
	if suspended and not _inputs_suspended:
		reset_inputs()
	_inputs_suspended = suspended
	if not visible:
		return
	_fire_feedback_remaining = maxf(0.0, _fire_feedback_remaining - delta)
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


func _layout_scale_for_rect(rect: Rect2) -> float:
	return clampf(minf(rect.size.x, rect.size.y) / 720.0, 0.72, 1.20) * control_scale


func _layout_scale() -> float:
	return _layout_scale_for_rect(_safe_rect())


func _layout_for_safe_rect(safe: Rect2) -> Dictionary:
	var scale := _layout_scale_for_rect(safe)
	var move_radius := move_joystick_radius * scale
	var aim_radius := aim_joystick_radius * scale
	var margin := safe_edge_margin * scale
	var move := Vector2(safe.position.x + margin + move_radius, safe.end.y - margin - move_radius)
	var aim := Vector2(safe.end.x - margin - aim_radius, safe.end.y - margin - aim_radius)
	return {
		"scale": scale,
		"move_radius": move_radius,
		"aim_radius": aim_radius,
		"move": move,
		"aim": aim,
		"actions": {
			"offensive": move + Vector2(-12.0, -150.0) * scale,
			"defensive": move + Vector2(101.0, -112.0) * scale,
			"mobility": move + Vector2(151.0, -30.0) * scale,
			"weapon": Vector2(safe.end.x - 48.0 * scale, safe.position.y + 56.0 * scale),
		},
	}


func set_control_scale(value: float) -> void:
	control_scale = clampf(value, 0.85, 1.15)
	queue_redraw()


func reset_inputs() -> void:
	_joystick_touch = -1
	_aim_touch = -1
	_action_touches.clear()
	_joystick_vector = Vector2.ZERO
	_aim_vector = Vector2.ZERO
	_fire_feedback_remaining = 0.0
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
	return float(_layout_for_safe_rect(_safe_rect()).move_radius)


func _aim_radius() -> float:
	return float(_layout_for_safe_rect(_safe_rect()).aim_radius)


func _joystick_center() -> Vector2:
	return Vector2(_layout_for_safe_rect(_safe_rect()).move)


func _aim_center() -> Vector2:
	return Vector2(_layout_for_safe_rect(_safe_rect()).aim)


func _action_centers() -> Dictionary:
	# Arc supérieur/droit autour du pouce gauche. Aucun module ne partage la
	# zone du joystick droit.
	return Dictionary(_layout_for_safe_rect(_safe_rect()).actions)


func _action_radius(action: String) -> float:
	return (module_button_radius if action != "weapon" else 32.0) * _layout_scale()


func _draw() -> void:
	var joystick := _joystick_center()
	var aim := _aim_center()
	var actions := _action_centers()
	var scale := _layout_scale()
	var joystick_radius := _joystick_radius()
	var aim_radius := _aim_radius()
	var base_color := Color(0.06, 0.10, 0.13, 0.42)
	var move_edge := Color(0.35, 0.85, 0.92, 0.64)
	var aim_edge := Color(0.95, 0.62, 0.30, 0.66)
	draw_circle(joystick, joystick_radius, base_color)
	draw_arc(joystick, joystick_radius, 0.0, TAU, 48, move_edge, 3.0 * scale, true)
	draw_circle(joystick + _joystick_vector * joystick_radius * 0.66, 30.0 * scale, Color(0.30, 0.85, 0.92, 0.78))
	draw_circle(aim, aim_radius, base_color)
	draw_arc(aim, aim_radius, 0.0, TAU, 48, aim_edge, 3.0 * scale, true)
	draw_circle(aim + _aim_vector * aim_radius * 0.62, 25.0 * scale, Color(0.96, 0.66, 0.30, 0.76))
	_draw_charge_feedback(aim, aim_radius, scale)
	_draw_action(actions["offensive"], _action_radius("offensive"), Color(0.35, 0.78, 0.96, 0.76), "A")
	_draw_action(actions["defensive"], _action_radius("defensive"), Color(0.38, 0.90, 0.62, 0.76), "E")
	_draw_action(actions["mobility"], _action_radius("mobility"), Color(0.92, 0.68, 0.30, 0.76), "R")
	if player == null or not bool(player.get("survival_mode")):
		_draw_action(actions["weapon"], _action_radius("weapon"), Color(0.70, 0.44, 0.80, 0.74), "G")
	var font := ThemeDB.fallback_font
	draw_string(font, joystick + Vector2(-30.0 * scale, joystick_radius + 22.0 * scale), "DÉPLACER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(14.0 * scale), Color(0.82, 0.95, 0.97, 0.82))
	draw_string(font, aim + Vector2(-74.0 * scale, aim_radius + 22.0 * scale), "VISER / TIRER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(14.0 * scale), Color(1.0, 0.88, 0.70, 0.86))
	draw_string(font, aim + Vector2(-178.0 * scale, -aim_radius - 16.0 * scale), "RELÂCHER : TIR  •  MAINTENIR : CHARGE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(12.0 * scale), Color(1.0, 0.91, 0.77, 0.80))


func _draw_charge_feedback(center: Vector2, radius: float, scale: float) -> void:
	var state := "aim"
	var progress := 0.0
	if player != null and is_instance_valid(player):
		if player.has_method("get_mobile_blaster_input_state"):
			state = str(player.call("get_mobile_blaster_input_state"))
		if player.has_method("get_blaster_charge_ratio"):
			progress = clampf(float(player.call("get_blaster_charge_ratio")), 0.0, 1.0)
	if state == "charging":
		draw_arc(center, radius + 8.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * progress, 56, Color(0.34, 0.91, 1.0, 0.94), 7.0 * scale, true)
	elif state == "ready":
		var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.014)
		draw_arc(center, radius + 9.0 * scale, 0.0, TAU, 56, Color(0.78, 1.0, 0.66, 0.84 + pulse * 0.16), 8.0 * scale, true)
		draw_arc(center, radius + (14.0 + pulse * 3.0) * scale, 0.0, TAU, 56, Color(0.78, 1.0, 0.66, 0.30), 3.0 * scale, true)
	if _fire_feedback_remaining > 0.0:
		var flash := _fire_feedback_remaining / 0.16
		draw_arc(center, radius + (18.0 - flash * 8.0) * scale, 0.0, TAU, 48, Color(1.0, 0.83, 0.44, flash), 5.0 * scale, true)


func _draw_action(center: Vector2, radius: float, color: Color, label: String) -> void:
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.72), 2.0, true)
	var font := ThemeDB.fallback_font
	var font_size := int(16.0 * _layout_scale())
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, center - Vector2(text_size.x * 0.5, -5.0 * _layout_scale()), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)


func _input(event: InputEvent) -> void:
	if not visible or player == null or not is_instance_valid(player) or get_tree().paused:
		return
	var handled := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		handled = _begin_touch(touch.index, touch.position) if touch.pressed else _end_touch(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		handled = _update_touch(drag.index, drag.position)
	if handled:
		get_viewport().set_input_as_handled()


func _begin_touch(index: int, position: Vector2) -> bool:
	var actions := _action_centers()
	# Les actions sont testées avant le joystick : leur zone tactile généreuse ne
	# peut ainsi jamais être interprétée comme un déplacement ou un tir.
	for action in actions.keys():
		if action == "weapon" and player != null and bool(player.get("survival_mode")):
			continue
		var radius := _action_radius(action) + touch_target_padding * _layout_scale()
		if position.distance_to(actions[action]) <= radius:
			_action_touches[index] = action
			_press_action(action)
			return true
	var joystick := _joystick_center()
	if position.distance_to(joystick) <= _joystick_radius() * 1.18 and _joystick_touch == -1:
		_joystick_touch = index
		_update_joystick(position)
		return true
	var aim := _aim_center()
	if position.distance_to(aim) <= _aim_radius() * 1.28 and _aim_touch == -1:
		_aim_touch = index
		_update_aim(position)
		if player.has_method("begin_touch_fire"):
			player.call("begin_touch_fire")
		elif player.has_method("set_touch_attack_held"):
			player.call("set_touch_attack_held", true)
		return true
	return false


func _update_touch(index: int, position: Vector2) -> bool:
	if index == _joystick_touch:
		_update_joystick(position)
		return true
	if index == _aim_touch:
		_update_aim(position)
		return true
	return _action_touches.has(index)


func _end_touch(index: int) -> bool:
	var handled := false
	if index == _joystick_touch:
		handled = true
		_joystick_touch = -1
		_joystick_vector = Vector2.ZERO
		if player.has_method("set_touch_move_vector"):
			player.call("set_touch_move_vector", Vector2.ZERO)
	if index == _aim_touch:
		handled = true
		# Le joueur reçoit la dernière valeur avant que l'interface ne recentre le
		# stick. La requête de tir possède ainsi un instantané immuable de la visée.
		var fire_requested := false
		if player.has_method("end_touch_fire"):
			fire_requested = bool(player.call("end_touch_fire", _aim_vector))
		elif player.has_method("set_touch_attack_held"):
			player.call("set_touch_attack_held", false)
			fire_requested = true
		_aim_touch = -1
		_aim_vector = Vector2.ZERO
		if player.has_method("set_touch_aim_vector"):
			player.call("set_touch_aim_vector", Vector2.ZERO)
		if fire_requested:
			_fire_feedback_remaining = 0.16
	if _action_touches.has(index):
		handled = true
		var action: String = _action_touches[index]
		_action_touches.erase(index)
		_release_action(action)
	return handled


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
	if player.has_method("trigger_touch_action"):
		player.call("trigger_touch_action", action)


func _release_action(_action: String) -> void:
	pass
