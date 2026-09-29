extends SceneTree


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var output_path := arguments[0] if not arguments.is_empty() else "user://pelto-smash.png"
	var capture_phase := arguments[1] if arguments.size() > 1 else "outbound"
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node("Player")
	var target: Node = scene.get_node("TargetDummy")
	var interface := scene.get_node_or_null("Interface")
	if interface != null:
		interface.visible = false
	var loadout := {
		"weapon": "blaster",
		"offensive": "pelto_smash",
		"defensive": "magnetic_field",
		"mobility": "pyro_boots",
		"passive": "baroud",
	}
	player.call("apply_loadout", loadout)
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.global_position = Vector3(0.0, 0.0, 6.0)
	target.call("set_training_bot_enabled", false)
	target.call("reset_combat_state")
	target.global_position = Vector3(0.0, 0.0, 1.0)
	var rig := scene.get_node_or_null("CameraRig")
	if rig != null:
		rig.call("set_target", player)
	await process_frame
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("_perform_pelto_smash")
	if capture_phase == "preparation":
		await _wait_frames(12)
	elif capture_phase == "return":
		await _wait_for_return(scene)
		await _wait_frames(12)
	else:
		await _wait_for_outbound(scene, 4.0)
	var image := get_root().get_viewport().get_texture().get_image()
	if image == null:
		push_error("Capture PELTO indisponible avec le pilote de rendu actif")
		quit(1)
		return
	image.save_png(output_path)
	quit()


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _wait_for_return(scene: Node) -> void:
	for _frame in range(120):
		await process_frame
		for child in scene.get_children():
			if child is PeltoSmashWave and str(child.get("phase")) == "return":
				return


func _wait_for_outbound(scene: Node, minimum_distance: float) -> void:
	for _frame in range(120):
		await process_frame
		for child in scene.get_children():
			if child is PeltoSmashWave and str(child.get("phase")) == "outbound" and float(child.get("travel_distance")) >= minimum_distance:
				return
