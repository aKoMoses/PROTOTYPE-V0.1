extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-camera-paths/"
const CATEGORIES := ["offensive", "defensive", "passive", "mobility"]
var garage
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
	root.size = Vector2i(1920, 1080)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	garage.library_path = "user://camera-paths-" + suffix + ".cfg"
	garage.legacy_save_path = "user://camera-paths-legacy-" + suffix + ".cfg"
	root.add_child(garage)
	for frame in 5:
		await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	for dimensions in [Vector2i(1920, 1080), Vector2i(960, 540), Vector2i(2340, 1080)]:
		root.size = dimensions
		for frame in 5:
			await process_frame
		garage.focus.set_process(false)
		print("FORGE RESOLUTION window=", root.size, " 3D=", garage.stage.viewport.size)
		for source in CATEGORIES:
			for target in CATEGORIES:
				garage._open_modules(source)
				garage.focus.advance(1.1)
				garage._open_modules(target)
				for sample in 30:
					garage.focus.advance(0.03)
					var camera_position: Vector3 = garage.stage.camera.global_position
					if camera_position.x < -7.15 or camera_position.x > 8.50 or camera_position.z < -5.15:
						failures.append("Camera behind wall: " + source + " -> " + target + " " + str(camera_position))
		if dimensions.x != 1920:
			continue
		for target in CATEGORIES:
			garage._show_garage(false)
			garage.focus.set_process(false)
			garage.focus.advance(1.1)
			garage._open_modules(target)
			garage.focus.set_process(false)
			for sample in 4:
				garage.focus.advance(0.225)
				await _capture(target + "-" + str(sample))
		garage._open_modules("defensive")
		garage.focus.advance(1.1)
		garage._open_modules("offensive")
		for sample in 4:
			garage.focus.advance(0.225)
			await _capture("defensive-to-offensive-" + str(sample))
	for failure in failures:
		push_error(failure)
	print("FORGE CAMERA PATHS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _capture(label: String) -> void:
	await create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + label + ".png")
