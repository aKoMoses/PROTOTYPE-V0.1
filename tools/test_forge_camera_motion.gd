extends SceneTree

## Idle orbit, real GUI interactions, framing and camera ownership.
const GARAGE := preload("res://scripts/forge_garage.gd")
const STEP := 1.0 / 60.0
var garage
var failures: Array[String] = []
var checks := 0
var temporary_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	temporary_paths = ["user://forge-orbit-" + suffix + ".cfg", "user://forge-orbit-legacy-" + suffix + ".cfg"]
	garage.library_path = temporary_paths[0]
	garage.legacy_save_path = temporary_paths[1]
	root.add_child(garage)
	for frame in 3:
		await process_frame
	_pause()
	var draft: Dictionary = garage.loadout.duplicate(true)
	var robot_pose: Transform3D = garage.stage.robot.global_transform
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(2340, 1080)]:
		root.size = dimensions
		for frame in 3:
			await process_frame
		garage._show_garage(false)
		_pause()
		_check_cycle(dimensions)
		await _check_hover_and_picking(dimensions)
	root.size = Vector2i(1280, 720)
	for frame in 3:
		await process_frame
	await _check_rotation(false)
	await _check_rotation(true)
	_check_other_views()
	await _check_visibility()
	check(garage.loadout == draft and garage.stage.robot.global_position.is_equal_approx(robot_pose.origin), "camera motion preserves build and robot position")
	if "--runtime" in OS.get_cmdline_user_args():
		await _check_native_motion()
	garage.queue_free()
	for frame in 4:
		await process_frame
	for path in temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE CAMERA MOTION TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks; ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)


func _advance(seconds: float) -> void:
	for frame in ceili(seconds / STEP):
		garage.focus.advance(STEP)


func _check_cycle(dimensions: Vector2i) -> void:
	var camera: Camera3D = garage.stage.camera
	var baseline := camera.global_transform
	var original_fov := camera.fov
	var pivot: Vector3 = garage.stage.robot.global_position + Vector3(0, 1.35, 0)
	var projected := _project(pivot)
	_advance(1.5)
	var minimum := INF
	var maximum := -INF
	var previous := camera.global_position
	var safe := true
	var smooth := true
	var stable_hero := true
	for frame in 1080:
		garage.focus.advance(STEP)
		var offset := camera.global_position - baseline.origin
		var lateral := offset.dot(baseline.basis.x)
		minimum = minf(minimum, lateral)
		maximum = maxf(maximum, lateral)
		safe = safe and offset.length() <= 0.101 and is_equal_approx(offset.y, 0.0) and is_equal_approx(camera.fov, original_fov)
		smooth = smooth and camera.global_position.distance_to(previous) < 0.001
		stable_hero = stable_hero and _project(pivot).distance_to(projected) < 0.02
		previous = camera.global_position
		if frame % 270 == 0:
			_check_station_framing(str(dimensions))
	check(maximum - minimum > 0.19, "complete subtle lateral cycle at " + str(dimensions))
	check(safe and smooth and stable_hero, "bounded smooth orbit, stable hero, height and FOV at " + str(dimensions))
	print("ORBIT ", dimensions, " span=", maximum - minimum)


func _check_station_framing(label: String) -> void:
	var bounds: AABB = garage.stage.robot.global_transform * garage.stage._robot_pick_bounds
	var fits := true
	for corner in 8:
		var point := bounds.get_endpoint(corner)
		fits = fits and not garage.stage.camera.is_position_behind(point) and garage.focus.frame_rect().grow(1).has_point(_project(point))
	check(fits, "robot remains framed throughout the orbit: " + label)
	for title in ["ARMES", "MODULES", "MES BUILDS"]:
		var button: Button = garage._nav[title]
		var rect := button.get_global_transform() * Rect2(Vector2.ZERO, button.size)
		check(button.is_visible_in_tree() and Rect2(Vector2.ZERO, garage.size).encloses(rect), "navigation stays accessible during the orbit: " + title)


func _check_hover_and_picking(dimensions: Vector2i) -> void:
	var modules: Button = garage._nav.MODULES
	var point: Vector2 = modules.get_global_transform() * (modules.size * 0.5)
	await _mouse_motion(point)
	check(garage.focus._station_hovered, "navigation hover pauses the camera at " + str(dimensions))
	var held: Transform3D = garage.stage.camera.global_transform
	_advance(3.0)
	check(garage.stage.camera.global_transform.is_equal_approx(held), "hover freezes current camera pose: " + str(dimensions))
	await _mouse_motion(Vector2(dimensions.x * 0.50, dimensions.y * 0.77))
	garage.focus.advance(STEP)
	check(garage.stage.camera.global_position.distance_to(held.origin) < 0.00002, "hover release resumes without a jump: " + str(dimensions))
	_advance(2.0)
	check(garage.stage.camera.global_position.distance_to(held.origin) > 0.005, "orbit resumes after leaving navigation")
	point = modules.get_global_transform() * (modules.size * 0.5)
	await _press(point, true, false)
	await _press(point, false, false)
	garage.focus.set_process(false)
	garage.focus.advance(0.95)
	check(garage._category == "passive" and garage.focus.zone in ["station", "catalog"], "navigation opens the selected family")
	var station_pose: Transform3D = garage.stage.camera.global_transform
	_advance(3.0)
	check(garage.stage.camera.global_transform.is_equal_approx(station_pose), "catalog camera remains stationary")
	garage._show_garage(false)
	_pause()
	_advance(2.0)
	var weapons: Button = garage._nav.ARMES
	await _mouse_motion(weapons.get_global_transform() * (weapons.size * 0.5))
	var weapon_hold: Transform3D = garage.stage.camera.global_transform
	_advance(1.0)
	check(garage.stage.camera.global_transform.is_equal_approx(weapon_hold), "weapon navigation also freezes the orbit")
	root.mouse_exited.emit()
	await _mouse_motion(Vector2(dimensions.x * 0.5, dimensions.y * 0.75))
	_advance(2.0)
	check(garage.stage.camera.global_position.distance_to(weapon_hold.origin) > 0.005, "leaving the controls clears the hover pause")


