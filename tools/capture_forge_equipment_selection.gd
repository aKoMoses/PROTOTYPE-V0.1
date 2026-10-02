extends SceneTree

## Native forge UI evidence. Isolated build paths preserve the user's draft.
## Run after imports without --headless; captures include the real interface.
const GARAGE := preload("res://scripts/forge_garage.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const OUTPUT := "res://captures/forge-equipment-selection/"
const KIT := {
	"robot": "polyvalent", "weapon": "blaster", "mobility": "pyro_boots",
	"offensive": "rocket_basket", "defensive": "magnetic_field", "passive": "auxiliary_reactor",
}
var garage
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var real_files: Dictionary = {}
var temporary_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	if ignore != null:
		ignore.store_string("\n")
	for path in [LOADOUT.SAVE_PATH, LIBRARY.SAVE_PATH]:
		real_files[path] = {"existed": FileAccess.file_exists(path), "bytes": _bytes(path)}
	var suffix := str(Time.get_ticks_usec())
	temporary_paths = ["user://forge-selection-capture-" + suffix + "-builds.cfg", "user://forge-selection-capture-" + suffix + "-loadout.cfg"]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	garage.library_path = temporary_paths[0]
	garage.legacy_save_path = temporary_paths[1]
	root.add_child(garage)
	for frame in 5:
		await process_frame
	garage.stage.set_process(false)
	garage.stage.automatic_service_enabled = false
	garage.stage.arm.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage.installation.set_process(false)
	garage.stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	garage.stage.viewport.msaa_3d = Viewport.MSAA_4X
	garage.set_loadout(KIT)
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = dimensions
		for frame in 4:
			await process_frame
		garage._show_garage(false)
		garage.focus.advance(1.1)
		await _capture("hub", dimensions)
		garage._open_modules("mobility")
		garage.focus.advance(1.1)
		garage._preview_equipment("mobility", "bio_injector")
		await _capture("modules-mobility", dimensions)
		garage._open_weapon_rack()
		garage.focus.advance(1.1)
		garage._preview_equipment("weapon", "longshot")
		await _capture("weapon-rack", dimensions)
		garage._navigate("ROBOT")
		garage.focus.advance(1.1)
		await _capture("robot-kit", dimensions)
	var manifest := FileAccess.open(OUTPUT + "capture-manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"loadout": KIT, "frames": frames}, "\t") + "\n")
	else:
		failures.append("capture manifest could not be saved")
	garage.queue_free()
	for frame in 4:
		await process_frame
	for path in real_files:
		if FileAccess.file_exists(path) != real_files[path].existed or _bytes(path) != real_files[path].bytes:
			failures.append("user save changed: " + path)
			_restore(path, real_files[path])
	for path in temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("FORGE EQUIPMENT SELECTION CAPTURE: ", "PASS" if failures.is_empty() else "FAIL", " (", frames.size(), " native UI frames)")
	quit(0 if failures.is_empty() else 1)


func _capture(label: String, dimensions: Vector2i) -> void:
	# Catalog fades belong to the actual UI. Let them finish before recording.
	await create_timer(0.40).timeout
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var filename := label + "-" + str(dimensions.x) + ".png"
	if pixels.get_size() != dimensions:
		failures.append("unexpected native screenshot size: " + filename)
	var result := pixels.save_png(OUTPUT + filename)
	if result != OK:
		failures.append("screenshot could not be saved: " + filename)
	if garage.loadout != KIT or garage.module_installation.active:
		failures.append("preview altered the build or started installation: " + filename)
	frames.append({"file": filename, "size": [dimensions.x, dimensions.y], "category": garage._category, "preview": garage._preview_id})
	print("FORGE EQUIPMENT SELECTION CAPTURE ", filename, " result=", result)


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


func _restore(path: String, backup: Dictionary) -> void:
	if not backup.existed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(backup.bytes)
		file.close()
