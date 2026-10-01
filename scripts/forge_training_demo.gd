extends Control

## Small, silent training clips. Preloads keep every video in exported builds.
const LOADOUT := preload("res://scripts/loadout_state.gd")
const CLIPS := {
	"blaster": preload("res://art/forge-demos/blaster.ogv"),
	"shotgun": preload("res://art/forge-demos/shotgun.ogv"),
	"mekatana": preload("res://art/forge-demos/mekatana.ogv"),
	"longshot": preload("res://art/forge-demos/longshot.ogv"),
	"modulo_drone": preload("res://art/forge-demos/modulo_drone.ogv"),
	"rocket_basket": preload("res://art/forge-demos/rocket_basket.ogv"),
	"javelin": preload("res://art/forge-demos/javelin.ogv"),
	"fulguro_punch": preload("res://art/forge-demos/fulguro_punch.ogv"),
	"pelto_smash": preload("res://art/forge-demos/pelto_smash.ogv"),
	"magnetic_field": preload("res://art/forge-demos/magnetic_field.ogv"),
	"static_shield": preload("res://art/forge-demos/static_shield.ogv"),
	"projector": preload("res://art/forge-demos/projector.ogv"),
	"counter": preload("res://art/forge-demos/counter.ogv"),
	"pyro_boots": preload("res://art/forge-demos/pyro_boots.ogv"),
	"bio_injector": preload("res://art/forge-demos/bio_injector.ogv"),
	"permutation": preload("res://art/forge-demos/permutation.ogv"),
	"eclipse": preload("res://art/forge-demos/eclipse.ogv"),
	"baroud": preload("res://art/forge-demos/baroud.ogv"),
	"omnivamp": preload("res://art/forge-demos/omnivamp.ogv"),
	"auxiliary_reactor": preload("res://art/forge-demos/auxiliary_reactor.ogv"),
	"tracker": preload("res://art/forge-demos/tracker.ogv"),
	"alternator": preload("res://art/forge-demos/alternator.ogv"),
	"inertia": preload("res://art/forge-demos/inertia.ogv"),
}
var equipment_id := ""
var thumbnail_rect := Rect2(1, 24, 222, 124)
var thumbnail_overlay: Control
var video: VideoStreamPlayer
var title: Label
var _video_layer: CanvasLayer
var _viewer: ColorRect
var _viewer_panel: Panel
var _viewer_title: Label
var _close_button: Button
var _previous_focus: Control
var _suppress_touch_mouse := false


func _ready() -> void:
	name = "TrainingDemo"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	set_process_input(false)
	var frame := Panel.new()
	frame.position = thumbnail_rect.position - Vector2.ONE
	frame.size = thumbnail_rect.size + Vector2.ONE * 2
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151b20")
	style.border_color = Color("#74604a")
	style.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)
	video = VideoStreamPlayer.new()
	video.name = "TrainingVideo"
	video.position = thumbnail_rect.position
	video.size = thumbnail_rect.size
	video.expand = true
	video.volume_db = -80
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.finished.connect(_loop)
	add_child(video)
	title = Label.new()
	title.size = Vector2(224, 21)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("#f5b844"))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	_build_viewer()
	visibility_changed.connect(_sync_visibility)
	show_equipment("blaster")


func show_equipment(identifier: String) -> void:
	if identifier == equipment_id:
		return
	equipment_id = identifier
	if video == null:
		return
	close_enlarged()
	video.stop()
	video.stream = CLIPS.get(identifier)
	title.text = LOADOUT.display_name(identifier)
	_viewer_title.text = title.text
	tooltip_text = "Démo en entraînement · " + title.text + "\nCliquer pour agrandir"
	# Newly pulled equipment can arrive before its training clip. Hide the
	# preview instead of retaining the previous equipment's demonstration.
	visible = video.stream != null
	_sync_visibility()


func _sync_visibility() -> void:
	if video == null:
		return
	if not is_visible_in_tree():
		_suppress_touch_mouse = false
		close_enlarged()
		set_process_input(false)
	video.visible = is_visible_in_tree()
	if is_visible_in_tree():
		video.play()
	else:
		video.stop()


func _loop() -> void:
	if is_visible_in_tree():
		video.play()


func _process(_delta: float) -> void:
	if is_visible_in_tree() and not _viewer.visible:
		_layout_video()


