extends SceneTree

const OUTPUT := "res://captures/forge-garage-focus/"
var suffix := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	suffix = "-wide" if root.size.x > 1800 else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var garage = load("res://scenes/forge_garage_preview.tscn").instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.stage.arm.cancel_service()
	if "--anchors" in OS.get_cmdline_user_args():
		for bone in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "Spine", "Spine1", "Spine2"]:
			print("FOCUS ANCHOR: ", bone, " = ", garage.focus.anchor(bone))
	await capture("00-overview")
	(garage.weapon_buttons["longshot"] as Button).pressed.emit()
	garage.focus.advance(0.70)
	await capture("01-longshot")
	for selection in [["offensive", 2, "02-fulguro-punch"], ["defensive", 1, "03-static-shield"], ["mobility", 0, "04-pyro-boots"], ["mobility", 1, "05-bio-injector"], ["passive", 1, "06-omnivamp"]]:
		garage._open_modules(str(selection[0]))
		(garage._module_options.get_child(int(selection[1])) as Button).pressed.emit()
		garage.focus.advance(0.70)
		await capture(str(selection[2]))
	garage._open_modules("mobility")
	garage.focus.advance(0.70)
	await capture("07-module-picker")
	garage._module_panel.hide()
	garage.stage.begin_robot_rotation()
	garage.stage.rotate_robot(0.75)
	garage.stage.end_robot_rotation()
	garage.focus.advance(0.70)
	await capture("08-rotated-core")
	garage.hide()
	garage._training_demo.video.stop()
	await process_frame
	garage.queue_free()
	await process_frame
	print("FORGE FOCUS CAPTURE: DONE")
	quit()


func capture(label: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + label + suffix + ".png")
	print("FORGE FOCUS CAPTURE: ", label, " = ", result)
