extends Resource
## Shared presentation controls. Quality follows the existing combat VFX setting.
@export_enum("Follow combat VFX:-1", "Low:0", "Normal:1") var quality: int = -1
@export var wind_direction := Vector2(0.94, -0.34)
@export_range(0.0, 1.5, 0.05) var wind_strength := 0.65
@export_range(0.0, 2.0, 0.05) var sunlight_energy := 1.22
@export_range(0.0, 1.0, 0.05) var ambient_energy := 0.56
@export_range(0.0, 1.0, 0.05) var fill_energy := 0.18
@export_range(20.0, 180.0, 1.0) var shadow_distance := 58.0
