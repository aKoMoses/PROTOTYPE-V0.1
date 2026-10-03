extends Node

## A cartridge leaves its bay after the authored gripper reaches it. Equipment
## changes at the mounting contact; interruption before then is reversible.
signal mounted(category: String, identifier: String)
signal completed(identifier: String)
signal cancelled

const INSTALLATION_AUDIO := preload("res://scripts/forge_installation_audio.gd")

const DURATION := 7.05
const WORK_TIME := 0.80
const JOINT_NAMES := ["BaseYaw", "Shoulder", "Elbow", "Wrist"]
const PHASES := ["approach", "pickup", "lift", "carry", "align", "work", "release", "return"]
const TIMES := [1.55, 0.35, 0.55, 1.70, 0.55, WORK_TIME, 0.35, 1.20]
const REAL_MODULES := ["pyro_boots", "bio_injector", "rocket_basket", "magnetic_field", "auxiliary_reactor", "fulguro_punch", "static_shield", "javelin", "projector", "pelto_smash", "counter", "permutation", "eclipse", "baroud", "omnivamp", "tracker", "alternator", "inertia"]
const LIMITS := [Vector2(-180, 180), Vector2(-55, 85), Vector2(18, 145), Vector2(-95, 85)]

var stage
var focus
var active := false
var equipment_id := ""
var category := ""
var phase := ""
var elapsed := 0.0
var worked_seconds := 0.0
var reached_module := false
var mounted_module := false
var _phase_index := 0
var _phase_elapsed := 0.0
var _joints: Array[Node3D] = []
var _joint_rest: Array[Transform3D] = []
var _fingers: Array[Node3D] = []
var _finger_rest: Array[Vector3] = []
var _rest := Vector4.ZERO
var _angles := Vector4.ZERO
var _return_angles := Vector4.ZERO
var _lengths := Vector3(1.3, 1.1, 0.36)
var _shoulder_offset := Vector3.ZERO
var _arm_original := Transform3D.IDENTITY
var _robot_yaw := 0.0
var _weapon_visible := true
var _source := Transform3D.IDENTITY
var _source_base := Vector3.ZERO
var _lift_point := Vector3.ZERO
var _approach_point := Vector3.ZERO
var _release_point := Vector3.ZERO
var _mount_pose := Transform3D.IDENTITY
var _payload: Node3D
var _gripper: Node3D
var _clamp_jaws: Array[Node3D] = []
var _installed: Dictionary = {}
var _bones: Dictionary = {}
var _carriage: Node3D
var _wheels: Array[Node3D] = []
var _pulse: OmniLight3D
var _camera_from := Transform3D.IDENTITY
var _camera_fov_from := 31.0
var _phase_camera := Transform3D.IDENTITY
var _phase_fov := 36.0
var _camera_started := false
var _restoring := false
var _lens_distance := 10.0
var _lens_transition := 3.0
var audio: INSTALLATION_AUDIO


func configure(garage_stage: Node, equipment_focus: Node) -> void:
	stage = garage_stage
	focus = equipment_focus


func _ready() -> void:
	process_priority = 3
	for label in JOINT_NAMES:
		var joint := stage.arm.model.find_child(label, true, false) as Node3D
		if joint == null:
			push_error("Installation: missing service-arm joint " + label)
			return
		_joints.append(joint)
	_rest = _read_angles()
	_angles = _rest
	_lengths = Vector3(_joints[2].position.length(), _joints[3].position.length(), stage.arm.contact.position.length())
	for node in stage.arm.model.find_children("ToolFinger*", "Node3D", true, false):
		_fingers.append(node as Node3D)
		_finger_rest.append((node as Node3D).position)
	for index in stage.skeleton.get_bone_count():
		var label: String = stage.skeleton.get_bone_name(index)
		_bones[label.to_lower().trim_prefix("mixamorig_").trim_prefix("mixamorig:")] = index
	stage.arm.manual_control_cancelled.connect(_forced_cancel)
	_build_carriage()
	audio = INSTALLATION_AUDIO.new()
	add_child(audio)
	set_process(false)


