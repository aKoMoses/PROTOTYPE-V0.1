extends SceneTree

## Whole-robot fit evidence. Every comparison uses the same stage, pose,
## camera and projection; module close-ups never determine visual acceptance.
## Run without --headless, after the five GLBs have finished importing.
const STAGE := preload("res://scripts/forge_garage_stage.gd")
const OUTPUT := "res://captures/module-fit/"
const BASELINE := {"mobility": "", "offensive": "", "defensive": "", "passive": ""}
const PYRO_KIT := {
	"mobility": "pyro_boots", "offensive": "rocket_basket",
	"defensive": "magnetic_field", "passive": "auxiliary_reactor",
}
const BIO_KIT := {
	"mobility": "bio_injector", "offensive": "rocket_basket",
	"defensive": "magnetic_field", "passive": "auxiliary_reactor",
}
const KITS := {"00-baseline": BASELINE, "01-pyro": PYRO_KIT, "02-bio": BIO_KIT}
const VIEWS := {"front": 0.0, "threequarter": PI / 4.0, "left": PI / 2.0, "right": -PI / 2.0, "back": PI}
const POSES := {"idle": 0.35, "warm_up": 1.20, "run": 0.24}
const CAMERA_POSITION := Vector3(0, 2.50, 7.45)
const CAMERA_TARGET := Vector3(0, 1.70, 0)
const CAMERA_FOV := 31.0
var stage
var errors: Array[String] = []
var frames: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	if ignore != null:
		ignore.store_string("\n")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	stage = STAGE.new()
	root.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for frame in 5:
		await process_frame
	stage.set_process(false)
	stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	stage.automatic_service_enabled = false
	stage.arm.set_process(false)
	stage.arm.visible = false
	stage.set_chassis("polyvalent")
	stage.camera.attributes = null
	stage.camera.near = 0.015
	stage.viewport.msaa_3d = Viewport.MSAA_4X
	stage.camera.fov = CAMERA_FOV
	stage.camera.global_position = CAMERA_POSITION
	stage.camera.look_at(CAMERA_TARGET)
	# -- --quick produces nine initial proportion comparisons before the
	# complete pose/view matrix is requested after visual inspection.
	var quick := OS.get_cmdline_user_args().has("--quick")
	var dimensions_list := [Vector2i(1600, 900)] if quick else [Vector2i(1600, 900), Vector2i(960, 540)]
	var poses: Dictionary = {"idle": POSES.idle} if quick else POSES
	var views: Dictionary = {"front": VIEWS.front, "threequarter": VIEWS.threequarter, "back": VIEWS.back} if quick else VIEWS
	for dimensions in dimensions_list:
		root.size = dimensions
		for frame in 3:
			await process_frame
		for pose in poses:
			if not _pose_animation(pose, float(poses[pose])):
				continue
			for view in views:
				# Rotate the same robot instead of moving through workshop walls.
				# Baseline and both equipped variants retain exactly this yaw.
				stage.robot.rotation.y = stage.ROBOT_YAW + float(views[view])
				for kit in KITS:
					stage.set_equipped_modules(KITS[kit])
					var label: String = pose + "-" + view + "-" + kit + "-" + str(dimensions.x)
					await _capture(label)
					frames.append({"file": label + ".png", "pose": pose, "sample_seconds": poses[pose], "view": view, "yaw_radians": stage.robot.rotation.y, "equipment": KITS[kit], "size": [dimensions.x, dimensions.y]})
	var manifest := FileAccess.open(OUTPUT + "capture-manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"camera_position": [CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z], "camera_target": [CAMERA_TARGET.x, CAMERA_TARGET.y, CAMERA_TARGET.z], "fov_degrees": CAMERA_FOV, "chassis": "polyvalent", "frames": frames}, "\t") + "\n")
	else:
		errors.append("could not save comparison manifest")
	stage.queue_free()
	await process_frame
	for message in errors:
		push_error(message)
	print("MODULE FIT CAPTURE: ", "PASS" if errors.is_empty() else "FAIL", " (", frames.size(), " fixed-frame comparisons)")
	quit(0 if errors.is_empty() else 1)


func _pose_animation(identifier: String, sample: float) -> bool:
	stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in stage.robot_animator.get_animation_list():
		if String(clip).to_lower().contains(identifier):
			if identifier == "run":
				# This stage owns duplicated libraries. Its existing helper retains
				# the authored pose while keeping run root motion on the platform.
				stage._keep_gesture_in_place(stage.robot_animator.get_animation(clip))
			stage.robot_animator.play(clip, 0.0)
			stage.robot_animator.seek(sample, true)
			stage.robot_animator.advance(0.0)
			stage.skeleton.force_update_all_bone_transforms()
			return true
	errors.append("missing source animation for capture: " + identifier)
	return false


func _capture(label: String) -> void:
	var sample_before: float = stage.robot_animator.current_animation_position
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	if not is_equal_approx(stage.robot_animator.current_animation_position, sample_before):
		errors.append("animation advanced during fixed-pose comparison: " + label)
	var pixels: Image = stage.viewport.get_texture().get_image()
	var darkest := 1.0
	var brightest := 0.0
	for y in range(1, 9):
		for x in range(1, 9):
			var luminance := pixels.get_pixel(pixels.get_width() * x / 9, pixels.get_height() * y / 9).get_luminance()
			darkest = minf(darkest, luminance)
			brightest = maxf(brightest, luminance)
	if brightest - darkest < 0.08:
		errors.append("frame lacks visible scene contrast: " + label)
	var error := pixels.save_png(OUTPUT + label + ".png")
	if error != OK:
		errors.append("save failed: " + label + " " + str(error))
	print("MODULE FIT CAPTURE ", label, " size=", pixels.get_size(), " result=", error)
