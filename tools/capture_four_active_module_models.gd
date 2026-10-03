extends SceneTree

## Fixed-pose comparisons with two exclusive mobility inserts, plus real installs.
const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/four-active/"
const MODELS := {"pelto_smash": "offensive", "counter": "defensive", "permutation": "mobility", "eclipse": "mobility"}
const KIT := {"weapon": "blaster", "mobility": "permutation", "offensive": "pelto_smash", "defensive": "counter", "passive": "auxiliary_reactor"}
const VIEWS := {"front": 0.0, "quarter-left": -PI / 4, "side-left": -PI / 2, "quarter-right": PI / 4, "side-right": PI / 2}
var garage
var frames: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var quick_fit := OS.get_cmdline_user_args().has("--fit-quick")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).store_string("")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	garage = GARAGE.new()
	garage.library_path = "user://four-active-capture-builds.cfg"
	garage.legacy_save_path = "user://four-active-capture-loadout.cfg"
	root.add_child(garage)
	for frame in 5:
		await process_frame
	garage.stage.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)
	garage.focus.set_process(false)
	var stage = garage.stage
	stage.automatic_service_enabled = false
	stage.arm.set_process(false)
	stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	stage.camera.attributes = null
	stage.viewport.msaa_3d = Viewport.MSAA_4X
	garage._ui.hide()
	stage.arm.visible = false
	for chassis in ["polyvalent", "agile", "puissant"]:
		garage.set_loadout(KIT.merged({"robot": chassis}, true))
		stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for pose in (["idle"] if quick_fit else ["idle", "warm_up", "run"]):
			_pose(pose)
			stage.camera.global_position = Vector3(0, 2.50, 7.45)
			stage.camera.look_at(Vector3(0, 1.70, 0))
			stage.camera.fov = 31
			for view in VIEWS:
				stage.robot.rotation.y = stage.ROBOT_YAW + VIEWS[view]
				stage.set_equipped_modules({"mobility": "", "offensive": "", "defensive": "", "passive": ""})
				await _capture(chassis + "-" + pose + "-" + view + "-baseline", true)
				for mobility in ["permutation", "eclipse"]:
					stage.set_equipped_modules(KIT.merged({"mobility": mobility}, true))
					await _capture(chassis + "-" + pose + "-" + view + "-" + mobility, true)
	if quick_fit:
		garage.queue_free()
		await process_frame
		print("FOUR ACTIVE MODULE QUICK FIT: ", "PASS" if failures.is_empty() else "FAIL", " (", frames.size(), " renders)")
		quit(0 if failures.is_empty() else 1)
		return
	garage.set_loadout(KIT.merged({"robot": "polyvalent"}, true))
	stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_pose("idle")
	stage.robot.rotation.y = stage.ROBOT_YAW
	garage._ui.show()
	stage.arm.visible = true
	for identifier in MODELS:
		var category: String = MODELS[identifier]
		garage.set_loadout(KIT.merged({category: identifier}, true))
		garage._open_modules(category)
		garage.focus.show_equipment(category, identifier, false)
		garage.focus.advance(1.2)
		await _capture(identifier + "-garage-detail", false)
		root.size = Vector2i(960, 540)
		for frame in 3:
			await process_frame
		garage.focus.advance(1.2)
		await _capture(identifier + "-garage-960", false)
		root.size = Vector2i(1600, 900)
		for frame in 3:
			await process_frame
	for identifier in MODELS:
		var category: String = MODELS[identifier]
		var baseline := KIT.duplicate()
		baseline[category] = "rocket_basket" if category == "offensive" else ("magnetic_field" if category == "defensive" else "bio_injector")
		garage.set_loadout(baseline)
		garage._select_equipment(category, identifier)
		garage.module_installation.set_process(false)
		garage.module_installation.advance(2.6)
		await _capture(identifier + "-pickup", false)
		garage.module_installation.advance(2.55)
		await _capture(identifier + "-fastening", false)
		garage.module_installation.advance(3.0)
		if garage.loadout[category] != identifier:
			failures.append("capture install failed: " + identifier)
	FileAccess.open(OUTPUT + "capture-manifest.json", FileAccess.WRITE).store_string(JSON.stringify({"frames": frames}, "\t"))
	garage.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("FOUR ACTIVE MODULE CAPTURE: ", "PASS" if failures.is_empty() else "FAIL", " (", frames.size(), " renders)")
	quit(0 if failures.is_empty() else 1)

func _pose(identifier: String) -> void:
	var stage = garage.stage
	for clip in stage.robot_animator.get_animation_list():
		if String(clip).to_lower().contains(identifier):
			if identifier == "run":
				stage._keep_gesture_in_place(stage.robot_animator.get_animation(clip))
			stage.robot_animator.play(clip, 0)
			stage.robot_animator.seek(1.2 if identifier == "warm_up" else 0.35, true)
			stage.robot_animator.advance(0)
			stage.skeleton.force_update_all_bone_transforms()
			return
	failures.append("missing pose: " + identifier)

func _capture(label: String, stage_only: bool) -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = garage.stage.viewport.get_texture().get_image() if stage_only else root.get_texture().get_image()
	var result := pixels.save_png(OUTPUT + label + ".png")
	if result != OK:
		failures.append("save failed: " + label)
	frames.append({"file": label + ".png", "equipment": garage.stage.module_visuals.equipment_ids.duplicate(), "size": [pixels.get_width(), pixels.get_height()], "robot_yaw": garage.stage.robot.rotation.y})
	print("NEW MODULE CAPTURE ", label, " result=", result)
