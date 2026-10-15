extends Control

const HUD_LAYOUT := preload("res://scripts/hud_layout.gd")
const MODULE_VISUAL := preload("res://scripts/touch_module_visual.gd")
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
var _module_aim_vector := Vector2.ZERO
var _fire_feedback_remaining := 0.0
var _cancel_feedback_remaining := 0.0
var _inputs_suspended := false
var _hud_layout: Dictionary = {}
var _reserved_rects: Array[Rect2] = []
var _editor_test := false
var _editor_editing := false
var _module_visual := MODULE_VISUAL.new()
var _cancel_canvas: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested()
	_hud_layout = HUD_LAYOUT.load_active()
	# The minimap uses layer 2. Only the transient cancel target goes above it;
	# the configurable joysticks and module buttons keep their existing order.
	var cancel_layer := CanvasLayer.new()
	cancel_layer.name = "SpellCancelOverlay"
	cancel_layer.layer = 3
	add_child(cancel_layer)
	_cancel_canvas = Control.new()
	_cancel_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cancel_layer.add_child(_cancel_canvas)
	_cancel_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cancel_canvas.draw.connect(func() -> void: _draw_cancel_zone(_cancel_canvas, _layout_scale()))
	_cancel_canvas.visible = is_visible_in_tree()
	queue_redraw()


func _touch_preview_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "touch_preview":
			return true
	return false


func set_player(value: Node) -> void:
	if player != value:
		reset_inputs()
		_module_visual.reset()
	player = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		reset_inputs()
		queue_redraw()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_inputs()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		reset_inputs()
		if _cancel_canvas != null:
			_cancel_canvas.hide()


func _exit_tree() -> void:
	reset_inputs()


func _process(delta: float) -> void:
	var suspended := not _can_accept_inputs()
	if suspended and not _inputs_suspended:
		reset_inputs()
	_inputs_suspended = suspended
	var desktop_action := _desktop_cancel_action()
	if _cancel_canvas != null:
		_cancel_canvas.visible = not _editor_editing and _can_accept_gameplay_inputs() and (not suspended or not desktop_action.is_empty() or _cancel_feedback_remaining > 0.0)
	_cancel_feedback_remaining = maxf(0.0, _cancel_feedback_remaining - delta)
	if _cancel_canvas != null:
		_cancel_canvas.queue_redraw()
	if not visible:
		_module_visual.reset()
		return
	_module_visual.update(player, delta, not suspended)
	_fire_feedback_remaining = maxf(0.0, _fire_feedback_remaining - delta)
	queue_redraw()


func _can_accept_inputs() -> bool:
	return is_visible_in_tree() and _can_accept_gameplay_inputs()


func _can_accept_gameplay_inputs() -> bool:
	if get_tree().paused or player == null or not is_instance_valid(player):
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
	_module_aim_vector = Vector2.ZERO
	_fire_feedback_remaining = 0.0
	_cancel_feedback_remaining = 0.0
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


func _can_cancel_action(action: String) -> bool:
	return not action.is_empty() and player != null and is_instance_valid(player) and player.has_method("can_cancel_aimed_action") and bool(player.call("can_cancel_aimed_action", action))


func _desktop_cancel_action() -> String:
	if _editor_editing or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or not _can_accept_gameplay_inputs() or not player.has_method("can_cancel_aimed_action"):
		return ""
	for action in ["offensive", "mobility"]:
		if bool(player.call("can_cancel_aimed_action", action, false)):
			return action
	return ""


func _try_cancel_desktop_at(position: Vector2) -> bool:
	var action := _desktop_cancel_action()
	if action.is_empty():
		return false
	var rect := _cancel_zone_rect()
	if position.distance_to(rect.get_center()) > rect.size.x * 0.5:
		return false
	player.call("cancel_aimed_action", action, false)
	_cancel_feedback_remaining = 0.35
	if _cancel_canvas != null:
		_cancel_canvas.queue_redraw()
	return true


