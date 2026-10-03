extends Node3D
class_name MekatanaVisual

## Attached presentation only. Combat owns phases, movement and validated hits.
## Source GLB is untouched; SourceAlignment seats its diagonal handle at the grip.
const ELECTRIC_COLOR := Color("#70e7ff")
const MAX_TRAIL_SAMPLES := 10
const WINDUP_SOUND := preload("res://art/audio/weapon-sfx/mekatana-windup.wav")
const SLASH_SOUNDS := [
	preload("res://art/audio/weapon-sfx/mekatana-slash-1.wav"),
	preload("res://art/audio/weapon-sfx/mekatana-slash-2.wav"),
	preload("res://art/audio/weapon-sfx/mekatana-slash-3.wav"),
]
const IMPACT_SOUNDS := [
	preload("res://art/audio/weapon-sfx/mekatana-impact-1.wav"),
	preload("res://art/audio/weapon-sfx/mekatana-impact-2.wav"),
	preload("res://art/audio/weapon-sfx/mekatana-impact-3.wav"),
]
## Presentation endpoints, sound grains and electrical intensity are shared by
## both rigs. These settings never change damage, casts or dash durations.
const STEP_PRESENTATION := [
	{
		"windup_yaw": 48.0, "strike_yaw": -48.0, "guard_yaw": -34.0,
		"electric_intensity": 0.66, "trail_opacity": 0.17,
		"trail_life": 0.055, "trail_blade_start": 0.82,
		"slash_duration": 0.11, "slash_pitch": 1.22, "slash_volume": -23.0,
		"impact_duration": 0.075, "impact_pitch": 1.16, "impact_volume": -23.0,
		"impact_scale": 0.80, "arc_count": 1, "arc_width": 0.012,
		"arc_life": 0.055, "arc_length": 0.15,
	},
	{
		"windup_yaw": -88.0, "strike_yaw": 88.0, "guard_yaw": 32.0,
		"electric_intensity": 0.95, "trail_opacity": 0.25,
		"trail_life": 0.080, "trail_blade_start": 0.70,
		"slash_duration": 0.16, "slash_pitch": 1.02, "slash_volume": -20.0,
		"impact_duration": 0.105, "impact_pitch": 0.96, "impact_volume": -20.0,
		"impact_scale": 1.00, "arc_count": 2, "arc_width": 0.016,
		"arc_life": 0.075, "arc_length": 0.22,
	},
	{
		"windup_yaw": 0.0, "strike_yaw": 0.0, "guard_yaw": 0.0,
		"electric_intensity": 1.20, "trail_opacity": 0.30,
		"trail_life": 0.100, "trail_blade_start": 0.66,
		"slash_duration": 0.20, "slash_pitch": 0.80, "slash_volume": -17.5,
		"impact_duration": 0.145, "impact_pitch": 0.79, "impact_volume": -17.5,
		"impact_scale": 1.18, "arc_count": 3, "arc_width": 0.020,
		"arc_life": 0.105, "arc_length": 0.28,
	},
]
const OVERHEAD_WINDUP := -116.0
const OVERHEAD_END := 38.0
const OVERHEAD_SHOULDER_LIFT := 0.045
var _step := 0
var _phase := ""
var _progress := 0.0
var _clock := 0.0
var _blade_base: Marker3D
var _blade_tip: Marker3D
var _skeleton: Skeleton3D
var _electric: MeshInstance3D
var _electric_material: StandardMaterial3D
var _trail: MeshInstance3D
var _trail_material: StandardMaterial3D
var _samples: Array[Dictionary] = []
var _audio: AudioStreamPlayer
var _charge_sound: AudioStreamWAV
var _slash_sounds: Array[AudioStreamWAV] = []
var _impact_sounds: Array[AudioStreamWAV] = []


