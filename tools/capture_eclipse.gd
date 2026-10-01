extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player") as CharacterBody3D
	var target := scene.get_node("TargetDummy") as Node3D
	target.call("set_training_bot_enabled", false)
	player.call("apply_loadout", {"mobility": "eclipse"})
	player.global_position = Vector3(-3, 0, 3)
	target.global_position = Vector3(3.8, 0, 4.5)
	player.call("_set_aim_direction", Vector3.RIGHT)
	player.set_physics_process(false)
	target.set_physics_process(false)
	var touch: Node = scene.get_node_or_null("Interface/TouchControls")
	if touch == null:
		touch = load("res://scripts/touch_controls.gd").new()
		touch.name = "EclipseCaptureTouch"
		flow.add_child(touch)
	touch.call("set_player", player)
	touch.call("set_editor_test", true)
	for frame in range(20):
		await process_frame
	player.call("begin_touch_action", "mobility")
	player.call("set_eclipse_touch_vector", Vector2(1.0 / 3.0, 0.0))
	target.global_position = player.get("_eclipse").destination + Vector3(0, 0, 2.5)
	await physics_frame
	player.get("_eclipse").update_aim(player)
	await process_frame
	await RenderingServer.frame_post_draw
	save("selection")
	player.call("end_touch_action", "mobility")
	if not player.call("is_eclipse_travelling"):
		push_error("Capture : départ refusé")
		quit(1)
		return
	player.get("_eclipse").update(player, 0.12)
	await process_frame
	await RenderingServer.frame_post_draw
	save("transit")
	player.get("_eclipse").update(player, 0.14)
	await create_timer(0.10).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	save("arrival")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit()

func save(phase: String) -> void:
	var path := "res://captures/eclipse/" + phase + ".png"
	DirAccess.make_dir_recursive_absolute("res://captures/eclipse")
	var error := root.get_texture().get_image().save_png(path)
	print("ECLIPSE CAPTURE ", phase, ": ", error)
