extends Node3D
class_name MekatanaVisual

## Attached presentation only. Combat owns phases, movement and validated hits.
## Source GLB is untouched; SourceAlignment seats its diagonal handle at the grip.
const ELECTRIC_COLOR := Color("#70e7ff")
const MELEE := preload("res://scripts/mekatana_attack.gd")
const DATA := preload("res://scripts/combat_data.gd")
const MAX_TRAIL_SAMPLES := 16
## Presentation endpoints, sound grains and electrical intensity are shared by
## both rigs. These settings never change damage, casts or dash durations.
const STEP_PRESENTATION := [
	{
		"windup_yaw": 48.0, "strike_yaw": -48.0, "guard_yaw": -34.0,
		"electric_intensity": 0.66, "trail_opacity": 0.24,
		"trail_life": 0.050, "trail_blade_start": 0.88,
		"slash_duration": 0.11, "slash_pitch": 1.22, "slash_volume": -23.0,
		"impact_duration": 0.075, "impact_pitch": 1.16, "impact_volume": -23.0,
		"impact_scale": 0.80, "arc_count": 1, "arc_width": 0.012,
		"arc_life": 0.055, "arc_length": 0.15,
	},
	{
		"windup_yaw": -88.0, "strike_yaw": 88.0, "guard_yaw": 32.0,
		"electric_intensity": 0.95, "trail_opacity": 0.32,
		"trail_life": 0.065, "trail_blade_start": 0.84,
		"slash_duration": 0.16, "slash_pitch": 1.02, "slash_volume": -20.0,
		"impact_duration": 0.105, "impact_pitch": 0.96, "impact_volume": -20.0,
		"impact_scale": 1.00, "arc_count": 2, "arc_width": 0.016,
		"arc_life": 0.075, "arc_length": 0.22,
	},
	{
		"windup_yaw": 0.0, "strike_yaw": 0.0, "guard_yaw": 0.0,
		"electric_intensity": 1.20, "trail_opacity": 0.38,
		"trail_life": 0.080, "trail_blade_start": 0.82,
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
var _rig: Node3D
var _actor: Node3D
var _cleave: MeshInstance3D
var _cleave_sparks: MeshInstance3D
var _cleave_mesh := ImmediateMesh.new()
var _spark_mesh := ImmediateMesh.new()
var _electric_mesh := ImmediateMesh.new()
var _trail_mesh := ImmediateMesh.new()
var _cleave_origin := Vector3.ZERO
var _cleave_direction := Vector3.FORWARD
var _cleave_points := PackedVector2Array()
var _wall_fractions := PackedFloat32Array()
var _sparks: Array[Dictionary] = []
var _cleave_tail := 0.0
var _hit_glow := 0.0


func _ready() -> void:
	process_priority = 120
	_blade_base = get_node("BladeBase") as Marker3D
	_blade_tip = get_node("BladeTip") as Marker3D
	_electric_material = _material(ELECTRIC_COLOR, 0.35)
	_electric = MeshInstance3D.new()
	_electric.name = "BladeCurrent"
	_electric.mesh = _electric_mesh
	_electric.material_override = _electric_material
	_electric.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_electric)
	_trail_material = _material(ELECTRIC_COLOR, 0.26)
	_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail = MeshInstance3D.new()
	_trail.name = "BladeTrail"
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.material_override = _trail_material
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY
	_cleave = _world_mesh("CleaveEnvelope", _cleave_mesh)
	_cleave_sparks = _world_mesh("CleaveSparks", _spark_mesh)
	_audio = AudioStreamPlayer.new()
	_audio.name = "MekatanaSound"
	_audio.max_polyphony = 3
	_audio.volume_db = -19.0
	if AudioServer.get_bus_index("Effects") >= 0:
		_audio.bus = &"Effects"
	add_child(_audio)
	_charge_sound = _sound(0.14, 0)
	for step in range(3):
		var settings: Dictionary = STEP_PRESENTATION[step]
		_slash_sounds.append(_sound(float(settings.slash_duration), 1, step))
		_impact_sounds.append(_sound(float(settings.impact_duration), 2, step))
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is Skeleton3D:
			_skeleton = ancestor as Skeleton3D
			_skeleton.skeleton_updated.connect(sample_blade_pose)
		if _rig == null and ancestor is Node3D and ancestor.has_method("set_mekatana_pose"):
			_rig = ancestor as Node3D
		if ancestor is Node3D and ancestor.has_method("get_health"):
			_actor = ancestor as Node3D
			break
		ancestor = ancestor.get_parent()


func _process(delta: float) -> void:
	_clock += maxf(0.0, delta)
	_hit_glow = maxf(0.0, _hit_glow - delta)
	if not is_visible_in_tree():
		_samples.clear()
		_sparks.clear()
		_trail.visible = false
		_cleave.hide()
		_cleave_sparks.hide()
		return
	_update_electric()
	# Skeleton signal and explicit bot refresh own the samples. Rendering only
	# retires them, so a slow render frame cannot lengthen the visible trail.
	_retire_samples()
	_rebuild_trail()
	_update_cleave(delta)


func set_phase(step: int, phase: String, progress: float) -> void:
	var changed := phase != _phase or step != _step
	_step = clampi(step, 0, 2)
	_phase = phase
	_progress = clampf(progress, 0.0, 1.0)
	var settings: Dictionary = STEP_PRESENTATION[_step]
	if changed:
		if phase == "active":
			_capture_cleave_frame()
			_cleave_points = MELEE.cleave_boundary(DATA.WEAPON_DEFINITIONS.mekatana, _step)
			_clip_cleave_boundary()
			_seed_cleave_sparks()
		elif phase == "recovery":
			_cleave_tail = 0.075
		elif phase in ["", "preparation"]:
			_sparks.clear()
			_cleave_tail = 0.0
			_cleave.hide()
			_cleave_sparks.hide()
	if is_instance_valid(_trail_material):
		_trail_material.albedo_color.a = float(settings.trail_opacity)
	if changed and is_instance_valid(_audio):
		if phase == "preparation":
			_samples.clear()
			_audio.stream = _charge_sound
			_audio.pitch_scale = [1.18, 1.05, 0.92][_step]
			_audio.volume_db = float(settings.slash_volume) - 1.0
			_audio.play()
		elif phase == "active":
			_audio.stream = _slash_sounds[_step]
			_audio.pitch_scale = float(settings.slash_pitch)
			_audio.volume_db = float(settings.slash_volume)
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
	var filament_length := minf(base.distance_to(tip) * (1.0 - float(settings.trail_blade_start)), 0.025 + float(_step) * 0.010)
	_samples.append({"base": tip - (tip - base).normalized() * filament_length, "tip": tip, "time": _clock})
	while _samples.size() > MAX_TRAIL_SAMPLES:
		_samples.pop_front()
	_retire_samples()
	_rebuild_trail()


func set_mekatana_impact(target: Node3D, power: float = 1.0) -> void:
	if not is_instance_valid(target) or get_tree().current_scene == null:
		return
	var manager := get_tree().current_scene.get_node_or_null("VFXManager")
	_capture_cleave_frame()
	var normal := _cleave_origin - target.global_position
	normal.y = 0.0
	normal = normal.normalized() if normal.length_squared() > 0.001 else -_cleave_direction
	var radius := float(target.call("get_fulguro_hit_radius")) if target.has_method("get_fulguro_hit_radius") else 0.45
	var origin := target.global_position + Vector3.UP * 0.85 + normal * radius * 0.65
	var settings: Dictionary = STEP_PRESENTATION[_step]
	var strength := clampf(power * float(settings.impact_scale), 0.4, 1.65)
	_hit_glow = 0.065
	if manager != null:
		manager.call("impact", origin, normal, "robot", strength, ELECTRIC_COLOR)
		manager.call("burst", origin, (normal + Vector3.UP * 0.7).normalized(), Color("#ffe4b2"), 6 + _step * 3, 2.2 + float(_step) * 0.6, 0.15 + float(_step) * 0.03, 0.032, 65.0)
		var arc_count := int(settings.arc_count) + (1 if strength > 1.4 else 0)
		for index in range(arc_count):
			var side := Vector3(cos(float(index) * 2.4), 0.25, sin(float(index) * 2.4))
			manager.call("tracer", origin, origin + side * (float(settings.arc_length) * strength), float(settings.arc_width), ELECTRIC_COLOR, float(settings.arc_life))
	if _audio != null:
		_audio.stream = _impact_sounds[_step]
		_audio.pitch_scale = float(settings.impact_pitch) / sqrt(strength)
		_audio.volume_db = float(settings.impact_volume)
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
	strength += _hit_glow / 0.065 * 0.65
	_electric_material.albedo_color.a = 0.16 + strength * 0.48
	var mesh := _electric_mesh
	mesh.clear_surfaces()
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
	var mesh := _trail_mesh
	mesh.clear_surfaces()
	var lifetime: float = STEP_PRESENTATION[_step].trail_life
	var has_surface := false
	for index in range(1, _samples.size()):
		var previous: Dictionary = _samples[index - 1]
		var current: Dictionary = _samples[index]
		if Vector3(previous.tip).distance_squared_to(current.tip) > 4.0:
			continue # A skipped pose/teleport must not create a giant curtain.
		if not has_surface:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			has_surface = true
		var age := clampf(1.0 - (_clock - float(current.time)) / lifetime, 0.0, 1.0)
		_trail_vertex(mesh, previous.base, age * 0.02)
		_trail_vertex(mesh, previous.tip, age)
		_trail_vertex(mesh, current.tip, age)
		_trail_vertex(mesh, previous.base, age * 0.02)
		_trail_vertex(mesh, current.tip, age)
		_trail_vertex(mesh, current.base, age * 0.02)
	if has_surface:
		mesh.surface_end()
	_trail.visible = has_surface
	_trail.mesh = mesh


func _trail_vertex(mesh: ImmediateMesh, point: Vector3, opacity: float) -> void:
	mesh.surface_set_color(Color(1.0, 1.0, 1.0, opacity))
	mesh.surface_add_vertex(point)


func _world_mesh(label: String, mesh: ImmediateMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.top_level = true
	node.mesh = mesh
	var material := _material(Color.WHITE, 1.0)
	material.emission = ELECTRIC_COLOR
	material.emission_energy_multiplier = 1.6
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_transform = Transform3D.IDENTITY
	node.hide()
	return node


func _capture_cleave_frame() -> void:
	_cleave_origin = _actor.global_position if is_instance_valid(_actor) else _rig.global_position if is_instance_valid(_rig) else global_position
	var facing := -_rig.global_basis.z if is_instance_valid(_rig) else Vector3.FORWARD
	if is_instance_valid(_actor) and _actor.has_method("get_mekatana_state"):
		facing = Vector3(_actor.get("aim_direction"))
	facing.y = 0.0
	_cleave_direction = facing.normalized() if facing.length_squared() > 0.001 else Vector3.FORWARD


func _clip_cleave_boundary() -> void:
	# Use the same wall mask and ray height as damage. The envelope visibly
	# stops at cover instead of advertising a hittable region behind it.
	_wall_fractions.resize(_cleave_points.size())
	var excluded: Array[RID] = []
	if is_instance_valid(_actor):
		_append_rids(_actor, excluded)
	for index in _cleave_points.size():
		var start := _cleave_origin + Vector3.UP * 0.85
		var end := _cleave_world(_cleave_points[index], 0.85)
		var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 8, excluded)
		query.collide_with_areas = true
		var collision := get_world_3d().direct_space_state.intersect_ray(query)
		var length := start.distance_to(end)
		_wall_fractions[index] = clampf((start.distance_to(collision.position) - 0.025) / maxf(length, 0.001), 0.0, 1.0) if not collision.is_empty() else 1.0


func _append_rids(node: Node, output: Array[RID]) -> void:
	if node is CollisionObject3D:
		output.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_append_rids(child, output)


func _cleave_world(point: Vector2, height: float) -> Vector3:
	return _cleave_origin + _cleave_direction.cross(Vector3.UP).normalized() * point.x + _cleave_direction * point.y + Vector3.UP * height


func _seed_cleave_sparks() -> void:
	_sparks.clear()
	var count := 28 + _step * 8
	for index in range(count):
		var sample := int(float(index) / float(count - 1) * float(_cleave_points.size() - 1))
		var point := _cleave_points[sample] * _wall_fractions[sample]
		var grain := fmod(float(index) * 0.6180339, 1.0)
		var radius := 1.0 if index % 3 != 0 else lerpf(0.38, 0.88, grain)
		var height := 0.055 if index % 2 == 0 else 0.45 + grain * 0.40
		var tangent := _cleave_direction.cross(Vector3.UP) * (-1.0 if _step == 1 else 1.0)
		_sparks.append({"position": _cleave_world(point * radius, height),
			"velocity": tangent * (0.12 + grain * 0.25) + Vector3.UP * (0.18 + grain * 0.45),
			"born": _clock + grain * 0.025, "life": 0.12 + grain * 0.09,
			"width": 0.018 + grain * 0.014, "grain": grain})


func _update_cleave(delta: float) -> void:
	if _phase == "active":
		var previous := _cleave_origin
		_capture_cleave_frame()
		if previous.distance_squared_to(_cleave_origin) > 0.000004:
			_clip_cleave_boundary()
	else:
		_cleave_tail = maxf(0.0, _cleave_tail - delta)
	var fade := 1.0 if _phase == "active" else _cleave_tail / 0.075 * 0.35
	_cleave.visible = fade > 0.001 and _cleave_points.size() > 1
	if _cleave.visible:
		_rebuild_cleave(fade)
	_rebuild_sparks()


func _rebuild_cleave(fade: float) -> void:
	_cleave_mesh.clear_surfaces()
	_cleave_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cut := 1.0 - pow(1.0 - _progress, 2.4)
	var sweep := 0.5 if _step == 2 else cut if _step == 0 else 1.0 - cut
	for index in range(1, _cleave_points.size()):
		var a := _cleave_points[index - 1] * _wall_fractions[index - 1]
		var b := _cleave_points[index] * _wall_fractions[index]
		# A faint fan makes the interior readable; thin rims and moving grains
		# show its actual limit without covering the target or the blade.
		_cleave_triangle(_cleave_world(Vector2.ZERO, 0.055), _cleave_world(a, 0.055), _cleave_world(b, 0.055), ELECTRIC_COLOR, 0.045 * fade)
		var amount := float(index) / float(_cleave_points.size() - 1)
		var pulse := exp(-pow((amount - sweep) * 6.0, 2.0))
		for radius in [0.82, 1.0]:
			var alpha := (0.65 + pulse * 0.30) if radius == 1.0 else 0.10 + pulse * 0.15
			var inner: float = float(radius) - (0.040 if radius == 1.0 else 0.018)
			_cleave_strip(a, b, inner, radius, 0.060, ELECTRIC_COLOR.lerp(Color.WHITE, pulse * 0.8), alpha * fade)
		# A second, airy row of sparks at blade height ties the floor footprint
		# to the real swing. The overhead finisher keeps the same broad cleave.
		_cleave_strip(a, b, 0.987, 1.0, 0.72, ELECTRIC_COLOR, pulse * 0.38 * fade)
	_cleave_mesh.surface_end()


func _cleave_strip(a: Vector2, b: Vector2, inner: float, outer: float, height: float, color: Color, alpha: float) -> void:
	var p := _cleave_world(a * inner, height)
	var q := _cleave_world(a * outer, height)
	var r := _cleave_world(b * outer, height)
	var s := _cleave_world(b * inner, height)
	_cleave_triangle(p, q, r, color, alpha)
	_cleave_triangle(p, r, s, color, alpha)


func _cleave_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, alpha: float) -> void:
	_cleave_mesh.surface_set_color(Color(color.r, color.g, color.b, alpha))
	_cleave_mesh.surface_add_vertex(a)
	_cleave_mesh.surface_add_vertex(b)
	_cleave_mesh.surface_add_vertex(c)


