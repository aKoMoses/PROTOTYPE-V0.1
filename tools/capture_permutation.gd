extends SceneTree

const MARK := preload("res://scripts/permutation.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	var loadout: Dictionary = flow.get("loadout").duplicate()
	loadout.mobility = "permutation"
	flow.set("loadout", loadout)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	player.position = Vector3(-5.0, 0.0, 17.0)
	target.position = Vector3(6.0, 0.0, 17.0)
	player.set("aim_direction", Vector3.RIGHT)
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	scene.get_node("CameraRig").set_process(false)
	scene.get_node("CameraRig").set_physics_process(false)
	camera.global_position = Vector3(0.5, 15.0, 31.0)
	camera.look_at(Vector3(0.5, 0.4, 17.0), Vector3.UP)
	await create_timer(0.6).timeout
	var mark := MARK.new()
	mark.configure(player, target, false)
	scene.add_child(mark)
	mark.set_physics_process(false)
	for _step in range(7): mark.call("_physics_process", 0.012)
	player.call("_start_module_cooldown", "permutation", 16.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://captures/permutation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var err := root.get_texture().get_image().save_png(directory + "/mark.png")
	if err != OK: quit(1); return
	mark.queue_free()
	await process_frame
	var origin := player.position
	var destination := target.position
	if not MARK.exchange(player, target): quit(1); return
	player.call("_on_permutation_arrived", origin, destination)
	MARK.pulse(scene, origin)
	MARK.pulse(scene, destination)
	await create_timer(0.08).timeout
	await RenderingServer.frame_post_draw
	err = root.get_texture().get_image().save_png(directory + "/arrival.png")
	print("PERMUTATION CAPTURE: ", "PASS" if err == OK else "FAIL")
	quit(0 if err == OK else 1)
