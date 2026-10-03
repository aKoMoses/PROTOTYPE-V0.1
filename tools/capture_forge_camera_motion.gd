extends SceneTree

## Render one real camera cycle; freeze the robot to make the subtle parallax inspectable.
const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-camera-motion/"
const FPS := 20
var garage
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "frames"))
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	ignore.store_string("\n")
	ignore.close()
	var git_ignore := FileAccess.open(OUTPUT + ".gitignore", FileAccess.WRITE)
	git_ignore.store_string("frames/\n*.log\n")
	git_ignore.close()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://forge-orbit-capture-" + suffix + ".cfg", "user://forge-orbit-capture-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	for frame in 5:
		await process_frame
	garage._show_garage(false)
	garage.focus.set_process(false)
	garage.stage.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)
	garage.set_process_input(false)
	# A full cycle after its initial speed ramp gives a continuous loop.
	for frame in 2 * FPS:
		garage.focus.advance(1.0 / FPS)
	var baseline: Transform3D = garage.focus._garage_transform()
	var minimum := INF
	var maximum := -INF
	for frame in 18 * FPS:
		garage.focus.advance(1.0 / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = root.get_texture().get_image()
		var offset: Vector3 = garage.stage.camera.global_position - baseline.origin
		var lateral := offset.dot(baseline.basis.x)
		minimum = minf(minimum, lateral)
		maximum = maxf(maximum, lateral)
		assert(pixels.save_png(OUTPUT + "frames/frame-%04d.png" % frame) == OK)
		if frame in [0, 90, 180, 270]:
			assert(pixels.save_png(OUTPUT + "garage-%02d.png" % (frame / FPS)) == OK)
		if frame % 120 == 0:
			print("ORBIT CAPTURE FRAME ", frame, "/360")
	assert(maximum - minimum > 0.19)
	garage.queue_free()
	await process_frame
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("FORGE CAMERA MOTION CAPTURE: PASS (360 GPU frames, 18 seconds, span=", maximum - minimum, ")")
	quit()
