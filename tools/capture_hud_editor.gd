extends SceneTree

func _initialize() -> void:
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
	var path := "res://captures/hud_editor_preview.png"
	var image := root.get_viewport().get_texture().get_image()
	var status := image.save_png(path)
	print("HUD EDITOR CAPTURE: ", "PASS" if status == OK else "FAIL", " ", path)
	quit(0 if status == OK else 1)
