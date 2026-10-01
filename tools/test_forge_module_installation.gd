extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var garage := GARAGE.new()
	garage.library_path = "user://module-test-builds.cfg"
	garage.legacy_save_path = "user://module-test-loadout.cfg"
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage._open_modules("mobility")
	if "--runtime" in OS.get_cmdline_user_args():
		await _runtime(garage)
		return
	var completed: Array[String] = []
	garage.module_installation.completed.connect(func(identifier: String): completed.append(identifier))
	var old_exists := FileAccess.file_exists(garage.legacy_save_path)
	for chassis in LOADOUT.ROBOTS:
		garage._select_equipment("robot", chassis)
		for identifier in ["pyro_boots", "bio_injector"]:
			var initial_camera: Transform3D = garage.stage.camera.global_transform
			garage._select_equipment("mobility", identifier)
			garage.module_installation.set_process(false)
			check(garage.module_installation.active and garage.focus.equipment_id == identifier, "click starts focused installation: " + chassis + " " + identifier)
			check(garage.stage.camera.global_transform.is_equal_approx(initial_camera), "camera transition has no initial jump")
			var reached := false
			var max_movement := 0.0
			var initial_tip: Vector3 = garage.stage.arm.contact.global_position
			var count_before := completed.size()
			for frame in 420:
				garage.module_installation.advance(STEP)
				garage.focus.advance(STEP)
				max_movement = maxf(max_movement, initial_tip.distance_to(garage.stage.arm.contact.global_position))
				if garage.module_installation.scanner.scanning:
					reached = true
					check(garage.module_installation.scanner.surface_point.distance_to(garage.stage.module_visuals.service_point(identifier)) < 0.025, "scanner works on the installed housing")
					check(garage.module_installation.scanner.pose_is_clear(garage.module_installation.scanner._command), "arm keeps collision clearance")
				if completed.size() > count_before or not garage.module_installation.active:
					break
			print("MODULE INSTALLATION ", chassis, " ", identifier, " reached=", reached, " work=", garage.module_installation.worked_seconds, " elapsed=", garage.module_installation.elapsed)
			check(reached and max_movement > 0.35, "articulated tool reaches accessory: " + chassis + " " + identifier)
			check(is_equal_approx(garage.module_installation.worked_seconds, 3.0), "exactly three seconds of work after approach")
			check(completed.size() == count_before + 1, "one completion per selection")
			check(not garage.stage.arm.active and not garage.module_installation.scanner._motor.playing, "servo and arm stop at completion")
			garage.focus.advance(0.6)
			check(garage.focus.zone == "robot", "camera returns to catalog view")
	check(FileAccess.file_exists(garage.legacy_save_path) == old_exists and not FileAccess.file_exists(garage.library_path), "selection never writes the saved build")
	garage._select_equipment("mobility", "pyro_boots")
	garage.module_installation.set_process(false)
	garage.module_installation.advance(0.4)
	garage._select_equipment("mobility", "bio_injector")
	garage.module_installation.set_process(false)
	check(garage.module_installation.equipment_id == "bio_injector" and is_zero_approx(garage.module_installation.worked_seconds), "rapid selection restarts on new housing")
	garage._select_equipment("mobility", "eclipse")
	check(not garage.module_installation.active and not garage.stage.arm.active, "another module cancels intervention")
	garage._select_equipment("mobility", "pyro_boots")
	garage._navigate("ROBOT")
	check(not garage.module_installation.active and garage.focus.zone == "robot", "navigation releases scanner")
	garage._select_equipment("mobility", "bio_injector")
	garage.hide()
	check(not garage.module_installation.active and not garage.module_installation.scanner.enabled, "closing cancels local work")
	garage.show()
	garage._select_equipment("mobility", "pyro_boots")
	garage._save_build()
	garage.installation.set_process(false)
	check(garage.installation.active and not garage.module_installation.active and not garage.module_installation.scanner.enabled, "Save transfers sole arm ownership")
	garage.installation.cancel()
	for dimensions in [Vector2i(960, 540), Vector2i(1920, 1080)]:
		root.size = dimensions
		await process_frame
		garage._open_modules("mobility")
		for identifier in ["pyro_boots", "bio_injector"]:
			garage._select_equipment("mobility", identifier)
			garage.module_installation.set_process(false)
			garage.focus.advance(0.6)
			var rect: Rect2 = garage.focus.frame_rect()
			var bounds: AABB = garage.stage.module_visuals.module_bounds(identifier)
			for corner in 8:
				var screen: Vector2 = garage.stage.camera.unproject_position(bounds.get_endpoint(corner)) * garage.stage.size / Vector2(garage.stage.viewport.size)
				check(rect.has_point(screen), "module stays in free preview area: " + identifier + " " + str(dimensions))
			garage.module_installation.cancel()
	garage.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE MODULE INSTALLATION TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _runtime(garage: Control) -> void:
	garage.stage.set_process(true)
	garage.focus.set_process(true)
	garage.module_installation.set_process(true)
	for identifier in ["pyro_boots", "bio_injector"]:
		var button: Button = garage._choices.mobility[identifier]
		var point := button.get_global_rect().get_center()
		await process_frame
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = point
			click.pressed = pressed
			click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			root.push_input(click, true)
			await process_frame
		check(garage.module_installation.active and garage.loadout.mobility == identifier, "real GUI click equips and starts installation: " + identifier)
		var deadline := Time.get_ticks_msec() + 8000
		while garage.module_installation.active and Time.get_ticks_msec() < deadline:
			await process_frame
		check(garage.module_installation.reached_module and is_equal_approx(garage.module_installation.worked_seconds, 3.0), "native frame processing produces three seconds on the housing: " + identifier)
		check(not garage.stage.arm.active and not garage.module_installation.scanner._motor.playing, "native completion releases arm and motor")
		print("MODULE NATIVE ", identifier, " work=", garage.module_installation.worked_seconds, " elapsed=", garage.module_installation.elapsed)
	garage.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE MODULE NATIVE TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
