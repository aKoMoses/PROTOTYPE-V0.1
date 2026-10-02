extends Node3D

## Small rigid accessories on the original skeleton. Meshes/materials are shared,
## opaque and static: no new skeleton, textures, lights or per-frame processing.
const REFERENCE_HEIGHT := 3.05
const SOURCE_HEIGHT := 0.86084
const MATERIAL_COLORS := {
	"steel": Color("#343e41"), "paint": Color("#bc8736"),
	"ivory": Color("#c2bdae"), "amber": Color("#f8a93e"),
	"jade": Color("#3c6851"), "green": Color("#79a76b"),
}
static var _shared_meshes: Dictionary = {}
static var _shared_materials: Dictionary = {}
var skeleton: Skeleton3D
var mobility_id := ""
var mounts: Dictionary = {}
var _sockets: Array[BoneAttachment3D] = []


func configure(source_skeleton: Skeleton3D) -> void:
	skeleton = source_skeleton
	name = "RobotModuleVisuals"
	set_process(false)
	# Work in the imported model's own units, so both the garage and combat
	# scale the exact same geometry with their existing visual roots.
	_make_mount("pyro_left", "leftfoot", Vector3(0.28, 0.20, 0.06), 1.0)
	_make_mount("pyro_right", "rightfoot", Vector3(-0.28, 0.20, 0.06), -1.0)
	_make_mount("bio", "spine1", Vector3(0.30, -0.18, 0.32))
	set_mobility_module(mobility_id)


func set_mobility_module(identifier: String) -> void:
	mobility_id = identifier
	for key in mounts:
		(mounts[key] as Node3D).visible = identifier == ("bio_injector" if key == "bio" else "pyro_boots")


func service_point(identifier: String) -> Vector3:
	var key := "bio" if identifier == "bio_injector" else "pyro_left"
	if not mounts.has(key):
		return Vector3.ZERO
	return (mounts[key].get_node("ServicePoint") as Node3D).global_position


func module_bounds(identifier: String) -> AABB:
	var result := AABB()
	var first := true
	for key in mounts:
		if (key == "bio") != (identifier == "bio_injector"):
			continue
		for child in (mounts[key] as Node3D).get_children():
			if child is MeshInstance3D:
				var bounds: AABB = child.global_transform * child.mesh.get_aabb()
				result = bounds if first else result.merge(bounds)
				first = false
	return result


func triangle_count(identifier: String) -> int:
	var total := 0
	for key in mounts:
		if (key == "bio") != (identifier == "bio_injector"):
			continue
		for child in (mounts[key] as Node3D).get_children():
			if child is MeshInstance3D:
				var arrays: Array = child.mesh.surface_get_arrays(0)
				total += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total


func _make_mount(key: String, bone_label: String, offset: Vector3, side: float = 1.0) -> void:
	var bone := -1
	for index in skeleton.get_bone_count():
		var label := skeleton.get_bone_name(index).to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
		if label == bone_label:
			bone = index
			break
	if bone < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "ModuleAttachment_" + key
	attachment.bone_name = skeleton.get_bone_name(bone)
	skeleton.add_child(attachment)
	_sockets.append(attachment)
	var mount := Node3D.new()
	mount.name = "BioInjector" if key == "bio" else "PyroBoot_" + bone_label
	attachment.add_child(mount)
	var unit := SOURCE_HEIGHT / REFERENCE_HEIGHT
	var rest := skeleton.get_bone_global_rest(bone)
	# Inverse bind coordinates keep the accessories on the same physical part
	# during idle, walking, turns and combat poses; no world-space follow script.
	mount.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit), rest.origin + offset * unit)
	mounts[key] = mount
	if not _shared_meshes.has(key):
		_shared_meshes[key] = _build_bio() if key == "bio" else _build_pyro(side)
	var meshes: Dictionary = _shared_meshes[key]
	for material_name in meshes:
		var visual := MeshInstance3D.new()
		visual.name = material_name
		visual.mesh = meshes[material_name]
		visual.material_override = _material(material_name)
		mount.add_child(visual)
	var target := Marker3D.new()
	target.name = "ServicePoint"
	target.position = Vector3(0, 0, 0.105 if key == "bio" else 0.12)
	mount.add_child(target)


func _exit_tree() -> void:
	for socket in _sockets:
		if is_instance_valid(socket):
			socket.queue_free()


static func _material(key: String) -> StandardMaterial3D:
	if not _shared_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = MATERIAL_COLORS[key]
		material.roughness = 0.68 if key == "paint" or key == "ivory" else 0.40
		material.metallic = 0.65 if key == "steel" else 0.25
		if key in ["amber", "green"]:
			material.emission_enabled = true
			material.emission = MATERIAL_COLORS[key]
			material.emission_energy_multiplier = 0.55 if key == "amber" else 0.18
		if key == "jade":
			material.roughness = 0.22
		_shared_materials[key] = material
	return _shared_materials[key]


