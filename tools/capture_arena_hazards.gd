extends SceneTree


func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0] if args.size() > 0 else "user://arena-hazards.png"
	var mode := args[1] if args.size() > 1 else "warning"
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_select_arena", "hazards")
	if mode == "equipment":
		flow.call("_open_equipment")
	else:
		flow.call("_start_duel")
		flow.call("_begin_live_round")
		var player := scene.get_node("Player") as Node3D
		var bot := scene.get_node("TargetDummy") as Node3D
		player.set_physics_process(false)
		player.set_process(false)
		bot.call("set_training_bot_enabled", false)
		player.position = Vector3(-0.5, 0, 3)
		bot.position = Vector3(3.5, 0, 7)
		var hazards := scene.get_node("ArenaHazards")
		hazards.set_physics_process(false)
		hazards.set("_next_event_at", 100000.0)
		hazards.call("warn_fixture", 0)
		hazards.call("warn_fixture", 4)
		var rig := scene.get_node("CameraRig") as Node3D
		rig.call("set_target", player)
		if mode.begins_with("tile") or mode.begins_with("cannon"):
			flow.visible = false
			rig.set_process(false)
			rig.set_physics_process(false)
			var camera := rig.get_node("Camera3D") as Camera3D
			camera.fov = 38.0
			player.position = Vector3(0, 0, 20)
			bot.position = Vector3(0, 0, -20)
			player.visible = false
			bot.visible = false
			var at := Vector3(-3.5, 0.10, -1.0) if mode.begins_with("tile") else Vector3(-26.3, 0.90, -13.0)
			camera.global_position = at + (Vector3(4.0, 4.2, 4.7) if mode.begins_with("tile") else Vector3(4.0, 2.3, 3.2))
			camera.look_at(at)
		if mode.ends_with("animation"):
			await _capture_sequence(hazards, output)
			return
		if mode.contains("idle"):
			hazards.call("stop_round")
		elif mode.contains("active"):
			for frame in range(97):
				hazards.call("advance", 1.0 / 60.0)
		elif mode.contains("return"):
			for frame in range(156):
				hazards.call("advance", 1.0 / 60.0)
		else:
			hazards.call("advance", 1.05)
		for bolt in get_nodes_in_group("arena_hazard_bolts"):
			bolt.set_physics_process(false)
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output)
	print("ARENA HAZARDS CAPTURE: %s (%s)" % [output, result])
	quit(0 if result == OK else 1)


func _capture_sequence(hazards: Node3D, directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	hazards.call("reset_round")
	hazards.call("start_round")
	hazards.set("_next_event_at", 100000.0)
	for frame in range(80):
		if frame == 10:
			hazards.call("warn_fixture", 0)
			hazards.call("warn_fixture", 4)
		hazards.call("advance", 0.05)
		await create_timer(0.05).timeout
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(directory.path_join("frame-%03d.png" % frame))
		if result != OK:
			push_error("Could not save animation frame")
			quit(1)
			return
	print("ARENA HAZARDS ANIMATION CAPTURE: 80 rendered frames in " + directory)
	quit(0)
