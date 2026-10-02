extends SceneTree

## GPU captures of the actual garage UI and articulated module transport.
const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-module-stations/"
const STEP := 1.0 / 60.0
var garage
var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path)
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	if ignore != null:
		ignore.store_string("\n")
		ignore.close()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	garage.library_path = "user://forge-stations-capture-" + suffix + "-builds.cfg"
	garage.legacy_save_path = "user://forge-stations-capture-" + suffix + "-loadout.cfg"
	root.add_child(garage)
	if "--movie" in OS.get_cmdline_user_args():
		await _movie()
		return
	for frame in 5:
		await process_frame
	_pause_controllers()
	garage._show_garage()
	garage.focus.advance(1.1)
	await _capture("00-garage-1280")
	for category in ["offensive", "defensive", "mobility", "passive"]:
		garage._open_modules(category)
		garage.focus.advance(1.1)
		await _capture("01-station-" + category + "-1280")
	await _sequence("offensive", "rocket_basket", "02-offensive")
	await _sequence("mobility", "pyro_boots", "03-mobility")
	garage._select_equipment("robot", "puissant")
	await _sequence("passive", "auxiliary_reactor", "04-puissant-passive")
	for dimensions in [Vector2i(960, 540), Vector2i(2340, 1080)]:
		root.size = dimensions
		for frame in 5:
			await process_frame
		_pause_controllers()
		garage._show_garage()
		garage.focus.advance(1.1)
		var size_label := str(dimensions.x)
		await _capture("05-garage-" + size_label)
		garage._open_modules("passive")
		garage.focus.advance(1.1)
		await _capture("06-station-passive-" + size_label)
		await _sequence("defensive", "projector", "07-defensive-" + size_label)
	garage.queue_free()
	for frame in 5:
		await process_frame
	for message in errors:
		push_error(message)
	print("FORGE MODULE STATIONS CAPTURE: ", "PASS" if errors.is_empty() else "FAIL")
	quit(0 if errors.is_empty() else 1)


func _movie() -> void:
	# MovieMaker advances real process frames at its fixed timestep.
	await process_frame
	garage._show_garage(false)
	for frame in 45:
		await process_frame
	garage._open_modules("offensive")
	for frame in 40:
		await process_frame
	garage._preview_equipment("offensive", "rocket_basket")
	for frame in 10:
		await process_frame
	garage._equip_preview()
	var started: bool = garage.module_installation.active
	for frame in 400:
		await process_frame
		if not garage.module_installation.active:
			break
	var finished: bool = started and not garage.module_installation.active and str(garage.loadout.offensive) == "rocket_basket"
	garage._show_garage()
	for frame in 45:
		await process_frame
	garage.queue_free()
	for frame in 4:
		await process_frame
	print("FORGE MODULE STATIONS MOVIE: ", "PASS" if finished else "FAIL")
	quit(0 if finished else 1)


func _pause_controllers() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage.installation.set_process(false)


func _sequence(category: String, identifier: String, label: String) -> void:
	garage._open_modules(category)
	garage.focus.advance(1.1)
	garage._select_equipment(category, identifier)
	garage.module_installation.set_process(false)
	var phases: Array[String] = []
	var sampled: Array[String] = []
	for frame in 900:
		garage.module_installation.advance(STEP)
		var phase: String = str(garage.module_installation.phase)
		if not phases.has(phase):
			phases.append(phase)
		if phase in ["pickup", "carry", "align", "work"] and not sampled.has(phase):
			# A few frames into each phase show an established camera and pose.
			for sample_frame in (16 if phase == "pickup" else 10):
				if not garage.module_installation.active:
					break
				garage.module_installation.advance(STEP)
			await _capture(label + "-" + phase)
			sampled.append(phase)
		if not garage.module_installation.active:
			break
	if garage.module_installation.active:
		errors.append("capture sequence did not finish: " + identifier)
		garage.module_installation.cancel()
	garage.focus.advance(1.1)
	await _capture(label + "-complete")
	print("STATION CAPTURE SEQUENCE ", identifier, " phases=", phases, " captured=", sampled)
	if sampled.size() < 3:
		errors.append("missing pickup / transport / mounting images: " + identifier)


func _capture(label: String) -> void:
	# UI catalog fades use native tweens while the arm/camera stay at this frame.
	await create_timer(0.35).timeout
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT + label + ".png")
	print("STATION CAPTURE ", label, " ", image.get_width(), "x", image.get_height(), " code=", error)
	if error != OK:
		errors.append("cannot save screenshot: " + label)