func _has_cancellable_action() -> bool:
	for action in _action_touches.values():
		if _can_cancel_action(str(action)):
			return true
	return false


func _cancel_zone_for_safe_rect(safe: Rect2) -> Rect2:
	var scale := _layout_scale_for_rect(safe)
	var extent := Vector2.ONE * minf(112.0 * scale, minf(safe.size.x, safe.size.y))
	var margin := 16.0 * scale
	return Rect2(Vector2(safe.end.x - extent.x - margin, safe.position.y + 100.0 * scale), extent)


func _cancel_zone_rect() -> Rect2:
	var safe := _safe_rect()
	var rect := _cancel_zone_for_safe_rect(safe)
	var obstacles: Array[Rect2] = _reserved_rects.duplicate()
	if _widget_visible("weapon_button") and not bool(player.get("survival_mode")):
		obstacles.append(get_widget_rect("weapon_button"))
	# Keep the transient target below Pause/Menu and a relocated weapon button.
	for attempt in range(obstacles.size() + 1):
		var previous_y := rect.position.y
		for obstacle in obstacles:
			if rect.intersects(obstacle):
				rect.position.y = obstacle.end.y + 8.0 * _layout_scale()
		if rect.position.y == previous_y:
			break
	rect.position.y = minf(rect.position.y, safe.end.y - rect.size.y)
	return rect


