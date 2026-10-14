extends SceneTree
## Rendered duel ablations. Run in a disposable process with a real renderer.
## PC render timings do not predict Android FPS. The supplied --path selects
## the source version; this script can live outside that project.
const LOADOUT := preload("res://scripts/loadout_state.gd")
const SEED := 1731
const SAMPLE_SECONDS := 4.0
var scene: Node3D
var player: Node3D
var target: Node3D
var bot: Node
var clock := 0.0
var driving := false
var report: Dictionary = {"samples": []}
var output := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty():
		push_error("Use a real renderer and pass an absolute output JSON path after --.")
		quit(1)
		return
	output = OS.get_cmdline_user_args()[0]
	seed(SEED)
	scene = load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	bot = target.get("_training_bot")
	var flow: Node = scene.get_node("Interface")
	scene.call("set_bot_build_seed", 4242)
	flow.set("loadout", LOADOUT.defaults())
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	scene.get_node("VFXManager").call("_apply_device_budget", true)
	root.scaling_3d_scale = 0.75
	# Explicitly remove the project's cap only in this diagnostic process.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	physics_frame.connect(_drive)
	driving = true
	report.merge({"engine": Engine.get_version_info().string,
		"project_path": ProjectSettings.globalize_path("res://"), "user_data_path": OS.get_user_data_dir(),
		"gpu": RenderingServer.get_video_adapter_name(), "viewport": str(root.size),
		"renderer": RenderingServer.get_current_rendering_method(),
		"physics_hz": Engine.physics_ticks_per_second,
		"note": "Sequential rendered PC ablations, not smartphone FPS. Uncapped hidden window, 0.75 scale, mobile VFX/scenery budgets; .mobile project settings such as shadow atlas size are not emulated by the command-line flag. Wall intervals include presentation and OS waits. Engine monitors are slowly refreshed snapshots; GPU and render CPU are viewport measurements. Each case resets the same seeded build; removing the bot also removes its attacks. One second of warm-up does not guarantee every first-use effect has compiled. Baseline is repeated to expose drift. Inventory includes hidden previews and is not a count of rendered meshes. Primitives are vertices/indices across render passes, not a triangle count."})
	await create_timer(2.0).timeout
	report["mesh_inventory"] = _inventory()
	if OS.get_cmdline_user_args().has("compare-mobile-gpu"):
		var gpu_budget := root.get_node("MobileRenderBudget")
		# ABBA compares the production GPU profile with the same gameplay and
		# geometry. Keep captures for checking the quality trade-off.
		await _sample("gpu_baseline_A1")
		await _capture("gpu-baseline")
		gpu_budget.call("activate")
		await _sample("gpu_budget_B1", true, 0.5)
		await _capture("gpu-budget")
		await _sample("gpu_budget_B2", true, 0.5)
		gpu_budget.call("deactivate")
		await _sample("gpu_baseline_A2")
		_save_report()
		return
	await _sample("baseline")
	await _capture("baseline")
	await _sample("without_bot", false)
	await _sample("resolution_050", true, 0.5)
	var shadow_lights: Array[Light3D] = []
	for light: Light3D in scene.find_children("*", "Light3D", true, false):
		if light.shadow_enabled:
			shadow_lights.append(light)
			light.shadow_enabled = false
	await _sample("without_shadows")
	for light in shadow_lights:
		light.shadow_enabled = true
	var scenery: Array[Node] = []
	for node in scene.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script != null and script.resource_path.begins_with("res://scripts/environment/") and node.is_processing():
			scenery.append(node)
			node.set_process(false)
	var scheduler := root.get_node_or_null("FramePacing/MobileCombatBudget")
	if scheduler != null:
		scheduler.set_process(false)
	await _sample("scenery_callbacks_suspended")
	if scheduler != null:
		scheduler.set_process(true)
	for node in scenery:
		node.set_process(true)
	await _sample("baseline_repeat")
	# Repeat the principal comparisons after every effect/path has run once.
	await _sample("without_bot_warm", false)
	await _sample("baseline_warm")
	_save_report()