func _check_rotation(touch: bool) -> void:
	garage._show_garage(false)
	_pause()
	_advance(2.0)
	var yaw: float = garage.stage.robot.rotation.y
	var point := _project(garage.stage.robot.global_position + Vector3(0, 1.35, 0))
	await _mouse_motion(point)
	var held: Transform3D = garage.stage.camera.global_transform
	await _press(point, true, touch)
	if touch:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = point + Vector2(100, 0)
		drag.relative = Vector2(100, 0)
		root.push_input(drag, true)
		await process_frame
	else:
		await _mouse_motion(point + Vector2(100, 0), true)
	_advance(3.0)
	check(absf(angle_difference(yaw, garage.stage.robot.rotation.y)) > 0.2, "real drag rotates the robot: touch=" + str(touch))
	check(garage.stage.camera.global_transform.is_equal_approx(held), "camera remains fixed throughout robot drag: touch=" + str(touch))
	await _press(point + Vector2(100, 0), false, touch)
	garage.focus.advance(STEP)
	check(garage.stage.camera.global_position.distance_to(held.origin) < 0.00002, "drag release resumes smoothly: touch=" + str(touch))
	_advance(2.0)
	check(garage.stage.camera.global_position.distance_to(held.origin) > 0.005, "orbit resumes after robot release: touch=" + str(touch))
	garage.stage.robot.rotation.y = yaw


func _check_other_views() -> void:
	garage._navigate("ROBOT")
	_pause()
	garage.focus.advance(0.95)
	var held: Transform3D = garage.stage.camera.global_transform
	_advance(3.0)
	check(garage.stage.camera.global_transform.is_equal_approx(held), "robot inspection has no ambient orbit")
	garage._open_weapon_rack()
	_pause()
	garage.focus.advance(0.95)
	garage._select_equipment("weapon", "shotgun" if garage.loadout.weapon != "shotgun" else "blaster")
	check(garage.module_installation.active and not garage.focus.is_processing(), "installation retains sole control of the camera")
	garage.module_installation.cancel(false)
	garage._show_garage()
	_pause()
	garage.focus.advance(0.95)
	var returned: Transform3D = garage.stage.camera.global_transform
	garage.focus.advance(STEP)
	check(garage.stage.camera.global_position.distance_to(returned.origin) < 0.00002, "return to workshop starts the orbit gently")


func _check_visibility() -> void:
	garage.hide()
	await process_frame
	var hidden: Transform3D = garage.stage.camera.global_transform
	_advance(2.0)
	check(not garage.focus.is_processing() and garage.stage.camera.global_transform.is_equal_approx(hidden), "hidden garage has no camera drift")
	garage.show()
	await process_frame
	_pause()
	var reopened: Transform3D = garage.stage.camera.global_transform
	garage.focus.advance(STEP)
	check(garage.stage.camera.global_position.distance_to(reopened.origin) < 0.00002, "reopening starts without a stale hover pause or jump")


func _check_native_motion() -> void:
	garage._show_garage(false)
	garage.focus.set_process(true)
	var initial: Transform3D = garage.stage.camera.global_transform
	await create_timer(3.0).timeout
	check(garage.stage.camera.global_position.distance_to(initial.origin) > 0.025, "native engine frames advance the workshop orbit")
	await _mouse_motion(_pick_point("passive"))
	var held: Transform3D = garage.stage.camera.global_transform
	await create_timer(1.0).timeout
	check(garage.stage.camera.global_transform.is_equal_approx(held), "native GUI hover holds the camera")
	await _mouse_motion(Vector2(640, 555))
	await create_timer(2.0).timeout
	check(garage.stage.camera.global_position.distance_to(held.origin) > 0.005, "native frames resume the camera after hover")
	_pause()


func _pick_point(category: String) -> Vector2:
	var provider = garage.stage.weapon_rack if category == "weapon" else garage.stage.module_stations
	var bounds: AABB = provider.bounds(category)
	var candidates: Array[Vector3] = [bounds.get_center()]
	for corner in 8:
		candidates.append(bounds.get_endpoint(corner).lerp(bounds.get_center(), 0.15))
	for point in candidates:
		var screen := _project(point)
		if garage._pick_station(screen) == category:
			return screen
	return Vector2(-1, -1)


func _project(point: Vector3) -> Vector2:
	return garage.stage.camera.unproject_position(point) * garage.stage.size / Vector2(garage.stage.viewport.size)


func _mouse_motion(point: Vector2, dragging: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(100, 0) if dragging else Vector2.ZERO
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	root.push_input(event, true)
	await process_frame


func _press(point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 0
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
	await process_frame


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
