extends SkeletonModifier3D
class_name PlayerAimModifier

## Runs after locomotion: stabilise the firing stance, absorb the impulse in
## the shoulder/arm chain, then solve the support arm against that same pose.
signal shot_finished

const KICK_TIME := 0.05
const RECOVERY_TIME := 0.12
const MEKATANA_VISUAL := preload("res://scripts/mekatana_visual.gd")

var aiming := false
var counter_guard := false
var carrying := false
var spine_index := -1
var spine_basis := Basis.IDENTITY
var hips_index := -1
var left_up_leg_index := -1
var right_up_leg_index := -1
var spine2_index := -1
var right_shoulder_index := -1
var right_arm_index := -1
var right_forearm_index := -1
var right_hand_index := -1
var left_arm_index := -1
var left_forearm_index := -1
var left_hand_index := -1
var grip_from_hand := Transform3D.IDENTITY
var support_enabled := false
var support_use_orientation := false
var left_grip_error := 0.0
var left_grip_reachable := false
var last_left_hand_world := Transform3D.IDENTITY
var last_right_hand_world := Transform3D.IDENTITY
var last_grip_world := Transform3D.IDENTITY
var shot_time := KICK_TIME + RECOVERY_TIME
var shot_strength := 1.0
var recoil_weight := 0.0
var punch_phase := ""
var punch_progress := 0.0
var pelto_phase := ""
var pelto_progress := 0.0
var mekatana_step := 0
var mekatana_phase := ""
var mekatana_progress := 0.0
var mekatana_equipped := false
var _mekatana_guard_yaw := 0.0
var _mekatana_prepare_start := 0.0


func trigger_shot(charge_ratio: float) -> void:
	shot_time = 0.0
	shot_strength = lerpf(1.0, 1.35, clampf(charge_ratio, 0.0, 1.0))


func cancel_shot() -> void:
	shot_time = KICK_TIME + RECOVERY_TIME
	recoil_weight = 0.0


func is_shot_active() -> bool:
	return shot_time < KICK_TIME + RECOVERY_TIME


func set_fulguro_pose(phase: String, progress: float) -> void:
	punch_phase = phase
	punch_progress = clampf(progress, 0.0, 1.0)


func clear_fulguro_pose() -> void:
	punch_phase = ""
	punch_progress = 0.0


func set_pelto_pose(phase: String, progress: float) -> void:
	pelto_phase = phase
	pelto_progress = clampf(progress, 0.0, 1.0)


func clear_pelto_pose() -> void:
	pelto_phase = ""
	pelto_progress = 0.0


func set_mekatana_pose(step: int, phase: String, progress: float) -> void:
	if phase == "preparation" and (mekatana_phase != phase or mekatana_step != step):
		_mekatana_prepare_start = _mekatana_guard_yaw
	mekatana_step = clampi(step, 0, 2)
	mekatana_phase = phase
	mekatana_progress = clampf(progress, 0.0, 1.0)


func clear_mekatana_pose() -> void:
	if mekatana_phase == "":
		return
	# A completed recovery leaves a side guard for the following swing. Real
	# interruptions return to neutral instead of retaining a delayed action.
	_mekatana_guard_yaw = MEKATANA_VISUAL.guard_yaw(mekatana_step) if mekatana_phase == "recovery" else 0.0
	mekatana_phase = ""
	mekatana_progress = 0.0


func is_fulguro_pose_active() -> bool:
	return punch_phase != ""


