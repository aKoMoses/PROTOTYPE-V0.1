extends SceneTree
## Bounded captures of maps 4-6, after the existing art adapters have settled.
## -- OUTPUT_DIRECTORY [low] [heliostat|tideglass|clockwork]
const IDS := ["heliostat", "tideglass", "clockwork"]
const CATALOG := preload("res://scripts/compact_arena_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Use a rendered process with an output directory")
		quit(2)
		return
	var directory: String = args[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var ids := IDS.duplicate()
	for arg in args:
		if arg in IDS:
			ids = [arg]
	var report := {"renderer": RenderingServer.get_current_rendering_driver_name(), "quality": 0 if args.has("low") else 1, "arenas": {}}
	for id in ids:
		await _capture(id, directory, report)
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("COMPACT PRESENTATION CAPTURE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _capture(id: String, directory: String, report: Dictionary) -> void:
	var script := load("res://scripts/main.gd") as Script
	if script == null or not script.can_instantiate():
		failures.append("main scripts did not compile")
		return
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 8:
		await process_frame
	scene.call("set_bot_build_seed", 81738 + IDS.find(id))
	var flow := scene.get_node("Interface")
	flow.call("_select_arena", id)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	scene.get_node("VFXManager").set("quality", int(report.quality))
	for frame in 5:
		await process_frame
	var presentation := scene.get_node_or_null("CompactArenaStage/CompactArenaPresentation")
	if presentation != null:
		presentation.call("refresh_quality")
	scene.set_meta("camera_shake_enabled", false)
	scene.set("_menu_showcase_active", false)
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.call("clear_touch_inputs")
	target.call("set_training_bot_enabled", false)
	_freeze(scene)
	var spawns: Array = CATALOG.definition(id).spawns
	player.global_position = spawns[0]
	player.call("_update_world_ui_anchor")
	target.global_position = spawns[1]
	player.set("aim_direction", Vector3.FORWARD)
	player.global_rotation = Vector3.ZERO
	target.global_rotation = Vector3.ZERO
	var hazards := scene.get_node("ArenaHazards")
	if id == "heliostat":
		hazards.call("advance", 6.0)
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	var rig := camera.get_parent()
	rig.call("set_target", player)
	for frame in 120:
		rig.call("_process", 1.0 / 60.0)
	flow.call("_update_hud")
	scene.get_node("SightTracker").call("_process", 0.0)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(directory.path_join(id + "-gameplay.png"))
	var counts := {"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	var entry := {"camera_position": str(camera.global_position), "camera_rotation": str(camera.global_rotation), "fov": camera.fov, "player_position": str(player.global_position), "target_position": str(target.global_position), "render_counts": counts}
	# A second real walking position shows the cover facades and moving objects.
	player.global_position = {"heliostat": Vector3(-1.8, 0, 4), "tideglass": Vector3(0, 1.35, 7), "clockwork": Vector3(-2.3, 0, 6.5)}[id]
	player.call("_update_world_ui_anchor")
	for frame in 120:
		rig.call("_process", 1.0 / 60.0)
	flow.call("_update_hud")
	scene.get_node("SightTracker").call("_process", 0.0)
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(directory.path_join(id + "-center.png"))
	entry["center_camera"] = {"position": str(camera.global_position), "fov": camera.fov, "player_position": str(player.global_position)}
	if id == "heliostat":
		var mirror: Node = hazards.find_children("SolarMirror*", "StaticBody3D", true, false)[0]
		if not mirror.call("request_turn"):
			failures.append("heliostat mirror command rejected")
		hazards.call("advance", 0.4)
	elif id == "tideglass":
		scene.get_node("CompactArenaStage/TideglassArena").call("advance", 12.0)
	else:
		hazards.call("advance", 9.6)
	player.call("_update_world_ui_anchor")
	flow.call("_update_hud")
	scene.get_node("SightTracker").call("_process", 0.0)
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(directory.path_join(id + "-active.png"))
	for canvas in scene.find_children("*", "CanvasLayer", true, false):
		canvas.visible = false
	for label in scene.find_children("*", "Label3D", true, false):
		label.visible = false
	var overview := Camera3D.new()
	overview.position = Vector3(0, 34, 26)
	overview.fov = 40.0
	scene.add_child(overview)
	overview.look_at(Vector3(0, 0.4, -0.5))
	overview.current = true
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(directory.path_join(id + "-overview.png"))
	entry["presentation"] = presentation.call("get_snapshot") if presentation != null else {}
	report.arenas[id] = entry
	print("COMPACT PRESENTATION VIEW: ", id, " ", counts)
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	current_scene = null
	await process_frame

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _save(path: String) -> void:
	if root.get_texture().get_image().save_png(path) != OK:
		failures.append("capture failed: " + path)
