extends SceneTree

## Captures the shipped arena and HUD in a clear, real lane. The overview
## camera makes the complete radius transition visible in a single frame.
var _output_path := "res://captures/sight_range_full.png"
var _mode := "full"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_output_path = arguments[0]
	if arguments.size() > 1:
		_mode = arguments[1]
	if arguments.has("mobile"):
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	call_deferred("_capture")


func _capture() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	scene.call("set_bot_build_seed", 42)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	scene.set("_menu_showcase_active", false)
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	var tracker := scene.get_node("SightTracker")
	var fog := scene.get_node("FogOfWar")
	tracker.set_process(false)
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.set_process(false)
	target.call("set_training_bot_enabled", false)
	target.call("reset_combat_state")
	target.set_physics_process(false)
	target.set_process(false)
	var echo := target.get_node("VisibilityEcho")
	echo.set_process(false)
	player.global_position = Vector3(-23.0, 0.0, -23.0)
	player.set("aim_direction", Vector3.BACK)
	target.global_position = player.global_position + Vector3(0.0, 0.0, 14.0)
	await physics_frame
	tracker.call("reset_tracking")
	tracker.call("_process", 0.1)
	target.call("_update_visibility_presentation", 0.0)
	if _mode in ["halo", "fade"]:
		target.global_position = player.global_position + Vector3(0.0, 0.0, 18.0)
		target.call("_update_visibility_presentation", 0.0)
	elif _mode == "fringe":
		target.global_position = player.global_position + Vector3(0.0, 0.0, 21.0)
		target.call("_update_visibility_presentation", 0.0)
	elif _mode == "lost":
		target.global_position = player.global_position + Vector3(0.0, 0.0, 20.5)
		tracker.call("_process", 0.1)
		target.call("_update_visibility_presentation", 0.0)
		target.global_position = player.global_position + Vector3(0.0, 0.0, 24.0)
		target.call("_update_visibility_presentation", 0.016)
		echo.call("_process", 0.12)
	elif _mode == "wall_echo":
		# The shipped NorthWestBlock covers this destination; the frozen echo
		# remains in the clear lane where the opponent was actually observed.
		target.global_position = Vector3(-15.0, 0.0, -11.0)
		target.call("_update_visibility_presentation", 0.016)
		echo.call("_process", 0.12)
	tracker.call("_process", 0.12 if _mode in ["lost", "wall_echo"] else 0.1)
	player.call("_update_world_ui_anchor")
	flow.call("_update_hud")
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	var camera := rig.get_node("Camera3D") as Camera3D
	var center := Vector3(-14.0, 0.0, -12.0)
	camera.global_position = center + Vector3(0.0, 40.0, 30.0)
	camera.fov = 41.0
	camera.look_at(center + Vector3.UP * 0.4, Vector3.UP)
	fog.call("set_enabled", true)
	fog.call("refresh_vision")
	for _frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var error := capture.save_png(_output_path)
	print("SIGHT CAPTURE: mode=%s raw_weight=%.3f opacity=%.3f echo=%s state=%s path=%s error=%d" % [_mode, float(target.call("get_visibility_weight", player)), float(target.call("get_presentation_visibility_weight")), echo.call("get_debug_state"), tracker.call("get_tracking_state"), _output_path, error])
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if error == OK else 1)
