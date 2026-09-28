extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output_path := args[0] if args.size() > 0 else "user://survival.png"
	var state := args[1] if args.size() > 1 else "selection"
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var frames_to_wait := 15
	if state != "selection":
		scene.call("_choose_weapon", "shotgun" if state == "shotgun_fire" else "blaster")
		if state != "arrival":
			scene.call("_begin_wave_combat")
		if state == "shotgun_fire":
			for enemy in scene.call("get_training_targets"):
				enemy.call("set_training_bot_enabled", false)
			var player: Node = scene.get_node("Player")
			player.call("set_touch_aim_vector", Vector2.UP)
			player.call("_perform_shotgun_attack")
			await create_timer(0.16).timeout
			frames_to_wait = 0
		if state in ["reward", "evolution"]:
			var waves_to_complete := 5 if state == "evolution" else 1
			for completed in range(waves_to_complete):
				for enemy in scene.call("get_training_targets"):
					enemy.call("take_damage", 5000.0, "capture", "capture_%d_%s" % [completed, enemy.name])
				await physics_frame
				await process_frame
				if completed < waves_to_complete - 1:
					var offers: Array = scene.get("progression").reward_choices(completed + 1)
					scene.call("_choose_reward", offers[0])
					scene.call("_begin_wave_combat")
	for _frame in range(frames_to_wait):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png(output_path)
	paused = false
	quit()
