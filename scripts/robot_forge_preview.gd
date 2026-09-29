extends SubViewportContainer

## The combat GLB and chassis paint, presented in an isolated, silent 3D world.
const MODEL := preload("res://art/player_mecha_animated.glb")
const CHASSIS_VISUALS := preload("res://scripts/robot_chassis_visuals.gd")
const ROTATION_SPEED := PI / 15.0
const SHOWCASE_STATES := ["idle", "warm_up", "walk", "run", "box_01", "bow"]

var chassis_id := "polyvalent"
var _viewport: SubViewport
var _turntable: Node3D
var _model: Node3D
var _animation_player: AnimationPlayer
var _clips: Array[StringName] = []
var _clip_index := 0
var _clip_elapsed := 0.0
var _clip_duration := 4.0
var _paint := CHASSIS_VISUALS.new()


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "RobotViewport"
	_viewport.size = Vector2i(240, 240)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var stage := Node3D.new()
	stage.name = "Showroom"
	_viewport.add_child(stage)
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.rotation.y = deg_to_rad(-18.0)
	stage.add_child(_turntable)
	_model = MODEL.instantiate() as Node3D
	_turntable.add_child(_model)
	var bounds := _model_bounds()
	_model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	_turntable.scale = Vector3.ONE * float(CHASSIS_VISUALS.SCALE_FACTORS.get(chassis_id, 1.0))
	_paint.apply(_model, chassis_id)
	_setup_animations()
	_build_showroom(stage, bounds)
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()


func _process(delta: float) -> void:
	if _turntable == null or not is_visible_in_tree():
		return
	_turntable.rotation.y = wrapf(_turntable.rotation.y + ROTATION_SPEED * delta, -PI, PI)
	if _animation_player == null or _clips.is_empty():
		return
	_clip_elapsed += delta
	if _clip_elapsed >= _clip_duration:
		_clip_index = (_clip_index + 1) % _clips.size()
		_play_clip()
	_animation_player.advance(delta)


func _sync_visibility() -> void:
	if _viewport == null:
		return
	var active := is_visible_in_tree()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)


func _model_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		var local_transform: Transform3D = _model.global_transform.affine_inverse() * mesh.global_transform
		var mesh_bounds: AABB = local_transform * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	return bounds


func _setup_animations() -> void:
	for node in _model.find_children("*", "AnimationPlayer", true, false):
		_animation_player = node as AnimationPlayer
		break
	if _animation_player == null:
		return
	# Each card owns its clips; removing root travel never edits combat resources.
	for library_name in _animation_player.get_animation_library_list():
		var library := _animation_player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		_animation_player.remove_animation_library(library_name)
		_animation_player.add_animation_library(library_name, library)
	var skeleton := _model.find_child("*Skeleton*", true, false) as Skeleton3D
	var clips_by_state: Dictionary = {}
	for clip_name in _animation_player.get_animation_list():
		var state := String(clip_name).get_slice("/", String(clip_name).get_slice_count("/") - 1).to_lower().replace(" ", "_").replace("-", "_")
		if state not in SHOWCASE_STATES:
			continue
		var clip := _animation_player.get_animation(clip_name)
		clip.loop_mode = Animation.LOOP_LINEAR
		_keep_clip_in_place(clip, skeleton)
		clips_by_state[state] = clip_name
	for state in SHOWCASE_STATES:
		if clips_by_state.has(state):
			_clips.append(clips_by_state[state])
	_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if not _clips.is_empty():
		_play_clip()
		_animation_player.advance(0.0)


func _keep_clip_in_place(clip: Animation, skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for track in range(clip.get_track_count()):
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := clip.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone_name := String(path.get_subname(0))
		if not (bone_name.to_lower().contains("hips") or bone_name.to_lower().contains("pelvis")):
			continue
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone).origin
		for key in range(clip.track_get_key_count(track)):
			var position: Vector3 = clip.track_get_key_value(track, key)
			position.x = rest.x
			position.z = rest.z
			clip.track_set_key_value(track, key, position)


func _play_clip() -> void:
	var name := _clips[_clip_index]
	var clip := _animation_player.get_animation(name)
	_clip_elapsed = 0.0
	_clip_duration = maxf(4.0, clip.length) if _clip_index == 0 else maxf(3.0, clip.length)
	_animation_player.play(name, 0.25)


func _build_showroom(stage: Node3D, bounds: AABB) -> void:
	var height := maxf(bounds.size.y, 0.1)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#1c1d1f")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#c1d9e0")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	stage.add_child(environment)
	_add_light(stage, Vector3(-35, -30, 0), Color("#ffe6c3"), 1.4, true)
	_add_light(stage, Vector3(-15, 135, 0), Color("#83d6e2"), 0.85, false)
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = height * 0.34
	cylinder.bottom_radius = cylinder.top_radius
	cylinder.height = height * 0.035
	plinth.mesh = cylinder
	plinth.position.y = -cylinder.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#344047")
	material.metallic = 0.5
	material.roughness = 0.65
	plinth.material_override = material
	stage.add_child(plinth)
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = height * 1.3
	stage.add_child(camera)
	camera.position = Vector3(0.0, height * 0.82, height * 3.0)
	camera.look_at(Vector3(0.0, height * 0.53, 0.0))
	camera.make_current()


func _add_light(stage: Node3D, angles: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	stage.add_child(light)
