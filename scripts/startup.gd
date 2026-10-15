extends CanvasLayer
## Lightweight startup scene: main.tscn and its dependencies load in the background.
## No preload of gameplay here, so the first animated frame can appear immediately.

const ART: Texture2D = preload("res://art/branding/startup-hangar.png")
const FONT: Font = preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const GLOW: Shader = preload("res://scripts/startup.gdshader")
const MINIMUM_PRESENTATION := 1.1

@export_file("*.tscn") var next_scene_path := "res://scenes/main.tscn"
var presentation_only := false
var loading_message := "Ouverture du garage…"
var minimum_presentation := MINIMUM_PRESENTATION
var origin_scene: Node
var origin_process_mode := Node.PROCESS_MODE_INHERIT
var origin_tree_paused := false
var progress := 0.0
var elapsed := 0.0
var loading_failed := false
var _requested := false
var _installing := false
var _preview := false
var _loaded_scene: PackedScene
var _screen: Control
var _art: TextureRect
var _material: ShaderMaterial
var _content: Control
var _title: Label
var _zero: Label
var _status: Label
var _percent: Label
var _bar: ProgressBar
var _retry: Button
var _back: Button
var _sweep: ColorRect
var _finishing := false
var _sparks: ForgeSparks

class ForgeSparks extends Control:
	var clock := 0.0
	var indicator := Vector2.ZERO
	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()
	func _draw() -> void:
		for index in range(28):
			var seed_value := float(index)
			var travel := fposmod(clock * (0.045 + fposmod(seed_value * 0.013, 0.04)) + seed_value * 0.137, 1.0)
			var x := size.x * (0.40 + fposmod(seed_value * 0.173, 0.58)) + sin(clock * 0.5 + seed_value) * 12.0
			var point := Vector2(x, size.y * (1.0 - travel))
			var alpha := sin(travel * PI) * (0.22 + fposmod(seed_value * 0.11, 0.38))
			draw_line(point, point + Vector2(1.5, 4.0), Color(1.0, 0.56, 0.21, alpha), 1.4, true)
		var angle := clock * 2.0
		draw_arc(indicator, 9.0, angle, angle + PI * 1.4, 24, Color("5ce2eb"), 2.0, true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preview = OS.get_cmdline_user_args().has("startup-preview")
	_build_screen()
	MenuTransition.register_overlay(self)
	if presentation_only:
		_percent.hide()
		_sweep.show()
	else:
		_begin_loading.call_deferred()

func _input(event: InputEvent) -> void:
	# Pointer events still reach Retry/Back through the opaque root Control.
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if loading_failed and event.is_action_pressed("ui_accept"):
			if _back.has_focus():
				cancel_loading()
			else:
				_begin_loading()
		get_viewport().set_input_as_handled()

func set_transition_message(value: String) -> void:
	loading_message = value
	_status.text = value

func complete_transition() -> void:
	if _finishing:
		return
	_finishing = true
	var remaining := maxf(0.0, 0.35 - elapsed)
	if remaining > 0.0:
		await get_tree().create_timer(remaining, true).timeout
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_screen, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	await tween.finished
	queue_free()

func cancel_loading() -> void:
	if is_instance_valid(origin_scene):
		origin_scene.process_mode = origin_process_mode
		get_tree().paused = origin_tree_paused
	queue_free()

func _build_screen() -> void:
	_screen = Control.new()
	_screen.name = "LoadingScreen"
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen)
	var back := ColorRect.new()
	back.color = Color("10151e")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(back)
	_art = TextureRect.new()
	_art.texture = ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = GLOW
	_art.material = _material
	_screen.add_child(_art)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.045, 0.15)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(shade)
	_sparks = ForgeSparks.new()
	_sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sparks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_sparks)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_content)
	_title = _label("PROTOTYPE", 48, Color("f4ead4"))
	_zero = _label("0", 136, Color("f9b64b"))
	_status = _label(loading_message, 18, Color("ede4d0"))
	_percent = _label("0 %", 18, Color("65dce4"))
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.15, 0.20, 0.23, 0.85)
	track.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("63dce5")
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	_content.add_child(_bar)
	_sweep = ColorRect.new()
	_sweep.color = Color("63dce5")
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.hide()
	_bar.add_child(_sweep)
	var tip := _label("Chaque module ouvre une nouvelle façon de combattre.", 14, Color("a6b1b9"))
	tip.name = "Tip"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_retry = Button.new()
	_retry.text = "Réessayer"
	_retry.add_theme_font_override("font", FONT)
	_retry.pressed.connect(_begin_loading)
	_retry.hide()
	_content.add_child(_retry)
	_back = Button.new()
	_back.text = "Retour"
	_back.add_theme_font_override("font", FONT)
	_back.pressed.connect(cancel_loading)
	_back.hide()
	_content.add_child(_back)
	_screen.resized.connect(_layout)
	_layout()

func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(label)
	return label

