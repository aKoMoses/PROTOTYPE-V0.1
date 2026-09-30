extends RefCounted

## Synchronous final pose pass. Call after AnimationTree.advance(), which must
## restore the authored pose every frame before these non-accumulating offsets.
## All bone transforms below are in skeleton space; only aim_target is world space.

const EPSILON := 0.000001
const REACH_MARGIN := 0.00001
const MEKATANA_VISUAL := preload("res://scripts/mekatana_visual.gd")

## Distance in world units between the support wrist and its weapon anchor.
var left_grip_error := 0.0

var _skeleton: Skeleton3D
var _hand_to_weapon := Transform3D.IDENTITY
var _support_from_weapon := Vector3.ZERO
var _muzzle_from_weapon := Vector3.ZERO
var _reference_spine_basis := Basis.IDENTITY
var _support_basis_from_weapon := Basis.IDENTITY
var _shoulder_base_position := Vector3.ZERO
var _hips := -1
var _spine := -1
var _spine2 := -1
var _right_shoulder := -1
var _right_arm := -1
var _right_forearm := -1
var _right_hand := -1
var _left_arm := -1
var _left_forearm := -1
var _left_hand := -1
var mekatana_equipped := false
var _mekatana_step := 0
var _mekatana_phase := ""
var _mekatana_progress := 0.0
var _mekatana_guard_yaw := 0.0
var _mekatana_prepare_start := 0.0


func configure(skeleton: Skeleton3D, hand_to_weapon: Transform3D, support_from_weapon: Vector3, muzzle_from_weapon: Vector3, reference_spine_basis: Basis) -> void:
	_skeleton = skeleton
	_hand_to_weapon = hand_to_weapon
	_support_from_weapon = support_from_weapon
	_muzzle_from_weapon = muzzle_from_weapon
	_reference_spine_basis = reference_spine_basis.orthonormalized()
	left_grip_error = 0.0
	if not is_instance_valid(_skeleton):
		return
	_hips = _skeleton.find_bone("mixamorig_Hips")
	_spine = _skeleton.find_bone("mixamorig_Spine")
	_spine2 = _skeleton.find_bone("mixamorig_Spine2")
	_right_shoulder = _skeleton.find_bone("mixamorig_RightShoulder")
	_right_arm = _skeleton.find_bone("mixamorig_RightArm")
	_right_forearm = _skeleton.find_bone("mixamorig_RightForeArm")
	_right_hand = _skeleton.find_bone("mixamorig_RightHand")
	_left_arm = _skeleton.find_bone("mixamorig_LeftArm")
	_left_forearm = _skeleton.find_bone("mixamorig_LeftForeArm")
	_left_hand = _skeleton.find_bone("mixamorig_LeftHand")
	if _right_shoulder >= 0:
		# These imported clips have no shoulder position track. Cache its
		# unmodified local translation rather than adding to last frame's kick.
		_shoulder_base_position = _skeleton.get_bone_pose_position(_right_shoulder)
	if _left_hand >= 0 and _right_hand >= 0:
		var weapon_basis := (_skeleton.get_bone_global_pose(_right_hand) * _hand_to_weapon).basis.orthonormalized()
		_support_basis_from_weapon = weapon_basis.inverse() * _skeleton.get_bone_global_pose(_left_hand).basis.orthonormalized()


func set_mekatana_pose(step: int, phase: String, progress: float) -> void:
	if phase == "preparation" and (phase != _mekatana_phase or step != _mekatana_step):
		_mekatana_prepare_start = _mekatana_guard_yaw
	_mekatana_step = clampi(step, 0, 2)
	_mekatana_phase = phase
	_mekatana_progress = clampf(progress, 0.0, 1.0)


func clear_mekatana_pose() -> void:
	if _mekatana_phase == "":
		return
	_mekatana_guard_yaw = MEKATANA_VISUAL.guard_yaw(_mekatana_step) if _mekatana_phase == "recovery" else 0.0
	_mekatana_phase = ""
	_mekatana_progress = 0.0


func reset_offsets() -> void:
	# Also call when bypassing the solver for death, preview or a reset.
	if is_instance_valid(_skeleton) and _right_shoulder >= 0:
		_skeleton.set_bone_pose_position(_right_shoulder, _shoulder_base_position)


