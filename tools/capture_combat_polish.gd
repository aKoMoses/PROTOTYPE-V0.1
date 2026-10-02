extends SceneTree

## Real rendering, gameplay camera and visible HUD. No resource or save changes.
## -- OUTPUT_DIR [classic|test|training|survival] [low] [mobile]
var _output: String
var _scene: Node3D
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_output = args[0] if not args.is_empty() else "res://outputs/combat-polish"
	var mode := args[1] if args.size() > 1 else "classic"
	var path := "res://scenes/%s.tscn" % ("main" if mode in ["classic", "test"] else "training_ground" if mode == "training" else "survival")
	var packed := load(path) as PackedScene
	if packed == null:
		quit(2)
		return
	_scene = packed.instantiate()
	if _scene.get_script() == null or not (_scene.get_script() as Script).can_instantiate():
		_scene.free()
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	await process_frame
	var player: Node3D = _scene.get("player")
	var flow: Node = _scene.get("game_flow") if mode in ["classic", "test"] else null
	var target: Node3D
	if mode in ["classic", "test"]:
		_scene.call("set_menu_showcase_enabled", false)
		_scene.call("set_bot_build_seed", 42)
		flow.call("_select_arena", mode)
		flow.call("_start_duel")
		flow.call("_begin_live_round")
		flow.set_process(false)
		target = _scene.get("target")
		target.call("set_training_bot_enabled", false)
		player.global_position = Vector3(-3.5, 2.4, 1.4) if mode == "test" else Vector3(0, 0, 2)
		target.global_position = Vector3(3.5, 2.4, -1) if mode == "test" else Vector3(3.5, 0, -2)
	elif mode == "training":
		if _scene.get("_menu").visible:
			_scene.call("_toggle_menu")
		player.global_position = Vector3(-24, 0, -5)
		target = _scene.get("_fixed_targets")[1]
	elif mode == "survival":
		_scene.call("_choose_weapon", "blaster")
		_scene.call("_begin_wave_combat")
		target = _scene.get("_enemies")[0]
		target.call("set_training_bot_enabled", false)
		target.global_position = player.global_position + Vector3(3.5, 0, -4)
	_scene.set_process(false)
	_scene.set_meta("camera_shake_enabled", false)
	player.call("clear_touch_inputs")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.set("aim_direction", Vector3.FORWARD)
	var rig := _scene.get_node("CameraRig")
	rig.call("set_target", player)
	rig.call("set_follow_offset", Vector3.ZERO, true)
	player.call("_update_world_ui_anchor")
	if flow != null:
		flow.call("_update_hud")
	if args.has("low"):
		_scene.get_node("VFXManager").set("quality", 0)
		var presentation := _scene.get_node_or_null("ArenaPresentation")
		if presentation != null:
			presentation.call("set_quality", 0)
	if args.has("mobile"):
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var suffix := "-low" if args.has("low") else ""
	for _frame in range(30):
		await process_frame
	await _save(mode + suffix + "-ready")
	if target != null:
		var aim := (target.global_position - player.global_position).normalized()
		player.set("aim_direction", aim)
		for weapon in ["blaster", "shotgun", "longshot"]:
			player.call("set_weapon", weapon)
			player.call("_begin_weapon_aim")
			for _frame in range(18):
				await process_frame
			player.get("_visual_rig").call("commit_firing_pose", aim)
			var vfx := _scene.get_node("VFXManager")
			var muzzle: Node3D = player.get("_visual_rig").call("get_weapon_muzzle", weapon)
			vfx.call("muzzle", muzzle, weapon, 1.0)
			var contact: Vector3 = target.global_position + Vector3(0, 1.0, 0)
			vfx.call("impact", contact, -aim, "robot", 1.25, Color("#8be5f2"))
			target.call("flash_impact", true)
			await _save(mode + suffix + "-" + weapon + "-impact")
			_scene.get_node("VFXManager").call("clear")
			await process_frame
	var report := {"mode": mode, "quality": "low" if args.has("low") else "normal", "failures": _failures, "renderer": RenderingServer.get_current_rendering_driver_name(), "camera_fov": root.get_camera_3d().fov}
	var file := FileAccess.open(_output.path_join(mode + suffix + "-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	root.get_node("GameSfx").call("clear")
	_scene.queue_free()
	await process_frame
	print("COMBAT POLISH CAPTURE: ", JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(_output.path_join(name + ".png"))
	if error != OK:
		_failures.append(name + ": save failed")
