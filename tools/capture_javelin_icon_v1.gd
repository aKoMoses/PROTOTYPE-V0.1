extends SceneTree

## Native captures of the selected icon, using isolated garage saves.
const ICONS := preload("res://scripts/equipment_icons.gd")
const GARAGE := preload("res://scripts/forge_garage.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const OUTPUT := "res://captures/javelin-icon-v1/"
var failures: Array[String] = []
var save_paths: Array[String] = []
var before_saves: Dictionary = {}
var frames: Array[String] = []

class ScaleSheet extends Control:
	var icons := ICONS.new()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color("#171d20"))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(44, 56), "JAVELIN · MÉTAL ILLUSTRÉ · TAILLES NATIVES", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#eee5ce"))
		draw_texture_rect(icons.get_icon("javelin"), Rect2(42, 118, 420, 420), false)
		for index in 3:
			var extent: float = [32.0, 48.0, 64.0][index]
			var at := Vector2(570 + index * 200, 200)
			draw_texture_rect(icons.get_icon("javelin"), Rect2(at, Vector2.ONE * extent), false)
			draw_string(font, at + Vector2(0, 100), "%d px" % int(extent), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#eee5ce"))
			draw_texture_rect(icons.get_cooldown_icon("javelin"), Rect2(at + Vector2(0, 180), Vector2.ONE * extent), false)
		draw_string(font, Vector2(570, 505), "Recharge : silhouette et transparence identiques", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#c6b596"))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).store_string("\n")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	root.get_node("FramePacing").hide()
	for path in [LIBRARY.SAVE_PATH, LOADOUT.SAVE_PATH]:
		before_saves[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	var sheet := ScaleSheet.new()
	root.add_child(sheet)
	await _capture("01-native-sizes")
	sheet.queue_free()
	await process_frame
	var garage := GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	save_paths = ["user://javelin-icon-" + suffix + ".cfg", "user://javelin-icon-legacy-" + suffix + ".cfg"]
	garage.library_path = save_paths[0]
	garage.legacy_save_path = save_paths[1]
	root.add_child(garage)
	await _settle()
	garage._open_station("offensive")
	garage.focus.advance(1.0)
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)
	await _capture("02-garage-catalog")
	garage._preview_equipment("offensive", "javelin")
	garage.focus.advance(1.0)
	await _capture("03-garage-detail")
	var garage_icon: TextureRect = garage._choices.offensive.javelin.get_node("EquipmentIcon")
	_check(garage_icon.texture.get_meta("source_path", "") == "res://art/icons/illustrated-metal/javelin.png", "garage uses the approved icon")
	_check(garage_icon.size == Vector2(48, 48), "desktop garage icon remains 48 pixels")
	garage.queue_free()
	await _settle()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle()
	var flow: Node = scene.get_node("Interface")
	var build := LOADOUT.defaults()
	build.merge({"offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots"}, true)
	flow.set("loadout", build)
	scene.call("start_duel", build)
	flow.call("_show_screen", 3)
	flow.call("_begin_round_countdown")
	flow.call("_begin_live_round")
	var player: Node = scene.get_node("Player")
	var target: Node = scene.get_node("TargetDummy")
	target.call("set_training_bot_enabled", false)
	player.set_physics_process(false)
	target.set_physics_process(false)
	await _capture("04-combat-ready")
	var hud: Dictionary = flow.get("_hud_labels")
	_check(hud.offensive_icon.texture.get_meta("source_path", "") == "res://art/icons/illustrated-metal/javelin.png", "combat uses the approved icon")
	_check(hud.offensive_icon.size == Vector2(48, 48), "combat icon remains 48 pixels")
	player.set("_module_cooldowns", {"javelin": 8.4})
	await _capture("05-combat-cooldown")
	var controls: Node = scene.get_node("Interface/TouchControls")
	controls.call("set_editor_test", true)
	controls.call("set_player", player)
	await _capture("06-touch-cooldown")
	player.set("_module_cooldowns", {})
	await create_timer(1.0).timeout
	await _capture("07-touch-ready")
	target.call("apply_javelin_mark", 10.0)
	player.set("_javelin_mark_target", target)
	player.set("_javelin_active_mark_duration", 10.0)
	await _capture("08-recast")
	_check(hud.offensive_icon.texture.resource_path == "res://art/ui/icons/javelin-recast.svg", "recast retains its distinct teleport cue")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await _settle()
	for path in before_saves:
		var after = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		_check(after == before_saves[path], "capture preserves the player's save: " + path)
	for path in save_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	FileAccess.open(OUTPUT + "verification.json", FileAccess.WRITE).store_string(JSON.stringify({"failures": failures, "frames": frames}, "\t"))
	for failure in failures:
		push_error(failure)
	print("JAVELIN ILLUSTRATED ICON CAPTURE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _settle() -> void:
	for frame in 8:
		await process_frame

func _capture(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK, "save capture: " + label)
	frames.append(label)
	print("JAVELIN ICON FRAME: ", label)
