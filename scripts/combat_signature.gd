extends Control

## A single short, bounded success card and a fixed impact stamp. No world nodes,
## full-screen flash, time scaling, collision or gameplay randomness.
const STYLES := {
	"shotgun": {"title": "PLEIN IMPACT", "detail": "SHOTGUN · 6 PLOMBS AU BUT", "color": Color("#ffd18a"), "life": 0.90, "stamp": 0.28},
	"counter": {"title": "PARADE", "detail": "COUNTER · RIPOSTE PRÊTE", "color": Color("#d5b2ff"), "life": 1.05, "stamp": 0.34},
	"fulguro_punch": {"title": "ÉCRASEMENT", "detail": "FULGURO · COLLISION MURALE", "color": Color("#ffad66"), "life": 1.05, "stamp": 0.34},
	"longshot": {"title": "EXÉCUTION", "detail": "LONGSHOT · TIR RENFORCÉ AU BUT", "color": Color("#8eeaff"), "life": 0.95, "stamp": 0.30},
}
const DISPLAY_FONT := preload("res://art/ui/fonts/RussoOne-Regular.ttf")
var kind := ""
var age := 0.0
var impact_position := Vector3.ZERO
var impact_target: WeakRef
var observer: WeakRef
var notice_top := 90.0
var _title: Label
var _detail: Label
var card_rect := Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_title = Label.new()
	_title.add_theme_font_override("font", DISPLAY_FONT)
	_title.add_theme_font_size_override("font_size", 18)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 11)
	for label in [_title, _detail]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		add_child(label)
	clear()

func show_success(id: String, target: Node3D, viewer: Node3D, at: Vector3) -> void:
	if not STYLES.has(id):
		return
	kind = id
	age = 0.0
	impact_position = at
	impact_target = weakref(target)
	observer = weakref(viewer)
	_title.text = STYLES[id].title
	_detail.text = STYLES[id].detail
	_title.add_theme_color_override("font_color", STYLES[id].color)
	_detail.add_theme_color_override("font_color", Color("#e0d6c9"))
	show()
	_layout()
	queue_redraw()

func clear() -> void:
	kind = ""
	age = 0.0
	impact_target = null
	observer = null
	hide()
	queue_redraw()

func _process(delta: float) -> void:
	if kind.is_empty():
		return
	age += delta
	if age >= float(STYLES[kind].life):
		clear()
		return
	_layout()
	queue_redraw()

func _layout() -> void:
	var width := minf(310.0, maxf(180.0, size.x - 32.0))
	var enter := 1.0 - pow(1.0 - clampf(age / 0.10, 0.0, 1.0), 3.0)
	card_rect = Rect2(Vector2((size.x - width) * 0.5, clampf(notice_top, 8.0, maxf(8.0, size.y - 55.0)) - (1.0 - enter) * 7.0), Vector2(width, 45.0))
	_title.position = card_rect.position + Vector2(46, 1)
	_title.size = Vector2(width - 54.0, 25.0)
	_detail.position = card_rect.position + Vector2(46, 25)
	_detail.size = Vector2(width - 54.0, 17.0)
	modulate.a = 1.0 - smoothstep(float(STYLES[kind].life) - 0.20, float(STYLES[kind].life), age)

func _draw() -> void:
	if kind.is_empty():
		return
	var color: Color = STYLES[kind].color
	var rect := card_rect
	var points := PackedVector2Array([rect.position + Vector2(7, 0), rect.position + Vector2(rect.size.x - 7, 0), rect.position + Vector2(rect.size.x, 7), rect.end - Vector2(0, 7), rect.end - Vector2(7, 0), rect.position + Vector2(7, rect.size.y), rect.position + Vector2(0, rect.size.y - 7), rect.position + Vector2(0, 7)])
	draw_colored_polygon(points, Color(0.045, 0.055, 0.065, 0.90))
	points.append(points[0])
	draw_polyline(points, Color(color, 0.65), 1.3, true)
	draw_line(rect.position + Vector2(43, 8), rect.position + Vector2(43, 37), Color(color, 0.30), 1.0)
	_glyph(rect.position + Vector2(23, 22), 12.0, color)
	# Impact positions are captured once. Never follow a hidden or moving victim.
	if age > float(STYLES[kind].stamp) or impact_target == null or observer == null:
		return
	var target: Node3D = impact_target.get_ref()
	var viewer: Node3D = observer.get_ref()
	if not is_instance_valid(target) or not is_instance_valid(viewer) or not target.is_visible_in_tree():
		return
	if target != viewer and target.has_method("is_visible_to") and not bool(target.call("is_visible_to", viewer)):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(impact_position):
		return
	var at := camera.unproject_position(impact_position)
	if not Rect2(Vector2.ZERO, size).grow(-18.0).has_point(at):
		return
	var progress := age / float(STYLES[kind].stamp)
	var radius := lerpf(17.0, 31.0, 1.0 - pow(1.0 - progress, 3.0))
	color.a = pow(1.0 - progress, 1.3)
	_glyph(at, radius, Color(0.025, 0.035, 0.04, color.a), 5.0)
	_glyph(at, radius, color, 2.2)

func _glyph(at: Vector2, radius: float, color: Color, width: float = 2.0) -> void:
	if kind == "counter":
		var shield := PackedVector2Array([at + Vector2(-radius * 0.75, -radius * 0.7), at + Vector2(0, -radius), at + Vector2(radius * 0.75, -radius * 0.7), at + Vector2(radius * 0.55, radius * 0.4), at + Vector2(0, radius), at + Vector2(-radius * 0.55, radius * 0.4), at + Vector2(-radius * 0.75, -radius * 0.7)])
		draw_polyline(shield, color, width, true)
		draw_polyline(PackedVector2Array([at + Vector2(-radius * 0.35, 0), at + Vector2(0, radius * 0.3), at + Vector2(radius * 0.38, -radius * 0.35)]), color, width, true)
	elif kind == "longshot":
		var diamond := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0), at + Vector2(0, -radius)])
		draw_polyline(diamond, color, width, true)
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(at + direction * radius * 0.26, at + direction * radius * 0.58, color, width, true)
	elif kind == "fulguro_punch":
		var burst := PackedVector2Array()
		for index in range(17):
			var angle := float(index) * TAU / 16.0
			burst.append(at + Vector2(cos(angle), sin(angle)) * radius * (1.0 if index % 2 == 0 else 0.57))
		draw_polyline(burst, color, width, true)
	else:
		for index in range(6):
			var angle := float(index) * TAU / 6.0 + PI / 6.0
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(at + direction * radius * 0.47, at + direction * radius, color, width, true)
		draw_circle(at, radius * 0.12, color, false, width, true)
