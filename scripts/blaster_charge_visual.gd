extends Node3D
## Reusable muzzle effect. Animation follows simulation time and owns no combat state.

var _phase := 0.0
var _core: MeshInstance3D
var _aura: MeshInstance3D
var _coils: Array[MeshInstance3D] = []
var _motes: Array[MeshInstance3D] = []
var _arcs: Array[MeshInstance3D] = []
var _core_material: StandardMaterial3D
var _energy_material: StandardMaterial3D
var _aura_material: StandardMaterial3D


func _ready() -> void:
	_core_material = _material(Color("#a4efff"), 0.8)
	_energy_material = _material(Color("#49dfff"), 0.55)
	_aura_material = _material(Color("#49bfff"), 0.12)
	_aura_material.emission_energy_multiplier = 0.3
	# Keep a cyan center even against the arena's bright sand and lighting.
	_core_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_core_material.emission_enabled = false
	_energy_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_energy_material.emission_enabled = false
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_core = _mesh("ChargeCore", sphere, _core_material)
	_core.position.z = -0.04
	_aura = _mesh("ChargeAura", sphere, _aura_material)
	_aura.position.z = -0.05
	var ring := TorusMesh.new()
	ring.inner_radius = 0.87
	ring.outer_radius = 1.0
	ring.rings = 8
	ring.ring_segments = 24
	for index in 3:
		var coil := _mesh("ChargeCoil%d" % index, ring, _energy_material)
		coil.rotation.x = PI * 0.5
		_coils.append(coil)
	var mote := BoxMesh.new()
	mote.size = Vector3.ONE
	for index in 12:
		_motes.append(_mesh("ChargeIntake%d" % index, mote, _core_material))
	for index in 3:
		_arcs.append(_mesh("OverloadArc%d" % index, ImmediateMesh.new(), _core_material))
	visible = false


func set_charge(active: bool, charge: float, delta: float) -> void:
	visible = active
	if not active:
		_phase = 0.0
		return
	var power := clampf(charge, 0.0, 1.0)
	var buildup := power * power
	_phase += maxf(0.0, delta) * lerpf(10.0, 42.0, buildup)
	var pulse := 0.5 + 0.5 * sin(_phase)
	var full := smoothstep(0.80, 1.0, power)
	var energy := Color("#36cbe9").lerp(Color("#91b7ff"), buildup).lerp(Color("#d2faff"), full * 0.65)
	_energy_material.albedo_color = Color(energy, 0.25 + power * 0.40 + pulse * full * 0.12)
	_core_material.albedo_color = Color(Color("#56d8ff").lerp(Color("#d3faff"), full * (0.45 + pulse * 0.20)), 0.60 + buildup * 0.35)
	_aura_material.albedo_color = Color(energy, 0.06 + buildup * 0.10 + pulse * full * 0.04)
	_aura_material.emission = energy
	_core.scale = Vector3.ONE * (0.07 + power * 0.12 + buildup * 0.13 + pulse * buildup * 0.035)
	_aura.scale = Vector3.ONE * (0.18 + power * 0.30 + pulse * buildup * 0.06)
	for index in _coils.size():
		var coil := _coils[index]
		var flow := fposmod(_phase * 0.11 + float(index) / 3.0, 1.0)
		var radius := 0.15 + power * 0.10 + sin(_phase + index * 2.0) * buildup * 0.018
		coil.scale = Vector3(radius, 0.035 + buildup * 0.025, radius)
		# Bands run along the barrel into the muzzle, tightening as power builds.
		coil.position.z = (1.0 - flow) * 0.48
		coil.rotation.y = sin(_phase * 0.3 + index) * buildup * 0.16
	for index in _motes.size():
		var mote_node := _motes[index]
		mote_node.visible = index < 3 + roundi(power * 9.0)
		var travel := fposmod(_phase * 0.085 + float(index) / 12.0, 1.0)
		var angle := float(index) * 2.39996 + _phase * 0.12
		var radius := (0.30 + power * 0.28) * (1.0 - travel)
		mote_node.position = Vector3(cos(angle) * radius, sin(angle) * radius, -0.65 * (1.0 - travel))
		var thickness := (0.009 + buildup * 0.016) * sin(travel * PI)
		mote_node.scale = Vector3(thickness, thickness, thickness * (2.0 + power * 2.0))
		mote_node.look_at(global_position + global_basis * Vector3(0, 0, 0.04), global_basis.y)
	for index in _arcs.size():
		var arc := _arcs[index]
		arc.visible = power > 0.60 and (full > 0.8 or sin(_phase * 0.55 + index * 2.1) > 0.1)
		if arc.visible:
			_update_arc(arc.mesh as ImmediateMesh, index, power)


func _update_arc(mesh: ImmediateMesh, index: int, power: float) -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var angle := index * TAU / 3.0 + _phase * 0.10
	var previous := Vector3(cos(angle) * 0.18, sin(angle) * 0.18, 0.48)
	for segment in range(1, 9):
		var progress := float(segment) / 8.0
		var jagged := sin(segment * 3.7 + _phase * 1.7 + index) * 0.065 * power
		var radius := lerpf(0.18, 0.08, progress) + jagged
		var point := Vector3(cos(angle + jagged) * radius, sin(angle + jagged) * radius, 0.48 * (1.0 - progress))
		for axis in [Vector3.RIGHT, Vector3.UP]:
			var width: Vector3 = axis * (0.008 + power * 0.007)
			for vertex in [previous - width, previous + width, point + width, previous - width, point + width, point - width]:
				mesh.surface_add_vertex(vertex)
		previous = point
	mesh.surface_end()


func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	return material


func _mesh(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node
