extends SceneTree

## Native GPU captures of the extended garage; temporary saves only.
const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-hangar/"
var garage
var paths: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	ignore.store_string("\n")
	ignore.close()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://forge-hangar-capture-" + suffix + ".cfg", "user://forge-hangar-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	for frame in 5:
		await process_frame
	_pause()
	garage._show_garage(false)
	garage.focus.advance(0.95)
	_pause()
	await _capture("garage-1280")
	print("HANGAR CAMERA ", garage.stage.camera.global_position, " batches=", garage.stage.world.get_node("GarageHangar").get_child_count())
	if not "--overview" in OS.get_cmdline_user_args():
		for category in ["weapon", "passive", "offensive", "defensive", "mobility"]:
			garage._open_station(category)
			garage.focus.advance(0.95)
			_pause()
			await _capture(category + "-1280")
		garage._show_garage(false)
		_pause()
		for frame in 270:
			garage.focus.advance(1.0 / 60.0)
		await _capture("orbit-left-1280")
		for frame in 540:
			garage.focus.advance(1.0 / 60.0)
		await _capture("orbit-right-1280")
		for dimensions in [Vector2i(960, 540), Vector2i(2340, 1080)]:
			root.size = dimensions
			for frame in 4:
				await process_frame
			garage._show_garage(false)
			garage.focus.advance(0.95)
			_pause()
			await _capture("garage-" + str(dimensions.x))
		# New scenery remains decorative: the existing five station picks are intact.
		for category in ["weapon", "passive", "offensive", "defensive", "mobility"]:
			var provider = garage.stage.weapon_rack if category == "weapon" else garage.stage.module_stations
			var point: Vector2 = garage.stage.camera.unproject_position(provider.bounds(category).get_center())
			point *= garage.stage.size / Vector2(garage.stage.viewport.size)
			if garage._pick_station(point) != category:
				failures.append("station picking failed: " + category)
	garage.queue_free()
	await process_frame
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("FORGE HANGAR CAPTURE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)


func _capture(label: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if pixels.save_png(OUTPUT + label + ".png") != OK:
		failures.append("capture could not be saved: " + label)
	print("HANGAR FRAME ", label, " ", pixels.get_size())