func solve(leg_yaw: float, aim_weight: float, aim_target: Vector3, recoil: float, hit: float) -> void:
	left_grip_error = 0.0
	if not is_instance_valid(_skeleton):
		return
	reset_offsets()
	# Source forward is +Z. Premultiplication turns the pelvis in skeleton
	# space even though the imported hip's own rest axes are rotated.
	if _hips >= 0 and is_finite(leg_yaw):
		var hips_basis := _skeleton.get_bone_global_pose(_hips).basis
		_set_global_basis(_hips, Basis(Vector3.UP, clampf(leg_yaw, -PI * 0.5, PI * 0.5)) * hips_basis)
	var weight := clampf(aim_weight, 0.0, 1.0)
	if _spine >= 0 and weight > 0.0:
		var spine_basis := _skeleton.get_bone_global_pose(_spine).basis.orthonormalized()
		_set_global_basis(_spine, spine_basis.slerp(_reference_spine_basis, weight))
	# An idle/passive target still reacts to damage. Recoil needs an armed pose.
	_apply_impulses(clampf(recoil, 0.0, 1.0) * weight, clampf(hit, 0.0, 1.35))
	if weight <= 0.0 or _spine < 0 or _right_arm < 0 or _right_hand < 0:
		return
	if mekatana_equipped:
		_apply_mekatana_pose()
		_solve_support_arm(weight)
		return
	if aim_target.is_finite():
		_aim_right_arm(_skeleton.global_transform.affine_inverse() * aim_target, weight)
	_solve_support_arm(weight)


func _apply_impulses(recoil: float, hit: float) -> void:
	# The shoulder absorbs the recoil; the rigid hand/socket connection never
	# moves independently. Small torso impulses keep the barrel from pitching up.
	if _spine2 >= 0:
		var impulse := Basis(Vector3.FORWARD, deg_to_rad(2.0) * hit)
		impulse = Basis(Vector3.RIGHT, deg_to_rad(0.65) * recoil) * impulse
		_set_global_basis(_spine2, impulse * _skeleton.get_bone_global_pose(_spine2).basis)
	if _right_shoulder >= 0 and recoil > 0.0:
		var parent := _skeleton.get_bone_parent(_right_shoulder)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var local_offset := parent_basis.inverse() * Vector3(0.0, 0.0, -0.016 * recoil)
		_skeleton.set_bone_pose_position(_right_shoulder, _shoulder_base_position + local_offset)


func _apply_mekatana_pose() -> void:
	var values: Dictionary = MEKATANA_VISUAL.pose_angles(_mekatana_step, _mekatana_phase, _mekatana_progress)
	var sweep: float = float(values.torso_yaw) + float(values.shoulder_yaw) + float(values.arm_yaw) + float(values.wrist_yaw)
	if _mekatana_phase == "":
		values = MEKATANA_VISUAL.pose_angles(0, "preparation", 0.0)
		sweep = _mekatana_guard_yaw
	elif _mekatana_phase == "preparation":
		sweep = MEKATANA_VISUAL.preparation_yaw(_mekatana_step, _mekatana_prepare_start, _mekatana_progress)
	_mekatana_guard_yaw = sweep
	if _right_shoulder >= 0 and float(values.shoulder_lift) > 0.0:
		var parent := _skeleton.get_bone_parent(_right_shoulder)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		_skeleton.set_bone_pose_position(_right_shoulder, _shoulder_base_position + parent_basis.inverse() * Vector3.UP * float(values.shoulder_lift))
	_rotate_axis(_spine2, Vector3.UP, sweep * 0.24)
	_rotate_axis(_spine2, Vector3.RIGHT, values.torso_pitch)
	_rotate_axis(_right_shoulder, Vector3.UP, sweep * 0.20)
	_rotate_axis(_right_shoulder, Vector3.RIGHT, values.shoulder_pitch)
	_rotate_axis(_right_arm, Vector3.UP, sweep * 0.42)
	_rotate_axis(_right_arm, Vector3.RIGHT, values.arm_pitch)
	_rotate_axis(_right_forearm, Vector3.RIGHT, values.forearm_pitch)
	_rotate_axis(_right_hand, Vector3.UP, sweep * 0.14)
	_rotate_axis(_right_hand, Vector3.RIGHT, values.wrist_pitch)


func _rotate_axis(bone: int, axis: Vector3, degrees: float) -> void:
	if bone >= 0 and absf(degrees) > 0.001:
		_set_global_basis(bone, Basis(axis, deg_to_rad(degrees)) * _skeleton.get_bone_global_pose(bone).basis)


func _aim_right_arm(target: Vector3, weight: float) -> void:
	var authored_rotation := _skeleton.get_bone_pose_rotation(_right_arm)
	# Solve the ray length before swinging about the shoulder. Repeatedly turning
	# toward target - muzzle oscillates at close range because the muzzle moves
	# with the arm, and can leave the barrel pointing above the target.
	var shoulder := _skeleton.get_bone_global_pose(_right_arm).origin
	var weapon_pose := _skeleton.get_bone_global_pose(_right_hand) * _hand_to_weapon
	var muzzle_offset := weapon_pose * _muzzle_from_weapon - shoulder
	var forward := -weapon_pose.basis.z.normalized()
	var target_offset := target - shoulder
	var along := muzzle_offset.dot(forward)
	var discriminant := along * along + target_offset.length_squared() - muzzle_offset.length_squared()
	var ray_length := maxf(0.0, -along + sqrt(maxf(0.0, discriminant)))
	_swing_bone(_right_arm, muzzle_offset + forward * ray_length, target_offset)
	var solved_rotation := _skeleton.get_bone_pose_rotation(_right_arm)
	_skeleton.set_bone_pose_rotation(_right_arm, authored_rotation.slerp(solved_rotation, weight).normalized())