func _draw_cancel_zone(canvas: Control, scale: float) -> void:
	if not _has_cancellable_action() and _desktop_cancel_action().is_empty() and _cancel_feedback_remaining <= 0.0:
		return
	var rect := _cancel_zone_rect()
	var center := rect.get_center()
	var radius := rect.size.x * 0.5
	var feedback := _cancel_feedback_remaining > 0.0
	var color := Color("#ffb19d") if feedback else Color("#ff7968")
	canvas.draw_circle(center, radius, Color(0.20, 0.045, 0.035, 0.86))
	canvas.draw_arc(center, radius, 0.0, TAU, 48, color, 3.0 * scale, true)
	var cross_center := center - Vector2(0.0, 10.0 * scale)
	var cross := 10.0 * scale
	canvas.draw_line(cross_center - Vector2(cross, cross), cross_center + Vector2(cross, cross), color, 4.0 * scale, true)
	canvas.draw_line(cross_center + Vector2(-cross, cross), cross_center + Vector2(cross, -cross), color, 4.0 * scale, true)
	var label := "ANNULÉ" if feedback else "ANNULER"
	var font := ThemeDB.fallback_font
	var font_size := int(14.0 * scale)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	canvas.draw_string(font, center + Vector2(-width * 0.5, 30.0 * scale), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


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
		_draw_module_action("offensive", actions["offensive"], Color("#66d6ee"))
		_draw_fulguro_charge_feedback(actions["offensive"], _action_radius("offensive"), scale)
		_draw_javelin_charge_feedback(actions["offensive"], _action_radius("offensive"), scale)
		_draw_javelin_recast_feedback(actions["offensive"], _action_radius("offensive"), scale)
	if _widget_visible("defensive_button"):
		_draw_module_action("defensive", actions["defensive"], Color("#87e3bb"))
	if _widget_visible("mobility_button"):
		_draw_module_action("mobility", actions["mobility"], Color("#edbb70"))
		if player != null and player.has_method("is_eclipse_aiming") and bool(player.call("is_eclipse_aiming")):
			var center: Vector2 = actions["mobility"]
			var radius := _action_radius("mobility") * 2.2
			draw_circle(center, radius, Color(0.12, 0.08, 0.22, 0.55))
			draw_arc(center, radius, 0.0, TAU, 48, Color("#a996ff"), 3.0, true)
			var vector: Vector2 = player.get("_eclipse").get("_touch_vector")
			draw_circle(center + vector * radius, 14.0 * scale, Color("#dccfff"))
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
	if player.has_method("is_pelto_preparing") and bool(player.call("is_pelto_preparing")):
		draw_arc(center, radius * 1.55, 0.0, TAU, 48, _with_opacity(Color(color.r, color.g, color.b, 0.55), "offensive_button"), 2.0 * scale, true)
		draw_circle(center + _module_aim_vector * radius * 0.95, radius * 0.30, _with_opacity(color, "offensive_button"))
		draw_string(ThemeDB.fallback_font, center + Vector2(-58, -radius * 1.7), "VISER / RELÂCHER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(13 * scale), _with_opacity(color, "offensive_button"))


func _draw_javelin_charge_feedback(center: Vector2, radius: float, scale: float) -> void:
	if player == null or not player.has_method("is_javelin_charging") or not bool(player.call("is_javelin_charging")):
		return
	var progress := float(player.call("get_javelin_charge_fraction"))
	var color := Color("#44c8ff").lerp(Color("#ddffff"), progress)
	draw_circle(center, radius * 1.55, _with_opacity(Color(0.04, 0.14, 0.22, 0.65), "offensive_button"))
	draw_arc(center, radius * 1.55, 0.0, TAU, 48, _with_opacity(Color(0.3, 0.8, 1.0, 0.45), "offensive_button"), 2.0 * scale, true)
	draw_arc(center, radius + 7.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, _with_opacity(color, "offensive_button"), 5.0 * scale, true)
	draw_circle(center + _module_aim_vector * radius * 0.95, radius * 0.34, _with_opacity(color, "offensive_button"))
	var text := "MAX • RELÂCHER" if progress >= 1.0 else "CHARGE %d%%" % roundi(progress * 100.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-44, -radius * 1.7), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(13 * scale), _with_opacity(color, "offensive_button"))


func _draw_javelin_recast_feedback(center: Vector2, radius: float, scale: float) -> void:
	if player == null or not player.has_method("get_offensive_module_id") or str(player.call("get_offensive_module_id")) != "javelin":
		return
	var remaining := float(player.call("get_javelin_recast_fraction"))
	if remaining <= 0.0:
		return
	var color := _with_opacity(Color("#ffe19a"), "offensive_button")
	draw_arc(center, radius + 7.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * remaining, 48, color, 5.0 * scale, true)
	draw_string(ThemeDB.fallback_font, center + Vector2(-43, -radius - 17 * scale), "TÉLÉPORTER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(13 * scale), color)


func _draw_charge_feedback(center: Vector2, radius: float, scale: float) -> void:
	var state := "aim"
	var progress := 0.0
	if player != null and is_instance_valid(player):
		if player.has_method("get_mobile_blaster_input_state"):
			state = str(player.call("get_mobile_blaster_input_state"))
		if player.has_method("get_blaster_charge_ratio"):
			progress = clampf(float(player.call("get_blaster_charge_ratio")), 0.0, 1.0)
		if player.has_method("get_blaster_heat_fraction") and str(player.call("get_weapon_id")) == "blaster":
			var heat := clampf(float(player.call("get_blaster_heat_fraction")), 0.0, 1.0)
			var heat_color := Color("#ff7960") if state == "overheated" else Color("#ffc069")
			draw_arc(center, radius + 17.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * heat, 56, _with_opacity(heat_color, "aim"), 4.0 * scale, true)
	if state == "overheated":
		var label := "SURCHAUFFE"
		var font := ThemeDB.fallback_font
		var font_size := int(13 * scale)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		draw_string(font, center + Vector2(-width * 0.5, -radius - 25.0 * scale), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _with_opacity(Color("#ff7960"), "aim"))
	if state == "charging":
		draw_arc(center, radius + 8.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * progress, 56, _with_opacity(Color(0.34, 0.91, 1.0, 0.94), "aim"), 7.0 * scale, true)
	elif state == "ready":
		var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.014)
		draw_arc(center, radius + 9.0 * scale, 0.0, TAU, 56, _with_opacity(Color(0.78, 1.0, 0.66, 0.84 + pulse * 0.16), "aim"), 8.0 * scale, true)
		draw_arc(center, radius + (14.0 + pulse * 3.0) * scale, 0.0, TAU, 56, _with_opacity(Color(0.78, 1.0, 0.66, 0.30), "aim"), 3.0 * scale, true)
	if _fire_feedback_remaining > 0.0:
		var flash := _fire_feedback_remaining / 0.16
		draw_arc(center, radius + (18.0 - flash * 8.0) * scale, 0.0, TAU, 48, _with_opacity(Color(1.0, 0.83, 0.44, flash), "aim"), 5.0 * scale, true)


func _draw_module_action(action: String, center: Vector2, accent: Color) -> void:
	_module_visual.draw_button(self, action, center, _action_radius(action), accent, _widget_opacity(action + "_button"), _layout_scale())


func _draw_action(center: Vector2, radius: float, color: Color, label: String, identifier: String) -> void:
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 32, _with_opacity(Color(1.0, 1.0, 1.0, 0.72), identifier), 2.0, true)
	var font := ThemeDB.fallback_font
	var font_size := int(16.0 * _layout_scale())
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, center - Vector2(text_size.x * 0.5, -5.0 * _layout_scale()), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _with_opacity(Color.WHITE, identifier))


