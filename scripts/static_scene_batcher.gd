extends Node
## Merge rigid opaque scenery without changing triangles, materials or collision.
const CELL_SIZE := 8.0
const REFERENCE_SHADER := "res://art/environment/reference_finish/surface.gdshader"
const SALVAGE_SHADER := "res://shaders/stylized_salvage.gdshader"
const RENDER_PROPERTIES := ["layers", "cast_shadow", "gi_mode", "extra_cull_margin", "lod_bias", "ignore_occlusion_culling", "visibility_range_begin", "visibility_range_begin_margin", "visibility_range_end", "visibility_range_end_margin", "visibility_range_fade_mode"]
var world: Node3D
var garage := false
var _groups: Dictionary = {}
var _checks: Array[Dictionary] = []
var _cursor := 0
var _serial := 0
var _preparing := false
var _prepared := false
var _prepare_frames := 0
var _mesh_arrays: Dictionary = {}
var stats := {"sources": 0, "batches": 0, "saved_surfaces": 0}

static func enabled() -> bool:
	if OS.get_cmdline_user_args().has("static-batching-baseline"):
		return false
	return DisplayServer.get_name() != "headless" or OS.has_feature("mobile") or OS.get_cmdline_user_args().has("static-batching")

static func install(root: Node3D, is_garage: bool = false) -> void:
	if not enabled() or root.has_node("StaticSceneBatcher"):
		return
	var helper: Node = load("res://scripts/static_scene_batcher.gd").new()
	helper.name = "StaticSceneBatcher"
	helper.world = root
	helper.garage = is_garage
	root.add_child(helper)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	get_tree().node_added.connect(_node_added)
	_prepare.call_deferred()

func _prepare() -> void:
	if _preparing:
		return
	_preparing = true
	# Existing material adapters and delayed scenery creation finish first.
	_prepare_frames = 8
	set_process(true)

func _node_added(node: Node) -> void:
	if _prepared and node is MeshInstance3D and not node.has_meta("static_render_batch") and world.is_ancestor_of(node) and _scope(node) != null:
		_prepare.call_deferred()

func _scope(mesh: MeshInstance3D) -> Node3D:
	var branch: Node = mesh
	var item: Node3D
	while branch != world and branch != null:
		if branch is Skeleton3D or branch is BoneAttachment3D or branch is Viewport:
			return null
		if branch is Node3D and (String(branch.name).begins_with("Cartridge_") or String(branch.name).begins_with("StockWeapon_")):
			item = branch
		if branch.get_parent() == world:
			break
		branch = branch.get_parent()
	if branch == null or branch == world:
		return null
	if garage:
		if branch.name in ["ModuleStorageStations", "WeaponStorageRack"]:
			return item if item != null else branch as Node3D
		if branch.name in ["workshop", "WorkshopRightWall", "GarageHangar"] or branch == mesh:
			return world
		return null
	if branch.name in ["ArenaPresentation", "ArenaExterior"] or (branch.is_in_group("arena_solid") and not branch.has_method("get_health")):
		var ancestor := mesh.get_parent()
		while ancestor != branch and ancestor != null:
			if ancestor is Node3D and ancestor.get_script() != null:
				var path: String = ancestor.get_script().resource_path
				if path not in ["res://scripts/environment/workshop_dressing.gd", "res://scripts/environment/main_map_art.gd", "res://scripts/environment/reference_render_finish.gd"]:
					return null
			ancestor = ancestor.get_parent()
		return branch as Node3D if branch.name in ["ArenaPresentation", "ArenaExterior"] else world
	return null

func _safe_material(material: Material) -> bool:
	if material == null or material.next_pass != null:
		return false
	if material is StandardMaterial3D:
		return material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and (not material.uv1_triplanar or material.uv1_world_triplanar) and (not material.uv2_triplanar or material.uv2_world_triplanar) and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_VERTEX and not material.grow
	if material is ShaderMaterial and material.shader != null:
		if material.shader.resource_path == REFERENCE_SHADER:
			return true
		if material.shader.resource_path == SALVAGE_SHADER:
			return material.get_shader_parameter("world_projection") == true
	return false

func _render_key(source: MeshInstance3D) -> Array:
	var key: Array = []
	for property in RENDER_PROPERTIES:
		key.append(source.get(property))
	return key

