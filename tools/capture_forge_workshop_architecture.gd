extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-workshop-architecture/"
var garage
var temporary_paths: Array[String] = []
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	ignore.store_string("\n")
	ignore.close()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.get_node("FramePacing").hide()
	root.size = Vector2i(1920, 1080)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	temporary_paths = ["user://workshop-capture-" + suffix + ".cfg", "user://workshop-capture-legacy-" + suffix + ".cfg"]
	garage.library_path = temporary_paths[0]
	garage.legacy_save_path = temporary_paths[1]
	root.add_child(garage)
	for frame in 15:
		await process_frame
	garage._show_entry(false)
	garage.focus.advance(0.0)
	_pause()
	await _capture("pc-1920-entry")
	garage._show_garage(false)
	garage.focus.advance(0.0)
	_pause()
	await _capture("pc-1920-build")
	garage.focus._desktop_zoom = 1.5
	garage.focus._desktop_zoom_goal = 1.5
	garage.focus.advance(0.0)
	_pause()
	await _capture("pc-1920-wide")
	garage.focus._desktop_zoom = 1.0
	garage.focus._desktop_zoom_goal = 1.0
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		garage._open_station(category)
		garage.focus.advance(1.0)
		_pause()
		await _capture("pc-1920-" + category)
	root.size = Vector2i(844, 390)
	for frame in 6:
		await process_frame
	garage.safe_area_override = Rect2(59, 0, 726, 369)
	garage._show_entry(false)
	garage.focus.advance(0.0)
	_pause()
	await _capture("phone-844-entry")
	garage._show_garage(false)
	garage.focus.advance(0.0)
	_pause()
	await _capture("phone-844-build")
	root.size = Vector2i(1280, 720)
	garage.safe_area_override = Rect2()
	for frame in 6:
		await process_frame
	for sample in [["offensive", "rocket_basket"], ["mobility", "pyro_boots"], ["passive", "auxiliary_reactor"]]:
		var baseline: Dictionary = garage.loadout.duplicate(true)
		baseline[sample[0]] = "bio_injector" if sample[0] == "mobility" else ("javelin" if sample[0] == "offensive" else "baroud")
		garage.set_loadout(baseline)
		garage._open_station(sample[0])
		garage.focus.advance(1.0)
		garage._select_equipment(sample[0], sample[1])
		_pause()
		for timestamp in [1.8, 3.6, 4.8]:
			while garage.module_installation.active and garage.module_installation.elapsed < timestamp:
				garage.module_installation.advance(1.0 / 30.0)
			_pause()
			await _capture("installation-%s-%03d" % [sample[1], int(timestamp * 100)])
		garage.module_installation.finish_now()
		_pause()
	garage.queue_free()
	for frame in 3:
		await process_frame
	await create_timer(0.5).timeout
	for temporary_path in temporary_paths:
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	print("FORGE WORKSHOP CAPTURE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)

func _capture(label: String) -> void:
	for frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	failed = failed or code != OK
	print("WORKSHOP FRAME ", label, " camera=", garage.stage.camera.global_position, " result=", code)
