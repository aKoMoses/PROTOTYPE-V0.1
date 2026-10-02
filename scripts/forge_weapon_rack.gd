extends Node3D

## Open workshop rack. Its centered GLBs are the same objects carried to the hand.
const FONT := preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const WEAPONS := ["blaster", "shotgun", "mekatana", "longshot"]
const DISPLAY_LENGTHS := {"blaster": 0.96, "shotgun": 1.04, "mekatana": 1.10, "longshot": 1.10}
const RACK_POSITION := Vector3(-2.55, 0, 3.30)
const RACK_YAW := 16.0
const LOCAL_BOUNDS := AABB(Vector3(-0.95, 0.01, -0.43), Vector3(1.90, 1.67, 0.88))
const ACCENT := Color("#dda963")

var stage
var items: Dictionary = {}
var item_categories: Dictionary = {}
var selected_category := ""
var selected_item := ""
var rack: Node3D
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _trim: StandardMaterial3D
var _light: OmniLight3D
var _title: Label3D
var _slot_trims: Dictionary = {}
var _slot_lights: Dictionary = {}


func configure(garage_stage: Node) -> void:
	stage = garage_stage


func _ready() -> void:
	name = "WeaponStorageRack"
	set_process(false)
	_material("steel", Color("#3a4140"), 0.78, 0.52)
	_material("dark", Color("#242b2b"), 0.65, 0.70)
	_material("edge", Color("#80877e"), 0.82, 0.42)
	_material("ivory", Color("#c4b9a2"), 0.24, 0.67)
	_material("rubber", Color("#171b19"), 0.02, 0.86)
	_trim = _material("accent", ACCENT, 0.38, 0.43)
	_trim.emission_enabled = true
	_trim.emission = ACCENT
	_build_rack()
	highlight("")


func pick(point: Vector2) -> String:
	if stage == null or stage.camera == null or rack == null or not is_visible_in_tree() or not stage.is_visible_in_tree():
		return ""
	if stage.size.x <= 0.0 or stage.size.y <= 0.0 or not Rect2(Vector2.ZERO, stage.size).has_point(point):
		return ""
	if stage.camera.is_position_behind(anchor()):
		return ""
	var screen: Vector2 = point * Vector2(stage.viewport.size) / stage.size
	var origin: Vector3 = stage.camera.project_ray_origin(screen)
	var direction: Vector3 = stage.camera.project_ray_normal(screen)
	var inverse := rack.global_transform.affine_inverse()
	var hit = LOCAL_BOUNDS.intersects_ray(inverse * origin, inverse.basis * direction)
	if hit == null:
		return ""
	var distance := origin.distance_to(rack.global_transform * (hit as Vector3))
	# A rack seen behind the hero must not take a drag meant to turn the hero.
	if stage.robot != null:
		var robot_inverse: Transform3D = stage.robot.global_transform.affine_inverse()
		var robot_hit = stage._robot_pick_bounds.intersects_ray(robot_inverse * origin, robot_inverse.basis * direction)
		if robot_hit != null and origin.distance_to(stage.robot.global_transform * (robot_hit as Vector3)) < distance:
			return ""
	return "weapon"


func anchor(kind: String = "weapon") -> Vector3:
	if kind != "weapon" or rack == null:
		return Vector3.ZERO
	return rack.global_transform * Vector3(0, 1.52, 0.10)


func bounds(kind: String = "weapon") -> AABB:
	if kind != "weapon" or rack == null:
		return AABB()
	return rack.global_transform * LOCAL_BOUNDS


func module_transform(identifier: String) -> Transform3D:
	if not items.has(identifier):
		return Transform3D.IDENTITY
	return (items[identifier] as Node3D).global_transform


func create_payload(identifier: String) -> Node3D:
	if not items.has(identifier):
		return null
	var payload := (items[identifier] as Node3D).duplicate(0) as Node3D
	payload.name = "WeaponPayload_" + identifier
	# Raw GLB axes and centering stay in the child; the transport owns root pose/scale.
	payload.transform = Transform3D.IDENTITY
	payload.visible = true
	return payload


func set_item_visible(identifier: String, value: bool) -> void:
	if items.has(identifier):
		(items[identifier] as Node3D).visible = value


func highlight(category: String) -> void:
	selected_category = "weapon" if category == "weapon" else ""
	var active := selected_category != ""
	if _trim != null:
		_trim.emission_energy_multiplier = 1.25 if active else 0.28
	if _light != null:
		_light.light_energy = 0.48 if active else 0.10
	if _title != null:
		_title.modulate = Color("#29251f")
	if not active:
		highlight_item("")


func highlight_item(identifier: String) -> void:
	selected_item = identifier if items.has(identifier) else ""
	for key in _slot_trims:
		var active: bool = key == selected_item
		var trim := _slot_trims[key] as StandardMaterial3D
		trim.albedo_color = Color("#86c9ce") if active else Color("#777e72")
		trim.emission_energy_multiplier = 1.1 if active else 0.0
		(_slot_lights[key] as OmniLight3D).light_energy = 0.23 if active else 0.0


