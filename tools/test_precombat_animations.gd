extends SceneTree

const SCREEN := preload("res://scripts/ui/precombat_screen.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var checks := 0
var capture := false
const OUTPUT := "res://.godot/precombat-animation-check/"

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var screen := SCREEN.new()
	root.add_child(screen)
	await process_frame
	var first := LOADOUT.defaults()
	var second := LOADOUT.defaults()
	for chassis in ["polyvalent", "agile", "puissant"]:
		first.robot = chassis
		second.robot = chassis
		screen.reveal(first, second)
		await process_frame
		var portraits: Array = screen.get("_portraits")
		var local: Node = portraits[0]
		var opponent: Node = portraits[1]
		for portrait in portraits:
			portrait.set_process(false)
			check(portrait.get("_clips").size() == 3, chassis + ": three preparation gestures")
		check(_animator(local).current_animation != _animator(opponent).current_animation, chassis + ": different openings")
		var source: Node = load(local.get("_model").scene_file_path).instantiate()
		var source_animator := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for clip_name in local.get("_clips"):
			check(_animator(local).get_animation(clip_name) != source_animator.get_animation(clip_name), chassis + ": clips isolated from combat")
			check(_animator(local).get_animation(clip_name) != _animator(opponent).get_animation(clip_name), chassis + ": clips isolated between portraits")
		var initial := _pose(local)
		var opening := _animator(local).current_animation
		var turntable: Node3D = local.get("_turntable")
		var initial_transform := turntable.transform
		for frame in range(15):
			for portrait in portraits:
				portrait.call("_process", 1.0 / 30.0)
			await process_frame
		check(_pose(local) != initial, chassis + ": skeleton actually moves")
		check(turntable.transform == initial_transform, chassis + ": fixed portrait orientation and position")
		if capture:
			await _capture(chassis + "-opening.png")
		for frame in range(90):
			for portrait in portraits:
				portrait.call("_process", 1.0 / 30.0)
			await process_frame
		check(_animator(local).current_animation != opening, chassis + ": gestures alternate during reveal")
		if capture:
			await _capture(chassis + "-boxing.png")
		var clip := _animator(local).current_animation
		var position := _animator(local).current_animation_position
		screen.hide()
		await process_frame
		for portrait in portraits:
			portrait.call("_process", 2.0)
		check(_animator(local).current_animation == clip and is_equal_approx(_animator(local).current_animation_position, position), chassis + ": hidden animation suspended")
		check(local.get("_viewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, chassis + ": hidden rendering suspended")
		screen.reveal(first, second, 3.0)
		check(_animator(local).current_animation == opening and is_equal_approx(_animator(local).current_animation_position, 1.2), chassis + ": next round restarts preparation")
		check(screen.get("_number").text == "03", chassis + ": short countdown preserved")
		source.free()
	first.robot = "agile"
	second.robot = "puissant"
	screen.reveal(first, second)
	root.size = Vector2i(960, 540)
	await process_frame
	if capture:
		await _capture("mobile.png")
	screen.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("PRECOMBAT ANIMATIONS TEST: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _animator(portrait: Node) -> AnimationPlayer:
	return portrait.get("_animation_player") as AnimationPlayer

func _pose(portrait: Node) -> Array[Quaternion]:
	var skeleton := (portrait.get("_model") as Node).find_child("*Skeleton*", true, false) as Skeleton3D
	var pose: Array[Quaternion] = []
	for bone in skeleton.get_bone_count():
		pose.append(skeleton.get_bone_pose_rotation(bone))
	return pose

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _capture(filename: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + filename) == OK, "capture " + filename)