func _layout() -> void:
	var viewport_size := _screen.size
	var ui_scale := clampf(viewport_size.y / 720.0, 0.65, 1.6)
	var narrow := viewport_size.x / maxf(viewport_size.y, 1.0) < 1.35
	var width := minf(viewport_size.x * (0.83 if narrow else 0.39), 530.0 * ui_scale)
	_content.position = Vector2(viewport_size.x * 0.065, viewport_size.y * (0.30 if narrow else 0.23))
	_content.size = Vector2(width, 460.0 * ui_scale)
	_title.position = Vector2.ZERO
	_title.size = Vector2(width, 66.0 * ui_scale)
	_title.add_theme_font_size_override("font_size", int(minf(48.0 * ui_scale, width / 6.6)))
	_zero.position = Vector2(-4.0, 50.0 * ui_scale)
	_zero.size = Vector2(width, 166.0 * ui_scale)
	_zero.add_theme_font_size_override("font_size", int(136.0 * ui_scale))
	_status.position = Vector2(28.0 * ui_scale, 258.0 * ui_scale)
	_status.size = Vector2(width - 106.0 * ui_scale, 35.0 * ui_scale)
	_status.add_theme_font_size_override("font_size", int(18.0 * ui_scale))
	_percent.position = Vector2(width - 78.0 * ui_scale, 258.0 * ui_scale)
	_percent.size = Vector2(78.0 * ui_scale, 35.0 * ui_scale)
	_percent.add_theme_font_size_override("font_size", int(18.0 * ui_scale))
	_bar.position = Vector2(0, 302.0 * ui_scale)
	_bar.size = Vector2(width, 5.0 * ui_scale)
	var tip := _content.get_node("Tip") as Label
	tip.position = Vector2(0, 326.0 * ui_scale)
	tip.size = Vector2(width, 62.0 * ui_scale)
	tip.add_theme_font_size_override("font_size", int(14.0 * ui_scale))
	_retry.position = Vector2(0, 392.0 * ui_scale)
	_retry.size = Vector2(170.0 * ui_scale, 44.0 * ui_scale)
	_back.position = Vector2(182.0 * ui_scale, 392.0 * ui_scale)
	_back.size = Vector2(140.0 * ui_scale, 44.0 * ui_scale)
	_sweep.size = Vector2(width * 0.22, 5.0 * ui_scale)
	_sparks.indicator = _content.position + Vector2(10.0 * ui_scale, 275.0 * ui_scale)
	_art.position = Vector2.ZERO
	_art.size = viewport_size
	_art.pivot_offset = viewport_size * Vector2(0.73, 0.36)
	_art.modulate.a = 0.55 if narrow else 1.0

func _begin_loading() -> void:
	loading_failed = false
	_requested = false
	_installing = false
	_loaded_scene = null
	progress = 0.0
	elapsed = 0.0
	_retry.hide()
	_back.hide()
	_status.text = loading_message
	# Let the first complete screen reach the display before starting disk work.
	await get_tree().process_frame
	await get_tree().process_frame
	if _preview:
		return
	if not ResourceLoader.exists(next_scene_path):
		_fail_loading()
		return
	var error := ResourceLoader.load_threaded_request(next_scene_path, "PackedScene", false)
	if error != OK:
		_fail_loading()
		return
	_requested = true

func _process(delta: float) -> void:
	elapsed += delta
	_material.set_shader_parameter("clock", elapsed)
	_art.scale = Vector2.ONE * (1.0 + 0.009 * (0.5 + 0.5 * sin(elapsed * 0.5)))
	if presentation_only:
		_sweep.position.x = (0.5 + 0.5 * sin(elapsed * 5.0 - PI * 0.5)) * (_bar.size.x - _sweep.size.x)
		return
	if _requested and not _installing and not loading_failed:
		var reported: Array = []
		var state := ResourceLoader.load_threaded_get_status(next_scene_path, reported)
		if state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail_loading()
		elif state == ResourceLoader.THREAD_LOAD_LOADED:
			_requested = false
			_loaded_scene = ResourceLoader.load_threaded_get(next_scene_path) as PackedScene
			if _loaded_scene == null:
				_fail_loading()
			else:
				progress = maxf(progress, 0.85)
		elif not reported.is_empty():
			progress = maxf(progress, clampf(float(reported[0]), 0.0, 1.0) * 0.85)
	if _loaded_scene != null and not _installing and not loading_failed and elapsed >= minimum_presentation:
		_installing = true
		_install_scene.call_deferred()
	_bar.value = move_toward(_bar.value, progress, delta * 1.8)
	_percent.text = "%d %%" % int(_bar.value * 100.0)

func _install_scene() -> void:
	_status.text = loading_message if is_instance_valid(origin_scene) else "Préparation de l’arène…"
	# Render the stage label before the synchronous node construction starts.
	await get_tree().process_frame
	await get_tree().process_frame
	var scene := _loaded_scene.instantiate()
	if scene == null:
		_fail_loading()
		return
	if is_instance_valid(origin_scene):
		# Release the old world only after the target resource has loaded successfully.
		get_tree().current_scene = null
		get_tree().root.remove_child(origin_scene)
		origin_scene.queue_free()
		origin_scene = null
	get_tree().root.add_child(scene)
	progress = 0.94
	# Main's _ready and the deferred scenery hooks run beneath our opaque overlay.
	for frame in range(8):
		await get_tree().process_frame
	get_tree().current_scene = scene
	get_tree().scene_changed.emit()
	progress = 1.0
	_bar.value = 1.0
	_percent.text = "100 %"
	_status.text = "Prêt."
	var tween := create_tween()
	tween.tween_interval(0.15)
	tween.tween_property(_screen, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	await tween.finished
	queue_free()

func _fail_loading() -> void:
	loading_failed = true
	_requested = false
	_installing = false
	_status.text = "Chargement interrompu."
	_retry.show()
	_back.visible = is_instance_valid(origin_scene)
	_retry.grab_focus()
	push_error("Startup: unable to load " + next_scene_path)
