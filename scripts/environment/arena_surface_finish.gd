extends RefCounted
## Reusable surface finish; clones and caches instance materials, never source assets.
const SURFACE := preload("res://art/environment/reference_finish/surface.gdshader")
const GROUND := preload("res://art/environment/reference_finish/ground.gdshader")
const EXTERIOR := preload("res://art/environment/reference_finish/exterior.gdshader")
const PAINTED := "res://shaders/stylized_salvage.gdshader"
const MATERIAL_LIBRARY := preload("res://scripts/environment/arena_material_library.gd")
const PARAMETERS := ["source_tint", "color_texture", "relief_texture", "has_texture", "normalized_texture", "has_relief", "vertex_tint", "world_projection", "texture_scale", "texture_offset", "texture_strength", "texture_gain", "pigment_color", "pigment_strength", "relief_strength", "surface_roughness", "surface_metallic", "sculpt_strength"]
var materials: Dictionary = {}
var _material_library := MATERIAL_LIBRARY.new()

func finish_mesh(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	if mesh.material_override != null:
		mesh.material_override = finish_material(mesh.material_override)
	else:
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source != null:
				var finish := finish_material(source)
				if finish != source:
					mesh.set_surface_override_material(surface, finish)


func finish_material(source: Material) -> Material:
	var original := source
	if source is StandardMaterial3D:
		if materials.has(source):
			return materials[source]
		var painted: ShaderMaterial = _material_library.paint(source)
		if painted == null:
			return source
		source = painted
	if not source is ShaderMaterial or source.shader == null or source.shader.resource_path != PAINTED:
		return source
	if materials.has(source):
		return materials[source]
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
	materials[original] = material
	return material


func _number(material: ShaderMaterial, parameter: String, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(parameter)
	return float(value) if value != null else fallback


func finish_ground(floor_mesh: MeshInstance3D) -> void:
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

func finish_exterior(exterior: MeshInstance3D) -> void:
	if exterior != null:
		var sand := ShaderMaterial.new()
		sand.shader = EXTERIOR
		sand.set_shader_parameter("concrete_detail", preload("res://art/environment/courtyard_concrete_detail.png"))
		exterior.material_override = sand
