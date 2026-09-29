extends SceneTree

# Run with --headless --path <project> --script res://tools/test_player_visual_rig.gd.
# Manual AnimationTree/Skeleton3D advancement makes 50/100/200 ms samples exact,
# independently of rendering speed. Capture bones inside skeleton_updated: Godot
# restores the unmodified animation pose after its modifier pass.
const STEP := 1.0 / 60.0
const SAMPLE_FRAMES := [0, 3, 6, 12, 21, 30]
var _failures: Array[String] = []
var _checks := 0
var _rig: PlayerVisualRig
var _player: Node3D
var _move := Vector3.ZERO
var _aim := Vector3.FORWARD
var _latest_pose: Dictionary = {}
var _finished_animations: Array[StringName] = []
var _support_diagnostics_printed := false


func _initialize() -> void:
	var scene: Node
	if "--isolated" in OS.get_cmdline_user_args():
		# Exercise the actual Player independently of unrelated arena/enemy edits.
		scene = Node3D.new()
		var player_script := load("res://scripts/player.gd") as Script
		if player_script == null or not player_script.can_instantiate():
			_check(false, "production Player script compiles")
			_finish()
			return
		var isolated_player := player_script.new() as CharacterBody3D
		isolated_player.name = "Player"
		scene.add_child(isolated_player)
		print("[RigFixture] isolated production Player (arena integration not covered)")
	else:
		scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_player = scene.get_node_or_null("Player") as Node3D
	_check(_player != null, "Player exists in the gameplay scene")
	if _player == null or not _player.has_method("set_gameplay_enabled"):
		_check(false, "production Player script compiles")
		_finish()
		return
	var target: Node = scene.get_node_or_null("TargetDummy")
	if target != null:
		if not target.has_method("set_training_bot_enabled"):
			_check(false, "arena target script compiles (use --isolated to diagnose Player separately)")
			_finish()
			return
		target.call("set_training_bot_enabled", false)
	_rig = _player.get_node_or_null("VisualRoot") as PlayerVisualRig
	_check(_rig != null and _rig.skeleton != null, "dedicated VisualRoot owns the GLB skeleton")
	if _rig == null or _rig.skeleton == null:
		_finish()
		return
	_check_structure()
	await _check_touch_inputs()
	_player.call("clear_touch_inputs")
	_player.call("set_gameplay_enabled", true)
	_player.set_physics_process(false)
	_player.set_process(false)
	_rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_rig.skeleton.skeleton_updated.connect(_capture_final_pose)
	_rig.action_finished.connect(_on_action_finished)
	_check(not _rig.aim_modifier.aiming and is_zero_approx(float(_rig.animation_tree.get(_rig.AIM_BLEND_PARAMETER))), "unalerted player starts in the lowered locomotion pose")
	_rig.set_aim_enabled(true)
	_rig.configure_left_hand_support(&"blaster")
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	_check_weapon_chain()
	var cases := [
		["A_idle", Vector3.ZERO, Vector3.FORWARD],
		["B_run_forward", Vector3.FORWARD, Vector3.FORWARD],
		["C_run_backward", Vector3.BACK, Vector3.FORWARD],
		["D_move_left_aim_right", Vector3.LEFT, Vector3.RIGHT],
		["E_move_right_aim_left", Vector3.RIGHT, Vector3.LEFT],
		["F_move_changes_in_recovery", Vector3.FORWARD, Vector3.FORWARD],
		["G_aim_rotates_in_recovery", Vector3.LEFT, Vector3.FORWARD],
	]
	for case_data in cases:
		await _test_shot_case(String(case_data[0]), case_data[1], case_data[2])
	await _test_repeated_shots()
	await _test_player_shot_entrypoint()
	await _test_charge_release()
	await _test_aim_interruptions()
	await _test_weapon_pose_state_machine()
	var root_position_before := _player.global_position
	await _settle(Vector3.FORWARD, Vector3.RIGHT)
	_check(_player.global_position.distance_to(root_position_before) < 0.001, "in-place locomotion never moves CharacterBody")
	_check(&"fire" in _finished_animations, "ShotKick completion is reported without leaving AimPose")
	_finish()


