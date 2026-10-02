extends Node3D
## One lightweight controller for cloth and a bounded set of local lamps.
## Never modifies gameplay state, cover geometry, collision or navigation.
const LIGHT_BUDGET := 6
var _cloth: Array[ShaderMaterial] = []
var _lights: Array[OmniLight3D] = []
var _quality := 1
var _clock := 0.0

func _ready() -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("workshop_cloth") and mesh.material_override is ShaderMaterial:
			mesh.material_override = mesh.material_override.duplicate()
			_cloth.append(mesh.material_override as ShaderMaterial)
	for light in find_children("*", "OmniLight3D", true, false):
		if light.has_meta("workshop_light"):
			_lights.append(light as OmniLight3D)
	_update_lights()
	_install_ambience.call_deferred()

func _install_ambience() -> void:
	if not has_node("WorkshopAmbience"):
		var ambience := load("res://scripts/environment/workshop_ambience.gd").new() as Node3D
		ambience.name = "WorkshopAmbience"
		add_child(ambience)

func set_quality(level: int, wind: Vector2, strength: float) -> void:
	_quality = clampi(level,0,1)
	for cloth in _cloth:
		cloth.set_shader_parameter("wind_direction",wind.normalized())
		cloth.set_shader_parameter("wind_strength",strength)
		cloth.set_shader_parameter("motion_scale",1.0 if _quality>0 else .25)
	_update_lights()

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= .35:
		_clock = 0
		_update_lights()

func _update_lights() -> void:
	var camera := get_viewport().get_camera_3d()
	var focus := Vector3.ZERO
	if camera != null:
		var arena := get_parent()
		while arena!=null and arena.get_node_or_null("CameraRig")==null:
			arena = arena.get_parent()
		var rig := arena.get_node_or_null("CameraRig") as Node3D if arena!=null else null
		focus = rig.global_position if rig != null else camera.global_position
	_lights.sort_custom(func(a: OmniLight3D,b: OmniLight3D) -> bool: return a.global_position.distance_squared_to(focus) < b.global_position.distance_squared_to(focus))
	var budget := LIGHT_BUDGET if _quality>0 and is_visible_in_tree() else 0
	for index in _lights.size():
		_lights[index].visible = index < budget and _lights[index].global_position.distance_squared_to(focus) < 230.0
	set_meta("active_light_count",mini(budget,_lights.filter(func(light: OmniLight3D) -> bool: return light.visible).size()))
