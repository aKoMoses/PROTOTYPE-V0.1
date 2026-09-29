extends Control

const HUD_LAYOUT := preload("res://scripts/hud_layout.gd")
const INPUT_TIE_ORDER := ["offensive_button", "defensive_button", "mobility_button", "weapon_button", "move", "aim"]

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
var _hud_layout: Dictionary = {}
var _reserved_rects: Array[Rect2] = []
var _editor_test := false
var _editor_editing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested()
	_hud_layout = HUD_LAYOUT.load_active()
	queue_redraw()


func _touch_preview_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "touch_preview":
			return true
	return false


func set_player(value: Node) -> void:
	if player != value:
		reset_inputs()
	player = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		reset_inputs()
		queue_redraw()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_inputs()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		reset_inputs()


func _exit_tree() -> void:
	reset_inputs()


func _process(delta: float) -> void:
	var suspended := not _can_accept_inputs()
	if suspended and not _inputs_suspended:
		reset_inputs()
	_inputs_suspended = suspended
	if not visible:
		return
	_fire_feedback_remaining = maxf(0.0, _fire_feedback_remaining - delta)
	queue_redraw()


func _can_accept_inputs() -> bool:
	if not is_visible_in_tree() or get_tree().paused or player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_gameplay_enabled") and not bool(player.call("is_gameplay_enabled")):
		return false
	return not (player.has_method("is_real_dead") and bool(player.call("is_real_dead")))


func _viewport_size() -> Vector2:
	return get_viewport_rect().size


func _safe_rect() -> Rect2:
	return HUD_LAYOUT.safe_rect(get_viewport())

func set_hud_layout(value: Dictionary) -> void:
	if not _editor_editing:
		reset_inputs()
	# HudLayoutController owns validation before passing the shared layout here.
	_hud_layout = value
	queue_redraw()

func set_reserved_rects(value: Array) -> void:
	_reserved_rects.clear()
	for rect in value:
		if rect is Rect2:
			_reserved_rects.append(rect)

func set_editor_test(value: bool) -> void:
	reset_inputs()
	_editor_test = value
	if value:
		visible = true

func set_editor_editing(value: bool) -> void:
	reset_inputs()
	_editor_editing = value
	if value:
		visible = true

func get_widget_rect(identifier: String) -> Rect2:
	var center := _widget_center(identifier)
	var radius := _hit_radius(identifier)
	return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)

func _hit_radius(identifier: String) -> float:
	var limit := minf(_safe_rect().size.x, _safe_rect().size.y) * 0.5
	if identifier == "move":
		return minf(_widget_radius(identifier) * 1.18, limit)
	if identifier == "aim":
		return minf(_widget_radius(identifier) * 1.28, limit)
	return minf(_widget_radius(identifier) + touch_target_padding * _layout_scale(), limit)

func _widget_item(identifier: String) -> Dictionary:
	if _hud_layout.is_empty():
		_hud_layout = HUD_LAYOUT.load_active()
	return _hud_layout[identifier]

func _widget_center(identifier: String) -> Vector2:
	var safe := _safe_rect()
	var radius := _hit_radius(identifier)
	var desired := HUD_LAYOUT.center(_widget_item(identifier), safe)
	return Vector2(clampf(desired.x, safe.position.x + radius, safe.end.x - radius), clampf(desired.y, safe.position.y + radius, safe.end.y - radius))

func _widget_radius(identifier: String) -> float:
	var base := move_joystick_radius if identifier == "move" else aim_joystick_radius if identifier == "aim" else 32.0 if identifier == "weapon_button" else module_button_radius
	return minf(base * _layout_scale() * float(_widget_item(identifier).get("s", 1.0)), minf(_safe_rect().size.x, _safe_rect().size.y) * 0.38)

func _widget_visible(identifier: String) -> bool:
	return bool(_widget_item(identifier).get("v", true))

func _widget_opacity(identifier: String) -> float:
	return float(_widget_item(identifier).get("o", 1.0))


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
	if player != null and is_instance_valid(player) and player.has_method("cancel_touch_action"):
		for action in _action_touches.values():
			if not str(action).is_empty():
				player.call("cancel_touch_action", action)
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
	return _widget_radius("move")


func _aim_radius() -> float:
	return _widget_radius("aim")