func _rebuild_sparks() -> void:
	_sparks = _sparks.filter(func(spark: Dictionary) -> bool: return _clock - float(spark.born) < float(spark.life))
	_cleave_sparks.visible = not _sparks.is_empty()
	if not _cleave_sparks.visible:
		return
	_spark_mesh.clear_surfaces()
	_spark_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var camera := get_viewport().get_camera_3d()
	var side := camera.global_basis.x.normalized() if is_instance_valid(camera) else Vector3.RIGHT
	for spark in _sparks:
		var age := _clock - float(spark.born)
		if age < 0.0:
			continue
		var amount := clampf(age / float(spark.life), 0.0, 1.0)
		var position: Vector3 = spark.position + spark.velocity * age
		var tail: Vector3 = spark.velocity * (0.055 + float(spark.grain) * 0.10)
		var width := side * float(spark.width) * (1.0 - amount * 0.75)
		_spark_mesh.surface_set_color(Color(0.78, 0.97, 1.0, pow(1.0 - amount, 1.6)))
		for vertex in [position - width, position + width, position + tail, position - width, position - tail, position + width]:
			_spark_mesh.surface_add_vertex(vertex)
	_spark_mesh.surface_end()


static func pose_angles(step: int, phase: String, progress: float) -> Dictionary:
	# Anatomical forward is +Z, corrected by PI at the model root. Positive
	# skeleton yaw is therefore the attacker's left; the first swing goes + to -.
	var amount := smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	if phase == "active":
		# A quick cut followed by a longer follow-through, continuous at both ends.
		amount = 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 2.4)
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