func _process_modification_with_delta(delta: float) -> void:
	var rig_skeleton := get_skeleton()
	if rig_skeleton == null or (not counter_guard and not aiming and not carrying and punch_phase == "" and pelto_phase == "" and mekatana_phase == "") or spine_index < 0 or right_hand_index < 0:
		cancel_shot()
		return
	if counter_guard:
		cancel_shot()
		_set_global_basis(rig_skeleton, spine_index, spine_basis)
		_rotate_global_axis(rig_skeleton, right_shoulder_index, Vector3.UP, -18.0)
		_rotate_global_axis(rig_skeleton, right_arm_index, Vector3.RIGHT, 28.0)
		_rotate_global_axis(rig_skeleton, right_forearm_index, Vector3.RIGHT, 52.0)
		last_right_hand_world = rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(right_hand_index)
		if support_enabled:
			_solve_support_arm(rig_skeleton)
		return
	if punch_phase != "":
		cancel_shot()
		_apply_fulguro_pose(rig_skeleton)
		last_right_hand_world = rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(right_hand_index)
		return
	if pelto_phase != "":
		cancel_shot()
		_apply_pelto_pose(rig_skeleton)
		last_right_hand_world = rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(right_hand_index)
		return
	if mekatana_equipped or mekatana_phase != "":
		cancel_shot()
		_apply_mekatana_pose(rig_skeleton)
		last_right_hand_world = rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(right_hand_index)
		if support_enabled:
			_solve_support_arm(rig_skeleton)
		return
	if not aiming:
		cancel_shot()
		# The unarmed run pitches the pelvis strongly. Keep the ready torso upright
		# while preserving the legs and bob, as in the firing stance.
		_set_global_basis(rig_skeleton, spine_index, spine_basis)
		last_right_hand_world = rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(right_hand_index)
		if support_enabled:
			_solve_support_arm(rig_skeleton)
		return
	var was_active := is_shot_active()
	shot_time = minf(shot_time + delta, KICK_TIME + RECOVERY_TIME)
	if shot_time < KICK_TIME:
		recoil_weight = smoothstep(0.0, KICK_TIME, shot_time)
	else:
		recoil_weight = 1.0 - smoothstep(KICK_TIME, KICK_TIME + RECOVERY_TIME, shot_time)
	var amount := recoil_weight * shot_strength
	# The pelvis still supplies translation/bob to the torso, but its authored
	# run tilt must not tilt the constant AimPose (or the fixed weapon socket).
	_set_global_basis(rig_skeleton, spine_index, spine_basis)
	if amount > 0.0:
		_rotate_global(rig_skeleton, spine2_index, 0.25 * amount)
		# Model forward is +Z. Pull the shoulder backward by at most 2.7 cm
		# in model units; the entire hand/weapon chain follows the shoulder.
		var parent := rig_skeleton.get_bone_parent(right_shoulder_index) if right_shoulder_index >= 0 else -1
		if right_shoulder_index >= 0 and parent >= 0:
			var parent_basis := rig_skeleton.get_bone_global_pose(parent).basis
			var offset := parent_basis.inverse() * Vector3(0.0, 0.0, -0.020 * amount)
			rig_skeleton.set_bone_pose_position(right_shoulder_index, rig_skeleton.get_bone_pose_position(right_shoulder_index) + offset)
		_rotate_global(rig_skeleton, right_shoulder_index, 0.20 * amount)
		_rotate_global(rig_skeleton, right_arm_index, 0.55 * amount)
		_rotate_global(rig_skeleton, right_forearm_index, -0.30 * amount)
		_rotate_global(rig_skeleton, right_hand_index, -0.15 * amount)
	last_right_hand_world = rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(right_hand_index)
	if support_enabled:
		_solve_support_arm(rig_skeleton)
	if was_active and not is_shot_active():
		shot_finished.emit()


func _apply_fulguro_pose(rig_skeleton: Skeleton3D) -> void:
	var windup := smoothstep(0.0, 1.0, punch_progress) if punch_phase == "preparation" else 0.0
	var extension := smoothstep(0.0, 1.0, punch_progress) if punch_phase == "active" else 1.0 - smoothstep(0.0, 1.0, punch_progress) if punch_phase == "recovery" else 0.0
	_set_global_basis(rig_skeleton, spine_index, spine_basis)
	_rotate_global_axis(rig_skeleton, spine2_index, Vector3.UP, -14.0 * windup + 10.0 * extension)
	_rotate_global_axis(rig_skeleton, right_shoulder_index, Vector3.UP, -28.0 * windup + 30.0 * extension)
	_rotate_global_axis(rig_skeleton, right_arm_index, Vector3.RIGHT, 42.0 * windup - 24.0 * extension)
	_rotate_global_axis(rig_skeleton, right_forearm_index, Vector3.RIGHT, 58.0 * windup - 46.0 * extension)
	_rotate_global_axis(rig_skeleton, right_hand_index, Vector3.RIGHT, -16.0 * windup + 9.0 * extension)
	if right_shoulder_index >= 0:
		var parent := rig_skeleton.get_bone_parent(right_shoulder_index)
		if parent >= 0:
			var parent_basis := rig_skeleton.get_bone_global_pose(parent).basis
			var world_offset := Vector3(0.0, 0.0, -0.035 * windup + 0.055 * extension)
			rig_skeleton.set_bone_pose_position(right_shoulder_index, rig_skeleton.get_bone_pose_position(right_shoulder_index) + parent_basis.inverse() * world_offset)


