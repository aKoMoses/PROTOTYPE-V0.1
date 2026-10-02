extends SkeletonModifier3D

## Presentation only. Never acquires an ActionGate or moves the CharacterBody.
## Authored rotations are measured relative to the clip's first pose: the boxing
## guard and the relaxed arm positions are deliberately not transferred.
const BANK := preload("res://scripts/mecha_animation_bank.gd")
const HIT_DURATION := 0.34
const HIT_COOLDOWN := 0.38
const REST_SPEED := 0.72

var autonomous := true
var library: AnimationLibrary = BANK.LIBRARY
var quiet_allowed := false
var torso_allowed := true
var quiet_clip: StringName = &""
var quiet_time := 0.0
var hit_clip: StringName = &""
var hit_time := 0.0
var serial := 0
var _received_serial := -1
var _hit_cooldown := 0.0
var _quiet_delay := 7.0
var _last_rest: StringName = &""
var _random := RandomNumberGenerator.new()
var _tracks: Dictionary = {}
var _fade_clip: StringName = &""
var _fade_time := 0.0
var _fade_remaining := 0.0
var _fade_weight := 0.0


func _ready() -> void:
	_random.randomize()
	_schedule_rest()
	var rig := get_skeleton()
	for clip_name in BANK.REST_CLIPS + BANK.HIT_CLIPS:
		var clip := library.get_animation(clip_name)
		var entries: Array[Dictionary] = []
		for track in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone_name := String(clip.track_get_path(track).get_subname(0))
			var head := bone_name.ends_with("Head") or bone_name.ends_with("Neck")
			if not head and not bone_name.ends_with("Spine2"):
				continue
			var bone := rig.find_bone(bone_name)
			if bone >= 0:
				entries.append({"bone": bone, "track": track, "head": head,
					"origin": clip.rotation_track_interpolate(track, 0.0)})
		_tracks[clip_name] = entries


func set_context(quiet: bool, torso: bool) -> void:
	quiet_allowed = quiet
	torso_allowed = torso
	if not quiet:
		interrupt_rest()


func interrupt_rest() -> void:
	if quiet_clip != &"":
		_fade_clip = quiet_clip
		_fade_time = quiet_time
		var length := library.get_animation(quiet_clip).length
		_fade_weight = clampf(minf(quiet_time / 0.45, (length - quiet_time) / 0.55), 0.0, 1.0) * 0.65
		_fade_remaining = 0.12
		quiet_clip = &""
		quiet_time = 0.0
		serial += 1
	_schedule_rest()


func reset_presence() -> void:
	interrupt_rest()
	_fade_clip = &""
	_fade_remaining = 0.0
	hit_clip = &""
	hit_time = 0.0
	_hit_cooldown = 0.0
	quiet_allowed = false
	serial += 1


func react_to_hit() -> bool:
	if not autonomous or _hit_cooldown > 0.0:
		return false
	interrupt_rest()
	serial += 1
	hit_clip = BANK.HIT_CLIPS[serial % BANK.HIT_CLIPS.size()]
	hit_time = 0.0
	_hit_cooldown = HIT_COOLDOWN
	return true


func snapshot() -> Dictionary:
	return {"serial": serial, "quiet_clip": String(quiet_clip), "quiet_time": quiet_time,
		"hit_clip": String(hit_clip), "hit_time": hit_time}


func restore(value: Dictionary) -> void:
	if autonomous or value.is_empty():
		return
	var incoming := int(value.get("serial", -1))
	if incoming < _received_serial:
		return
	var rest := StringName(value.get("quiet_clip", ""))
	var hit := StringName(value.get("hit_clip", ""))
	if rest != &"" and rest not in BANK.REST_CLIPS:
		return
	if hit != &"" and hit not in BANK.HIT_CLIPS:
		return
	var new_event := incoming != _received_serial
	if new_event:
		if quiet_clip != rest:
			interrupt_rest()
		quiet_clip = rest
		hit_clip = hit
		quiet_time = maxf(0.0, float(value.get("quiet_time", 0.0)))
		hit_time = maxf(0.0, float(value.get("hit_time", 0.0)))
	else:
		# Repeated snapshots must not rewind or restart a finished/interrupted gesture.
		if quiet_clip == rest:
			quiet_time = maxf(quiet_time, float(value.get("quiet_time", 0.0)))
		if hit_clip == hit:
			hit_time = maxf(hit_time, float(value.get("hit_time", 0.0)))
	_received_serial = incoming


func _process_modification_with_delta(delta: float) -> void:
	_hit_cooldown = maxf(0.0, _hit_cooldown - delta)
	if _fade_remaining > 0.0:
		_fade_remaining = maxf(0.0, _fade_remaining - delta)
		_apply(_fade_clip, _fade_time, _fade_weight * _fade_remaining / 0.12, 18.0)
	if autonomous and quiet_allowed and quiet_clip == &"" and hit_clip == &"":
		_quiet_delay -= delta
		if _quiet_delay <= 0.0:
			var choices := BANK.REST_CLIPS.duplicate()
			choices.erase(_last_rest)
			quiet_clip = choices[_random.randi_range(0, choices.size() - 1)]
			_last_rest = quiet_clip
			quiet_time = 0.0
			serial += 1
	if quiet_clip != &"":
		quiet_time += delta * REST_SPEED
		var clip := library.get_animation(quiet_clip)
		if quiet_time >= clip.length:
			interrupt_rest()
		else:
			var weight := clampf(minf(quiet_time / 0.45, (clip.length - quiet_time) / 0.55), 0.0, 1.0)
			_apply(quiet_clip, quiet_time, weight * 0.65, 18.0)
	if hit_clip != &"":
		hit_time += delta
		if hit_time >= HIT_DURATION:
			hit_clip = &""
			if autonomous:
				serial += 1
		else:
			var clip := library.get_animation(hit_clip)
			var weight := clampf(minf(hit_time / 0.045, (HIT_DURATION - hit_time) / 0.12), 0.0, 1.0)
			_apply(hit_clip, clip.length * hit_time / HIT_DURATION, weight * 0.8, 24.0)


func _apply(clip_name: StringName, time: float, weight: float, cap_degrees: float) -> void:
	var rig := get_skeleton()
	var clip := library.get_animation(clip_name)
	for entry in _tracks.get(clip_name, []):
		if not entry.head and not torso_allowed:
			continue
		var rotation: Quaternion = entry.origin.inverse() * clip.rotation_track_interpolate(entry.track, time)
		var angle := Quaternion.IDENTITY.angle_to(rotation)
		var strength := weight * (1.0 if entry.head else 0.45)
		if angle > deg_to_rad(cap_degrees):
			strength *= deg_to_rad(cap_degrees) / angle
		var offset := Quaternion.IDENTITY.slerp(rotation, strength)
		rig.set_bone_pose_rotation(entry.bone, rig.get_bone_pose_rotation(entry.bone) * offset)


func _schedule_rest() -> void:
	_quiet_delay = _random.randf_range(6.0, 11.0)
