extends SceneTree
## Native renderer capture: local traversal, actual impact and rocket factory.
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
	var life := ambience.get_node("SceneryLife")
	var circuits: Array = ambience.get("_circuits")
	var candidates := circuits.filter(func(entry: Dictionary) -> bool: return entry.neon)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at.length_squared() < b.at.length_squared())
	var sign: Dictionary = candidates[0]
	var loose: Array = life.get("_loose")
	loose.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.origin as Vector3).distance_squared_to(sign.at) < (b.origin as Vector3).distance_squared_to(sign.at))
	var paper: Dictionary = loose.filter(func(entry: Dictionary) -> bool: return entry.kind == "paper")[0]
	var player: Node3D = scene.get("player")
	player.set_physics_process(false)
	player.global_position = paper.origin + sign.out * 1.2 - sign.axis * 1.0
	player.global_position.y = 0.0
	player.call("set_gameplay_enabled", true)
	player.get_node("WorldUIAnchor").hide()
	var target: Node3D = scene.get("target")
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.hide()
	var rig := scene.get_node("CameraRig") as Node3D
	rig.set_process(false)
	rig.global_position = paper.origin + sign.out * 1.0
	var camera := scene.get_viewport().get_camera_3d()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	camera.global_position = sign.at + sign.out * 7.0 + Vector3.UP * 4.6 + sign.axis * 1.6
	camera.look_at(sign.at + Vector3.DOWN * 0.85 + sign.out * 0.40)
	for index in 12:
		await process_frame
	# Start just ahead of an actual bird passage. No production periods change.
	life.set("_clock", float(life.get("_bird_period")) * 2.0 - float(life.get("_bird_phase")) + 0.65)
	var manager := scene.get_node("VFXManager")
	for index in 150:
		if index < 42:
			player.global_position += sign.axis * 0.035 - sign.out * 0.016
		elif index > 95 and index < 126:
			player.global_position += sign.out * 0.018
		if index == 50:
			manager.call("impact", sign.at + sign.out * 0.13, sign.out, "metal", 1.25)
		if index == 102:
			load("res://scripts/rocket_visual.gd").spawn_burst(scene, paper.at + Vector3.UP * 0.3, Vector3.UP)
		player.call("_update_world_ui_anchor")
		flow.call("_update_hud")
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % index))
		if error != OK:
			quit(2)
			return
	print("SCENERY LIFE CAPTURE: ", JSON.stringify({"frames": 150, "renderer": RenderingServer.get_current_rendering_driver_name(), "counts": life.call("get_debug_counts")}))
	manager.call("clear")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0)