func _check_structure() -> void:
	_check(_rig.skeleton.get_bone_count() >= 60, "GLB skeleton retains its authored bones")
	_check(_rig.right_hand_bone_name == &"mixamorig_RightHand", "weapon attachment uses the actual right hand")
	_check(_rig.right_hand_attachment != null and _rig.right_hand_attachment.bone_name == _rig.right_hand_bone_name, "BoneAttachment follows RightHand")
	var available: Array[StringName] = []
	for clip_name in _rig.animation_player.get_animation_list():
		available.append(_rig._canonical_animation_name(clip_name))
	var all_clips_available := true
	for clip_name in [&"bow", &"warm_up", &"run", &"fall", &"fire", &"idle", &"box_01", &"afraid", &"walk"]:
		all_clips_available = all_clips_available and clip_name in available
	_check(all_clips_available, "all nine authored GLB animation clips are retained")
	_check(_rig.animation_tree != null and _rig.animation_tree.active, "AnimationTree remains active")
	_check(_rig.animation_tree.tree_root is AnimationNodeBlendTree, "AnimationTree layers base, locomotion, low-ready arms and transient aim")
	_check(not _rig._base_state_machine.has_node(&"fire") and not _rig._base_state_machine.has_node(&"run") and not _rig._base_state_machine.has_node(&"walk"), "fire and locomotion remain independent of full-body base states")
	_check(_rig._locomotion_state_machine.has_node(&"run") and _rig._locomotion_state_machine.has_node(&"walk"), "walk/run retain continuously advancing state machine")
	_check(_rig.lower_body_blend != null and not _rig.lower_body_blend.filter_enabled, "unalerted locomotion uses the authored full-body walk/run")
	_check(_rig.ready_blend != null and _rig.ready_blend.filter_enabled, "ReadyPose stabilizes only the carried-weapon arms")
	_check(_rig.aim_blend != null and _rig.aim_blend.filter_enabled, "AimPose is a transient upper-body filtered blend")
	var fire_clip := _rig.animation_player.get_animation("fire")
	_check(fire_clip != null and is_equal_approx(fire_clip.length, 1.5), "authored fire source stays 1.5 seconds")
	_check(_rig.aim_pose_sample_time >= 0.0 and _rig.aim_pose_sample_time <= fire_clip.length, "AimPose frame is sampled within authored fire")
	var aim_clip := _rig.animation_player.get_animation("runtime/AimPose")
	_check(aim_clip != null, "runtime/AimPose exists")
	if aim_clip != null:
		var constant_rotations_only := aim_clip.get_track_count() > 0
		var excludes_lower_body := true
		for track in range(aim_clip.get_track_count()):
			constant_rotations_only = constant_rotations_only and aim_clip.track_get_type(track) == Animation.TYPE_ROTATION_3D
			var track_path := aim_clip.track_get_path(track)
			var path_text := String(track_path).to_lower()
			excludes_lower_body = excludes_lower_body and not (path_text.contains("hips") or path_text.contains("leg") or path_text.contains("foot") or path_text.contains("toe"))
			for key in range(1, aim_clip.track_get_key_count(track)):
				var first: Quaternion = aim_clip.track_get_key_value(track, 0)
				var next: Quaternion = aim_clip.track_get_key_value(track, key)
				constant_rotations_only = constant_rotations_only and first.is_equal_approx(next)
		_check(constant_rotations_only, "AimPose contains constant rotations only, without translations/root motion")
		_check(excludes_lower_body, "AimPose never includes pelvis or legs")
	var ready_clip := _rig.animation_player.get_animation("runtime/ReadyPose")
	var ready_arms_only := ready_clip != null and ready_clip.get_track_count() > 0
	if ready_clip != null:
		for track in range(ready_clip.get_track_count()):
			var ready_path := String(ready_clip.track_get_path(track)).to_lower()
			ready_arms_only = ready_arms_only and ready_clip.track_get_type(track) == Animation.TYPE_ROTATION_3D and (ready_path.contains("left") or ready_path.contains("right"))
	_check(ready_arms_only, "ReadyPose is a constant arm-only pose without pelvis or root motion")
	_check(is_equal_approx(float(_rig.animation_tree.get(_rig.READY_BLEND_PARAMETER)), 1.0), "low-ready arm layer is active outside combat")
	var spine_track := _find_bone_track(fire_clip, "mixamorig_Spine")
	var hand_track := _find_bone_track(fire_clip, "mixamorig_RightHand")
	_check(_rig.aim_blend.is_path_filtered(spine_track) and _rig.aim_blend.is_path_filtered(hand_track), "AimPose filter includes torso and weapon hand")
	_check(not _rig.aim_blend.is_path_filtered(_find_bone_track(fire_clip, "mixamorig_Hips")), "AimPose filter excludes pelvis")
	var run_clip := _rig.animation_player.get_animation("run")
	_check(_rig.lower_body_blend.is_path_filtered(_find_bone_track(run_clip, "mixamorig_Hips")) and _rig.lower_body_blend.is_path_filtered(_find_bone_track(run_clip, "mixamorig_LeftUpLeg")), "locomotion filter keeps pelvis and legs")
	_check(not _rig.lower_body_blend.is_path_filtered(_find_bone_track(run_clip, "mixamorig_Spine")), "locomotion filter leaves torso to AimPose")
	_check(_root_motion_is_flat(&"walk") and _root_motion_is_flat(&"run"), "walk/run retain removed horizontal root motion")


