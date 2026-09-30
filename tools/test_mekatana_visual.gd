extends SceneTree

## Real imported skeletons, no animation mocks. Optional `-- capture` stores
## sampled poses under .godot; headless assertions also cover moving legs.

var rig: PlayerVisualRig
var bot: EnemyDroidVisual
var failures := 0
var checks := 0
var capture := false
var latest_tip := Vector3.ZERO
var latest_right_error := 0.0


func _initialize() -> void:
	capture = "capture" in OS.get_cmdline_user_args()
	call_deferred("run")


func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#24323c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#ecf8ff")
	environment.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(7.0, 5.0, -8.0)
	camera.look_at(Vector3(0, 1.8, 0))
	camera.current = true
	rig = load("res://scripts/player_visual_rig.gd").new() as PlayerVisualRig
	rig.scale = Vector3.ONE * 1.188
	rig.position.x = -2.0
	stage.add_child(rig)
	rig.setup_visual_motion()
	check(rig.install_animated_model(null, 2.0), "player rig imported")
	var sword := load("res://scenes/weapons/mekatana.tscn").instantiate() as Node3D
	rig.equip_weapon(&"mekatana", sword, {"position": Vector3.ZERO, "rotation": Vector3.ZERO, "scale": Vector3.ONE, "carry_pitch_degrees": -25.0})
	rig.configure_left_hand_support(&"mekatana")
	rig.skeleton.skeleton_updated.connect(func():
		latest_tip = (sword.get_node("BladeTip") as Node3D).global_position
		latest_right_error = (sword.get_node("RightHandGrip") as Node3D).global_position.distance_to(rig.right_hand_attachment.global_position)
	)
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	bot = load("res://scripts/enemy_droid_visual.gd").new() as EnemyDroidVisual
	bot.position.x = 2.0
	stage.add_child(bot)
	check(bot.setup(), "bot rig imported")
	bot.set_weapon("mekatana")
	await process_frame
	var phases: Array[String] = ["preparation", "active", "recovery"]
	var points: Array[float] = [0.0, 0.5, 1.0]
	var sampled: Array[Vector3] = []
	var sampled_bot: Array[Vector3] = []
	for step in range(3):
		for phase in phases:
			for progress in points:
				await process_frame
				rig.set_aim_enabled(true, true)
				rig.set_mekatana_pose(step, phase, progress)
				rig.update_visual_state(Vector3.ZERO, Vector3.FORWARD, 0.0, 5.0, 0.016)
				rig.animation_tree.advance(0.016)
				rig.skeleton.advance(0.016)
				await rig.skeleton.skeleton_updated
				bot.set_mekatana_direction(Vector3.FORWARD)
				bot.set_mekatana_pose(step, phase, progress)
				bot.update_visual(0.016, Vector3.ZERO, bot.global_position + Vector3.FORWARD * 5.0, true, false, false)
				var marker := sword.get_node("RightHandGrip") as Node3D
				check(latest_right_error < 0.002, "right grip %d/%s/%.1f" % [step, phase, progress])
				check(rig.aim_modifier.left_grip_error < 0.10, "player left grip %d/%s/%.1f error %.4f" % [step, phase, progress, rig.aim_modifier.left_grip_error])
				check(bot.left_grip_error < 0.10, "bot left grip %d/%s/%.1f error %.4f" % [step, phase, progress, bot.left_grip_error])
				if phase == "active":
					sampled.append(latest_tip)
					sampled_bot.append(bot.muzzle.global_position)
				if capture and ((phase == "preparation" and progress == 1.0) or (phase == "active" and progress == 0.5)):
					await process_frame
					await RenderingServer.frame_post_draw
					var filename := "res://.godot/mekatana_%d_%s.png" % [step + 1, phase]
					root.get_texture().get_image().save_png(filename)
					print("CAPTURE ", filename)
		rig.clear_mekatana_pose()
		bot.clear_mekatana_pose()
		var guard := rig.aim_modifier._mekatana_guard_yaw
		var bot_guard: float = bot.pose_solver._mekatana_guard_yaw
		rig.clear_mekatana_pose()
		bot.clear_mekatana_pose()
		check(is_equal_approx(guard, rig.aim_modifier._mekatana_guard_yaw), "player clearing idle preserves side guard")
		check(is_equal_approx(bot_guard, float(bot.pose_solver._mekatana_guard_yaw)), "bot clearing idle preserves side guard")
	check(sampled[0].x < sampled[2].x, "first slash goes attacker left to right")
	check(sampled[3].x > sampled[5].x, "second slash goes attacker right to left")
	check(sampled[6].y > sampled[8].y, "third slash goes top to bottom")
	# Compare rendered blade paths, rather than repeating the configured angles.
	# The reverse stroke must read wider and the overhead must clear the floor.
	for index in range(2):
		var path: Array[Vector3] = sampled if index == 0 else sampled_bot
		var actor_name := "player" if index == 0 else "bot"
		var first_width := absf(path[2].x - path[0].x)
		var reverse_width := absf(path[5].x - path[3].x)
		check(reverse_width > first_width * 1.25, actor_name + " reverse stroke is clearly wider")
		check(absf(path[0].y - path[2].y) < 0.05, actor_name + " compact slash stays horizontal")
		check(absf(path[3].y - path[5].y) < 0.05, actor_name + " reverse slash stays horizontal")
		check(path[6].y > path[3].y + 1.0, actor_name + " overhead begins clearly above horizontal strokes")
		check(path[8].y > 0.0, actor_name + " overhead end remains above floor")
	print("SAMPLES ", sampled)
	print("BOT_SAMPLES ", sampled_bot)
	rig.set_mekatana_pose(1, "preparation", 0.5)
	bot.set_mekatana_pose(1, "active", 0.5)
	rig.clear_mekatana_pose()
	bot.clear_mekatana_pose()
	check(is_zero_approx(rig.aim_modifier._mekatana_guard_yaw), "player interruption resets guard")
	check(is_zero_approx(float(bot.pose_solver._mekatana_guard_yaw)), "bot interruption resets guard")
	var moving_cases := [
		[Vector3.RIGHT, Vector3.LEFT],
		[Vector3.BACK, Vector3.FORWARD],
		[Vector3.FORWARD, Vector3.RIGHT],
	]
	for moving_case in moving_cases:
		await process_frame
		var movement: Vector3 = moving_case[0]
		var direction: Vector3 = moving_case[1]
		rig.set_aim_enabled(true, true)
		rig.set_mekatana_pose(1, "active", 0.5)
		rig.update_visual_state(movement, direction, 5.0, 5.0, 0.016)
		rig.animation_tree.advance(0.016)
		rig.skeleton.advance(0.016)
		await rig.skeleton.skeleton_updated
		bot.set_mekatana_direction(direction)
		bot.set_mekatana_pose(1, "active", 0.5)
		bot.update_visual(0.016, movement * 5.0, bot.global_position + direction * 5.0, true, false, false)
		check(latest_right_error < 0.002, "moving player right grip follows wrist")
		check(rig.aim_modifier.left_grip_error < 0.10, "moving player support grip remains held")
		check(bot.left_grip_error < 0.10, "moving bot support grip remains held")
		check((-rig.global_basis.z).normalized().dot(direction) > 0.999, "moving player locks body to attack direction")
		check((-bot.global_basis.z).normalized().dot(direction) > 0.999, "moving bot locks body to attack direction")
	print("MEKATANA_VISUAL ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	await create_timer(0.08).timeout
	current_scene = null
	stage.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ", message)
