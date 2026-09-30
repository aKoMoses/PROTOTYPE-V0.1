extends SceneTree

# Standalone regression: does not load main.tscn or the training bot. Use:
# Godot --headless --path <project> --script res://tools/test_shotgun_visual.gd
# Sample in skeleton_updated: Skeleton3D restores its unmodified animation pose
# after modifiers, so reading bones on an arbitrary idle frame is misleading.
const STEP := 1.0 / 60.0
const SAMPLE_FRAMES := [0, 3, 6, 12, 21, 30]
var _failures: Array[String] = []
var _checks := 0
var _player: ShotgunProbe
var _rig: PlayerVisualRig
var _stage: Node3D
var _move := Vector3.ZERO
var _aim := Vector3.FORWARD
var _pose: Dictionary = {}


class ShotgunProbe:

	extends "res://scripts/player.gd"

	var emissions: Array[Dictionary] = []
	var shot_started_at := 0

	func _spawn_shotgun_projectile(start: Vector3, endpoint: Vector3, salvo: Dictionary, index: int) -> void:
		emissions.append({
			"start": start,
			"endpoint": endpoint,
			"index": index,
			"muzzle": _shotgun_muzzle.global_position,
			"muzzle_forward": -_shotgun_muzzle.global_basis.z.normalized(),
			"muzzle_up": _shotgun_muzzle.global_basis.y.normalized(),
			"aim": aim_direction.normalized(),
			"attack_direction": _shotgun_attack_direction,
			"attack_origin": _shotgun_attack_origin,
			"player_origin": global_position,
			"elapsed_ms": Time.get_ticks_msec() - shot_started_at,
		})
		# Keep the real projectile creation, spread and travel path under test.
		super(start, endpoint, salvo, index)


func _initialize() -> void:
	_stage = Node3D.new()
	_stage.name = "ShotgunVisualTestStage"
	root.add_child(_stage)
	current_scene = _stage
	_player = ShotgunProbe.new()
	_player.name = "Player"
	_stage.add_child(_player)
	await process_frame
	await process_frame
	_rig = _player.get_node_or_null("VisualRoot") as PlayerVisualRig
	_check(_rig != null and _rig.skeleton != null, "standalone player installs its GLB skeleton")
	if _rig == null or _rig.skeleton == null:
		_finish()
		return
	await _test_touch_motion()
	_player.clear_touch_inputs()
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.global_position = Vector3.ZERO
	_rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_rig.skeleton.skeleton_updated.connect(_capture_final_pose)
	_player.set_weapon("shotgun")
	_player._begin_weapon_aim()
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	_test_structure_and_parameters()
	await _test_weapon_switches()
	for case_data in [
		["idle", Vector3.ZERO, Vector3.FORWARD],
		["run_forward", Vector3.FORWARD, Vector3.FORWARD],
		["run_backward", Vector3.BACK, Vector3.FORWARD],
		["strafe_left_aim_right", Vector3.LEFT, Vector3.RIGHT],
		["strafe_right_aim_left", Vector3.RIGHT, Vector3.LEFT],
		["aim_changes_during_recovery", Vector3.LEFT, Vector3.FORWARD],
	]:
		await _test_pose_case(String(case_data[0]), case_data[1], case_data[2])
	await _test_repeated_recoil()
	await _test_emission_and_touch_attack()
	await _test_switch_cancels_pending_emission()
	_finish()


func _test_touch_motion() -> void:
	_player.set_weapon("shotgun")
	var rotation_before := _player.rotation.y
	_player.set_touch_move_vector(Vector2.RIGHT)
	_player.set_touch_aim_vector(Vector2.UP)
	await create_timer(0.20).timeout
	_check(_player.move_direction.length_squared() > 0.5 and absf(_player.move_direction.dot(_player.aim_direction)) < 0.05, "touch movement and shotgun aim remain independent")
	_check(absf(wrapf(_player.rotation.y - rotation_before, -PI, PI)) < 0.02, "touch aim does not rotate the CharacterBody")
	_check(not _rig.aim_modifier.aiming and _player.get_weapon_pose_state_name() in [&"IDLE", &"LOCOMOTION"], "touch aim alone keeps the shotgun in its lowered locomotion pose")


