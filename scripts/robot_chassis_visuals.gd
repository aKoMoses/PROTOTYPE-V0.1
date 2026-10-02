extends RefCounted

## Instance-local paint variants. The source GLB, textures and shared materials
## remain untouched, and Polyvalent restores the exact original overrides.
const PAINT_SHADER := preload("res://art/shaders/robot_chassis.gdshader")
const SCALE_FACTORS := {"agile": 0.95, "polyvalent": 1.0, "puissant": 1.05}
const PROFILES := {
	"agile": {
		"panel_color": Color("#c2d2d5"), "accent_color": Color("#369aa9"),
		"fabric_color": Color("#285968"), "pack_color": Color("#4c7079"),
		"panel_roughness": 0.52, "panel_metallic": 0.22,
	},
	"puissant": {
		"panel_color": Color("#626b73"), "accent_color": Color("#d1a14c"),
		"fabric_color": Color("#792e34"), "pack_color": Color("#8e754e"),
		"panel_roughness": 0.66, "panel_metallic": 0.20,
	},
}
# Authored tripo_part IDs, inspected against the GLB's bounds and textures.
const ARMOUR_PARTS := [0, 1, 2, 3, 4, 5, 6, 8, 9, 13, 16, 17, 24, 25, 43, 45, 46]
const CLOTH_PARTS := [15, 27, 31, 32, 44]
const BACKPACK_PART := 7

var _surfaces: Array[Dictionary] = []


func apply(imported_model: Node3D, identifier: String) -> void:
	if imported_model == null:
		return
	if _surfaces.is_empty():
		_collect_surfaces(imported_model)
	for entry in _surfaces:
		var mesh: MeshInstance3D = entry.mesh
		if not PROFILES.has(identifier):
			mesh.set_surface_override_material(entry.surface, entry.original_override)
			continue
		var variants: Dictionary = entry.variants
		if not variants.has(identifier):
			variants[identifier] = _make_material(entry.source, entry.role, PROFILES[identifier])
		mesh.set_surface_override_material(entry.surface, variants[identifier])


func _collect_surfaces(node: Node) -> void:
	# Weapons live under runtime bone attachments inside the imported skeleton.
	# They retain their own appearance, independently of chassis selection.
	if node is BoneAttachment3D:
		return
	if node is MeshInstance3D and String(node.name).begins_with("tripo_part_"):
		var part := String(node.name).trim_prefix("tripo_part_").to_int()
		var role := -1
		if part in ARMOUR_PARTS:
			role = 0
		elif part in CLOTH_PARTS:
			role = 1
		elif part == BACKPACK_PART:
			role = 2
		var mesh := node as MeshInstance3D
		if role >= 0 and mesh.mesh != null:
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if material != null and material.albedo_texture != null:
					_surfaces.append({"mesh": mesh, "surface": surface, "role": role,
						"source": material, "original_override": mesh.get_surface_override_material(surface), "variants": {}})
	for child in node.get_children():
		_collect_surfaces(child)


func _make_material(source: StandardMaterial3D, role: int, profile: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAINT_SHADER
	material.set_shader_parameter("visibility_opacity", 1.0)
	material.set_shader_parameter("visibility_silhouette", 0.0)
	material.set_shader_parameter("base_texture", source.albedo_texture)
	material.set_shader_parameter("source_tint", source.albedo_color)
	material.set_shader_parameter("source_roughness", source.roughness)
	material.set_shader_parameter("source_metallic", source.metallic)
	material.set_shader_parameter("part_role", role)
	for parameter in profile:
		material.set_shader_parameter(parameter, profile[parameter])
	return material
