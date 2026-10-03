extends SceneTree

var scene: Node3D
var solar: Node3D
var player: Node3D
var bot: Node3D
var directory := ""
var camera: Camera3D

func _initialize() -> void:
	call_deferred("_run")

func _sample(time: float) -> void:
	solar.call("reset_round")
	solar.call("start_round")
	solar.call("advance", time)

func _save(name: String, into: String = "") -> void:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var destination := directory if into == "" else into
	var status := root.get_texture().get_image().save_png(destination.path_join(name + ".png"))
	assert(status == OK, "capture write failed")

func _centroid(polygon: PackedVector2Array) -> Vector3:
	var point := Vector2.ZERO
	for vertex in polygon:
		point += vertex
	point /= polygon.size()
	return Vector3(point.x, 0, point.y)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	directory = args[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var frames_directory := args[1] if args.size() > 1 else directory
	DirAccess.make_dir_recursive_absolute(frames_directory)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	scene.call("set_bot_build_seed", 81738)
	flow.call("_select_arena", "heliostat")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	scene.set("_menu_showcase_active", false)
	scene.set_meta("camera_shake_enabled", false)
	player = scene.get_node("Player")
	bot = scene.get_node("TargetDummy")
	player.set_process(false)
	player.set_physics_process(false)
	bot.call("set_training_bot_enabled", false)
	bot.set_process(false)
	bot.set_physics_process(false)
	scene.get_node("CompactArenaStage").set_process(false)
	solar = scene.get_node("ArenaHazards")
	solar.set_physics_process(false)
	assert(solar.get_script().resource_path == "res://scripts/heliostat_arena.gd", "production scene uses wrong arena controller")
	scene.get_node("FogOfWar").call("set_enabled", false)
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	var layers: Array[CanvasLayer] = []
	for child in scene.get_children():
		if child is CanvasLayer:
			layers.append(child)
			child.visible = false
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 34, 26)
	camera.fov = 40
	camera.look_at(Vector3(0, 0, -0.5))
	camera.current = true
	_sample(12.6)
	for polygon in solar.get("shadow_polygons"):
		var point := _centroid(polygon)
		if not solar.call("exposure_at", point, 0.4):
			player.position = point
			break
	solar.call("_update_heat", 0.01)
	await _save("heliostat-solar-overview")
	var report := {"engine": Engine.get_version_info().string, "controller": solar.get_script().resource_path, "shadow_example": solar.call("get_snapshot"), "player_in_shadow": not solar.call("exposure_at", player.position, 0.32), "source": "actual production scene rendered in Godot"}
	for index in range(49):
		_sample(5.7 + index * 0.5)
		await _save("sweep-%02d" % index, frames_directory)
	_sample(6.1)
	await _save("mirror-before")
	var mirror: Node3D = solar.get("mirrors")[0]
	mirror.call("projectile_impact", mirror.global_position)
	solar.call("advance", 0.4)
	await _save("mirror-announced")
	solar.call("advance", 0.42)
	await _save("mirror-after")
	report["mirror_after"] = solar.call("get_snapshot")
	# Production follow camera and HUD, with the player warmed by real exposure.
	_sample(12.6)
	for index in range(80):
		var polygons: Array = solar.get("light_polygons")
		if not polygons.is_empty():
			player.position = _centroid(polygons[polygons.size() / 2])
		solar.call("advance", 1.0 / 60.0)
	for layer in layers:
		layer.visible = true
	camera.current = false
	rig.get_node("Camera3D").current = true
	for index in range(120):
		rig.call("_process", 1.0 / 60.0)
	flow.call("_update_countdown_overlay")
	flow.call("_update_hud")
	player.call("_update_world_ui_anchor")
	await _save("heliostat-solar-gameplay")
	report["heat_example"] = solar.call("get_snapshot")
	var file := FileAccess.open(directory.path_join("heliostat-captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	scene.call("stop_duel")
	scene.queue_free()
	await process_frame
	print("HELIOSTAT PRODUCTION CAPTURE: PASS")
	quit()
