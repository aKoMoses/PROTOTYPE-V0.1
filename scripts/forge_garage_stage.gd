extends SubViewportContainer

const WORKSHOP := preload("res://art/forge-garage/workshop.glb")
const PAINT := preload("res://scripts/robot_chassis_visuals.gd")
const SERVICE_ARM := preload("res://scripts/forge_service_arm.gd")
const STATIC_BATCHER := preload("res://scripts/static_scene_batcher.gd")
const FINISHES := preload("res://scripts/forge_workshop_materials.gd")
const HANGAR := preload("res://scripts/forge_garage_hangar.gd")
const MODULE_VISUALS := preload("res://scripts/robot_module_visuals.gd")
const CONTEXT_BANK := preload("res://scripts/mecha_animation_bank.gd")
const WEAPON_MODELS := {
	"blaster": preload("res://art/player_heavy_blaster.glb"),
	"shotgun": preload("res://art/player_shotgun.glb"),
	"mekatana": preload("res://art/weapons/mekatana.glb"),
	"longshot": preload("res://art/weapons/longshot.glb"),
}
const WEAPON_LENGTHS := {"blaster": 0.96, "shotgun": 1.08, "mekatana": 1.45, "longshot": 1.50}
const ROBOT_YAW := -PI / 20.0
const ROBOT_GESTURES := CONTEXT_BANK.GARAGE_REST_CLIPS
const GESTURE_DELAY := Vector2(8.0, 14.0)
const GESTURE_SPEED := 0.9

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var robot: Node3D
var robot_model: Node3D
var skeleton: Skeleton3D
var robot_animator: AnimationPlayer
var arm
var weapon_attachment: BoneAttachment3D
var weapon_socket: Node3D
var module_visuals: MODULE_VISUALS
var module_stations: Node3D
var weapon_rack: Node3D
var idle_clip: StringName = &""
var chassis_id := "polyvalent"
var weapon_id := "blaster"
var _paint := PAINT.new()
var _normalizing_scale := 1.0
var _next_service := 1.2
var _opaque_paint_shader: Shader
var _opaque_paint_materials: Dictionary = {}
var _weapon_profiles: Dictionary = {}
var _robot_pick_bounds := AABB()
var _rotating_robot := false
var _equipment_focused := false
var automatic_service_enabled := true
var _gesture_clips: Array[StringName] = []
var _gesture_clip: StringName = &""
var _last_gesture: StringName = &""
var _gesture_elapsed := 0.0
var _next_gesture := 0.0
var _gesture_random := RandomNumberGenerator.new()
var _pending_reaction: StringName = &""
var _welcome_index := 0
var _approval_index := 0
var _failure_index := 0


