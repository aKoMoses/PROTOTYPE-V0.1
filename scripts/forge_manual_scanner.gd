extends Node3D

## Local inspection only. Four rigid joints remain on the imported Blender arm.
signal enabled_changed(enabled: bool)

const PAINT := preload("res://scripts/robot_chassis_visuals.gd")
const JOINT_NAMES := ["BaseYaw", "Shoulder", "Elbow", "Wrist"]
const LIMITS := [Vector2(-35, 45), Vector2(-40, 75), Vector2(18, 138), Vector2(-65, 70)]
const SPEEDS := Vector4(1.3, 1.25, 1.65, 2.2)
const COLOR := Color("#77e5ee")
const STANDOFF := Vector3(0.42, 0.04, 0.24)

var stage
var enabled := false
var held := false
var target_valid := false
var target_zone := ""
var surface_point := Vector3.ZERO
var surface_normal := Vector3.FORWARD
var tool_target := Vector3.ZERO
var scanning := false
var scan_elapsed := 0.0
var rejection := ""
var _joints: Array[Node3D] = []
var _bones: Dictionary = {}
var _rest := Vector4.ZERO
var _command := Vector4.ZERO
var _solution := Vector4.ZERO
var _saved_yaw := 0.0
var _lengths := Vector3(1.3, 1.1, 0.36)
var _pointer := Vector2.ZERO
var _has_pointer := false
var _automatic_surface := false
var motion_speed := 1.0
var _clock := 0.0
var _zones: Array[Dictionary] = []
var _projector: Node3D
var _lamp: SpotLight3D
var _beam: MeshInstance3D
var _halo: MeshInstance3D
var _scan_patch: Node3D
var _ring: MeshInstance3D
var _stripe: MeshInstance3D
var _motor: AudioStreamPlayer


func configure(garage_stage: Node) -> void:
	stage = garage_stage


func _ready() -> void:
	process_priority = 2
	for label in JOINT_NAMES:
		var joint := stage.arm.model.find_child(label, true, false) as Node3D
		if joint == null:
			push_error("Manual scanner: missing arm joint " + label)
			return
		_joints.append(joint)
	_rest = Vector4(_joints[0].rotation.y, _joints[1].rotation.z, _joints[2].rotation.z, _joints[3].rotation.z)
	_command = _rest
	_lengths = Vector3(_joints[2].position.length(), _joints[3].position.length(), stage.arm.contact.position.length())
	for index in stage.skeleton.get_bone_count():
		var label: String = stage.skeleton.get_bone_name(index)
		_bones[label.to_lower().trim_prefix("mixamorig_").trim_prefix("mixamorig:")] = index
	stage.arm.manual_control_cancelled.connect(_forced_cancel)
	_build_projection()
	_build_motor()
	set_process(false)


func set_enabled(value: bool) -> void:
	if value == enabled or _joints.size() != 4:
		return
	if value:
		stage.end_robot_rotation()
		stage._return_to_idle()
		_saved_yaw = stage.robot.rotation.y
		stage.robot.rotation.y = stage.ROBOT_YAW
		stage.arm.begin_manual_control()
		_command = _rest
		enabled = true
		stage.arm.manual_phase = "SCANNER MANUEL"
		_update_zones()
	else:
		enabled = false
		retract()
		stage.arm.end_manual_control()
		stage.robot.rotation.y = _saved_yaw
	set_process(enabled)
	enabled_changed.emit(enabled)


func _forced_cancel() -> void:
	if not enabled:
		return
	enabled = false
	retract()
	stage.robot.rotation.y = _saved_yaw
	set_process(false)
	enabled_changed.emit(false)


func point_at(position_in_stage: Vector2, pressed: bool = false) -> void:
	if not enabled:
		return
	_pointer = position_in_stage
	_automatic_surface = false
	_has_pointer = true
	held = pressed
	_pick_target()


