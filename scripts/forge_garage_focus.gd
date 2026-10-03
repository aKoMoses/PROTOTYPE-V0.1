extends Node

## Inspection camera and short equipment cues; no combat state is changed.
const TRANSITION_TIME := 0.52
const EFFECT_TIME := 1.65
const GARAGE_ORBIT_PERIOD := 18.0
const GARAGE_ORBIT_AMPLITUDE := 0.10
const GARAGE_ORBIT_RESUME := 1.5
const COLORS := {
	"weapon": Color("#77e5ff"), "offensive": Color("#ffac52"),
	"defensive": Color("#68bfff"), "mobility": Color("#ffcf65"),
	"passive": Color("#bd9aff"),
}
const ZONES := {
	"modulo_drone": "shoulder", "rocket_basket": "shoulder", "javelin": "arm", "fulguro_punch": "arm", "pelto_smash": "arm",
	"magnetic_field": "torso", "static_shield": "torso",
	"pyro_boots": "legs", "bio_injector": "core", "baroud": "core", "omnivamp": "core",
}

var stage
var category := "robot"
var equipment_id := ""
var zone := "robot"
var effect_elapsed := EFFECT_TIME
var _picker: Control
var _ui: Control
var _base: Transform3D
var _base_fov := 31.0
var _design_fov := 31.0
var _authored_fov := 31.0
var _framed_chassis := ""
var _view_direction := Vector3(0.006, 0.139, 0.990).normalized()
var _from: Transform3D
var _transition := 1.0
var _bones: Dictionary = {}
var _effects: Node3D
var _holders: Array[Node3D] = []
var _materials: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _light: OmniLight3D
var _chassis_scale := 1.0
var station_category := ""
var _from_fov := 31.0
var _target_fov := 31.0
var _via_garage := false
var _garage_orbit_phase := 0.0
var _garage_orbit_speed := 0.0
var _station_hovered := false
var _catalog_bounds := AABB()


func configure(garage_stage: Node, picker: Control, interface: Control) -> void:
	stage = garage_stage
	_picker = picker
	_ui = interface
	_base = stage.camera.global_transform
	_base_fov = stage.camera.fov
	_design_fov = _base_fov
	_authored_fov = _base_fov
	_from = _base
	_from_fov = _base_fov
	_target_fov = _base_fov
	_chassis_scale = stage.robot.scale.x
	for index in stage.skeleton.get_bone_count():
		var bone: String = stage.skeleton.get_bone_name(index)
		_bones[bone.to_lower().trim_prefix("mixamorig_").trim_prefix("mixamorig:")] = index


func _ready() -> void:
	process_priority = 1
	_effects = Node3D.new()
	_effects.name = "EquipmentInspectionEffects"
	stage.world.add_child(_effects)
	stage.visibility_changed.connect(_sync_visibility)
	stage.resized.connect(_reframe)
	_picker.visibility_changed.connect(_reframe)
	_sync_visibility()


func _exit_tree() -> void:
	if is_instance_valid(_effects):
		_effects.queue_free()


func _sync_visibility() -> void:
	var active: bool = stage.is_visible_in_tree()
	set_process(active)
	if not active:
		show_overview(false)


func _reframe() -> void:
	if zone != "robot":
		_from = stage.camera.global_transform
		_transition = 0.0


func fit_layout() -> void:
	# Keep the model's size relative to the letterboxed interface at narrow ratios.
	_framed_chassis = stage.chassis_id
	_design_fov = _authored_fov + (6.0 if _framed_chassis == "puissant" else 0.0)
	var design_height := _ui.size.y * _ui.scale.y
	_base_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_design_fov * 0.5)) * stage.size.y / maxf(design_height, 1.0)))
	if zone not in ["garage", "station", "catalog"]:
		_target_fov = _base_fov
	if zone not in ["garage", "station", "catalog"] and (not stage._equipment_focused or zone != "robot"):
		stage.camera.fov = _base_fov
	_reframe()


func show_equipment(kind: String, identifier: String, play_effect: bool = true) -> void:
	_via_garage = false
	station_category = ""
	_from_fov = stage.camera.fov
	_target_fov = _base_fov
	if kind == "robot":
		show_overview()
		return
	if not COLORS.has(kind):
		return
	category = kind
	equipment_id = identifier
	zone = "weapon" if kind == "weapon" else str(ZONES.get(identifier, "core"))
	_from = stage.camera.global_transform
	_transition = 0.0
	stage.set_equipment_focus(true)
	_clear_effects()
	effect_elapsed = 0.0 if play_effect else EFFECT_TIME
	if play_effect:
		_build_effects()


