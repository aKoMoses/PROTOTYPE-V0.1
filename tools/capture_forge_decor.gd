extends SceneTree

## Actual garage at desktop/phone logical sizes, isolated from personal saves.
const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-decor/"
var garage
var paths: Array[String] = []
var failures: Array[String] = []
var checks := 0

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
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://forge-decor-" + suffix + ".cfg", "user://forge-decor-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	for frame in 5:
		await process_frame
	var before: Dictionary = garage.loadout.duplicate(true)
	var distances: Dictionary = {}
	for profile in [{"id": "pc-1280", "size": Vector2i(1280, 720)}, {"id": "pc-1920", "size": Vector2i(1920, 1080)}, {"id": "phone-844", "size": Vector2i(844, 390)}, {"id": "phone-667", "size": Vector2i(667, 375)}]:
		root.size = profile.size
		for frame in 6:
			await process_frame
		garage.safe_area_override = Rect2(59, 0, 726, 369) if profile.id == "phone-844" else Rect2()
		garage._show_garage(false)
		garage.focus._desktop_zoom = 1.0
		garage.focus._desktop_zoom_goal = 1.0
		garage.focus.advance(0.0)
		_pause()
		distances[profile.id] = garage.stage.camera.global_position.distance_to(garage.stage.robot.global_position)
		_check_robot(profile.id)
		await _capture(profile.id)
		if garage.has_method("_show_entry"):
			garage._show_entry(false)
			garage.focus.advance(0.0)
			_pause()
			_check_robot(profile.id + "-entry")
			await _capture(profile.id + "-entry")
			garage._show_garage(false)
			garage.focus.advance(0.0)
			_pause()
		if profile.id in ["pc-1280", "phone-844"] and not "--overview" in OS.get_cmdline_user_args():
			for category in ["weapon", "passive", "offensive", "defensive", "mobility"]:
				garage._open_station(category)
				garage.focus.advance(0.95)
				_pause()
				await _capture(profile.id + "-" + category)
			garage._show_garage(false)
			garage.focus.advance(0.0)
			_pause()
			garage.stage.begin_robot_rotation()
			garage.stage.rotate_robot(0.7)
			garage.stage.end_robot_rotation()
			_check_robot(profile.id + "-rotated")
			garage.stage.robot.rotation.y = garage.stage.ROBOT_YAW
		await _exercise_controls(profile.id)
		if not garage._compact_layout:
			await _capture(profile.id + "-wide")
	if distances["pc-1280"] <= distances["phone-844"] * 1.3:
		failures.append("desktop must expose substantially more workshop than phone")
	if before != garage.loadout:
		failures.append("capture changed the draft")
	print("DECOR DISTANCES ", distances)
	var surfaces := 0
	var triangles := 0
	for child in garage.stage.world.find_children("*", "MeshInstance3D", true, false):
		if child.name not in ["WorkshopStaticMesh", "WorkshopWindowGlass"]:
			continue
		surfaces += child.mesh.get_surface_count()
		for surface in child.mesh.get_surface_count():
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size() / 3
	print("DECOR GEOMETRY surfaces=", surfaces, " triangles=", triangles)
	garage.queue_free()
	await process_frame
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("FORGE DECOR CAPTURE: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " interaction checks)")
	quit(0 if failures.is_empty() else 1)

func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)

func _check_robot(label: String) -> void:
	var bounds: AABB = garage.stage.robot.global_transform * garage.stage._robot_pick_bounds
	var safe: Rect2 = garage.focus.frame_rect().grow(2)
	for corner in 8:
		var point := bounds.get_endpoint(corner)
		var screen: Vector2 = garage.stage.camera.unproject_position(point) * garage.stage.size / Vector2(garage.stage.viewport.size)
		if garage.stage.camera.is_position_behind(point) or not safe.has_point(screen):
			failures.append("hero outside usable view: " + label)
			break