func _surfaces(source: MeshInstance3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source.mesh is ArrayMesh and source.mesh.get_blend_shape_count() > 0:
		return result
	if not source.mesh is ArrayMesh and not source.mesh is PrimitiveMesh:
		return result
	for surface in source.mesh.get_surface_count():
		if source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return []
		var material := source.get_active_material(surface)
		if not _safe_material(material):
			return []
		var cache_key := str([source.mesh.get_instance_id(), surface])
		if not _mesh_arrays.has(cache_key):
			_mesh_arrays[cache_key] = source.mesh.surface_get_arrays(surface)
		var arrays: Array = _mesh_arrays[cache_key]
		if arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_VERTEX].is_empty():
			return []
		for slot in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_WEIGHTS + 1):
			if arrays[slot] != null and not arrays[slot].is_empty():
				return []
		var format_key := ""
		for slot in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			format_key += "1" if arrays[slot] != null and not arrays[slot].is_empty() else "0"
		result.append({"material": material, "cache_key": cache_key, "key": str([material.get_instance_id(), format_key])})
	return result

func build() -> void:
	# Baked lightmaps have atlas transforms stored on the original instance.
	if not world.find_children("*", "LightmapGI", true, false).is_empty():
		return
	var pending: Dictionary = {}
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		if source.mesh == null or source.layers == 0 or source.skin != null or source.material_overlay != null or source.has_meta("static_render_batch") or not source.is_visible_in_tree() or source.transparency != 0.0 or source.visibility_parent != NodePath("") or source.custom_aabb != AABB():
			continue
		# Fading depends on the original instance origin.
		if source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0:
			continue
		var scope := _scope(source)
		if scope == null or source.get_viewport() != world.get_viewport():
			continue
		var pose := scope.global_transform.affine_inverse() * source.global_transform
		if pose.basis.determinant() <= 0.000001:
			continue
		var surfaces := _surfaces(source)
		if surfaces.is_empty():
			continue
		var center: Vector3 = (pose * source.mesh.get_aabb()).get_center()
		var cell_size := CELL_SIZE if garage else CELL_SIZE * 0.5
		var cell := Vector3i(floori(center.x / cell_size), floori(center.y / cell_size), floori(center.z / cell_size))
		var properties := _render_key(source)
		var key := str([scope.get_instance_id(), cell, properties])
		if not pending.has(key):
			pending[key] = {"scope": scope, "sources": [], "surfaces": {}, "original_surfaces": 0, "properties": properties}
		var group: Dictionary = pending[key]
		var entry := {"node": weakref(source), "mesh": source.mesh, "pose": pose, "layers": source.layers, "materials": [], "scope": weakref(scope), "properties": properties}
		for surface in surfaces:
			entry.materials.append(surface.material)
			if not group.surfaces.has(surface.key):
				group.surfaces[surface.key] = {"material": surface.material, "entries": []}
			group.surfaces[surface.key].entries.append({"cache_key": surface.cache_key, "pose": pose})
		group.sources.append(entry)
		group.original_surfaces += surfaces.size()
	for group in pending.values():
		if group.original_surfaces > group.surfaces.size():
			_commit(group)
	_mesh_arrays.clear()
	set_process(_preparing or not _groups.is_empty())
	_publish_stats()

func _merge_surface(entries: Array) -> Array:
	var merged: Array = []
	merged.resize(Mesh.ARRAY_MAX)
	merged[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	merged[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	merged[Mesh.ARRAY_TANGENT] = PackedFloat32Array()
	merged[Mesh.ARRAY_COLOR] = PackedColorArray()
	merged[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	merged[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
	merged[Mesh.ARRAY_INDEX] = PackedInt32Array()
	for entry in entries:
		var arrays: Array = _mesh_arrays[entry.cache_key]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offset: int = merged[Mesh.ARRAY_VERTEX].size()
		var pose: Transform3D = entry.pose
		var normals := pose.basis.inverse().transposed()
		for vertex in vertices:
			merged[Mesh.ARRAY_VERTEX].append(pose * vertex)
		if arrays[Mesh.ARRAY_NORMAL] != null:
			for normal in arrays[Mesh.ARRAY_NORMAL]:
				merged[Mesh.ARRAY_NORMAL].append((normals * normal).normalized())
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for index in range(0, tangents.size(), 4):
				var tangent: Vector3 = (pose.basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])).normalized()
				merged[Mesh.ARRAY_TANGENT].append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, tangents[index + 3]]))
		for slot in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if arrays[slot] != null:
				merged[slot].append_array(arrays[slot])
		if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty():
			for index in arrays[Mesh.ARRAY_INDEX]:
				merged[Mesh.ARRAY_INDEX].append(offset + index)
		else:
			for index in vertices.size():
				merged[Mesh.ARRAY_INDEX].append(offset + index)
	for slot in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if merged[slot].is_empty():
			merged[slot] = null
	return merged