func _test_structure_and_parameters() -> void:
	var socket := _rig.get_weapon_socket(&"shotgun")
	var weapon := _weapon_root(&"shotgun")
	var shotgun := weapon.get_node_or_null("WeaponSway/WeaponRecoil/Shotgun") as Node3D
	var right_grip := shotgun.get_node_or_null("RightHandGrip") as Marker3D if shotgun != null else null
	_check(socket != null and socket.get_parent() == _rig.right_hand_attachment and weapon.get_parent() == socket, "shotgun attaches through the right hand and dedicated socket")
	_check(shotgun != null, "dedicated Shotgun scene is under the existing recoil wrappers")
	if shotgun == null:
		return
	_check(shotgun.get_node_or_null("VisualRoot/ShotgunGLB") is Node3D, "Shotgun scene contains the imported GLB under VisualRoot")
	_check(shotgun.get_node_or_null("Muzzle") is Marker3D and shotgun.get_node_or_null("LeftHandGrip") is Marker3D and right_grip != null, "Shotgun scene exposes muzzle and both hand-grip markers")
	_check(right_grip != null and not right_grip.position.is_zero_approx(), "shotgun rear-grip anchor compensates the imported mesh offset")
	_check(float(_pose.get("right_hand_error", INF)) <= 0.001, "shotgun rear grip is seated on the animated right hand")
	_check(_rig.get_weapon_muzzle(&"shotgun") == shotgun.get_node_or_null("Muzzle"), "recursive muzzle lookup resolves the nested scene marker")
	_check(_wrapper_transforms_are_identity(), "weapon, sway, recoil and Shotgun scene roots are identity")
	_check(_rig.animation_tree.active and _rig.aim_modifier.aiming, "shotgun uses the active AnimationTree when combat aim is requested")
	var expected := {
		"_shotgun_pellet_speed": 22.0,
		"_shotgun_max_range": 7.0,
		"_shotgun_falloff_start": 3.0,
		"_shotgun_pellet_damage": 20.0,
		"_shotgun_minimum_damage": 8.0,
		"_shotgun_hitbox_radius": 0.78,
		"_shotgun_preparation": 0.10,
		"_shotgun_recovery": 0.60,
		"_shotgun_magazine_size": 3.0,
		"_shotgun_reload_duration": 1.80,
	}
	var parameters_unchanged := true
	for property in expected:
		parameters_unchanged = parameters_unchanged and is_equal_approx(float(_player.get(property)), float(expected[property]))
	_check(parameters_unchanged and _player._shotgun_pellet_angles == [-14.0, -8.0, -3.0, 3.0, 8.0, 14.0], "integration preserves shotgun damage, spread, speed, range, timing and magazine values")
	_check(is_equal_approx(_player._shotgun_damage_at_distance(2.0), 20.0) and is_equal_approx(_player._shotgun_damage_at_distance(5.0), 14.0) and is_equal_approx(_player._shotgun_damage_at_distance(7.0), 8.0), "damage falloff remains 20 to 8 between 3 and 7 units")


func _test_weapon_switches() -> void:
	var shotgun_id := _weapon_root(&"shotgun").get_instance_id()
	var blaster_id := _weapon_root(&"blaster").get_instance_id()
	var switches_ok := true
	var maximum_support_error := 0.0
	for index in range(8):
		var weapon_id := "blaster" if index % 2 == 0 else "shotgun"
		_player.set_weapon(weapon_id)
		_player._begin_weapon_aim()
		await _settle(Vector3.ZERO, Vector3.FORWARD)
		maximum_support_error = maxf(maximum_support_error, float(_pose.get("hand_error", INF)))
		switches_ok = switches_ok and _rig.aim_modifier.aiming and _rig.aim_modifier.support_enabled
		switches_ok = switches_ok and _weapon_root(&"shotgun").visible == (weapon_id == "shotgun")
		switches_ok = switches_ok and _weapon_root(&"blaster").visible == (weapon_id == "blaster")
		switches_ok = switches_ok and _weapon_root(&"shotgun").get_instance_id() == shotgun_id
		switches_ok = switches_ok and _weapon_root(&"blaster").get_instance_id() == blaster_id
		switches_ok = switches_ok and _player.find_children("ShotgunGLB", "", true, false).size() == 1
	_check(switches_ok, "eight weapon switches preserve one instance, visibility and requested AimPose for each weapon")
	_check(maximum_support_error <= 0.035, "weapon switches retarget left-hand support to the active grip")
	print("[ShotgunSwitches] switches=8 maximum_support_error=%.6f" % maximum_support_error)