func show_overview(animated: bool = true) -> void:
	_via_garage = false
	station_category = ""
	_from_fov = stage.camera.fov
	_target_fov = _base_fov
	category = "robot"
	equipment_id = ""
	zone = "robot"
	_from = stage.camera.global_transform
	_transition = 0.0 if animated else 1.0
	stage.set_equipment_focus(false)
	_clear_effects()
	effect_elapsed = EFFECT_TIME
	if not animated:
		stage.camera.global_transform = _base
		stage.camera.fov = _base_fov


func show_garage(animated: bool = true) -> void:
	_via_garage = false
	category = "robot"
	equipment_id = ""
	station_category = ""
	zone = "garage"
	_garage_orbit_phase = 0.0
	_garage_orbit_speed = 0.0
	_station_hovered = false
	_from = stage.camera.global_transform
	_from_fov = stage.camera.fov
	_target_fov = 40.0
	_transition = 0.0 if animated else 1.0
	stage.set_equipment_focus(false)
	_clear_effects()
	effect_elapsed = EFFECT_TIME
	if not animated:
		stage.camera.global_transform = _garage_transform()
		stage.camera.fov = _target_fov


func set_station_hovered(value: bool) -> void:
	_station_hovered = value
	if value:
		_garage_orbit_speed = 0.0


func _garage_orbit(base: Transform3D, delta: float, settled: bool) -> Transform3D:
	# Freeze the phase at its current pose while the player aims or drags.
	# Ramp only its speed on release, so resuming never recentres the camera.
	var paused: bool = not settled or _station_hovered or stage._rotating_robot or stage.arm.active or not stage.is_visible_in_tree()
	if paused:
		_garage_orbit_speed = 0.0
	else:
		var step := minf(delta, 0.1)
		_garage_orbit_speed = move_toward(_garage_orbit_speed, 1.0, step / GARAGE_ORBIT_RESUME)
		_garage_orbit_phase = fposmod(_garage_orbit_phase + step * _garage_orbit_speed * TAU / GARAGE_ORBIT_PERIOD, TAU)
	var pivot: Vector3 = stage.robot.global_position + Vector3(0, 1.35, 0)
	var radial := base.origin - pivot
	var radius := maxf(Vector2(radial.x, radial.z).length(), 1.0)
	var angle := sin(_garage_orbit_phase) * GARAGE_ORBIT_AMPLITUDE / radius
	var orbit := Basis(Vector3.UP, angle)
	# Rotate both pose and aim around the same pivot: no zoom or vertical bob.
	return Transform3D(orbit * base.basis, pivot + orbit * radial)


func show_station(kind: String, animated: bool = true) -> void:
	var provider := _station_provider(kind)
	if provider == null or not COLORS.has(kind):
		return
	_via_garage = animated and zone == "station" and station_category != kind
	category = kind
	equipment_id = ""
	station_category = kind
	zone = "station"
	_from = stage.camera.global_transform
	_from_fov = stage.camera.fov
	_target_fov = 36.0
	_transition = 0.0 if animated else 1.0
	stage.set_equipment_focus(true)
	if stage.module_stations != null:
		stage.module_stations.highlight(kind)
	if stage.weapon_rack != null:
		stage.weapon_rack.highlight(kind)
	_clear_effects()
	effect_elapsed = EFFECT_TIME
	if not animated:
		stage.camera.global_transform = _station_transform()
		stage.camera.fov = _target_fov


func _garage_transform() -> Transform3D:
	if bool(_ui.get_meta("garage_hero", false)):
		# A yaw-independent envelope prevents reframing while dragging the robot.
		var local: AABB = stage._robot_pick_bounds
		var radius := 0.0
		var bottom := INF
		var top := -INF
		for corner in 8:
			var point: Vector3 = local.get_endpoint(corner) * stage.robot.scale
			radius = maxf(radius, Vector2(point.x, point.z).length())
			bottom = minf(bottom, point.y)
			top = maxf(top, point.y)
		var hero := AABB(stage.robot.global_position + Vector3(-radius, bottom, -radius), Vector3(radius * 2, top - bottom, radius * 2))
		var compact: bool = _ui.get_meta("garage_hero_compact", false)
		hero = hero.merge(AABB(Vector3(-1.6, 0, -1.6), Vector3(3.2, 3.3, 3.2)) if compact else AABB(Vector3(-2.2, 0, -1.7), Vector3(5.0, 3.7, 4.2)))
		return cinematic_frame(hero, Vector3(-0.06, 0.28, 1.0), 40.0)
	var bounds := AABB(Vector3(-4.35, 0.1, -3.6), Vector3(8.65, 3.5, 6.0))
	if stage.weapon_rack != null:
		bounds = bounds.merge(stage.weapon_rack.bounds("weapon").grow(0.22))
	if stage.module_stations != null:
		for category in stage.module_stations.CATEGORIES:
			bounds = bounds.merge(stage.module_stations.bounds(category).grow(0.35))
	return cinematic_frame(bounds, Vector3(-0.06, 0.32, 1.0), 40.0)


