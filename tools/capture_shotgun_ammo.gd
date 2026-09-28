extends SceneTree

## Capture the actual in-game ammo HUD, loaded and partway through reload.

func _initialize() -> void:
	var scene: Node = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(20):
		await process_frame
	var player: Node = scene.get_node_or_null("Player")
	if player == null:
		push_error("Player introuvable")
		quit(1)
		return
	player.call("set_weapon", "shotgun")
	for _frame in range(4):
		await process_frame
	if not _capture("res://captures/shotgun_ammo_loaded.png"):
		quit(1)
		return
	player.set("_shotgun_ammo", 1)
	player.call("_start_shotgun_reload")
	await create_timer(0.78).timeout
	for _frame in range(3):
		await process_frame
	if not _capture("res://captures/shotgun_ammo_reload.png"):
		quit(1)
		return
	print("SHOTGUN AMMO CAPTURE: PASS")
	quit(0)


func _capture(path: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	var result := image.save_png(path)
	if result != OK:
		push_error("Capture impossible: %s" % path)
		return false
	return true
