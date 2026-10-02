extends Node3D

## Shared player/bot cocoon. Geometry stays readable without bloom or textures.
const SHELL := preload("res://shaders/stasis_shell.gdshader")
const ICE := Color("#b4eeff")
const VIOLET := Color("#a38bff")
const RELEASE_DURATION := 0.18

var _duration := 1.5
var _elapsed := 0.0
var _release_age := -1.0
var _remaining_source: Callable
var _shell: MeshInstance3D
var _shell_material: ShaderMaterial
var _cage: Node3D
var _timer: MeshInstance3D
var _wave: MeshInstance3D
var _materials: Array[StandardMaterial3D] = []
var _base_alpha: Array[float] = []


func configure(duration: float, remaining_source := Callable()) -> void:
	_duration = maxf(0.01, duration)
	_remaining_source = remaining_source


func _ready() -> void:
	name = "StasisCocoon"
	_shell_material = ShaderMaterial.new()
	_shell_material.shader = SHELL
	var sphere := SphereMesh.new()
	sphere.radius = 1.08
	sphere.height = 2.38
	sphere.radial_segments = 48
	sphere.rings = 24
	_shell = _mesh(self, sphere, null)
	_shell.material_override = _shell_material
	_shell.position.y = 1.25
	_cage = Node3D.new()
	add_child(_cage)
	# Three open meridians form a suspended containment cage, not a solid globe.
	var ribs := ImmediateMesh.new()
	ribs.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(3):
		var yaw := float(index) * TAU / 3.0
		for segment in range(44):
			var a := -1.12 + float(segment) / 44.0 * 2.24
			var b := -1.12 + float(segment + 1) / 44.0 * 2.24
			var side := Vector3(cos(yaw), 0, -sin(yaw)) * 0.012
			var pa := Vector3(sin(yaw) * cos(a) * 1.09, 1.25 + sin(a) * 1.20, cos(yaw) * cos(a) * 1.09)
			var pb := Vector3(sin(yaw) * cos(b) * 1.09, 1.25 + sin(b) * 1.20, cos(yaw) * cos(b) * 1.09)
			for point in [pa - side, pa + side, pb + side, pa - side, pb + side, pb - side]:
				ribs.surface_add_vertex(point)
	ribs.surface_end()
	_mesh(_cage, ribs, _material(Color(VIOLET, 0.65)))
	for index in range(2):
		var orbit := _mesh(_cage, _arc(0.96, 0.018, 0.72), _material(Color(ICE, 0.65)))
		orbit.position.y = 0.70 + float(index) * 1.10
		orbit.rotation.y = float(index) * PI
	var base := _mesh(self, _arc(1.30, 0.022, 1.0, true), _material(Color(VIOLET, 0.78)))
	base.position.y = 0.045
	_timer = _mesh(self, ImmediateMesh.new(), _material(Color(ICE, 0.94)))
	_timer.position.y = 0.055
	_wave = _mesh(self, _arc(1.0, 0.03, 1.0), _material(Color(ICE, 0.65)))
	_wave.position.y = 0.035
	# A few suspended motes add scale without particle emitters or lights.
	var motes := ImmediateMesh.new()
	motes.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(12):
		var angle := float(index) * 2.39996
		var y := 0.30 + float(index % 5) * 0.39
		var radius := 1.11 * sqrt(maxf(0.1, 1.0 - pow((y - 1.25) / 1.25, 2.0)))
		var center := Vector3(sin(angle) * radius, y, cos(angle) * radius)
		var side := Vector3(cos(angle), 0.0, -sin(angle)) * 0.024
		for point in [center + Vector3.UP * 0.06, center + side, center - Vector3.UP * 0.06, center + Vector3.UP * 0.06, center - Vector3.UP * 0.06, center - side]:
			motes.surface_add_vertex(point)
	motes.surface_end()
	_mesh(_cage, motes, _material(Color(ICE, 0.80)))
	_update_visual(1.0)


func _process(delta: float) -> void:
	_elapsed += delta
	var remaining := maxf(0.0, _duration - _elapsed)
	if _remaining_source.is_valid():
		remaining = maxf(0.0, float(_remaining_source.call()))
	if remaining <= 0.0 and _release_age < 0.0:
		_release_age = 0.0
	if _release_age >= 0.0:
		_release_age += delta
		if _release_age >= RELEASE_DURATION:
			queue_free()
			return
	_update_visual(clampf(remaining / _duration, 0.0, 1.0))


func _update_visual(ratio: float) -> void:
	var opening := 1.0 - pow(1.0 - clampf(_elapsed / 0.16, 0.0, 1.0), 3.0)
	var release := clampf(_release_age / RELEASE_DURATION, 0.0, 1.0)
	var strength := opening * (1.0 - release)
	_shell.scale = Vector3.ONE * (0.86 + opening * 0.14 + release * 0.06)
	_shell_material.set_shader_parameter("strength", strength)
	_shell_material.set_shader_parameter("clock", _elapsed)
	_shell_material.set_shader_parameter("release", release)
	_cage.rotation.y = _elapsed * 0.20
	_cage.scale = Vector3.ONE * (0.95 + opening * 0.05 + release * 0.08)
	for index in range(_materials.size()):
		_materials[index].albedo_color.a = _base_alpha[index] * strength
	_arc(1.20, 0.048, ratio, false, _timer.mesh as ImmediateMesh)
	_wave.scale = Vector3.ONE * (0.75 + minf(_elapsed / 0.36, 1.0) * 0.64)
	(_wave.material_override as StandardMaterial3D).albedo_color.a = 0.65 * (1.0 - clampf(_elapsed / 0.36, 0.0, 1.0))
	_wave.visible = _elapsed < 0.36


func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.albedo_color = color
	_materials.append(result)
	_base_alpha.append(color.a)
	return result


func _mesh(parent: Node3D, shape: Mesh, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result


func _arc(radius: float, width: float, ratio: float, segmented := false, reuse: ImmediateMesh = null) -> ImmediateMesh:
	var result := reuse if reuse != null else ImmediateMesh.new()
	result.clear_surfaces()
	if ratio <= 0.0:
		return result
	result.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(96):
		if segmented and index % 8 >= 6:
			continue
		var a := TAU * ratio * float(index) / 96.0
		var b := TAU * ratio * float(index + 1) / 96.0
		var pa := Vector3(sin(a), 0, cos(a))
		var pb := Vector3(sin(b), 0, cos(b))
		for point in [pa * radius, pa * (radius + width), pb * (radius + width), pa * radius, pb * (radius + width), pb * radius]:
			result.surface_add_vertex(point)
	result.surface_end()
	return result
