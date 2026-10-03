extends SceneTree

## Real GPU views of the wall hooks, charging tray and their pickup poses.
const GARAGE := preload("res://scripts/forge_garage.gd")
var output := "res://captures/forge-finishes/" if "--finishes" in OS.get_cmdline_user_args() else "res://captures/forge-wall-storage/"
var garage
var failures: Array[String] = []
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open(output + ".gdignore", FileAccess.WRITE)
	ignore.store_string("\n")
	ignore.close()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://forge-wall-capture-" + suffix + ".cfg", "user://forge-wall-capture-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	for frame in 5:
		await process_frame
	garage.stage.automatic_service_enabled = false
	garage.stage.arm.set_process(false)
	garage.stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if not "--finishes" in OS.get_cmdline_user_args():
		garage.stage.viewport.msaa_3d = Viewport.MSAA_4X
	_pause()
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(2340, 1080)]:
		root.size = dimensions
		for frame in 4:
			await process_frame
		_pause()
		garage._show_garage(false)
		garage.focus.advance(1.1)
		await _capture("garage-" + str(dimensions.x))
		for category in (["weapon", "passive", "offensive", "defensive", "mobility"] if "--finishes" in OS.get_cmdline_user_args() else ["weapon", "passive"]):
			garage._open_station(category)
			garage.focus.advance(1.1)
			await _capture(category + "-" + str(dimensions.x))
	root.size = Vector2i(1280, 720)
	for frame in 4:
		await process_frame
	_pause()
	for id in ["longshot", "blaster", "auxiliary_reactor"]:
		var category := "passive" if id == "auxiliary_reactor" else "weapon"
		var draft: Dictionary = garage.loadout.duplicate(true)
		draft[category] = ("longshot" if id == "blaster" else "blaster") if category == "weapon" else "baroud"
		garage.set_loadout(draft)
		garage._open_station(category)
		garage.focus.advance(1.1)
		garage._select_equipment(category, id)
		_pause()
		var captured := false
		var clearance := true
		for frame in 900:
			garage.module_installation.advance(1.0 / 60.0)
			if category == "weapon" and garage.module_installation.active:
				var carriage: Node3D = garage.module_installation._carriage
				var box: AABB = carriage.global_transform * garage.stage._bounds(carriage)
				clearance = clearance and box.position.x > -7.39 and box.end.x < 8.74 and box.position.z > -5.40
				clearance = clearance and not box.intersects(garage.stage.module_stations.bounds("defensive"))
			if garage.module_installation.phase == "lift" and not captured:
				await _capture(id + "-pickup")
				captured = true
			if not garage.module_installation.active:
				break
		if not captured or str(garage.loadout[category]) != id:
			failures.append("pickup did not complete: " + id)
		if not clearance:
			failures.append("carriage crossed a wall or the defensive cabinet: " + id)
		garage.module_installation.cancel()
		_pause()
	garage.queue_free()
	await process_frame
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("FORGE WALL STORAGE CAPTURE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)


func _capture(label: String) -> void:
	await create_timer(0.35).timeout
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var result := pixels.save_png(output + label + ".png")
	if result != OK:
		failures.append("could not save: " + label)
	print("WALL STORAGE FRAME ", label, " ", pixels.get_size(), " result=", result)