func _ready() -> void:
	_gesture_random.randomize()
	_schedule_gesture()
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "GarageViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	world.name = "WorkshopWorld"
	viewport.add_child(world)
	var workshop := WORKSHOP.instantiate() as Node3D
	world.add_child(workshop)
	var finishes := FINISHES.new()
	finishes.apply_imported(workshop)
	_close_workshop_edge()
	var hangar := HANGAR.new()
	hangar.name = "GarageHangar"
	world.add_child(hangar)
	_build_environment()
	_build_robot()
	arm = SERVICE_ARM.new()
	arm.name = "ServiceMechanism"
	arm.position.z = 0.25
	world.add_child(arm)
	finishes.apply_imported(arm.model)
	_build_camera()
	_build_dust()
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()
	set_chassis(chassis_id)
	set_weapon(weapon_id)
	STATIC_BATCHER.install(world, true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	arm.advance_service(delta)
	if automatic_service_enabled and not _equipment_focused and not arm.active and not _rotating_robot and _gesture_clip == &"" and is_zero_approx(angle_difference(robot.rotation.y, ROBOT_YAW)):
		_next_service -= delta
		if _next_service <= 0.0:
			arm.start_service()
			_next_service = 15.0
	_advance_robot_animation(delta)


func _advance_robot_animation(delta: float) -> void:
	if robot_animator == null or idle_clip == &"":
		return
	if _rotating_robot or arm.active or _equipment_focused:
		_return_to_idle()
		robot_animator.advance(delta * 0.45)
		return
	if _gesture_clip != &"":
		var step := delta * GESTURE_SPEED
		robot_animator.advance(step)
		_gesture_elapsed += step
		if _gesture_elapsed >= robot_animator.get_animation(_gesture_clip).length:
			_return_to_idle()
		return
	robot_animator.advance(delta * 0.45)
	if _pending_reaction != &"":
		_gesture_clip = _pending_reaction
		_pending_reaction = &""
		_gesture_elapsed = 0.0
		robot_animator.play(_gesture_clip, 0.3)
		robot_animator.advance(0.0)
		return
	_next_gesture -= delta
	if _next_gesture <= 0.0 and not _gesture_clips.is_empty():
		var choices := _gesture_clips.duplicate()
		if choices.size() > 1:
			choices.erase(_last_gesture)
		_gesture_clip = choices[_gesture_random.randi_range(0, choices.size() - 1)]
		_last_gesture = _gesture_clip
		_gesture_elapsed = 0.0
		robot_animator.play(_gesture_clip, 0.3)
		robot_animator.advance(0.0)


func _schedule_gesture() -> void:
	_next_gesture = _gesture_random.randf_range(GESTURE_DELAY.x, GESTURE_DELAY.y)


func react_to_installation(saved: bool) -> void:
	# Defer until the focus/installation arm has released the robot.
	var choices := CONTEXT_BANK.APPROVE_CLIPS if saved else [&"frustrated_01", &"frustrated_02"]
	var index := _approval_index if saved else _failure_index
	_pending_reaction = StringName("context/" + String(choices[index % choices.size()]))
	if saved:
		_approval_index += 1
	else:
		_failure_index += 1
	_return_to_idle()
	_next_service = 15.0


func _return_to_idle(blend: float = 0.3) -> void:
	if _gesture_clip == &"":
		return
	_gesture_clip = &""
	_gesture_elapsed = 0.0
	robot_animator.play(idle_clip, blend)
	robot_animator.advance(0.0)
	_schedule_gesture()


func _sync_visibility() -> void:
	if viewport == null:
		return
	var active := is_visible_in_tree()
	if active:
		_pending_reaction = StringName("context/" + String(CONTEXT_BANK.GREET_CLIPS[_welcome_index % CONTEXT_BANK.GREET_CLIPS.size()]))
		_welcome_index += 1
		_next_service = 8.0
	elif not active:
		_pending_reaction = &""
		_return_to_idle(0.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)
	if world != null:
		world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func is_robot_at_position(point: Vector2) -> bool:
	if camera == null or robot == null or not is_visible_in_tree() or not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	var screen_point := point * Vector2(viewport.size) / size
	var inverse := robot.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(screen_point)
	var direction := inverse.basis * camera.project_ray_normal(screen_point)
	return _robot_pick_bounds.intersects_ray(origin, direction) != null


func begin_robot_rotation() -> void:
	_rotating_robot = true
	_return_to_idle()
	_schedule_gesture()
	arm.cancel_service()
	_next_service = 15.0


func set_equipment_focus(active: bool) -> void:
	_equipment_focused = active
	if active:
		_return_to_idle()
		arm.cancel_service()
		_next_service = 15.0


func rotate_robot(radians: float) -> void:
	robot.rotation.y = wrapf(robot.rotation.y + radians, -PI, PI)


func end_robot_rotation() -> void:
	_rotating_robot = false


func set_chassis(identifier: String) -> void:
	chassis_id = identifier if PAINT.SCALE_FACTORS.has(identifier) else "polyvalent"
	if robot_model == null:
		return
	_return_to_idle(0.0)
	if arm != null and arm.active:
		arm.cancel_service()
		_next_service = 0.8
	if robot_model.scene_file_path != PAINT.model_path(chassis_id):
		var equipment: Dictionary = module_visuals.equipment_ids.duplicate()
		robot_model.free()
		robot_model = null
		skeleton = null
		robot_animator = null
		weapon_attachment = null
		weapon_socket = null
		module_visuals = null
		idle_clip = &""
		_gesture_clip = &""
		_gesture_clips.clear()
		_pending_reaction = &""
		_paint = PAINT.new()
		_opaque_paint_materials.clear()
		_build_robot()
		module_visuals.set_loadout(equipment)
	robot.scale = Vector3.ONE * _normalizing_scale * float(PAINT.SCALE_FACTORS[chassis_id])
	_paint.apply(robot_model, chassis_id)
	_make_paint_opaque()
	if weapon_attachment != null:
		set_weapon(weapon_id)


func set_weapon(identifier: String) -> void:
	_return_to_idle(0.0)
	weapon_id = identifier if WEAPON_MODELS.has(identifier) else "blaster"
	if weapon_socket != null:
		weapon_socket.free()
		weapon_socket = null
	if weapon_attachment == null:
		return
	var weapon := (WEAPON_MODELS[weapon_id] as PackedScene).instantiate() as Node3D
	weapon_socket = Node3D.new()
	weapon_socket.name = "GarageWeaponSocket"
	weapon_attachment.add_child(weapon_socket)
	var holder := Node3D.new()
	holder.name = "WeaponGeometry"
	weapon_socket.add_child(holder)
	holder.add_child(weapon)
	var bounds: AABB = _weapon_profile(weapon_id).bounds
	weapon.position -= bounds.get_center()
	# Socket's world transform already cancels the imported centimetre scale.
	var desired := weapon_mount_transform(weapon_id)
	holder.scale = desired.basis.get_scale()
	desired.basis = desired.basis.orthonormalized()
	skeleton.force_update_all_bone_transforms()
	var hand_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(weapon_attachment.bone_idx)
	weapon_socket.transform = hand_pose.affine_inverse() * desired


func _weapon_profile(identifier: String) -> Dictionary:
	if not _weapon_profiles.has(identifier):
		var source := (WEAPON_MODELS[identifier] as PackedScene).instantiate() as Node3D
		source.visible = false
		world.add_child(source)
		var bounds := _bounds(source)
		source.free()
		var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var axis := Vector3.RIGHT if bounds.size.x == longest else (Vector3.UP if bounds.size.y == longest else Vector3.BACK)
		_weapon_profiles[identifier] = {
			"bounds": bounds,
			"basis": Basis(Quaternion(axis, Vector3(-0.18, -0.98, 0.02).normalized())),
			"scale": float(WEAPON_LENGTHS[identifier]) / maxf(longest, 0.001),
		}
	return _weapon_profiles[identifier]


func weapon_geometry_bounds(identifier: String) -> AABB:
	var bounds: AABB = _weapon_profile(identifier).bounds
	return AABB(bounds.position - bounds.get_center(), bounds.size)


func weapon_mount_transform(identifier: String) -> Transform3D:
	if weapon_attachment == null or not WEAPON_MODELS.has(identifier):
		return Transform3D.IDENTITY
	var profile := _weapon_profile(identifier)
	skeleton.force_update_all_bone_transforms()
	var hand_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(weapon_attachment.bone_idx)
	var hand_offset := -0.50 if identifier == "mekatana" else (-0.38 if identifier == "longshot" else -0.29)
	# The centred raw geometry has this exact world pose in the hand and gripper.
	var turn := Basis(Vector3.UP, robot.rotation.y - ROBOT_YAW)
	var basis: Basis = turn * profile.basis
	return Transform3D(basis.scaled(Vector3.ONE * float(profile.scale)), hand_pose.origin + turn * Vector3(-0.035, hand_offset, 0.02))


func set_mobility_module(identifier: String) -> void:
	if module_visuals != null:
		module_visuals.set_mobility_module(identifier)


func set_equipped_modules(equipment: Dictionary) -> void:
	if module_visuals != null:
		module_visuals.set_loadout(equipment)


func inspect_robot() -> bool:
	if arm == null or arm.active or _rotating_robot:
		return false
	_return_to_idle()
	robot.rotation.y = ROBOT_YAW
	return arm.start_service()


func _build_robot() -> void:
	if robot == null:
		robot = Node3D.new()
		robot.name = "HeroRobot"
		robot.position = Vector3(0, 0.346, 0)
		robot.rotation.y = ROBOT_YAW
		world.add_child(robot)
	robot_model = (load(PAINT.model_path(chassis_id)) as PackedScene).instantiate() as Node3D
	robot.add_child(robot_model)
	var bounds := _bounds(robot_model)
	robot_model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	_robot_pick_bounds = AABB(bounds.position + robot_model.position, bounds.size)
	_normalizing_scale = 3.05 / maxf(bounds.size.y, 0.01)
	_improve_hero_materials()
	for node in robot_model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	for node in robot_model.find_children("*", "AnimationPlayer", true, false):
		robot_animator = node as AnimationPlayer
		break
	if robot_animator != null:
		for library_name in robot_animator.get_animation_library_list():
			var library := robot_animator.get_animation_library(library_name).duplicate(true) as AnimationLibrary
			robot_animator.remove_animation_library(library_name)
			robot_animator.add_animation_library(library_name, library)
		CONTEXT_BANK.install(robot_animator, skeleton, CONTEXT_BANK.GARAGE_CLIPS)
		for candidate in robot_animator.get_animation_list():
			var clip_name := String(candidate).get_slice("/", String(candidate).get_slice_count("/") - 1).to_lower()
			if clip_name == "idle":
				idle_clip = candidate
			elif String(candidate).begins_with("context/") and clip_name in ROBOT_GESTURES:
				var gesture := robot_animator.get_animation(candidate)
				gesture.loop_mode = Animation.LOOP_NONE
				_keep_gesture_in_place(gesture)
				_gesture_clips.append(candidate)
		_protect_weapon_arm()
		robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if idle_clip != &"":
			robot_animator.get_animation(idle_clip).loop_mode = Animation.LOOP_LINEAR
			robot_animator.play(idle_clip)
			robot_animator.advance(0.0)
	if skeleton != null:
		module_visuals = MODULE_VISUALS.new()
		robot_model.add_child(module_visuals)
		module_visuals.configure(skeleton)
		for index in range(skeleton.get_bone_count()):
			if skeleton.get_bone_name(index).to_lower().replace("_", "").ends_with("righthand"):
				weapon_attachment = BoneAttachment3D.new()
				weapon_attachment.name = "GarageRightHand"
				weapon_attachment.bone_name = skeleton.get_bone_name(index)
				skeleton.add_child(weapon_attachment)
				break


func _protect_weapon_arm() -> void:
	if idle_clip == &"":
		return
	var idle := robot_animator.get_animation(idle_clip)
	var baseline: Dictionary = {}
	for track in idle.get_track_count():
		baseline["%s|%d" % [idle.track_get_path(track), idle.track_get_type(track)]] = track
	for clip_name in CONTEXT_BANK.GARAGE_CLIPS:
		var clip := robot_animator.get_animation("context/" + String(clip_name))
		if clip_name in CONTEXT_BANK.GREET_CLIPS or clip_name in [&"agree", &"scratch"]:
			_mirror_free_hand_gesture(clip, idle, baseline)
		for track in clip.get_track_count():
			var path := clip.track_get_path(track)
			var bone := String(path.get_subname(0)).to_lower()
			if not (bone.contains("rightshoulder") or bone.contains("rightarm") or bone.contains("rightforearm") or bone.contains("righthand")):
				continue
			var source_track := int(baseline.get("%s|%d" % [path, clip.track_get_type(track)], -1))
			if source_track < 0 or idle.track_get_type(source_track) != clip.track_get_type(track):
				continue
			var value: Variant = idle.track_get_key_value(source_track, 0)
			for key in clip.track_get_key_count(track):
				clip.track_set_key_value(track, key, value)


func _mirror_free_hand_gesture(clip: Animation, idle: Animation, baseline: Dictionary) -> void:
	# Reflect the authored right-arm gesture into the left joint's rest frame.
	# The right arm will then be held in its ordinary carried-weapon pose.
	var reflection := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
	for track in range(clip.get_track_count()):
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path := clip.track_get_path(track)
		var right_name := String(path.get_subname(0))
		if not (right_name.contains("RightShoulder") or right_name.contains("RightArm") or right_name.contains("RightForeArm") or right_name.contains("RightHand")):
			continue
		var left_name := right_name.replace("Right", "Left")
		var right := skeleton.find_bone(right_name)
		var left := skeleton.find_bone(left_name)
		if right < 0 or left < 0:
			continue
		var left_path := NodePath(String(path).replace(right_name, left_name))
		var target := clip.find_track(left_path, Animation.TYPE_ROTATION_3D)
		if target < 0:
			target = clip.add_track(Animation.TYPE_ROTATION_3D)
			clip.track_set_path(target, left_path)
		var base_track := int(baseline.get("%s|%d" % [left_path, Animation.TYPE_ROTATION_3D], -1))
		var left_origin: Quaternion = idle.rotation_track_interpolate(base_track, 0.0) if base_track >= 0 else skeleton.get_bone_rest(left).basis.get_rotation_quaternion()
		var right_origin := clip.rotation_track_interpolate(track, 0.0)
		var mapping := skeleton.get_bone_global_rest(left).basis.orthonormalized().inverse() * reflection * skeleton.get_bone_global_rest(right).basis.orthonormalized()
		for key in range(clip.track_get_key_count(target) - 1, -1, -1):
			clip.track_remove_key(target, key)
		for key in clip.track_get_key_count(track):
			var authored: Quaternion = clip.track_get_key_value(track, key)
			var delta := Basis(right_origin.inverse() * authored)
			var mirrored := (mapping * delta * mapping.inverse()).get_rotation_quaternion()
			clip.track_insert_key(target, clip.track_get_key_time(track, key), left_origin * mirrored)


func _keep_gesture_in_place(clip: Animation) -> void:
	if skeleton == null:
		return
	for track in range(clip.get_track_count()):
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := clip.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone_name := String(path.get_subname(0))
		if not (bone_name.to_lower().contains("hips") or bone_name.to_lower().contains("pelvis")):
			continue
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone).origin
		for key in range(clip.track_get_key_count(track)):
			var position: Vector3 = clip.track_get_key_value(track, key)
			position.x = rest.x
			position.z = rest.z
			clip.track_set_key_value(track, key, position)


