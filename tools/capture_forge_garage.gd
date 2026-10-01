extends SceneTree

const OUTPUT := "res://captures/forge-garage/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var suffix := ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	main.get_node("Interface").call("_open_equipment")
	for frame in range(18):
		await process_frame
	await RenderingServer.frame_post_draw
	suffix = "-wide" if root.get_texture().get_image().get_width() > 1800 else ""
	print("FORGE CAPTURE: entry code=", root.get_texture().get_image().save_png(OUTPUT + "00-entry" + suffix + ".png"))
	main.get_node("Interface").set_process(false)
	for audio_node in main.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	await create_timer(0.1).timeout
	main.queue_free()
	await process_frame
	var garage: Control = load("res://scenes/forge_garage_preview.tscn").instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	var stage = garage.get("stage")
	stage.set_process(false)
	stage.arm.active = true
	for sample in [[0.0, "01-overview"], [2.8, "02-approach"], [4.5, "03-inspection"], [8.4, "04-return"]]:
		stage.arm.seek_service(float(sample[0]))
		for frame in range(18):
			await process_frame
		await RenderingServer.frame_post_draw
		var output: String = OUTPUT + str(sample[1]) + suffix + ".png"
		var result := root.get_texture().get_image().save_png(output)
		print("FORGE CAPTURE: ", output, " code=", result)
		print("ARM CONTACT: ", (stage.arm.contact as Node3D).global_position)
	stage.arm.cancel_service()
	var selected: Dictionary = garage.get("loadout").duplicate(true)
	selected.robot = "puissant"
	selected.weapon = "shotgun"
	garage.call("set_loadout", selected)
	for sample in ["05-shotgun", "06-modules"]:
		if sample == "06-modules":
			garage.call("_open_modules", "offensive")
		for frame in range(18):
			await process_frame
		await RenderingServer.frame_post_draw
		var output: String = OUTPUT + sample + suffix + ".png"
		print("FORGE CAPTURE: ", output, " code=", root.get_texture().get_image().save_png(output))
	garage.get("_module_panel").hide()
	for identifier in ["mekatana", "longshot"]:
		selected.weapon = identifier
		garage.call("set_loadout", selected)
		for frame in range(18):
			await process_frame
		await RenderingServer.frame_post_draw
		var output: String = OUTPUT + "08-" + identifier + suffix + ".png"
		print("FORGE CAPTURE: ", output, " code=", root.get_texture().get_image().save_png(output))
	garage.call("_open_weapon_info", "longshot")
	for frame in range(18):
		await process_frame
	await RenderingServer.frame_post_draw
	print("FORGE CAPTURE: weapon info code=", root.get_texture().get_image().save_png(OUTPUT + "09-weapon-info" + suffix + ".png"))
	garage.queue_free()
	for frame in range(4):
		await process_frame
	quit()
