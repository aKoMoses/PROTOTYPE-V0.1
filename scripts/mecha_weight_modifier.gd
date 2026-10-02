extends SkeletonModifier3D

## Add lower-body weight before the existing aim/hand solvers. The inverse spine
## rotation keeps the torso and weapon independent from the animated pelvis.
var lean := Vector2.ZERO
var enabled := false
var _hips := -1
var _spine := -1

func _ready() -> void:
	var rig := get_skeleton()
	for index in rig.get_bone_count():
		var label := String(rig.get_bone_name(index)).to_lower()
		if label.ends_with("hips"):
			_hips = index
		if label.ends_with("spine"):
			_spine = index

func _process_modification() -> void:
	if not enabled or _hips < 0 or _spine < 0 or lean.is_zero_approx():
		return
	var rig := get_skeleton()
	var offset := Quaternion.from_euler(Vector3(clampf(lean.y, -0.075, 0.075), 0.0, clampf(lean.x, -0.065, 0.065)))
	rig.set_bone_pose_rotation(_hips, (rig.get_bone_pose_rotation(_hips) * offset).normalized())
	rig.set_bone_pose_rotation(_spine, (offset.inverse() * rig.get_bone_pose_rotation(_spine)).normalized())
