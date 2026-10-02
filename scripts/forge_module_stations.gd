extends Node3D

## Physical catalog bays. The same cartridge geometry travels with the mechanic.
const LOADOUT := preload("res://scripts/loadout_state.gd")
const ICONS := preload("res://scripts/equipment_icons.gd")
const MODULE_VISUALS := preload("res://scripts/robot_module_visuals.gd")
const FONT := preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const CATEGORIES := ["offensive", "defensive", "passive", "mobility"]
const TITLES := {"offensive": "OFFENSIF", "defensive": "DÉFENSIF", "passive": "PASSIF", "mobility": "MOBILITÉ"}
const COLORS := {"offensive": Color("#f19d4e"), "defensive": Color("#69bddd"), "passive": Color("#b99ad9"), "mobility": Color("#9ecb91")}
const POSITIONS := {
	"offensive": Vector3(-3.20, 0, -0.05),
	"defensive": Vector3(3.18, 0, -0.80),
	"passive": Vector3(-1.08, 0, -3.24),
	"mobility": Vector3(3.25, 0, 1.68),
}
const YAW := {"offensive": 10.0, "defensive": -10.0, "passive": 0.0, "mobility": -18.0}
const LOCAL_BOUNDS := AABB(Vector3(-0.76, 0.02, -0.33), Vector3(1.52, 1.87, 0.69))

var stage
var station_nodes: Dictionary = {}
var items: Dictionary = {}
var item_categories: Dictionary = {}
var selected_category := ""
var _icons := ICONS.new()
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _trims: Dictionary = {}
var _lights: Dictionary = {}
var _titles: Dictionary = {}
var _item_marks: Dictionary = {}


func configure(garage_stage: Node) -> void:
	stage = garage_stage


func _ready() -> void:
	name = "ModuleStorageStations"
	set_process(false)
	_material("steel", Color("#3c4345"), 0.78, 0.43)
	_material("dark", Color("#202728"), 0.64, 0.65)
	_material("ivory", Color("#d0c8b8"), 0.25, 0.61)
	_material("edge", Color("#879093"), 0.85, 0.35)
	_material("rubber", Color("#151a1a"), 0.05, 0.83)
	var selection := _material("selection", Color("#ffd484"), 0.3, 0.35)
	selection.emission_enabled = true
	selection.emission = Color("#ffd484")
	selection.emission_energy_multiplier = 1.7
	for category in CATEGORIES:
		var trim := _material(category, COLORS[category], 0.37, 0.38)
		trim.emission_enabled = true
		trim.emission = COLORS[category]
		trim.emission_energy_multiplier = 0.65
		_trims[category] = trim
		_build_station(category)
	highlight("")


func pick(point: Vector2) -> String:
	if stage == null or stage.camera == null or not is_visible_in_tree() or not stage.is_visible_in_tree():
		return ""
	if stage.size.x <= 0.0 or stage.size.y <= 0.0 or not Rect2(Vector2.ZERO, stage.size).has_point(point):
		return ""
	var screen: Vector2 = point * Vector2(stage.viewport.size) / stage.size
	var origin: Vector3 = stage.camera.project_ray_origin(screen)
	var direction: Vector3 = stage.camera.project_ray_normal(screen)
	var nearest := INF
	var result := ""
	for category in CATEGORIES:
		var station: Node3D = station_nodes[category]
		if not station.is_visible_in_tree() or stage.camera.is_position_behind(anchor(category)):
			continue
		var inverse := station.global_transform.affine_inverse()
		var hit = LOCAL_BOUNDS.intersects_ray(inverse * origin, inverse.basis * direction)
		if hit == null:
			continue
		var distance := origin.distance_to(station.global_transform * (hit as Vector3))
		if distance < nearest:
			nearest = distance
			result = category
	# The rear bay must not steal a drag that starts on the robot in front of it.
	if result != "" and stage.robot != null:
		var inverse: Transform3D = stage.robot.global_transform.affine_inverse()
		var robot_hit = stage._robot_pick_bounds.intersects_ray(inverse * origin, inverse.basis * direction)
		if robot_hit != null:
			var robot_distance := origin.distance_to(stage.robot.global_transform * (robot_hit as Vector3))
			if robot_distance < nearest:
				return ""
	return result


