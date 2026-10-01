extends SceneTree
## Capture the actual weapon attachment at three stages; no gameplay tuning overrides.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Charge capture requires a graphics backend.")
		quit(1)
		return
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node3D = scene.get_node("Player")
	if not player.has_method("_update_blaster_charge_visual"):
		push_error("Charge capture blocked: Player did not compile.")
		quit(1)
		return
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.visible = false
	var target: Node3D = scene.get_node("TargetDummy")
	target.call("set_training_bot_enabled", false)
	target.position = Vector3(15, 0, -15)
	player.call("set_weapon", "blaster")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	player.set("aim_direction", Vector3.FORWARD)
	scene.get_node("FogOfWar").call("set_enabled", false)
	scene.get_node("CameraRig").set_process(false)
	scene.get_node("CameraRig").set_physics_process(false)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.8
	camera.global_position = Vector3(4.4, 4.2, -4.5)
	camera.look_at(Vector3(0, 1.0, -0.3))
	camera.make_current()
	player.call("_begin_blaster_charge")
	var rig: Node = player.get("_visual_rig")
	for frame in 90:
		rig.call("update_visual_state", Vector3.ZERO, Vector3.FORWARD, 0.0, 5.0, 1.0 / 60.0)
		await process_frame
	var directory := "res://captures/blaster-charge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for stage in [0.15, 0.60, 1.0]:
		player.set("_blaster_charge_ratio", stage)
		for frame in 24:
			player.call("_update_blaster_charge_visual", 1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join("charge_%03d.png" % roundi(stage * 100.0))
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Could not save charge capture.")
			quit(1)
			return
		print("BLASTER CHARGE CAPTURE: " + path)
	player.call("_cancel_blaster_charge")
	var visual: Node3D = player.get("_blaster_charge_visual")
	var light: OmniLight3D = player.get("_blaster_light")
	if visual.visible or light.light_energy > 0.0:
		push_error("Charge cancellation left the effect active.")
		quit(1)
		return
	print("BLASTER CHARGE CAPTURE: PASS")
	current_scene = null
	scene.queue_free()
	await process_frame
	quit(0)
