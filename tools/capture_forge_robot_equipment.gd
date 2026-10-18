extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-robot-equipment/"
var garage
var paths: Array[String] = []
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	root.get_node("FramePacing").hide()
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://robot-equipment-capture-" + suffix + ".cfg", "user://robot-equipment-capture-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	for frame in 12:
		await process_frame
	garage._show_entry(false)
	_pause()
	await _capture("01-pc-entry")
	garage._begin_edit()
	garage.focus.advance(1.0)
	_pause()
	await _capture("02-pc-robot")
	garage._open_station("offensive")
	garage._preview_equipment("offensive", "fulguro_punch")
	_pause()
	await _capture("03-pc-offensive")
	garage.robot_equipment._toggle_details()
	_pause()
	await _capture("03-pc-details")
	garage.robot_equipment._toggle_details()
	garage._select_equipment("offensive", "fulguro_punch")
	_pause()
	for timestamp in [0.65, 1.65, 2.45]:
		while garage.module_installation.active and garage.module_installation.elapsed < timestamp:
			garage.module_installation.advance(1.0 / 60.0)
		_pause()
		await _capture("04-installation-%03d" % int(timestamp * 100))
	garage.module_installation.finish_now()
	_pause()
	await _capture("05-pc-mounted")
	var baseline: Dictionary = garage.loadout.duplicate(true)
	for chassis in ["agile", "puissant"]:
		var equipment := baseline.duplicate(true)
		equipment.robot = chassis
		garage.set_loadout(equipment)
		garage._show_garage(false)
		_pause()
		await _capture("05-pc-" + chassis)
	garage.set_loadout(baseline)
	root.size = Vector2i(1280, 720)
	for frame in 5:
		await process_frame
	garage._open_station("passive")
	garage._preview_equipment("passive", "auxiliary_reactor")
	_pause()
	await _capture("06-pc-passives")
	root.size = Vector2i(844, 390)
	for frame in 5:
		await process_frame
	garage.safe_area_override = Rect2(45, 0, 754, 390)
	garage._show_garage(false)
	_pause()
	await _capture("07-compact-robot")
	garage._open_station("offensive")
	garage._preview_equipment("offensive", "javelin")
	_pause()
	await _capture("08-compact-offensive")
	garage._open_station("passive")
	_pause()
	await _capture("09-compact-passives")
	root.size = Vector2i(1280, 720)
	garage.safe_area_override = Rect2()
	for frame in 5:
		await process_frame
	for sample in [["mobility", "pyro_boots"], ["passive", "auxiliary_reactor"]]:
		var equipment: Dictionary = garage.loadout.duplicate(true)
		equipment[sample[0]] = "bio_injector" if sample[0] == "mobility" else "baroud"
		garage.set_loadout(equipment)
		garage._show_garage(false)
		garage._open_station(sample[0])
		garage._select_equipment(sample[0], sample[1])
		_pause()
		while garage.module_installation.active and garage.module_installation.elapsed < 2.1:
			garage.module_installation.advance(1.0 / 60.0)
		_pause()
		await _capture("10-pose-" + sample[1])
		garage.module_installation.finish_now()
		_pause()
	garage.queue_free()
	for frame in 3:
		await process_frame
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.35).timeout
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("FORGE ROBOT EQUIPMENT CAPTURE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)
	garage.robot_equipment.set_process(false)
	garage.robot_equipment.pin_alpha = 1.0
	garage.robot_equipment._update_pins()

func _capture(label: String) -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	failed = failed or result != OK
	print("ROBOT FRAME ", label, " camera=", garage.stage.camera.global_position, " result=", result)