func anchor(category: String) -> Vector3:
	if not station_nodes.has(category):
		return Vector3.ZERO
	return (station_nodes[category] as Node3D).global_transform * Vector3(0, 1.73, 0.33)


func bounds(category: String) -> AABB:
	if not station_nodes.has(category):
		return AABB()
	return (station_nodes[category] as Node3D).global_transform * LOCAL_BOUNDS


func module_transform(identifier: String) -> Transform3D:
	if not items.has(identifier):
		return Transform3D.IDENTITY
	return (items[identifier] as Node3D).global_transform


func create_payload(identifier: String) -> Node3D:
	if not items.has(identifier):
		return null
	var payload := (items[identifier] as Node3D).duplicate(0) as Node3D
	payload.name = "ModulePayload_" + identifier
	payload.transform = Transform3D.IDENTITY
	payload.visible = true
	return payload


func set_item_visible(identifier: String, value: bool) -> void:
	if items.has(identifier):
		(items[identifier] as Node3D).visible = value


func highlight(category: String) -> void:
	selected_category = category if CATEGORIES.has(category) else ""
	for key in CATEGORIES:
		var active: bool = key == selected_category
		(_trims[key] as StandardMaterial3D).emission_energy_multiplier = 1.5 if active else 0.65
		(_lights[key] as OmniLight3D).light_energy = 0.70 if active else 0.12
		(_titles[key] as Label3D).modulate = COLORS[key].lightened(0.30) if active else Color("#dfd8c9")
	if selected_category.is_empty():
		highlight_item("")


func highlight_item(identifier: String) -> void:
	for key in _item_marks:
		(_item_marks[key] as Node3D).visible = key == identifier


func _catalog(category: String) -> Array:
	return {"offensive": LOADOUT.OFFENSIVE, "defensive": LOADOUT.DEFENSIVE, "passive": LOADOUT.PASSIVES, "mobility": LOADOUT.MOBILITY}[category]


func _build_station(category: String) -> void:
	var rack := Node3D.new()
	rack.name = "Storage_" + category
	add_child(rack)
	rack.position = POSITIONS[category]
	rack.rotation_degrees.y = YAW[category]
	station_nodes[category] = rack
	# A weighted plinth, folded sheet backing and proud tubular corner posts.
	_box(rack, Vector3(1.48, 0.12, 0.60), Vector3(0, 0.08, 0), "dark", 0.035)
	_box(rack, Vector3(1.35, 0.045, 0.51), Vector3(0, 0.156, 0), "steel", 0.014)
	_box(rack, Vector3(1.37, 1.59, 0.055), Vector3(0, 0.94, -0.255), "dark", 0.016)
	for x in [-0.70, 0.70]:
		_box(rack, Vector3(0.065, 1.66, 0.065), Vector3(x, 0.975, -0.17), "edge", 0.013)
		_box(rack, Vector3(0.035, 1.42, 0.025), Vector3(x, 0.94, -0.13), category, 0.008)
		_box(rack, Vector3(0.085, 0.10, 0.09), Vector3(x, 0.24, -0.17), "steel", 0.01)
	_box(rack, Vector3(1.44, 0.21, 0.19), Vector3(0, 1.74, -0.065), "steel", 0.022)
	_box(rack, Vector3(1.33, 0.025, 0.018), Vector3(0, 1.866, 0.045), category, 0.004)
	var title := _label(rack, TITLES[category], Vector3(0, 1.74, 0.048), 48, 0.00225, Color("#dfd8c9"))
	_titles[category] = title
	var number := "%02d" % (CATEGORIES.find(category) + 1)
	_label(rack, "BAY " + number, Vector3(-0.52, 0.26, 0.31), 32, 0.0016, COLORS[category])
	_box(rack, Vector3(0.31, 0.08, 0.035), Vector3(0.43, 0.26, 0.284), "rubber", 0.008)
	for index in 4:
		_box(rack, Vector3(0.043, 0.035, 0.014), Vector3(0.33 + index * 0.065, 0.26, 0.31), category, 0.004)
	var catalog := _catalog(category)
	var rows := ceili(catalog.size() / 2.0)
	for row in rows:
		var y := 1.42 - row * 0.44 if rows == 3 else 1.34 - row * 0.53
		_box(rack, Vector3(1.30, 0.065, 0.49), Vector3(0, y - 0.21, 0.005), "steel", 0.012)
		_box(rack, Vector3(1.20, 0.015, 0.025), Vector3(0, y - 0.177, 0.246), category, 0.003)
		for column in 2:
			var index := row * 2 + column
			if index >= catalog.size():
				continue
			var x := -0.34 if column == 0 else 0.34
			_box(rack, Vector3(0.49, 0.025, 0.38), Vector3(x, y - 0.155, 0.016), "rubber", 0.009)
			_box(rack, Vector3(0.025, 0.07, 0.39), Vector3(x - 0.25, y - 0.128, 0.016), "edge", 0.004)
			_box(rack, Vector3(0.025, 0.07, 0.39), Vector3(x + 0.25, y - 0.128, 0.016), "edge", 0.004)
			var identifier := str(catalog[index])
			var item := _cartridge(category, identifier, index)
			rack.add_child(item)
			item.position = Vector3(x, y, 0.035)
			items[identifier] = item
			item_categories[identifier] = category
			var mark := _box(rack, Vector3(0.48, 0.024, 0.021), Vector3(x, y - 0.173, 0.263), "selection", 0.004)
			mark.name = "SelectedBay_" + identifier
			mark.visible = false
			_item_marks[identifier] = mark
	var lamp := OmniLight3D.new()
	lamp.name = "BayAccent"
	lamp.position = Vector3(0, 1.56, 0.55)
	lamp.light_color = COLORS[category]
	lamp.omni_range = 1.4
	lamp.omni_attenuation = 2.0
	lamp.shadow_enabled = false
	rack.add_child(lamp)
	_lights[category] = lamp


