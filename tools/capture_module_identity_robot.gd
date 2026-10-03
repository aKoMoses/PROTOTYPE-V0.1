extends SceneTree

## Capture the actual imported robot for image-based design mockups.
## Instantiates only the garage stage, without loading or writing user saves.
const STAGE := preload("res://scripts/forge_garage_stage.gd")
const OUTPUT := "res://captures/module-identity-concepts/"
const VIEWS := {"front": 0.0, "front-quarter": -PI / 6.0, "rear-quarter": -3 * PI / 4.0}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).store_string("")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1200, 1500)
	var stage = STAGE.new()
	root.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for frame in 5:
		await process_frame
	stage.set_process(false)
	stage.automatic_service_enabled = false
	stage.arm.set_process(false)
	stage.arm.hide()
	stage.set_chassis("polyvalent")
	stage.set_equipped_modules({"mobility": "", "offensive": "", "defensive": "", "passive": ""})
	stage.weapon_socket.hide()
	stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in stage.robot_animator.get_animation_list():
		if String(clip).to_lower() == "idle":
			stage.robot_animator.play(clip, 0.0)
			stage.robot_animator.seek(0.35, true)
			stage.robot_animator.advance(0.0)
			break
	stage.skeleton.force_update_all_bone_transforms()
	stage.camera.attributes = null
	stage.viewport.msaa_3d = Viewport.MSAA_4X
	stage.camera.fov = 31.0
	stage.camera.global_position = Vector3(0, 2.15, 7.0)
	stage.camera.look_at(Vector3(0, 1.6, 0))
	var frames: Array[Dictionary] = []
	var errors: Array[String] = []
	for view in VIEWS:
		stage.robot.rotation.y = stage.ROBOT_YAW + VIEWS[view]
		for frame in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = stage.viewport.get_texture().get_image()
		var path: String = OUTPUT + "vrai-robot-" + view + "-v1.png"
		if pixels.save_png(path) != OK:
			errors.append(path)
		frames.append({"path": path, "model": stage.robot_model.scene_file_path, "chassis": stage.chassis_id, "size": [pixels.get_width(), pixels.get_height()], "yaw": stage.robot.rotation.y})
	FileAccess.open(OUTPUT + "robot-reference-manifest-v1.json", FileAccess.WRITE).store_string(JSON.stringify({"purpose": "Real game robot reference for concept image edits", "frames": frames}, "\t"))
	stage.queue_free()
	await process_frame
	print("MODULE IDENTITY ROBOT REFERENCE: ", "PASS" if errors.is_empty() else "FAIL", " (", frames.size(), " actual model renders)")
	quit(0 if errors.is_empty() else 1)
