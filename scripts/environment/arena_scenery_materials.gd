extends RefCounted
## Per-recipe materials: broad mineral variation, enamel chips and metal patina.
const SURFACE := preload("res://shaders/arena_scenery_surface.gdshader")
const FOLIAGE := preload("res://shaders/arena_foliage.gdshader")
var _palette: Dictionary = {}
var _source_finishes: Dictionary = {}
var recipe: Resource

func _init(art_recipe: Resource) -> void:
	recipe = art_recipe

func surface(color: Color, kind: int, roughness: float, metallic: float, stains: float = 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("source_tint", color)
	material.set_shader_parameter("surface_kind", kind)
	material.set_shader_parameter("surface_roughness", roughness)
	material.set_shader_parameter("surface_metallic", metallic)
	material.set_shader_parameter("weathering", recipe.weathering)
	material.set_shader_parameter("water_stains", stains)
	material.set_shader_parameter("surface_texture", recipe.metal_texture if kind == 1 else recipe.paint_texture if kind == 2 else recipe.stone_texture)
	material.set_shader_parameter("texture_strength", recipe.material_texture_strength)
	material.set_shader_parameter("texture_scale", 0.24 if kind == 1 else 0.27 if kind == 2 else 0.17)
	material.set_shader_parameter("surface_normal", recipe.metal_normal if kind == 1 else recipe.paint_normal if kind == 2 else recipe.stone_normal)
	material.set_shader_parameter("normal_strength", 0.38 if kind == 1 else 0.26)
	return material

func palette() -> Dictionary:
	if not _palette.is_empty():
		return _palette
	var colors: Dictionary = recipe.colors()
	for key in colors:
		if key in ["leaf", "leaf_light"]:
			var material := ShaderMaterial.new()
			material.shader = FOLIAGE
			material.set_shader_parameter("leaf_color", colors[key])
			_palette[key] = material
		elif key in ["stem", "soil", "marking"]:
			var material := StandardMaterial3D.new()
			material.albedo_color = colors[key]
			material.roughness = 0.88
			_palette[key] = material
		else:
			var kind := 0 if key == "stone" else 2 if key == "paint" else 1
			var roughness := 0.82 if kind == 0 else 0.37 if kind == 2 else 0.46
			_palette[key] = surface(colors[key], kind, roughness, 0.02 if kind == 0 else 0.28 if kind == 2 else 0.72)
	return _palette

func finish(source: Material, color: Color, kind: int, roughness: float, metallic: float, stains: float = 0.0) -> Material:
	if _source_finishes.has(source):
		return _source_finishes[source]
	var material := surface(color, kind, roughness, metallic, stains)
	_source_finishes[source] = material
	_source_finishes[material] = material
	return material