func _build_rack() -> void:
	rack = Node3D.new()
	rack.name = "Storage_weapon"
	add_child(rack)
	rack.position = RACK_POSITION
	rack.rotation_degrees.y = RACK_YAW
	# Two weighted feet and an open welded frame leave the weapon silhouettes clear.
	for side in [-1.0, 1.0]:
		var x: float = side * 0.865
		_box(rack, Vector3(0.17, 0.09, 0.69), Vector3(x, 0.055, 0), "dark", 0.023)
		_box(rack, Vector3(0.145, 0.018, 0.57), Vector3(x, 0.110, 0), "edge", 0.005)
		_cylinder(rack, 0.026, 1.40, Vector3(x, 0.82, -0.27), Vector3.UP, "steel")
		_cylinder(rack, 0.031, 0.12, Vector3(x, 0.185, -0.27), Vector3.UP, "edge")
		_beam(rack, Vector3(x, 0.15, 0.25), Vector3(x, 0.59, -0.27), 0.017, "steel")
		_box(rack, Vector3(0.021, 0.91, 0.013), Vector3(x, 0.92, -0.238), "ivory", 0.003)
	for y in [0.34, 1.13]:
		_box(rack, Vector3(1.73, 0.067, 0.067), Vector3(0, y, -0.27), "steel", 0.010)
		_box(rack, Vector3(1.59, 0.014, 0.012), Vector3(0, y + 0.027, -0.230), "edge", 0.002)
	_box(rack, Vector3(1.77, 0.16, 0.105), Vector3(0, 1.545, -0.25), "steel", 0.022)
	_box(rack, Vector3(1.60, 0.095, 0.012), Vector3(0, 1.546, -0.191), "ivory", 0.007)
	_box(rack, Vector3(1.58, 0.015, 0.018), Vector3(0, 1.629, -0.20), "accent", 0.003)
	_title = _label(rack, "ARMES", Vector3(0, 1.545, -0.179), 48, 0.0028, Color("#29251f"))
	for index in WEAPONS.size():
		var identifier: String = WEAPONS[index]
		var x: float = -0.675 + index * 0.45
		var item := _weapon(identifier, index)
		if item == null:
			continue
		rack.add_child(item)
		item.position = Vector3(x, 0.88, 0.035)
		items[identifier] = item
		item_categories[identifier] = "weapon"
		_build_support(x, index, item)
	_light = OmniLight3D.new()
	_light.name = "RackWorklight"
	_light.position = Vector3(0, 1.45, 0.48)
	_light.light_color = Color("#ffc98a")
	_light.omni_range = 1.7
	_light.omni_attenuation = 2.0
	_light.shadow_enabled = false
	rack.add_child(_light)


func _weapon(identifier: String, index: int) -> Node3D:
	if stage == null or not stage.WEAPON_MODELS.has(identifier):
		push_error("Weapon rack has no GLB for " + identifier)
		return null
	var item := Node3D.new()
	item.name = "StockWeapon_" + identifier
	item.set_meta("equipment_id", identifier)
	item.set_meta("category", "weapon")
	var model := (stage.WEAPON_MODELS[identifier] as PackedScene).instantiate() as Node3D
	model.name = "WeaponGeometry"
	item.add_child(model)
	var geometry_bounds := _geometry_bounds(model)
	model.position -= geometry_bounds.get_center()
	var longest := maxf(geometry_bounds.size.x, maxf(geometry_bounds.size.y, geometry_bounds.size.z))
	var axis := Vector3.RIGHT if geometry_bounds.size.x == longest else (Vector3.UP if geometry_bounds.size.y == longest else Vector3.BACK)
	var lean := -0.035 if index % 2 == 0 else 0.035
	var direction := Vector3(lean, 1.0, -0.105).normalized()
	item.basis = Basis(Quaternion(axis, direction)).scaled(Vector3.ONE * float(DISPLAY_LENGTHS[identifier]) / maxf(longest, 0.001))
	item.set_meta("raw_bounds", geometry_bounds)
	item.set_meta("raw_axis", axis)
	return item