func _check_touch_inputs() -> void:
	_player.call("set_gameplay_enabled", true)
	var player_rotation_before := _player.rotation.y
	_player.call("set_touch_move_vector", Vector2(1.0, 0.0))
	_player.call("set_touch_aim_vector", Vector2(0.0, -1.0))
	await create_timer(0.30).timeout
	var movement: Vector3 = _player.get("move_direction")
	var aim: Vector3 = _player.get("aim_direction")
	_check(movement.length_squared() > 0.5 and absf(movement.normalized().dot(aim.normalized())) < 0.25, "touch movement/aim remain independent")
	_check(absf(wrapf(_player.rotation.y - player_rotation_before, -PI, PI)) < 0.02, "aim input leaves CharacterBody orientation unchanged")
	var cardinal: Vector3 = _player.call("_camera_relative_direction", Vector2(1.0, 0.0))
	var diagonal: Vector3 = _player.call("_camera_relative_direction", Vector2(1.0, -1.0))
	_check(absf(cardinal.length() - 1.0) < 0.001 and absf(diagonal.length() - 1.0) < 0.001, "cardinal/diagonal movement remain normalized")


func _check_weapon_chain() -> void:
	for weapon_id in [&"blaster", &"shotgun"]:
		var socket := _rig.get_weapon_socket(weapon_id)
		var weapon := socket.get_node_or_null("Weapon_%s" % weapon_id) as Node3D if socket != null else null
		_check(weapon != null and weapon.get_parent() == socket and socket.get_parent() == _rig.right_hand_attachment, "%s follows RightHand -> BoneAttachment -> socket -> root" % weapon_id)
		if weapon != null:
			_check(weapon.transform.is_equal_approx(Transform3D.IDENTITY), "%s root stays identity under its fixed socket" % weapon_id)
			_check(weapon.find_child("LeftHandGrip", true, false) is Marker3D, "%s exposes LeftHandGrip support target" % weapon_id)
			_check(weapon.find_child("RightHandGrip", true, false) is Marker3D, "%s exposes RightHandGrip attachment target" % weapon_id)
		_check(_rig.get_weapon_muzzle(weapon_id) != null, "%s exposes a dedicated muzzle" % weapon_id)
	_check(_rig.aim_modifier != null, "post-animation skeleton modifier owns recoil and hand support")
	_check(float(_latest_pose.get("right_hand_error", INF)) <= 0.001, "blaster rear grip is seated on the animated right hand")
	print("[LeftHandSupport] reachable=%s solver_error=%.6f measured_error=%.6f" % [_rig.aim_modifier.left_grip_reachable, _rig.aim_modifier.left_grip_error, _latest_pose.get("hand_error", INF)])