func _cartridge(category: String, identifier: String, index: int) -> Node3D:
	if MODULE_VISUALS.has_model(identifier):
		var display := MODULE_VISUALS.create_display(identifier)
		display.name = "Cartridge_" + identifier
		display.set_meta("category", category)
		var bounds := AABB()
		var first := true
		for child in display.get_children():
			if child is MeshInstance3D:
				bounds = child.mesh.get_aabb() if first else bounds.merge(child.mesh.get_aabb())
				first = false
		var fit := minf(1.0, minf(0.44 / maxf(bounds.size.x, 0.001), minf(0.30 / maxf(bounds.size.y, 0.001), 0.24 / maxf(bounds.size.z, 0.001))))
		display.scale = Vector3.ONE * fit
		return display
	var item := Node3D.new()
	item.name = "Cartridge_" + identifier
	item.set_meta("equipment_id", identifier)
	item.set_meta("category", category)
	var width := 0.44 if category == "defensive" else (0.38 if category == "passive" else 0.41)
	var depth := 0.24 if category == "mobility" else 0.20
	_box(item, Vector3(width, 0.30, depth), Vector3.ZERO, "steel", 0.025)
	_box(item, Vector3(width - 0.052, 0.258, 0.025), Vector3(0, 0, depth * 0.5 + 0.012), "ivory", 0.014)
	_box(item, Vector3(width - 0.085, 0.014, 0.013), Vector3(0, 0.113, depth * 0.5 + 0.031), category, 0.003)
	for side in [-1.0, 1.0]:
		_box(item, Vector3(0.029, 0.222, depth + 0.02), Vector3(side * width * 0.5, 0, -0.01), "dark", 0.009)
		_box(item, Vector3(0.013, 0.154, 0.014), Vector3(side * (width * 0.5 + 0.01), 0.01, depth * 0.5 + 0.007), category, 0.003)
	# The families read differently even before their final module models arrive.
	match category:
		"offensive":
			for x in [-0.10, 0.10]:
				_cylinder(item, 0.035, 0.026, 0.12, Vector3(x, 0.17, -0.04), Vector3.UP, "dark")
				_cylinder(item, 0.027, 0.027, 0.018, Vector3(x, 0.22, -0.04), Vector3.UP, category)
		"defensive":
			_box(item, Vector3(width + 0.025, 0.04, 0.045), Vector3(0, -0.125, depth * 0.5 + 0.026), "edge", 0.008)
			_box(item, Vector3(0.16, 0.04, 0.06), Vector3(0, 0.16, -0.02), "dark", 0.01)
		"passive":
			_cylinder(item, 0.07, 0.07, 0.075, Vector3(0, 0.17, -0.025), Vector3.UP, "dark")
			_cylinder(item, 0.045, 0.045, 0.018, Vector3(0, 0.21, -0.025), Vector3.UP, category)
		"mobility":
			for side in [-1.0, 1.0]:
				_cylinder(item, 0.040, 0.025, 0.09, Vector3(side * 0.12, -0.135, -0.035), Vector3.DOWN, "dark")
				_box(item, Vector3(0.05, 0.028, 0.16), Vector3(side * 0.10, 0.155, -0.018), "edge", 0.005)
	for x in [-width * 0.36, width * 0.36]:
		for y in [-0.10, 0.09]:
			_cylinder(item, 0.009, 0.009, 0.009, Vector3(x, y, depth * 0.5 + 0.032), Vector3.BACK, "dark", 6)
	var icon_material := StandardMaterial3D.new()
	icon_material.albedo_texture = _icons.get_icon(identifier)
	icon_material.albedo_color = Color.WHITE
	icon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	icon_material.alpha_scissor_threshold = 0.1
	icon_material.roughness = 0.74
	icon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var icon := QuadMesh.new()
	icon.size = Vector2(0.247, 0.145)
	var decal := _mesh(item, icon, icon_material, Vector3(0, 0.023, depth * 0.5 + 0.029))
	decal.name = "CatalogFace"
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(item, Vector3(0.24, 0.037, 0.008), Vector3(0, -0.088, depth * 0.5 + 0.032), "dark", 0.003)
	_label(item, "%02d / %s" % [index + 1, _short_name(identifier)], Vector3(0, -0.088, depth * 0.5 + 0.038), 32, 0.00077, Color("#ded6c1"))
	return item


