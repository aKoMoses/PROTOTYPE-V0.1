extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player")
	var target := scene.get_node("TargetDummy")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	player.position = Vector3(-3, 0, 17)
	target.position = Vector3(3, 0, 17)
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	camera.global_position = Vector3(0, 15, 31)
	camera.look_at(Vector3(0, 0.4, 17), Vector3.UP)
	await create_timer(0.5).timeout
	var directory := "res://captures/new-passives"
	if "touch_preview" in OS.get_cmdline_user_args():
		directory += "/mobile"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for id in ["auxiliary_reactor", "tracker", "alternator", "inertia"]:
		player.call("set_passive", id)
		var state = player.get("passive_state")
		match id:
			"auxiliary_reactor": state.reactor_remaining = 0.6
			"tracker":
				for shot in 3:
					state.weapon_hit(target, 10.0, state.emit_weapon(), 0.0)
			"alternator": state.alternator_remaining = 2.5
			"inertia": state.inertia_remaining = 2.0
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory + "/" + id + ".png") != OK:
			quit(1)
			return
	print("FOUR PASSIVE CAPTURE: PASS")
	quit(0)