func point_at_surface(point: Vector3, normal: Vector3, label: String) -> bool:
	if not enabled:
		return false
	_automatic_surface = true
	_has_pointer = false
	held = true
	_update_zones()
	surface_point = point
	surface_normal = normal.normalized()
	target_zone = label
	tool_target = point + stage.robot.global_basis.orthonormalized() * STANDOFF
	var solution := solve_pose(tool_target)
	target_valid = not solution.is_empty() and pose_is_clear(solution.get("angles", _rest))
	if target_valid:
		_solution = solution.angles
	return target_valid


func retract() -> void:
	held = false
	_has_pointer = false
	_automatic_surface = false
	target_valid = false
	target_zone = ""
	scanning = false
	scan_elapsed = 0.0
	_hide_projection()
	if _motor != null:
		_motor.stop()
		_motor.volume_db = -60.0


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not enabled:
		return
	_clock += delta
	_update_zones()
	if _has_pointer:
		_pick_target()
	var desired := _solution if target_valid else _rest
	var candidate := _command
	var movement := 0.0
	for index in 4:
		var difference := angle_difference(_command[index], desired[index])
		var step := clampf(difference * (1.0 - exp(-delta * 6.5 * motion_speed)), -SPEEDS[index] * motion_speed * delta, SPEEDS[index] * motion_speed * delta)
		candidate[index] += step
		movement += absf(step) / maxf(delta, 0.0001)
	if target_valid and not pose_is_clear(candidate):
		retract()
		rejection = "BRAS HORS PORTÉE"
	else:
		_command = candidate
	_apply_angles(_command)
	var error: float = stage.arm.contact.global_position.distance_to(tool_target)
	scanning = held and target_valid and error < 0.065
	if scanning:
		scan_elapsed += delta
		# A tiny mechanical tremor remains subordinate to the solved wrist pose.
		_joints[3].rotation.z = _command.w + sin(_clock * 47.0) * 0.002
	else:
		scan_elapsed = 0.0
	_update_projection()
	_update_motor(delta, movement)
	if scanning:
		stage.arm.manual_phase = "BALAYAGE DU " + target_zone if target_zone == "TORSE" else "BALAYAGE DE L’ÉPAULE"
	elif target_valid:
		stage.arm.manual_phase = "MAINTIENS POUR SCANNER" if error < 0.065 else "BRAS EN APPROCHE"
	elif _command.distance_to(_rest) > 0.04:
		stage.arm.manual_phase = "RETOUR DU BRAS"
	else:
		stage.arm.manual_phase = rejection if _has_pointer and rejection != "" else "SCANNER MANUEL"


func _apply_angles(angles: Vector4) -> void:
	_joints[0].rotation.y = angles.x
	_joints[1].rotation.z = angles.y
	_joints[2].rotation.z = angles.z
	_joints[3].rotation.z = angles.w


func _anchor(label: String, offset: Vector3) -> Vector3:
	var index := int(_bones.get(label, -1))
	var factor := float(PAINT.SCALE_FACTORS.get(stage.chassis_id, 1.0))
	var pose: Transform3D = stage.skeleton.global_transform * stage.skeleton.get_bone_global_pose(index)
	return pose.origin + stage.robot.global_basis.orthonormalized() * offset * factor


func _update_zones() -> void:
	var factor := float(PAINT.SCALE_FACTORS.get(stage.chassis_id, 1.0))
	var rotation: Basis = stage.robot.global_basis.orthonormalized()
	_zones = [
		{"label": "TORSE", "center": _anchor("spine1", Vector3(0, 0.06, -0.04)), "radii": Vector3(0.40, 0.33, 0.30) * factor, "basis": rotation},
		{"label": "ÉPAULE", "center": _anchor("leftarm", Vector3(0.025, 0.05, 0.025)), "radii": Vector3(0.23, 0.23, 0.24) * factor, "basis": rotation},
		{"label": "ÉPAULE", "center": _anchor("rightarm", Vector3(-0.025, 0.05, 0.025)), "radii": Vector3(0.23, 0.23, 0.24) * factor, "basis": rotation},
	]