func _short_name(identifier: String) -> String:
	return {"rocket_basket": "ROCKET", "fulguro_punch": "FULGURO", "pelto_smash": "PELTO", "magnetic_field": "MAGNETIC", "static_shield": "STATIC", "pyro_boots": "PYRO", "bio_injector": "BIO", "auxiliary_reactor": "REACTOR", "baroud": "BAROUD"}.get(identifier, identifier.to_upper().left(10))


func _material(key: String, color: Color, metal: float, roughness: float) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metal
		material.roughness = roughness
		_materials[key] = material
	return _materials[key]


func _mesh(parent: Node3D, shape: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = shape
	visual.material_override = material
	visual.position = pos
	parent.add_child(visual)
	return visual


func _box(parent: Node3D, dimensions: Vector3, pos: Vector3, material: String, bevel: float) -> MeshInstance3D:
	var key := "%s:%s" % [dimensions, bevel]
	if not _meshes.has(key):
		_meshes[key] = _beveled_box(dimensions, bevel)
	return _mesh(parent, _meshes[key], _materials[material], pos)


func _cylinder(parent: Node3D, radius_top: float, radius_bottom: float, height: float, pos: Vector3, axis: Vector3, material: String, sides: int = 12) -> MeshInstance3D:
	var key := "c:%s:%s:%s:%s" % [radius_top, radius_bottom, height, sides]
	if not _meshes.has(key):
		var shape := CylinderMesh.new()
		shape.top_radius = radius_top
		shape.bottom_radius = radius_bottom
		shape.height = height
		shape.radial_segments = sides
		shape.rings = 1
		_meshes[key] = shape
	var visual := _mesh(parent, _meshes[key], _materials[material], pos)
	visual.basis = Basis(Quaternion(Vector3.UP, axis))
	return visual


func _label(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = 0
	label.modulate = color
	label.position = pos
	label.no_depth_test = false
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