static func _build_pyro(side: float) -> Dictionary:
	var surfaces: Dictionary = {}
	_box(surfaces, "steel", Vector3(0.21, 0.26, 0.055), Vector3(0, 0, -0.065))
	_box(surfaces, "steel", Vector3(0.205, 0.23, 0.18), Vector3.ZERO, 0.025)
	_box(surfaces, "paint", Vector3(0.213, 0.05, 0.185), Vector3(0, 0.094, 0), 0.009)
	for front in [-1.0, 1.0]:
		_box(surfaces, "steel", Vector3(0.052, 0.135, 0.015), Vector3(-side * 0.042, 0.005, front * 0.097), 0.008)
		_box(surfaces, "amber", Vector3(0.018, 0.100, 0.014), Vector3(-side * 0.042, 0.01, front * 0.107), 0.004)
	var exhaust_axis := Vector3(side, 0, 0)
	_cylinder(surfaces, "steel", 0.074, 0.063, 0.075, Vector3(side * 0.12, -0.035, 0), exhaust_axis)
	_cylinder(surfaces, "ivory", 0.063, 0.061, 0.018, Vector3(side * 0.163, -0.035, 0), exhaust_axis)
	_cylinder(surfaces, "steel", 0.050, 0.050, 0.021, Vector3(side * 0.174, -0.035, 0), exhaust_axis)
	_cylinder(surfaces, "amber", 0.030, 0.030, 0.004, Vector3(side * 0.187, -0.035, 0), exhaust_axis)
	for x in [-0.074, 0.074]:
		_cylinder(surfaces, "ivory", 0.014, 0.014, 0.012, Vector3(x, -0.082, 0.105), Vector3.BACK, 6)
	# A few deliberately placed bare-metal chips, readable without a texture.
	_box(surfaces, "steel", Vector3(0.025, 0.012, 0.005), Vector3(0.046, 0.092, 0.092), 0.002)
	_box(surfaces, "steel", Vector3(0.012, 0.033, 0.005), Vector3(-0.085, 0.069, 0.092), 0.002)
	return _commit(surfaces)


static func _build_bio() -> Dictionary:
	var surfaces: Dictionary = {}
	_box(surfaces, "steel", Vector3(0.25, 0.32, 0.055), Vector3(0, 0, -0.035), 0.025)
	_box(surfaces, "ivory", Vector3(0.055, 0.305, 0.13), Vector3(0.103, 0, 0.034), 0.018)
	_box(surfaces, "paint", Vector3(0.058, 0.18, 0.007), Vector3(0.103, 0.045, 0.103), 0.008)
	for x in [-0.065, 0.022]:
		_cylinder(surfaces, "jade", 0.034, 0.034, 0.17, Vector3(x, 0.025, 0.042))
		_cylinder(surfaces, "green", 0.024, 0.024, 0.12, Vector3(x, 0.015, 0.065))
		for y in [-0.071, 0.122]:
			_cylinder(surfaces, "steel", 0.044, 0.044, 0.043, Vector3(x, y, 0.043))
			_cylinder(surfaces, "ivory", 0.043, 0.043, 0.012, Vector3(x, y + 0.021, 0.043))
		_box(surfaces, "steel", Vector3(0.069, 0.014, 0.084), Vector3(x, 0.025, 0.043), 0.003)
	_box(surfaces, "steel", Vector3(0.071, 0.056, 0.025), Vector3(0.089, -0.113, 0.104), 0.008)
	_cylinder(surfaces, "green", 0.015, 0.015, 0.005, Vector3(0.089, -0.113, 0.12), Vector3.BACK)
	var hose := [Vector3(-0.067, -0.092, 0.043), Vector3(-0.068, -0.15, 0.038), Vector3(-0.13, -0.18, 0.021), Vector3(-0.18, -0.14, -0.005)]
	for segment in hose.size() - 1:
		var direction: Vector3 = hose[segment + 1] - hose[segment]
		_cylinder(surfaces, "steel", 0.015, 0.015, direction.length(), (hose[segment] + hose[segment + 1]) * 0.5, direction.normalized(), 8)
	_box(surfaces, "steel", Vector3(0.021, 0.036, 0.006), Vector3(0.12, 0.117, 0.106), 0.002)
	return _commit(surfaces)


static func _surface(surfaces: Dictionary, key: String) -> SurfaceTool:
	if not surfaces.has(key):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[key] = builder
	return surfaces[key]


static func _cylinder(surfaces: Dictionary, key: String, top: float, bottom: float, height: float, position: Vector3, axis: Vector3 = Vector3.UP, segments: int = 10) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	_surface(surfaces, key).append_from(mesh, 0, Transform3D(Basis(Quaternion(Vector3.UP, axis)), position))


static func _box(surfaces: Dictionary, key: String, size: Vector3, position: Vector3, bevel: float = 0.01) -> void:
	# Four octagonal rings form bevelled caps and sides (60 triangles).
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var half := size * 0.5
	var b := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.45)
	var points: Array[Vector3] = []
	for ring in 4:
		var inset := b if ring in [0, 3] else 0.0
		var x := half.x - inset
		var y := half.y - inset
		var corner := b
		var z: float = [-half.z, -half.z + b, half.z - b, half.z][ring]
		for point in [Vector2(-x + corner, -y), Vector2(x - corner, -y), Vector2(x, -y + corner), Vector2(x, y - corner), Vector2(x - corner, y), Vector2(-x + corner, y), Vector2(-x, y - corner), Vector2(-x, -y + corner)]:
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
	# Every appended primitive must be indexed. Otherwise cylinder indices in
	# the same material batch leave the box vertices unreferenced.
	tool.index()
	_surface(surfaces, key).append_from(tool.commit(), 0, Transform3D(Basis.IDENTITY, position))


static func _commit(surfaces: Dictionary) -> Dictionary:
	var meshes: Dictionary = {}
	for key in surfaces:
		meshes[key] = (surfaces[key] as SurfaceTool).commit()
	return meshes