func _test_pose_case(label: String, movement: Vector3, aim: Vector3) -> void:
	await _settle(movement, aim)
	_check(_pose_aligned(), label + " full 3D muzzle direction aligns before recoil")
	var fixed_transforms := _weapon_transforms()
	var root_position := _player.global_position
	_check(_rig.play_shot_kick(), label + " accepts skeletal recoil")
	var maximum_angle := 0.0
	var maximum_support_error := 0.0
	var maximum_right_hand_error := 0.0
	var recovered_alignment := true
	var wrappers_fixed := true
	var phase_before := _rig._locomotion_playback.get_current_play_position()
	var phase_advanced := movement.is_zero_approx()
	for frame in range(31):
		if frame > 0:
			if frame == 4 and label == "aim_changes_during_recovery":
				_aim = Vector3.RIGHT
			await _step(STEP)
		wrappers_fixed = wrappers_fixed and _transforms_equal(fixed_transforms, _weapon_transforms())
		maximum_support_error = maxf(maximum_support_error, float(_pose.get("hand_error", INF)))
		maximum_right_hand_error = maxf(maximum_right_hand_error, float(_pose.get("right_hand_error", INF)))
		maximum_angle = maxf(maximum_angle, _pose_angle())
		if frame >= 12 and frame in SAMPLE_FRAMES:
			recovered_alignment = recovered_alignment and _pose_aligned()
		if frame == 6 and not movement.is_zero_approx():
			var duration := _rig.animation_player.get_animation("run").length
			var actual_delta := fposmod(_rig._locomotion_playback.get_current_play_position() - phase_before, duration)
			var expected_delta := 6.0 * STEP * float(_rig.animation_tree.get("parameters/Locomotion/run/TimeScale/scale"))
			phase_advanced = absf(actual_delta - expected_delta) <= 0.005
	_check(maximum_support_error <= 0.035, label + " left hand stays within 3.5 cm of the support grip")
	_check(maximum_right_hand_error <= 0.001, label + " rear grip stays attached to the right hand")
	_check(recovered_alignment and not _rig.is_shot_kick_active(), label + " returns to aligned AimPose after recoil")
	_check(wrappers_fixed and _wrapper_transforms_are_identity(), label + " skeletal recoil leaves attachment wrappers unchanged")
	_check(phase_advanced and _player.global_position.is_equal_approx(root_position), label + " recoil preserves locomotion phase and adds no root motion")
	if label != "aim_changes_during_recovery":
		_check(maximum_angle <= 5.0, label + " recoil stays within the controlled 3D envelope")
	print("[ShotgunPose] %s max_angle=%.5fdeg support_error=%.6f" % [label, maximum_angle, maximum_support_error])


func _test_repeated_recoil() -> void:
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	var before: Vector3 = _pose.forward
	var transforms_before := _weapon_transforms()
	var maximum_drift := 0.0
	var maximum_support_error := 0.0
	var shots_accepted := true
	for shot in range(10):
		shots_accepted = _rig.play_shot_kick() and shots_accepted
		for frame in range(30):
			await _step(STEP)
			maximum_support_error = maxf(maximum_support_error, float(_pose.get("hand_error", INF)))
		maximum_drift = maxf(maximum_drift, rad_to_deg(before.angle_to(_pose.forward)))
	_check(shots_accepted and maximum_drift <= 0.05, "ten consecutive skeletal shots return to the original 3D aim without drift")
	_check(maximum_support_error <= 0.035 and _transforms_equal(transforms_before, _weapon_transforms()), "repeated shots preserve support and all attachment transforms")
	print("[ShotgunRepeated] count=10 maximum_drift=%.6fdeg support_error=%.6f" % [maximum_drift, maximum_support_error])


