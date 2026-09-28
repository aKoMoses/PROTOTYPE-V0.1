extends SkeletonModifier3D
class_name PlayerLowerBodyDirectionModifier

## Turns the animated hips toward movement while counter-rotating the spine,
## so the torso, weapon and aim can keep facing the target.

var hips_bone_index := -1
var spine_bone_index := -1
var source_local_move_direction := Vector3.ZERO
var locomotion_enabled := false


func configure(hips_index: int, spine_index: int) -> void:
	hips_bone_index = hips_index
	spine_bone_index = spine_index


func set_locomotion_direction(direction: Vector3, enabled: bool) -> void:
	source_local_move_direction = direction
	locomotion_enabled = enabled and direction.length_squared() > 0.0225


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not locomotion_enabled:
		return
	if hips_bone_index < 0 or spine_bone_index < 0:
		return
	var flat_direction := source_local_move_direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.0225:
		return
	flat_direction = flat_direction.normalized()
	# This GLB's authored forward is +Z; yaw the pelvis in its local frame.
	var yaw := atan2(flat_direction.x, flat_direction.z)
	if absf(yaw) <= 0.015:
		return
	var yaw_rotation := Quaternion(Vector3.UP, yaw)
	var hips_pose := skeleton.get_bone_pose_rotation(hips_bone_index)
	var spine_pose := skeleton.get_bone_pose_rotation(spine_bone_index)
	skeleton.set_bone_pose_rotation(hips_bone_index, (hips_pose * yaw_rotation).normalized())
	skeleton.set_bone_pose_rotation(spine_bone_index, (yaw_rotation.inverse() * spine_pose).normalized())