func _save_report() -> void:
	driving = false
	Input.action_release("game_attack")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COMBAT_FRAME_REPORT " + output)
	scene.queue_free()
	await process_frame
	quit()

func _drive() -> void:
	if not driving:
		return
	clock += 1.0 / float(Engine.physics_ticks_per_second)
	player.get("combat_state").health = float(player.call("get_max_health"))
	target.get("combat_state").health = float(target.call("get_max_health"))
	player.call("set_move_input", Vector2(sin(clock * 1.1), cos(clock * 1.1)) * 0.35)
	player.call("_set_aim_direction", target.global_position - player.global_position)
	if fmod(clock, 1.4) < 0.65:
		Input.action_press("game_attack")
	else:
		Input.action_release("game_attack")

func _sample(label: String, with_bot: bool = true, scale_3d: float = 0.75) -> void:
	Input.action_release("game_attack")
	clock = 0.0
	seed(SEED)
	scene.call("prepare_round", LOADOUT.defaults())
	scene.call("activate_round")
	target.call("set_training_bot_enabled", with_bot)
	root.scaling_3d_scale = scale_3d
	await create_timer(1.0).timeout
	var intervals: Array[float] = []
	var hitches: Array[Dictionary] = []
	var pipelines_before := _pipelines()
	var sums := {"draw_calls": 0.0, "primitives": 0.0, "gpu_ms": 0.0, "render_cpu_ms": 0.0, "physics_monitor_ms": 0.0, "bot_tick_ms": 0.0}
	var over_budget := 0
	var stalls := 0
	var before := Time.get_ticks_usec()
	var start := before
	while float(Time.get_ticks_usec() - start) / 1000000.0 < SAMPLE_SECONDS:
		await process_frame
		var now := Time.get_ticks_usec()
		var interval := float(now - before) / 1000.0
		before = now
		intervals.append(interval)
		over_budget += int(interval > 1000.0 / 60.0)
		stalls += int(interval > 1000.0 / 30.0)
		if interval > 50.0:
			hitches.append({"interval_ms": interval, "simulation_seconds": clock,
				"player_position": str(player.global_position), "target_position": str(target.global_position),
				"player_concealed": bool(player.get("_visual_rig").get("_bush_concealed")),
				"pipeline_counters": _pipelines()})
		sums.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sums.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		sums.gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		sums.render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		sums.physics_monitor_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		sums.bot_tick_ms += float(bot.call("get_runtime_costs").average_ms)
	var total := 0.0
	for value in intervals:
		total += value
	for key in sums:
		sums[key] /= float(intervals.size())
	intervals.sort()
	var row := {"case": label, "scale_3d": root.scaling_3d_scale, "frames": intervals.size(),
		"player_weapon": str(player.get("_weapon_id")), "bot_build": scene.call("get_bot_build"),
		"wall_mean_ms": total / intervals.size(), "wall_p50_ms": _percentile(intervals, 0.5),
		"wall_p95_ms": _percentile(intervals, 0.95), "wall_max_ms": intervals.back(),
		"frames_over_16_67_ms": over_budget, "frames_over_33_33_ms": stalls, "means": sums,
		"hitches": hitches, "pipelines_before": pipelines_before, "pipelines_after": _pipelines()}
	report.samples.append(row)
	print("COMBAT_FRAME_SAMPLE " + JSON.stringify(row))

func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(fraction * values.size()) - 1, 0, values.size() - 1)]

func _pipelines() -> Dictionary:
	return {"draw": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
		"surface": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
		"mesh": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
		"specialization": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)}

func _inventory() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for branch in scene.get_children():
		var meshes := branch.find_children("*", "MeshInstance3D", true, false)
		if branch is MeshInstance3D:
			meshes.append(branch)
		var surfaces := 0
		var skinned := 0
		for mesh: MeshInstance3D in meshes:
			if mesh.mesh != null:
				surfaces += mesh.mesh.get_surface_count()
				skinned += int(mesh.skin != null)
		if not meshes.is_empty():
			entries.append({"branch": str(branch.name), "meshes": meshes.size(), "surfaces": surfaces, "skinned_meshes": skinned})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.surfaces) > int(b.surfaces))
	return entries

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.get_basename() + "-" + label + ".png")