func begin(identifier: String, kind: String = "") -> bool:
	if active or _joints.size() != 4 or not stage.is_visible_in_tree() or stage.arm.manual_control:
		return false
	var target_kind := "weapon" if stage.WEAPON_MODELS.has(identifier) else ("module" if kind.is_empty() else kind)
	if identifier not in REAL_MODULES and target_kind != "weapon":
		return false
	var stations := _provider(target_kind)
	if stations == null or not stations.items.has(identifier):
		return false
	category = str(stations.item_categories.get(identifier, kind))
	if category.is_empty() or (not kind.is_empty() and category != kind):
		return false
	if category == "weapon" and not stage.WEAPON_MODELS.has(identifier):
		return false
	equipment_id = identifier
	_source = stations.module_transform(identifier)
	_arm_original = stage.arm.global_transform
	_robot_yaw = stage.robot.rotation.y
	_weapon_visible = stage.weapon_socket.visible if is_instance_valid(stage.weapon_socket) else true
	var lens := stage.camera.attributes as CameraAttributesPractical
	if lens != null:
		_lens_distance = lens.dof_blur_far_distance
		_lens_transition = lens.dof_blur_far_transition
	stage.end_robot_rotation()
	stage.robot.rotation.y = stage.ROBOT_YAW
	stage.set_equipment_focus(true)
	stage.arm.begin_manual_control()
	_joint_rest.clear()
	for joint in _joints:
		_joint_rest.append(joint.transform)
	_rest = _read_angles()
	_angles = _rest
	_shoulder_offset = _joints[1].global_position - stage.arm.global_position
	_source_base = _base_for(_source.origin)
	_mount_pose = _mount_transform(identifier, category)
	# Wall hooks release toward the aisle before transport; a high vertical lift
	# would take the upper weapons beyond the mechanic's articulated reach.
	_lift_point = _source.origin + (Vector3(0, 0.12, 0.48) if category == "weapon" else Vector3(0, 0.52, 0.24))
	_approach_point = _mount_pose.origin + _front() * 0.34
	active = true
	mounted_module = false
	reached_module = false
	worked_seconds = 0.0
	elapsed = 0.0
	_phase_elapsed = 0.0
	_phase_index = 0
	phase = PHASES[0]
	_camera_started = false
	focus.set_process(false)
	_carriage.visible = true
	_gripper.visible = true
	audio.stop_all()
	audio.enter_phase(phase)
	set_process(true)
	return true


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	if not stage.is_visible_in_tree() or not stage.arm.manual_control:
		cancel(false)
		return
	if not _camera_started:
		_start_phase_camera()
		_camera_started = true
	var remaining := maxf(delta, 0.0)
	while remaining > 0.00001 and active:
		var step := minf(remaining, minf(1.0 / 30.0, float(TIMES[_phase_index]) - _phase_elapsed))
		if step <= 0.00001:
			_next_phase()
			continue
		_phase_elapsed += step
		elapsed = minf(DURATION, elapsed + step)
		remaining -= step
		_advance_motion(step)
		if active and _phase_elapsed >= float(TIMES[_phase_index]) - 0.00001:
			_next_phase()


