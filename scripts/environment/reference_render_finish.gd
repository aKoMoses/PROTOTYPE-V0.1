extends Node3D
## The courtyard's final lighting/material pass. Uses the existing Mobile
## renderer, geometry, UV layout and local lamp budget. No actor or camera edits.
const SURFACE := preload("res://art/environment/reference_finish/surface.gdshader")
const CONTACT := preload("res://art/environment/reference_finish/contact.gdshader")
const GROUND := preload("res://art/environment/reference_finish/ground.gdshader")
const EXTERIOR := preload("res://art/environment/reference_finish/exterior.gdshader")
const DETAILS := preload("res://art/environment/reference_finish/detail_builder.gd")
const PAINTED := "res://shaders/stylized_salvage.gdshader"
const PARAMETERS := ["source_tint", "color_texture", "relief_texture", "has_texture", "normalized_texture", "has_relief", "vertex_tint", "world_projection", "texture_scale", "texture_offset", "texture_strength", "texture_gain", "pigment_color", "pigment_strength", "relief_strength", "surface_roughness", "surface_metallic", "sculpt_strength"]
var _scene: Node3D
var _director: Node3D
var _materials: Dictionary = {}
var _quality := -1
var _clock := 0.0
var _initialized := false
var _shadow_defaults: Array = []
var _original_msaa := Viewport.MSAA_DISABLED

func _ready() -> void:
	set_process(false)
	if OS.get_cmdline_user_args().has("reference-render-baseline"):
		return
	_director = get_parent() as Node3D
	_scene = _director.get_parent() as Node3D
	_configure.call_deferred()

func _configure() -> void:
	# Existing deferred presentation adapters run first. Shared source resources
	# are never changed, and a scene transition cannot leave a coroutine alive.
	if not is_inside_tree():
		return
	var tree := get_tree()
	for frame in range(2):
		await tree.process_frame
		if not is_inside_tree() or is_queued_for_deletion():
			return
	if not is_inside_tree() or not is_instance_valid(_scene):
		return
	_shadow_defaults = [
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)),
		bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true)),
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 1)),
	]
	_original_msaa = get_viewport().msaa_3d
	_configure_lighting()
	for mesh in _scene.find_children("*", "MeshInstance3D", true, false):
		if _is_scenery(mesh):
			_finish_mesh(mesh)
	var floor_mesh := _scene.get_node_or_null("Ground") as MeshInstance3D
	if floor_mesh != null and floor_mesh.material_override is ShaderMaterial:
		var source := floor_mesh.material_override as ShaderMaterial
		if source.shader.resource_path == "res://shaders/stylized_courtyard.gdshader":
			var finish := ShaderMaterial.new()
			finish.shader = GROUND
			finish.resource_name = "Reference finish / cracked concrete"
			for parameter in ["layout_albedo", "surface_normal", "concrete_detail", "use_layout", "world_layout", "layout_origin", "layout_span", "zone_tint", "floor_tint", "combat_clarity"]:
				var value: Variant = source.get_shader_parameter(parameter)
				if value != null:
					finish.set_shader_parameter(parameter, value)
			floor_mesh.material_override = finish
	var exterior := _scene.get_node_or_null("ArenaExterior/ExteriorDustTerrain") as MeshInstance3D
	if exterior != null:
		var sand := ShaderMaterial.new()
		sand.shader = EXTERIOR
		sand.set_shader_parameter("concrete_detail", preload("res://art/environment/courtyard_concrete_detail.png"))
		exterior.material_override = sand
	_build_contacts()
	# Bounded static details are batched once. They belong to this presentation
	# branch so changing arenas hides them together with the workshops.
	DETAILS.new().build(self, _scene)
	_initialized = true
	_update_quality()
	set_process(true)
	set_meta("finished_materials", _materials.size())
	set_meta("visual_only", true)

func _is_scenery(mesh: MeshInstance3D) -> bool:
	if _director.is_ancestor_of(mesh):
		return true
	var branch: Node = mesh
	while branch != null and branch.get_parent() != _scene:
		branch = branch.get_parent()
	return branch != null and (branch.is_in_group("arena_solid") or branch.name in ["Ground", "ArenaExterior"])

