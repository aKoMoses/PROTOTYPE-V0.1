extends SubViewportContainer

const WORKSHOP := preload("res://art/forge-garage/workshop.glb")
const ROBOT := preload("res://art/player_mecha_animated.glb")
const PAINT := preload("res://scripts/robot_chassis_visuals.gd")
const SERVICE_ARM := preload("res://scripts/forge_service_arm.gd")
const WEAPON_MODELS := {
	"blaster": preload("res://art/player_heavy_blaster.glb"),
	"shotgun": preload("res://art/player_shotgun.glb"),
	"mekatana": preload("res://art/weapons/mekatana.glb"),
	"longshot": preload("res://art/weapons/longshot.glb"),
}
const WEAPON_LENGTHS := {"blaster": 0.96, "shotgun": 1.08, "mekatana": 1.45, "longshot": 1.50}

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
var idle_clip: StringName = &""
var chassis_id := "polyvalent"
var weapon_id := "blaster"
var _paint := PAINT.new()
var _normalizing_scale := 1.0
var _idle_elapsed := 0.0
var _next_service := 1.2
var _opaque_paint_shader: Shader
var _opaque_paint_materials: Dictionary = {}


func _ready() -> void:
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
	world.add_child(WORKSHOP.instantiate())
	_build_environment()
	_build_robot()
	arm = SERVICE_ARM.new()
	arm.name = "ServiceMechanism"
	arm.position.z = 0.25
	world.add_child(arm)
	_build_camera()
	_build_dust()
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()
	set_chassis(chassis_id)
	set_weapon(weapon_id)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_idle_elapsed += delta
	if robot_animator != null:
		robot_animator.advance(delta * 0.45)
	arm.advance_service(delta)
	if not arm.active:
		_next_service -= delta
		if _next_service <= 0.0:
			arm.start_service()
			_next_service = 15.0


func _sync_visibility() -> void:
	if viewport == null:
		return
	var active := is_visible_in_tree()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)
	if world != null:
		world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func set_chassis(identifier: String) -> void:
	chassis_id = identifier if PAINT.SCALE_FACTORS.has(identifier) else "polyvalent"
	if robot_model == null:
		return
	if arm != null and arm.active:
		arm.cancel_service()
		_next_service = 0.8
	robot.scale = Vector3.ONE * _normalizing_scale * float(PAINT.SCALE_FACTORS[chassis_id])
	_paint.apply(robot_model, chassis_id)
	_make_paint_opaque()
	if weapon_socket != null:
		set_weapon(weapon_id)


func set_weapon(identifier: String) -> void:
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
	var bounds := _bounds(weapon)
	weapon.position -= bounds.get_center()
	var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	# Socket's world transform already cancels the imported centimetre scale.
	holder.scale = Vector3.ONE * float(WEAPON_LENGTHS[weapon_id]) / maxf(longest, 0.001)
	var axis := Vector3.RIGHT if bounds.size.x == longest else (Vector3.UP if bounds.size.y == longest else Vector3.BACK)
	var desired_basis := Basis(Quaternion(axis, Vector3(-0.18, -0.98, 0.02).normalized()))
	skeleton.force_update_all_bone_transforms()
	var hand_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(weapon_attachment.bone_idx)
	var hand_offset := -0.50 if weapon_id == "mekatana" else (-0.38 if weapon_id == "longshot" else -0.29)
	var desired := Transform3D(desired_basis, hand_pose.origin + Vector3(-0.035, hand_offset, 0.02))
	weapon_socket.transform = hand_pose.affine_inverse() * desired


func inspect_robot() -> bool:
	return arm.start_service() if arm != null else false


func _build_robot() -> void:
	robot = Node3D.new()
	robot.name = "HeroRobot"
	robot.position = Vector3(0, 0.346, 0)
	robot.rotation.y = deg_to_rad(-9.0)
	world.add_child(robot)
	robot_model = ROBOT.instantiate() as Node3D
	robot.add_child(robot_model)
	var bounds := _bounds(robot_model)
	robot_model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
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
		for candidate in robot_animator.get_animation_list():
			if String(candidate).to_lower().ends_with("idle"):
				idle_clip = candidate
				break
		robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if idle_clip != &"":
			robot_animator.get_animation(idle_clip).loop_mode = Animation.LOOP_LINEAR
			robot_animator.play(idle_clip)
			robot_animator.advance(0.0)
	if skeleton != null:
		for index in range(skeleton.get_bone_count()):
			if skeleton.get_bone_name(index).to_lower().replace("_", "").ends_with("righthand"):
				weapon_attachment = BoneAttachment3D.new()
				weapon_attachment.name = "GarageRightHand"
				weapon_attachment.bone_name = skeleton.get_bone_name(index)
				skeleton.add_child(weapon_attachment)
				break


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


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#30251c")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#a8b7bf")
	settings.ambient_light_energy = 0.38
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.glow_enabled = true
	settings.glow_intensity = 0.55
	settings.glow_bloom = 0.09
	settings.fog_enabled = true
	settings.fog_density = 0.011
	settings.fog_light_color = Color("#947054")
	settings.fog_sky_affect = 0.0
	environment.environment = settings
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "WindowSun"
	sun.rotation_degrees = Vector3(-38, -135, 0)
	sun.light_color = Color("#ffd4a0")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 28.0
	sun.shadow_bias = 0.035
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "CoolFrontFill"
	fill.rotation_degrees = Vector3(-20, -15, 0)
	fill.light_color = Color("#a0c0ce")
	fill.light_energy = 0.65
	world.add_child(fill)
	_add_spot("WorkbenchLamp", Vector3(-3.65, 3.47, -1.4), Vector3(-3.65, 1.0, -1.5), Color("#ffb452"), 3.0, 6.0)
	_add_spot("HeroKey", Vector3(2.8, 5.2, 2.3), Vector3(0, 1.6, 0), Color("#ffdeb3"), 3.1, 8.0)


func _add_spot(label: String, pos: Vector3, target: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := SpotLight3D.new()
	light.name = label
	light.light_color = color
	light.light_energy = energy
	light.spot_range = reach
	light.spot_angle = 54.0
	light.shadow_enabled = true
	world.add_child(light)
	light.position = pos
	light.look_at(target)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "GarageCamera"
	camera.fov = 31.0
	camera.near = 0.1
	camera.far = 40.0
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
	dust.amount = 60
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
	ramp.colors = PackedColorArray([Color(0.8, 0.66, 0.4, 0), Color(0.8, 0.66, 0.4, 0.14), Color(0.8, 0.66, 0.4, 0)])
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
