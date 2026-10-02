extends SkeletonModifier3D

## Authored free-hand gestures, evaluated AFTER the weapon/IK modifier.
## No hips, legs, torso, weapon hand, socket or gameplay clock is modified.
const BANK := preload("res://scripts/mecha_animation_bank.gd")
const PHASE_BLEND := 0.06
const PROFILES := {
	"fulguro_punch": {"clips": [&"box_02", &"box_03"], "times": Vector4(0, 0.45, 1.0, 1.8)},
	"pelto_smash": {"clips": [&"slash"], "times": Vector4(0, 1.4, 2.35, 4.1)},
	"javelin": {"clips": [&"pitch_baseball"], "times": Vector4(0, 1.2, 1.75, 3.5), "mirror": true},
	"rocket_basket": {"clips": [&"basketball_shot"], "times": Vector4(0.7, 2.0, 2.6, 4.2), "mirror": true},
	"projector": {"clips": [&"cast_a_spell"], "times": Vector4(0.2, 1.4, 3.4, 4.9)},
	"magnetic_field": {"clips": [&"cast_a_spell"], "times": Vector4(0.2, 1.4, 3.4, 4.9)},
	"permutation": {"clips": [&"cast_a_spell"], "times": Vector4(0.2, 1.4, 3.4, 4.9)},
	"eclipse": {"clips": [&"cast_a_spell"], "times": Vector4(0.2, 1.4, 3.4, 4.9)},
	"counter": {"clips": [&"box_01"], "times": Vector4(0, 0.2, 0.75, 1.6), "hand": false},
	"static_shield": {"clips": [&"box_03"], "times": Vector4(0, 0.35, 1.65, 2.4)},
	"pyro_boots": {"clips": [&"flee_01"], "times": Vector4(0, 0.45, 0.95, 2.6)},
	"bio_injector": {"clips": [&"greet_01"], "times": Vector4(0, 0.6, 1.1, 2.7), "mirror": true},
}

var library: AnimationLibrary = BANK.LIBRARY
var idle_clip: Animation
var module_id := ""
var phase := ""
var progress := 0.0
var duration := 0.2
var variant := 0
var serial := 0
var hand_allowed := true
var replica := false
var _received_serial := -1
var _tracks: Dictionary = {}
var _torso_tracks: Dictionary = {}
var _last_pose: Dictionary = {}
var _from_pose: Dictionary = {}
var _blend_remaining := 0.0


func _ready() -> void:
	var rig := get_skeleton()
	var carried: Dictionary = {}
	if idle_clip != null:
		for track in idle_clip.get_track_count():
			if idle_clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				carried[String(idle_clip.track_get_path(track).get_subname(0))] = idle_clip.rotation_track_interpolate(track, 0.0)
	for clip_name in BANK.MODULE_CLIPS:
		var clip := library.get_animation(clip_name)
		var rotations: Dictionary = {}
		for track in clip.get_track_count():
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				rotations[rig.find_bone(clip.track_get_path(track).get_subname(0))] = track
		var parent := rig.get_bone_parent(rig.find_bone("mixamorig_LeftShoulder"))
		var chain: Array[Dictionary] = []
		while parent >= 0:
			chain.push_front({"track": rotations.get(parent, -1), "rest": rig.get_bone_rest(parent).basis.get_rotation_quaternion()})
			parent = rig.get_bone_parent(parent)
		_torso_tracks[clip_name] = chain
		var entries: Array[Dictionary] = []
		for track in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var name := String(clip.track_get_path(track).get_subname(0))
			var head := name.ends_with("Head") or name.ends_with("Neck")
			var arm := name.contains("LeftShoulder") or name.contains("LeftArm") or name.contains("LeftForeArm") or name.contains("LeftForearm") or name.contains("LeftHand")
			var right := name.contains("RightShoulder") or name.contains("RightArm") or name.contains("RightForeArm") or name.contains("RightForearm") or name.contains("RightHand")
			if not head and not arm and not right:
				continue
			var bone := rig.find_bone(name)
			if bone < 0:
				continue
			var entry := {"bone": bone, "track": track, "head": head, "right": right, "shoulder": name.ends_with("Shoulder"),
				"origin": clip.rotation_track_interpolate(track, 0.0)}
			if right:
				var left := rig.find_bone(name.replace("Right", "Left"))
				if left < 0:
					continue
				var reflection := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
				entry["left"] = left
				entry["left_rest"] = carried.get(name.replace("Right", "Left"), rig.get_bone_rest(left).basis.get_rotation_quaternion())
				entry["mapping"] = (rig.get_bone_global_rest(left).basis.inverse() * reflection * rig.get_bone_global_rest(bone).basis).orthonormalized()
			entries.append(entry)
		_tracks[clip_name] = entries


func set_pose(id: String, next_phase: String, amount: float, seconds: float, selection: int = 0, free_hand: bool = true) -> void:
	if not PROFILES.has(id) or next_phase not in ["preparation", "active", "recovery"]:
		clear_pose()
		return
	if module_id != id or phase != next_phase or variant != selection:
		_begin_phase_blend(id, next_phase)
		serial += 1
	module_id = id
	phase = next_phase
	progress = clampf(amount, 0.0, 1.0)
	duration = maxf(seconds, 0.001)
	variant = selection
	hand_allowed = free_hand


