extends SceneTree

## Production camera visual/performance fixture. No camera projection or offsets
## are overridden. Positions and aim are fixed; HUD, visibility and actor rigs run.
## Usage: -- <output-directory> <prefix> [center|north|west|south|east|all]
## Optional: low, combat, mobile, baseline=<metrics.json>.
## Output includes PNGs and metrics; baseline verifies actual camera invariance.

const POSITIONS := {
	"center": Vector3(0.0, 0.0, 2.0),
	"north": Vector3(0.0, 0.0, -24.0),
	"west": Vector3(-24.0, 0.0, 0.0),
	"south": Vector3(0.0, 0.0, 24.0),
	"east": Vector3(24.0, 0.0, 0.0),
}
const SAMPLE_FRAMES := 60


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Use <output-directory> <prefix> [view|all] [low] [combat] [mobile]")
		quit(2)
		return
	var views: Array[String] = ["center", "north", "west", "south", "east"]
	if args.size() > 2 and args[2] != "all":
		views = [args[2]]
	for view in views:
		if not POSITIONS.has(view):
			push_error("Unknown capture view: %s" % view)
			quit(2)
			return
	if args.has("mobile"):
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
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
	scene.set_meta("camera_shake_enabled", false)
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.call("reset_combat_state")
	player.call("clear_touch_inputs")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.set_process(false)
	player.set("aim_direction", Vector3.FORWARD)
	target.call("set_training_bot_enabled", false)
	target.call("reset_combat_state")
	target.set_physics_process(false)
	target.set_process(false)
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	var camera := rig.get_node("Camera3D") as Camera3D
	var quality_applied := not args.has("low")
	if args.has("low"):
		var presentation := scene.get_node_or_null("ArenaPresentation")
		if presentation != null and presentation.has_method("set_quality"):
			presentation.call("set_quality", 0)
			quality_applied = true
		if not quality_applied:
			push_warning("No ArenaPresentation quality hook available; capture records quality_applied=false")
	var measure := RenderingServer.has_method("viewport_set_measure_render_time")
	if measure:
		RenderingServer.call("viewport_set_measure_render_time", root.get_viewport_rid(), true)
	var report := {
		"engine": Engine.get_version_info().string,
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"device": RenderingServer.get_video_adapter_name(),
		"viewport": [root.size.x, root.size.y],
		"capture_pixels": [root.get_texture().get_width(), root.get_texture().get_height()],
		"stretch_aspect": root.content_scale_aspect,
		"aspect_expand_fixture": args.has("mobile"),
		"quality": "low" if args.has("low") else "default",
		"quality_applied": quality_applied,
		"combat_effects": args.has("combat"),
		"camera_fixture": "production rig; fixed FORWARD aim; snap via set_follow_offset",
		"views": {},
	}
	var code := 0
	var baseline: Variant = null
	for arg in args:
		if arg.begins_with("baseline="):
			baseline = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("baseline=")))
			if not baseline is Dictionary:
				push_error("Missing/invalid capture baseline metrics")
				code = 1
	report["camera_fixture_match"] = null
	for view in views:
		player.global_position = POSITIONS[view]
		target.global_position = player.global_position + Vector3(3.5, 0.0, -4.0)
		if view == "north":
			target.global_position = player.global_position + Vector3(3.5, 0.0, 3.0)
		player.set("aim_direction", Vector3.FORWARD)
		rig.call("set_target", player)
		rig.call("set_follow_offset", Vector3.ZERO, true)
		await physics_frame
		var fog := scene.get_node_or_null("FogOfWar")
		if fog != null:
			fog.call("refresh_vision")
		var tracker := scene.get_node_or_null("SightTracker")
		if tracker != null:
			tracker.call("reset_tracking")
			tracker.call("_process", 0.1)
		target.call("_update_visibility_presentation", 0.0)
		player.call("_update_world_ui_anchor")
		flow.call("_update_hud")
		for _frame in range(30):
			await process_frame
		var totals := {"fps": 0.0, "process_ms": 0.0, "physics_ms": 0.0, "draw_calls": 0.0, "primitives": 0.0, "render_cpu_ms": 0.0, "render_gpu_ms": 0.0}
		for _frame in range(SAMPLE_FRAMES):
			await process_frame
			totals.fps += Performance.get_monitor(Performance.TIME_FPS)
			totals.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			totals.physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			totals.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			totals.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			if measure:
				totals.render_cpu_ms += float(RenderingServer.call("viewport_get_measured_render_time_cpu", root.get_viewport_rid()))
				totals.render_gpu_ms += float(RenderingServer.call("viewport_get_measured_render_time_gpu", root.get_viewport_rid()))
		for key in totals.keys():
			totals[key] /= SAMPLE_FRAMES
		if args.has("combat"):
			target.call("apply_spotted", 5.0, "arena_capture")
			target.call("apply_burn", 3.5, 20.0, "arena_capture")
			player.call("_fire_blaster_projectile", 50.0, 1.0, (target.global_position - player.global_position).normalized())
			for _frame in range(3):
				await process_frame
		await RenderingServer.frame_post_draw
		var path := args[0].path_join("%s-%s.png" % [args[1], view])
		var error := root.get_texture().get_image().save_png(path)
		if error != OK:
			code = 1
		report.views[view] = {"player_position": _vec(player.global_position), "target_position": _vec(target.global_position), "rig_position": _vec(rig.global_position), "camera_position": _vec(camera.global_position), "camera_rotation": _vec(camera.global_rotation), "camera_fov": camera.fov, "camera_projection": camera.projection, "capture_path": path, "capture_error": error, "average": totals, "samples": SAMPLE_FRAMES}
		if baseline is Dictionary and baseline.get("views", {}).has(view):
			var camera_match := true
			for key in ["player_position", "target_position", "rig_position", "camera_position", "camera_rotation", "camera_fov", "camera_projection"]:
				var expected: Variant = baseline.views[view].get(key)
				var actual: Variant = JSON.parse_string(JSON.stringify(report.views[view][key]))
				if JSON.stringify(expected) != JSON.stringify(actual):
					camera_match = false
					push_error("Capture fixture changed: %s %s" % [view, key])
			if JSON.stringify(baseline.get("viewport")) != JSON.stringify(JSON.parse_string(JSON.stringify(report.viewport))):
				camera_match = false
				push_error("Capture viewport changed")
			report.views[view]["camera_fixture_match"] = camera_match
			if not camera_match:
				code = 1
		print("ARENA ART CAPTURE: %s %s metrics=%s" % [view, path, JSON.stringify(totals)])
		if args.has("combat"):
			scene.call("clear_transient_fx")
			target.call("reset_combat_state")
	if baseline is Dictionary:
		report.camera_fixture_match = code == 0
	report["static_memory_mib"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var report_path := args[0].path_join("%s-metrics.json" % args[1])
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		code = 1
	else:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	scene.queue_free()
	current_scene = null
	await process_frame
	quit(code)


func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.00001), snappedf(value.y, 0.00001), snappedf(value.z, 0.00001)]