func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		var local: Transform3D = node.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = local * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _improve_hero_materials() -> void:
	if chassis_id == "puissant":
		preload("res://scripts/robot_surface_polish.gd").apply(robot_model)
		return
	for mesh_node in robot_model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		var part := String(mesh.name).trim_prefix("tripo_part_").to_int()
		if part not in PAINT.ARMOUR_PARTS:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var local := source.duplicate() as StandardMaterial3D
			local.metallic = 0.38
			local.roughness = 0.57
			mesh.set_surface_override_material(surface, local)


func _make_paint_opaque() -> void:
	# Combat paint supports concealment with ALPHA; the garage is fully visible.
	# Opaque paint participates in depth of field and avoids blurred body panels.
	if _opaque_paint_shader == null:
		_opaque_paint_shader = Shader.new()
		_opaque_paint_shader.code = PAINT.PAINT_SHADER.code.replace("depth_prepass_alpha", "depth_draw_opaque").replace("ALPHA = visibility_opacity;", "")
	for mesh_node in robot_model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var painted := mesh.get_active_material(surface) as ShaderMaterial
			if painted == null or painted.shader != PAINT.PAINT_SHADER:
				continue
			var key := painted.get_instance_id()
			if not _opaque_paint_materials.has(key):
				var opaque := painted.duplicate() as ShaderMaterial
				opaque.shader = _opaque_paint_shader
				_opaque_paint_materials[key] = opaque
			mesh.set_surface_override_material(surface, _opaque_paint_materials[key])


