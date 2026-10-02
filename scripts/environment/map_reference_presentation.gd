extends "res://scripts/environment/workshop_dressing.gd"
## Instance-only presentation for the other maps and their late transitions.
var _scene: Node3D
var _brush: Array[MeshInstance3D] = []
var _quality_clock := 0.0
var _zone := Vector3.INF

func _ready() -> void:
	_scene = get_parent() as Node3D
	while _scene!=null and _scene.get_node_or_null("CameraRig")==null:
		_scene = _scene.get_parent() as Node3D
	super._ready()
	for mesh in find_children("*","MeshInstance3D",true,false):
		if mesh.has_meta("reference_grass"):
			mesh.material_override = mesh.material_override.duplicate()
			_brush.append(mesh)
	if _scene!=null:
		# The existing factory lamps join this same budget, not a second set of
		# six. A single controller covers the casse, passage and factory together.
		for light in _scene.find_children("*","OmniLight3D",true,false):
			if light.get_viewport()==_scene.get_viewport() and light.is_visible_in_tree() and _is_scenery_light(light) and not light in _lights:
				if _scene.get_script().resource_path=="res://scripts/survival.gd":
					light.light_color = Color("#ffcf91")
				_lights.append(light)
	_sync()

func _is_scenery_light(light: OmniLight3D) -> bool:
	var branch: Node = light
	while branch.get_parent()!=_scene:
		branch = branch.get_parent()
		if branch==null:
			return false
	return branch==self or branch.name in ["TestArena","ArenaPresentation"] or branch.get_script()==null

func _process(delta: float) -> void:
	super._process(delta)
	_quality_clock += delta
	if _quality_clock>=.25:
		_quality_clock = 0.0
		_sync()

func _sync() -> void:
	if _scene==null:
		return
	var vfx := _scene.get_node_or_null("VFXManager")
	var quality := int(vfx.get("quality")) if vfx!=null else 1
	if _quality!=clampi(quality,0,1):
		set_quality(quality,Vector2(.94,-.34),.65)
	for mesh in _brush:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality>0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override.set_shader_parameter("wind_strength",.36 if quality>0 else .12)
		mesh.material_override.set_shader_parameter("local_actor_influence",0.0)
	if _scene.get_script().resource_path=="res://scripts/survival.gd":
		var center: Vector3 = _scene.get("arena_center")
		if center!=_zone:
			_zone = center
			# Entering the factory changes scene lights in gameplay code. Reapply
			# the approved warm key and cool ambient only when that zone changes.
			var sun := _scene.get_node("SurvivalSun") as DirectionalLight3D
			sun.light_color = Color("#ffcb87")
			sun.light_energy = .86
			var environment := (_scene.get_node("SurvivalEnvironment") as WorldEnvironment).environment
			environment.ambient_light_color = Color("#849dbb")
			environment.ambient_light_energy = .34