func _station_provider(kind: String) -> Node3D:
	return stage.weapon_rack if kind == "weapon" else stage.module_stations


func _station_transform() -> Transform3D:
	var provider := _station_provider(station_category)
	if provider == null:
		return _garage_transform()
	var bounds: AABB = provider.bounds(station_category).grow(0.22)
	# Observe the bays from the central aisle. The former outward angles put
	# the camera behind the side walls after the bays were moved apart.
	var direction := Vector3(float({"weapon": -0.55, "offensive": -0.05, "defensive": -0.55, "passive": 0.45, "mobility": -0.45}.get(station_category, 0.0)), 0.38, 1.0)
	return cinematic_frame(bounds, direction, _target_fov)


func cinematic_frame(bounds: AABB, direction: Vector3, fov: float = 36.0) -> Transform3D:
	var target := bounds.get_center()
	direction = direction.normalized()
	var basis := Basis.looking_at(-direction, Vector3.UP)
	var rect := frame_rect()
	var control_size: Vector2 = stage.size
	var fraction := rect.size / control_size
	var aspect := float(stage.viewport.size.x) / maxf(stage.viewport.size.y, 1.0)
	var tangent := tan(deg_to_rad(fov * 0.5))
	var distance := 2.5
	for corner in 8:
		var relative := bounds.get_endpoint(corner) - target
		var depth := relative.dot(direction)
		distance = maxf(distance, absf(relative.dot(basis.x)) / maxf(tangent * aspect * fraction.x * 0.9, 0.01) + depth)
		distance = maxf(distance, absf(relative.dot(basis.y)) / maxf(tangent * fraction.y * 0.9, 0.01) + depth)
	var center := rect.get_center() / control_size
	var position := target + direction * distance
	position -= basis.x * ((center.x - 0.5) * 2.0 * tangent * distance * aspect)
	position += basis.y * ((center.y - 0.5) * 2.0 * tangent * distance)
	return Transform3D(basis, position)


func preview_equipment(kind: String, identifier: String) -> void:
	# The catalog keeps the whole robot visible while retaining the local cue.
	show_overview(false)
	if kind == "robot" or not COLORS.has(kind):
		return
	category = kind
	equipment_id = identifier
	effect_elapsed = 0.0
	_build_effects()


func show_catalog_preview(kind: String, identifier: String, bounds: AABB) -> void:
	_via_garage = false
	category = kind
	equipment_id = identifier
	station_category = kind if kind != "robot" else ""
	_catalog_bounds = bounds
	zone = "catalog"
	_from = stage.camera.global_transform
	_from_fov = stage.camera.fov
	_target_fov = 36.0
	_transition = 0.0
	stage.set_equipment_focus(true)
	_clear_effects()
	effect_elapsed = EFFECT_TIME


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _framed_chassis != stage.chassis_id:
		_bones.clear()
		for index in stage.skeleton.get_bone_count():
			var bone: String = stage.skeleton.get_bone_name(index)
			_bones[bone.to_lower().trim_prefix("mixamorig_").trim_prefix("mixamorig:")] = index
		fit_layout()
	var settled := _transition >= 1.0
	var duration := 0.9 if zone in ["garage", "station"] else TRANSITION_TIME
	_transition = minf(_transition + delta / duration, 1.0)
	var weight := _transition * _transition * _transition * (_transition * (_transition * 6.0 - 15.0) + 10.0)
	var desired := _base
	if zone == "garage":
		desired = _garage_orbit(_garage_transform(), delta, settled)
	elif zone == "station":
		desired = _station_transform()
	elif zone == "catalog":
		desired = cinematic_frame(_catalog_bounds, Vector3(0.12, 0.19, 1), _target_fov)
	elif zone != "robot":
		desired = _focused_transform()
	if _via_garage and zone == "station":
		# Pull back into the open aisle before travelling to another bay,
		# rather than cutting across the workbench, cases and robot.
		var waypoint := _base
		var leg := clampf(_transition * 2.0 if _transition < 0.5 else (_transition - 0.5) * 2.0, 0.0, 1.0)
		leg = leg * leg * (3.0 - 2.0 * leg)
		stage.camera.global_transform = _from.interpolate_with(waypoint, leg) if _transition < 0.5 else waypoint.interpolate_with(desired, leg)
	else:
		stage.camera.global_transform = _from.interpolate_with(desired, weight)
	stage.camera.fov = lerpf(_from_fov, _target_fov, weight)
	var lens := stage.camera.attributes as CameraAttributesPractical
	if lens != null:
		lens.dof_blur_far_enabled = zone != "garage"
		var target := Vector3(0, 1.7, 0)
		if zone == "station":
			var provider := _station_provider(station_category)
			if provider != null:
				target = provider.bounds(station_category).get_center()
		elif zone == "catalog":
			target = _catalog_bounds.get_center()
		elif zone != "robot" and zone != "garage":
			target = region_bounds().get_center()
		lens.dof_blur_far_distance = stage.camera.global_position.distance_to(target) + 2.0
	effect_elapsed = minf(effect_elapsed + delta, EFFECT_TIME)
	_update_effects()