func _close_workshop_edge() -> void:
	# The original frontal shot never saw the open right edge of the set.
	# Station travelling shots now need the same enclosed workshop on that side.
	var material := FINISHES.surface("steel", Color("#454b4c"), 0.32, 0.76)
	var wall := MeshInstance3D.new()
	wall.name = "WorkshopRightWall"
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.22, 7.2, 12.0)
	wall.mesh = wall_mesh
	wall.material_override = material
	wall.position = Vector3(8.85, 3.6, -0.25)
	world.add_child(wall)
	for index in 11:
		var rib := MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(0.07, 7.0, 0.055)
		rib.material_override = material
		rib.position = Vector3(8.70, 3.5, -5.0 + index)
		world.add_child(rib)


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "WorkshopEnvironment"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#334650")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#bdb8ac")
	settings.ambient_light_energy = 0.30
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.glow_enabled = true
	settings.glow_intensity = 0.32
	settings.glow_bloom = 0.03
	settings.fog_enabled = true
	settings.fog_density = 0.0015
	settings.fog_light_color = Color("#98a4a8")
	settings.fog_sky_affect = 0.0
	environment.environment = settings
	world.add_child(environment)
	# A local source at the glass keeps warm light in the room and leaves its
	# corners quieter. It replaces the broad sun, keeping three shadow lights.
	_add_spot("WindowSun", Vector3(3.8, 4.8, -5.29), Vector3(-1, 0, 3.6), Color("#ffd7a2"), 11.0, 14.0, 58.0)
	var fill := DirectionalLight3D.new()
	fill.name = "CoolFrontFill"
	fill.rotation_degrees = Vector3(-20, -15, 0)
	fill.light_color = Color("#cbd0ce")
	fill.light_energy = 0.40
	world.add_child(fill)
	_add_spot("WorkbenchLamp", Vector3(-3.65, 3.47, -1.4), Vector3(-3.65, 1.0, -1.5), Color("#ffcf91"), 2.8, 5.0, 46.0)
	_add_spot("HeroKey", Vector3(2.8, 5.2, 2.3), Vector3(0, 1.6, 0), Color("#edf3ef"), 4.5, 8.0, 40.0)