func _build_support(x: float, index: int, item: Node3D) -> void:
	var identifier: String = WEAPONS[index]
	var raw: AABB = item.get_meta("raw_bounds")
	var fitted: AABB = item.transform * AABB(-raw.size * 0.5, raw.size)
	var width := clampf(fitted.size.x + 0.035, 0.18, 0.43)
	var rear := fitted.position.z + 0.022
	for y in [0.53, 1.06]:
		_beam(rack, Vector3(x, y, -0.27), Vector3(x, y, rear), 0.013, "steel")
		_box(rack, Vector3(width, 0.065, 0.028), Vector3(x, y, rear), "steel", 0.008)
		_box(rack, Vector3(width - 0.018, 0.047, 0.014), Vector3(x, y, rear + 0.019), "rubber", 0.004)
		for side in [-1.0, 1.0]:
			_box(rack, Vector3(0.025, 0.088, 0.090), Vector3(x + side * width * 0.5, y, rear + 0.040), "steel", 0.006)
			_box(rack, Vector3(0.012, 0.066, 0.063), Vector3(x + side * (width * 0.5 - 0.013), y, rear + 0.044), "rubber", 0.003)
	_box(rack, Vector3(0.30, 0.045, 0.30), Vector3(x, 0.255, 0.02), "dark", 0.012)
	_box(rack, Vector3(0.25, 0.010, 0.21), Vector3(x, 0.284, 0.02), "rubber", 0.003)
	_box(rack, Vector3(0.13, 0.023, 0.008), Vector3(x, 0.250, 0.179), "accent", 0.002)
	var key := "slot_" + identifier
	var trim := _material(key, Color("#777e72"), 0.38, 0.41)
	trim.emission_enabled = true
	trim.emission = Color("#86c9ce")
	trim.emission_energy_multiplier = 0.0
	_slot_trims[identifier] = trim
	_box(rack, Vector3(0.11, 0.012, 0.013), Vector3(x, 0.286, 0.159), key, 0.002)
	var lamp := OmniLight3D.new()
	lamp.name = "SlotIndicator_" + identifier
	lamp.position = Vector3(x, 0.83, 0.40)
	lamp.light_color = Color("#a7e0e3")
	lamp.light_energy = 0.0
	lamp.omni_range = 0.68
	lamp.omni_attenuation = 2.3
	lamp.shadow_enabled = false
	rack.add_child(lamp)
	_slot_lights[identifier] = lamp
	_label(rack, "%02d" % (index + 1), Vector3(x, 0.319, 0.177), 25, 0.0011, ACCENT)


func _geometry_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		var local := mesh.transform
		var ancestor := mesh.get_parent()
		while ancestor != node and ancestor is Node3D:
			local = (ancestor as Node3D).transform * local
			ancestor = ancestor.get_parent()
		var box: AABB = local * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _material(key: String, color: Color, metal: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = roughness
	_materials[key] = material
	return material


func _mesh(parent: Node3D, shape: Mesh, material: String, pos: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = shape
	visual.material_override = _materials[material]
	visual.position = pos
	parent.add_child(visual)
	return visual


func _box(parent: Node3D, dimensions: Vector3, pos: Vector3, material: String, bevel: float) -> MeshInstance3D:
	var key := "%s:%s" % [dimensions, bevel]
	if not _meshes.has(key):
		_meshes[key] = _beveled_box(dimensions, bevel)
	return _mesh(parent, _meshes[key], material, pos)


func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, axis: Vector3, material: String) -> MeshInstance3D:
	var key := "c:%s:%s" % [radius, height]
	if not _meshes.has(key):
		var shape := CylinderMesh.new()
		shape.top_radius = radius
		shape.bottom_radius = radius
		shape.height = maxf(height, 0.001)
		shape.radial_segments = 12
		shape.rings = 1
		_meshes[key] = shape
	var visual := _mesh(parent, _meshes[key], material, pos)
	visual.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	return visual


func _beam(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: String) -> void:
	var direction := end - start
	if direction.length_squared() > 0.000001:
		_cylinder(parent, radius, direction.length(), (start + end) * 0.5, direction.normalized(), material)


func _label(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = 0
	label.modulate = color
	label.position = pos
	label.shaded = false
	parent.add_child(label)
	return label


func _beveled_box(dimensions: Vector3, bevel: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var half := dimensions * 0.5
	var b := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.45)
	var points: Array[Vector3] = []
	for ring in 4:
		var inset := b if ring == 0 or ring == 3 else 0.0
		var x := half.x - inset
		var y := half.y - inset
		var z: float = [-half.z, -half.z + b, half.z - b, half.z][ring]
		for point in [Vector2(-x + b, -y), Vector2(x - b, -y), Vector2(x, -y + b), Vector2(x, y - b), Vector2(x - b, y), Vector2(-x + b, y), Vector2(-x, y - b), Vector2(-x, -y + b)]:
			points.append(Vector3(point.x, point.y, z))
	for ring in 3:
		for edge in 8:
			var a := ring * 8 + edge
			var next := ring * 8 + (edge + 1) % 8
			for vertex in [a, next + 8, next, a, a + 8, next + 8]:
				tool.add_vertex(points[vertex])
	for edge in range(1, 7):
		for vertex in [0, edge, edge + 1, 24, 24 + edge + 1, 24 + edge]:
			tool.add_vertex(points[vertex])
	tool.generate_normals()
	tool.index()
	return tool.commit()
