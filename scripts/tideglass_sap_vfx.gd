extends Node3D

## Small reusable meshes, no lights or independent timers. The sap controller
## supplies round time and visibility, so fog, pause and reset remain authoritative.
const JADE := Color("#53f7c7")
const GOLD := Color("#ffcd64")
const ENERGY := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.3, 1.0, 0.75, 1.0);
uniform float clock = 0.0;
uniform float progress = 1.0;
uniform float intensity = 1.0;
uniform float visibility_weight = 1.0;
uniform float segments = 20.0;
void fragment() {
    if (UV.x > progress) { discard; }
    float edge = pow(max(0.0, sin(UV.y * 3.14159)), 0.55);
    float dash = mix(0.25, 1.0, smoothstep(0.08, 0.20, fract(UV.x * segments)));
    float flow = 0.72 + 0.28 * sin(UV.x * 28.0 - clock * 5.0);
    ALBEDO = tint.rgb * (1.0 + flow * 0.65);
    ALPHA = edge * dash * flow * intensity * visibility_weight;
}
"""

var _ground: MeshInstance3D
var _ribbons: MeshInstance3D
var _burst: MeshInstance3D
var _seed: Node3D
var _weapon: Node3D
var _motes: MultiMeshInstance3D
var _energy_materials: Array[ShaderMaterial] = []
var _solid_materials: Array[StandardMaterial3D] = []
var _shader: Shader
var _phase := ""
var _phase_started := 0.0

func configure() -> void:
	_shader = Shader.new()
	_shader.code = ENERGY
	_ground = _mesh(self, "DurationHalo", _band(1.16, 0.10), _energy(JADE))
	_ribbons = _mesh(self, "LivingSapFilaments", _helix(), _energy(JADE))
	_burst = _mesh(self, "ActivationWave", _band(1.0, 0.14), _energy(GOLD))
	_seed = Node3D.new()
	_seed.name = "CarriedSeed"
	add_child(_seed)
	var core := SphereMesh.new()
	core.radius = 0.23
	core.height = 0.46
	core.radial_segments = 12
	core.rings = 5
	_mesh(_seed, "GoldenHeart", core, _solid(GOLD))
	var leaf := PrismMesh.new()
	leaf.size = Vector3(0.15, 0.85, 0.34)
	for index in range(3):
		var angle := float(index) * TAU / 3.0
		var petal := _mesh(_seed, "SapPetal", leaf, _solid(JADE))
		petal.position = Vector3(cos(angle) * 0.32, 0, sin(angle) * 0.32)
		petal.rotation = Vector3(0.25, -angle, 0.30)
	_weapon = Node3D.new()
	_weapon.name = "EmpoweredWeapon"
	add_child(_weapon)
	for index in range(2):
		var band := _mesh(_weapon, "WeaponCorona", _band(0.24 + index * 0.055, 0.035), _energy(GOLD if index == 0 else JADE))
		band.position.y = -float(index) * 0.22
	var spark := SphereMesh.new()
	spark.radius = 1.0
	spark.height = 2.0
	spark.radial_segments = 4
	spark.rings = 1
	_motes = MultiMeshInstance3D.new()
	_motes.name = "SapSparks"
	_motes.multimesh = MultiMesh.new()
	_motes.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_motes.multimesh.mesh = spark
	_motes.multimesh.instance_count = 14
	_motes.material_override = _solid(GOLD)
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)

func update_effect(actor: Node3D, phase: String, remaining: float, clock: float, water: float, weight: float = 1.0) -> void:
	if phase != _phase:
		_phase = phase
		_phase_started = clock
	visible = weight > 0.01
	if not visible:
		return
	var pickup := phase == "pickup"
	var active := phase == "active"
	var age := maxf(0.0, clock - _phase_started)
	var fade := minf(1.0, remaining) if not pickup else 1.0
	var progress := clampf(remaining / (10.0 if active else 15.0), 0.0, 1.0) if not pickup else 1.0
	if is_instance_valid(actor):
		global_position = actor.global_position
	var ground_y := maxf(0.0, water - global_position.y) + 0.045
	_ground.position.y = ground_y
	_ground.scale = Vector3.ONE * (1.0 if active or pickup else 0.65)
	(_ground.material_override as ShaderMaterial).set_shader_parameter("progress", progress)
	_ribbons.visible = active or pickup
	_ribbons.rotation.y = -clock * 1.8
	_ribbons.scale = Vector3.ONE * (0.78 if pickup else 1.0)
	_ribbons.position.y = ground_y
	_seed.visible = not active
	_seed.position = Vector3(0, water + 1.05, 0) if pickup else Vector3(cos(clock * 2.0) * 0.85, 1.45 + sin(clock * 3.0) * 0.10, sin(clock * 2.0) * 0.85)
	_seed.rotation = Vector3(sin(clock) * 0.15, clock * 1.8, 0)
	_seed.scale = Vector3.ONE * (1.0 if pickup else 0.55)
	_burst.visible = not pickup and age < 0.70
	_burst.position.y = ground_y + 0.02
	_burst.scale = Vector3.ONE * lerpf(0.5, 2.6 if active else 1.5, clampf(age / 0.70, 0, 1))
	_weapon.visible = active
	if active and is_instance_valid(actor):
		_weapon.global_position = actor.call("get_passive_weapon_point") if actor.has_method("get_passive_weapon_point") else actor.global_position + Vector3.UP
		var direction: Vector3 = actor.get("aim_direction") if "aim_direction" in actor else -actor.global_basis.z
		if direction.length_squared() > 0.001:
			_weapon.quaternion = Quaternion(Vector3.UP, direction.normalized())
		_weapon.rotate_object_local(Vector3.UP, clock * 2.3)
	for material in _energy_materials:
		material.set_shader_parameter("clock", clock)
		material.set_shader_parameter("visibility_weight", weight)
		material.set_shader_parameter("intensity", fade * (0.8 if active or pickup else 0.45))
	(_burst.material_override as ShaderMaterial).set_shader_parameter("intensity", maxf(0.0, 1.0 - age / 0.70))
	for material in _solid_materials:
		var color := material.albedo_color
		color.a = weight * fade
		material.albedo_color = color
	_motes.multimesh.visible_instance_count = 14 if active or pickup else 6
	for index in range(_motes.multimesh.visible_instance_count):
		var t := float(index) / 14.0
		var lift := fposmod(t + clock * 0.42, 1.0)
		var angle := t * TAU * 2.0 - clock * 2.5
		var radius := (0.72 + lift * 0.25) if active or pickup else 0.55
		var at := Vector3(cos(angle) * radius, ground_y + 0.15 + lift * (2.0 if active or pickup else 1.5), sin(angle) * radius)
		var size := 0.025 + sin(lift * PI) * 0.035
		_motes.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3(size, size * 2.3, size)), at))

func _energy(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("tint", color)
	_energy_materials.append(material)
	return material

func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.3
	_solid_materials.append(material)
	return material

func _mesh(parent: Node3D, label: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _band(radius: float, width: float) -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(64):
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			var t: float = (float(index) + corner.x) / 64.0
			var angle: float = t * TAU
			var r: float = radius + (corner.y - 0.5) * width
			builder.set_uv(Vector2(t, corner.y))
			builder.add_vertex(Vector3(cos(angle) * r, 0, sin(angle) * r))
	builder.generate_normals()
	return builder.commit()

func _helix() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strand in range(3):
		for index in range(32):
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var t: float = (float(index) + corner.x) / 32.0
				var angle: float = t * TAU * 0.80 + float(strand) * TAU / 3.0
				var radius := 0.75 + sin(t * PI) * 0.15
				builder.set_uv(Vector2(t, corner.y))
				builder.add_vertex(Vector3(cos(angle) * radius, 0.15 + t * 2.1 + (corner.y - 0.5) * 0.085, sin(angle) * radius))
	builder.generate_normals()
	return builder.commit()
