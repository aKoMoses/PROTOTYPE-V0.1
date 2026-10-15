extends SceneTree
## Reproducible art review; diagnostic cameras exist only in this capture.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	scene.call("set_bot_build_seed", 42)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	scene.set_process(false)
	scene.set("_menu_showcase_active", false)
	flow.set_process(false)
	for branch in ["Player", "TargetDummy", "CameraRig"]:
		_freeze(scene.get_node(branch))
	var player := scene.get_node("Player") as Node3D
	player.call("set_robot", "puissant")
	player.global_position = Vector3(0, 0, 2)
	var target := scene.get_node("TargetDummy") as Node3D
	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(3.5, 0, -2)
	for canvas in scene.find_children("*", "CanvasLayer", true, false):
		(canvas as CanvasLayer).visible = false
	for label in scene.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	for readout in scene.find_children("*HealthReadout", "Node3D", true, false):
		(readout as Node3D).visible = false
	for frame in 12:
		await process_frame
	var art := scene.get_node("ArenaPresentation/MainMapArt")
	if not bool(art.get("_initialized")):
		push_error("MAIN MAP ART CAPTURE: decoration did not initialize")
		quit(1)
		return
	var culling: Array = []
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		culling.append([mesh, mesh.visibility_range_end, mesh.visibility_range_end_margin])
		mesh.visibility_range_end = 0.0
		mesh.visibility_range_end_margin = 0.0
	var sun := scene.get_node("ArenaKeyLight") as DirectionalLight3D
	var shadow_distance := sun.directional_shadow_max_distance
	sun.directional_shadow_max_distance = 150.0
	var camera := Camera3D.new()
	camera.name = "DiagnosticArtCamera"
	scene.add_child(camera)
	camera.current = true
	var views := [
		["overview", Vector3(0, 76, 53), Vector3(0, 0, 5), 38.0],
		["electric", Vector3(15, 12, 5), Vector3(12, 0.9, -6.0), 42.0],
		["recovery", Vector3(-13, 11, 18), Vector3(-12, 0.9, 8.3), 43.0],
		["landmark", Vector3(27, 16, -4), Vector3(35.2, 4.3, -18), 52.0]
	]
	for view in views:
		camera.global_position = view[1]
		camera.fov = view[3]
		camera.look_at(view[2])
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var code := root.get_texture().get_image().save_png(args[0].path_join(view[0] + ".png"))
		if code != OK:
			push_error("MAIN MAP ART CAPTURE: failed to save " + view[0])
	# Also review the real gameplay camera, HUD, lamp and culling budgets.
	camera.queue_free()
	await process_frame
	for row in culling:
		row[0].visibility_range_end = row[1]
		row[0].visibility_range_end_margin = row[2]
	sun.directional_shadow_max_distance = shadow_distance
	player.global_position = Vector3(12.0, 0.0, -2.7)
	scene.call("reset_round_camera")
	(scene.get_node("CameraRig/Camera3D") as Camera3D).make_current()
	for canvas in scene.find_children("*", "CanvasLayer", true, false):
		(canvas as CanvasLayer).visible = true
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join("gameplay.png"))
	print("MAIN MAP ART CAPTURE: ", art.get_meta("art_counts"), " triangles=", art.get_meta("triangles"), " batches=", art.get_meta("batches"))
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	current_scene = null
	await process_frame
	quit()

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)
