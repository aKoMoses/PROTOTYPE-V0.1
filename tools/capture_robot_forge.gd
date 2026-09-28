extends SceneTree

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_open_equipment")
	flow.call("_open_equipment_category", "robot")
	var build: Dictionary = flow.get("loadout")
	build.robot = "polyvalent"
	flow.set("loadout", build)
	flow.call("_refresh_equipment")
	await _capture("robot_forge")
	flow.call("_open_equipment_category", "weapon")
	await _capture("robot_forge_weapon")
	(flow.get_node("MenuMusic") as AudioStreamPlayer).stop()
	await create_timer(0.1).timeout
	scene.queue_free()
	await process_frame
	quit()

func _capture(filename: String) -> void:
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var suffix := "_mobile" if root.size.x > 1800 else ""
	var output := "res://captures/%s%s.png" % [filename, suffix]
	var result := root.get_texture().get_image().save_png(output)
	print("ROBOT FORGE CAPTURE: ", output, " code=", result)
