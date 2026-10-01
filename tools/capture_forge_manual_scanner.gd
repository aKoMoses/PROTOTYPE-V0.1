extends SceneTree

const OUTPUT := "res://captures/forge-manual-scanner/"
var garage
var scanner


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	garage = load("res://scenes/forge_garage_preview.tscn").instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.manual_scanner_ui.set_process(false)
	scanner = garage.manual_scanner_ui.scanner
	garage.manual_scanner_ui.button.pressed.emit()
	scanner.set_process(false)
	if "--motion" in OS.get_cmdline_user_args():
		await capture_motion()
		scanner.set_enabled(false)
		garage.queue_free()
		for frame in 6:
			await process_frame
		quit()
		return
	await capture("00-scanner-ready")
	for selection in [[0, "01-torso-scan"], [1, "02-shoulder-scan"]]:
		var point: Vector2 = garage.stage.camera.unproject_position(scanner._zones[int(selection[0])].center)
		point = point * garage.stage.size / Vector2(garage.stage.viewport.size)
		scanner.point_at(point, true)
		for frame in 150:
			scanner.advance(1.0 / 60.0)
		await capture(str(selection[1]))
		print("SCANNER CAPTURE TARGET: ", scanner.target_zone, " scanning=", scanner.scanning, " error=", garage.stage.arm.contact.global_position.distance_to(scanner.tool_target))
		scanner.retract()
		for frame in 150:
			scanner.advance(1.0 / 60.0)
	scanner.set_enabled(false)
	await capture("03-returned")
	garage.queue_free()
	for frame in 5:
		await process_frame
	quit()


func capture(label: String) -> void:
	garage.manual_scanner_ui.queue_redraw()
	for frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	print("SCANNER CAPTURE: ", label, " code=", root.get_texture().get_image().save_png(OUTPUT + label + ".png"))


func capture_motion() -> void:
	var motion_path := OUTPUT + "motion/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(motion_path))
	var saved_frames := 0
	for frame in 285:
		garage.stage._advance_robot_animation(1.0 / 30.0)
		if frame >= 15 and frame < 225:
			var index := 0 if frame < 135 else 1
			scanner._update_zones()
			var pointer: Vector2 = garage.stage.camera.unproject_position(scanner._zones[index].center)
			pointer = pointer * garage.stage.size / Vector2(garage.stage.viewport.size)
			pointer += Vector2(sin(float(frame) * 0.045) * 5.0, cos(float(frame) * 0.045) * 3.0)
			scanner.point_at(pointer, frame >= 60)
		elif frame == 225:
			scanner.retract()
		scanner.advance(1.0 / 30.0)
		garage.manual_scanner_ui.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 3 == 0:
			var result := root.get_texture().get_image().save_png(motion_path + "%03d.png" % saved_frames)
			if result != OK:
				push_error("Scanner frame could not be saved: " + str(result))
				quit(1)
				return
			saved_frames += 1
	print("SCANNER MOTION CAPTURE: ", saved_frames, " real frames, 9.5 seconds")