func _advance_motion(delta: float) -> void:
	var time := clampf(_phase_elapsed / float(TIMES[_phase_index]), 0.0, 1.0)
	var weight := _ease(time)
	var old_base: Vector3 = stage.arm.global_position
	_mount_pose = _mount_transform(equipment_id, category)
	if phase == "approach":
		_drive_to_bay(time)
		var travel := Vector4(_rest.x, deg_to_rad(-15), deg_to_rad(105), deg_to_rad(0))
		var desired := _solve(_source.origin, _source_base)
		if desired.is_empty():
			cancel()
			return
		if time < 0.28:
			_apply(_interpolate_angles(_rest, travel, _ease(time / 0.28)))
		elif time < 0.76:
			_apply(travel)
		else:
			_apply(_interpolate_angles(travel, desired.angles, _ease((time - 0.76) / 0.24)))
	elif phase == "pickup":
		_point_tool(_source.origin)
		_grip(weight)
		if time >= 0.55 and _payload == null:
			_take_from_bay()
	elif phase == "lift":
		_point_tool(_source.origin.lerp(_lift_point, weight))
		_orient_payload(0.0)
	elif phase == "carry":
		_approach_point = _mount_pose.origin + _front() * 0.34
		_point_tool(_carry_point(time))
		_orient_payload(_ease(time) * 0.86)
	elif phase == "align":
		_point_tool(_approach_point.lerp(_mount_pose.origin, weight))
		_orient_payload(0.86 + weight * 0.14)
	elif phase == "work":
		_point_tool(_mount_pose.origin)
		_orient_payload(1.0)
		worked_seconds = minf(WORK_TIME, _phase_elapsed)
		stage.arm.particles.emitting = time > 0.10 and time < 0.76
		audio.set_welding(stage.arm.particles.emitting)
		_pulse.global_position = _mount_pose.origin + _front() * 0.14
		_pulse.light_energy = sin(time * PI) * (0.45 + sin(time * 51.0) * 0.10)
	elif phase == "release":
		_point_tool(_release_point.lerp(_release_point + _front() * 0.38 + Vector3.UP * 0.16, weight))
		_grip(1.0 - weight)
	elif phase == "return":
		_return_home(time)
	var travelled: float = stage.arm.global_position.distance_to(old_base)
	for wheel in _wheels:
		wheel.rotate_x(travelled / 0.115)
	if active:
		_update_camera(delta, time)
		stage.arm.manual_phase = {"approach": "RETRAIT DU MODULE", "pickup": "PRISE DU MODULE", "lift": "MODULE SAISI", "carry": "TRANSFERT DU MODULE", "align": "ALIGNEMENT DU SUPPORT", "work": "FIXATION DU MODULE", "release": "MODULE FIXÉ", "return": "RETOUR DU MÉCANICIEN"}.get(phase, "INSTALLATION")


func _next_phase() -> void:
	if phase == "pickup" and _payload == null:
		_take_from_bay()
		if _payload == null:
			cancel()
			return
	if phase == "work":
		_mount_payload()
		if not active:
			return
		_release_point = _mount_pose.origin
		stage.arm.particles.emitting = false
		_pulse.light_energy = 0.0
	_phase_index += 1
	if _phase_index >= PHASES.size():
		_finish()
		return
	_phase_elapsed = 0.0
	phase = PHASES[_phase_index]
	audio.enter_phase(phase)
	if phase == "align" and category == "weapon" and is_instance_valid(stage.weapon_socket):
		stage.weapon_socket.visible = false
	if phase == "return":
		_release_point = stage.arm.global_position
		_return_angles = _read_angles()
		_gripper.visible = false
	_start_phase_camera()


func _drive_to_bay(time: float) -> void:
	var start := _arm_original.origin
	var shoulder_home := start + _shoulder_offset
	var shoulder_bay := _source_base + _shoulder_offset
	var front_z := maxf(2.15, shoulder_bay.z + 0.45)
	var outside_x := maxf(2.40, shoulder_bay.x)
	if category == "weapon":
		# Reach the rear wall through the inside aisle, clear of the defensive
		# cabinet, then cross behind it to the pickup stance.
		outside_x = minf(outside_x, 5.80)
	var points: Array[Vector3] = [start, Vector3(outside_x, shoulder_home.y, front_z) - _shoulder_offset, Vector3(outside_x, shoulder_bay.y, shoulder_bay.z) - _shoulder_offset, _source_base]
	if shoulder_bay.z >= 0.10:
		points[2] = Vector3(shoulder_bay.x, shoulder_bay.y, front_z) - _shoulder_offset
	stage.arm.global_position = _path(points, time)


