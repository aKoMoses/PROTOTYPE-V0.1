extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0] if args.size() > 0 else "res://captures/training_ground.png"
	var show_menu := args.size() > 1 and args[1] == "menu"
	var overview := args.size() > 1 and args[1] == "overview"
	var section := args[1] if args.size() > 1 else ""
	var scene: Node = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	if section == "fixed":
		scene.get_node("Player").global_position = Vector3(-24.0, 0.0, -5.0)
	elif section == "shooter":
		scene.get_node("Player").global_position = Vector3(24.0, 0.0, -5.0)
	if section == "fixed" or section == "shooter":
		scene.get_node("CameraRig").call("set_target", scene.get_node("Player"))
	for _frame in range(20):
		await process_frame
	if show_menu:
		scene.call("_toggle_menu")
		for _frame in range(3):
			await process_frame
	if overview:
		scene.get_node("TrainingUI").visible = false
		var rig: Node3D = scene.get_node("CameraRig")
		rig.set_process(false)
		rig.global_position = Vector3.ZERO
		var camera: Camera3D = rig.get_node("Camera3D")
		camera.position = Vector3(0.0, 82.0, 48.0)
		camera.fov = 48.0
		camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
		for _frame in range(3):
			await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(output)
	paused = false
	if error != OK:
		push_error("Capture impossible: %s" % error)
		quit(1)
	else:
		print("TRAINING CAPTURE: ", output)
		quit(0)