func _test_shot_case(label: String, movement: Vector3, aim: Vector3) -> void:
	await _settle(movement, aim)
	var before := _measure(label, -1.0)
	var hand_before: Vector3 = _latest_pose.right_hand_position
	_assert_aim(before, 0.98 if movement.is_zero_approx() else 0.97, 0.05, label + " before")
	var phase_before := _rig._locomotion_playback.get_current_play_position()
	var transforms_before := _weapon_transforms()
	_check(_rig.play_shot_kick(), label + " accepts a skeleton ShotKick")
	_check(_rig.is_shot_kick_active(), label + " kick starts independently of gameplay cooldown")
	var max_angle := 0.0
	var peak_angle := 0.0
	var hundred_ms_angle := 0.0
	var transforms_stayed_fixed := true
	for frame in range(31):
		if frame > 0:
			if frame == 4 and label.begins_with("F_"):
				_move = Vector3.BACK
			if frame == 4 and label.begins_with("G_"):
				_aim = Vector3.RIGHT
			await _step(STEP)
		var sample := _measure(label, frame * STEP, frame in SAMPLE_FRAMES)
		transforms_stayed_fixed = transforms_stayed_fixed and _transforms_match(transforms_before, _weapon_transforms())
		max_angle = maxf(max_angle, float(sample.angle))
		if frame == 3:
			peak_angle = float(sample.angle)
			if movement.is_zero_approx():
				var hand_displacement: Vector3 = _latest_pose.right_hand_position - hand_before
				_check(hand_displacement.dot(-_aim) > 0.005, label + " ShotKick actually moves the right hand backward")
		if frame == 6:
			hundred_ms_angle = float(sample.angle)
		if frame in SAMPLE_FRAMES:
			_check(float(sample.hand_error) <= 0.035, "%s %.2fs left hand stays on support grip" % [label, frame * STEP])
			_check(float(sample.right_hand_error) <= 0.001, "%s %.2fs rear grip stays attached to the right hand" % [label, frame * STEP])
			if frame >= 12:
				_assert_aim(sample, 0.98, 0.05, "%s %.2fs recovered" % [label, frame * STEP])
			else:
				_check(float(sample.angle) <= 5.0 and absf(float(sample.pitch)) <= 3.0, "%s %.2fs recoil has controlled full-3D deviation" % [label, frame * STEP])
		if frame == 6 and not movement.is_zero_approx():
			var phase_after := _rig._locomotion_playback.get_current_play_position()
			var expected_delta := STEP * 6.0 * float(_rig.animation_tree.get("parameters/Locomotion/run/TimeScale/scale"))
			var duration := _rig.animation_player.get_animation("run").length
			var actual_delta := fposmod(phase_after - phase_before, duration)
			_check(absf(actual_delta - expected_delta) <= 0.005, label + " run phase advances without restarting on shot")
	_check(not _rig.is_shot_kick_active(), label + " recoil has finished by 500 ms")
	_check(transforms_stayed_fixed, label + " socket/root/sway/recoil remain fixed during every recoil/recovery frame")
	if not label.begins_with("G_"):
		_check(hundred_ms_angle <= peak_angle + 0.15, label + " 100 ms sample is recovering from peak")
	print("[ShotSummary] %s max_angle=%.5fdeg t100=%.5fdeg" % [label, max_angle, hundred_ms_angle])


func _test_repeated_shots() -> void:
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	var before: Vector3 = _latest_pose.forward
	var transforms_before := _weapon_transforms()
	var maximum_final_drift := 0.0
	for shot in range(10):
		_check(_rig.play_shot_kick(), "repeated shot %d accepted" % (shot + 1))
		for frame in range(30):
			await _step(STEP)
		var sample := _measure("repeat_%02d" % (shot + 1), 0.50)
		_assert_aim(sample, 0.98, 0.05, "repeated shot %d returned to aim" % (shot + 1))
		maximum_final_drift = maxf(maximum_final_drift, rad_to_deg(before.angle_to(sample.forward)))
	_check(maximum_final_drift <= 0.05, "10 consecutive shots return to original full-3D muzzle orientation (<= 0.05 degrees)")
	_check(_transforms_match(transforms_before, _weapon_transforms()), "10 consecutive shots leave all four local transforms unchanged")
	print("[RepeatedShots] count=10 maximum_final_drift=%.6fdeg transforms_unchanged=%s" % [maximum_final_drift, _transforms_match(transforms_before, _weapon_transforms())])


