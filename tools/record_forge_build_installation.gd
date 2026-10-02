extends SceneTree

## Native recording of the actual five-second save, with isolated build files.
const GARAGE := preload("res://scripts/forge_garage.gd")
const PATHS := ["user://garage-movie-builds.cfg", "user://garage-movie-loadout.cfg"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	var garage := GARAGE.new()
	garage.library_path = PATHS[0]
	garage.legacy_save_path = PATHS[1]
	root.add_child(garage)
	current_scene = garage
	await process_frame
	garage._select_equipment("robot", "agile")
	garage._select_equipment("passive", "alternator")
	garage.build_name = "ÉCLAIREUR"
	garage._refresh_build_names()
	await create_timer(0.9).timeout
	garage._save_button.pressed.emit()
	await garage.installation.completed
	if garage.is_dirty() or not garage._ui.visible or garage.installation.scanned_parts.size() < 3:
		push_error("GARAGE BUILD MOVIE: installation incomplete")
		quit(1)
		return
	print("GARAGE BUILD MOVIE: PASS duration=", garage.installation.elapsed, " scanned=", garage.installation.scanned_parts)
	await create_timer(0.9).timeout
	for path in PATHS:
		DirAccess.remove_absolute(path)
	root.get_node("GameSfx").call("clear")
	await create_timer(0.15).timeout
	quit()
