extends Node3D

## A frozen observation, never a second rendering of the hidden live actor.
## Meshes, bones and colours are sampled only while strict sight is positive.
const DURATION := 0.55

var _meshes: Array[Dictionary] = []
var _skeletons: Array[Dictionary] = []
var _remaining := 0.0
var _known := false
var _position := Vector3.ZERO
var _opacity := 0.0
var _watched: Dictionary = {}
var _skeleton_paths: Dictionary = {}


func configure(visual_root: Node3D) -> void:
	top_level = true
	visible = false
	process_priority = 120
	for source: Skeleton3D in visual_root.find_children("*", "Skeleton3D", true, false):
		_cache_skeleton(source)
	_watch(visual_root)


func _watch(source: Node) -> void:
	if source == self or source is Viewport or _watched.has(source.get_instance_id()):
		return
	var key := source.get_instance_id()
	var exiting := _forget.bind(key)
	_watched[key] = {"source": weakref(source), "exiting": exiting}
	source.child_entered_tree.connect(_watch)
	source.tree_exiting.connect(exiting)
	if source is Skeleton3D:
		_cache_skeleton(source)
	elif source is MeshInstance3D:
		_cache_mesh(source)
	for child in source.get_children():
		_watch(child)


func _forget(key: int) -> void:
	if not _watched.has(key):
		return
	var source := _watched[key].source.get_ref() as Node
	if is_instance_valid(source) and source.child_entered_tree.is_connected(_watch):
		source.child_entered_tree.disconnect(_watch)
	_watched.erase(key)
	_skeleton_paths.erase(key)
	# Keep the last observed mesh and pose until the echo ends or sight returns.
	# Removing a hidden live weapon must not rewrite its frozen observation.


func _exit_tree() -> void:
	for watched: Dictionary in _watched.values():
		var source := watched.source.get_ref() as Node
		if not is_instance_valid(source):
			continue
		if source.child_entered_tree.is_connected(_watch):
			source.child_entered_tree.disconnect(_watch)
		if source.tree_exiting.is_connected(watched.exiting):
			source.tree_exiting.disconnect(watched.exiting)
	_watched.clear()
	_skeleton_paths.clear()


func _cache_skeleton(source: Skeleton3D) -> void:
	if _skeleton_paths.has(source.get_instance_id()):
		return
	for record: Dictionary in _skeletons:
		if record.source.get_ref() == source:
			_skeleton_paths[source.get_instance_id()] = record.snapshot
			return
	var snapshot := Skeleton3D.new()
	snapshot.name = "SnapshotSkeleton%d" % _skeletons.size()
	add_child(snapshot)
	for bone in range(source.get_bone_count()):
		snapshot.add_bone(source.get_bone_name(bone))
		snapshot.set_bone_parent(bone, source.get_bone_parent(bone))
		snapshot.set_bone_rest(bone, source.get_bone_rest(bone))
	_skeletons.append({"source": weakref(source), "snapshot": snapshot})
	_skeleton_paths[source.get_instance_id()] = snapshot


func _cache_mesh(source: MeshInstance3D) -> void:
	if source.mesh == null:
		return
	for record: Dictionary in _meshes:
		if record.source.get_ref() == source:
			return
	var snapshot := MeshInstance3D.new()
	snapshot.name = "SnapshotMesh%d" % _meshes.size()
	snapshot.mesh = source.mesh
	snapshot.skin = source.skin
	snapshot.visible = false
	snapshot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(snapshot)
	var source_skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D
	if source_skeleton != null and _skeleton_paths.has(source_skeleton.get_instance_id()):
		snapshot.skeleton = snapshot.get_path_to(_skeleton_paths[source_skeleton.get_instance_id()])
	var materials: Array[Dictionary] = []
	for surface in range(source.mesh.get_surface_count()):
		var material_record := {"surface": surface}
		_sample_material(source.get_active_material(surface), material_record, snapshot)
		materials.append(material_record)
	_meshes.append({"source": weakref(source), "snapshot": snapshot, "materials": materials})


func _supports_visibility_shader(material: Material) -> bool:
	if material is ShaderMaterial and material.shader != null:
		for uniform in material.shader.get_shader_uniform_list():
			if str(uniform.name) == "visibility_opacity":
				return true
	return false