func _capture(label: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	if pixels.save_png(OUTPUT + label + ".png") != OK:
		failures.append("cannot save " + label)
	print("DECOR FRAME ", label, " camera=", garage.stage.camera.global_position)

func _exercise_controls(label: String) -> void:
	garage._show_garage(false)
	garage.focus.advance(0.0)
	_pause()
	var point: Vector2 = garage.stage.camera.unproject_position(garage.stage.robot.global_position + Vector3(0, 1.35, 0)) * garage.stage.size / Vector2(garage.stage.viewport.size)
	var yaw: float = garage.stage.robot.rotation.y
	var pressed := InputEventMouseButton.new()
	pressed.position = point
	pressed.global_position = point
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	root.push_input(pressed, true)
	await process_frame
	_check(garage.stage._rotating_robot, "real mouse picks the robot: " + label)
	var held: Transform3D = garage.stage.camera.global_transform
	var drag := InputEventMouseMotion.new()
	drag.position = point + Vector2(70, 0)
	drag.global_position = drag.position
	drag.relative = Vector2(70, 0)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	await process_frame
	for frame in 30:
		garage.focus.advance(1.0 / 60.0)
	_check(absf(angle_difference(yaw, garage.stage.robot.rotation.y)) > 0.2, "real drag rotates robot: " + label)
	_check(garage.stage.camera.global_transform.is_equal_approx(held), "camera waits throughout drag: " + label)
	pressed.pressed = false
	pressed.position = drag.position
	pressed.global_position = drag.position
	root.push_input(pressed, true)
	await process_frame
	garage.stage.robot.rotation.y = yaw
	_check(not garage.stage._rotating_robot, "release stops drag: " + label)
	if garage._compact_layout:
		await _exercise_touch(point, label)
	var zoom_point: Vector2 = garage.focus.frame_rect().get_center()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = zoom_point
	wheel.global_position = zoom_point
	for click in 6:
		root.push_input(wheel, true)
		await process_frame
	for frame in 120:
		garage.focus.advance(1.0 / 60.0)
	_check(is_equal_approx(garage.focus._desktop_zoom_goal, 1.0 if garage._compact_layout else 1.5), "wheel uses desktop only, bounded zoom: " + label)
	if not garage._compact_layout:
		var wide: Transform3D = garage.stage.camera.global_transform
		var drawn: Vector2 = garage.stage.camera.unproject_position(garage.stage.robot.global_position + Vector3(0, 1.35, 0)) * garage.stage.size / Vector2(garage.stage.viewport.size)
		_check(garage.stage.is_robot_at_position(drawn), "robot remains pickable after pulling back: " + label)
		garage.focus.set_station_hovered(true)
		for frame in 120:
			garage.focus.advance(1.0 / 60.0)
		_check(garage.stage.camera.global_position.distance_to(wide.origin) < 0.001, "hover freezes orbit after zoom settles: " + label)
		garage.focus.set_station_hovered(false)
	# Header/UI scrolling must never pull the scene away from its selected view.
	var goal: float = garage.focus._desktop_zoom_goal
	wheel.position = Vector2(40, 25)
	wheel.global_position = wheel.position
	root.push_input(wheel, true)
	await process_frame
	_check(is_equal_approx(garage.focus._desktop_zoom_goal, goal), "wheel over UI leaves scene unchanged: " + label)
	garage.hide()
	await process_frame
	_check(not garage.focus.is_processing() and not garage.stage.is_processing(), "hidden garage stops rendering work: " + label)
	garage.show()
	await process_frame
	garage._show_garage(false)
	_pause()
	garage.focus.advance(0.0)

func _exercise_touch(point: Vector2, label: String) -> void:
	var yaw: float = garage.stage.robot.rotation.y
	var held: Transform3D = garage.stage.camera.global_transform
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = true
	root.push_input(touch, true)
	await process_frame
	_check(garage.stage._rotating_robot, "touch picks the robot: " + label)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point + Vector2(55, 0)
	drag.relative = Vector2(55, 0)
	root.push_input(drag, true)
	await process_frame
	garage.focus.advance(0.1)
	_check(absf(angle_difference(yaw, garage.stage.robot.rotation.y)) > 0.2, "touch rotates the robot: " + label)
	_check(garage.stage.camera.global_transform.is_equal_approx(held), "phone camera waits during touch: " + label)
	touch.pressed = false
	touch.position = drag.position
	root.push_input(touch, true)
	await process_frame
	_check(not garage.stage._rotating_robot, "touch release restores the view: " + label)
	garage.stage.robot.rotation.y = yaw

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