func _carry_point(time: float) -> Vector3:
	var high := minf(3.08, maxf(_lift_point.y, _approach_point.y) + 0.38)
	var points: Array[Vector3] = [_lift_point, Vector3(2.0, high, maxf(_lift_point.z + 0.40, 0.95)), Vector3(1.75, high, 1.50), _approach_point]
	# A rear bay takes the right-hand aisle before crossing to the robot.
	if _source.origin.z < -1.5:
		points[1] = Vector3(2.0, high, _lift_point.z + 0.45)
		points[2] = Vector3(2.0, high, 1.50)
	if _rear_mount():
		# Stay in the outside aisle until behind the robot, then approach the
		# rear-facing socket without taking a diagonal through the torso.
		var robot_basis: Basis = stage.robot.global_basis.orthonormalized()
		var rear_depth := minf((_approach_point - stage.robot.global_position).dot(robot_basis.z), -0.95)
		var rear_aisle: Vector3 = stage.robot.global_position + robot_basis.x * 2.0 + robot_basis.z * rear_depth
		rear_aisle.y = high
		points[2] = rear_aisle
	return _path(points, time)


func _path(points: Array[Vector3], time: float) -> Vector3:
	var segment := mini(points.size() - 2, int(time * (points.size() - 1)))
	var local := clampf(time * (points.size() - 1) - segment, 0.0, 1.0)
	return points[segment].lerp(points[segment + 1], _ease(local))


func _base_for(target: Vector3) -> Vector3:
	# Keeping the shoulder outside the body allows a compact, bounded elbow pose.
	var reach := lerpf(1.86, 1.40, clampf((target.y - 0.40) / 2.70, 0.0, 1.0))
	if category == "weapon":
		# Bring the wheeled shoulder closer to the upper wall hooks.
		# The lower hooks also keep the carriage entirely inside the right wall.
		reach = lerpf(minf(reach, 1.15), 0.75, clampf((target.y - 2.20) / 1.30, 0.0, 1.0))
	var side := Vector3.RIGHT
	var facing := Vector3.BACK
	if equipment_id in REAL_MODULES and phase in ["carry", "align", "work", "release"]:
		side = stage.robot.global_basis.x.normalized()
		var surface := _front()
		surface.y = 0.0
		if surface.length_squared() > 0.01:
			surface = surface.normalized()
			# Pickup retains the bay stance; the base turns continuously during
			# carry before settling on the socket's exposed side.
			var weight := _ease(_phase_elapsed / float(TIMES[_phase_index])) if phase == "carry" else 1.0
			facing = facing.lerp(surface, weight)
	var shoulder := target + side * reach + facing * 0.34
	shoulder.y = _arm_original.origin.y + _shoulder_offset.y
	return shoulder - _shoulder_offset


func _point_tool(target: Vector3) -> void:
	var base := _base_for(target)
	var solution := _solve(target, base)
	if solution.is_empty():
		cancel()
		return
	stage.arm.global_position = base
	_apply(solution.angles)


func _solve(target: Vector3, base: Vector3) -> Dictionary:
	var offset := target - (base + _shoulder_offset)
	var yaw := atan2(offset.z, -offset.x)
	var best := {}
	var cost := INF
	for degrees in range(80, 141, 2):
		var end := deg_to_rad(float(degrees))
		var horizontal := Vector2(offset.x, offset.z).length() - _lengths.z * sin(end)
		var vertical := offset.y - _lengths.z * cos(end)
		var cosine := (horizontal * horizontal + vertical * vertical - _lengths.x * _lengths.x - _lengths.y * _lengths.y) / (2.0 * _lengths.x * _lengths.y)
		if cosine < -1.0 or cosine > 1.0:
			continue
		var elbow := acos(cosine)
		var shoulder := atan2(horizontal, vertical) - atan2(_lengths.y * sin(elbow), _lengths.x + _lengths.y * cos(elbow))
		var angles := Vector4(yaw, shoulder, elbow, end - shoulder - elbow)
		var valid := true
		for index in 4:
			valid = valid and is_finite(angles[index]) and angles[index] >= deg_to_rad(LIMITS[index].x) and angles[index] <= deg_to_rad(LIMITS[index].y)
		if not valid:
			continue
		var score := angles.distance_squared_to(_angles) + absf(float(degrees) - 110.0) * 0.0005
		if score < cost:
			best = {"angles": angles}
			cost = score
	return best


func _read_angles() -> Vector4:
	return Vector4(_joints[0].rotation.y, _joints[1].rotation.z, _joints[2].rotation.z, _joints[3].rotation.z)