func _finish_mesh(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	if mesh.material_override != null:
		mesh.material_override = _finish_material(mesh.material_override)
	else:
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source != null:
				var finish := _finish_material(source)
				if finish != source:
					mesh.set_surface_override_material(surface, finish)

func _finish_material(source: Material) -> Material:
	if not source is ShaderMaterial or source.shader == null or source.shader.resource_path != PAINTED:
		return source
	if _materials.has(source):
		return _materials[source]
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.resource_name = "Reference finish / " + source.resource_name
	for parameter in PARAMETERS:
		var value: Variant = source.get_shader_parameter(parameter)
		if value != null:
			material.set_shader_parameter(parameter, value)
	var texture := source.get_shader_parameter("color_texture") as Texture2D
	if texture != null and texture.resource_path.ends_with("courtyard_steel_albedo.png"):
		material.set_shader_parameter("surface_roughness", 0.61)
		material.set_shader_parameter("surface_metallic", 0.40)
		material.set_shader_parameter("texture_gain", 1.20)
		material.set_shader_parameter("weathering_strength", 0.80)
		material.set_shader_parameter("steel_finish", 1.0)
		material.set_shader_parameter("texture_scale", (source.get_shader_parameter("texture_scale") as Vector3) * 0.55)
	elif texture != null and texture.resource_path.ends_with("courtyard_paint_albedo.png") and source.get_shader_parameter("normalized_texture") != true:
		material.set_shader_parameter("surface_roughness", 0.76)
		material.set_shader_parameter("surface_metallic", 0.10)
		material.set_shader_parameter("texture_gain", _number(source, "texture_gain", 1.0) * 1.06)
		material.set_shader_parameter("weathering_strength", 1.0)
	material.set_shader_parameter("relief_strength", minf(_number(source, "relief_strength", 0.35) * 1.6, 0.42))
	_materials[source] = material
	return material

func _number(material: ShaderMaterial, parameter: String, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(parameter)
	return float(value) if value != null else fallback

func _configure_lighting() -> void:
	var sun := _scene.get_node_or_null("ArenaKeyLight") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("#ffd097")
		sun.light_energy = 1.30
		sun.shadow_blur = 1.0
		sun.shadow_bias = 0.015
		sun.shadow_normal_bias = 0.22
		sun.directional_shadow_max_distance = 58.0
	var fill := _scene.get_node_or_null("CoolFillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = 0.10
	for child in _scene.get_children():
		if child is WorldEnvironment:
			# Sky reflections reveal the curved steel/brass without adding lights.
			var environment := (child as WorldEnvironment).environment
			environment.ambient_light_color = Color("#adb0ad")
			environment.ambient_light_energy = 0.40
			var sky_material := ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("#8cabc1")
			sky_material.sky_horizon_color = Color("#d8c6a1")
			sky_material.ground_bottom_color = Color("#70634f")
			sky_material.ground_horizon_color = Color("#c7b491")
			sky_material.sky_energy_multiplier = 0.65
			sky_material.ground_energy_multiplier = 0.45
			sky_material.sun_angle_max = 0.0
			var sky := Sky.new()
			sky.sky_material = sky_material
			sky.radiance_size = Sky.RADIANCE_SIZE_128
			environment.sky = sky
			environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

func _build_contacts() -> void:
	var entries: Array[Node3D] = []
	for body in get_tree().get_nodes_in_group("arena_solid"):
		if _scene.is_ancestor_of(body) and not body.get_meta("invisible_safety_limit", false) and body.get_node_or_null("Collision") is CollisionShape3D:
			if (body.get_node("Collision") as CollisionShape3D).shape is BoxShape3D:
				entries.append(body)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = PlaneMesh.new()
	(instances.mesh as PlaneMesh).size = Vector2.ONE
	instances.instance_count = entries.size()
	for index in entries.size():
		var body := entries[index]
		var collision := body.get_node("Collision") as CollisionShape3D
		var shape := collision.shape as BoxShape3D
		if shape == null:
			continue
		var size := Vector2(shape.size.x, shape.size.z)
		var extent := size + Vector2.ONE * 1.6
		var pose := body.global_transform * collision.transform
		pose.origin.y = 0.012
		pose.basis = pose.basis * Basis.from_scale(Vector3(extent.x, 1.0, extent.y))
		instances.set_instance_transform(index, global_transform.affine_inverse() * pose)
		instances.set_instance_custom_data(index, Color(size.x, size.y, extent.x, extent.y))
	var contacts := MultiMeshInstance3D.new()
	contacts.name = "CoverContactOcclusion"
	contacts.multimesh = instances
	var material := ShaderMaterial.new()
	material.shader = CONTACT
	contacts.material_override = material
	contacts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contacts)
	set_meta("contact_instances", entries.size())

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 0.25:
		_clock = 0.0
		_update_quality()

func _update_quality() -> void:
	var quality := int(_director.get_meta("active_quality", 1))
	if quality == _quality:
		return
	_quality = quality
	var details := get_node_or_null("ReferenceEdgeDetails")
	if details != null:
		for mesh in details.get_children():
			if mesh is MeshInstance3D:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if DisplayServer.get_name() != "headless":
		get_viewport().msaa_3d = Viewport.MSAA_4X if quality > 0 else Viewport.MSAA_DISABLED
		RenderingServer.directional_shadow_atlas_set_size(4096 if quality > 0 else 1024, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality > 0 else RenderingServer.SHADOW_QUALITY_HARD)
	set_meta("active_quality", quality)

func _exit_tree() -> void:
	if _initialized and DisplayServer.get_name() != "headless":
		# RenderingServer shadow controls are global; release this arena's budget.
		get_viewport().msaa_3d = _original_msaa
		RenderingServer.directional_shadow_atlas_set_size(_shadow_defaults[0], _shadow_defaults[1])
		RenderingServer.directional_soft_shadow_filter_set_quality(_shadow_defaults[2])
