extends SceneTree

## Real gameplay-camera comparison of long identity, weapon state and statuses.
var _scene: Node3D
var _target: Node3D
var _readout: Node3D
var _directory := "res://captures/pass_complete/after/readout"
var _failures := 0


func _initialize() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Readout capture requires an actual graphics backend")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_directory = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var flow := _scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	_target = _scene.get_node("TargetDummy") as Node3D
	_target.call("set_training_bot_enabled", false)
	_target.position = Vector3(1.0, 0.0, -2.4)
	_target.set_process(false)
	_target.set_physics_process(false)
	_readout = _target.get_node("TargetHealthReadout")
	var player := _scene.get_node("Player") as Node3D
	player.position = Vector3(-1.7, 0.0, 0.8)
	player.set("aim_direction", Vector3.FORWARD)
	player.set_process(false)
	player.set_physics_process(false)
	_scene.set_meta("camera_shake_enabled", false)
	# Settle the same production camera follow code deterministically. Its lens,
	# offset, projection and gameplay geometry retain their authored values.
	var camera := root.get_viewport().get_camera_3d()
	var rig := camera.get_parent()
	rig.set_process(false)
	for _step in range(300):
		rig.call("_process", 1.0 / 60.0)
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		await process_frame
		_readout.call("update_actor_identity", Color("#ee6b4e"), "HARCELEUR · BLASTER")
		_readout.call("set_shotgun_ammo", false, 0, 3, false, 0.0)
		_readout.call("set_blaster_charge", true, true, 0.65)
		_readout.call("set_health", 1000.0, 1000.0)
		await _save("harceleur_%d" % dimensions.x)
		_readout.call("update_actor_identity", Color("#ee6b4e"), "ASSAILLANT · SHOTGUN")
		_readout.call("set_blaster_charge", false, false, 0.0)
		_readout.call("set_shotgun_ammo", true, 2, 3, false, 0.0)
		await _save("assaillant_%d" % dimensions.x)
		_readout.call("update_actor_identity", Color("#ee6b4e"), "HARCELEUR · BLASTER")
		_readout.call("set_shotgun_ammo", false, 0, 3, false, 0.0)
		_readout.call("set_blaster_charge", true, false, 0.0)
		_target.call("apply_burn", 20.0, 0.0, "readout_capture")
		_target.call("apply_slow", 20.0, 30.0, "readout_capture")
		_target.call("apply_stun", 20.0, "readout_capture")
		_target.call("apply_spotted", 20.0, "readout_capture")
		_target.call("_update_effect_presentation")
		var status := _target.get_node("StatusVFX")
		status.get("_rng").seed = 12345
		status.set_process(false)
		status.call("_process", 0.01)
		await _save("four_statuses_%d" % dimensions.x)
		_target.call("reset_combat_state")
		_target.call("_update_effect_presentation")
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
	print("READOUT CAPTURE: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(_directory.path_join(label + ".png"))
	if error != OK:
		_failures += 1
		push_error("Readout capture failed: " + error_string(error))
	# This native viewport detail preserves the original 300x108 UI pixels and
	# complements the gameplay shot without changing the gameplay camera.
	var viewport := _readout.get_node("HealthBarViewport") as SubViewport
	error = viewport.get_texture().get_image().save_png(_directory.path_join(label + "_detail.png"))
	if error != OK:
		_failures += 1
		push_error("Readout native detail failed: " + error_string(error))
	var identity := viewport.get_node("HealthBarUI/ActorName") as Label
	print("READOUT %s: text=%s bounds=%s native_size=%s" % [label, identity.text.replace("\n", "/"), identity.get_rect(), viewport.size])