func _apply(value: Vector4) -> void:
	_angles = value
	_joints[0].rotation.y = value.x
	_joints[1].rotation.z = value.y
	_joints[2].rotation.z = value.z
	_joints[3].rotation.z = value.w


func _interpolate_angles(from: Vector4, to: Vector4, weight: float) -> Vector4:
	return Vector4(lerp_angle(from.x, to.x, weight), lerp_angle(from.y, to.y, weight), lerp_angle(from.z, to.z, weight), lerp_angle(from.w, to.w, weight))


func _grip(weight: float) -> void:
	for index in _fingers.size():
		var point := _finger_rest[index]
		point.x *= lerpf(1.20, 0.68, weight)
		_fingers[index].position = point
	for index in _clamp_jaws.size():
		_clamp_jaws[index].position.x = (-1.0 if index == 0 else 1.0) * lerpf(0.31, 0.245, weight)


func _take_from_bay() -> void:
	if _payload != null or stage.arm.contact.global_position.distance_to(_source.origin) > 0.055:
		return
	_payload = _provider().create_payload(equipment_id)
	if _payload == null:
		return
	stage.world.add_child(_payload)
	_payload.global_transform = _source
	_gripper.global_basis = _source.basis.orthonormalized()
	_gripper.position = Vector3.ZERO
	_payload.reparent(_gripper, true)
	_provider().set_item_visible(equipment_id, false)
	reached_module = true
	audio.play("pickup")


func _orient_payload(weight: float) -> void:
	if _payload == null:
		return
	# The visible swivel turns its jaws and the rigidly held cartridge together.
	_gripper.global_basis = _source.basis.orthonormalized().slerp(_mount_pose.basis.orthonormalized(), weight)
	_gripper.position = Vector3.ZERO
	if equipment_id in REAL_MODULES or category == "weapon":
		# Shelf copies fit their bays; ease to the installed dimensions only at
		# alignment, after the rigid carry has completed.
		var fit_weight := _ease(clampf((weight - 0.86) / 0.14, 0.0, 1.0))
		_payload.scale = _source.basis.get_scale().lerp(_mount_pose.basis.get_scale(), fit_weight)


func _mount_transform(identifier: String, kind: String) -> Transform3D:
	if identifier in REAL_MODULES and stage.module_visuals != null:
		return stage.module_visuals.module_transform(identifier)
	if kind == "weapon":
		return stage.weapon_mount_transform(identifier)
	return Transform3D.IDENTITY


func _provider(kind: String = "") -> Node3D:
	var selected_kind := category if kind.is_empty() else kind
	return stage.weapon_rack if selected_kind == "weapon" else stage.module_stations


func _mount_payload() -> void:
	if _payload == null or mounted_module:
		return
	if stage.arm.contact.global_position.distance_to(_mount_pose.origin) > 0.055:
		cancel()
		return
	_purge_installed()
	_payload.free()
	_payload = null
	mounted_module = true
	mounted.emit(category, equipment_id)
	audio.play("lock")


func sync_loadout(_loadout: Dictionary) -> void:
	_purge_installed()


func _purge_installed() -> void:
	for holder in _installed.values():
		if is_instance_valid(holder):
			holder.free()
	_installed.clear()


func _front() -> Vector3:
	if equipment_id in REAL_MODULES:
		return _mount_pose.basis.z.normalized()
	return stage.robot.global_basis.orthonormalized() * Vector3.BACK


func _rear_mount() -> bool:
	return equipment_id in REAL_MODULES and _front().dot(stage.robot.global_basis.z.normalized()) < -0.25


func _mount_view_direction() -> Vector3:
	if equipment_id in REAL_MODULES:
		return (_front() + stage.robot.global_basis.x.normalized() * 0.30 + Vector3.UP * 0.18).normalized()
	return Vector3(0.38, 0.13, 1).normalized()


