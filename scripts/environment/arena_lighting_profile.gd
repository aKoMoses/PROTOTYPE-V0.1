extends Resource
## Per-map lighting profile. Applies to explicit lights/environment only.
## Sun direction stays owned by the map, including moving-sun mechanisms.
@export var sunlight_color := Color("#ffd097")
@export var sunlight_energy := 1.30
@export var shadow_blur := 1.0
@export var shadow_bias := 0.015
@export var shadow_normal_bias := 0.22
@export var shadow_distance := 58.0
@export var fill_energy := 0.10
@export var ambient_color := Color("#adb0ad")
@export var ambient_energy := 0.40
@export var sky_top_color := Color("#8cabc1")
@export var sky_horizon_color := Color("#d8c6a1")
@export var ground_bottom_color := Color("#70634f")
@export var ground_horizon_color := Color("#c7b491")
@export var sky_energy := 0.65
@export var ground_energy := 0.45
@export var shadow_atlas_normal := 4096
@export var shadow_atlas_low := 1024
@export var antialiasing_normal: Viewport.MSAA = Viewport.MSAA_4X

func apply(environment: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D = null) -> void:
	if sun != null:
		sun.light_color = sunlight_color
		sun.light_energy = sunlight_energy
		sun.shadow_blur = shadow_blur
		sun.shadow_bias = shadow_bias
		sun.shadow_normal_bias = shadow_normal_bias
		sun.directional_shadow_max_distance = shadow_distance
	if fill != null:
		fill.light_energy = fill_energy
	if environment != null:
		environment.ambient_light_color = ambient_color
		environment.ambient_light_energy = ambient_energy
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = sky_top_color
		sky_material.sky_horizon_color = sky_horizon_color
		sky_material.ground_bottom_color = ground_bottom_color
		sky_material.ground_horizon_color = ground_horizon_color
		sky_material.sky_energy_multiplier = sky_energy
		sky_material.ground_energy_multiplier = ground_energy
		sky_material.sun_angle_max = 0.0
		var sky := Sky.new()
		sky.sky_material = sky_material
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		environment.sky = sky
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

func apply_render_quality(viewport: Viewport, quality: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	viewport.msaa_3d = antialiasing_normal if quality > 0 else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_normal if quality > 0 else shadow_atlas_low, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality > 0 else RenderingServer.SHADOW_QUALITY_HARD)