func _ready() -> void:
	process_priority = 120
	_blade_base = get_node("BladeBase") as Marker3D
	_blade_tip = get_node("BladeTip") as Marker3D
	_electric_material = _material(ELECTRIC_COLOR, 0.35)
	_electric = MeshInstance3D.new()
	_electric.name = "BladeCurrent"
	_electric.material_override = _electric_material
	_electric.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_electric)
	_trail_material = _material(ELECTRIC_COLOR, 0.26)
	_trail = MeshInstance3D.new()
	_trail.name = "BladeTrail"
	_trail.top_level = true
	_trail.material_override = _trail_material
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY
	_audio = AudioStreamPlayer.new()
	_audio.name = "MekatanaSound"
	_audio.max_polyphony = 3
	_audio.volume_db = -19.0
	if AudioServer.get_bus_index("Effects") >= 0:
		_audio.bus = &"Effects"
	add_child(_audio)
	_charge_sound = WINDUP_SOUND
	for step in range(3):
		_slash_sounds.append(SLASH_SOUNDS[step])
		_impact_sounds.append(IMPACT_SOUNDS[step])
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is Skeleton3D:
			_skeleton = ancestor as Skeleton3D
			_skeleton.skeleton_updated.connect(sample_blade_pose)
			break
		ancestor = ancestor.get_parent()


func _process(delta: float) -> void:
	_clock += maxf(0.0, delta)
	if not is_visible_in_tree():
		_samples.clear()
		_trail.visible = false
		return
	_update_electric()
	# Skeleton signal and explicit bot refresh own the samples. Rendering only
	# retires them, so a slow render frame cannot lengthen the visible trail.
	_retire_samples()
	_rebuild_trail()


func set_phase(step: int, phase: String, progress: float) -> void:
	var changed := phase != _phase or step != _step
	_step = clampi(step, 0, 2)
	_phase = phase
	_progress = clampf(progress, 0.0, 1.0)
	var settings: Dictionary = STEP_PRESENTATION[_step]
	if is_instance_valid(_trail_material):
		_trail_material.albedo_color.a = float(settings.trail_opacity)
	if changed and is_instance_valid(_audio):
		if phase == "preparation":
			_samples.clear()
			_audio.stream = _charge_sound
			_audio.pitch_scale = 1.0
			_audio.volume_db = -4.0
			_audio.play()
		elif phase == "active":
			_audio.stream = _slash_sounds[_step]
			_audio.pitch_scale = 1.0
			_audio.volume_db = -2.0
			_audio.play()
		elif phase == "":
			_audio.stop()
			_samples.clear()
			_trail.visible = false


func clear_mekatana_pose() -> void:
	set_phase(0, "", 0.0)


func sample_blade_pose() -> void:
	if _phase != "active" or not is_visible_in_tree() or _blade_tip == null:
		return
	var base := _blade_base.global_position
	var tip := _blade_tip.global_position
	if not _samples.is_empty() and tip.distance_squared_to(_samples[-1].tip) < 0.000004:
		return
	# Trace only the end of the actual blade. A full base-to-tip fan would
	# cover the arms and other fighters during the overhead stroke.
	var settings: Dictionary = STEP_PRESENTATION[_step]
	_samples.append({"base": base.lerp(tip, float(settings.trail_blade_start)), "tip": tip, "time": _clock})
	while _samples.size() > MAX_TRAIL_SAMPLES:
		_samples.pop_front()
	_retire_samples()
	_rebuild_trail()


func set_mekatana_impact(target: Node3D, power: float = 1.0) -> void:
	if not is_instance_valid(target) or get_tree().current_scene == null:
		return
	var manager := get_tree().current_scene.get_node_or_null("VFXManager")
	var origin := target.global_position + Vector3.UP * 0.9
	var settings: Dictionary = STEP_PRESENTATION[_step]
	var strength := clampf(power * float(settings.impact_scale), 0.4, 1.65)
	if manager != null:
		manager.call("impact", origin, Vector3.UP, "robot", strength, ELECTRIC_COLOR)
		var arc_count := int(settings.arc_count) + (1 if strength > 1.4 else 0)
		for index in range(arc_count):
			var side := Vector3(cos(float(index) * 2.4), 0.25, sin(float(index) * 2.4))
			manager.call("tracer", origin, origin + side * (float(settings.arc_length) * strength), float(settings.arc_width), ELECTRIC_COLOR, float(settings.arc_life))
	if _audio != null:
		_audio.stream = _impact_sounds[_step]
		_audio.pitch_scale = 1.0 / sqrt(clampf(strength, 0.85, 1.15))
		_audio.volume_db = -2.0
		_audio.play()


