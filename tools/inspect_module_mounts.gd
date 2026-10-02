extends SceneTree

## Prints authored robot anatomy in the module reference frame; no saved edits.
const MODEL := preload("res://art/player_mecha_animated.glb")
const REFERENCE_UNITS := 3.05 / 0.86084
const BONES := ["hips", "spine", "spine1", "spine2", "neck", "head", "leftshoulder", "leftarm", "leftforearm", "lefthand", "leftleg", "leftfoot", "lefttoebase", "rightforearm", "rightfoot"]
var skeleton: Skeleton3D
var vertices := PackedVector3Array()
var parts: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := MODEL.instantiate() as Node3D
	root.add_child(model)
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	await process_frame
	print("REFERENCE AXES +Y up +Z front; multiplier=", REFERENCE_UNITS, " skeleton_transform=", skeleton.global_transform)
	var inverse := skeleton.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var transform := inverse * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / positions.size() if not positions.is_empty() else 0
			for vertex_index in positions.size():
				var point: Vector3 = (transform * positions[vertex_index]) * REFERENCE_UNITS
				vertices.append(point)
				var greatest := 0.0
				var selected := -1
				for influence in influences:
					var offset := vertex_index * influences + influence
					if weights[offset] > greatest:
						greatest = weights[offset]
						selected = bones[offset]
				if selected >= 0 and mesh.skin != null:
					var label := str(mesh.skin.get_bind_name(selected)).to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
					if label.is_empty():
						label = skeleton.get_bone_name(mesh.skin.get_bind_bone(selected)).to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
					if not parts.has(label):
						parts[label] = PackedVector3Array()
					var points: PackedVector3Array = parts[label]
					points.append(point)
					parts[label] = points
	var full := _bounds(vertices)
	print("REST ROBOT ENVELOPE ", full)
	for index in skeleton.get_bone_count():
		var label := skeleton.get_bone_name(index).to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
		if label not in BONES:
			continue
		var rest := skeleton.get_bone_global_rest(index)
		var point := rest.origin * REFERENCE_UNITS
		var nearby := PackedVector3Array()
		for vertex in vertices:
			if absf(vertex.y - point.y) < 0.16 and absf(vertex.x - point.x) < 0.24:
				nearby.append(vertex)
		print("BONE ", label, " origin=", _vector(point), " basis_x=", _vector(rest.basis.x), " basis_y=", _vector(rest.basis.y), " surface=", _bounds(nearby))
		if parts.has(label):
			print("PART ", label, " dominant-weight-envelope=", _bounds(parts[label]))
	_sample("heel_left", Vector3(0.06, -0.04, -0.35), Vector3(0.50, 0.47, 0.02))
	_sample("ankle_left", Vector3(0.06, 0.35, -0.25), Vector3(0.50, 0.75, 0.18))
	_sample("chest_front_side", Vector3(0.22, 1.45, 0.0), Vector3(0.55, 1.95, 0.8))
	_sample("chest_back", Vector3(-0.25, 1.50, -1.0), Vector3(0.25, 2.25, -0.05))
	_sample("shoulder_left", Vector3(0.35, 2.0, -0.6), Vector3(1.0, 2.75, 0.6))
	_sample("back_center_lower", Vector3(-0.20, 1.65, -1.0), Vector3(0.20, 2.05, -0.05))
	_sample("back_center_upper", Vector3(-0.20, 2.05, -1.0), Vector3(0.20, 2.35, -0.05))
	_sample("bio_side_lip", Vector3(0.24, 1.68, 0.30), Vector3(0.42, 1.98, 0.65))
	_sample("forearm_left_middle", Vector3(0.94, 1.98, -0.25), Vector3(1.12, 2.27, 0.55))
	model.queue_free()
	await process_frame
	quit()


func _sample(label: String, lower: Vector3, upper: Vector3) -> void:
	var selected := PackedVector3Array()
	for vertex in vertices:
		if vertex.x >= lower.x and vertex.x <= upper.x and vertex.y >= lower.y and vertex.y <= upper.y and vertex.z >= lower.z and vertex.z <= upper.z:
			selected.append(vertex)
	print("AREA ", label, " count=", selected.size(), " bounds=", _bounds(selected))


func _bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


func _vector(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]