func _joystick_center() -> Vector2:
	return _widget_center("move")


func _aim_center() -> Vector2:
	return _widget_center("aim")


func _action_centers() -> Dictionary:
	return {"offensive": _widget_center("offensive_button"), "defensive": _widget_center("defensive_button"), "mobility": _widget_center("mobility_button"), "weapon": _widget_center("weapon_button")}


func _action_radius(action: String) -> float:
	return _widget_radius(action + "_button")


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
	if _widget_visible("move"):
		draw_circle(joystick, joystick_radius, _with_opacity(base_color, "move"))
		draw_arc(joystick, joystick_radius, 0.0, TAU, 48, _with_opacity(move_edge, "move"), 3.0 * scale, true)
		draw_circle(joystick + _joystick_vector * joystick_radius * 0.66, 30.0 * scale * float(_widget_item("move").s), _with_opacity(Color(0.30, 0.85, 0.92, 0.78), "move"))
	if _widget_visible("aim"):
		draw_circle(aim, aim_radius, _with_opacity(base_color, "aim"))
		draw_arc(aim, aim_radius, 0.0, TAU, 48, _with_opacity(aim_edge, "aim"), 3.0 * scale, true)
		draw_circle(aim + _aim_vector * aim_radius * 0.62, 25.0 * scale * float(_widget_item("aim").s), _with_opacity(Color(0.96, 0.66, 0.30, 0.76), "aim"))
		_draw_charge_feedback(aim, aim_radius, scale)
	if _widget_visible("offensive_button"):
		_draw_action(actions["offensive"], _action_radius("offensive"), _with_opacity(Color(0.35, 0.78, 0.96, 0.76), "offensive_button"), "A", "offensive_button")
		_draw_fulguro_charge_feedback(actions["offensive"], _action_radius("offensive"), scale)
	if _widget_visible("defensive_button"):
		_draw_action(actions["defensive"], _action_radius("defensive"), _with_opacity(Color(0.38, 0.90, 0.62, 0.76), "defensive_button"), "E", "defensive_button")
	if _widget_visible("mobility_button"):
		_draw_action(actions["mobility"], _action_radius("mobility"), _with_opacity(Color(0.92, 0.68, 0.30, 0.76), "mobility_button"), "R", "mobility_button")
	if _widget_visible("weapon_button") and (player == null or not bool(player.get("survival_mode"))):
		_draw_action(actions["weapon"], _action_radius("weapon"), _with_opacity(Color(0.70, 0.44, 0.80, 0.74), "weapon_button"), "G", "weapon_button")
	var font := ThemeDB.fallback_font
	if _widget_visible("move"):
		draw_string(font, joystick + Vector2(-30.0 * scale, joystick_radius * 0.72), "DÉPLACER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(14.0 * scale), _with_opacity(Color(0.82, 0.95, 0.97, 0.82), "move"))
	if _widget_visible("aim"):
		draw_string(font, aim + Vector2(-53.0 * scale, aim_radius * 0.72), "VISER / TIRER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(14.0 * scale), _with_opacity(Color(1.0, 0.88, 0.70, 0.86), "aim"))

func _with_opacity(color: Color, identifier: String) -> Color:
	return Color(color.r, color.g, color.b, color.a * _widget_opacity(identifier))


func _draw_fulguro_charge_feedback(center: Vector2, radius: float, scale: float) -> void:
	if player == null:
		return
	var progress := 0.0
	var color := Color("#ff7a28")
	if player.has_method("is_fulguro_charging") and bool(player.call("is_fulguro_charging")):
		progress = clampf(float(player.call("get_fulguro_charge_fraction")), 0.0, 1.0)
		color = Color("#ff7a28").lerp(Color("#fff0a0"), progress)
	elif player.has_method("is_pelto_preparing") and bool(player.call("is_pelto_preparing")):
		progress = clampf(float(player.call("get_pelto_preparation_fraction")), 0.0, 1.0)
		color = Color("#9a5b37").lerp(Color("#f0bd73"), progress)
	else:
		return
	draw_arc(center, radius + 7.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, _with_opacity(color, "offensive_button"), 5.0 * scale, true)
	draw_circle(center, radius * (0.18 + progress * 0.14), _with_opacity(Color(color.r, color.g, color.b, 0.22 + progress * 0.22), "offensive_button"))


func _draw_charge_feedback(center: Vector2, radius: float, scale: float) -> void:
	var state := "aim"
	var progress := 0.0
	if player != null and is_instance_valid(player):
		if player.has_method("get_mobile_blaster_input_state"):
			state = str(player.call("get_mobile_blaster_input_state"))
		if player.has_method("get_blaster_charge_ratio"):
			progress = clampf(float(player.call("get_blaster_charge_ratio")), 0.0, 1.0)
	if state == "charging":
		draw_arc(center, radius + 8.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * progress, 56, _with_opacity(Color(0.34, 0.91, 1.0, 0.94), "aim"), 7.0 * scale, true)
	elif state == "ready":
		var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.014)
		draw_arc(center, radius + 9.0 * scale, 0.0, TAU, 56, _with_opacity(Color(0.78, 1.0, 0.66, 0.84 + pulse * 0.16), "aim"), 8.0 * scale, true)
		draw_arc(center, radius + (14.0 + pulse * 3.0) * scale, 0.0, TAU, 56, _with_opacity(Color(0.78, 1.0, 0.66, 0.30), "aim"), 3.0 * scale, true)
	if _fire_feedback_remaining > 0.0:
		var flash := _fire_feedback_remaining / 0.16
		draw_arc(center, radius + (18.0 - flash * 8.0) * scale, 0.0, TAU, 48, _with_opacity(Color(1.0, 0.83, 0.44, flash), "aim"), 5.0 * scale, true)


func _draw_action(center: Vector2, radius: float, color: Color, label: String, identifier: String) -> void:
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 32, _with_opacity(Color(1.0, 1.0, 1.0, 0.72), identifier), 2.0, true)
	var font := ThemeDB.fallback_font
	var font_size := int(16.0 * _layout_scale())
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, center - Vector2(text_size.x * 0.5, -5.0 * _layout_scale()), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _with_opacity(Color.WHITE, identifier))


