extends Node3D

# Both charge timers live in the existing cooldown dictionary, so resets,
# Bio Injector acceleration and authoritative network snapshots include them.
const PRIMARY := "pyro_boots"
const RESERVE := "pyro_boots_reserve"
const LIFETIME := 0.48
var _age := 0.0
var _direction := Vector3.FORWARD
var _actor: Node3D
var _dash_state: Node
var _dash_revision := -1
var _boots: Node3D
var _ring: MeshInstance3D
var _flash: MeshInstance3D
var _embers: Array[MeshInstance3D] = []
var _flames: Array[MeshInstance3D] = []
var _flame_shader: Shader


static func charges(cooldowns: Dictionary) -> int:
	return int(float(cooldowns.get(PRIMARY, 0.0)) <= 0.0) + int(float(cooldowns.get(RESERVE, 0.0)) <= 0.0)


static func spend(cooldowns: Dictionary, duration: float) -> void:
	var key := PRIMARY if float(cooldowns.get(PRIMARY, 0.0)) <= 0.0 else RESERVE
	cooldowns[key] = maxf(0.0, duration)


static func recharge_remaining(cooldowns: Dictionary) -> float:
	var first := maxf(0.0, float(cooldowns.get(PRIMARY, 0.0)))
	var second := maxf(0.0, float(cooldowns.get(RESERVE, 0.0)))
	return minf(first, second) if first > 0.0 and second > 0.0 else maxf(first, second)


func ignite(actor: Node3D, direction: Vector3, dash_state: Node) -> void:
	name = "PyroBootsIgnition"
	_actor = actor
	_dash_state = dash_state
	if actor.has_method("is_dash_active"):
		_dash_revision = int(actor.get("_dash_token"))
	_direction = direction.normalized()
	actor.get_tree().current_scene.add_child(self)
	global_position = actor.global_position
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.86
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 32
	_ring = _mesh(self, ring_mesh, Color("#ff8729"), 0.90)
	_ring.position.y = 0.10
	_ring.scale = Vector3(0.2, 0.07, 0.2)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_flash = _mesh(self, sphere, Color("#ffe49c"), 0.85)
	_flash.position.y = 0.20
	for index in range(14):
		var ember := _mesh(self, sphere, Color("#ffab32") if index % 3 else Color("#ff5420"), 0.95)
		var angle := TAU * float(index) / 14.0
		ember.set_meta("velocity", Vector3(cos(angle), 0.35 + float(index % 4) * 0.27, sin(angle)) * 4.2)
		ember.position.y = 0.15
		ember.scale = Vector3(0.10, 0.19, 0.10)
		_embers.append(ember)
	_boots = Node3D.new()
	_boots.name = "BurningBoots"
	add_child(_boots)
	var side := _direction.cross(Vector3.UP).normalized()
	_flame_shader = Shader.new()
	_flame_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 flame_color : source_color;
void vertex() {
	float height = UV.y;
	VERTEX.x += sin(TIME * 32.0 + height * 12.0) * 0.04 * height;
	VERTEX.z += cos(TIME * 27.0 + height * 9.0) * 0.03 * height;
}
void fragment() {
	float flicker = 0.7 + 0.3 * sin(UV.x * 23.0 + UV.y * 15.0 - TIME * 34.0);
	ALBEDO = flame_color.rgb;
	EMISSION = flame_color.rgb * 1.3;
	ALPHA = flame_color.a * flicker;
}
"""
	for sign_value in [-1.0, 1.0]:
		var boot := Node3D.new()
		_boots.add_child(boot)
		boot.position = side * float(sign_value) * 0.28 + Vector3.UP * 0.20
		for layer in range(4):
			var cone := CylinderMesh.new()
			cone.top_radius = 0.004
			cone.bottom_radius = 0.17 if layer == 0 else 0.085
			cone.height = 0.82 if layer == 0 else 0.58 + float(layer % 2) * 0.14
			cone.radial_segments = 9
			cone.rings = 4
			var color := Color("#ff6514") if layer == 0 else Color("#ffda59")
			var flame := _mesh(boot, cone, color, 0.65)
			var flame_material := ShaderMaterial.new()
			flame_material.shader = _flame_shader
			flame_material.set_shader_parameter("flame_color", Color(color.r, color.g, color.b, 0.45 if layer == 0 else 0.55))
			flame.material_override = flame_material
			flame.position = -_direction * 0.18 + side * (float(layer - 2) * 0.06 if layer > 0 else 0.0) + Vector3.UP * (0.15 + float(layer % 2) * 0.07)
			flame.quaternion = Quaternion(Vector3.UP, (-_direction + Vector3.UP * (0.55 + float(layer) * 0.17)).normalized())
			_flames.append(flame)
	_update_boots()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME or not is_instance_valid(_actor):
		queue_free()
		return
	var progress := _age / LIFETIME
	_ring.scale = Vector3.ONE * lerpf(0.2, 1.85, progress)
	_ring.scale.y = 0.07
	_alpha(_ring, (1.0 - progress) * 0.9)
	_flash.scale = Vector3(1.5, 0.6, 1.5) * (0.4 + minf(_age / 0.12, 1.0))
	_alpha(_flash, maxf(0.0, 1.0 - _age / 0.18) * 0.8)
	for ember in _embers:
		ember.position += Vector3(ember.get_meta("velocity")) * delta
		ember.scale *= maxf(0.0, 1.0 - delta * 1.8)
		_alpha(ember, 1.0 - progress)
	_update_boots()
	for index in range(_flames.size()):
		_flames[index].scale = Vector3.ONE * (0.90 + sin(_age * 95.0 + index * 2.1) * 0.14)


func _update_boots() -> void:
	_boots.global_position = _actor.global_position
	var active := false
	if is_instance_valid(_dash_state):
		active = bool(_dash_state.call("is_dash_active")) if _dash_state.has_method("is_dash_active") else bool(_dash_state.call("is_dashing"))
	if _dash_revision >= 0:
		active = active and int(_actor.get("_dash_token")) == _dash_revision
	_boots.visible = active and _age <= 0.18


func _mesh(parent: Node3D, mesh: Mesh, color: Color, alpha: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	visual.material_override = material
	parent.add_child(visual)
	return visual


func _alpha(visual: MeshInstance3D, value: float) -> void:
	var material := visual.material_override as StandardMaterial3D
	material.albedo_color.a = value
