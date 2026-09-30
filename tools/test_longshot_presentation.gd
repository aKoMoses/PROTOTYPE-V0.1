extends SceneTree
## Rendered rig regression independent of arena integration.
## Omit --headless; captures are written to the ignored .godot directory.

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("LONGSHOT presentation requires a rendering backend; omit --headless")
		quit(1)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var rig := PlayerVisualRig.new()
	rig.name = "VisualRoot"
	rig.scale = Vector3.ONE * 0.88 * 1.35
	stage.add_child(rig)
	var motion := rig.setup_visual_motion()
	var fallback := Node3D.new()
	motion.add_child(fallback)
	if not rig.install_animated_model(fallback, 2.0):
		_check(false, "animated model installs")
		quit(1)
		return
	var pivot := Node3D.new()
	pivot.add_child(load("res://scenes/weapons/longshot.tscn").instantiate())
	rig.equip_weapon(&"longshot", pivot, {"position": Vector3(0.58, 0.88, -0.36), "rotation": Vector3.ZERO, "scale": Vector3.ONE, "carry_pitch_degrees": -22.0})
	rig.configure_left_hand_support(&"longshot")
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.6
	stage.add_child(camera)
	camera.position = Vector3(3.8, 3.8, 4.4)
	camera.look_at(Vector3(0, 1.90, 0))
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#27313d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-46, -34, 0)
	light.light_energy = 1.6
	stage.add_child(light)
	root.size = Vector2i(1280, 720)
	var weapon := rig.get_weapon_socket(&"longshot").get_node("Weapon_longshot") as Node3D
	_check(weapon.find_child("Muzzle", true, false) != null, "production rig attaches LONGSHOT and its muzzle")
	_check(weapon.find_child("RightHandGrip", true, false) != null, "production rig finds rear grip")
	var grip := weapon.find_child("RightHandGrip", true, false) as Node3D
	# Skeleton restores temporary modifier overrides after rendering. Cache the
	# final modified hand from skeleton_updated, like the production regression.
	var final_hand := {"origin": Vector3.ZERO}
	rig.skeleton.skeleton_updated.connect(func() -> void:
		var hand_pose := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.get_right_hand_bone_index())
		final_hand.origin = hand_pose.origin
	)
	for direction in 8:
		var angle := float(direction) * TAU / 8.0
		var aim := Vector3(sin(angle), 0, -cos(angle))
		rig.set_aim_enabled(true, true)
		for frame in 20:
			rig.update_visual_state(Vector3.RIGHT, aim, 5.0, 5.0, 1.0 / 60.0)
			rig.animation_tree.advance(1.0 / 60.0)
			rig.skeleton.advance(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var error := rad_to_deg(rig.get_weapon_forward_direction(&"longshot").angle_to(aim))
		var grip_error := grip.global_position.distance_to(final_hand.origin)
		_check(error < 0.1 and grip_error < 0.001, "moving aim %d muzzle %.4f degrees grip %.6f m" % [direction, error, grip_error])
		root.get_texture().get_image().save_png("res://.godot/longshot-player-%02d.png" % direction)
	rig.commit_firing_pose(Vector3(-0.7071068, 0, -0.7071068))
	rig.play_shot_kick(1.0)
	for frame in 24:
		rig.update_visual_state(Vector3.RIGHT, Vector3(-0.7071068, 0, -0.7071068), 5.0, 5.0, 1.0 / 60.0)
		rig.animation_tree.advance(1.0 / 60.0)
		rig.skeleton.advance(1.0 / 60.0)
		await process_frame
	_check(not rig.is_shot_kick_active(), "controlled shot recoil settles after 0.4 seconds")
	var last_aim := Vector3(-0.7071068, 0, -0.7071068).normalized()
	_check(rad_to_deg(rig.get_weapon_forward_direction(&"longshot").angle_to(last_aim)) < 0.1, "barrel returns to exact aim after recoil")
	var vfx := load("res://scripts/vfx_manager.gd").new() as Node3D
	stage.add_child(vfx)
	var diameters: Array[float] = []
	for enhanced in [false, true]:
		var projectile := Node3D.new()
		stage.add_child(projectile)
		vfx.call("projectile_visual", projectile, "longshot", 1.0 if enhanced else 0.0)
		var sheath := projectile.get_node("ProjectileSheath") as MeshInstance3D
		diameters.append(sheath.mesh.get_aabb().size.x * sheath.scale.x)
	_check(is_equal_approx(diameters[0], 0.15) and is_equal_approx(diameters[1], 0.225), "visual projectile diameters match .15/.225 collision diameters")
	print("LONGSHOT PRESENTATION %s: %d failures" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