func _apply_pelto_pose(rig_skeleton: Skeleton3D) -> void:
	var weights := pelto_pose_weights(pelto_phase, pelto_progress)
	var prepare := weights.x
	var strike := weights.y
	var crouch := prepare * 0.72 + strike
	_set_global_basis(rig_skeleton, spine_index, spine_basis)
	if hips_index >= 0:
		rig_skeleton.set_bone_pose_position(hips_index, rig_skeleton.get_bone_pose_position(hips_index) + Vector3(0.0, -0.035 * crouch, 0.018 * strike))
	_rotate_global_axis(rig_skeleton, left_up_leg_index, Vector3.RIGHT, 8.0 * crouch)
	_rotate_global_axis(rig_skeleton, right_up_leg_index, Vector3.RIGHT, 8.0 * crouch)
	_rotate_global_axis(rig_skeleton, spine2_index, Vector3.RIGHT, -16.0 * prepare + 38.0 * strike)
	_rotate_global_axis(rig_skeleton, right_shoulder_index, Vector3.RIGHT, -48.0 * prepare + 72.0 * strike)
	_rotate_global_axis(rig_skeleton, right_shoulder_index, Vector3.UP, -24.0 * prepare + 16.0 * strike)
	_rotate_global_axis(rig_skeleton, right_arm_index, Vector3.RIGHT, -62.0 * prepare + 104.0 * strike)
	_rotate_global_axis(rig_skeleton, right_forearm_index, Vector3.RIGHT, 38.0 * prepare - 70.0 * strike)
	_rotate_global_axis(rig_skeleton, right_hand_index, Vector3.RIGHT, -18.0 * prepare + 34.0 * strike)


static func pelto_pose_weights(phase: String, progress: float) -> Vector2:
	var blend := smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	match phase:
		"preparation": return Vector2(blend, 0.0)
		"impact": return Vector2(1.0 - blend, blend)
		"recovery": return Vector2(0.0, 1.0 - blend)
	return Vector2.ZERO


func _apply_mekatana_pose(rig_skeleton: Skeleton3D) -> void:
	_set_global_basis(rig_skeleton, spine_index, spine_basis)
	var values: Dictionary = MEKATANA_VISUAL.pose_angles(mekatana_step, mekatana_phase, mekatana_progress)
	if mekatana_phase == "":
		values = MEKATANA_VISUAL.pose_angles(0, "preparation", 0.0)
		_set_mekatana_sweep(values, _mekatana_guard_yaw)
	elif mekatana_phase == "preparation":
		_set_mekatana_sweep(values, MEKATANA_VISUAL.preparation_yaw(mekatana_step, _mekatana_prepare_start, mekatana_progress))
	_mekatana_guard_yaw = float(values.torso_yaw) + float(values.shoulder_yaw) + float(values.arm_yaw) + float(values.wrist_yaw)
	if right_shoulder_index >= 0 and float(values.shoulder_lift) > 0.0:
		var parent := rig_skeleton.get_bone_parent(right_shoulder_index)
		var parent_basis := rig_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var offset := parent_basis.inverse() * Vector3.UP * float(values.shoulder_lift)
		rig_skeleton.set_bone_pose_position(right_shoulder_index, rig_skeleton.get_bone_pose_position(right_shoulder_index) + offset)
	_rotate_global_axis(rig_skeleton, spine2_index, Vector3.UP, values.torso_yaw)
	_rotate_global_axis(rig_skeleton, spine2_index, Vector3.RIGHT, values.torso_pitch)
	_rotate_global_axis(rig_skeleton, right_shoulder_index, Vector3.UP, values.shoulder_yaw)
	_rotate_global_axis(rig_skeleton, right_shoulder_index, Vector3.RIGHT, values.shoulder_pitch)
	_rotate_global_axis(rig_skeleton, right_arm_index, Vector3.UP, values.arm_yaw)
	_rotate_global_axis(rig_skeleton, right_arm_index, Vector3.RIGHT, values.arm_pitch)
	_rotate_global_axis(rig_skeleton, right_forearm_index, Vector3.RIGHT, values.forearm_pitch)
	_rotate_global_axis(rig_skeleton, right_hand_index, Vector3.UP, values.wrist_yaw)
	_rotate_global_axis(rig_skeleton, right_hand_index, Vector3.RIGHT, values.wrist_pitch)


