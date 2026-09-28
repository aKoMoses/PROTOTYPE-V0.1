extends SkeletonModifier3D
class_name PlayerAimModifier

## Runs after locomotion: stabilise the firing stance, absorb the impulse in
## the shoulder/arm chain, then solve the support arm against that same pose.
signal shot_finished

const KICK_TIME := 0.05
const RECOVERY_TIME := 0.12

var aiming := false
var spine_index := -1
var spine_basis := Basis.IDENTITY
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


func trigger_shot(charge_ratio: float) -> void:
	shot_time = 0.0
	shot_strength = lerpf(1.0, 1.35, clampf(charge_ratio, 0.0, 1.0))


func cancel_shot() -> void:
	shot_time = KICK_TIME + RECOVERY_TIME
	recoil_weight = 0.0


func is_shot_active() -> bool:
	return shot_time < KICK_TIME + RECOVERY_TIME


func _process_modification_with_delta(delta: float) -> void:
	var rig_skeleton := get_skeleton()
	if rig_skeleton == null or not aiming or spine_index < 0 or right_hand_index < 0:
		cancel_shot()
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


func _set_global_basis(rig_skeleton: Skeleton3D, bone: int, desired: Basis) -> void:
	if bone < 0:
		return
	var parent := rig_skeleton.get_bone_parent(bone)
	var parent_basis := rig_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	rig_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion())


func _rotate_global(rig_skeleton: Skeleton3D, bone: int, degrees: float) -> void:
	if bone >= 0:
		_set_global_basis(rig_skeleton, bone, Basis(Vector3.RIGHT, deg_to_rad(degrees)) * rig_skeleton.get_bone_global_pose(bone).basis)


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
