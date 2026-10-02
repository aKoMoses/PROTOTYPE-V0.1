extends SceneTree

const OUTPUT := "res://captures/forge-demos/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var garage = load("res://scenes/forge_garage_preview.tscn").instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	garage.stage.arm.cancel_service()
	garage.stage.set_process(false)
	for identifier in ["mekatana", "shotgun", "longshot"]:
		garage.weapon_buttons[identifier].pressed.emit()
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + identifier + ".png")
	garage.weapon_buttons["mekatana"].pressed.emit()
	await _capture_enlarged(garage, "mekatana-enlarged.png")
	garage.call("_open_modules", "offensive")
	garage.get("_module_options").get_child(2).pressed.emit()
	await create_timer(1.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "fulguro-punch.png")
	garage.call("_open_modules", "passive")
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "modules.png")
	garage.get("_module_panel").hide()
	root.size = Vector2i(960, 540)
	garage.weapon_buttons["mekatana"].pressed.emit()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "mekatana-960.png")
	await _capture_enlarged(garage, "mekatana-enlarged-960.png")
	print("FORGE TRAINING DEMO CAPTURES: DONE")
	quit()


func _capture_enlarged(garage, filename: String) -> void:
	await create_timer(0.5).timeout
	var preview = garage.get("_training_demo")
	await _click(preview.video.get_global_rect().get_center())
	assert(preview._viewer.visible, "le clic ouvre la video agrandie")
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + filename)
	await _click(preview._close_button.get_global_rect().get_center())
	assert(not preview._viewer.visible and preview.video.is_playing(), "fermeture avec lecture conservee")


func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	for pressed in [true, false]:
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
