extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-spaced-layout/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	ignore.store_string("\n")
	ignore.close()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	garage.library_path = "user://forge-layout-" + suffix + ".cfg"
	garage.legacy_save_path = "user://forge-layout-legacy-" + suffix + ".cfg"
	root.add_child(garage)
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(2340, 1080)]:
		root.size = dimensions
		for frame in 5:
			await process_frame
		garage.stage.set_process(false)
		garage.focus.set_process(false)
		garage._show_garage(false)
		garage.focus.set_process(false)
		garage.focus.advance(1.1)
		await _capture("garage-" + str(dimensions.x))
		assert(garage.find_children("Station_*", "Button", true, false).is_empty())
		garage._build_menu.get_popup().id_pressed.emit(0)
		assert(garage._rename_panel.visible)
		garage._finish_rename()
		garage._build_menu.get_popup().id_pressed.emit(2)
		assert(garage.build_name.ends_with("COPIE"))
		garage._build_menu.get_popup().id_pressed.emit(1)
		assert(garage.build_name.begins_with("BUILD "))
		garage._finish_rename()
		garage._build_menu.get_popup().id_pressed.emit(3)
		assert(garage.installation.active)
		garage.installation.cancel()
	garage.queue_free()
	await process_frame
	print("FORGE SPACED LAYOUT CAPTURE: PASS")
	quit()


func _capture(label: String) -> void:
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK)
