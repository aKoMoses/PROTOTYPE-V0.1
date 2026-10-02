extends SceneTree
## A native renderer close-up of real authored neon and service equipment.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(2)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for index in 8:
		await process_frame
	var flow: Node = scene.get("game_flow")
	scene.call("set_menu_showcase_enabled", false)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	scene.set_meta("camera_shake_enabled", false)
	var ambience := scene.find_child("WorkshopAmbience", true, false)
	var circuits: Array = ambience.get("_circuits")
	var candidates := circuits.filter(func(entry: Dictionary) -> bool: return entry.neon and int(entry.mode) in [0, 3])
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at.length_squared() < b.at.length_squared())
	var circuit: Dictionary = candidates[0] if not candidates.is_empty() else circuits.filter(func(entry: Dictionary) -> bool: return entry.neon)[0]
	var player: Node3D = scene.get("player")
	player.set_physics_process(false)
	player.global_position = circuit.at + circuit.out * 3.1 + circuit.axis * 2.6
	player.global_position.y = 0.0
	player.call("set_gameplay_enabled", true)
	player.get_node("WorldUIAnchor").hide()
	var target: Node3D = scene.get("target")
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.global_position = Vector3(20, 0, 20)
	var rig := scene.get_node("CameraRig") as Node3D
	rig.set_process(false)
	rig.global_position = player.global_position
	var camera := scene.get_viewport().get_camera_3d()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	camera.global_position = circuit.at + circuit.out * 7.0 + Vector3.UP * 5.0 + circuit.axis * 2.0
	camera.look_at(circuit.at + Vector3.DOWN * 0.5)
	# Skip ahead to a real scheduled ignition; production circuit settings stay intact.
	ambience.set("_clock", float(circuit.period) * 2.0 - float(circuit.phase) + 0.7)
	for index in 12:
		await process_frame
	print("WORKSHOP CAPTURE START: ", JSON.stringify({"circuit": circuit.id, "at": circuit.at, "mode": circuit.mode, "clock": ambience.get("_clock"), "state": ambience.get("_values")[int(circuit.id)]}))
	for index in 180:
		if index == 95:
			camera.size = 6.6
			camera.look_at(circuit.at + Vector3.DOWN * 0.65)
		player.call("_update_world_ui_anchor")
		flow.call("_update_hud")
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % index))
		if error != OK:
			quit(2)
			return
	print("WORKSHOP CAPTURE: ", JSON.stringify({"frames": 180, "renderer": RenderingServer.get_current_rendering_driver_name(), "circuit": circuit.id, "counts": ambience.call("get_debug_counts")}))
	scene.get_node("VFXManager").call("clear")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0)
