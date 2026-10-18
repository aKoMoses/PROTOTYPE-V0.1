extends SceneTree

## Render the actual shared textures and garage/HUD, without changing real saves.
const ICONS := preload("res://scripts/equipment_icons.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const OUTPUT := "res://captures/illustrated-equipment/"
const ART := "res://art/icons/illustrated-metal/"
var failures: Array[String] = []
var frames: Array[String] = []
var checks := 0

class Gallery extends Control:
	var icons := ICONS.new()
	var raw := false
	var textures: Dictionary = {}
	var identifiers: Array = []
	func _ready() -> void:
		for id in LOADOUT.WEAPONS + LOADOUT.OFFENSIVE + LOADOUT.DEFENSIVE + LOADOUT.MOBILITY + LOADOUT.PASSIVES:
			if raw:
				var path := ART + str(id) + ".png"
				if not FileAccess.file_exists(path):
					continue
				textures[id] = ImageTexture.create_from_image(Image.load_from_file(path))
			else:
				textures[id] = icons.get_icon(id)
			identifiers.append(id)
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var cream := Color("#eee5ce")
		draw_rect(Rect2(0, 0, 1920, 1080), Color("#171d20"))
		draw_string(font, Vector2(32, 46), "ARMES & MODULES · MÉTAL ILLUSTRÉ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, cream)
		draw_string(font, Vector2(1390, 43), "ART EN COURS" if raw else "APERÇUS NATIFS · 48 px / 32 px / RECHARGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c6b596"))
		for index in identifiers.size():
			var id: String = identifiers[index]
			var at := Vector2(28 + (index % 6) * 316, 70 + (index / 6) * 246)
			draw_style_box(_tile_style(), Rect2(at, Vector2(300, 232)))
			var texture: Texture2D = textures[id]
			draw_texture_rect(texture, Rect2(at + Vector2(64, 0), Vector2(172, 172)), false)
			var label := LOADOUT.display_name(id).replace("BAROUD D’HONNEUR", "BAROUD").replace("RÉACTEUR AUXILIAIRE", "RÉACTEUR AUX.")
			draw_string(font, at + Vector2(12, 188), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, cream)
			draw_texture_rect(texture, Rect2(at + Vector2(12, 191), Vector2(36, 36)), false)
			if not raw:
				draw_texture_rect(texture, Rect2(at + Vector2(82, 181), Vector2(48, 48)), false)
				draw_texture_rect(texture, Rect2(at + Vector2(163, 197), Vector2(32, 32)), false)
				draw_texture_rect(icons.get_cooldown_icon(id), Rect2(at + Vector2(235, 181), Vector2(48, 48)), false)
	func _tile_style() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#20292e")
		style.border_color = Color("#584a39")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		return style

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).store_string("\n")
	root.get_node("FramePacing").hide()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	var gallery := Gallery.new()
	gallery.raw = "--raw" in OS.get_cmdline_user_args()
	root.add_child(gallery)
	await _capture("art-progress" if gallery.raw else "01-collection")
	if gallery.raw or "--gallery-only" in OS.get_cmdline_user_args():
		quit()
		return
	gallery.queue_free()
	await _settle()
	var icons := ICONS.new()
	for id in LOADOUT.WEAPONS + LOADOUT.OFFENSIVE + LOADOUT.DEFENSIVE + LOADOUT.MOBILITY + LOADOUT.PASSIVES:
		var ready: Texture2D = icons.get_icon(id)
		var grey: Texture2D = icons.get_cooldown_icon(id)
		_check(ready != null and grey != null, "icon loads: " + id)
		_check(ready.get_size() == grey.get_size(), "cooldown preserves size: " + id)
		_check(icons.get_cooldown_icon(id) == grey, "grayscale is cached: " + id)
		var normal_image := ready.get_image()
		var grey_image := grey.get_image()
		_check(normal_image.get_size() == grey_image.get_size(), "pixel dimensions match: " + id)
		for y in range(0, normal_image.get_height(), 13):
			for x in range(0, normal_image.get_width(), 13):
				_check(is_equal_approx(normal_image.get_pixel(x, y).a, grey_image.get_pixel(x, y).a), "alpha stays aligned: " + id)
	var original_saves: Dictionary = {}
	for path in [LIBRARY.SAVE_PATH, LOADOUT.SAVE_PATH]:
		original_saves[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	root.size = Vector2i(1280, 720)
	var garage_script = load("res://scripts/forge_garage.gd")
	if garage_script == null or not garage_script.can_instantiate():
		push_error("Garage could not compile; shared art can still be checked with --gallery-only.")
		quit(1)
		return
	var garage = garage_script.new()
	var suffix := str(Time.get_ticks_usec())
	var isolated := ["user://metal-icons-" + suffix + ".cfg", "user://metal-icons-legacy-" + suffix + ".cfg"]
	garage.library_path = isolated[0]
	garage.legacy_save_path = isolated[1]
	root.add_child(garage)
	await _settle()
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		garage._open_station(category)
		garage.focus.advance(1.0)
		garage.stage.set_process(false)
		garage.focus.set_process(false)
		garage.installation.set_process(false)
		garage.module_installation.set_process(false)
		await _capture("02-garage-" + category)
		for button: Button in garage._choices[category].values():
			_check(button.get_node("EquipmentIcon").texture != null, "catalog has texture: " + str(button.name))
	garage.queue_free()
	await _settle()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle()
	var flow: Node = scene.get_node("Interface")
	var player: Node = scene.get_node("Player")
	var target: Node = scene.get_node("TargetDummy")
	var controls: Node = scene.get_node("Interface/TouchControls")
	var builds := [
		{"weapon": "blaster", "offensive": "rocket_basket", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "baroud"},
		{"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"},
		{"weapon": "mekatana", "offensive": "fulguro_punch", "defensive": "projector", "mobility": "permutation", "passive": "auxiliary_reactor"},
		{"weapon": "longshot", "offensive": "pelto_smash", "defensive": "counter", "mobility": "eclipse", "passive": "tracker"},
	]
	for index in builds.size():
		var build := LOADOUT.defaults()
		build.merge(builds[index], true)
		flow.set("loadout", build)
		scene.call("start_duel", build)
		flow.call("_show_screen", 3)
		flow.call("_begin_round_countdown")
		flow.call("_begin_live_round")
		target.call("set_training_bot_enabled", false)
		player.set_physics_process(false)
		target.set_physics_process(false)
		controls.call("set_editor_test", index == 0 or index == 3)
		controls.call("set_player", player)
		await _capture("03-combat-%d-ready" % index)
		var cooldowns := {"pyro_boots_reserve": 5.0}
		for category in ["offensive", "defensive", "mobility"]:
			cooldowns[build[category]] = 5.0
		player.set("_module_cooldowns", cooldowns)
		await _capture("04-combat-%d-cooldown" % index)
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await _settle()
	set_meta("garage_test_loadout", builds[2])
	var training: Node = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(training)
	current_scene = training
	await _settle()
	training.get_node("Player").set_physics_process(false)
	await _capture("05-training")
	training.queue_free()
	await _settle()
	for path in original_saves:
		var after = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		_check(after == original_saves[path], "player save preserved: " + path)
	for path in isolated:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	FileAccess.open(OUTPUT + "verification.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "frames": frames}, "\t"))
	for failure in failures:
		push_error(failure)
	print("ILLUSTRATED EQUIPMENT CAPTURE: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value and not message in failures:
		failures.append(message)

func _settle() -> void:
	for frame in 8:
		await process_frame

func _capture(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK, "capture: " + label)
	frames.append(label)
	print("ILLUSTRATED EQUIPMENT FRAME: ", label)