func clear_pose() -> void:
	if not module_id.is_empty():
		serial += 1
	module_id = ""
	phase = ""
	progress = 0.0
	_last_pose.clear()
	_from_pose.clear()
	_blend_remaining = 0.0


func snapshot() -> Dictionary:
	return {"serial": serial, "id": module_id, "phase": phase, "progress": progress,
		"duration": duration, "variant": variant, "hand": hand_allowed}


func restore(value: Dictionary) -> void:
	if value.is_empty():
		return
	var incoming := int(value.get("serial", -1))
	if incoming < _received_serial:
		return
	var id := String(value.get("id", ""))
	var next_phase := String(value.get("phase", ""))
	if not id.is_empty() and (not PROFILES.has(id) or next_phase not in ["preparation", "active", "recovery"]):
		return
	var amount := clampf(float(value.get("progress", 0.0)), 0.0, 1.0)
	if incoming == _received_serial:
		# Finished/cancelled poses cannot be restarted by an old packet.
		if module_id != id or phase != next_phase:
			return
		amount = maxf(progress, amount)
	else:
		_begin_phase_blend(id, next_phase)
		_blend_remaining = maxf(0.0, _blend_remaining - amount * float(value.get("duration", 0.2)))
	module_id = id
	phase = next_phase
	progress = amount
	duration = clampf(float(value.get("duration", 0.2)), 0.001, 10.0)
	variant = maxi(0, int(value.get("variant", 0)))
	hand_allowed = bool(value.get("hand", true))
	_received_serial = incoming
	replica = true


func _process_modification_with_delta(delta: float) -> void:
	if module_id.is_empty():
		return
	_blend_remaining = maxf(0.0, _blend_remaining - delta)
	if replica:
		progress = minf(1.0, progress + delta / duration)
	var profile: Dictionary = PROFILES[module_id]
	var clips: Array = profile.clips
	var clip_name: StringName = clips[variant % clips.size()]
	var clip := library.get_animation(clip_name)
	var times: Vector4 = profile.times
	var time := lerpf(times.x, times.y, progress)
	var weight := smoothstep(0.0, 0.35, progress)
	if phase == "active":
		# The release pose is already visible when the real strike/projectile fires.
		time = lerpf(times.z, (times.z + times.w) * 0.5, progress)
		weight = 1.0
	elif phase == "recovery":
		time = lerpf((times.z + times.w) * 0.5, times.w, progress)
		weight = 1.0 - smoothstep(0.0, 1.0, progress)
	var mirrored := bool(profile.get("mirror", false))
	var rig := get_skeleton()
	var parent_delta := _parent_rotation(clip_name, 0.0).inverse() * _parent_rotation(clip_name, time)
	for entry in _tracks.get(clip_name, []):
		var sample := clip.rotation_track_interpolate(entry.track, minf(time, clip.length))
		if entry.head:
			var offset: Quaternion = entry.origin.inverse() * sample
			var angle := Quaternion.IDENTITY.angle_to(offset)
			var strength := weight * 0.45 * minf(1.0, deg_to_rad(20.0) / maxf(angle, 0.0001))
			_write_rotation(entry.bone, rig.get_bone_pose_rotation(entry.bone) * Quaternion.IDENTITY.slerp(offset, strength))
		elif hand_allowed and bool(profile.get("hand", true)) and entry.right == mirrored:
			var bone: int = entry.bone
			# Keep the authored arm arc when the original throw turns the torso.
			# Transfer that turn into the free shoulder rather than the armed torso.
			if entry.shoulder:
				sample = parent_delta * sample
			if mirrored:
				bone = entry.left
				var mapping: Basis = entry.mapping
				sample = entry.left_rest * Quaternion(mapping * Basis(entry.origin.inverse() * sample) * mapping.inverse())
			_write_rotation(bone, rig.get_bone_pose_rotation(bone).slerp(sample, weight * 0.85))


func _begin_phase_blend(id: String, next_phase: String) -> void:
	if module_id == id and not id.is_empty() and phase != next_phase:
		_from_pose = _last_pose.duplicate()
		_blend_remaining = PHASE_BLEND
	else:
		_from_pose.clear()
		_blend_remaining = 0.0


func _write_rotation(bone: int, target: Quaternion) -> void:
	if _blend_remaining > 0.0 and _from_pose.has(bone):
		target = (_from_pose[bone] as Quaternion).slerp(target, 1.0 - smoothstep(0.0, PHASE_BLEND, _blend_remaining))
	get_skeleton().set_bone_pose_rotation(bone, target)
	_last_pose[bone] = target


func _parent_rotation(clip_name: StringName, time: float) -> Quaternion:
	var clip := library.get_animation(clip_name)
	var rotation := Quaternion.IDENTITY
	for entry in _torso_tracks.get(clip_name, []):
		rotation *= clip.rotation_track_interpolate(entry.track, minf(time, clip.length)) if entry.track >= 0 else entry.rest
	return rotation.normalized()