func _pick_target() -> void:
	target_valid = false
	target_zone = ""
	rejection = "VISE LE TORSE OU LES ÉPAULES"
	if stage.size.x <= 0 or stage.size.y <= 0 or not Rect2(Vector2.ZERO, stage.size).has_point(_pointer):
		return
	var screen: Vector2 = _pointer * Vector2(stage.viewport.size) / stage.size
	var origin: Vector3 = stage.camera.project_ray_origin(screen)
	var direction: Vector3 = stage.camera.project_ray_normal(screen)
	var nearest := INF
	for zone in _zones:
		var inverse: Basis = (zone.basis as Basis).transposed()
		var radii: Vector3 = zone.radii
		var local_origin: Vector3 = inverse * (origin - (zone.center as Vector3)) / radii
		var local_direction: Vector3 = inverse * direction / radii
		var a := local_direction.length_squared()
		var b := 2.0 * local_origin.dot(local_direction)
		var c := local_origin.length_squared() - 1.0
		var discriminant := b * b - 4.0 * a * c
		if discriminant < 0.0:
			continue
		var distance := (-b - sqrt(discriminant)) / (2.0 * a)
		if distance <= 0.0 or distance >= nearest:
			continue
		nearest = distance
		surface_point = origin + direction * distance
		var local_hit: Vector3 = inverse * (surface_point - (zone.center as Vector3))
		surface_normal = ((zone.basis as Basis) * (local_hit / (radii * radii))).normalized()
		target_zone = zone.label
	if is_inf(nearest):
		return
	tool_target = surface_point + stage.robot.global_basis.orthonormalized() * STANDOFF
	var solution := solve_pose(tool_target)
	if solution.is_empty():
		rejection = "BRAS HORS PORTÉE"
		return
	_solution = solution.angles
	if not pose_is_clear(_solution):
		rejection = "TRAJECTOIRE BLOQUÉE"
		return
	target_valid = true
	rejection = ""


func solve_pose(target: Vector3) -> Dictionary:
	var shoulder_position: Vector3 = _joints[1].global_position
	var offset := target - shoulder_position
	var yaw := atan2(offset.z, -offset.x)
	var end_angle := deg_to_rad(100.0)
	var horizontal := Vector2(offset.x, offset.z).length() - _lengths.z * sin(end_angle)
	var vertical := offset.y - _lengths.z * cos(end_angle)
	var cosine := (horizontal * horizontal + vertical * vertical - _lengths.x * _lengths.x - _lengths.y * _lengths.y) / (2.0 * _lengths.x * _lengths.y)
	if cosine < -1.0 or cosine > 1.0:
		return {}
	var elbow := acos(cosine)
	var shoulder := atan2(horizontal, vertical) - atan2(_lengths.y * sin(elbow), _lengths.x + _lengths.y * cos(elbow))
	var angles := Vector4(yaw, shoulder, elbow, end_angle - shoulder - elbow)
	for index in 4:
		if not is_finite(angles[index]) or angles[index] < deg_to_rad(LIMITS[index].x) or angles[index] > deg_to_rad(LIMITS[index].y):
			return {}
	return {"angles": angles}


func joint_positions(angles: Vector4) -> Array[Vector3]:
	var origin: Vector3 = _joints[1].global_position
	var heading := Vector3(-cos(angles.x), 0, sin(angles.x))
	var elbow := origin + heading * sin(angles.y) * _lengths.x + Vector3.UP * cos(angles.y) * _lengths.x
	var wrist := elbow + heading * sin(angles.y + angles.z) * _lengths.y + Vector3.UP * cos(angles.y + angles.z) * _lengths.y
	var tip := wrist + heading * sin(angles.y + angles.z + angles.w) * _lengths.z + Vector3.UP * cos(angles.y + angles.z + angles.w) * _lengths.z
	return [origin, elbow, wrist, tip]


func pose_is_clear(angles: Vector4) -> bool:
	var points := joint_positions(angles)
	for segment in 3:
		var clearance: float = [0.18, 0.14, 0.08][segment]
		for sample in range(1, 13):
			var point := points[segment].lerp(points[segment + 1], float(sample) / 12.0)
			for zone in _zones:
				var inverse: Basis = (zone.basis as Basis).transposed()
				var radii: Vector3 = zone.radii + Vector3.ONE * clearance
				var local: Vector3 = inverse * (point - (zone.center as Vector3)) / radii
				if local.length_squared() < 1.0:
					return false
	return true