func _test_emission_and_touch_attack() -> void:
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	_player.reset_shotgun_state()
	_player.emissions.clear()
	_player.shot_started_at = Time.get_ticks_msec()
	_player.set_touch_attack_held(true)
	_player._update_attack()
	_player.set_touch_attack_held(false)
	_check(_player._shotgun_attack_busy and _player.get_shotgun_ammo() == 2, "touch fire starts one attack and consumes one shell")
	_check(_player.emissions.is_empty() and not _rig.is_shot_kick_active(), "preparation does not emit pellets or start recoil early")
	# Move and turn between the trigger and the delayed emission. Capture inside
	# projectile creation, before physics can advance the real pellets.
	_player.global_position = Vector3(2.0, 0.0, 1.0)
	_player.set_touch_aim_vector(Vector2.RIGHT)
	_player._update_aim()
	_aim = _player.aim_direction
	var deadline := Time.get_ticks_msec() + 2000
	while _player.emissions.size() < 6 and Time.get_ticks_msec() < deadline:
		await _step(STEP)
	_check(_player.emissions.size() == 6, "delayed shotgun emission creates exactly six real pellets")
	var starts_at_muzzle := not _player.emissions.is_empty()
	var fresh_origin_and_aim := starts_at_muzzle
	var kick_at_emission := starts_at_muzzle and _rig.is_shot_kick_active()
	var spread_preserved := starts_at_muzzle
	var minimum_elapsed := 999999
	for record in _player.emissions:
		starts_at_muzzle = starts_at_muzzle and record.start.distance_to(record.muzzle) < 0.0001
		fresh_origin_and_aim = fresh_origin_and_aim and record.attack_origin.distance_to(record.player_origin) < 0.0001
		fresh_origin_and_aim = fresh_origin_and_aim and record.attack_direction.dot(Vector3.RIGHT) >= 0.9999 and record.aim.dot(Vector3.RIGHT) >= 0.9999
		minimum_elapsed = mini(minimum_elapsed, int(record.elapsed_ms))
		# Pellets fan around the evaluated barrel axis at every range. A nearby
		# convergence point would tilt the fan away from that live aim.
		var center_direction: Vector3 = record.attack_direction
		var expected_direction: Vector3 = center_direction.rotated(Vector3.UP, deg_to_rad(float(_player._shotgun_pellet_angles[int(record.index)])))
		var actual_direction: Vector3 = record.endpoint - record.start
		spread_preserved = spread_preserved and actual_direction.normalized().dot(expected_direction) >= 0.9999 and record.muzzle_forward.dot(record.aim) >= 0.98
	_check(starts_at_muzzle, "all six pellets originate at the current nested GLB muzzle")
	_check(fresh_origin_and_aim and spread_preserved, "emission samples current player position and aim while retaining six spread angles")
	_check(kick_at_emission and minimum_elapsed >= 80, "skeletal recoil begins at emission after the 100 ms preparation")
	_check(_wrapper_transforms_are_identity(), "actual touch-fired attack leaves weapon wrappers at identity")
	_player.clear_touch_inputs()
	_player.reset_shotgun_state()
	await _settle(Vector3.ZERO, Vector3.RIGHT)
	_check(_pose_aligned(), "actual touch-fired shotgun recovers to the new aim")
	print("[ShotgunEmission] pellets=%d preparation_ms=%d current_muzzle=%s" % [_player.emissions.size(), minimum_elapsed, starts_at_muzzle])


func _test_switch_cancels_pending_emission() -> void:
	_player.reset_shotgun_state()
	_player.emissions.clear()
	_player._perform_shotgun_attack()
	var pending_token := _player._shotgun_attack_token
	_player.set_weapon("blaster")
	var deadline := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await _step(STEP)
	_check(_player._shotgun_attack_token != pending_token and _player.emissions.is_empty(), "weapon switch invalidates pending shotgun emission token")
	_check(not _rig.aim_modifier.aiming, "cancelled shotgun preparation returns the swapped blaster to ready-low")
	_player._begin_weapon_aim()
	await _settle(Vector3.ZERO, Vector3.RIGHT)
	_check(_rig.aim_modifier.aiming and _pose_aligned(), "blaster AimPose remains usable after cancelling shotgun preparation")
	_player.set_weapon("shotgun")
	_player._begin_weapon_aim()
	await _settle(Vector3.ZERO, Vector3.FORWARD)
	_check(_pose_aligned() and float(_pose.hand_error) <= 0.035, "re-equipping after cancellation restores shotgun aim and support")


