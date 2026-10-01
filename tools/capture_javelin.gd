extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/javelin/" + path + ".png")


func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node3D = scene.get_node("Player")
	var target: Node3D = scene.get_node("TargetDummy")
	if not player.has_method("begin_touch_action") or not target.has_method("apply_javelin_mark"):
		push_error("Javelin capture blocked: combat actors could not compile")
		quit(1)
		return
	var flow: Node = scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	player.call("apply_loadout", {"weapon": "blaster", "offensive": "javelin", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0, 2)
	player.set("aim_direction", Vector3.FORWARD)
	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(0, 0, -3)
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
	scene.set_process(false)
	var controls: Node = scene.get_node("Interface/TouchControls")
	controls.visible = true
	var center: Vector2 = controls.call("_widget_center", "offensive_button")
	controls.call("_begin_touch", 90, center)
	player.call("_update_javelin_charge", 0.35)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/javelin"))
	await create_timer(0.10).timeout
	await _capture("charge_low")
	player.call("_update_javelin_charge", 1.39)
	await create_timer(0.10).timeout
	await _capture("charge_full")
	controls.call("_end_touch", 90)
	player.call("_update_javelin_charge", 0.0)
	var projectile: Node3D
	for node in get_nodes_in_group("prototype0_gameplay_projectiles"):
		if str(node.name).begins_with("JavelinProjectile"):
			projectile = node
	if projectile != null:
		projectile.set_physics_process(false)
		projectile.global_position = Vector3(0, 0.95, -0.2)
		await create_timer(0.06).timeout
		await _capture("flight")
		projectile.set_physics_process(true)
		for frame in range(40):
			await physics_frame
			if not is_instance_valid(projectile):
				break
		await _capture("impact")
		player.call("begin_touch_action", "offensive")
		await create_timer(0.06).timeout
		await _capture("recast")
	print("JAVELIN CAPTURE: PASS")
	quit()