func _commit(group: Dictionary) -> void:
	var geometry := ArrayMesh.new()
	for surface in group.surfaces.values():
		geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _merge_surface(surface.entries))
		geometry.surface_set_material(geometry.get_surface_count() - 1, surface.material)
	var batch := MeshInstance3D.new()
	batch.name = "StaticRenderBatch"
	batch.set_meta("static_render_batch", true)
	batch.mesh = geometry
	for index in RENDER_PROPERTIES.size():
		batch.set(RENDER_PROPERTIES[index], group.properties[index])
	group.scope.add_child(batch)
	_serial += 1
	group["render"] = batch
	group["connections"] = []
	group["saved"] = group.original_surfaces - geometry.get_surface_count()
	group.erase("surfaces")
	group["scope"] = weakref(group.scope)
	_groups[_serial] = group
	for entry in group.sources:
		var source: MeshInstance3D = entry.node.get_ref()
		source.layers = 0
		entry["id"] = _serial
		_checks.append(entry)
		var ancestor: Node = source
		var scope: Node3D = group.scope.get_ref()
		while ancestor != scope.get_parent():
			if ancestor is Node3D:
				var callback := _visibility_changed.bind(_serial)
				for signal_name in ["visibility_changed", "tree_exiting"]:
					if not ancestor.is_connected(signal_name, callback):
						ancestor.connect(signal_name, callback)
						group.connections.append({"node": weakref(ancestor), "signal": signal_name, "callback": callback})
			ancestor = ancestor.get_parent()
	stats.sources += group.sources.size()
	stats.batches += 1
	stats.saved_surfaces += group.saved

func _visibility_changed(id: int) -> void:
	_restore_group(id)
	if is_inside_tree() and not is_queued_for_deletion():
		_prepare.call_deferred()

func _materials_unchanged(source: MeshInstance3D, entry: Dictionary) -> bool:
	if source.mesh.get_surface_count() != entry.materials.size():
		return false
	for surface in entry.materials.size():
		if source.get_active_material(surface) != entry.materials[surface]:
			return false
	return true

func _properties_unchanged(source: MeshInstance3D, entry: Dictionary) -> bool:
	for index in range(1, RENDER_PROPERTIES.size()):
		if source.get(RENDER_PROPERTIES[index]) != entry.properties[index]:
			return false
	return source.visibility_parent == NodePath("") and source.custom_aabb == AABB()

func _process(_delta: float) -> void:
	if _prepare_frames > 0:
		_prepare_frames -= 1
		if _prepare_frames == 0:
			_preparing = false
			_prepared = true
			build()
	if not world.can_process():
		return
	for count in mini(12, _checks.size()):
		if _checks.is_empty():
			break
		_cursor %= _checks.size()
		var entry: Dictionary = _checks[_cursor]
		_cursor += 1
		var source: MeshInstance3D = entry.node.get_ref()
		var scope: Node3D = entry.scope.get_ref()
		if not is_instance_valid(source) or not is_instance_valid(scope) or not source.is_inside_tree() or source.mesh != entry.mesh or source.layers != 0 or source.material_overlay != null or source.transparency != 0.0 or not _materials_unchanged(source, entry) or not _properties_unchanged(source, entry) or not (scope.global_transform.affine_inverse() * source.global_transform).is_equal_approx(entry.pose):
			_restore_group(entry.id)

func _restore_group(id: int) -> void:
	if not _groups.has(id):
		return
	var group: Dictionary = _groups[id]
	_groups.erase(id)
	for connection in group.connections:
		var node: Node3D = connection.node.get_ref()
		if is_instance_valid(node) and node.is_connected(connection.signal, connection.callback):
			node.disconnect(connection.signal, connection.callback)
	for entry in group.sources:
		var source: MeshInstance3D = entry.node.get_ref()
		if is_instance_valid(source) and source.layers == 0:
			source.layers = entry.layers
	_checks = _checks.filter(func(entry: Dictionary) -> bool: return entry.id != id)
	var batch: MeshInstance3D = group.render
	if is_instance_valid(batch):
		batch.hide()
		batch.queue_free()
	stats.sources -= group.sources.size()
	stats.batches -= 1
	stats.saved_surfaces -= group.saved
	_publish_stats()
	set_process(_preparing or not _groups.is_empty())

func _publish_stats() -> void:
	if is_instance_valid(world):
		world.set_meta("static_batch_stats", stats.duplicate())

func _exit_tree() -> void:
	for id in _groups.keys():
		_restore_group(id)
	_checks.clear()
	_mesh_arrays.clear()