func _test_player_shot_entrypoint() -> void:
	await _settle(Vector3.FORWARD, Vector3.RIGHT)
	_player.call("reset_blaster_state")
	var token_before: int = _player.get("_blaster_attack_token")
	var transforms_before := _weapon_transforms()
	_player.call("_fire_blaster_projectile", 20.0, 0.0, _aim)
	_check(int(_player.get("_blaster_attack_token")) == token_before + 1, "actual player projectile entry point accepts a shot")
	_check(_rig.is_shot_kick_active(), "actual player projectile entry point triggers skeleton recoil")
	for frame in range(30):
		await _step(STEP)
		if frame in [2, 5, 11, 20, 29]:
			var sample := _measure("player_entrypoint", (frame + 1) * STEP)
			if frame >= 11:
				_assert_aim(sample, 0.98, 0.05, "actual projectile entry point returns to aim")
	_check(_transforms_match(transforms_before, _weapon_transforms()), "player shot path leaves fixed socket and weapon wrappers unchanged")


func _test_charge_release() -> void:
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	_player.call("reset_blaster_state")
	_player.set("aim_direction", _aim)
	_player.call("_begin_blaster_charge")
	_check(bool(_player.call("is_blaster_charging")), "player charge entry point starts charging")
	var transforms_before := _weapon_transforms()
	for frame in range(60):
		# Gameplay's clock-driven charge/cooldown is covered by test_blaster.gd;
		# here advance the same ratio deterministically alongside skeletal time.
		_player.set("_blaster_charge_ratio", (frame + 1) / 60.0)
		_player.call("_update_blaster_charge_visual", STEP)
		await _step(STEP)
		if frame in [0, 29, 59]:
			var sample := _measure("charging", (frame + 1) * STEP)
			_assert_aim(sample, 0.98, 0.05, "charging preserves aim")
			_check(float(sample.hand_error) <= 0.035, "charging keeps support hand on grip")
	_player.call("_release_blaster_charge")
	_check(not bool(_player.call("is_blaster_charging")) and _rig.is_shot_kick_active(), "actual charge release triggers ShotKick and exits charge")
	var maximum_angle := 0.0
	for frame in range(31):
		if frame > 0:
			await _step(STEP)
		var sample := _measure("charged_release", frame * STEP, frame in SAMPLE_FRAMES)
		maximum_angle = maxf(maximum_angle, float(sample.angle))
		if frame in SAMPLE_FRAMES:
			_check(float(sample.angle) <= 5.0 and absf(float(sample.pitch)) <= 3.0, "charged shot stays within small 3D recoil envelope")
			_check(float(sample.hand_error) <= 0.035, "charged recoil retains left-hand support")
			if frame >= 12:
				_assert_aim(sample, 0.98, 0.05, "charged shot returned to aim")
	_check(_transforms_match(transforms_before, _weapon_transforms()), "charged shot has no socket/root/sway/recoil transform accumulation")
	print("[ChargedShotSummary] max_angle=%.6fdeg" % maximum_angle)


