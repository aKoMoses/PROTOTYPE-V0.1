extends SceneTree
## Diagnostic only. Run with a real rendering backend, not --headless.
## Timings are PC observations; the low profile does not emulate a phone GPU.
var scene: Node3D
var flow: Node
var report: Dictionary = {"timings_ms": {}, "samples": []}

class TimedBot extends "res://scripts/training_bot.gd":
	func _begin_attack(body: Node3D, player: Node3D) -> void:
		var started := Time.get_ticks_usec()
		super._begin_attack(body, player)
		print("BOT_BEGIN_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " mode " + _attack_mode + " at " + str(_elapsed))
	func _resolve_attack(body: Node3D, player: Node3D) -> void:
		var started := Time.get_ticks_usec()
		super._resolve_attack(body, player)
		print("BOT_RESOLVE_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " mode " + _attack_mode + " at " + str(_elapsed))
	func _can_attack(body: Node3D, player: Node3D) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._can_attack(body, player)
		if Time.get_ticks_usec() - started > 2000:
			print("BOT_CAN_ATTACK_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " at " + str(_elapsed))
		return result
	func _update_patrol(body: Node3D, position: Vector3, delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._update_patrol(body, position, delta)
		if Time.get_ticks_usec() - started > 2000:
			print("BOT_PATROL_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " at " + str(_elapsed))
	func _try_dodge(body: Node3D, player: Node3D, visible: bool, duel: bool) -> void:
		var started := Time.get_ticks_usec()
		super._try_dodge(body, player, visible, duel)
		if Time.get_ticks_usec() - started > 2000:
			print("BOT_DODGE_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " at " + str(_elapsed))
	func _sense_projectile_threat(body: Node3D) -> void:
		var started := Time.get_ticks_usec()
		super._sense_projectile_threat(body)
		if Time.get_ticks_usec() - started > 2000:
			print("BOT_THREAT_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " at " + str(_elapsed))
	func _physics_process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._physics_process(delta)
		if Time.get_ticks_usec() - started > 2000:
			print("BOT_PHYSICS_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " at " + str(_elapsed))
	func _spawn_attack_visual(player: Node3D, attack_id: String, offset: Vector3 = Vector3.ZERO) -> void:
		var started := Time.get_ticks_usec()
		super._spawn_attack_visual(player, attack_id, offset)
		print("BOT_SHOT_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " at " + str(_elapsed))
	func _resolve_projectile(hit: Dictionary, distance: float, player: Node3D, scene: Node, attack_id: String) -> void:
		var started := Time.get_ticks_usec()
		super._resolve_projectile(hit, distance, player, scene, attack_id)
		print("BOT_IMPACT_TIME " + str((Time.get_ticks_usec() - started) / 1000.0) + " at " + str(_elapsed))

class TimedNavigation extends "res://scripts/bot_navigation.gd":
	func get_direction(body: CollisionObject3D, destination: Vector3, now: float, arena_limit: float = 27.0) -> Vector3:
		var started := Time.get_ticks_usec()
		var result := super.get_direction(body, destination, now, arena_limit)
		var milliseconds := (Time.get_ticks_usec() - started) / 1000.0
		if milliseconds > 2.0:
			print("NAV_TIME " + str(milliseconds) + " at " + str(now))
		return result

class TimedBlaster extends "res://scripts/player/components/blaster.gd":
	func _init(controller):
		super(controller)
	func _release_blaster_charge() -> void:
		var started := Time.get_ticks_usec()
		super._release_blaster_charge()
		print("BLASTER_RELEASE_TIME " + str((Time.get_ticks_usec() - started) / 1000.0))
	func _begin_blaster_charge(now: float = -1.0) -> void:
		var started := Time.get_ticks_usec()
		super._begin_blaster_charge(now)
		if (Time.get_ticks_usec() - started) > 2000:
			print("BLASTER_BEGIN_TIME " + str((Time.get_ticks_usec() - started) / 1000.0))
	func _on_blaster_projectile_finished(hit: Dictionary, distance: float, damage: float, charge_ratio: float, token: int, shot_direction: Vector3, passive_attack: Dictionary = {}) -> void:
		var started := Time.get_ticks_usec()
		super._on_blaster_projectile_finished(hit, distance, damage, charge_ratio, token, shot_direction, passive_attack)
		if (Time.get_ticks_usec() - started) > 2000:
			print("BLASTER_IMPACT_TIME " + str((Time.get_ticks_usec() - started) / 1000.0))
	func _spawn_blaster_projectile(start: Vector3, damage: float, charge_ratio: float, token: int, shot_direction: Vector3, passive_attack: Dictionary = {}) -> void:
		var started := Time.get_ticks_usec()
		super._spawn_blaster_projectile(start, damage, charge_ratio, token, shot_direction, passive_attack)
		print("BLASTER_SPAWN_TIME " + str((Time.get_ticks_usec() - started) / 1000.0))
	func _play_blaster_recoil(charge_ratio: float) -> void:
		var started := Time.get_ticks_usec()
		super._play_blaster_recoil(charge_ratio)
		if (Time.get_ticks_usec() - started) > 2000:
			print("BLASTER_RECOIL_TIME " + str((Time.get_ticks_usec() - started) / 1000.0))

class TimedEffects extends "res://scripts/player/components/effects.gd":
	func _init(controller):
		super(controller)
	func _create_muzzle_burst(origin: Vector3, direction: Vector3, color: Color, scale: float = 1.0, anchor: Node3D = null) -> void:
		var started := Time.get_ticks_usec()
		super._create_muzzle_burst(origin, direction, color, scale, anchor)
		print("MUZZLE_TIME " + str((Time.get_ticks_usec() - started) / 1000.0))
	func _contact_fx(contact: Dictionary, color: Color, power: float = 1.0, weapon: String = "") -> void:
		var started := Time.get_ticks_usec()
		super._contact_fx(contact, color, power, weapon)
		print("CONTACT_FX_TIME " + str((Time.get_ticks_usec() - started) / 1000.0))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	report["engine"] = Engine.get_version_info().string
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["display"] = DisplayServer.get_name()
	report["viewport"] = str(root.size)
	report["note"] = "Short sequential PC samples at 1280x720 in a hidden window; warm OS/import caches, no mobile FPS extrapolation. Frame intervals include presentation/waits; they are not user-visible FPS. Hidden-arena experiment changes visibility and may also reduce scenery script work. Engine TIME_PROCESS monitors update slowly and may include transition spikes; they are not per-script timings."
	var start := Time.get_ticks_usec()
	var packed := load("res://scenes/main.tscn") as PackedScene
	report.timings_ms["load_main"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	scene = packed.instantiate() as Node3D
	report.timings_ms["instantiate_main"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	root.add_child(scene)
	current_scene = scene
	report.timings_ms["add_main_and_ready"] = (Time.get_ticks_usec() - start) / 1000.0
	flow = scene.get_node("Interface")
	if OS.get_cmdline_user_args().has("timed-bot"):
		var owner_actor := scene.get_node("TargetDummy") as Node3D
		var old_bot: Node = owner_actor.get("_training_bot")
		old_bot.set_physics_process(false)
		old_bot.name = "OldBot"
		var timed_bot := TimedBot.new()
		timed_bot.name = "TrainingBot"
		owner_actor.add_child(timed_bot)
		owner_actor.set("_training_bot", timed_bot)
		timed_bot.set_spawn_position(owner_actor.global_position)
		timed_bot.set_enabled(true)
		timed_bot.set("_navigation", TimedNavigation.new())
		old_bot.queue_free()
	if OS.get_cmdline_user_args().has("timed-navigation"):
		scene.get_node("TargetDummy/TrainingBot").set("_navigation", TimedNavigation.new())
	if OS.get_cmdline_user_args().has("timed-blaster"):
		var actor: Node = scene.get_node("Player")
		var old_component: Node = actor.get("_blaster_component")
		var timed_component := TimedBlaster.new(actor)
		actor.add_child(timed_component)
		actor.set("_blaster_component", timed_component)
		old_component.queue_free()
		var old_effects: Node = actor.get("_effects_component")
		var timed_effects := TimedEffects.new(actor)
		actor.add_child(timed_effects)
		actor.set("_effects_component", timed_effects)
		old_effects.queue_free()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await _sample("menu", 900 if OS.get_cmdline_user_args().has("menu-only") else 180)
	await _capture("menu")
	if OS.get_cmdline_user_args().has("menu-only"):
		var menu_output := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
		menu_output.store_string(JSON.stringify(report, "\t"))
		menu_output.close()
		print("PROFILE_RESULT " + JSON.stringify(report))
		scene.queue_free()
		await process_frame
		quit()
		return
	start = Time.get_ticks_usec()
	flow.call("_open_equipment")
	report.timings_ms["first_open_garage"] = (Time.get_ticks_usec() - start) / 1000.0
	var garage: Node = flow.get("_forge_garage")
	var viewport: SubViewport = garage.get("stage").get("viewport")
	report["garage_viewport"] = {"size": str(viewport.size), "msaa": viewport.msaa_3d, "scale_3d": viewport.scaling_3d_scale}
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	await _sample("garage", 180, viewport)
	await _capture("garage")
	var saved_visibility: Dictionary = {}
	for child in scene.get_children():
		if child is Node3D:
			saved_visibility[child] = child.visible
			child.visible = false
	await _sample("garage_arena_hidden", 180, viewport)
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.scaling_3d_scale = 0.75
	var garage_world: Node = garage.get("stage").get("world")
	var lights := garage_world.find_children("*", "Light3D", true, false)
	var shadow_lights := 0
	for light in lights:
		if light.shadow_enabled:
			shadow_lights += 1
		light.shadow_enabled = false
	report["garage_lights"] = {"total": lights.size(), "shadow_lights": shadow_lights}
	await _sample("garage_arena_hidden_no_shadows_075", 180, viewport)
	for child in saved_visibility:
		child.visible = saved_visibility[child]
	start = Time.get_ticks_usec()
	flow.call("_open_menu")
	flow.call("_open_equipment")
	report.timings_ms["repeat_open_garage"] = (Time.get_ticks_usec() - start) / 1000.0
	await _sample("garage_repeat", 120, viewport)
	flow.call("_show_screen", flow.Screen.COMBAT)
	scene.get_node("Player").call("set_gameplay_enabled", true)
	scene.get_node("TargetDummy").call("set_training_bot_enabled", false)
	await _sample("combat_idle", 180)
	await _capture("combat")
	var vfx := scene.get_node("VFXManager")
	vfx.call("_apply_device_budget", true)
	root.scaling_3d_scale = 0.75
	await _sample("combat_low_profile", 180)
	var disabled: Array[Node] = []
	for node in scene.find_children("*", "Node", true, false):
		if node.get_script() != null and node.get_script().resource_path.begins_with("res://scripts/environment/") and node.is_processing():
			node.set_process(false)
			disabled.append(node)
	report["disabled_scenery_scripts"] = disabled.map(func(n: Node) -> String: return n.get_script().resource_path)
	await _sample("combat_low_scenery_process_off", 180)
	for node in disabled:
		node.set_process(true)
	var output := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "res://docs/performance-diagnostic.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save profile: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PROFILE_RESULT " + JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit()

func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("capture-frames"):
		return
	await RenderingServer.frame_post_draw
	var directory := "C:/Users/Ben/Documents/Codex/2026-09-23/j-ai-x20/outputs/PROTOTYPE-0/outputs/performance-frames"
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))

func _sample(label: String, frames: int, extra: SubViewport = null) -> void:
	var intervals: Array[float] = []
	var hitches: Array[Dictionary] = []
	var sums := {"process_ms": 0.0, "physics_ms": 0.0, "draw_calls": 0.0, "primitives": 0.0, "main_gpu_ms": 0.0, "garage_gpu_ms": 0.0, "main_cpu_ms": 0.0}
	await create_timer(2.0).timeout
	var previous := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append((now - previous) / 1000.0)
		if label == "menu" and intervals[-1] > 25.0:
			hitches.append({"interval_ms": intervals[-1], "showcase_elapsed": scene.get("_menu_showcase_elapsed"), "clip": scene.get("_menu_showcase_clip")})
		previous = now
		sums.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sums.physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		sums.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sums.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		sums.main_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		sums.main_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		if extra != null:
			sums.garage_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(extra.get_viewport_rid())
	for key in sums:
		sums[key] /= frames
	intervals.sort()
	sums["label"] = label
	if label == "menu":
		sums["hitches"] = hitches
	sums["interval_p50_ms"] = intervals[frames / 2]
	sums["interval_p95_ms"] = intervals[int(frames * 0.95)]
	sums["interval_max_ms"] = intervals[-1]
	sums["frames_over_33ms"] = intervals.filter(func(value: float) -> bool: return value > 33.333).size()
	sums["engine_memory_mib"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	sums["gpu_memory_mib"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	sums["meshes_in_tree"] = scene.find_children("*", "MeshInstance3D", true, false).size()
	report.samples.append(sums)
	print("PROFILE_SAMPLE " + JSON.stringify(sums))
