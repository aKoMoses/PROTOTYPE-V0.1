extends RefCounted

const LIBRARY: AnimationLibrary = preload("res://art/mecha-context/context.res")
const REST_CLIPS := [&"standing_relax", &"look_around", &"wait", &"scratch"]
const HIT_CLIPS := [&"hit_to_body_01", &"hit_to_side", &"hit_to_body_02", &"hit_to_head", &"hit_to_stomach"]
const WIN_CLIPS := [&"cheer", &"greet_04", &"laugh_02"]
const LOSE_CLIPS := [&"defeat_02", &"frustrated_01", &"frustrated_02"]
const RESULT_CLIPS := WIN_CLIPS + LOSE_CLIPS
const GARAGE_REST_CLIPS := [&"standing_relax", &"look_around", &"wait", &"scratch", &"laugh_02"]
const GREET_CLIPS := [&"greet_02", &"greet_04", &"greet_01", &"greet_03"]
const APPROVE_CLIPS := [&"agree", &"greet_01", &"laugh_01"]
const GARAGE_CLIPS := [&"standing_relax", &"look_around", &"wait", &"scratch", &"laugh_02", &"laugh_01",
	&"greet_02", &"greet_01", &"greet_03", &"greet_04", &"agree", &"frustrated_01", &"frustrated_02"]
const MODULE_CLIPS := [&"box_01", &"box_02", &"box_03", &"slash", &"pitch_baseball",
	&"basketball_shot", &"cast_a_spell", &"flee_01", &"greet_01"]


static func install(animator: AnimationPlayer, skeleton: Skeleton3D, names: Array, hold_weapon := false) -> void:
	var library := AnimationLibrary.new()
	var animation_root := animator.get_node(animator.root_node)
	var skeleton_path := String(animation_root.get_path_to(skeleton))
	for clip_name in names:
		var source := animator.get_animation(clip_name) if animator.has_animation(clip_name) else LIBRARY.get_animation(clip_name)
		var clip := source.duplicate(true) as Animation
		clip.length = minf(clip.length, LIBRARY.get_animation(clip_name).length)
		for track in range(clip.get_track_count() - 1, -1, -1):
			var path := clip.track_get_path(track)
			if path.get_subname_count() == 0:
				clip.remove_track(track)
				continue
			var bone := String(path.get_subname(0))
			if skeleton.find_bone(bone) < 0:
				clip.remove_track(track)
				continue
			clip.track_set_path(track, NodePath(skeleton_path + ":" + bone))
			if bone.to_lower().ends_with("hips") and clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
				var origin := skeleton.get_bone_rest(skeleton.find_bone(bone)).origin
				for key in clip.track_get_key_count(track):
					var position: Vector3 = clip.track_get_key_value(track, key)
					position.x = origin.x
					position.z = origin.z
					clip.track_set_key_value(track, key, position)
		if hold_weapon:
			var carry := animator.get_animation(&"runtime/ReadyPose") if animator.has_animation(&"runtime/ReadyPose") else animator.get_animation(&"idle")
			_adapt_armed_result(clip, carry, skeleton, clip_name == &"greet_04", animator.get_animation(&"idle"))
		library.add_animation(clip_name, clip)
	animator.add_animation_library(&"context", library)


static func _adapt_armed_result(clip: Animation, carry: Animation, skeleton: Skeleton3D, mirror: bool, idle: Animation) -> void:
	var baseline: Dictionary = {}
	for track in carry.get_track_count():
		baseline["%s|%d" % [carry.track_get_path(track).get_subname(0), carry.track_get_type(track)]] = track
	if mirror:
		var resting: Dictionary = {}
		for track in idle.get_track_count():
			if idle.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				resting[String(idle.track_get_path(track).get_subname(0))] = idle.rotation_track_interpolate(track, 0.0)
		var reflection := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
		for track in range(clip.get_track_count()):
			var name := String(clip.track_get_path(track).get_subname(0))
			var hand := name.contains("RightShoulder") or name.contains("RightArm") or name.contains("RightFore") or name.contains("RightHand")
			if not hand or clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var left_name := name.replace("Right", "Left")
			var left_path := NodePath(String(clip.track_get_path(track)).replace(name, left_name))
			var target := clip.find_track(left_path, Animation.TYPE_ROTATION_3D)
			var left := skeleton.find_bone(left_name)
			var right := skeleton.find_bone(name)
			if left < 0 or right < 0:
				continue
			var origin := clip.rotation_track_interpolate(track, 0.0)
			var left_origin: Quaternion = resting.get(left_name, skeleton.get_bone_rest(left).basis.get_rotation_quaternion())
			var mapping := (skeleton.get_bone_global_rest(left).basis.inverse() * reflection * skeleton.get_bone_global_rest(right).basis).orthonormalized()
			if target < 0:
				target = clip.add_track(Animation.TYPE_ROTATION_3D)
				clip.track_set_path(target, left_path)
			for key in range(clip.track_get_key_count(target) - 1, -1, -1): clip.track_remove_key(target, key)
			for key in clip.track_get_key_count(track):
				var delta := origin.inverse() * clip.rotation_track_interpolate(track, clip.track_get_key_time(track, key))
				clip.track_insert_key(target, clip.track_get_key_time(track, key), left_origin * Quaternion(mapping * Basis(delta) * mapping.inverse()))
	for track in clip.get_track_count():
		var name := String(clip.track_get_path(track).get_subname(0))
		if not (name.contains("RightShoulder") or name.contains("RightArm") or name.contains("RightFore") or name.contains("RightHand")):
			continue
		var reference := int(baseline.get("%s|%d" % [name, clip.track_get_type(track)], -1))
		if reference < 0:
			continue
		var value: Variant = carry.track_get_key_value(reference, 0)
		for key in clip.track_get_key_count(track): clip.track_set_key_value(track, key, value)


static func presence_library(animator: AnimationPlayer) -> AnimationLibrary:
	return sampling_library(animator, REST_CLIPS + HIT_CLIPS)


static func sampling_library(animator: AnimationPlayer, names: Array) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name in names:
		var source := animator.get_animation(clip_name) if animator.has_animation(clip_name) else LIBRARY.get_animation(clip_name)
		var clip := source.duplicate() as Animation
		clip.length = minf(clip.length, LIBRARY.get_animation(clip_name).length)
		library.add_animation(clip_name, clip)
	return library
