extends SceneTree

var player: CharacterBody3D
var actor: Node3D
var rig: PlayerVisualRig
var bot: EnemyDroidVisual
var stage: Node3D


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#25323d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e5f0fb")
	environment.ambient_light_energy = 0.85
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-44, -32, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0.0, 3.5, -8.0)
	camera.look_at(Vector3(0, 1.7, -0.2))
	camera.fov = 42.0
	camera.current = true
	player = load("res://scripts/player.gd").new() as CharacterBody3D
	player.name = "Player"
	player.position.x = -2.2
	stage.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.call("set_weapon", "mekatana")
	player.call("set_gameplay_enabled", true)
	(player.get_node("WorldUIAnchor") as Node3D).hide()
	rig = player.get_node("VisualRoot") as PlayerVisualRig
	rig.play_action(&"idle")
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	actor = load("res://scripts/target_dummy.gd").new() as Node3D
	actor.name = "TargetDummy"
	actor.position.x = 2.2
	stage.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.call("set_training_bot_enabled", false)
	for name in ["TargetHealthReadout", "StatusLabel", "JavelinMarkLabel"]:
		var ui := actor.get_node_or_null(name) as Node3D
		if ui != null:
			ui.hide()
	bot = actor.get_node("VisualRoot") as EnemyDroidVisual
	bot.set_weapon("mekatana")
	for tick in range(12):
		await advance_pose(-1, "", 0.0)
	await save("00_idle")
	for step in range(3):
		for tick in range(9):
			await advance_pose(step, "preparation", float(tick) / 8.0)
		for tick in range(13):
			var progress := float(tick) / 12.0
			await advance_pose(step, "active", progress)
			if tick in [0, 6, 12]:
				var pose := "start" if tick == 0 else "middle" if tick == 6 else "end"
				await save("%02d_coup_%d_%s" % [step * 3 + 1 + tick / 6, step + 1, pose])
		for tick in range(12):
			await advance_pose(step, "recovery", float(tick) / 11.0)
		rig.clear_mekatana_pose()
		bot.clear_mekatana_pose()
	print("MEKATANA_CAPTURE_PASS player+bot idle and 9 slash poses")
	current_scene = null
	stage.queue_free()
	await process_frame
	quit()


func advance_pose(step: int, phase: String, progress: float) -> void:
	await process_frame
	rig.set_aim_enabled(step >= 0, true)
	if step >= 0:
		rig.set_mekatana_pose(step, phase, progress)
		bot.set_mekatana_pose(step, phase, progress)
	bot.set_mekatana_direction(Vector3.FORWARD)
	rig.update_visual_state(Vector3.ZERO, Vector3.FORWARD, 0.0, 5.0, 1.0 / 60.0)
	rig.animation_tree.advance(1.0 / 60.0)
	rig.skeleton.advance(1.0 / 60.0)
	await rig.skeleton.skeleton_updated
	bot.update_visual(1.0 / 60.0, Vector3.ZERO, bot.global_position + Vector3.FORWARD * 5.0, step >= 0, false, false)


func save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var output := "res://.godot/mekatana-review/" + filename + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/mekatana-review"))
	var result := root.get_texture().get_image().save_png(output)
	print("CAPTURE ", output, " ", error_string(result))
