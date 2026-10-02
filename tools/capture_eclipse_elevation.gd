extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("set_menu_showcase_enabled", false)
	scene.call("set_arena_variant", "test")
	scene.get("game_flow").set_process(false)
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	var player: CharacterBody3D = scene.get("player")
	player.call("apply_loadout", {"mobility": "eclipse"})
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.position = Vector3(0, 0, -5)
	scene.get("target").call("set_training_bot_enabled", false)
	scene.get("target").position = Vector3(-10, 0, -10)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 25, 23)
	camera.fov = 42
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true
	await physics_frame
	player.call("begin_touch_action", "mobility")
	player.call("set_eclipse_touch_vector", Vector2(3.5, 5.6) / 12.0)
	for frame in range(25):
		await process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	var code := root.get_texture().get_image().save_png(args[0])
	quit(0 if code == OK else 1)
