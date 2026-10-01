extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player")
	var enemy := scene.get_node("TargetDummy")
	enemy.call("set_training_bot_enabled", false)
	player.global_position = Vector3(0, 0, 2)
	enemy.global_position = Vector3(0, 0, -3)
	player.set("aim_direction", Vector3.FORWARD)
	player.call("set_touch_aim_vector", Vector2(0, -1))
	scene.get_node("CameraRig").set_process(false)
	scene.get_node("CameraRig").set_physics_process(false)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.0
	camera.global_position = Vector3(4.2, 6.0, 7.5)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.make_current()
	scene.get_node("FogOfWar").call("set_enabled", false)
	player.call("_perform_magnetic_field")
	await create_timer(0.6).timeout
	var wall: Node3D = player.get("_magnetic_wall")
	if not is_instance_valid(wall):
		push_error("Wall capture: deployment failed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/wall"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/wall/deployed.png")
	wall.call("projectile_impact", wall.to_global(Vector3(0.35, 1.2, -0.07)))
	await create_timer(0.08).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/wall/impact.png")
	print("WALL CAPTURE: PASS")
	quit()