func _sample_material(source: Material, record: Dictionary, snapshot: MeshInstance3D) -> void:
	var shader_source := source as ShaderMaterial if _supports_visibility_shader(source) else null
	var local: Material = record.get("material")
	if shader_source != null:
		if not local is ShaderMaterial or local.shader != shader_source.shader:
			local = shader_source.duplicate(false) as ShaderMaterial
			record.material = local
			snapshot.set_surface_override_material(int(record.surface), local)
		# Take the complete paint/texture state only while the actor is observed.
		# Hidden chassis changes must never update this frozen observation.
		for uniform in shader_source.shader.get_shader_uniform_list():
			local.set_shader_parameter(uniform.name, shader_source.get_shader_parameter(uniform.name))
		record.opacity = float(shader_source.get_shader_parameter("visibility_opacity"))
		var silhouette: Variant = shader_source.get_shader_parameter("visibility_silhouette")
		record.silhouette = float(silhouette) if silhouette != null else 0.0
		return
	var base_source := source as BaseMaterial3D
	if not local is BaseMaterial3D:
		local = base_source.duplicate(false) as BaseMaterial3D if base_source != null else StandardMaterial3D.new()
		record.material = local
		snapshot.set_surface_override_material(int(record.surface), local)
	var base_local := local as BaseMaterial3D
	base_local.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var observed := base_source if base_source != null else base_local
	record.color = observed.albedo_color
	record.emission = observed.emission
	record.energy = observed.emission_energy_multiplier


func observe(actor_position: Vector3) -> void:
	if not is_inside_tree():
		reset()
		return
	visible = false
	_remaining = 0.0
	_known = true
	_position = actor_position
	global_position = actor_position
	for record: Dictionary in _skeletons:
		var source := record.source.get_ref() as Skeleton3D
		var snapshot: Skeleton3D = record.snapshot
		if not is_instance_valid(source) or not source.is_inside_tree() or not snapshot.is_inside_tree():
			continue
		snapshot.global_transform = source.global_transform
		for bone in range(source.get_bone_count()):
			snapshot.set_bone_pose(bone, source.get_bone_pose(bone))
		snapshot.force_update_all_bone_transforms()
	for record: Dictionary in _meshes:
		var source := record.source.get_ref() as MeshInstance3D
		var snapshot: MeshInstance3D = record.snapshot
		if not is_instance_valid(source) or not source.is_inside_tree() or not snapshot.is_inside_tree():
			snapshot.visible = false
			continue
		snapshot.visible = source.is_visible_in_tree()
		snapshot.global_transform = source.global_transform
		for material_record: Dictionary in record.materials:
			_sample_material(source.get_active_material(int(material_record.surface)), material_record, snapshot)


func begin_loss() -> void:
	if not _known:
		return
	_remaining = DURATION
	visible = true
	_update_materials()


func reset() -> void:
	_remaining = 0.0
	_known = false
	_opacity = 0.0
	visible = false


func get_debug_state() -> Dictionary:
	return {"visible": visible, "remaining": _remaining, "position": _position, "opacity": _opacity}


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - maxf(0.0, delta))
	visible = _remaining > 0.0
	_update_materials()


func _update_materials() -> void:
	var progress := 1.0 - _remaining / DURATION
	_opacity = 1.0 - smoothstep(0.0, 1.0, progress)
	var silhouette := smoothstep(0.0, 0.35, progress)
	for record: Dictionary in _meshes:
		for material_record: Dictionary in record.materials:
			if material_record.material is ShaderMaterial:
				var shader_material: ShaderMaterial = material_record.material
				shader_material.set_shader_parameter("visibility_opacity", float(material_record.opacity) * _opacity)
				if shader_material.get_shader_parameter("visibility_silhouette") != null:
					shader_material.set_shader_parameter("visibility_silhouette", 1.0 - (1.0 - float(material_record.silhouette)) * (1.0 - silhouette))
				continue
			var material: BaseMaterial3D = material_record.material
			var color: Color = material_record.color
			color = color.lerp(Color(0.32, 0.39, 0.48, color.a), silhouette * 0.88)
			color.a *= _opacity
			material.albedo_color = color
			material.emission = material_record.emission * (1.0 - silhouette)
			material.emission_energy_multiplier = float(material_record.energy) * (1.0 - silhouette)
