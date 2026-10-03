extends Node3D

## Static extension of the garage set. Shared cube batches, no picking or physics.
const FINISHES := preload("res://scripts/forge_workshop_materials.gd")
const FLOOR_TOP := -0.018 # Original slab top is -0.015: no coplanar surfaces.
var _surfaces: Dictionary = {}
var _boxes: Dictionary = {}


func _ready() -> void:
	_surfaces["concrete"] = FINISHES.surface("concrete", Color("#7b7b70"), 0.0, 1.0)
	_surfaces["joints"] = FINISHES.surface("plain", Color("#414744"), 0.0, 1.0)
	_surfaces["steel"] = FINISHES.surface("steel", Color("#1d2a34"), 0.3, 0.92)
	_surfaces["edge"] = FINISHES.surface("edge", Color("#34414c"), 0.4, 0.9)
	_surfaces["wall"] = FINISHES.surface("steel", Color("#192732"), 0.2, 0.95)
	# Low diffuse emission suggests distant ambient haze without fog volumes.
	var wall := _surfaces["wall"] as StandardMaterial3D
	wall.emission_enabled = true
	wall.emission = Color("#364b5b")
	wall.emission_energy_multiplier = 0.035
	_surfaces["wood"] = FINISHES.surface("wood", Color("#655039"), 0.0, 1.0)
	_surfaces["cases"] = FINISHES.surface("steel", Color("#495044"), 0.2, 0.94)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("#bf853e")
	lamp.emission_enabled = true
	lamp.emission = Color("#ff9f49")
	lamp.emission_energy_multiplier = 0.85
	_surfaces["lamp"] = lamp
	_floor()
	_shell()
	_neighboring_bays()
	_commit_batches()


func _floor() -> void:
	_box("concrete", Vector3(0, FLOOR_TOP - 0.12, -8), Vector3(76, 0.24, 96))
	# Continue the existing two-metre joints outside its 19 x 16 metre slab.
	for x in range(-36, 37, 2):
		if absf(x) > 9.5:
			_box("joints", Vector3(x, FLOOR_TOP + 0.001, -8), Vector3(0.018, 0.002, 96))
		else:
			_box("joints", Vector3(x, FLOOR_TOP + 0.001, 24), Vector3(0.018, 0.002, 32))
			_box("joints", Vector3(x, FLOOR_TOP + 0.001, -32), Vector3(0.018, 0.002, 48))
	for z in range(-54, 41, 2):
		if absf(z) >= 8.0:
			_box("joints", Vector3(0, FLOOR_TOP + 0.001, z), Vector3(76, 0.002, 0.018))
		else:
			for side in [-1.0, 1.0]:
				_box("joints", Vector3(side * 23.75, FLOOR_TOP + 0.001, z), Vector3(28.5, 0.002, 0.018))


func _shell() -> void:
	_box("wall", Vector3(0, 7, -24), Vector3(76, 14, 0.25))
	_box("wall", Vector3(0, 14, -4), Vector3(76, 0.20, 80))
	for side in [-1.0, 1.0]:
		_box("wall", Vector3(side * 37, 7, -4), Vector3(0.25, 14, 80))
	# Freestanding I-section pillars frame the bay without obstructing its aisle.
	for x in [-27.0, -19.0, -12.0, 12.0, 19.0, 27.0]:
		for z in [-3.0, -16.0]:
			_box("steel", Vector3(x, 6.9, z), Vector3(0.24, 13.8, 0.64))
			for dz in [-0.34, 0.34]:
				_box("edge", Vector3(x, 6.9, z + dz), Vector3(0.7, 13.8, 0.10))
			_box("concrete", Vector3(x, 0.22, z), Vector3(1.05, 0.45, 1.0))
			_box("steel", Vector3(x, 0.48, z), Vector3(0.85, 0.07, 0.85))
	for z in [-3.0, -16.0]:
		_box("steel", Vector3(0, 10.7, z), Vector3(74, 0.4, 0.55))
		_box("steel", Vector3(0, 13.5, z), Vector3(74, 0.35, 0.55))
	# A remote service walkway adds a second depth plane above the neighboring bays.
	_box("steel", Vector3(0, 6.8, -21.5), Vector3(70, 0.16, 1.0))
	for y in [7.35, 7.95]:
		_box("edge", Vector3(0, y, -20.97), Vector3(70, 0.045, 0.045))
	for x in range(-33, 34, 3):
		_box("edge", Vector3(x, 7.4, -20.97), Vector3(0.045, 1.05, 0.045))
	for x in [-27.0, -19.0, -12.0, 12.0, 19.0, 27.0]:
		_box("steel", Vector3(x, 13.4, -4), Vector3(0.24, 0.45, 77))
	# Broad distant panel seams: fewer details and lower contrast than the workshop.
	for x in range(-34, 35, 3):
		_box("steel", Vector3(x, 6.7, -23.8), Vector3(0.06, 13, 0.08))
	_box("steel", Vector3(0, 6.4, -23.7), Vector3(74, 0.18, 0.15))
	for x in [-19.0, -12.0, 12.0, 19.0]:
		_lamp(Vector3(x, 4.1, -2.57), true)
		if absf(x) == 12.0:
			var pool := OmniLight3D.new()
			pool.name = "ColumnLampLeft" if x < 0 else "ColumnLampRight"
			pool.position = Vector3(x, 4.0, -2.2)
			pool.light_color = Color("#ffbc76")
			pool.light_energy = 0.65
			pool.omni_range = 4.0
			pool.shadow_enabled = false
			add_child(pool)
	for x in [-24.0, -15.0, -5.0, 5.0, 15.0, 24.0]:
		_lamp(Vector3(x, 8.2, -23.5), false)


