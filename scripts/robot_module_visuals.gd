extends Node3D

## Authored rigid accessories, shared by the garage, its storage bays and combat.
## Geometry is cached once in reference metres and follows existing skeleton bones.
const REFERENCE_HEIGHT := 3.05
const SOURCE_HEIGHT := 0.86084
const MODEL_PATHS := {
	"pyro_boots": "res://art/modules/pyro_boots.glb",
	"bio_injector": "res://art/modules/bio_injector.glb",
	"rocket_basket": "res://art/modules/rocket_basket.glb",
	"magnetic_field": "res://art/modules/magnetic_field.glb",
	"auxiliary_reactor": "res://art/modules/auxiliary_reactor.glb",
}
const MODEL_SCENES := {
	"pyro_boots": preload("res://art/modules/pyro_boots.glb"),
	"bio_injector": preload("res://art/modules/bio_injector.glb"),
	"rocket_basket": preload("res://art/modules/rocket_basket.glb"),
	"magnetic_field": preload("res://art/modules/magnetic_field.glb"),
	"auxiliary_reactor": preload("res://art/modules/auxiliary_reactor.glb"),
}
const MODEL_CATEGORIES := {
	"pyro_boots": "mobility", "bio_injector": "mobility",
	"rocket_basket": "offensive", "magnetic_field": "defensive",
	"auxiliary_reactor": "passive",
}
const MOUNT_IDS := {
	"pyro_left": "pyro_boots", "pyro_right": "pyro_boots",
	"bio": "bio_injector", "rocket": "rocket_basket",
	"magnetic": "magnetic_field", "reactor": "auxiliary_reactor",
}
static var _shared_meshes: Dictionary = {}
static var _shared_materials: Dictionary = {}
var skeleton: Skeleton3D
var mobility_id := ""
var equipment_ids := {"offensive": "", "defensive": "", "mobility": "", "passive": ""}
var mounts: Dictionary = {}
var _sockets: Array[BoneAttachment3D] = []


func configure(source_skeleton: Skeleton3D) -> void:
	skeleton = source_skeleton
	name = "RobotModuleVisuals"
	set_process(false)
	# Shallow inserts follow armour surfaces; the authored back plane is Z=0.
	_make_mount("pyro_left", "leftfoot", Vector3(0.04, 0.04, -0.25), false, Vector3(0, PI, 0))
	_make_mount("pyro_right", "rightfoot", Vector3(-0.04, 0.04, -0.25), true, Vector3(0, PI, 0))
	_make_mount("bio", "spine1", Vector3(0.2776, -0.0803, 0.1871), false, Vector3(0.3320, 0.6739, 0.0192))
	_make_mount("rocket", "leftarm", Vector3(0.1447, 0.0876, 0.1795), false, Vector3(-0.4721, 0.7048, 1.0034))
	_make_mount("magnetic", "leftforearm", Vector3(0.18, -0.005, 0.230), false, Vector3(0, 0, -PI / 2))
	_make_mount("reactor", "leftarm", Vector3(0.2169, -0.0284, -0.1132), false, Vector3(0.0938, -3.0804, 1.5765))
	set_loadout(equipment_ids)


func set_loadout(equipment: Dictionary) -> void:
	for category in equipment_ids:
		if equipment.has(category):
			equipment_ids[category] = str(equipment[category])
	mobility_id = str(equipment_ids.mobility)
	for key in mounts:
		var identifier: String = MOUNT_IDS[key]
		(mounts[key] as Node3D).visible = str(equipment_ids[MODEL_CATEGORIES[identifier]]) == identifier


func set_mobility_module(identifier: String) -> void:
	set_loadout({"mobility": identifier})


static func has_model(identifier: String) -> bool:
	return MODEL_PATHS.has(identifier)


func module_transform(identifier: String) -> Transform3D:
	for key in mounts:
		if MOUNT_IDS[key] == identifier:
			return (mounts[key] as Node3D).global_transform
	return Transform3D.IDENTITY


func service_point(identifier: String) -> Vector3:
	for key in mounts:
		if MOUNT_IDS[key] == identifier:
			return (mounts[key].get_node("ServicePoint") as Node3D).global_position
	return Vector3.ZERO


func module_bounds(identifier: String) -> AABB:
	var result := AABB()
	var first := true
	for key in mounts:
		if MOUNT_IDS[key] != identifier:
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
		if MOUNT_IDS[key] != identifier:
			continue
		for child in (mounts[key] as Node3D).get_children():
			if child is MeshInstance3D:
				var arrays: Array = child.mesh.surface_get_arrays(0)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				total += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total


