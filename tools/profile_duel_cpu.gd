extends SceneTree
## Measures actual duel CPU work; PC timings are not Android frame rates.
const LOADOUT := preload("res://scripts/loadout_state.gd")
var scene: Node3D
var bot: Node
var target: Node3D
var player: Node3D
var fog: Node
var samples: Array[Dictionary] = []

class Timing:
	static var values: Dictionary = {}
	static func record(label: String, start: int) -> void:
		var elapsed := float(Time.get_ticks_usec() - start) / 1000.0
		var entry: Dictionary = values.get(label, {"calls": 0, "total_ms": 0.0, "peak_ms": 0.0})
		entry.calls += 1
		entry.total_ms += elapsed
		entry.peak_ms = maxf(entry.peak_ms, elapsed)
		values[label] = entry

class TimedNavigation extends "res://scripts/bot_navigation.gd":
	func _find_path(context: Dictionary, origin: Vector3, destination: Vector3) -> Array[Vector3]:
		var start := Time.get_ticks_usec()
		var result := super._find_path(context, origin, destination)
		Timing.record("navigation_search", start)
		return result
	func _context(body: CollisionObject3D, arena_limit: float) -> Dictionary:
		var start := Time.get_ticks_usec()
		var result := super._context(body, arena_limit)
		Timing.record("navigation_context", start)
		return result

class TimedBot extends "res://scripts/training_bot.gd":
	func _physics_process(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._physics_process(delta)
		Timing.record("bot_physics", start)
	func _update_duel_decision(body: Node3D, opponent: Node3D) -> void:
		var start := Time.get_ticks_usec()
		super._update_duel_decision(body, opponent)
		Timing.record("bot_decisions", start)
	func _update_repair_target(body: Node3D, opponent: Node3D) -> bool:
		var start := Time.get_ticks_usec()
		var result := super._update_repair_target(body, opponent)
		Timing.record("bot_repairs", start)
		return result
	func _update_duel_movement(body: Node3D, destination: Vector3, visible: bool, delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._update_duel_movement(body, destination, visible, delta)
		Timing.record("bot_movement", start)
	func _update_duel_perception(body: Node3D, opponent: Node3D, visible: bool) -> void:
		var start := Time.get_ticks_usec()
		super._update_duel_perception(body, opponent, visible)
		Timing.record("bot_perception", start)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(1731)
	scene = load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	target = scene.get_node("TargetDummy")
	player = scene.get_node("Player")
	var old: Node = target.get("_training_bot")
	old.set_physics_process(false)
	old.name = "OldBot"
	bot = TimedBot.new()
	bot.name = "TrainingBot"
	target.add_child(bot)
	target.set("_training_bot", bot)
	bot.set("_navigation", TimedNavigation.new())
	old.queue_free()
	fog = scene.get_node_or_null("FogOfWar")
	if OS.get_cmdline_user_args().has("mobile-performance"):
		scene.get_node("VFXManager").call("_apply_device_budget", true)
	if OS.get_cmdline_user_args().has("legacy-cost"):
		# Reproduce the measured budgets without reverting production files.
		fog.name = "DiscardedFog"
		fog.queue_free()
		fog = load("res://.godot/android-duel-performance/legacy_fog.gd").new()
		fog.name = "FogOfWar"
		scene.add_child(fog)
		fog.call("configure", player, scene.get_node("CameraRig/Camera3D"))
		scene.set("fog_of_war", fog)
		var scheduler := root.get_node_or_null("FramePacing/MobileCombatBudget")
		if scheduler != null:
			scheduler.queue_free()
			await process_frame
	var flow: Node = scene.get_node("Interface")
	scene.call("set_bot_build_seed", 4242)
	flow.set("loadout", LOADOUT.defaults())
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for frame in 150:
		_keep_alive(false)
		await physics_frame
	await _sample("duel", true, true, false)
	await _sample("duel_without_bot", false, true, false)
	await _sample("duel_without_fog", true, false, false)
	await _sample("wounded_bot", true, true, true)
	var report := {"engine": Engine.get_version_info().string, "backend": DisplayServer.get_name(), "arguments": OS.get_cmdline_user_args(), "samples": samples, "note": "CPU samples on PC, fixed simulation ticks, actual actors and authored arena. No Android FPS claim."}
	if not OS.get_cmdline_user_args().is_empty():
		var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	print("DUEL_CPU_PROFILE " + JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit()

func _keep_alive(wounded: bool) -> void:
	player.get("combat_state").health = float(player.call("get_max_health"))
	target.get("combat_state").health = float(target.call("get_max_health")) * (0.1 if wounded else 1.0)

func _sample(label: String, bot_enabled: bool, fog_enabled: bool, wounded: bool) -> void:
	scene.call("prepare_round", LOADOUT.defaults())
	scene.call("activate_round")
	target.call("set_training_bot_enabled", bot_enabled)
	if fog != null:
		fog.call("set_enabled", fog_enabled)
		fog.set_process(fog_enabled)
		fog.set_physics_process(fog_enabled)
		if not fog_enabled:
			# Main keeps the enabled state synchronized with the round. Suppress
			# the draw as well as the callbacks for a genuine fog-off ablation.
			(fog.get("_overlay") as MeshInstance3D).layers = 0
	for frame in 60:
		_keep_alive(wounded)
		await physics_frame
	Timing.values.clear()
	var started := Time.get_ticks_usec()
	var fog_total := 0.0
	var fog_peak := 0.0
	var fog_updates := 0
	var last_profile := int(fog.get("_profile_updates")) if fog != null else 0
	for frame in 600:
		_keep_alive(wounded)
		player.call("set_move_input", Vector2(sin(float(frame) * 0.017), cos(float(frame) * 0.017)) * 0.5)
		await physics_frame
		if fog != null and int(fog.get("_profile_updates")) != last_profile:
			last_profile = int(fog.get("_profile_updates"))
			fog_updates += 1
			fog_total += float(fog.get("_last_update_ms"))
			fog_peak = maxf(fog_peak, float(fog.get("_last_update_ms")))
	var metrics := Timing.values.duplicate(true)
	for metric in metrics.values():
		metric["ms_per_tick"] = float(metric.total_ms) / 600.0
		metric["ms_per_call"] = float(metric.total_ms) / maxi(1, int(metric.calls))
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) if DisplayServer.get_name() != "headless" else 0.0
	samples.append({"label": label, "wall_ms_per_tick": float(Time.get_ticks_usec() - started) / 600000.0, "metrics": metrics, "fog": {"updates": fog_updates, "ms_per_tick": fog_total / 600.0, "peak_ms": fog_peak}, "navigation_cache": bot.get("_navigation").get_cache_stats(), "gpu_last_ms": gpu_ms})
	print("DUEL_SAMPLE " + JSON.stringify(samples.back()))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := OS.get_cmdline_user_args()[0].get_base_dir()
		root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
