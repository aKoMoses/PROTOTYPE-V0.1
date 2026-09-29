extends SceneTree
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_open_settings")
	await process_frame
	var comfort: Node = flow.get("_settings_panel").find_child("ComfortSettings", true, false)
	for child in comfort.get_children():
		if child is Button and child.toggle_mode:
			child.set_pressed(true)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/comfort-settings.png")
	print("COMFORT CAPTURE: PASS")
	quit()