func _solve_support_arm(weight: float) -> void:
	if _left_arm < 0 or _left_forearm < 0 or _left_hand < 0:
		return
	# Read fresh right-hand bone data, never BoneAttachment's cached transform.
	var weapon_pose := _skeleton.get_bone_global_pose(_right_hand) * _hand_to_weapon
	var target := weapon_pose * _support_from_weapon
	var shoulder := _skeleton.get_bone_global_pose(_left_arm).origin
	var elbow := _skeleton.get_bone_global_pose(_left_forearm).origin
	var wrist := _skeleton.get_bone_global_pose(_left_hand).origin
	var upper_length := shoulder.distance_to(elbow)
	var lower_length := elbow.distance_to(wrist)
	var offset := target - shoulder
	var distance := offset.length()
	if distance < REACH_MARGIN or upper_length < REACH_MARGIN or lower_length < REACH_MARGIN:
		_update_grip_error(target)
		return
	var direction := offset / distance
	var reach := clampf(distance, absf(upper_length - lower_length) + REACH_MARGIN, upper_length + lower_length - REACH_MARGIN)
	# The freshly animated elbow provides the pole each frame. No state from
	# the previous IK result feeds back into this solve.
	var pole := elbow - shoulder
	pole -= direction * pole.dot(direction)
	if pole.length_squared() < EPSILON:
		pole = _perpendicular(direction, Vector3.DOWN)
	else:
		pole = pole.normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var desired_elbow := shoulder + direction * along + pole * height
	var authored_upper := _skeleton.get_bone_pose_rotation(_left_arm)
	var authored_lower := _skeleton.get_bone_pose_rotation(_left_forearm)
	_swing_bone(_left_arm, elbow - shoulder, desired_elbow - shoulder)
	elbow = _skeleton.get_bone_global_pose(_left_forearm).origin
	wrist = _skeleton.get_bone_global_pose(_left_hand).origin
	_swing_bone(_left_forearm, wrist - elbow, shoulder + direction * reach - elbow)
	# Solve fully first, then blend the two local rotations once. Applying
	# weight in each geometric step would change the elbow solution itself.
	var solved_upper := _skeleton.get_bone_pose_rotation(_left_arm)
	var solved_lower := _skeleton.get_bone_pose_rotation(_left_forearm)
	_skeleton.set_bone_pose_rotation(_left_arm, authored_upper.slerp(solved_upper, weight).normalized())
	_skeleton.set_bone_pose_rotation(_left_forearm, authored_lower.slerp(solved_lower, weight).normalized())
	# Keep the calibrated palm roll relative to the gun. Position-only IK
	# would leave the fingers hanging away from the support contact point.
	var hand_basis := _skeleton.get_bone_global_pose(_left_hand).basis.orthonormalized()
	var grip_basis := weapon_pose.basis.orthonormalized() * _support_basis_from_weapon
	_set_global_basis(_left_hand, hand_basis.slerp(grip_basis, weight))
	_update_grip_error(target)


func _update_grip_error(target: Vector3) -> void:
	var wrist := _skeleton.get_bone_global_pose(_left_hand).origin
	left_grip_error = (_skeleton.global_transform * wrist).distance_to(_skeleton.global_transform * target)


func _set_global_basis(bone: int, desired: Basis) -> void:
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local_basis := (parent_basis.inverse() * desired).orthonormalized()
	_skeleton.set_bone_pose_rotation(bone, local_basis.get_rotation_quaternion().normalized())


func _swing_bone(bone: int, current: Vector3, desired: Vector3) -> void:
	if current.length_squared() < EPSILON or desired.length_squared() < EPSILON:
		return
	var from := current.normalized()
	var to := desired.normalized()
	var cosine := clampf(from.dot(to), -1.0, 1.0)
	var swing := Quaternion.IDENTITY
	var axis := from.cross(to)
	if axis.length_squared() > 0.000000000001:
		swing = Quaternion(axis.normalized(), atan2(axis.length(), cosine))
	elif cosine < 0.0:
		# The ordinary shortest-arc constructor is ambiguous at 180 degrees.
		# Use a deterministic axis close to the authored bone up direction.
		var bone_up := _skeleton.get_bone_global_pose(bone).basis.y.normalized()
		swing = Quaternion(_perpendicular(from, bone_up), PI)
	_set_global_basis(bone, Basis(swing) * _skeleton.get_bone_global_pose(bone).basis)


func _perpendicular(direction: Vector3, preferred: Vector3) -> Vector3:
	var perpendicular := preferred - direction * preferred.dot(direction)
	if perpendicular.length_squared() < EPSILON:
		var fallback := Vector3.RIGHT if absf(direction.x) < 0.8 else Vector3.FORWARD
		perpendicular = fallback - direction * fallback.dot(direction)
	return perpendicular.normalized()