func _settle(movement: Vector3, aim: Vector3) -> void:
	_move = movement
	_aim = aim
	for frame in range(45):
		await _step(STEP)


func _step(delta: float) -> void:
	await process_frame
	_player.aim_direction = _aim
	_player.move_direction = _move
	_player._update_weapon_ambient_motion(delta)
	_rig.update_visual_state(_move, _aim, 0.0 if _move.is_zero_approx() else _player.move_speed, _player.move_speed, delta)
	_rig.animation_tree.advance(delta)
	_rig.skeleton.advance(delta)
	await _rig.skeleton.skeleton_updated


func _capture_final_pose() -> void:
	var weapon_id := StringName(_player.get_weapon_id())
	var muzzle := _rig.get_weapon_muzzle(weapon_id)
	var weapon := _weapon_root(weapon_id)
	var grip := weapon.find_child("LeftHandGrip", true, false) as Node3D if weapon != null else null
	var right_grip := weapon.find_child("RightHandGrip", true, false) as Node3D if weapon != null else null
	var left_hand_index := _rig.skeleton.find_bone(String(_rig.left_hand_bone_name))
	var right_hand_index := _rig.skeleton.find_bone(String(_rig.right_hand_bone_name))
	var hand_error := INF
	var right_hand_error := INF
	if grip != null and left_hand_index >= 0:
		var hand_world := _rig.skeleton.global_transform * _rig.skeleton.get_bone_global_pose(left_hand_index)
		hand_error = hand_world.origin.distance_to(grip.global_position)
	if right_grip != null and right_hand_index >= 0:
		var right_hand_world := _rig.skeleton.global_transform * _rig.skeleton.get_bone_global_pose(right_hand_index)
		right_hand_error = right_hand_world.origin.distance_to(right_grip.global_position)
	_pose = {"forward": -muzzle.global_basis.z.normalized() if muzzle != null else Vector3.ZERO, "hand_error": hand_error, "right_hand_error": right_hand_error}


func _pose_aligned() -> bool:
	var forward: Vector3 = _pose.get("forward", Vector3.ZERO)
	return forward.dot(_aim.normalized()) >= 0.98 and absf(forward.y - _aim.normalized().y) <= 0.05


func _pose_angle() -> float:
	var forward: Vector3 = _pose.get("forward", Vector3.ZERO)
	return rad_to_deg(acos(clampf(forward.dot(_aim.normalized()), -1.0, 1.0)))


func _weapon_root(weapon_id: StringName) -> Node3D:
	var socket := _rig.get_weapon_socket(weapon_id)
	return socket.get_node_or_null("Weapon_%s" % weapon_id) as Node3D if socket != null else null


func _weapon_transforms() -> Array[Transform3D]:
	var socket := _rig.get_weapon_socket(&"shotgun")
	var weapon := _weapon_root(&"shotgun")
	var sway := weapon.get_node("WeaponSway") as Node3D
	var recoil := sway.get_node("WeaponRecoil") as Node3D
	return [socket.transform, weapon.transform, sway.transform, recoil.transform]


func _wrapper_transforms_are_identity() -> bool:
	var transforms := _weapon_transforms()
	for index in range(1, transforms.size()):
		if not transforms[index].is_equal_approx(Transform3D.IDENTITY):
			return false
	var shotgun := _weapon_root(&"shotgun").get_node_or_null("WeaponSway/WeaponRecoil/Shotgun") as Node3D
	return shotgun != null and shotgun.transform.is_equal_approx(Transform3D.IDENTITY)


func _transforms_equal(before: Array[Transform3D], after: Array[Transform3D]) -> bool:
	for index in range(before.size()):
		if not before[index].is_equal_approx(after[index]):
			return false
	return true


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("FAIL: " + label)


func _finish() -> void:
	if _failures.is_empty():
		print("SHOTGUN GLB VISUAL REGRESSION: PASS (%d checks)" % _checks)
		quit(0)
	else:
		print("SHOTGUN GLB VISUAL REGRESSION: FAIL (%d failures / %d checks)" % [_failures.size(), _checks])
		quit(1)