func _input(event: InputEvent) -> void:
	if _editor_editing or not _can_accept_inputs():
		return
	var handled := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.canceled:
			reset_inputs()
			handled = true
		else:
			handled = _begin_touch(touch.index, touch.position) if touch.pressed else _end_touch(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		handled = _update_touch(drag.index, drag.position)
	elif _editor_test and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
		handled = _begin_touch(-2, event.position) if event.pressed else _end_touch(-2)
	elif _editor_test and event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
		handled = _update_touch(-2, event.position)
	if handled:
		get_viewport().set_input_as_handled()


func _begin_touch(index: int, position: Vector2) -> bool:
	for rect in _reserved_rects:
		if rect.has_point(position):
			return false
	var ordered := INPUT_TIE_ORDER.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool:
		var first_order := int(_widget_item(a).z)
		var second_order := int(_widget_item(b).z)
		return INPUT_TIE_ORDER.find(a) < INPUT_TIE_ORDER.find(b) if first_order == second_order else first_order > second_order
	)
	for identifier in ordered:
		if not _widget_visible(identifier) or (identifier == "weapon_button" and bool(player.get("survival_mode"))):
			continue
		if position.distance_to(_widget_center(identifier)) > _hit_radius(identifier):
			continue
		if identifier == "move":
			if _joystick_touch != -1:
				continue
			_joystick_touch = index
			_update_joystick(position)
			return true
		if identifier == "aim":
			if _aim_touch != -1:
				continue
			_aim_touch = index
			_update_aim(position)
			if player.has_method("begin_touch_fire"):
				player.call("begin_touch_fire")
			elif player.has_method("set_touch_attack_held"):
				player.call("set_touch_attack_held", true)
			return true
		var action: String = str(identifier).trim_suffix("_button")
		# Keep the rejected finger owned by this button so it cannot migrate to a
		# joystick, but never forward its release to an already-running cast.
		_action_touches[index] = action if _press_action(action) else ""
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
		if not action.is_empty():
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


func _press_action(action: String) -> bool:
	if player.has_method("begin_touch_action"):
		return bool(player.call("begin_touch_action", action))
	elif player.has_method("trigger_touch_action"):
		player.call("trigger_touch_action", action)
		return true
	return false


func _release_action(action: String) -> void:
	if player.has_method("end_touch_action"):
		player.call("end_touch_action", action)
