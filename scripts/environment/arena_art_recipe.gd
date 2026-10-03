extends Resource
## Complete starting palette and finish settings. Geometry/gameplay stay map-owned.
@export var title := "Arena"
@export_enum("solar", "garden", "clock") var cover_style := "solar"
@export var stone := Color("#cdbf9f")
@export var metal := Color("#856442")
@export var paint := Color("#397873")
@export var bright := Color("#c7af7c")
@export var dark := Color("#263637")
@export var marking := Color("#e1d6b9")
@export var leaf := Color("#294f3b")
@export var leaf_light := Color("#789460")
@export_range(0.0, 1.0) var weathering := 0.72
@export_range(0.0, 1.0) var floor_wear := 0.7
@export_range(0.0, 1.0) var floor_grain := 0.38
@export var floor_tint := Color.WHITE
@export var floor_base := Color.TRANSPARENT
@export var floor_inlay := Color.TRANSPARENT
@export_range(0.05, 1.0) var floor_texture_scale := 0.16
@export_range(0.0, 1.0) var material_texture_strength := 0.78
@export var stone_texture: Texture2D = preload("res://art/environment/courtyard_concrete_detail.png")
@export var paint_texture: Texture2D = preload("res://art/environment/courtyard_paint_albedo.png")
@export var metal_texture: Texture2D = preload("res://art/environment/courtyard_steel_albedo.png")
@export var stone_normal: Texture2D = preload("res://art/environment/arena_concrete_normal.png")
@export var paint_normal: Texture2D = preload("res://art/environment/courtyard_paint_normal.png")
@export var metal_normal: Texture2D = preload("res://art/environment/courtyard_steel_normal.png")
@export var sun_color := Color("#ffe0b2")
@export var sun_energy := 1.15
@export_range(0.0, 1.0) var shadow_bias := 0.1
@export_range(0.0, 2.0) var shadow_normal_bias := 0.6
@export var ambient_color := Color("#a2b6bf")
@export var ambient_energy := 0.39
@export var sky_top := Color("#6997b0")
@export var sky_horizon := Color("#d9d7bb")
@export var sky_ground := Color("#567f96")
@export var sky_ground_horizon := Color("#b8d0ce")
@export var sky_energy := 1.0

func colors() -> Dictionary:
	return {"stone": stone, "metal": metal, "paint": paint, "bright": bright,
		"trim": metal.darkened(0.16), "dark": dark, "marking": marking,
		"leaf": leaf, "leaf_light": leaf_light, "stem": leaf.lightened(0.1), "soil": Color("#293429")}
