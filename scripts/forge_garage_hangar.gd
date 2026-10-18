extends Node3D

## Static dressing for one continuous workshop and its exterior window view.
## Shared batches only: no picking, physics, or per-frame scenery work.
const FINISHES := preload("res://scripts/forge_workshop_materials.gd")
const FLOOR_TOP := -0.018
var _surfaces: Dictionary = {}
var _boxes: Dictionary = {}


func _ready() -> void:
	_surfaces["concrete"] = FINISHES.surface("concrete", Color("#807d73"), 0.0, 1.0)
	_surfaces["floor"] = FINISHES.surface("concrete", Color("#77756e"), 0.0, 1.0)
	_surfaces["joints"] = FINISHES.surface("plain", Color("#41433e"), 0.0, 1.0)
	_surfaces["steel"] = FINISHES.surface("dark", Color("#303835"), 0.3, 0.92)
	_surfaces["edge"] = FINISHES.surface("edge", Color("#626964"), 0.4, 0.9)
	_surfaces["wood"] = FINISHES.surface("wood", Color("#97754d"), 0.0, 1.0)
	_surfaces["cases"] = FINISHES.surface("steel", Color("#555b48"), 0.2, 0.94)
	for profile in [["lamp", Color("#ffba6d")], ["yard_near", Color("#9a8b73")], ["yard_far", Color("#b9a58a")]]:
		var material := StandardMaterial3D.new()
		material.albedo_color = profile[1]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_surfaces[profile[0]] = material
	_floor()
	_room()
	_side_workbenches()
	_exterior()
	_commit_batches()


func _floor() -> void:
	_box("floor", Vector3(0, FLOOR_TOP - 0.12, -8), Vector3(76, 0.24, 96))
	# The original 19 x 16 slab shares the same level and two-metre joint grid.
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


func _room() -> void:
	# The matching right return is WorkshopRightWall. The back wall and roof
	# are authored in workshop.glb; do not put a second hall behind them.
	_box("concrete", Vector3(-18, 5.8, 17.1), Vector3(0.40, 11.6, 46.0))
	# Rear-facing socket close-ups look toward this front return, rather than
	# an empty background beyond the camera's normal overview position.
	_box("concrete", Vector3(0, 5.8, 40.0), Vector3(36, 11.6, 0.40))
	_box("cases", Vector3(0, 2.37, 39.78), Vector3(35.6, 0.23, 0.035))
	for x in [-17.6, -12.5, -7.8, -3.5, 0.6, 6.8, 12.5, 17.6]:
		_box("steel", Vector3(x, 5.8, 39.7), Vector3(0.24, 11.6, 0.16))
	for side in [-1.0, 1.0]:
		for z in [-4.8, 2.8, 10.4, 18.0, 25.6, 33.2, 39.5]:
			if side < 0:
				_box("steel", Vector3(side * 17.73, 5.8, z), Vector3(0.16, 11.6, 0.24))
			_box("concrete", Vector3(side * 17.60, 0.20, z), Vector3(0.68, 0.4, 0.72))
		for x in [10.5, 15.3]:
			var point := Vector3(side * x, 4.2, -5.05)
			_box("steel", point, Vector3(0.28, 0.65, 0.16))
			_box("lamp", point + Vector3(0, 0, 0.10), Vector3(0.12, 0.43, 0.045))
		var pool := OmniLight3D.new()
		pool.name = "SideWorkshopLampLeft" if side < 0 else "SideWorkshopLampRight"
		pool.position = Vector3(side * 11.5, 5.5, -2.8)
		pool.light_color = Color("#ffd09a")
		pool.light_energy = 2.6
		pool.omni_range = 10.0
		pool.shadow_enabled = false
		add_child(pool)


func _side_workbenches() -> void:
	# Neighboring work surfaces now share the actual exterior wall and floor.
	for side in [-1.0, 1.0]:
		var x: float = side * 12.0
		_box("wood", Vector3(x, 1.15, -4.25), Vector3(3.3, 0.15, 0.95))
		for offset in [-1.4, 1.4]:
			_box("steel", Vector3(x + offset, 0.55, -4.25), Vector3(0.13, 1.1, 0.70))
		_box("steel", Vector3(x, 0.35, -4.25), Vector3(3.05, 0.05, 0.82))
		_box("cases", Vector3(x - side * 0.8, 0.65, -4.25), Vector3(1.0, 0.85, 0.80))
		for drawer in 4:
			_box("steel", Vector3(x - side * 0.8, 0.32 + drawer * 0.20, -3.83), Vector3(0.89, 0.17, 0.04))
			_box("edge", Vector3(x - side * 0.8, 0.32 + drawer * 0.20, -3.79), Vector3(0.40, 0.03, 0.04))
		_box("cases", Vector3(x, 2.7, -5.18), Vector3(2.8, 1.2, 0.07))
		for tool in 6:
			var tool_x: float = x - 1.05 + tool * 0.40
			_box("edge", Vector3(tool_x, 2.65, -5.08), Vector3(0.04, 0.40 + (tool % 3) * 0.11, 0.045))
			_box("steel", Vector3(tool_x, 2.85, -5.04), Vector3(0.16, 0.08, 0.045))
		_box("steel", Vector3(x, 3.7, -5.10), Vector3(2.3, 0.18, 0.20))
		_box("lamp", Vector3(x, 3.65, -4.95), Vector3(1.7, 0.035, 0.035))
		_box("cases", Vector3(x + side * 2.2, 0.48, -4.3), Vector3(1.0, 0.96, 0.85))
		_box("cases", Vector3(x + side * 2.2, 1.22, -4.3), Vector3(0.9, 0.52, 0.75))


func _exterior() -> void:
	# An actual depth gap separates the glass at z=-5.64 from this quiet yard.
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("#b1bec0"), Color("#f4d6a3")])
	var sky_texture := GradientTexture2D.new()
	sky_texture.gradient = gradient
	sky_texture.fill_from = Vector2(0.5, 0.0)
	sky_texture.fill_to = Vector2(0.5, 1.0)
	var sky_material := StandardMaterial3D.new()
	sky_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_material.albedo_texture = sky_texture
	var sky := MeshInstance3D.new()
	sky.name = "ExteriorSky"
	var plane := QuadMesh.new()
	plane.size = Vector2(100, 60)
	sky.mesh = plane
	sky.material_override = sky_material
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky.position = Vector3(3, 12, -36)
	add_child(sky)
	for profile in [[-11.0, 3.4, -26.0, 7.0], [-3.0, 4.7, -29.0, 5.0], [6.0, 2.9, -24.0, 7.0], [15.0, 5.2, -30.0, 6.0]]:
		var x: float = profile[0]
		var height: float = profile[1]
		var z: float = profile[2]
		var width: float = profile[3]
		_box("yard_far", Vector3(x, height / 2, z), Vector3(width, height, 4))
		_box("yard_far", Vector3(x + 0.8, height + 0.4, z), Vector3(1.1, 0.8, 1.0))
	for x in [-4.5, 9.5]:
		_box("yard_near", Vector3(x, 2.0, -17), Vector3(3.5, 4.0, 4.5))
		_box("yard_near", Vector3(x + 0.6, 4.5, -17), Vector3(0.40, 1.0, 0.40))


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