func anchor(bone: String, offset: Vector3 = Vector3.ZERO) -> Vector3:
	var rotation: Basis = stage.robot.global_basis.orthonormalized()
	var index: int = int(_bones.get(bone.to_lower(), -1))
	if index < 0:
		return stage.robot.global_position + rotation * (Vector3(0, 1.8, 0) + offset)
	var pose: Transform3D = stage.skeleton.global_transform * stage.skeleton.get_bone_global_pose(index)
	return pose.origin + rotation * offset * _scale_factor()


func _scale_factor() -> float:
	return float(stage.robot.scale.x) / maxf(_chassis_scale, 0.001)


func frame_rect() -> Rect2:
	if _ui.has_meta("preview_rect"):
		var design: Rect2 = _ui.get_meta("preview_rect")
		return Rect2(_ui.position + design.position * _ui.scale, design.size * _ui.scale)
	var left := 606.0 if _picker.visible else 280.0
	var design := Rect2(Vector2(left, 105), Vector2(955 - left, 510))
	return Rect2(_ui.position + design.position * _ui.scale, design.size * _ui.scale)


func region_bounds() -> AABB:
	var factor := _scale_factor()
	if stage.module_visuals != null and stage.module_visuals.has_model(equipment_id) and zone != "robot":
		# Frame the installed housing and enough neighbouring armor to locate it.
		return stage.module_visuals.module_bounds(equipment_id).grow(0.22 * factor)
	if zone == "weapon" and stage.weapon_socket != null:
		var bounds: AABB = stage.weapon_socket.global_transform * stage.call("_bounds", stage.weapon_socket)
		return bounds.expand(anchor("RightHand")).grow(0.12 * factor)
	if zone == "legs":
		var bounds := AABB(anchor("LeftLeg"), Vector3.ZERO)
		for bone in ["RightLeg", "LeftFoot", "RightFoot"]:
			bounds = bounds.expand(anchor(bone))
		return bounds.grow(0.24 * factor)
	if zone == "arm":
		var bounds := AABB(anchor("RightArm"), Vector3.ZERO)
		return bounds.expand(anchor("RightHand", Vector3(0, -0.08, 0))).grow(0.24 * factor)
	if zone == "shoulder":
		var extent := Vector3(1.05, 1.02, 0.80) * factor
		return AABB(anchor("RightShoulder") - extent * 0.5, extent)
	var center := anchor("Spine1", Vector3(0, 0.01, 0.31)) if zone == "core" else anchor("Spine", Vector3(0, -0.08, 0.27))
	var extent := (Vector3(1.50, 1.85, 0.95) if zone == "torso" else Vector3(1.05, 1.00, 0.75)) * factor
	return AABB(center - extent * 0.5, extent)


