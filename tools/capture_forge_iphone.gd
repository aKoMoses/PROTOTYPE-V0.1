extends SceneTree

## PC framing/readability audit at representative iPhone logical landscape sizes.
## No device emulation, iOS performance claims, or changes to the player's saves.
const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/forge-iphone/"
const PROFILES := [
	{"id": "compact", "title": "Compact", "width": 667, "height": 375, "safe_side": 0, "safe_bottom": 0},
	{"id": "standard", "title": "Standard", "width": 844, "height": 390, "safe_side": 59, "safe_bottom": 21},
	{"id": "large", "title": "Grand", "width": 932, "height": 430, "safe_side": 59, "safe_bottom": 21},
]
const CATEGORIES := ["weapon", "passive", "offensive", "defensive", "mobility"]
var garage
var paths: Array[String] = []
var failures: Array[String] = []
var checks := 0
var report: Dictionary = {"kind": "pc-logical-size-audit", "profiles": [], "checks": 0, "failures": []}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	ignore.store_string("\n")
	ignore.close()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(844, 390)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://forge-iphone-" + suffix + ".cfg", "user://forge-iphone-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	for frame in 5:
		await process_frame
	_pause()
	var original: Dictionary = garage.loadout.duplicate(true)
	for profile: Dictionary in PROFILES:
		root.size = Vector2i(profile.width, profile.height)
		for frame in 5:
			await process_frame
		garage._show_garage(false)
		garage.focus.advance(0.0)
		_pause()
		var result: Dictionary = profile.duplicate(true)
		result["frames"] = []
		result["stations"] = []
		result["actual_window"] = [root.size.x, root.size.y]
		_check(root.size == Vector2i(profile.width, profile.height), "window size: " + str(profile.id))
		result.frames.append(await _capture(profile, "garage"))
		for category: String in CATEGORIES:
			garage._show_garage(false)
			garage.focus.advance(0.0)
			_pause()
			var point := _pick_point(category)
			var provider = garage.stage.weapon_rack if category == "weapon" else garage.stage.module_stations
			var bounds: AABB = provider.bounds(category)
			var rect := _projected_rect(bounds)
			result.stations.append({"category": category, "rect": _rect_data(rect), "center_pick": [point.x, point.y]})
			_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect), "station framing: " + str(profile.id) + "/" + category)
			await _touch(point, true)
			await _touch(point, false)
			garage.focus.advance(0.95)
			_pause()
			_check(garage._category == category and garage.focus.zone == "station", "raw station touch: " + str(profile.id) + "/" + category)
			result.frames.append(await _capture(profile, category))
		# Check a GUI row selection separately from the direct 3D touch handlers.
		garage._preview_equipment("passive", "baroud")
		garage._open_station("passive")
		garage.focus.advance(0.95)
		_pause()
		garage._preview_equipment("passive", "baroud")
		var before: Dictionary = garage.loadout.duplicate(true)
		var row: Button = garage._choices.passive.omnivamp
		var row_center := _control_rect(row).get_center()
		await _touch(row_center, true, true)
		await _touch(row_center, false, true)
		_check(garage._preview_id == "omnivamp", "touch-emulated GUI row selects preview: " + str(profile.id))
		_check(garage.loadout == before, "row preview does not equip: " + str(profile.id))
		garage._preview_equipment("passive", "baroud")
		var scroll := garage._detail_description.get_parent() as ScrollContainer
		var scroll_center := _control_rect(scroll).get_center()
		await _touch(scroll_center + Vector2(0, 20), true)
		for step in 5:
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			drag.position = scroll_center + Vector2(0, 20 - (step + 1) * 9)
			drag.relative = Vector2(0, -9)
			root.push_input(drag, true)
			await process_frame
		await _touch(scroll_center + Vector2(0, -25), false)
		result["raw_touch_scroll_offset"] = scroll.scroll_vertical
		# Native Windows isn't a touch OS; record this separately from geometric findings.
		scroll.scroll_vertical = 0
		result["robot_rect"] = _rect_data(_projected_rect(garage.stage.robot.global_transform * garage.stage._robot_pick_bounds))
		garage._show_garage(false)
		garage.focus.advance(0.0)
		_pause()
		result["robot_overview_rect"] = _rect_data(_projected_rect(garage.stage.robot.global_transform * garage.stage._robot_pick_bounds))
		_check(garage.loadout == original, "audit preserves equipment: " + str(profile.id))
		report.profiles.append(result)
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(OUTPUT + "audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	garage.queue_free()
	for frame in 4:
		await process_frame
	# Let transient UI click sounds complete before shutting down the engine.
	await create_timer(0.25).timeout
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("FORGE IPHONE AUDIT: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks; ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)


func _capture(profile: Dictionary, view: String) -> Dictionary:
	# Settle the catalog's UI fade as well as the manually advanced camera.
	await create_timer(0.3).timeout
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var filename := str(profile.id) + "-" + view + ".png"
	_check(pixels.get_size() == Vector2i(profile.width, profile.height), "capture dimensions: " + filename)
	_check(pixels.save_png(OUTPUT + filename) == OK, "capture saved: " + filename)
	var safe := Rect2(profile.safe_side, 0, profile.width - profile.safe_side * 2, profile.height - profile.safe_bottom)
	var buttons: Array[Dictionary] = []
	for child in garage._ui.find_children("*", "BaseButton", true, false):
		var button := child as BaseButton
		if not button.is_visible_in_tree():
			continue
		var label := String(button.get("text")) if button is Button else String(button.name)
		if label.is_empty():
			for sub in button.get_children():
				if sub is Label:
					label = sub.text
					break
		var rect := _control_rect(button)
		buttons.append({"label": label, "rect": _rect_data(rect), "under_44pt": rect.size.x < 44.0 or rect.size.y < 44.0, "outside_assumed_safe_area": not safe.encloses(rect), "disabled": button.disabled})
	var result := {"view": view, "file": filename, "scale": garage._ui.scale.y, "buttons": buttons, "description_font_pt": _font_size(garage._detail_description), "nav_font_pt": _font_size(garage._nav.ARMES), "row_title_font_pt": 14.0 * garage._ui.scale.y, "row_subtitle_font_pt": 13.0 * garage._ui.scale.y, "save_button_rect": _rect_data(_control_rect(garage._save_button)), "nav_button_rect": _rect_data(_control_rect(garage._nav.ARMES))}
	print("IPHONE FRAME ", filename, " ui-scale=", garage._ui.scale.y, " body-size=", result.description_font_pt)
	return result


func _font_size(control: Control) -> float:
	return control.get_theme_font_size("font_size") * control.get_global_transform().get_scale().y


func _control_rect(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)


func _rect_data(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _project(point: Vector3) -> Vector2:
	return garage.stage.camera.unproject_position(point) * garage.stage.size / Vector2(garage.stage.viewport.size)


func _projected_rect(box: AABB) -> Rect2:
	var result := Rect2(_project(box.get_endpoint(0)), Vector2.ZERO)
	for corner in range(1, 8):
		result = result.expand(_project(box.get_endpoint(corner)))
	return result


func _pick_point(category: String) -> Vector2:
	var provider = garage.stage.weapon_rack if category == "weapon" else garage.stage.module_stations
	var bounds: AABB = provider.bounds(category)
	var candidates: Array[Vector3] = [bounds.get_center()]
	for corner in 8:
		candidates.append(bounds.get_endpoint(corner).lerp(bounds.get_center(), 0.15))
	for point: Vector3 in candidates:
		var screen := _project(point)
		if garage._pick_station(screen) == category:
			return screen
	return Vector2(-1, -1)


func _touch(point: Vector2, pressed: bool, emulate_button: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)
	# Window.push_input bypasses platform-generated mouse-from-touch events.
	# Send the companion event explicitly for BaseButton controls on Windows.
	if emulate_button:
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.position = point
		mouse.global_position = point
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mouse, true)
	await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
