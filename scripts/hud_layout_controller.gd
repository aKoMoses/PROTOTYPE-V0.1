class_name PrototypeHudLayoutController
extends Node

const LAYOUT := preload("res://scripts/hud_layout.gd")

var touch: Control
var layout: Dictionary = {}
var controls: Dictionary = {}
var original_sizes: Dictionary = {}
var slot_origins: Dictionary = {}
var contextual: Dictionary = {}
var preview_mode := false

func _ready() -> void:
	if layout.is_empty():
		layout = LAYOUT.load_active()
	get_viewport().size_changed.connect(apply)
	call_deferred("apply")

func bind_touch(value: Control) -> void:
	touch = value
	if is_inside_tree():
		apply()

func register(identifier: String, control: Control, is_contextual: bool = false) -> void:
	controls[identifier] = control
	contextual[identifier] = is_contextual
	original_sizes[identifier] = control.size
	if identifier in LAYOUT.MODULE_IDS:
		slot_origins[identifier] = control.position
	if is_inside_tree():
		call_deferred("apply")

func set_layout(value: Dictionary) -> void:
	layout = LAYOUT.sanitize(value)
	apply()

func set_preview(value: bool) -> void:
	preview_mode = value
	apply()

func apply() -> void:
	if not is_inside_tree():
		return
	if layout.is_empty():
		layout = LAYOUT.load_active()
	if touch != null and is_instance_valid(touch):
		touch.call("set_hud_layout", layout)
	var safe := LAYOUT.safe_rect(get_viewport())
	for identifier in controls.keys():
		if identifier in LAYOUT.MODULE_IDS:
			continue
		_apply_control(identifier, safe)
	for identifier in LAYOUT.MODULE_IDS:
		if controls.has(identifier):
			_apply_slot(identifier)
	if touch != null and is_instance_valid(touch):
		var reserved: Array[Rect2] = []
		for identifier in ["pause", "training_menu"]:
			if controls.has(identifier) and is_instance_valid(controls[identifier]) and controls[identifier].visible:
				reserved.append(widget_rect(identifier))
		touch.call("set_reserved_rects", reserved)

func _apply_control(identifier: String, safe: Rect2) -> void:
	var control: Control = controls[identifier]
	if not is_instance_valid(control):
		return
	var item: Dictionary = layout[identifier]
	var dimensions: Vector2 = original_sizes[identifier] * float(item.s)
	var usable := Vector2(maxf(1.0, safe.size.x), maxf(1.0, safe.size.y))
	var fitted_scale := minf(float(item.s), minf(usable.x / maxf(1.0, original_sizes[identifier].x), usable.y / maxf(1.0, original_sizes[identifier].y)))
	dimensions = original_sizes[identifier] * fitted_scale
	var center := LAYOUT.center(item, safe)
	center.x = clampf(center.x, safe.position.x + dimensions.x * 0.5, safe.end.x - dimensions.x * 0.5)
	center.y = clampf(center.y, safe.position.y + dimensions.y * 0.5, safe.end.y - dimensions.y * 0.5)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.pivot_offset = original_sizes[identifier] * 0.5
	control.scale = Vector2.ONE * fitted_scale
	control.position = center - original_sizes[identifier] * 0.5
	control.modulate.a = float(item.o)
	if not bool(contextual.get(identifier, false)) or preview_mode:
		control.visible = bool(item.v)
	elif not bool(item.v):
		control.visible = false
	control.z_index = int(item.z)

func _apply_slot(identifier: String) -> void:
	var control: Control = controls[identifier]
	if not is_instance_valid(control):
		return
	var item: Dictionary = layout[identifier]
	var origin: Vector2 = slot_origins[identifier]
	var parent := control.get_parent() as Control
	var parent_height := maxf(1.0, parent.size.y)
	var shift := Vector2(float(item.d[0]), float(item.d[1])) * parent_height
	control.pivot_offset = original_sizes[identifier] * 0.5
	var safe := LAYOUT.safe_rect(get_viewport())
	var parent_scale := parent.get_global_transform_with_canvas().get_scale().abs()
	var fit := minf(safe.size.x / maxf(1.0, original_sizes[identifier].x * parent_scale.x), safe.size.y / maxf(1.0, original_sizes[identifier].y * parent_scale.y))
	control.scale = Vector2.ONE * minf(float(item.s), fit)
	control.position = origin + shift
	control.modulate.a = float(item.o)
	control.visible = bool(item.v)
	control.z_index = int(item.z)
	var rect := widget_rect(identifier)
	var desired := Vector2(clampf(rect.get_center().x, safe.position.x + minf(rect.size.x, safe.size.x) * 0.5, safe.end.x - minf(rect.size.x, safe.size.x) * 0.5), clampf(rect.get_center().y, safe.position.y + minf(rect.size.y, safe.size.y) * 0.5, safe.end.y - minf(rect.size.y, safe.size.y) * 0.5))
	var original_local := parent.get_global_transform_with_canvas().affine_inverse() * rect.get_center()
	var desired_local := parent.get_global_transform_with_canvas().affine_inverse() * desired
	control.position += desired_local - original_local

func widget_rect(identifier: String) -> Rect2:
	if identifier in LAYOUT.TOUCH_IDS:
		return touch.call("get_widget_rect", identifier) if touch != null else Rect2()
	if not controls.has(identifier) or not is_instance_valid(controls[identifier]):
		return Rect2()
	var control: Control = controls[identifier]
	var transform := control.get_global_transform_with_canvas()
	var points := [transform * Vector2.ZERO, transform * Vector2(control.size.x, 0.0), transform * control.size, transform * Vector2(0.0, control.size.y)]
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect

func ids() -> Array:
	var result := LAYOUT.TOUCH_IDS.duplicate()
	if touch != null and touch.get("player") != null and bool(touch.get("player").get("survival_mode")):
		result.erase("weapon_button")
	for identifier in controls.keys():
		result.append(identifier)
	return result

func set_widget_center(identifier: String, desired: Vector2) -> void:
	var item: Dictionary = layout[identifier]
	if identifier in LAYOUT.MODULE_IDS:
		var control: Control = controls[identifier]
		var parent: Control = control.get_parent()
		var safe := LAYOUT.safe_rect(get_viewport())
		var extent := widget_rect(identifier).size
		var half := Vector2(minf(extent.x, safe.size.x) * 0.5, minf(extent.y, safe.size.y) * 0.5)
		desired = Vector2(clampf(desired.x, safe.position.x + half.x, safe.end.x - half.x), clampf(desired.y, safe.position.y + half.y, safe.end.y - half.y))
		var local := parent.get_global_transform_with_canvas().affine_inverse() * desired
		var base_center: Vector2 = slot_origins[identifier] + original_sizes[identifier] * 0.5
		var delta: Vector2 = (local - base_center) / maxf(1.0, parent.size.y)
		item.d = [clampf(delta.x, -3.0, 3.0), clampf(delta.y, -3.0, 3.0)]
	else:
		LAYOUT.set_center(item, desired, LAYOUT.safe_rect(get_viewport()), widget_rect(identifier).size)
	layout[identifier] = item
	apply()