func _test_aim_interruptions() -> void:
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	var transforms_before := _weapon_transforms()
	var socket_before := _rig.get_weapon_socket(&"blaster")
	var canonical_aim_transform: Transform3D = socket_before.get_meta("weapon_aim_transform")
	var canonical_carry_transform: Transform3D = socket_before.get_meta("weapon_carry_transform")
	for full_body_action in [&"warm_up", &"fall"]:
		_rig.play_shot_kick()
		_check(_rig.play_action(full_body_action), "%s full-body action is available" % full_body_action)
		await _step(STEP)
		_check(not _rig.aim_modifier.aiming and not _rig.is_shot_kick_active() and not _rig.play_shot_kick(), "%s suspends combat aim, cancels recoil and rejects new recoil" % full_body_action)
		_check(is_zero_approx(float(_rig.animation_tree.get(_rig.AIM_BLEND_PARAMETER))), "%s receives the unmasked full-body animation" % full_body_action)
		_rig.play_action(&"idle")
		await _settle(Vector3.ZERO, Vector3.FORWARD)
		_assert_aim(_measure("after_%s" % full_body_action, 0.75), 0.98, 0.05, "%s interruption restores aim" % full_body_action)
	_rig.play_shot_kick()
	_player.call("set_weapon", "shotgun")
	await _step(STEP)
	_check(not _rig.aim_modifier.aiming and not _rig.is_shot_kick_active(), "weapon swap cancels recoil and returns to the lowered ready pose")
	_player.call("set_weapon", "blaster")
	_player.call("_begin_weapon_aim")
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	_check(_rig.aim_modifier.aiming, "an explicit attack preparation raises the re-equipped blaster")
	_assert_aim(_measure("blaster_reequipped", 0.75), 0.98, 0.05, "raised re-equipped blaster preserves calibration")
	_rig.play_shot_kick()
	_player.call("set_gameplay_enabled", false)
	await _step(STEP)
	_check(not _rig.aim_modifier.aiming and not _rig.is_shot_kick_active() and not _rig.play_shot_kick(), "gameplay disable suspends AimPose and cancels ShotKick")
	_player.call("set_gameplay_enabled", true)
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	_check(not _rig.aim_modifier.aiming, "gameplay resume stays lowered until an attack")
	var socket_after := _rig.get_weapon_socket(&"blaster")
	var transforms_after := _weapon_transforms()
	var wrappers_unchanged := true
	for index in range(1, transforms_before.size()):
		wrappers_unchanged = wrappers_unchanged and transforms_before[index].is_equal_approx(transforms_after[index])
	_check(
		socket_after.get_meta("weapon_aim_transform", Transform3D.IDENTITY).is_equal_approx(canonical_aim_transform)
		and socket_after.get_meta("weapon_carry_transform", Transform3D.IDENTITY).is_equal_approx(canonical_carry_transform)
		and socket_after.transform.is_equal_approx(canonical_carry_transform)
		and wrappers_unchanged,
		"interruptions preserve both calibrated socket poses and leave weapon wrappers fixed"
	)
	_player.call("set_gameplay_enabled", false)
	_player.call("reset_combat_state")
	await _step(STEP)
	_check(_rig._active_action == &"warm_up" and not _rig.aim_modifier.aiming, "round reset starts the full-body warmup")
	_player.call("set_gameplay_enabled", true)
	await _step(STEP)
	_check(_rig._active_action == &"" and not _rig.aim_modifier.aiming, "countdown completion releases warmup into the lowered idle pose")
	_player.call("_fire_blaster_projectile", 20.0, 0.0, _aim)
	_check(_rig.is_shot_kick_active(), "first shot after countdown triggers skeletal recoil immediately")
	_check(bool(_player.get("_blaster_attack_busy")), "first tap defers projectile emission until the raised BoneAttachment is current")
	await _step(STEP)
	_assert_aim(_measure("countdown_first_shot", STEP), 0.98, 0.05, "first actual shot emits from the committed horizontal aim pose")
	_check(not bool(_player.get("_blaster_attack_busy")), "deferred first-tap emission completes on the next skeleton update")
	await _settle(Vector3.ZERO, Vector3.FORWARD)


