extends RefCounted
## Correct inward prism surfaces on a copied visual mesh. No collider/source edits.
var _meshes: Dictionary = {}
var corrected := 0

func orient_prism(source: Mesh) -> Mesh:
	if not source is ArrayMesh or source.get_surface_count() != 1:
		return source
	if _meshes.has(source):
		return _meshes[source]
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var top := source.get_aabb().end.y
	var cap_normal := 0.0
	var original: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var face_indices := original
	if face_indices.is_empty():
		for index in vertices.size():
			face_indices.append(index)
	# Detect winding from flat cap triangles, not smoothed edge normals. Narrow
	# platforms can have no vertex normal pointing predominantly upwards/downwards.
	for index in range(0, face_indices.size(), 3):
		var a := vertices[face_indices[index]]
		var b := vertices[face_indices[index + 1]]
		var c := vertices[face_indices[index + 2]]
		if absf(a.y - top) < 0.0001 and absf(b.y - top) < 0.0001 and absf(c.y - top) < 0.0001:
			cap_normal += (c - a).cross(b - a).y
	if cap_normal >= 0.0:
		_meshes[source] = source
		return source
	var indices := PackedInt32Array()
	if original.is_empty():
		for index in range(0, vertices.size(), 3):
			indices.append_array(PackedInt32Array([index, index + 2, index + 1]))
	else:
		for index in range(0, original.size(), 3):
			indices.append_array(PackedInt32Array([original[index], original[index + 2], original[index + 1]]))
	for index in normals.size():
		normals[index] = -normals[index]
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, source.surface_get_material(0))
	mesh.resource_name = source.resource_name + " / outward faces"
	_meshes[source] = mesh
	_meshes[mesh] = mesh
	corrected += 1
	return mesh
