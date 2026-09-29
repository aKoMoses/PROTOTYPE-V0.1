extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
var _output_directory := "res://captures"
var _players: Array[Node3D] = []
var _camera: Camera3D
var _labels: Array[Label] = []


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_directory))
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("set_menu_showcase_enabled", false)
	scene.get_node("Interface").hide()
	var touch_controls: Control = scene.get("touch_controls")
	if touch_controls != null:
		touch_controls.hide()
	var target := scene.get_node("TargetDummy") as Node3D
	target.call("set_training_bot_enabled", false)
	target.hide()
	# Clear only the foreground occluders for this comparison, in the real arena.
	for name in ["NorthCenterCover", "BushNorthCenter"]:
		var occluder := scene.get_node_or_null(name) as Node3D
		if occluder != null:
			occluder.hide()
	var identifiers := ["agile", "polyvalent", "puissant"]
	for index in range(3):
		var player: Node3D = scene.get_node("Player") if index == 0 else PLAYER.new()
		if index > 0:
			player.name = "ChassisPreview" + str(index)
			scene.add_child(player)
		player.call("set_gameplay_enabled", false)
		player.call("set_robot", identifiers[index])
		player.position = Vector3((1 - index) * 2.1, 0.0, 0.0)
		player.get_node("WorldUIAnchor").hide()
		_players.append(player)
	for audio in scene.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.8
	scene.add_child(_camera)
	_camera.position = Vector3(0.0, 2.8, -10.0)
	_camera.look_at(Vector3(0.0, 0.85, 0.0))
	_camera.make_current()
	var overlay := CanvasLayer.new()
	scene.add_child(overlay)
	for text in ["AGILE · 95 %", "POLYVALENT · 100 %", "PUISSANT · 105 %"]:
		var label := Label.new()
		label.text = text
		label.size = Vector2(380, 50)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color("#f3ddbb"))
		label.add_theme_color_override("font_outline_color", Color("#161b20"))
		label.add_theme_constant_override("outline_size", 8)
		overlay.add_child(label)
		_labels.append(label)
	await _capture("front")
	for player in _players:
		(player.get_node("VisualRoot") as Node3D).rotation.y = PI
	await _capture("back")
	scene.queue_free()
	for frame in range(3):
		await process_frame
	quit()


func _capture(view_name: String) -> void:
	for index in range(_players.size()):
		var feet := _camera.unproject_position(_players[index].position + Vector3(0, -0.25, 0))
		_labels[index].position = feet - Vector2(190, 0)
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := _output_directory.path_join("chassis_variants_%s.png" % view_name)
	var error := root.get_texture().get_image().save_png(path)
	print("CHASSIS CAPTURE: ", path, " code=", error)