func _test_weapon_pose_state_machine() -> void:
	_player.call("_reset_weapon_pose_to_locomotion", true)
	await _settle(Vector3.RIGHT, Vector3.FORWARD)
	_check(_player.call("get_weapon_pose_state_name") in [&"IDLE", &"LOCOMOTION"] and not _rig.aim_modifier.aiming, "ready-low state does not enable combat aim")
	_check(float(_latest_pose.get("right_hand_error", INF)) <= 0.001, "ready-low pose keeps the blaster rear grip in the right hand")
	_check(_rig.get_aim_forward_direction().dot(Vector3.RIGHT) >= 0.98, "outside combat the character faces movement rather than stale aim")
	_player.call("_begin_weapon_aim")
	var maximum_raise_grip_error := 0.0
	for frame in range(45):
		await _step(STEP)
		maximum_raise_grip_error = maxf(maximum_raise_grip_error, float(_latest_pose.get("right_hand_error", INF)))
	_check(maximum_raise_grip_error <= 0.001, "aim transition keeps the blaster rear grip attached on every frame")
	_check(_player.call("get_weapon_pose_state_name") == &"AIM" and _rig.aim_modifier.aiming, "attack preparation enters AIM without stopping locomotion")
	_check(_rig.get_aim_forward_direction().dot(Vector3.FORWARD) >= 0.98, "AIM faces the independent aim direction while moving sideways")
	_player.call("_begin_weapon_fire")
	_check(_player.call("get_weapon_pose_state_name") == &"FIRE", "committed attack enters FIRE")
	_player.call("_begin_aim_hold")
	var configured_hold: float = _player.get("aim_hold_time")
	_player.call("_update_weapon_pose_state", configured_hold * 0.5)
	_check(_player.call("get_weapon_pose_state_name") == &"AIM_HOLD" and _rig.aim_modifier.aiming, "AIM_HOLD keeps the weapon raised through half its configured window")
	_player.call("_begin_weapon_fire")
	_player.call("_begin_aim_hold")
	_check(is_equal_approx(float(_player.get("_aim_hold_remaining")), configured_hold), "a repeated shot restarts the complete AIM_HOLD window")
	_player.call("_update_weapon_pose_state", configured_hold + 0.01)
	_check(_player.call("get_weapon_pose_state_name") in [&"IDLE", &"LOCOMOTION"] and not _rig.aim_modifier.aiming, "expired AIM_HOLD returns to lowered locomotion")


func _settle(movement: Vector3, aim: Vector3) -> void:
	_move = movement
	_aim = aim
	for frame in range(45):
		await _step(STEP)


func _step(delta: float) -> void:
	# The previous skeleton_updated handler runs inside the modifier update.
	# Yield before advancing again so its temporary pose has been restored.
	await process_frame
	var speed: float = _player.get("move_speed")
	_player.call("_update_weapon_ambient_motion", delta)
	_rig.update_visual_state(_move, _aim, 0.0 if _move.is_zero_approx() else speed, speed, delta)
	_rig.animation_tree.advance(delta)
	_rig.skeleton.advance(delta)
	await _rig.skeleton.skeleton_updated


func _capture_final_pose() -> void:
	var muzzle := _rig.get_weapon_muzzle(&"blaster")
	if muzzle == null:
		return
	var socket := _rig.get_weapon_socket(&"blaster")
	var grip := socket.get_node_or_null("Weapon_blaster/WeaponSway/WeaponRecoil/LeftHandGrip") as Node3D
	var right_grip := socket.get_node_or_null("Weapon_blaster/WeaponSway/WeaponRecoil/RightHandGrip") as Node3D
	var left_hand_index := _rig.skeleton.find_bone(String(_rig.left_hand_bone_name))
	var hand_error := INF
	if grip != null and left_hand_index >= 0:
		var hand_world := _rig.skeleton.global_transform * _rig.skeleton.get_bone_global_pose(left_hand_index)
		hand_error = hand_world.origin.distance_to(grip.global_position)
		if not _support_diagnostics_printed:
			_support_diagnostics_printed = true
			var shoulder := _rig.skeleton.global_transform * _rig.skeleton.get_bone_global_pose(_rig.aim_modifier.left_arm_index)
			var elbow := _rig.skeleton.global_transform * _rig.skeleton.get_bone_global_pose(_rig.aim_modifier.left_forearm_index)
			var upper_length := shoulder.origin.distance_to(elbow.origin)
			var lower_length := elbow.origin.distance_to(hand_world.origin)
			print("[GripGeometry] shoulder=%s elbow=%s hand=%s actual_grip=%s solver_grip=%s upper_length=%.6f lower_length=%.6f max_reach=%.6f target_distance=%.6f reachable=%s solver_error=%.6f measured_error=%.6f" % [shoulder.origin, elbow.origin, hand_world.origin, grip.global_position, _rig.aim_modifier.last_grip_world.origin, upper_length, lower_length, upper_length + lower_length, shoulder.origin.distance_to(grip.global_position), _rig.aim_modifier.left_grip_reachable, _rig.aim_modifier.left_grip_error, hand_error])
	var right_hand_world := _rig.skeleton.global_transform * _rig.skeleton.get_bone_global_pose(_rig.get_right_hand_bone_index())
	var right_hand_error := right_hand_world.origin.distance_to(right_grip.global_position) if right_grip != null else INF
	_latest_pose = {"forward": -muzzle.global_basis.z.normalized(), "hand_error": hand_error, "right_hand_error": right_hand_error, "right_hand_position": right_hand_world.origin}


