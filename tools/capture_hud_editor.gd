extends SceneTree

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.has("logical_canvas"):
		# Stress the editor at the requested logical size without changing the
		# production stretch configuration or camera.
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_open_settings")
	flow.call("_open_hud_editor")
	var editor: Control = flow.get_node("HudEditor")
	editor.call("select", "move")
	for _frame in range(30):
		await process_frame
	var path := str(arguments[0]) if arguments.size() > 0 and str(arguments[0]).ends_with(".png") else "res://captures/hud_editor_preview.png"
	var image := root.get_viewport().get_texture().get_image()
	var status := image.save_png(path)
	print("HUD EDITOR CAPTURE: ", "PASS" if status == OK else "FAIL", " ", path)
	quit(0 if status == OK else 1)
