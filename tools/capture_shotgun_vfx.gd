extends "res://scripts/main.gd"
## Runs the production shotgun and camera at 60 Hz, retaining a short shot sequence.
## Godot --path <project> res://tools/capture_shotgun_vfx.tscn -- OUTPUT_DIR

var _capture_output := "res://exports/shotgun-style/after"
var _capture_hits := 0
var _capture_frames := 0


func _ready() -> void:
	super()
	call_deferred("_capture_run")


func _capture_run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Shotgun capture requires a graphics backend.")
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_capture_output = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_capture_output))
	game_flow.call("_start_duel")
	game_flow.call("_begin_live_round")
	set_meta("camera_shake_enabled", false)
	touch_controls.set_process(false)
	touch_controls.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	# Aim across the screen: readable spread with no nearby occluding container.
	player.global_position = Vector3(-2.0, 0.0, 1.0)
	target.global_position = Vector3(2.0, 0.0, 0.0)
	player.call("set_weapon", "shotgun")
	var direction := (target.global_position - player.global_position).normalized()
	player.call("set_touch_aim_vector", Vector2(direction.x, direction.z))
	player.set("aim_direction", direction)
	get_node("CameraRig").call("set_follow_offset", Vector3.ZERO, true)
	await get_tree().create_timer(0.7).timeout
	player.call("set_touch_aim_vector", Vector2(direction.x, direction.z))
	var health_before := float(target.call("get_health"))
	player.call("_perform_shotgun_attack")
	for frame in range(48):
		await RenderingServer.frame_post_draw
		var frame_image := get_viewport().get_texture().get_image()
		if frame_image.save_png(_capture_output.path_join("frame_%03d.png" % frame)) == OK:
			_capture_frames += 1
		if float(target.call("get_health")) < health_before and _capture_hits == 0:
			_capture_hits = 1
			frame_image.save_png(_capture_output.path_join("impact.png"))
		if frame == 9:
			frame_image.save_png(_capture_output.path_join("shot.png"))
	var damage := health_before - float(target.call("get_health"))
	print("SHOTGUN STYLE CAPTURE: %s frames=%d damage=%.1f output=%s" % ["PASS" if _capture_frames == 48 and _capture_hits > 0 else "FAIL", _capture_frames, damage, ProjectSettings.globalize_path(_capture_output)])
	get_tree().quit(0 if _capture_frames == 48 and _capture_hits > 0 else 1)