func _set_mekatana_sweep(values: Dictionary, sweep: float) -> void:
	values.torso_yaw = sweep * 0.24
	values.shoulder_yaw = sweep * 0.20
	values.arm_yaw = sweep * 0.42
	values.wrist_yaw = sweep * 0.14


func _set_global_basis(rig_skeleton: Skeleton3D, bone: int, desired: Basis) -> void:
	if bone < 0:
		return
	var parent := rig_skeleton.get_bone_parent(bone)
	var parent_basis := rig_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	rig_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion())


func _rotate_global(rig_skeleton: Skeleton3D, bone: int, degrees: float) -> void:
	if bone >= 0:
		_set_global_basis(rig_skeleton, bone, Basis(Vector3.RIGHT, deg_to_rad(degrees)) * rig_skeleton.get_bone_global_pose(bone).basis)


func _rotate_global_axis(rig_skeleton: Skeleton3D, bone: int, axis: Vector3, degrees: float) -> void:
	if bone >= 0 and absf(degrees) > 0.001:
		_set_global_basis(rig_skeleton, bone, Basis(axis.normalized(), deg_to_rad(degrees)) * rig_skeleton.get_bone_global_pose(bone).basis)


func _solve_support_arm(rig_skeleton: Skeleton3D) -> void:
	if left_arm_index < 0 or left_forearm_index < 0 or left_hand_index < 0:
		return
	# Compute from the NEW right-hand pose and immutable local transforms.
	# Reading BoneAttachment.global_transform here would be one frame late.
	var target_pose := rig_skeleton.get_bone_global_pose(right_hand_index) * grip_from_hand
	var shoulder := rig_skeleton.get_bone_global_pose(left_arm_index).origin
	var elbow := rig_skeleton.get_bone_global_pose(left_forearm_index).origin
	var wrist := rig_skeleton.get_bone_global_pose(left_hand_index).origin
	var upper_length := shoulder.distance_to(elbow)
	var lower_length := elbow.distance_to(wrist)
	var target_vector := target_pose.origin - shoulder
	var distance := target_vector.length()
	if distance < 0.0001 or upper_length < 0.0001 or lower_length < 0.0001:
		return
	left_grip_reachable = distance <= upper_length + lower_length and distance >= absf(upper_length - lower_length)
	var direction := target_vector / distance
	var reach := clampf(distance, absf(upper_length - lower_length) + 0.0001, upper_length + lower_length - 0.0001)
	# Keep the authored elbow side. The pole is derived from the stable pose,
	# not the previous IK result, so there is no accumulated roll or drift.
	var pole := elbow - shoulder
	pole -= direction * pole.dot(direction)
	if pole.length_squared() < 0.000001:
		pole = Vector3.DOWN - direction * Vector3.DOWN.dot(direction)
	pole = pole.normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var desired_elbow := shoulder + direction * along + pole * height
	_swing_bone(rig_skeleton, left_arm_index, elbow - shoulder, desired_elbow - shoulder)
	elbow = rig_skeleton.get_bone_global_pose(left_forearm_index).origin
	wrist = rig_skeleton.get_bone_global_pose(left_hand_index).origin
	_swing_bone(rig_skeleton, left_forearm_index, wrist - elbow, shoulder + direction * reach - elbow)
	# Opt-in grip orientation lets a long weapon support the palm underneath it.
	# Existing weapons keep the authored hand roll unless their marker requests it.
	if support_use_orientation:
		_set_global_basis(rig_skeleton, left_hand_index, target_pose.basis.orthonormalized())
	last_left_hand_world = rig_skeleton.global_transform * rig_skeleton.get_bone_global_pose(left_hand_index)
	last_grip_world = rig_skeleton.global_transform * target_pose
	left_grip_error = last_left_hand_world.origin.distance_to(last_grip_world.origin)


func _swing_bone(rig_skeleton: Skeleton3D, bone: int, current: Vector3, desired: Vector3) -> void:
	if current.length_squared() < 0.000001 or desired.length_squared() < 0.000001:
		return
	var swing := Quaternion(current.normalized(), desired.normalized())
	_set_global_basis(rig_skeleton, bone, Basis(swing) * rig_skeleton.get_bone_global_pose(bone).basis)