func _update_electric() -> void:
	var strength := 0.16
	var intensity: float = STEP_PRESENTATION[_step].electric_intensity
	if _phase == "preparation":
		strength = lerpf(0.25, intensity, _progress)
	elif _phase == "active":
		strength = intensity * 0.90
	elif _phase == "recovery":
		strength = lerpf(intensity * 0.60, 0.16, _progress)
	_electric_material.albedo_color.a = 0.16 + strength * 0.48
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var base := _blade_base.position
	var tip := _blade_tip.position
	for index in range(9):
		var amount := float(index) / 8.0
		var point := base.lerp(tip, amount)
		var envelope := sin(amount * PI)
		point.x += sin(_clock * 47.0 + float(index) * 2.3) * 0.023 * strength * envelope
		point.y += 0.013 + cos(_clock * 39.0 + float(index) * 1.7) * 0.018 * strength * envelope
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_electric.mesh = mesh


func _retire_samples() -> void:
	var lifetime: float = STEP_PRESENTATION[_step].trail_life
	while not _samples.is_empty() and _clock - float(_samples[0].time) > lifetime:
		_samples.pop_front()


func _rebuild_trail() -> void:
	_trail.visible = _samples.size() >= 2
	if not _trail.visible:
		return
	var mesh := ImmediateMesh.new()
	var lifetime: float = STEP_PRESENTATION[_step].trail_life
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, _samples.size()):
		var previous: Dictionary = _samples[index - 1]
		var current: Dictionary = _samples[index]
		var age := clampf(1.0 - (_clock - float(current.time)) / lifetime, 0.0, 1.0)
		mesh.surface_set_color(Color(1.0, 1.0, 1.0, age))
		mesh.surface_add_vertex(previous.base)
		mesh.surface_add_vertex(previous.tip)
		mesh.surface_add_vertex(current.tip)
		mesh.surface_add_vertex(previous.base)
		mesh.surface_add_vertex(current.tip)
		mesh.surface_add_vertex(current.base)
	mesh.surface_end()
	_trail.mesh = mesh


static func pose_angles(step: int, phase: String, progress: float) -> Dictionary:
	# Anatomical forward is +Z, corrected by PI at the model root. Positive
	# skeleton yaw is therefore the attacker's left; the first swing goes + to -.
	var amount := smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	var sweep := 0.0
	var overhead := 0.0
	var shoulder_lift := 0.0
	var previous_guard := guard_yaw(step - 1) if step > 0 else 0.0
	var settings: Dictionary = STEP_PRESENTATION[clampi(step, 0, 2)]
	if step < 2:
		sweep = lerpf(previous_guard, float(settings.windup_yaw), amount) if phase == "preparation" else lerpf(float(settings.windup_yaw), float(settings.strike_yaw), amount) if phase == "active" else lerpf(float(settings.strike_yaw), float(settings.guard_yaw), amount)
	else:
		sweep = lerpf(previous_guard, 0.0, amount) if phase == "preparation" else 0.0
		overhead = lerpf(0.0, OVERHEAD_WINDUP, amount) if phase == "preparation" else lerpf(OVERHEAD_WINDUP, OVERHEAD_END, amount) if phase == "active" else lerpf(OVERHEAD_END, 0.0, amount)
		shoulder_lift = OVERHEAD_SHOULDER_LIFT * amount if phase == "preparation" else OVERHEAD_SHOULDER_LIFT * (1.0 - amount) if phase == "active" else 0.0
	return {
		"torso_yaw": sweep * 0.24, "shoulder_yaw": sweep * 0.20,
		"arm_yaw": sweep * 0.42, "wrist_yaw": sweep * 0.14,
		"torso_pitch": overhead * 0.10, "shoulder_pitch": overhead * 0.18,
		"arm_pitch": overhead * 0.34, "forearm_pitch": overhead * 0.25,
		"wrist_pitch": overhead * 0.13,
		"shoulder_lift": shoulder_lift,
	}


static func guard_yaw(step: int) -> float:
	return float(STEP_PRESENTATION[clampi(step, 0, 2)].guard_yaw)


static func preparation_yaw(step: int, start_yaw: float, progress: float) -> float:
	var endpoint: float = STEP_PRESENTATION[clampi(step, 0, 2)].windup_yaw
	return lerpf(start_yaw, endpoint, smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0)))


static func _material(color: Color, opacity: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.albedo_color.a = opacity
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	material.vertex_color_use_as_albedo = true
	return material
