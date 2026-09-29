extends SceneTree

## Deterministic before/after graphics proof using the unchanged gameplay camera.
var _scene: Node3D
var _directory := "res://captures/pass_complete/after/stun"


func _initialize() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("STUN capture requires an actual graphics backend")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_directory = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var flow := _scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var target := _scene.get_node("TargetDummy") as Node3D
	target.call("set_training_bot_enabled", false)
	target.position = Vector3(1.0, 0.0, -2.4)
	var player := _scene.get_node("Player") as Node3D
	player.position = Vector3(-1.7, 0.0, 0.8)
	await create_timer(0.5).timeout
	player.set_process(false)
	player.set_physics_process(false)
	target.set_process(false)
	target.set_physics_process(false)
	var status := target.get_node("StatusVFX")
	status.get("_rng").seed = 12345
	status.call("sync", ["STUN"])
	status.set_process(false)
	status.call("_process", 0.01)
	await _save("01_pulse")
	status.call("_process", 0.12)
	await _save("02_quiet_gap")
	status.call("_process", 0.25)
	await _save("03_next_pulse")
	status.call("clear")
	await _save("04_cleared")
	_scene.call("clear_transient_fx")
	var sfx := root.get_node("GameSfx")
	if sfx.has_method("clear"):
		sfx.call("clear")
	else:
		for sound in sfx.get_children():
			(sound as AudioStreamPlayer).stop()
	_scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.10).timeout
	quit()


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(_directory.path_join(label + ".png"))
	print("STUN CAPTURE %s: %s" % [label, error_string(error)])
	# Supplement the unchanged gameplay view with an explicitly named close-up
	# so sub-second arc gaps are inspectable at native resolution.
	var camera := root.get_viewport().get_camera_3d()
	var original_transform := camera.global_transform
	var original_fov := camera.fov
	var target := _scene.get_node("TargetDummy") as Node3D
	camera.global_position = target.global_position + Vector3(2.6, 1.9, -3.6)
	camera.look_at(target.global_position + Vector3.UP * 1.0)
	camera.fov = 38.0
	await RenderingServer.frame_post_draw
	image = root.get_texture().get_image()
	error = image.save_png(_directory.path_join(label + "_detail.png"))
	print("STUN DETAIL %s: %s" % [label, error_string(error)])
	camera.global_transform = original_transform
	camera.fov = original_fov
