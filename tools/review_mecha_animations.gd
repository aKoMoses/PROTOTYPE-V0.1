extends SceneTree

## Isolated raw-GLB reviewer. No combat model or import settings are changed.
## --script tools/review_mecha_animations.gd -- SOURCE.glb OUTPUT_DIR [--capture]
var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _names: Array[StringName]
var _hips := -1
var _time := 0.0
var _playing := true
var _in_place := true
var _speed := 1.0
var _clip := 0
var _timeline: HSlider
var _caption: Label
var _output := "res://outputs/mecha-animation-review"
var _capture_mode := false

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Supply source GLB, output directory and optional --capture")
		quit(1)
		return
	if args.size() > 1:
		_output = args[1]
	_capture_mode = "--capture" in args
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var error := doc.append_from_file(args[0], state)
	if error != OK:
		push_error(error_string(error))
		quit(1)
		return
	_model = doc.generate_scene(state)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	stage.add_child(_model)
	for node in _model.find_children("*", "AnimationPlayer", true, false):
		_player = node as AnimationPlayer
		break
	for node in _model.find_children("*", "Skeleton3D", true, false):
		_skeleton = node as Skeleton3D
		break
	if _player == null or _skeleton == null:
		push_error("Missing AnimationPlayer or Skeleton3D")
		quit(1)
		return
	for i in _skeleton.get_bone_count():
		if String(_skeleton.get_bone_name(i)).to_lower().ends_with("hips"):
			_hips = i
	_names.assign(_player.get_animation_list())
	_names.erase(&"RESET")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var bounds := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var b := mesh.global_transform * mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	var height := maxf(bounds.size.y, 0.5)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#202a36")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d4e2f1")
	env.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = height * 1.85
	stage.add_child(camera)
	var focus := bounds.get_center()
	camera.position = focus + Vector3(height * 1.3, height * 0.7, height * 2.7)
	camera.look_at(focus)
	camera.make_current()
	_select_clip(0)
	if _capture_mode:
		root.size = Vector2i(256, 256)
		await _capture()
	else:
		_build_ui()
		process_frame.connect(_tick)
	print("MECHA_REVIEW: bones=%d clips=%d" % [_skeleton.get_bone_count(), _names.size()])

func _select_clip(index: int) -> void:
	_clip = index
	_time = 0.0
	_player.stop()
	_player.play(_names[_clip])
	_sample()
	if _timeline != null:
		_timeline.max_value = _player.get_animation(_names[_clip]).length

func _sample() -> void:
	_player.seek(_time, true)
	if _in_place and _hips >= 0:
		var p := _skeleton.get_bone_pose_position(_hips)
		var rest := _skeleton.get_bone_rest(_hips).origin
		p.x = rest.x
		p.z = rest.z
		_skeleton.set_bone_pose_position(_hips, p)
	_skeleton.force_update_all_bone_transforms()
	_skeleton.advance(0.0)

func _tick() -> void:
	var duration := _player.get_animation(_names[_clip]).length
	if _playing:
		_time = fmod(_time + root.get_process_delta_time() * _speed, duration)
		_sample()
	_timeline.set_value_no_signal(_time)
	_caption.text = "%s · %.2f / %.2f s" % [_names[_clip], _time, duration]

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size.x = 340
	layer.add_child(panel)
	var picker := OptionButton.new()
	for clip_name in _names:
		picker.add_item(String(clip_name))
	picker.item_selected.connect(_select_clip)
	panel.add_child(picker)
	_caption = Label.new()
	panel.add_child(_caption)
	_timeline = HSlider.new()
	_timeline.max_value = _player.get_animation(_names[0]).length
	_timeline.step = 0.001
	_timeline.value_changed.connect(func(value: float): _time = value; _sample())
	panel.add_child(_timeline)
	var pause := CheckButton.new()
	pause.text = "Lecture"
	pause.button_pressed = true
	pause.toggled.connect(func(value: bool): _playing = value)
	panel.add_child(pause)
	var in_place := CheckButton.new()
	in_place.text = "Retirer le déplacement horizontal du bassin"
	in_place.button_pressed = true
	in_place.toggled.connect(func(value: bool): _in_place = value; _sample())
	panel.add_child(in_place)
	var slow := CheckButton.new()
	slow.text = "Ralenti × 0,25"
	slow.toggled.connect(func(value: bool): _speed = 0.25 if value else 1.0)
	panel.add_child(slow)

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	# Preserve raw source order so the JSON index and contact sheets agree.
	var raw_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_output.path_join("report.json")))
	var source_names: Array = raw_report.animations.map(func(item: Dictionary): return StringName(item.name))
	var report := {"clips": [], "bone_count": _skeleton.get_bone_count(), "capture_fractions": [0.05, 0.35, 0.65, 0.95]}
	var sheet: Image
	var sheet_index := 0
	var font := ThemeDB.fallback_font
	var label := Label.new()
	label.position = Vector2(10, 6)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 17)
	root.add_child(label)
	for i in source_names.size():
		if i % 6 == 0:
			sheet = Image.create(1024, 1536, false, Image.FORMAT_RGBA8)
			sheet.fill(Color("#202a36"))
			sheet_index += 1
		var clip_name: StringName = source_names[i]
		if not _names.has(clip_name):
			push_error("Clip missing after Godot import: " + String(clip_name))
			quit(1)
			return
		_select_clip(_names.find(clip_name))
		var animation := _player.get_animation(clip_name)
		report.clips.append({"name": String(clip_name), "duration": animation.length, "tracks": animation.get_track_count()})
		for column in 4:
			_time = animation.length * report.capture_fractions[column]
			_sample()
			label.text = "%s · %.2fs" % [clip_name, _time]
			await process_frame
			await RenderingServer.frame_post_draw
			var snapshot := root.get_texture().get_image()
			sheet.blit_rect(snapshot, Rect2i(0, 0, 256, 256), Vector2i(column * 256, (i % 6) * 256))
		if i % 6 == 5 or i == source_names.size() - 1:
			var result := sheet.save_png(_output.path_join("sheet-%02d.png" % sheet_index))
			if result != OK:
				push_error(error_string(result))
				quit(1)
				return
			print("MECHA_SHEET: %d/%d" % [i + 1, source_names.size()])
	var file := FileAccess.open(_output.path_join("godot-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MECHA_CAPTURE_OK: clips=%d sheets=%d" % [source_names.size(), sheet_index])
	quit()