static func create_display(identifier: String) -> Node3D:
	if not has_model(identifier):
		return null
	var display := Node3D.new()
	display.name = "Module_" + identifier
	display.set_meta("equipment_id", identifier)
	_add_geometry(display, identifier)
	return display


func _make_mount(key: String, bone_label: String, offset: Vector3, mirrored: bool = false, rotation: Vector3 = Vector3.ZERO) -> void:
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
	mount.name = "BioInjector" if key == "bio" else "Module_" + key
	attachment.add_child(mount)
	var unit := SOURCE_HEIGHT / REFERENCE_HEIGHT
	var rest := skeleton.get_bone_global_rest(bone)
	# Orient in source axes before converting to the animated bone's coordinates.
	mount.transform = rest.affine_inverse() * Transform3D(Basis.from_euler(rotation).scaled(Vector3.ONE * unit), rest.origin + offset * unit)
	mounts[key] = mount
	_add_geometry(mount, str(MOUNT_IDS[key]), mirrored)
	var target := Marker3D.new()
	target.name = "ServicePoint"
	var geometry := AABB()
	var first := true
	for child in mount.get_children():
		if child is MeshInstance3D:
			geometry = child.mesh.get_aabb() if first else geometry.merge(child.mesh.get_aabb())
			first = false
	target.position = Vector3(0, 0, geometry.end.z)
	mount.add_child(target)


func _exit_tree() -> void:
	for socket in _sockets:
		if is_instance_valid(socket):
			socket.queue_free()


static func _add_geometry(parent: Node3D, identifier: String, mirrored: bool = false) -> void:
	var meshes := _geometry(identifier, mirrored)
	for key in meshes:
		var visual := MeshInstance3D.new()
		visual.name = str(key)
		visual.mesh = meshes[key]
		visual.material_override = _shared_materials[identifier][key]
		parent.add_child(visual)


static func _geometry(identifier: String, mirrored: bool = false) -> Dictionary:
	var cache_key := identifier + ("_mirrored" if mirrored else "")
	if _shared_meshes.has(cache_key):
		return _shared_meshes[cache_key]
	if mirrored:
		_shared_meshes[cache_key] = _mirror_geometry(_geometry(identifier))
		return _shared_meshes[cache_key]
	var model := MODEL_SCENES[identifier] as PackedScene
	if model == null:
		push_error("Missing authored module model: " + identifier)
		return {}
	var source := model.instantiate() as Node3D
	var builders: Dictionary = {}
	_shared_materials[identifier] = {}
	_collect_geometry(source, Transform3D.IDENTITY, identifier, builders)
	source.free()
	var meshes: Dictionary = {}
	for key in builders:
		meshes[key] = (builders[key] as SurfaceTool).commit()
	_shared_meshes[cache_key] = meshes
	return meshes


static func _collect_geometry(node: Node3D, parent_transform: Transform3D, identifier: String, builders: Dictionary) -> void:
	var local_transform := parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material := node.get_active_material(surface) as StandardMaterial3D
			var key := material.resource_name.to_lower() if material != null else str(node.name).to_lower()
			if key.is_empty():
				key = "steel"
			if not builders.has(key):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[key] = builder
				var shared := material.duplicate() as StandardMaterial3D if material != null else StandardMaterial3D.new()
				shared.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				_shared_materials[identifier][key] = shared
			(builders[key] as SurfaceTool).append_from(node.mesh, surface, local_transform)
	for child in node.get_children():
		if child is Node3D:
			_collect_geometry(child, local_transform, identifier, builders)


static func _mirror_geometry(meshes: Dictionary) -> Dictionary:
	var mirrored: Dictionary = {}
	for key in meshes:
		var source := meshes[key] as ArrayMesh
		var arrays: Array = source.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents := PackedFloat32Array()
		if arrays[Mesh.ARRAY_TANGENT] != null:
			tangents = arrays[Mesh.ARRAY_TANGENT]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in vertices.size():
			vertices[index].x = -vertices[index].x
			if index < normals.size():
				normals[index].x = -normals[index].x
			if index * 4 + 3 < tangents.size():
				tangents[index * 4] = -tangents[index * 4]
				tangents[index * 4 + 3] = -tangents[index * 4 + 3]
		# Bake reflection and reverse triangle winding, keeping positive sockets.
		for triangle in range(0, indices.size(), 3):
			var swap := indices[triangle + 1]
			indices[triangle + 1] = indices[triangle + 2]
			indices[triangle + 2] = swap
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mirrored[key] = mesh
	return mirrored
