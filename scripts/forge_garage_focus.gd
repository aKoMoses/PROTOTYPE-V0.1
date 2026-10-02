extends Node

## Inspection camera and short equipment cues; no combat state is changed.
const TRANSITION_TIME := 0.52
const EFFECT_TIME := 1.65
const COLORS := {
	"weapon": Color("#77e5ff"), "offensive": Color("#ffac52"),
	"defensive": Color("#68bfff"), "mobility": Color("#ffcf65"),
	"passive": Color("#bd9aff"),
}
const ZONES := {
	"modulo_drone": "shoulder", "javelin": "arm", "fulguro_punch": "arm", "pelto_smash": "arm",
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


func configure(garage_stage: Node, picker: Control, interface: Control) -> void:
	stage = garage_stage
	_picker = picker
	_ui = interface
	_base = stage.camera.global_transform
	_base_fov = stage.camera.fov
	_design_fov = _base_fov
	_authored_fov = _base_fov
	_from = _base
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
	var design_height := 720.0 * _ui.scale.y
	_base_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_design_fov * 0.5)) * stage.size.y / maxf(design_height, 1.0)))
	if not stage._equipment_focused or zone != "robot":
		stage.camera.fov = _base_fov
	_reframe()


func show_equipment(kind: String, identifier: String, play_effect: bool = true) -> void:
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


func preview_equipment(kind: String, identifier: String) -> void:
	# The catalog keeps the whole robot visible while retaining the local cue.
	show_overview(false)
	if kind == "robot" or not COLORS.has(kind):
		return
	category = kind
	equipment_id = identifier
	effect_elapsed = 0.0
	_build_effects()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _framed_chassis != stage.chassis_id:
		_bones.clear()
		for index in stage.skeleton.get_bone_count():
			var bone: String = stage.skeleton.get_bone_name(index)
			_bones[bone.to_lower().trim_prefix("mixamorig_").trim_prefix("mixamorig:")] = index
		fit_layout()
	_transition = minf(_transition + delta / TRANSITION_TIME, 1.0)
	var weight := _transition * _transition * (3.0 - 2.0 * _transition)
	var desired := _base if zone == "robot" else _focused_transform()
	stage.camera.global_transform = _from.interpolate_with(desired, weight)
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
	if equipment_id in ["pyro_boots", "bio_injector"] and zone != "robot" and stage.module_visuals != null:
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
	var basis := Basis.looking_at(-_view_direction, Vector3.UP)
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
		var depth := relative.dot(_view_direction)
		distance = maxf(distance, absf(relative.dot(basis.x)) / maxf(tangent * aspect * fraction.x * 0.88, 0.01) + depth)
		distance = maxf(distance, absf(relative.dot(basis.y)) / maxf(tangent * fraction.y * 0.88, 0.01) + depth)
	var center := rect.get_center() / control_size
	var position := target + _view_direction * distance
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
		_light.light_energy = intensity * (0.65 + 0.15 * sin(effect_elapsed * 18.0))
	_effects.visible = effect_elapsed < EFFECT_TIME