func _glow(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(COLOR, alpha)
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 2.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	return material


func _beam_mesh(radius: float, alpha: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.material = _glow(alpha)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _build_projection() -> void:
	_projector = Node3D.new()
	_projector.name = "ManualScannerOptic"
	stage.arm.contact.add_child(_projector)
	_lamp = SpotLight3D.new()
	_lamp.light_color = COLOR
	_lamp.spot_range = 1.4
	_lamp.spot_angle = 29.0
	_lamp.spot_attenuation = 0.8
	_projector.add_child(_lamp)
	_beam = _beam_mesh(0.004, 0.75)
	_halo = _beam_mesh(0.018, 0.06)
	_scan_patch = Node3D.new()
	_scan_patch.name = "SurfaceScan"
	add_child(_scan_patch)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.058
	ring_mesh.outer_radius = 0.063
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	ring_mesh.material = _glow(0.65)
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scan_patch.add_child(_ring)
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.16, 0.0025, 0.004)
	stripe_mesh.material = _glow(0.9)
	_stripe = MeshInstance3D.new()
	_stripe.mesh = stripe_mesh
	_stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scan_patch.add_child(_stripe)
	_hide_projection()


func _hide_projection() -> void:
	if _lamp == null:
		return
	_lamp.visible = false
	_beam.visible = false
	_halo.visible = false
	_scan_patch.visible = false


func _update_projection() -> void:
	_hide_projection()
	if not target_valid:
		return
	var tip: Vector3 = stage.arm.contact.global_position
	var distance := tip.distance_to(surface_point)
	# The lamp turns on only near the metal, never while crossing the workshop.
	_lamp.visible = distance < 0.7
	if _lamp.visible:
		_projector.look_at(surface_point, Vector3.UP)
		_lamp.light_energy = 2.6 + sin(scan_elapsed * 14.0) * 0.2 if scanning else 0.55
	if not scanning:
		return
	var endpoint := surface_point + surface_normal * 0.015
	var direction := endpoint - tip
	var beam_basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	for beam in [_beam, _halo]:
		beam.global_transform = Transform3D(beam_basis.scaled(Vector3(1, direction.length(), 1)), (tip + endpoint) * 0.5)
		beam.visible = true
	var patch_basis := Basis(Quaternion(Vector3.UP, surface_normal))
	_scan_patch.global_transform = Transform3D(patch_basis, endpoint)
	_scan_patch.visible = true
	_ring.scale = Vector3.ONE * (1.0 + sin(scan_elapsed * 4.0) * 0.14)
	_stripe.position.z = sin(scan_elapsed * 3.0) * 0.045


func _build_motor() -> void:
	# A quiet loop is synthesized once, avoiding network/media dependencies.
	var rate := 24000
	var data := PackedByteArray()
	data.resize(rate)
	for index in rate / 2:
		var t := float(index) / rate
		var wave := (sin(TAU * 120.0 * t) * 0.60 + sin(TAU * 360.0 * t) * 0.16 + sin(TAU * 780.0 * t) * 0.04) * (0.9 + sin(TAU * 18.0 * t) * 0.1)
		data.encode_s16(index * 2, int(wave * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = rate / 2
	_motor = AudioStreamPlayer.new()
	_motor.name = "ScannerServo"
	_motor.stream = stream
	_motor.bus = &"Effects"
	_motor.volume_db = -60.0
	add_child(_motor)


func _update_motor(delta: float, movement: float) -> void:
	var volume := -60.0
	if movement > 0.07:
		volume = -29.0
	elif scanning:
		volume = -35.0
	_motor.volume_db = move_toward(_motor.volume_db, volume, delta * 100.0)
	_motor.pitch_scale = lerpf(_motor.pitch_scale, 0.86 + minf(movement, 3.0) * 0.09, minf(delta * 8.0, 1.0))
	if _motor.volume_db > -59.0 and not _motor.playing:
		_motor.play()
	elif _motor.volume_db <= -59.0:
		_motor.stop()


func _exit_tree() -> void:
	if is_instance_valid(_projector):
		_projector.queue_free()