func _measure(label: String, elapsed: float, log_sample: bool = true) -> Dictionary:
	var forward: Vector3 = _latest_pose.get("forward", Vector3.ZERO)
	var aim := _aim.normalized()
	var dot3d := clampf(forward.dot(aim), -1.0, 1.0)
	var angle := rad_to_deg(acos(dot3d))
	var pitch := rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	var sample := {"forward": forward, "aim": aim, "dot": dot3d, "pitch": pitch, "angle": angle, "hand_error": _latest_pose.get("hand_error", INF), "right_hand_error": _latest_pose.get("right_hand_error", INF)}
	if log_sample:
		print("[Muzzle3D] %s t=%.3f muzzle=%s aim=%s dot=%.8f pitch=%.5fdeg angle=%.5fdeg left_grip_error=%.6f right_grip_error=%.6f" % [label, elapsed, forward, aim, dot3d, pitch, angle, sample.hand_error, sample.right_hand_error])
	return sample


func _assert_aim(sample: Dictionary, minimum_dot: float, maximum_vertical_error: float, label: String) -> void:
	_check(float(sample.dot) >= minimum_dot and absf(sample.forward.y - sample.aim.y) <= maximum_vertical_error, label + " aligns full 3D muzzle including vertical component")


func _weapon_transforms() -> Array[Transform3D]:
	var socket := _rig.get_weapon_socket(&"blaster")
	var weapon := socket.get_node("Weapon_blaster") as Node3D
	var sway := weapon.get_node("WeaponSway") as Node3D
	var recoil := sway.get_node("WeaponRecoil") as Node3D
	return [socket.transform, weapon.transform, sway.transform, recoil.transform]


func _transforms_match(before: Array[Transform3D], after: Array[Transform3D]) -> bool:
	for index in range(before.size()):
		if not before[index].is_equal_approx(after[index]):
			return false
	return true


func _root_motion_is_flat(wanted_clip: StringName) -> bool:
	var animation := _rig.animation_player.get_animation(wanted_clip)
	var rest_position := _rig.skeleton.get_bone_rest(_rig._hips_bone_index).origin
	var found_position_track := false
	for track_index in range(animation.get_track_count()):
		if not str(animation.track_get_path(track_index)).to_lower().contains("hips") or animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		found_position_track = true
		for key_index in range(animation.track_get_key_count(track_index)):
			var key_position: Vector3 = animation.track_get_key_value(track_index, key_index)
			if absf(key_position.x - rest_position.x) > 0.002 or absf(key_position.z - rest_position.z) > 0.002:
				return false
	return found_position_track


func _find_bone_track(animation: Animation, bone_name: String) -> NodePath:
	if animation != null:
		for track_index in range(animation.get_track_count()):
			var track_path := animation.track_get_path(track_index)
			if String(track_path).ends_with(":" + bone_name):
				return track_path
	return NodePath()


func _on_action_finished(animation_name: StringName) -> void:
	_finished_animations.append(animation_name)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		_failures.append(label)
		push_error("FAIL: %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("PLAYER VISUAL RIG REGRESSION TEST: PASS (%d checks)" % _checks)
		quit(0)
	else:
		print("PLAYER VISUAL RIG REGRESSION TEST: FAIL (%d failures / %d checks)" % [_failures.size(), _checks])
		quit(1)
