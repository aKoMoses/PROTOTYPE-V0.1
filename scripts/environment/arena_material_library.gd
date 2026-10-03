extends RefCounted
## Per-map shared material recipes. No source Resource is mutated.
const SURFACE := preload("res://shaders/stylized_salvage.gdshader")
const PAINT := preload("res://art/environment/courtyard_paint_albedo.png")
const STEEL := preload("res://art/environment/courtyard_steel_albedo.png")
const METAL_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const STEEL_DARK_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")

var painted_materials: Dictionary = {}
var _material_cache: Dictionary = {}
var _textured_material_cache: Dictionary = {}

func material(color: Color, roughness: float = 0.8, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var key := "%s|%.3f|%s" % [color.to_html(), roughness, emission.to_html()]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.35
	_material_cache[key] = material
	return material


func textured(color: Color, roughness: float, emission: Color, texture: Texture2D, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var texture_path := texture.resource_path if texture != null else ""
	var key := "%s|%.3f|%s|%s|%.3f,%.3f,%.3f" % [color.to_html(), roughness, emission.to_html(), texture_path, uv_scale.x, uv_scale.y, uv_scale.z]
	if _textured_material_cache.has(key):
		return _textured_material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.35
	if texture != null:
		material.albedo_texture = texture
		material.uv1_scale = uv_scale
		if texture == STEEL_DARK_TEXTURE:
			material.metallic = 0.42
		elif texture == METAL_RUST_TEXTURE:
			material.metallic = 0.18
		else:
			material.metallic = 0.04
	_textured_material_cache[key] = material
	return material


func paint(source: StandardMaterial3D) -> ShaderMaterial:
	# Glow, translucency, foliage and gameplay markers keep their own pipeline.
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.emission_enabled or source.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or source.albedo_color.a < 0.99:
		return null
	if source.uv1_triplanar and not source.uv1_world_triplanar:
		return null
	if source.cull_mode != BaseMaterial3D.CULL_BACK:
		return null
	if painted_materials.has(source):
		return painted_materials[source]
	var finish := ShaderMaterial.new()
	finish.shader = SURFACE
	finish.resource_name = "Painted courtyard / " + source.resource_name
	finish.set_shader_parameter("source_tint", source.albedo_color)
	finish.set_shader_parameter("vertex_tint", source.vertex_color_use_as_albedo)
	finish.set_shader_parameter("has_texture", source.albedo_texture != null)
	finish.set_shader_parameter("world_projection", source.uv1_world_triplanar)
	finish.set_shader_parameter("texture_scale", source.uv1_scale)
	finish.set_shader_parameter("texture_offset", source.uv1_offset)
	if source.albedo_texture != null:
		var texture_path := source.albedo_texture.resource_path
		var texture := source.albedo_texture
		if texture_path.ends_with("metal_cream.svg") or texture_path.ends_with("metal_rust.svg"):
			texture = PAINT
		elif texture_path.ends_with("steel_dark.svg"):
			texture = STEEL
		finish.set_shader_parameter("color_texture", texture)
		if texture != source.albedo_texture:
			finish.set_shader_parameter("world_projection", true)
			finish.set_shader_parameter("texture_scale", Vector3.ONE * 0.42)
		var pigment := Color("#c4b79c")
		if "steel" in texture_path:
			pigment = Color("#8dabb6")
			# The supplied steel texture is already dark gunmetal. Retain its
			# chips while bringing the large lids into the reference's blue-grey.
			finish.set_shader_parameter("texture_gain", 1.70)
		elif "rust" in texture_path:
			pigment = Color("#ae7656")
		elif "paint" in texture_path or "cream" in texture_path:
			pigment = Color("#d9c7a4")
		elif "banner" in texture_path:
			pigment = Color("#a75a47")
		elif texture_path.ends_with("courtyard_concrete_detail.png"):
			finish.set_shader_parameter("texture_gain", 1.50)
		finish.set_shader_parameter("pigment_color", pigment)
		finish.set_shader_parameter("pigment_strength", 0.12)
	else:
		finish.set_shader_parameter("has_texture", true)
		finish.set_shader_parameter("normalized_texture", true)
		finish.set_shader_parameter("color_texture", PAINT)
		finish.set_shader_parameter("world_projection", true)
		finish.set_shader_parameter("texture_scale", Vector3.ONE * 0.32)
	finish.set_shader_parameter("has_relief", source.normal_enabled and source.normal_texture != null)
	if source.normal_texture != null:
		finish.set_shader_parameter("relief_texture", source.normal_texture)
	finish.set_shader_parameter("relief_strength", source.normal_scale * 0.65)
	finish.set_shader_parameter("surface_roughness", clampf(source.roughness, 0.48, 0.96))
	finish.set_shader_parameter("surface_metallic", minf(source.metallic, 0.50))
	# Cloth/dust stay calm and matte; manufactured plates have stronger planes.
	var soft := "cloth" in source.resource_name or "sand" in source.resource_name
	finish.set_shader_parameter("sculpt_strength", 0.05 if soft else 0.15)
	painted_materials[source] = finish
	return finish