func _neighboring_bays() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 13.0
		_box("wall", Vector3(x, 2.8, -10.5), Vector3(6.8, 5.6, 0.16))
		_box("steel", Vector3(x, 5.6, -10.35), Vector3(7.4, 0.23, 0.25))
		for offset in [-3.4, 3.4]:
			_box("steel", Vector3(x + offset, 2.8, -10.35), Vector3(0.18, 5.6, 0.25))
		_box("wood", Vector3(x, 1.15, -8.6), Vector3(3.3, 0.15, 0.95))
		for offset in [-1.4, 1.4]:
			_box("steel", Vector3(x + offset, 0.55, -8.6), Vector3(0.13, 1.1, 0.70))
			_box("edge", Vector3(x + offset, 0.08, -8.6), Vector3(0.28, 0.06, 0.78))
		_box("steel", Vector3(x, 0.35, -8.6), Vector3(3.05, 0.05, 0.82))
		# A cabinet, bench vice and differentiated hanging tools read at distance.
		_box("cases", Vector3(x - side * 0.8, 0.65, -8.6), Vector3(1.0, 0.85, 0.80))
		for drawer in 4:
			_box("steel", Vector3(x - side * 0.8, 0.32 + drawer * 0.20, -8.18), Vector3(0.89, 0.17, 0.04))
			_box("edge", Vector3(x - side * 0.8, 0.32 + drawer * 0.20, -8.14), Vector3(0.40, 0.03, 0.04))
		_box("edge", Vector3(x + side * 1.0, 1.32, -8.4), Vector3(0.48, 0.24, 0.28))
		_box("steel", Vector3(x + side * 1.0, 1.45, -8.4), Vector3(0.42, 0.04, 0.34))
		_box("cases", Vector3(x, 2.7, -10.25), Vector3(2.8, 1.2, 0.07))
		for tool in 6:
			var tool_x: float = x - 1.05 + tool * 0.40
			var height: float = 0.40 + (tool % 3) * 0.11
			_box("edge", Vector3(tool_x, 2.65, -10.17), Vector3(0.04, height, 0.045))
			_box("steel", Vector3(tool_x, 2.85, -10.13), Vector3(0.16 if tool % 2 == 0 else 0.09, 0.08, 0.045))
		_box("cases", Vector3(x + side * 2.3, 0.47, -8.7), Vector3(1.15, 0.95, 0.85))
		_box("cases", Vector3(x + side * 2.3, 1.24, -8.7), Vector3(1.0, 0.58, 0.75))
		for offset in [-0.35, 0.35]:
			_box("edge", Vector3(x + side * 2.3 + offset, 0.47, -8.25), Vector3(0.09, 0.16, 0.04))
			_box("edge", Vector3(x + side * 2.3 + offset, 1.24, -8.30), Vector3(0.07, 0.12, 0.04))
		_box("steel", Vector3(x + side * 2.3, 0.88, -8.7), Vector3(1.19, 0.06, 0.89))
		_box("steel", Vector3(x + side * 2.3, 1.56, -8.7), Vector3(1.05, 0.05, 0.80))
		# Painted bay boundaries and wall cable runs keep this part of the hangar
		# coherent with the detailed foreground, in the same eight static batches.
		for offset in [-3.6, 3.6]:
			_box("cases", Vector3(x + offset, FLOOR_TOP + 0.003, -6.5), Vector3(0.055, 0.004, 7.3))
		_box("steel", Vector3(x, 4.6, -10.2), Vector3(6.5, 0.065, 0.085))
		_box("edge", Vector3(x - side * 2.9, 3.1, -10.17), Vector3(0.06, 3.0, 0.08))
		_box("steel", Vector3(x - side * 2.9, 1.7, -10.02), Vector3(0.45, 0.66, 0.25))
		_box("steel", Vector3(x, 3.7, -10.3), Vector3(2.3, 0.18, 0.20))
		_box("lamp", Vector3(x, 3.65, -10.15), Vector3(1.7, 0.035, 0.035))
		var pool := OmniLight3D.new()
		pool.name = "DistantBayLampLeft" if side < 0 else "DistantBayLampRight"
		pool.position = Vector3(x, 3.2, -9.3)
		pool.light_color = Color("#ffc58a")
		pool.light_energy = 1.5
		pool.omni_range = 5.0
		pool.shadow_enabled = false
		add_child(pool)


func _lamp(pos: Vector3, vertical: bool) -> void:
	_box("steel", pos, Vector3(0.25, 0.6, 0.16) if vertical else Vector3(0.65, 0.2, 0.18))
	_box("lamp", pos + Vector3(0, 0, 0.10), Vector3(0.10, 0.39, 0.045) if vertical else Vector3(0.41, 0.06, 0.045))


func _box(surface: String, pos: Vector3, dimensions: Vector3) -> void:
	if not _boxes.has(surface):
		_boxes[surface] = []
	_boxes[surface].append(Transform3D(Basis.from_scale(dimensions), pos))


func _commit_batches() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	for surface: String in _boxes:
		var transforms: Array = _boxes[surface]
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = cube
		instances.instance_count = transforms.size()
		for index in transforms.size():
			instances.set_instance_transform(index, transforms[index])
		var batch := MultiMeshInstance3D.new()
		batch.name = "Hangar_" + surface
		batch.multimesh = instances
		batch.material_override = _surfaces[surface]
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
	_boxes.clear()
