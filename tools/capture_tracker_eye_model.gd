extends SceneTree

## Native Godot captures, including the exact camera of the approved mockup.
## Separate user config, no writes to the player's library or saved loadout.
const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/tracker-eye/"
const VIEWS := {"front": 0.0, "front-quarter": -PI / 6.0, "side-left": -PI / 2.0}
const KIT := {"weapon": "blaster", "mobility": "permutation", "offensive": "rocket_basket", "defensive": "counter", "passive": "tracker"}
var garage
var frames: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var powerful_only := OS.get_cmdline_user_args().has("--puissant")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).store_string("")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1200, 1500)
	garage = GARAGE.new()
	garage.library_path = "user://tracker-eye-capture-library.cfg"
	garage.legacy_save_path = "user://tracker-eye-capture-loadout.cfg"
	root.add_child(garage)
	for frame in 5:
		await process_frame
	garage.stage.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)
	garage.focus.set_process(false)
	garage._ui.hide()
	var stage = garage.stage
	stage.automatic_service_enabled = false
	stage.arm.set_process(false)
	stage.arm.hide()
	stage.camera.attributes = null
	stage.viewport.msaa_3d = Viewport.MSAA_4X
	for chassis in (["puissant"] if powerful_only else (["polyvalent"] if quick else ["polyvalent", "agile", "puissant"])):
		garage.set_loadout(KIT.merged({"robot": chassis}, true))
		stage.weapon_socket.hide()
		stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		stage.camera.fov = 31.0
		stage.camera.global_position = Vector3(0, 2.50, 7.8) if chassis == "puissant" else Vector3(0, 2.15, 7.0)
		stage.camera.look_at(Vector3(0, 1.8, 0) if chassis == "puissant" else Vector3(0, 1.6, 0))
		for pose in (["idle"] if quick else ["idle", "warm_up", "run"]):
			_pose(pose)
			if pose == "idle":
				print("TRACKER IDLE ", chassis, " mount=", stage.module_visuals.module_transform("tracker"))
				for index in stage.skeleton.get_bone_count():
					if String(stage.skeleton.get_bone_name(index)).to_lower().contains("leftarm"):
						print("TRACKER IDLE UPRIGHT ", chassis, " ", (stage.skeleton.get_bone_global_rest(index).basis * stage.skeleton.get_bone_global_pose(index).basis.inverse()).get_euler())
			for view in VIEWS:
				stage.robot.rotation.y = stage.ROBOT_YAW + VIEWS[view]
				stage.set_equipped_modules({"mobility": "", "offensive": "", "defensive": "", "passive": "tracker"})
				await _capture(chassis + "-" + pose + "-" + view, true)
				if not quick and pose == "idle":
					for offensive in ["rocket_basket", "javelin"]:
						stage.set_equipped_modules(KIT.merged({"offensive": offensive}, true))
						await _capture(chassis + "-" + offensive + "-" + view, true)
		var mount: Node3D = stage.module_visuals.mounts.tracker
		print("TRACKER FIT ", chassis, " foot=", mount.global_position, " bounds=", stage.module_visuals.module_bounds("tracker"))
		for index in stage.skeleton.get_bone_count():
			if String(stage.skeleton.get_bone_name(index)).to_lower().contains("leftarm"):
				print("LEFT ARM rest=", stage.skeleton.get_bone_global_rest(index), " pose=", stage.skeleton.get_bone_global_pose(index))
				var upright: Basis = stage.skeleton.get_bone_global_rest(index).basis * stage.skeleton.get_bone_global_pose(index).basis.inverse()
				print("TRACKER UPRIGHT euler=", upright.get_euler(), " offset=", upright * Vector3(0.16, 0.27, 0.04))
	if not quick:
		root.size = Vector2i(1600, 900)
		for frame in 5:
			await process_frame
		garage.set_loadout(KIT.merged({"robot": "polyvalent"}, true))
		_pose("idle")
		stage.robot.rotation.y = stage.ROBOT_YAW
		stage.weapon_socket.show()
		stage.arm.show()
		garage._ui.show()
		garage._open_modules("passive")
		garage.focus.show_equipment("passive", "tracker", false)
		garage.focus.advance(1.2)
		await _capture("garage-detail", false)
		root.size = Vector2i(960, 540)
		for frame in 5:
			await process_frame
		garage.focus.advance(1.2)
		await _capture("garage-detail-960", false)
		root.size = Vector2i(1600, 900)
		for frame in 5:
			await process_frame
		garage.set_loadout(KIT.merged({"robot": "polyvalent", "passive": "auxiliary_reactor"}, true))
		garage._select_equipment("passive", "tracker")
		garage.module_installation.set_process(false)
		garage.module_installation.advance(2.6)
		await _capture("pickup", false)
		garage.module_installation.advance(2.55)
		await _capture("fastening", false)
		garage.module_installation.advance(3.0)
		await _capture("installed", false)
		if garage.loadout.passive != "tracker":
			failures.append("actual installation did not finish")
	FileAccess.open(OUTPUT + "capture-manifest.json", FileAccess.WRITE).store_string(JSON.stringify({"native_renderer": true, "reference_camera": "capture_module_identity_robot.gd", "frames": frames}, "\t"))
	garage.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("TRACKER EYE CAPTURE: ", "PASS" if failures.is_empty() else "FAIL", " (", frames.size(), " native renders)")
	quit(0 if failures.is_empty() else 1)

func _pose(identifier: String) -> void:
	var stage = garage.stage
	stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in stage.robot_animator.get_animation_list():
		if String(clip).to_lower().contains(identifier):
			if identifier == "run":
				stage._keep_gesture_in_place(stage.robot_animator.get_animation(clip))
			stage.robot_animator.play(clip, 0)
			stage.robot_animator.seek(1.2 if identifier == "warm_up" else 0.35, true)
			stage.robot_animator.advance(0)
			stage.skeleton.force_update_all_bone_transforms()
			return
	failures.append("missing animation " + identifier)

func _capture(label: String, stage_only: bool) -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = garage.stage.viewport.get_texture().get_image() if stage_only else root.get_texture().get_image()
	if pixels.save_png(OUTPUT + label + ".png") != OK:
		failures.append("capture failed " + label)
	frames.append({"file": label + ".png", "size": [pixels.get_width(), pixels.get_height()], "loadout": garage.stage.module_visuals.equipment_ids.duplicate()})
