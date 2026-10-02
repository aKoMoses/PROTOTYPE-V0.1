extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/stasis"))
	root.get_texture().get_image().save_png("res://captures/stasis/" + label + ".png")


func run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	player.position = Vector3(-1.8, 0, 17)
	target.position = Vector3(1.8, 0, 17)
	player.call("_set_aim_direction", Vector3.RIGHT)
	player.set("_defensive_module_id", "static_shield")
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	camera.global_position = Vector3(0, 7, 24)
	camera.look_at(Vector3(0, 0.8, 17), Vector3.UP)
	await create_timer(0.5).timeout
	player.call("_perform_static_shield")
	await create_timer(0.22).timeout
	var suffix := "before" if "before" in OS.get_cmdline_user_args() else "after"
	await capture(suffix + "-detail")
	camera.position = Vector3(0, 20.5, 17.5)
	rig.global_position = player.global_position + Vector3.RIGHT * 1.6
	camera.look_at(rig.global_position + Vector3.UP * 0.45, Vector3.UP)
	await capture(suffix + "-gameplay")
	if suffix == "after":
		camera.global_position = Vector3(0, 7, 24)
		camera.look_at(Vector3(0, 0.8, 17), Vector3.UP)
		player.set("_stasis_remaining", 0.6)
		await capture("after-duration")
		# Bot uses the same effect and must release it when reset, even while disabled.
		var equipment := target.get_node("TrainingBot/DuelEquipment")
		equipment.call("_activate_static_shield", target)
		await create_timer(0.2).timeout
		await capture("after-bot")
		equipment.call("reset")
		await create_timer(0.25).timeout
		if target.get_node_or_null("StasisCocoon") != null:
			push_error("Stasis bot effect survived reset")
			quit(1)
			return
	player.set("_stasis_remaining", 0.0)
	if suffix == "after":
		await create_timer(0.08).timeout
		await capture("after-release")
	await create_timer(0.3).timeout
	if suffix == "after" and player.get("_stasis_visual") != null:
		push_error("Stasis effect survived protection expiry")
		quit(1)
		return
	player.call("reset_combat_state")
	print("STASIS CAPTURE: PASS")
	quit(0)