static func _sound(duration: float, kind: int, step: int = 0) -> AudioStreamWAV:
	# Short, deterministic electrical/metallic grains; no gameplay random state.
	var sample_rate := 22050
	var count := int(duration * float(sample_rate))
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in range(count):
		var time := float(index) / float(sample_rate)
		var amount := float(index) / float(count)
		var envelope := sin(minf(amount * 12.0, 1.0) * PI * 0.5) * pow(1.0 - amount, 2.0)
		var grain := sin(float(index) * 12.9898) * sin(float(index) * 0.731)
		var frequency := lerpf(420.0, 1050.0, amount) if kind == 0 else lerpf([1250.0, 920.0, 660.0][step], [260.0, 180.0, 110.0][step], amount)
		var wave := sin(TAU * frequency * time) * 0.35 + grain * (0.20 if kind == 0 else 0.65)
		if kind == 1:
			wave += sin(TAU * [180.0, 140.0, 90.0][step] * time) * [0.06, 0.14, 0.27][step]
		if kind == 2:
			wave += sin(TAU * [1900.0, 1400.0, 960.0][step] * time) * 0.20
		data.encode_s16(index * 2, int(clampf(wave * envelope, -1.0, 1.0) * 12500.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = sample_rate
	sound.data = data
	return sound
