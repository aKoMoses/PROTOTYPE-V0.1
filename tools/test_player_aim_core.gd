extends SceneTree

## Rig-only regression: usable even while the arena/Player integration is edited.
## The production Player, projectile damage and touch UI are covered separately
## by test_player_visual_rig.gd, test_blaster.gd and test_touch_controls.gd.
const STEP := 1.0 / 60.0
var rig: PlayerVisualRig
var muzzle: Marker3D
var aim := Vector3.FORWARD
var movement := Vector3.ZERO
var failures: Array[String] = []
var angle := 0.0
var maximum_angle := 0.0
var maximum_hand_error := 0.0
var wrappers: Array[Node3D] = []
var rest_transforms: Array[Transform3D] = []
var recovered_drift := 0.0
var baseline_forward := Vector3.ZERO
var forward := Vector3.ZERO


func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	call_deferred("_run")


func _run() -> void:
	rig = PlayerVisualRig.new()
	rig.scale = Vector3.ONE * 0.88
	root.add_child(rig)
	rig.setup_visual_motion()
	if not rig.install_animated_model(null):
		push_error("AIM CORE: production rig could not load")
		quit(1)
		return
	var weapon := Node3D.new()
	rig.equip_weapon(&"blaster", weapon, {})
	var sway := Node3D.new()
	sway.name = "WeaponSway"
	weapon.add_child(sway)
	var recoil := Node3D.new()
	recoil.name = "WeaponRecoil"
	sway.add_child(recoil)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.08, -0.88)
	recoil.add_child(muzzle)
	var grip := Marker3D.new()
	grip.name = "LeftHandGrip"
	grip.position = Vector3(-0.10, -0.04, -0.20)
	recoil.add_child(grip)
	rig.configure_left_hand_support(&"blaster")
	rig.set_aim_enabled(true, true)
	wrappers.assign([rig.get_weapon_socket(&"blaster"), weapon, sway, recoil])
	for wrapper in wrappers:
		rest_transforms.append(wrapper.transform)
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.skeleton_updated.connect(_sample)
	await _step()
	baseline_forward = forward
	_log("before", 0.0)
	for shot in range(10):
		var charge := float(shot % 2)
		if not rig.play_shot_kick(charge):
			failures.append("shot rejected")
		for frame in range(31):
			if frame > 0:
				# Turn the aim and reverse movement while recovering, preserving
				# the authored running phase. Return to the initial aim at the end.
				aim = Vector3.RIGHT if frame >= 4 and frame < 12 else Vector3.FORWARD
				movement = -aim if frame < 6 else aim
				await _step()
			if shot < 2 and frame in [0, 3, 6, 12, 21, 30]:
				_log("charged" if charge > 0.0 else "normal", frame * STEP)
			if angle > 1.0:
				failures.append("recoil exceeded one degree")
			if frame >= 12:
				recovered_drift = maxf(recovered_drift, _angle(forward, baseline_forward))
				if angle > 0.01:
					failures.append("muzzle did not return to aim at 200 ms")
			for index in range(wrappers.size()):
				if not wrappers[index].transform.is_equal_approx(rest_transforms[index]):
					failures.append("local weapon transform drift")
	if maximum_hand_error > 0.001:
		failures.append("left hand missed reachable grip")
	print("AIM CORE: %s | ten alternating normal/charged shots | max_angle=%.6fdeg | recovery_drift=%.6fdeg | max_hand_error=%.8fm | fixed_transforms=%s" % ["PASS" if failures.is_empty() else "FAIL", maximum_angle, recovered_drift, maximum_hand_error, failures.is_empty()])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _step() -> void:
	await process_frame
	rig.update_visual_state(movement, aim, 0.0 if movement.is_zero_approx() else 5.0, 5.0, STEP)
	rig.animation_tree.advance(STEP)
	rig.skeleton.advance(STEP)
	await rig.skeleton.skeleton_updated


func _sample() -> void:
	forward = -muzzle.global_basis.z.normalized()
	angle = _angle(forward, aim)
	maximum_angle = maxf(maximum_angle, angle)
	maximum_hand_error = maxf(maximum_hand_error, rig.aim_modifier.left_grip_error)


func _angle(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(atan2(a.cross(b).length(), a.dot(b)))


func _log(label: String, elapsed: float) -> void:
	print("[CoreMuzzle3D] %s t=%.3f muzzle=%s aim=%s dot=%.8f pitch=%.6fdeg angle=%.6fdeg grip_error=%.8fm" % [label, elapsed, forward, aim, forward.dot(aim), rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))), angle, rig.aim_modifier.left_grip_error])
