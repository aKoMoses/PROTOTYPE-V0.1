extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player")
	player.call("apply_loadout", {"weapon": "blaster"})
	player.set_physics_process(false)
	scene.get_node("TargetDummy").call("set_training_bot_enabled", false)
	var touch := flow.get_node("TouchControls")
	touch.visible = true
	player.get("_blaster_heat").restore({"heat": 100.0, "overheated": true})
	# Show the vitals preview regardless of the selected HUD preset.
	var overlay := CanvasLayer.new()
	scene.add_child(overlay)
	var vitals := preload("res://scripts/hud_vitals.gd").new()
	overlay.add_child(vitals)
	vitals.position = Vector2(24, 100)
	vitals.set_player(player)
	for frame in 12:
		await process_frame
	# Force the QA frame even when the temporary window is outside the desktop.
	RenderingServer.force_draw(true)
	var path := "res://.godot/blaster-overheat-checks/heat-ui.png"
	root.get_texture().get_image().save_png(path)
	print("BLASTER HEAT CAPTURE: ", ProjectSettings.globalize_path(path))
	current_scene = null
	scene.queue_free()
	await process_frame
	quit()