func _add_spot(label: String, pos: Vector3, target: Vector3, color: Color, energy: float, reach: float, spread: float = 54.0) -> void:
	var light := SpotLight3D.new()
	light.name = label
	light.light_color = color
	light.light_energy = energy
	light.spot_range = reach
	light.spot_angle = spread
	light.shadow_enabled = true
	world.add_child(light)
	light.position = pos
	light.look_at(target)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "GarageCamera"
	camera.fov = 31.0
	camera.near = 0.1
	camera.far = 90.0
	world.add_child(camera)
	camera.position = Vector3(0.05, 2.72, 7.75)
	camera.look_at(Vector3(0, 1.62, -0.10))
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 10.0
	lens.dof_blur_far_transition = 3.0
	lens.dof_blur_amount = 0.16
	camera.attributes = lens
	camera.make_current()


func _build_dust() -> void:
	var dust := GPUParticles3D.new()
	dust.name = "WorkshopDust"
	dust.amount = 40
	dust.lifetime = 10.0
	dust.preprocess = 2.0
	dust.position = Vector3(0, 3, -1)
	dust.visibility_aabb = AABB(Vector3(-7, -3, -5), Vector3(14, 7, 10))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(6, 3, 4)
	process.direction = Vector3.UP
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.015
	process.initial_velocity_max = 0.06
	process.scale_min = 0.25
	process.scale_max = 0.9
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.9, 0.82, 0.66, 0), Color(0.9, 0.82, 0.66, 0.10), Color(0.9, 0.82, 0.66, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	process.color_ramp = texture
	dust.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(1, 0.8, 0.5, 0.2)
	quad.material = material
	dust.draw_pass_1 = quad
	world.add_child(dust)
