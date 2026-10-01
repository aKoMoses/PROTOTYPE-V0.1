extends SceneTree

const OUTPUT := "res://captures/robot-modules/"
var garage


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	garage = preload("res://scripts/forge_garage.gd").new()
	garage.library_path = "user://module-capture-builds.cfg"
	garage.legacy_save_path = "user://module-capture-loadout.cfg"
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage._open_modules("mobility")
	for identifier in ["pyro_boots", "bio_injector"]:
		garage._select_equipment("mobility", identifier)
		garage.module_installation.set_process(false)
		for frame in 160:
			garage.module_installation.advance(1.0 / 60.0)
			garage.focus.advance(1.0 / 60.0)
		print("MODULE CAPTURE ", identifier, " active=", garage.module_installation.active, " work=", garage.module_installation.worked_seconds, " point=", garage.stage.module_visuals.service_point(identifier), " bounds=", garage.stage.module_visuals.module_bounds(identifier))
		await _capture(identifier + "-work")
		garage.module_installation.cancel(false)
		garage.focus.show_equipment("mobility", identifier, false)
		garage.focus.advance(0.6)
		await _capture(identifier + "-detail")
		garage.focus.show_overview(false)
		await _capture(identifier + "-overview")
		root.size = Vector2i(960, 540)
		await process_frame
		garage.focus.show_equipment("mobility", identifier, false)
		garage.focus.advance(0.6)
		await _capture(identifier + "-mobile")
		root.size = Vector2i(1600, 900)
		await process_frame
	garage.queue_free()
	await process_frame
	print("ROBOT MODULE CAPTURE: PASS")
	quit()


func _capture(label: String) -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	print("MODULE CAPTURE ", label, " result=", error)
