extends SceneTree

const OUTPUT := "res://outputs/powerful-chassis/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var garage: Control = load("res://scenes/forge_garage_preview.tscn").instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	var stage = garage.get("stage")
	stage.automatic_service_enabled = false
	stage.arm.cancel_service()
	for weapon in ["blaster", "shotgun", "longshot", "mekatana"]:
		var selected: Dictionary = garage.get("loadout").duplicate(true)
		selected.robot = "puissant"
		selected.weapon = weapon
		garage.call("set_loadout", selected)
		garage.call("_navigate", "ROBOT")
		garage.focus.show_overview(false)
		stage.set_process(false)
		stage.robot_animator.play(stage.idle_clip)
		stage.robot_animator.advance(0.3)
		for frame in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = OUTPUT + "garage-" + weapon + ".png"
		print("POWERFUL CAPTURE: ", path, " code=", root.get_texture().get_image().save_png(path))
	var icon := preload("res://scripts/robot_forge_preview.gd").new()
	icon.chassis_id = "puissant"
	root.add_child(icon)
	icon.set_process(false)
	icon.stretch = false
	icon.size = Vector2(640, 1024)
	icon._viewport.size = Vector2i(640, 1024)
	var icon_environment := icon._viewport.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	icon_environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	icon._turntable.rotation = Vector3.ZERO
	icon._turntable.scale = Vector3.ONE
	icon._viewport.get_node("Showroom/Plinth").hide()
	icon._animation_player.play(&"idle")
	icon._animation_player.seek(0.3, true)
	var camera := icon._viewport.get_node("Showroom/PreviewCamera") as Camera3D
	camera.size = 1.3
	camera.position = Vector3(0.0, 0.54, 3.0)
	camera.look_at(Vector3(0.0, 0.54, 0.0))
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var icon_image := icon._viewport.get_texture().get_image()
	print("POWERFUL ICON: ", icon_image.save_png("res://art/robot-concepts/robot-puissant-orange.png"), " corner_alpha=", icon_image.get_pixel(0, 0).a)
	icon.queue_free()
	garage.queue_free()
	for frame in range(3):
		await process_frame
	quit()
