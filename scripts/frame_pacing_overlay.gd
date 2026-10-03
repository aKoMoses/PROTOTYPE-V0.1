extends CanvasLayer
## Shared across scenes, including loading/pause. Wall-clock intervals expose
## stalls even when Godot clamps simulation delta. UI refreshes only at 4 Hz.
const SAMPLE_COUNT := 120
var _intervals := PackedFloat32Array()
var _cursor := 0
var _count := 0
var _previous_usec := 0
var _refresh := 0.0
var _label: Label
var _panel: PanelContainer

func _ready() -> void:
	name = "FramePacing"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless":
		Engine.max_fps = 60
	_intervals.resize(SAMPLE_COUNT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(12, 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.045, 0.8)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("#adebbb"))
	_label.text = "FPS · mesure…"
	_panel.add_child(_label)
	_previous_usec = Time.get_ticks_usec()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	record_interval((now - _previous_usec) / 1000.0)
	_previous_usec = now
	_refresh += delta
	if _refresh < 0.25:
		return
	_refresh = 0.0
	var stats := get_stats()
	_label.text = "%.0f FPS · %.1f ms\npic %.1f ms · >33 ms : %d" % [stats.fps, stats.average_ms, stats.peak_ms, stats.stalls]
	_label.add_theme_color_override("font_color", Color("#ffb276") if stats.peak_ms > 33.333 else Color("#adebbb"))

func record_interval(milliseconds: float) -> void:
	if _intervals.size() != SAMPLE_COUNT:
		_intervals.resize(SAMPLE_COUNT)
	_intervals[_cursor] = maxf(milliseconds, 0.001)
	_cursor = (_cursor + 1) % SAMPLE_COUNT
	_count = mini(_count + 1, SAMPLE_COUNT)

func get_stats() -> Dictionary:
	var total := 0.0
	var peak := 0.0
	var stalls := 0
	for index in _count:
		var interval := float(_intervals[index])
		total += interval
		peak = maxf(peak, interval)
		if interval > 33.333:
			stalls += 1
	var average := total / maxf(_count, 1)
	return {"fps": 1000.0 / maxf(average, 0.001), "average_ms": average, "peak_ms": peak, "stalls": stalls}

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_panel.visible = not _panel.visible
