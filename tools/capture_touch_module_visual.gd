extends SceneTree

const ICONS := preload("res://scripts/equipment_icons.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const OUTPUT := "res://captures/module-buttons/"

class IconSheet extends Control:
	var icons := ICONS.new()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color("#142029"))
		draw_string(ThemeDB.fallback_font, Vector2(30, 36), "MODULES · MÉTAL IVOIRE / CUIVRE / ÉNERGIE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#f3ddbb"))
		var identifiers: Array = LOADOUT.OFFENSIVE + LOADOUT.DEFENSIVE + LOADOUT.MOBILITY + LOADOUT.PASSIVES
		for index in range(identifiers.size()):
			var at := Vector2(30 + (index % 6) * 205, 57 + (index / 6) * 213)
			draw_rect(Rect2(at, Vector2(192, 200)), Color("#1b2c36"))
			var texture: Texture2D = icons.get_icon(identifiers[index])
			draw_texture_rect(texture, Rect2(at + Vector2(29, 6), Vector2(134, 134)), false)
			# Verify the same silhouette at the actual phone button size.
			draw_texture_rect(texture, Rect2(at + Vector2(8, 144), Vector2(42, 42)), false)
			var label := LOADOUT.display_name(identifiers[index])
			var font := ThemeDB.fallback_font
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, at + Vector2(117 - width * 0.5, 170), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f3ddbb"))

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var sheet := IconSheet.new()
	root.add_child(sheet)
	await save("icons")
	sheet.queue_free()
	await process_frame
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var build := {"weapon": "blaster", "offensive": "pelto_smash", "defensive": "projector", "mobility": "eclipse", "passive": "omnivamp"}
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
	var controls: Node = scene.get_node("Interface/TouchControls")
	controls.call("set_editor_test", true)
	controls.call("set_player", player)
	await save("ready")
	player.set("_module_cooldowns", {"pelto_smash": 7.5, "projector": 3.0, "eclipse": 2.5})
	await save("cooldown")
	player.set("_module_cooldowns", {})
	await save("recovered")
	player.call("apply_loadout", {"offensive": "javelin", "defensive": "counter", "mobility": "pyro_boots", "passive": "baroud"})
	player.set("_module_cooldowns", {"javelin": 5.0, "counter": 4.0, "pyro_boots": 2.0})
	await save("pyro_one_charge")
	player.set("_module_cooldowns", {"javelin": 5.0, "counter": 4.0, "pyro_boots": 2.0, "pyro_boots_reserve": 4.0})
	await save("pyro_empty")
	player.set("_module_cooldowns", {"javelin": 5.0, "counter": 4.0, "pyro_boots_reserve": 2.0})
	await save("pyro_recovered")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit()

func save(label: String) -> void:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	if error != OK:
		push_error("Capture failed: " + label)
		quit(1)
	print("MODULE BUTTON CAPTURE: ", label)