func _gui_input(event: InputEvent) -> void:
	if _is_pointer_press(event) or event.is_action_pressed("ui_accept"):
		show_enlarged()
		accept_event()


func _input(event: InputEvent) -> void:
	if _suppress_touch_mouse and event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		if not event.pressed:
			_suppress_touch_mouse = false
			set_process_input(_viewer.visible)
		return
	if not _viewer.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_enlarged()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.is_action("ui_accept"):
		# Keep keyboard focus in the viewer instead of reaching the garage behind it.
		get_viewport().set_input_as_handled()


func _is_pointer_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		# Touch is handled above; ignore its synthesized mouse event.
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION
	return false


func show_enlarged() -> void:
	if not is_visible_in_tree() or _viewer.visible:
		return
	_previous_focus = get_viewport().gui_get_focus_owner()
	_viewer.show()
	_layout_viewer()
	_close_button.grab_focus()
	set_process_input(true)


func close_enlarged() -> void:
	if _viewer == null or not _viewer.visible:
		return
	_viewer.hide()
	_layout_video()
	set_process_input(_suppress_touch_mouse)
	_close_button.release_focus()
	if is_visible_in_tree() and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null


func _build_viewer() -> void:
	_video_layer = CanvasLayer.new()
	_video_layer.name = "TrainingDemoPresentation"
	_video_layer.layer = 40
	add_child(_video_layer)
	_viewer = ColorRect.new()
	_viewer.name = "Backdrop"
	_viewer.color = Color(0.025, 0.03, 0.04, 0.94)
	_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	_video_layer.add_child(_viewer)
	_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer.gui_input.connect(func(event: InputEvent) -> void:
		if _is_pointer_press(event):
			# The emulated mouse press must not reach buttons behind a dismissed viewer.
			_suppress_touch_mouse = event is InputEventScreenTouch
			_viewer.accept_event()
			close_enlarged()
	)
	_viewer_panel = Panel.new()
	_viewer_panel.name = "VideoFrame"
	_viewer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151b20")
	style.border_color = Color("#74604a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_viewer_panel.add_theme_stylebox_override("panel", style)
	_viewer.add_child(_viewer_panel)
	_viewer_title = Label.new()
	_viewer_title.position = Vector2(16, 9)
	_viewer_title.add_theme_font_override("font", title.get_theme_font("font"))
	_viewer_title.add_theme_font_size_override("font_size", 20)
	_viewer_title.add_theme_color_override("font_color", Color("#f5b844"))
	_viewer_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_viewer_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewer_panel.add_child(_viewer_title)
	_close_button = Button.new()
	_close_button.name = "CloseDemo"
	_close_button.text = "FERMER ×"
	_close_button.size = Vector2(112, 30)
	_close_button.add_theme_font_override("font", title.get_theme_font("font"))
	_close_button.add_theme_font_size_override("font_size", 14)
	_close_button.pressed.connect(close_enlarged)
	_viewer_panel.add_child(_close_button)
	_viewer.hide()
	# Keep the player in one canvas throughout playback: reparenting stops its decoder.
	video.reparent(_video_layer, false)
	_layout_video()
	get_viewport().size_changed.connect(_layout_viewer)


func _layout_viewer() -> void:
	if not _viewer.visible:
		return
	if is_instance_valid(thumbnail_overlay):
		thumbnail_overlay.hide()
	var viewport_size := get_viewport_rect().size
	var available := viewport_size - Vector2(88, 120)
	var ratio := minf(available.x / 16.0, available.y / 9.0)
	var video_size := Vector2(16, 9) * maxf(ratio, 1.0)
	_viewer_panel.size = video_size + Vector2(24, 56)
	_viewer_panel.position = (viewport_size - _viewer_panel.size) * 0.5
	_viewer_title.size = Vector2(_viewer_panel.size.x - 160, 26)
	_close_button.position = Vector2(_viewer_panel.size.x - 128, 8)
	video.position = _viewer_panel.position + Vector2(12, 44)
	video.size = video_size


func _layout_video() -> void:
	var transform := get_global_transform()
	video.position = transform * thumbnail_rect.position
	video.size = thumbnail_rect.size * transform.get_scale()
	if is_instance_valid(thumbnail_overlay):
		thumbnail_overlay.show()
		thumbnail_overlay.scale = transform.get_scale()
		thumbnail_overlay.position = (video.size - thumbnail_overlay.size * thumbnail_overlay.scale) * 0.5
