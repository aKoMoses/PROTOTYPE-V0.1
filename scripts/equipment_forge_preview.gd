extends SubViewportContainer

## Static combat models displayed in their own silent forge showroom.
const MODEL_PATHS := {
	"blaster": "res://art/player_heavy_blaster.glb",
	"shotgun": "res://art/player_shotgun.glb",
	"longshot": "res://art/weapons/longshot.glb",
	"mekatana": "res://art/weapons/mekatana.glb",
}
const ROTATION_SPEED := PI / 15.0
const MODEL_SPAN := 1.6
const FRAME_MARGIN := 1.18

var equipment_id := "blaster"
var _viewport: SubViewport
var _turntable: Node3D
var _model: Node3D
var _camera: Camera3D
var _view_center := Vector3.ZERO
var _framing_radius := 1.0
var _horizontal_extent := 1.0
var _vertical_extent := 1.0


static func has_model(identifier: String) -> bool:
	return ResourceLoader.exists(model_path(identifier), "PackedScene")


static func model_path(identifier: String) -> String:
	return str(MODEL_PATHS.get(identifier, "res://art/weapons/%s.glb" % identifier))


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not has_model(equipment_id):
		set_process(false)
		return
	var model_scene := load(model_path(equipment_id)) as PackedScene
	if model_scene == null:
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.name = "EquipmentViewport"
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
	_model = model_scene.instantiate() as Node3D
	_turntable.add_child(_model)
	var bounds := _model_bounds()
	var longest_axis := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var model_scale := MODEL_SPAN / maxf(longest_axis, 0.001)
	_model.position -= bounds.get_center()
	_turntable.scale = Vector3.ONE * model_scale
	var height := bounds.size.y * model_scale
	_turntable.position.y = height * 0.5
	_view_center = _turntable.position
	var horizontal_radius := Vector2(bounds.size.x, bounds.size.z).length() * model_scale * 0.5
	_build_showroom(stage, height, horizontal_radius)
	resized.connect(_fit_camera)
	visibility_changed.connect(_sync_visibility)
	_fit_camera()
	_sync_visibility()


func _process(delta: float) -> void:
	if _turntable == null or not is_visible_in_tree():
		return
	_turntable.rotation.y = wrapf(_turntable.rotation.y + ROTATION_SPEED * delta, -PI, PI)


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


func _build_showroom(stage: Node3D, height: float, horizontal_radius: float) -> void:
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
	cylinder.top_radius = maxf(horizontal_radius * 1.08, 0.1)
	cylinder.bottom_radius = cylinder.top_radius
	cylinder.height = maxf(height * 0.035, 0.025)
	plinth.mesh = cylinder
	plinth.position.y = -cylinder.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#344047")
	material.metallic = 0.5
	material.roughness = 0.65
	plinth.material_override = material
	stage.add_child(plinth)
	# Keep the camera beyond every yaw angle, including the plinth below it.
	var model_radius := Vector2(horizontal_radius, height * 0.5).length()
	var plinth_radius := Vector2(cylinder.top_radius, height * 0.5 + cylinder.height).length()
	_framing_radius = maxf(maxf(model_radius, plinth_radius), 0.1)
	var camera_offset := Vector3(0.0, _framing_radius * 0.75, _framing_radius * 3.5)
	var sin_pitch := camera_offset.y / camera_offset.length()
	var cos_pitch := camera_offset.z / camera_offset.length()
	# Project the full yaw-invariant body and plinth bounds onto camera up.
	# Fitting their vertical span separately avoids shrinking wide weapon cards.
	var body_extent := horizontal_radius * sin_pitch + height * 0.5 * cos_pitch
	var plinth_min := -(height * 0.5 + cylinder.height) * cos_pitch - cylinder.top_radius * sin_pitch
	var plinth_max := -height * 0.5 * cos_pitch + cylinder.top_radius * sin_pitch
	var vertical_min := minf(-body_extent, plinth_min)
	var vertical_max := maxf(body_extent, plinth_max)
	_vertical_extent = (vertical_max - vertical_min) * 0.5
	_horizontal_extent = maxf(horizontal_radius, cylinder.top_radius)
	_view_center.y += (vertical_min + vertical_max) * 0.5 / cos_pitch
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.01
	stage.add_child(_camera)
	_camera.position = _view_center + camera_offset
	_camera.look_at(_view_center)
	_camera.make_current()


func _fit_camera() -> void:
	if _camera == null:
		return
	var dimensions := size
	if dimensions.x <= 0.0 or dimensions.y <= 0.0:
		dimensions = Vector2(_viewport.size)
	var aspect := maxf(dimensions.x / maxf(dimensions.y, 1.0), 0.01)
	_camera.size = maxf(_vertical_extent * 2.0, _horizontal_extent * 2.0 / aspect) * FRAME_MARGIN


func _add_light(stage: Node3D, angles: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	stage.add_child(light)
