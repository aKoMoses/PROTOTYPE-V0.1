extends Node3D

## Shared electric trident. Geometry stays bounded during an indefinite hold.
var _power := 0.0
var _charging := false
var _clock := 0.0
var _trident: Node3D
var _halo: MeshInstance3D
var _guide: MeshInstance3D
var _arcs := ImmediateMesh.new()
var _arc_material: StandardMaterial3D
var _core_material: StandardMaterial3D


func configure(charging: bool) -> void:
	_charging = charging
	_core_material = _material(Color("#e3ffff"), 3.2)
	var shell := _material(Color("#219ace"), 1.5)
	_arc_material = _material(Color("#87f7ff"), 3.0)
	_trident = Node3D.new()
	_trident.name = "ElectricTrident"
	add_child(_trident)
	_segment(_trident, Vector3(0, 0, 0.65), Vector3(0, 0, -0.65), 0.045, shell)
	_segment(_trident, Vector3(0, 0, 0.50), Vector3(0, 0, -0.85), 0.017, _core_material)
	for side in [-1.0, 1.0]:
		_segment(_trident, Vector3(0, 0, -0.18), Vector3(side * 0.28, 0, -0.43), 0.035, shell)
		_segment(_trident, Vector3(side * 0.28, 0, -0.43), Vector3(side * 0.28, 0, -0.97), 0.027, _core_material)
	for x in [-0.28, 0.0, 0.28]:
		var tip := MeshInstance3D.new()
		tip.name = "TridentProng%d" % roundi((x + 0.28) * 100.0)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.067 if x == 0.0 else 0.055
		cone.height = 0.30
		cone.radial_segments = 8
		tip.mesh = cone
		tip.rotation.x = -PI * 0.5
		tip.position = Vector3(x, 0, -1.10 if x == 0.0 else -1.02)
		tip.material_override = _core_material
		_trident.add_child(tip)
	_halo = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.25
	ring.outer_radius = 0.28
	ring.rings = 20
	ring.ring_segments = 8
	_halo.mesh = ring
	_halo.rotation.x = PI * 0.5
	_halo.material_override = _material(Color(0.25, 0.83, 1.0, 0.6), 2.0)
	add_child(_halo)
	var electricity := MeshInstance3D.new()
	electricity.name = "ElectricArcs"
	electricity.mesh = _arcs
	add_child(electricity)
	if charging:
		_guide = MeshInstance3D.new()
		_guide.name = "ChargeRangeGuide"
		_guide.mesh = BoxMesh.new()
		_guide.material_override = _material(Color(0.24, 0.86, 1.0, 0.3), 1.3)
		add_child(_guide)
	set_power(0.0, 8.0)


func set_power(power: float, shot_range: float) -> void:
	_power = clampf(power, 0.0, 1.0)
	if _trident == null:
		return
	_trident.scale = Vector3.ONE * (0.75 + _power * 0.50)
	_core_material.emission_energy_multiplier = 2.0 + _power * 4.0
	if _guide != null:
		(_guide.mesh as BoxMesh).size = Vector3(0.025 + _power * 0.025, 0.012, shot_range)
		_guide.position = Vector3(0.0, -1.17, -shot_range * 0.5)


func _process(delta: float) -> void:
	if _trident == null:
		return
	_clock += delta
	var pulse := 1.0 + sin(_clock * (7.0 + _power * 16.0)) * (0.025 + _power * 0.04)
	_halo.scale = Vector3.ONE * pulse * (0.8 + _power * 1.5)
	_halo.position.z = sin(_clock * 5.0) * 0.30 if _charging else 0.5
	_arcs.clear_surfaces()
	_arcs.surface_begin(Mesh.PRIMITIVE_LINES, _arc_material)
	# Several zigzags run between the three prongs and converge into the core.
	for strand in range(3 + roundi(_power * 4.0)):
		var phase := _clock * (18.0 + _power * 22.0) + strand * 2.4
		var previous := Vector3(0.0, 0.0, 0.5)
		for step in range(1, 9):
			var t := float(step) / 8.0
			var spread := (0.12 + _power * 0.22) * sin(t * PI)
			var point := Vector3(sin(phase + step * 2.1) * spread, cos(phase * 1.3 + step * 1.7) * spread * 0.6, lerpf(0.5, -1.15, t))
			if step == 8:
				point.x = (float(strand % 3) - 1.0) * 0.28
			_arcs.surface_add_vertex(previous)
			_arcs.surface_add_vertex(point)
			previous = point
	if not _charging:
		for side in [-1.0, 1.0]:
			_arcs.surface_add_vertex(Vector3(side * 0.15, 0, 0.3))
			_arcs.surface_add_vertex(Vector3(side * 0.06, 0, 1.4 + _power * 1.1))
	_arcs.surface_end()


func _segment(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 8
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	visual.position = (start + end) * 0.5
	visual.basis = Basis.looking_at((end - start).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)


func _material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
