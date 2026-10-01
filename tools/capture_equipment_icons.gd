extends SceneTree

## Capture every garage category and both sets of combat icons without saving a build.
func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	if not scene.get_node("Player").has_method("apply_loadout"):
		push_error("Player script did not load; captures aborted.")
		quit(1)
		return
	var flow: Node = scene.get_node("Interface")
	flow.call("_open_equipment")
	var tabs: Dictionary = flow.get("_equipment_nav_buttons")
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		(tabs[category] as Button).emit_signal("pressed")
		await _capture("garage_" + category)
	var builds := [
		{"weapon": "shotgun", "offensive": "javelin", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "baroud"},
		{"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"},
	]
	# Start the scene directly to avoid _start_duel's persistent loadout write.
	for index in range(builds.size()):
		flow.set("loadout", builds[index])
		scene.call("start_duel", builds[index])
		flow.call("_show_screen", 3)
		flow.call("_begin_round_countdown")
		flow.call("_begin_live_round")
		scene.get_node("TargetDummy").call("set_training_bot_enabled", false)
		if index == 1:
			scene.get_node("Player").set("_module_cooldowns", {"javelin": 8.4, "static_shield": 6.3})
		await _capture("duel_%d" % (index + 1))
	scene.queue_free()
	await process_frame
	quit()

func _capture(label: String) -> void:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://captures/ben_icons_%s.png" % label
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Capture failed: " + path)
		quit(1)
	print("BEN ICONS CAPTURE: ", path)
