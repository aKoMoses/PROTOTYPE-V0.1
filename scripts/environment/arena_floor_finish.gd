extends RefCounted
## Optional concrete/ceramic grain for existing engraved floor layouts.
## Existing layouts and shader uniforms are retained; source materials are cloned.
const FLOOR := "res://shaders/compact_arena_floor.gdshader"
const CONCRETE := preload("res://art/environment/courtyard_concrete_detail.png")
var _materials: Dictionary = {}
var recipe: Resource
var wear_zones := PackedVector4Array()

func configure(art_recipe: Resource, zones: PackedVector4Array) -> void:
	recipe = art_recipe
	wear_zones = zones

func finish(source: Material) -> Material:
	if not source is ShaderMaterial or source.shader == null or source.shader.resource_path != FLOOR:
		return source
	var style: Variant = source.get_shader_parameter("style")
	if style not in [0, 1, 2]:
		return source
	if _materials.has(source):
		return _materials[source]
	var material := source.duplicate() as ShaderMaterial
	material.set_shader_parameter("detail_albedo", recipe.stone_texture if recipe != null else CONCRETE)
	material.set_shader_parameter("detail_strength", float(recipe.floor_grain) if recipe != null else 0.38)
	material.set_shader_parameter("detail_scale", recipe.floor_texture_scale if recipe != null else 0.16)
	material.set_shader_parameter("detail_relief", 0.012)
	material.set_shader_parameter("authored_wear", float(recipe.floor_wear) if recipe != null else 0.7)
	material.set_shader_parameter("wear_zone_count", mini(wear_zones.size(), 12))
	var padded := wear_zones.duplicate()
	padded.resize(12)
	material.set_shader_parameter("wear_zones", padded)
	if recipe != null:
		var color: Color = source.get_shader_parameter("stone_color")
		if recipe.floor_base.a > 0.0:
			color = recipe.floor_base
		material.set_shader_parameter("stone_color", color * recipe.floor_tint)
		if recipe.floor_inlay.a > 0.0:
			material.set_shader_parameter("metal_color", recipe.floor_inlay)
	_materials[source] = material
	_materials[material] = material
	return material
