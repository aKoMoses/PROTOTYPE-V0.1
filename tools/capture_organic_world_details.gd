extends SceneTree
## Native Mobile-renderer sequence through authored grass and real weapon VFX.
var scene: Node3D
var player: Node3D
var output := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(2)
		return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var flow: Node = scene.get("game_flow")
	scene.call("set_menu_showcase_enabled", false)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	scene.set_meta("camera_shake_enabled", false)
	player = scene.get("player")
	player.set_physics_process(false)
	player.call("set_gameplay_enabled", true)
	var target: Node3D = scene.get("target")
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.global_position = Vector3(4, 0, -5)
	var bush := scene.get_node("BushNorthCenter") as Node3D
	var centre: Vector3 = bush.get_meta("bush_center")
	player.global_position = centre + Vector3(0, 0, 2.4)
	player.set("aim_direction", Vector3.FORWARD)
	player.call("set_weapon", "shotgun")
	player.call("_begin_weapon_aim")
	var camera := scene.get_node("CameraRig")
	camera.call("set_target", player)
	camera.call("set_follow_offset", Vector3.ZERO, true)
	for index in 35:
		await process_frame
	var vfx := scene.get_node("VFXManager")
	var rig := player.get("_visual_rig") as Node3D
	for index in 110:
		if index < 25:
			player.global_position.z -= 0.065
		elif index >= 35 and index < 58:
			player.global_position.z += 0.055
		if index in [6, 66]:
			rig.call("commit_firing_pose", Vector3.FORWARD)
			vfx.call("muzzle", rig.call("get_weapon_muzzle", "shotgun"), "shotgun", 0.0)
			vfx.call("impact", centre + Vector3(1.2, 0.45, 0.0), Vector3.BACK, "metal", 1.1)
		if index == 82:
			load("res://scripts/rocket_visual.gd").spawn_burst(scene, centre + Vector3(1.4, 0.35, 0.9), Vector3.FORWARD)
		player.call("_update_world_ui_anchor")
		flow.call("_update_hud")
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % index))
		if error != OK:
			quit(2)
			return
	var counts: Dictionary = scene.get_node("OrganicWorldDetails").call("get_debug_counts")
	print("ORGANIC CAPTURE: ", JSON.stringify({"frames": 110, "renderer": RenderingServer.get_current_rendering_driver_name(), "counts": counts}))
	vfx.call("clear")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0)
