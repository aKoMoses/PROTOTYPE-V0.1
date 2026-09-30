extends SceneTree

## Replays exactly the same 60 Hz orbit around the shipped NorthWestBlock.
## Saves actual viewport frames; no image compositing changes the fog rendering.
## Usage: --script res://tools/capture_fog_motion.gd -- after overview 360
## "before" loads the locally preserved previous fog renderer for comparison.
const FIXED_DELTA := 1.0 / 60.0
const ORBIT_CENTER := Vector3(-17.5, 0.0, -15.0)
const VIEW_CENTER := Vector3(-16.0, 0.0, -13.0)
const BASELINE_PATH := "res://.godot/fog_organic_baseline/fog_of_war.gd"

var _version := "after"
var _view := "overview"
var _frame_count := 360
var _stride := 2
var _output_dir := ""


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 0:
		_version = arguments[0]
	if arguments.size() > 1:
		_view = arguments[1]
	if arguments.size() > 2:
		_frame_count = maxi(1, int(arguments[2]))
	if arguments.size() > 3:
		_stride = maxi(1, int(arguments[3]))
	_output_dir = "res://captures/fog_organic/%s_%s" % [_version, _view]
	DirAccess.make_dir_recursive_absolute(_output_dir)
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
	scene.set_meta("camera_shake_enabled", false)
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	var tracker := scene.get_node("SightTracker")
	tracker.set_process(false)
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.set_process(false)
	target.call("set_training_bot_enabled", false)
	target.call("reset_combat_state")
	target.set_physics_process(false)
	target.set_process(false)
	target.get_node("VisibilityEcho").set_process(false)
	target.global_position = Vector3(-17.5, 0.0, -9.8)
	var rig := scene.get_node("CameraRig") as Node3D
	rig.set_process(false)
	var camera := rig.get_node("Camera3D") as Camera3D
	var fog := scene.get_node("FogOfWar") as Node3D
	if _version == "before":
		if not ResourceLoader.exists(BASELINE_PATH):
			push_error("Missing preserved before renderer: %s" % BASELINE_PATH)
			quit(1)
			return
		fog.call("set_enabled", false)
		fog.queue_free()
		await process_frame
		fog = load(BASELINE_PATH).new() as Node3D
		fog.name = "FogOfWar"
		scene.add_child(fog)
		fog.call("configure", player, camera)
	fog.set_process(false)
	fog.set_physics_process(false)
	player.global_position = _route_position(0)
	player.set("aim_direction", Vector3.FORWARD)
	if _view == "follow":
		rig.call("set_target", player)
	else:
		camera.global_position = VIEW_CENTER + Vector3(0.0, 34.0, 25.0)
		camera.fov = 42.0
		camera.look_at(VIEW_CENTER + Vector3.UP * 0.4, Vector3.UP)
	fog.call("set_enabled", true)
	fog.call("refresh_vision")
	await physics_frame
	# Settle the renderer at the route's first position before recording.
	for _warmup in range(24):
		fog.call("_physics_process", FIXED_DELTA)
		fog.call("_process", FIXED_DELTA)
		await process_frame
	var sample_costs := PackedFloat64Array()
	var sample_frames: Array[Dictionary] = []
	var saved_frames := 0
	var error := OK
	for frame_index in range(_frame_count):
		await physics_frame
		player.global_position = _route_position(frame_index)
		var next_position := _route_position(frame_index + 1)
		var aim := (next_position - player.global_position).normalized()
		player.set("aim_direction", aim)
		if _view == "follow":
			rig.call("_process", FIXED_DELTA)
		var start_usec := Time.get_ticks_usec()
		fog.call("_physics_process", FIXED_DELTA)
		fog.call("_process", FIXED_DELTA)
		sample_costs.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
		tracker.call("_process", FIXED_DELTA)
		target.call("_update_visibility_presentation", FIXED_DELTA)
		player.call("_update_world_ui_anchor")
		await process_frame
		await RenderingServer.frame_post_draw
		if frame_index % _stride == 0:
			var capture := root.get_texture().get_image()
			var frame_path := "%s/motion_%04d.png" % [_output_dir, saved_frames]
			error = capture.save_png(frame_path)
			if error != OK:
				push_error("Could not save %s: %s" % [frame_path, error_string(error)])
				break
			saved_frames += 1
			if frame_index in [0, 90, 180, 270]:
				capture.save_png("%s/snapshot_%04d.png" % [_output_dir, frame_index])
				sample_frames.append({"frame": frame_index, "position": _vector_array(player.global_position), "fog": fog.call("get_debug_snapshot")})
		if frame_index % 90 == 0:
			print("FOG MOTION: %s %s frame=%d/%d position=%s" % [_version, _view, frame_index, _frame_count, player.global_position])
	sample_costs.sort()
	var total_cost := 0.0
	for cost in sample_costs:
		total_cost += cost
	var count := maxi(1, sample_costs.size())
	var metrics := {
		"version": _version,
		"view": _view,
		"fixed_dt": FIXED_DELTA,
		"simulation_hz": 60,
		"frame_count": _frame_count,
		"saved_frames": saved_frames,
		"frame_stride": _stride,
		"clip_fps": 60.0 / float(_stride),
		"orbit_center": _vector_array(ORBIT_CENTER),
		"orbit_radii": [6.0, 4.5],
		"route": "clockwise ellipse around actual arena NorthWestBlock; 6 seconds per revolution",
		"fog_cpu_mean_ms": total_cost / float(count),
		"fog_cpu_p95_ms": sample_costs[mini(count - 1, int(float(count - 1) * 0.95))],
		"fog_cpu_max_ms": sample_costs[count - 1],
		"snapshots": sample_frames,
		"final_fog": fog.call("get_debug_snapshot"),
	}
	var metrics_file := FileAccess.open("%s/metrics.json" % _output_dir, FileAccess.WRITE)
	if metrics_file != null:
		metrics_file.store_string(JSON.stringify(metrics, "\t"))
	print("FOG MOTION COMPLETE: %s frames=%d fog_mean_ms=%.4f fog_p95_ms=%.4f error=%d" % [_output_dir, saved_frames, metrics.fog_cpu_mean_ms, metrics.fog_cpu_p95_ms, error])
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


func _route_position(frame_index: int) -> Vector3:
	var angle := TAU * float(frame_index) * FIXED_DELTA / 6.0
	return ORBIT_CENTER + Vector3(cos(angle) * 6.0, 0.0, sin(angle) * 4.5)


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
