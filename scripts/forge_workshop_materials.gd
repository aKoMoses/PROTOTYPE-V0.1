extends RefCounted

## Local garage finishes: shared within one set, never applied to combat resources.
const MAPS := {
	"paint": [preload("res://art/forge-garage/finishes/paint_albedo.png"), preload("res://art/forge-garage/finishes/paint_normal.png"), preload("res://art/forge-garage/finishes/paint_roughness.png")],
	"metal": [preload("res://art/forge-garage/finishes/metal_albedo.png"), preload("res://art/forge-garage/finishes/metal_normal.png"), preload("res://art/forge-garage/finishes/metal_roughness.png")],
	"concrete": [preload("res://art/forge-garage/finishes/concrete_albedo.png"), preload("res://art/forge-garage/finishes/concrete_normal.png"), preload("res://art/forge-garage/finishes/concrete_roughness.png")],
	"wood": [preload("res://art/forge-garage/finishes/wood_albedo.png"), preload("res://art/forge-garage/finishes/wood_normal.png"), preload("res://art/forge-garage/finishes/wood_roughness.png")],
}
const GLASS := preload("res://art/forge-garage/finishes/glass_albedo.png")
const IMPORTED := {
	"worn_steel": ["steel", Color("#596267")],
	"oiled_metal": ["dark", Color("#30383c")],
	"rusted_iron": ["steel", Color("#454b4c")],
	"exposed_metal": ["edge", Color("#929c9d")],
	"workshop_concrete": ["concrete", Color("#747c7c")],
	"scarred_workbench": ["wood", Color("#a27c54")],
	"workshop_ochre": ["steel", Color("#bc893e")],
	"toolbox_red": ["steel", Color("#87473a")],
	"equipment_cases": ["steel", Color("#595e4d")],
}
var _imported: Dictionary = {}


static func surface(key: String, color: Color, metal: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "GarageFinish_" + key
	material.albedo_color = color
	material.metallic = metal
	material.roughness = roughness
	var finish := "paint"
	match key:
		"steel", "dark", "ivory":
			material.metallic = 0.32 if key != "dark" else 0.48
			material.roughness = 0.92
		"edge":
			finish = "metal"
			material.metallic = 0.78
			material.roughness = 0.9
		"concrete":
			finish = "concrete"
			material.metallic = 0.0
			material.roughness = 1.0
		"wood":
			finish = "wood"
			material.metallic = 0.0
			material.roughness = 1.0
		_:
			return material
	material.albedo_texture = MAPS[finish][0]
	material.normal_enabled = true
	material.normal_texture = MAPS[finish][1]
	material.normal_scale = 0.3
	material.roughness_texture = MAPS[finish][2]
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# Both imported furniture and bevelled procedural cabinets use world-sized grain.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * (0.65 if finish == "concrete" else 2.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material


func apply_imported(root: Node3D) -> void:
	# Let sunlight cross the glass while the existing mullions cast their grid.
	for node in root.find_children("*", "MeshInstance3D", true, false):
		_split_window(node as MeshInstance3D)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for index in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(index) as StandardMaterial3D
			if original == null:
				continue
			var key := String(original.resource_name)
			if not _imported.has(key):
				if IMPORTED.has(key):
					var profile: Array = IMPORTED[key]
					_imported[key] = surface(profile[0], profile[1], original.metallic, original.roughness)
				elif key in ["sunlit_window", "lamp_diffuser", "service_indicator"]:
					var local := original.duplicate() as StandardMaterial3D
					local.emission_energy_multiplier = 0.40 if key == "sunlit_window" else (1.2 if key == "lamp_diffuser" else 0.65)
					if key == "sunlit_window":
						local.albedo_color = Color("#806c4e")
						local.albedo_texture = GLASS
						local.emission = Color("#ffd397")
						local.emission_texture = GLASS
						local.uv1_triplanar = true
						local.uv1_world_triplanar = true
						local.uv1_scale = Vector3.ONE * 0.18
					_imported[key] = local
				else:
					continue
			mesh.set_surface_override_material(index, _imported[key])


func _split_window(visual: MeshInstance3D) -> void:
	if visual.name == "WorkshopWindowGlass":
		return
	var source := visual.mesh
	var window_index := -1
	for index in source.get_surface_count():
		var material := source.surface_get_material(index)
		if material != null and material.resource_name == "sunlit_window":
			window_index = index
			break
	if window_index < 0:
		return
	var opaque := ArrayMesh.new()
	var glass := ArrayMesh.new()
	for index in source.get_surface_count():
		var target := glass if index == window_index else opaque
		target.add_surface_from_arrays(source.surface_get_primitive_type(index), source.surface_get_arrays(index))
		target.surface_set_material(target.get_surface_count() - 1, source.surface_get_material(index))
	visual.mesh = opaque
	var panes := MeshInstance3D.new()
	panes.name = "WorkshopWindowGlass"
	panes.mesh = glass
	panes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(panes)