func _focused_transform() -> Transform3D:
	var bounds := region_bounds()
	var target := bounds.get_center()
	var direction := _view_direction
	if stage.module_visuals != null and stage.module_visuals.has_model(equipment_id):
		var module_pose: Transform3D = stage.module_visuals.module_transform(equipment_id)
		# Inspect the authored face, including heel exhausts and the rear reactor.
		direction = (module_pose.basis.z.normalized() + Vector3.UP * 0.14 + stage.robot.global_basis.x.normalized() * 0.12).normalized()
	var basis := Basis.looking_at(-direction, Vector3.UP)
	var rect := frame_rect()
	var viewport_size := Vector2(stage.viewport.size)
	var control_size: Vector2 = stage.size
	var fraction := rect.size / control_size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var tangent := tan(deg_to_rad(_base_fov * 0.5))
	var distance := 2.25
	# Fit all corners in the actual free area, including wide/rotated weapons.
	for corner in 8:
		var relative := bounds.get_endpoint(corner) - target
		var depth := relative.dot(direction)
		distance = maxf(distance, absf(relative.dot(basis.x)) / maxf(tangent * aspect * fraction.x * 0.88, 0.01) + depth)
		distance = maxf(distance, absf(relative.dot(basis.y)) / maxf(tangent * fraction.y * 0.88, 0.01) + depth)
	var center := rect.get_center() / control_size
	var position := target + direction * distance
	position -= basis.x * ((center.x - 0.5) * 2.0 * tangent * distance * aspect)
	position += basis.y * ((center.y - 0.5) * 2.0 * tangent * distance)
	return Transform3D(basis, position)


func _clear_effects() -> void:
	_holders.clear()
	_materials.clear()
	_base_alphas.clear()
	_light = null
	if _effects == null:
		return
	_effects.visible = false
	for child in _effects.get_children():
		child.free()


