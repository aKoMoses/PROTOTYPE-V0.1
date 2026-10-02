extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("set_menu_showcase_enabled", false)
	var args := OS.get_cmdline_user_args()
	var flow: CanvasLayer = scene.get("game_flow")
	if args.size() > 1 and args[1] == "menu":
		flow.call("_open_equipment")
		flow.get("_forge_garage").call("_choose_arena", "test")
	elif args.size() > 1 and args[1] == "hud":
		flow.call("_select_arena", "test")
		flow.call("_start_duel")
		flow.call("_begin_live_round")
		flow.set_process(false)
		scene.get("player").set_physics_process(false)
		scene.get("target").call("set_training_bot_enabled", false)
		scene.get("player").position = Vector3(-3.5, 2.4, 1.4)
		scene.get("target").position = Vector3(3.5, 2.4, -1.0)
		scene.call("reset_round_camera")
	else:
		scene.call("set_arena_variant", "test")
		for kit in get_nodes_in_group("repair_kits"):
			kit.call("reset_for_round", true)
		for child in scene.get_children():
			if child is CanvasLayer:
				child.visible = false
		scene.get("player").call("set_gameplay_enabled", false)
		scene.get("player").position = Vector3(-3.5, 2.4, 1.4)
		scene.get("target").position = Vector3(3.5, 2.4, -1.0)
		var camera := Camera3D.new()
		camera.position = Vector3(0, 42, 35)
		if args.size() > 1 and args[1] == "bridge":
			camera.position = Vector3(13, 15, 16)
		camera.fov = 45
		scene.add_child(camera)
		camera.look_at(Vector3(0, 0, 0))
		camera.current = true
	for frame in range(35):
		await process_frame
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(args[0])
	quit(0 if code == OK else 1)