func _start_phase_camera() -> void:
	_camera_from = stage.camera.global_transform
	_camera_fov_from = stage.camera.fov
	var bounds := AABB(_source.origin - Vector3(0.65, 0.45, 0.40), Vector3(1.30, 0.90, 0.80))
	var side: float = {"weapon": -0.55, "offensive": -0.40, "defensive": 0.90, "passive": -0.65, "mobility": 0.65}.get(category, 0.26)
	var direction := Vector3(side, 0.60 if category == "passive" else 0.18, 1).normalized()
	_phase_fov = 37.0
	if phase in ["carry", "lift"]:
		bounds = bounds.expand(_mount_pose.origin).grow(0.30)
		direction = Vector3(0.42, 0.19, 1).normalized()
		if phase == "carry" and equipment_id in REAL_MODULES:
			direction = _mount_view_direction()
		_phase_fov = 39.0
	elif phase in ["align", "work", "release"]:
		bounds = AABB(_mount_pose.origin - Vector3(0.58, 0.48, 0.40), Vector3(1.16, 0.96, 0.80))
		if category == "weapon":
			bounds = (_mount_pose * stage.weapon_geometry_bounds(equipment_id)).grow(0.22)
		direction = _mount_view_direction()
		_phase_fov = 34.0
	elif phase == "return":
		bounds = _provider().bounds(category).grow(0.20)
		direction = Vector3(side, 0.60 if category == "passive" else 0.12, 1).normalized()
		_phase_fov = 36.0
	_phase_camera = focus.cinematic_frame(bounds, direction, _phase_fov)


func _update_camera(delta: float, time: float) -> void:
	var blend := _ease(minf(_phase_elapsed / minf(float(TIMES[_phase_index]), 0.72), 1.0))
	if phase == "carry":
		var tip: Vector3 = stage.arm.contact.global_position
		var bounds := AABB(tip - Vector3(0.75, 0.65, 0.60), Vector3(1.50, 1.30, 1.20)).expand(_mount_pose.origin).grow(0.18)
		var direction := _mount_view_direction() if equipment_id in REAL_MODULES else Vector3(0.38, 0.17, 1).normalized()
		var tracking: Transform3D = focus.cinematic_frame(bounds, direction, _phase_fov)
		var desired := _camera_from.interpolate_with(tracking, blend)
		stage.camera.global_transform = stage.camera.global_transform.interpolate_with(desired, 1.0 - exp(-delta * 9.0))
	else:
		stage.camera.global_transform = _camera_from.interpolate_with(_phase_camera, blend)
	stage.camera.fov = lerpf(_camera_fov_from, _phase_fov, blend)
	if phase == "work":
		stage.camera.global_position -= stage.camera.global_basis.z * sin(time * PI) * 0.035
	var lens := stage.camera.attributes as CameraAttributesPractical
	if lens != null:
		var subject: Vector3 = _source.origin
		if phase in ["lift", "carry"]:
			subject = stage.arm.contact.global_position
		elif phase in ["align", "work", "release"]:
			subject = _mount_pose.origin
		elif phase == "return":
			subject = _provider().anchor(category)
		lens.dof_blur_far_distance = stage.camera.global_position.distance_to(subject) + 2.4
		lens.dof_blur_far_transition = 3.0


func _return_home(time: float) -> void:
	stage.arm.global_position = _release_point.lerp(_arm_original.origin, _ease(time))
	_apply(_interpolate_angles(_return_angles, _rest, _ease(time)))


func complete_immediately() -> void:
	# Traverse the same contacts and signals even when the player skips the shot.
	if not active:
		return
	var already_mounted := mounted_module
	audio.stop_all()
	audio.suppressed = true
	var steps := 0
	while active and steps < 260:
		advance(1.0 / 30.0)
		steps += 1
	audio.suppressed = false
	if mounted_module and not active and not already_mounted:
		audio.play("lock")


func finish_now() -> void:
	complete_immediately()


func cancel(overview: bool = true) -> void:
	if not active:
		return
	active = false
	if is_instance_valid(_payload):
		_payload.queue_free()
	_payload = null
	_restore(overview)
	cancelled.emit()


func _forced_cancel() -> void:
	if active and not _restoring:
		cancel()


func _finish() -> void:
	if not mounted_module:
		cancel()
		return
	active = false
	_restore(true)
	completed.emit(equipment_id)