func _holder(bone: String, offset: Vector3, orbit: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.set_meta("bone", bone)
	holder.set_meta("offset", offset)
	holder.set_meta("orbit", orbit)
	_effects.add_child(holder)
	_holders.append(holder)
	return holder


func _material(color: Color, alpha: float = 0.7) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	_materials.append(material)
	_base_alphas.append(alpha)
	return material


func _mesh(parent: Node3D, shape: Mesh, color: Color, alpha: float = 0.7) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = _material(color, alpha)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _ring(parent: Node3D, radius: float, color: Color, vertical: bool = true) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.012
	mesh.outer_radius = radius + 0.012
	mesh.rings = 32
	mesh.ring_segments = 8
	var ring := _mesh(parent, mesh, color)
	if vertical:
		ring.rotation.x = PI * 0.5


func _orb(parent: Node3D, radius: float, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	_mesh(parent, mesh, color)


func _build_effects() -> void:
	var color: Color = COLORS[category]
	var cue_zone := "weapon" if category == "weapon" else str(ZONES.get(equipment_id, "core"))
	if equipment_id == "bio_injector":
		color = Color("#85ffc0")
	elif equipment_id == "baroud":
		color = Color("#ff745d")
	if stage.module_visuals != null and stage.module_visuals.has_model(equipment_id):
		_build_module_effects(color)
		_update_effects()
		return
	var bone := "RightFoot" if cue_zone == "legs" else ("RightHand" if cue_zone in ["weapon", "arm"] else ("RightShoulder" if cue_zone == "shoulder" else ("Spine1" if cue_zone == "core" else "Spine")))
	var offset := Vector3(0, 0.01, 0.34) if cue_zone == "core" else (Vector3(0, -0.08, 0.34) if bone == "Spine" else Vector3(0, -0.05, 0.19))
	var center := _holder(bone, offset)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 1.1
	_light.light_energy = 0.0
	center.add_child(_light)
	if cue_zone == "legs":
		for foot in ["LeftFoot", "RightFoot"]:
			var side := 1.0 if foot == "LeftFoot" else -1.0
			var boot := _holder(foot, Vector3(side * 0.15, -0.05, 0.36))
			_ring(boot, 0.18, color, false)
			var flame := CylinderMesh.new()
			flame.top_radius = 0.005
			flame.bottom_radius = 0.07
			flame.height = 0.26
			flame.radial_segments = 12
			_mesh(boot, flame, Color("#ffad5a"), 0.45).position.y = 0.06
			_orb(boot, 0.065, Color("#fff3c3"))
			for plume_index in 3:
				var plume := _holder(foot, Vector3(side * 0.15, -0.05, 0.52))
				plume.set_meta("plume_phase", float(plume_index) / 3.0)
				_orb(plume, 0.025, color)
	elif equipment_id == "magnetic_field":
		var field := _holder("Spine", Vector3(0, 0, 0.62))
		var plate := QuadMesh.new()
		plate.size = Vector2(1.25, 1.40)
		_mesh(field, plate, color, 0.075)
		for edge in [-1.0, 1.0]:
			var line := BoxMesh.new()
			line.size = Vector3(0.018, 1.40, 0.018)
			_mesh(field, line, color).position.x = edge * 0.625
		for row in 6:
			var line := BoxMesh.new()
			line.size = Vector3(1.25, 0.009, 0.009)
			_mesh(field, line, color, 0.35).position.y = -0.58 + row * 0.23
	elif equipment_id == "static_shield":
		var mesh := SphereMesh.new()
		mesh.radius = 0.73
		mesh.height = 2.0
		mesh.radial_segments = 32
		mesh.rings = 16
		var shell := _holder("Spine", Vector3(0, 0, 0.1))
		_mesh(shell, mesh, color, 0.075)
		_ring(center, 0.61, color)
	elif cue_zone == "shoulder":
		_ring(center, 0.25, color)
		for satellite in 4:
			var point := _holder(bone, Vector3(0, 0, 0.26), satellite * TAU / 4.0 + 0.01)
			_orb(point, 0.04, color)
	else:
		_ring(center, 0.23 if cue_zone == "core" else 0.17, color)
		for point_index in 6:
			var point := _holder(bone, offset, point_index * TAU / 6.0 + 0.01)
			_orb(point, 0.022, color)
	_update_effects()


func _build_module_effects(color: Color) -> void:
	var modules = stage.module_visuals
	for key in modules.mounts:
		if str(modules.MOUNT_IDS[key]) != equipment_id:
			continue
		var mount := modules.mounts[key] as Node3D
		var holder := _holder("", Vector3.ZERO)
		holder.set_meta("module_mount", key)
		var bounds := AABB()
		var first := true
		for child in mount.get_children():
			if child is MeshInstance3D:
				bounds = child.mesh.get_aabb() if first else bounds.merge(child.mesh.get_aabb())
				first = false
		var radius := clampf(maxf(bounds.size.x, bounds.size.y) * 0.22, 0.016, 0.045)
		var halo := TorusMesh.new()
		halo.inner_radius = radius - 0.002
		halo.outer_radius = radius + 0.002
		halo.rings = 24
		halo.ring_segments = 6
		var ring := _mesh(holder, halo, color, 0.35)
		ring.rotation.x = PI * 0.5
		ring.position.z = 0.004
		if _light == null:
			_light = OmniLight3D.new()
			_light.light_color = color
			_light.omni_range = 0.24
			_light.light_energy = 0.0
			_light.position.z = 0.02
			_light.set_meta("compact_module", true)
			holder.add_child(_light)


func _update_effects() -> void:
	if _holders.is_empty():
		return
	if effect_elapsed >= EFFECT_TIME:
		_effects.visible = false
		return
	var time := effect_elapsed / EFFECT_TIME
	var intensity := smoothstep(0.12, 0.30, time) * (1.0 - smoothstep(0.68, 1.0, time))
	var rotation: Basis = stage.robot.global_basis.orthonormalized()
	for holder in _holders:
		if holder.has_meta("module_mount"):
			var key := str(holder.get_meta("module_mount"))
			var mount := stage.module_visuals.mounts[key] as Node3D
			holder.global_transform = mount.global_transform
			holder.global_position = (mount.get_node("ServicePoint") as Node3D).global_position
			continue
		var offset: Vector3 = holder.get_meta("offset")
		var orbit: float = holder.get_meta("orbit")
		if not is_zero_approx(orbit):
			var radius := lerpf(0.33, 0.12, time) if category == "passive" else 0.25
			var angle := orbit + effect_elapsed * 2.6
			offset += Vector3(cos(angle), sin(angle), 0) * radius
		if holder.has_meta("plume_phase"):
			var rise := fmod(effect_elapsed * 3.5 + float(holder.get_meta("plume_phase")), 1.0)
			offset += Vector3(sin(effect_elapsed * 15.0 + rise) * 0.025, rise * 0.32, 0)
		holder.global_transform = Transform3D(rotation.scaled(Vector3.ONE * _scale_factor()), anchor(str(holder.get_meta("bone")), offset))
	for index in _materials.size():
		var color := _materials[index].albedo_color
		color.a = _base_alphas[index] * intensity
		_materials[index].albedo_color = color
	if _light != null:
		if _light.has_meta("compact_module"):
			_light.light_energy = intensity * (0.16 + 0.0368 * sin(effect_elapsed * 18.0))
		else:
			_light.light_energy = intensity * (0.65 + 0.15 * sin(effect_elapsed * 18.0))
	_effects.visible = effect_elapsed < EFFECT_TIME
