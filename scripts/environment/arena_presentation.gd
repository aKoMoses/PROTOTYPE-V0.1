extends Node3D
## Visual-only director. Physics, navigation, actors and camera belong to Main.
const SETTINGS = preload("res://art/environment/arena_art_settings.tres")
const SAND = preload("res://art/environment/arena_sand.tres")
const EXTERIOR_SAND = preload("res://art/environment/exterior_sand.tres")
@export var settings: Resource = SETTINGS
var _quality := -2
var _quality_clock := 0.0
var _scene: Node3D
var _yard: Node3D

func _ready() -> void:
	_scene = get_parent() as Node3D
	_yard = get_node_or_null("SalvageYard") as Node3D
	var ground := _scene.get_node_or_null("Ground") as MeshInstance3D
	if ground != null:
		ground.material_override = SAND
	var exterior := _scene.get_node_or_null("ArenaExterior/ExteriorDustTerrain") as MeshInstance3D
	if exterior != null:
		exterior.material_override = EXTERIOR_SAND
	var sun := _scene.get_node_or_null("ArenaKeyLight") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("#ffe9c8")
		sun.light_energy = settings.sunlight_energy
		sun.rotation_degrees = Vector3(-46.0, -38.0, 0.0)
		sun.directional_shadow_max_distance = settings.shadow_distance
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_blend_splits = true
		sun.shadow_bias = 0.035
		sun.shadow_normal_bias = 0.65
		# Keep a dense map over the camera's combat region; no extra shadow lights.
		sun.directional_shadow_fade_start = 0.85
	var fill := _scene.get_node_or_null("CoolFillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = settings.fill_energy
	for child in _scene.get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_color = Color("#a4b6c1")
			child.environment.ambient_light_energy = settings.ambient_energy
			child.environment.background_color = Color("#a38c66")
	# Mounted amber lamps are luminous surfaces. Their point lights contribute
	# little in daylight, so keep them disabled rather than spending mobile lights.
	for light in _scene.get("_flicker_lights"):
		light.visible = false
	_apply_quality()

func _process(delta: float) -> void:
	_quality_clock += delta
	if _quality_clock >= 0.5:
		_quality_clock = 0.0
		_apply_quality()

func set_quality(level: int) -> void:
	# Runtime overrides stay on this director, not on the shared saved resource.
	settings = settings.duplicate()
	settings.quality = clampi(level, 0, 1)
	_apply_quality()

func _apply_quality() -> void:
	var quality := int(settings.quality)
	if quality < 0:
		var vfx := _scene.get_node_or_null("VFXManager")
		quality = int(vfx.get("quality")) if vfx != null else 1
	if quality == _quality:
		return
	_quality = quality
	set_meta("active_quality", quality)
	if _yard != null and _yard.has_method("set_quality"):
		_yard.call("set_quality", quality, settings.wind_direction, settings.wind_strength)
	for bush in get_tree().get_nodes_in_group("bush_placeholder"):
		var foliage := bush.get_node_or_null("GroundedVegetation/LayeredHighGrass") as MeshInstance3D
		if foliage != null and foliage.material_override is ShaderMaterial:
			foliage.material_override.set_shader_parameter("wind_direction", settings.wind_direction.normalized())
			foliage.material_override.set_shader_parameter("wind_strength", settings.wind_strength * (0.55 if quality == 0 else 1.0))