func _restore(overview: bool) -> void:
	_restoring = true
	audio.stop_all()
	_provider().set_item_visible(equipment_id, true)
	if category == "weapon" and not mounted_module and is_instance_valid(stage.weapon_socket):
		stage.weapon_socket.visible = _weapon_visible
	stage.arm.end_manual_control()
	stage.arm.global_transform = _arm_original
	for index in _joints.size():
		if index < _joint_rest.size():
			_joints[index].transform = _joint_rest[index]
	for index in _fingers.size():
		_fingers[index].position = _finger_rest[index]
	stage.robot.rotation.y = _robot_yaw
	_carriage.visible = false
	_gripper.visible = false
	_pulse.light_energy = 0.0
	var lens := stage.camera.attributes as CameraAttributesPractical
	if lens != null:
		lens.dof_blur_far_distance = _lens_distance
		lens.dof_blur_far_transition = _lens_transition
	phase = ""
	focus.set_process(stage.is_visible_in_tree())
	if overview and stage.is_visible_in_tree():
		focus.show_station(category)
	_restoring = false
	set_process(false)


func _ease(value: float) -> float:
	var time := clampf(value, 0.0, 1.0)
	return time * time * (3.0 - 2.0 * time)


func _build_carriage() -> void:
	_carriage = Node3D.new()
	_carriage.name = "MechanicServiceCarriage"
	stage.arm.add_child(_carriage)
	var base: Vector3 = stage.arm.to_local(_joints[0].global_position)
	_carriage.position = Vector3(base.x, 0.22, base.z)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#485356")
	steel.metallic = 0.78
	steel.roughness = 0.38
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("#161b1c")
	rubber.roughness = 0.88
	var platform := BoxMesh.new()
	platform.size = Vector3(0.94, 0.14, 0.84)
	platform.material = steel
	var body := MeshInstance3D.new()
	body.mesh = platform
	body.position.y = 0.14
	_carriage.add_child(body)
	for x in [-0.45, 0.45]:
		for z in [-0.28, 0.28]:
			var wheel := MeshInstance3D.new()
			var tire := CylinderMesh.new()
			tire.top_radius = 0.115
			tire.bottom_radius = 0.115
			tire.height = 0.10
			tire.radial_segments = 16
			tire.material = rubber
			wheel.mesh = tire
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(x, 0.17, z)
			_carriage.add_child(wheel)
			_wheels.append(wheel)
	_carriage.visible = false
	_pulse = OmniLight3D.new()
	_pulse.name = "ModuleFixingPulse"
	_pulse.light_color = Color("#ffc67c")
	_pulse.omni_range = 0.85
	_pulse.light_energy = 0.0
	stage.world.add_child(_pulse)
	_build_gripper(steel)


func _build_gripper(steel: StandardMaterial3D) -> void:
	_gripper = Node3D.new()
	_gripper.name = "CartridgeSwivelClamp"
	stage.arm.contact.add_child(_gripper)
	var bearing := TorusMesh.new()
	bearing.inner_radius = 0.073
	bearing.outer_radius = 0.103
	bearing.rings = 24
	bearing.ring_segments = 8
	bearing.material = steel
	var ring := MeshInstance3D.new()
	ring.mesh = bearing
	ring.rotation.x = PI * 0.5
	ring.position.z = -0.17
	_gripper.add_child(ring)
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.54, 0.045, 0.04)
	bridge.material = steel
	var crossbar := MeshInstance3D.new()
	crossbar.mesh = bridge
	crossbar.position.z = -0.17
	_gripper.add_child(crossbar)
	for side in [-1.0, 1.0]:
		var jaw := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(0.025, 0.10, 0.24)
		shape.material = steel
		jaw.mesh = shape
		jaw.position = Vector3(side * 0.31, 0, -0.065)
		_gripper.add_child(jaw)
		_clamp_jaws.append(jaw)
	_gripper.visible = false


func _exit_tree() -> void:
	if active and is_instance_valid(stage):
		cancel(false)
	if is_instance_valid(_carriage):
		_carriage.queue_free()
	if is_instance_valid(_pulse):
		_pulse.queue_free()
	if is_instance_valid(_gripper):
		_gripper.queue_free()