func _input(event: InputEvent) -> void:
	# Desktop aiming uses keyboard holds while the touch joysticks are hidden.
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _try_cancel_desktop_at(event.position):
		get_viewport().set_input_as_handled()
		return
	if _editor_editing or not _can_accept_inputs():
		return
	var handled := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.canceled:
			reset_inputs()
			handled = true
		else:
			if touch.pressed:
				handled = _begin_touch(touch.index, touch.position)
			else:
				if _action_touches.has(touch.index):
					_update_touch(touch.index, touch.position)
				handled = _end_touch(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		handled = _update_touch(drag.index, drag.position)
	elif _editor_test and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
		if event.pressed:
			handled = _begin_touch(-2, event.position)
		else:
			if _action_touches.has(-2):
				_update_touch(-2, event.position)
			handled = _end_touch(-2)
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
		if not str(_action_touches[index]).is_empty():
			_cancel_feedback_remaining = 0.0
		if _action_touches[index] == "offensive":
			_module_aim_vector = Vector2.ZERO
		return true
	return false


func _update_touch(index: int, position: Vector2) -> bool:
	if index == _joystick_touch:
		_update_joystick(position)
		return true
	if index == _aim_touch:
		_update_aim(position)
		return true
	var action := str(_action_touches.get(index, ""))
	if _can_cancel_action(action):
		var cancel_rect := _cancel_zone_rect()
		if position.distance_to(cancel_rect.get_center()) <= cancel_rect.size.x * 0.5:
			player.call("cancel_aimed_action", action)
			# Consume this finger until it lifts: leaving the zone cannot revive the
			# cast, and the release must never become a shot or a fresh activation.
			_action_touches[index] = ""
			if action == "offensive":
				_module_aim_vector = Vector2.ZERO
			_cancel_feedback_remaining = 0.35
			queue_redraw()
			return true
	if str(_action_touches.get(index, "")) == "offensive" and player.has_method("is_pelto_preparing") and bool(player.call("is_pelto_preparing")):
		_module_aim_vector = ((position - _widget_center("offensive_button")) / (_action_radius("offensive") * 1.55)).limit_length(1.0)
		player.call("set_pelto_touch_aim", _module_aim_vector)
		return true
	if str(_action_touches.get(index, "")) == "offensive" and player.has_method("is_javelin_charging") and bool(player.call("is_javelin_charging")):
		_module_aim_vector = ((position - _widget_center("offensive_button")) / (_action_radius("offensive") * 1.55)).limit_length(1.0)
		player.call("set_javelin_touch_aim", _module_aim_vector)
		return true
	if str(_action_touches.get(index, "")) == "mobility" and player.has_method("set_eclipse_touch_vector"):
		player.call("set_eclipse_touch_vector", (position - _widget_center("mobility_button")) / (_action_radius("mobility") * 2.2))
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
			if action == "offensive":
				_module_aim_vector = Vector2.ZERO
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
