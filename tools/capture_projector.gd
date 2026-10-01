extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/projector"))
	root.get_texture().get_image().save_png("res://captures/projector/" + name + ".png")


func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	var build: Dictionary = flow.get("loadout").duplicate()
	build.defensive = "projector"
	flow.set("loadout", build)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	player.position = Vector3(-1.5, 0, 17)
	target.position = Vector3(1.5, 0, 17)
	player.set("aim_direction", Vector3.RIGHT)
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	camera.global_position = Vector3(0, 12, 32)
	camera.look_at(Vector3(0, 0.8, 17), Vector3.UP)
	await create_timer(0.5).timeout
	player.call("_perform_projector")
	await create_timer(0.08).timeout
	await _save("cast")
	player.call("_update_projector_cast", 0.18)
	target.call("_update_fulguro_projection", 0.1)
	await create_timer(0.1).timeout
	await _save("shockwave")
	print("PROJECTOR CAPTURE: PASS")
	quit(0)
