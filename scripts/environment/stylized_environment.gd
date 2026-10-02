extends Node
## Shared visual finish for the existing maps. Deferred until the scene and
## its art directors are ready; never scans actors, UI or transient combat FX.
const SURFACE := preload("res://shaders/stylized_salvage.gdshader")
const FLOOR := preload("res://shaders/stylized_courtyard.gdshader")
const CONCRETE := preload("res://art/environment/courtyard_concrete_detail.png")
const PAINT := preload("res://art/environment/courtyard_paint_albedo.png")
const STEEL := preload("res://art/environment/courtyard_steel_albedo.png")
const SCENES := ["res://scripts/main.gd", "res://scripts/training_ground.gd", "res://scripts/survival.gd"]
var enabled := true
var _materials: Dictionary = {}
var _bevels: Dictionary = {}
var _scenes: Array[WeakRef] = []
var _secondary_suns: Array[WeakRef] = []
var _quality_clock := 0.0

func _ready() -> void:
	enabled = not OS.get_cmdline_user_args().has("stylized-baseline")
	get_tree().node_added.connect(_on_node_added)
	set_process(false)
	# SceneTree capture/test scripts can instantiate a map in _initialize,
	# before autoloads reach _ready. Finish those maps too.
	for node in get_tree().root.get_children():
		if node is Node3D:
			_on_node_added(node)

func _process(delta: float) -> void:
	_quality_clock += delta
	if _quality_clock >= 0.5:
		_quality_clock = 0.0
		_update_quality()

func _update_quality() -> void:
	var active: Array[WeakRef] = []
	for reference in _secondary_suns:
		var sun := reference.get_ref() as DirectionalLight3D
		if sun != null:
			var vfx := sun.get_parent().get_node_or_null("VFXManager")
			sun.shadow_enabled = vfx == null or int(vfx.get("quality")) > 0
			active.append(reference)
	_secondary_suns = active
	set_process(not _secondary_suns.is_empty())

func _on_node_added(node: Node) -> void:
	if not enabled:
		return
	if node is Node3D and node.get_script() != null and node.get_script().resource_path in SCENES:
		_prepare_added_scene.call_deferred(weakref(node))
	elif node is MeshInstance3D:
		# Handles factory extensions and the test arena created after _ready.
		var ancestor := node.get_parent()
		while ancestor != null:
			if ancestor.has_meta("stylized_environment_ready"):
				if _environment_mesh(node, ancestor):
					_finish_added.call_deferred(weakref(node), weakref(ancestor))
				return
			ancestor = ancestor.get_parent()

func _prepare_added_scene(reference: WeakRef) -> void:
	var scene := reference.get_ref() as Node3D
	if scene != null:
		await _prepare_scene(scene)

func _prepare_scene(scene: Node3D) -> void:
	await get_tree().process_frame
	if not is_instance_valid(scene) or not scene.is_inside_tree():
		return
	var active: Array[WeakRef] = []
	for reference in _scenes:
		if reference.get_ref() != null:
			active.append(reference)
	if active.is_empty():
		_materials.clear()
		_bevels.clear()
	_scenes = active
	if not _scenes.any(func(reference: WeakRef) -> bool: return reference.get_ref() == scene):
		_scenes.append(weakref(scene))
	if not scene.has_meta("stylized_environment_ready"):
		_configure_secondary_lighting(scene)
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		_finish_mesh(mesh, scene)
	scene.set_meta("stylized_environment_ready", true)

func _configure_secondary_lighting(scene: Node3D) -> void:
	# The duel's authored directors own its dusk lighting. Bring the standalone
	# training/survival arenas into the same warm-key / cool-shadow vocabulary.
	if scene.get_script().resource_path == "res://scripts/main.gd":
		return
	for node in scene.get_children():
		if node is WorldEnvironment:
			node.environment.ambient_light_color = Color("#a2b8cb")
			node.environment.ambient_light_energy = 0.38
			node.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		elif node is DirectionalLight3D:
			node.light_color = Color("#ffe0b3")
			node.light_energy = 0.78
			node.rotation_degrees = Vector3(-43, -36, 0)
			node.shadow_enabled = true
			node.shadow_blur = 1.5
			node.directional_shadow_max_distance = 58.0
			node.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_secondary_suns.append(weakref(node))
	var fill := DirectionalLight3D.new()
	fill.name = "PaintedCourtyardFill"
	fill.light_color = Color("#91b5d4")
	fill.light_energy = 0.12
	fill.rotation_degrees = Vector3(-38, 145, 0)
	fill.shadow_enabled = false
	scene.add_child(fill)
	_update_quality()

func _finish_added(mesh_reference: WeakRef, scene_reference: WeakRef) -> void:
	var mesh := mesh_reference.get_ref() as MeshInstance3D
	var scene := scene_reference.get_ref() as Node
	if mesh != null and scene != null and mesh.is_inside_tree() and scene.is_ancestor_of(mesh):
		_finish_mesh(mesh, scene)

func _environment_mesh(mesh: MeshInstance3D, scene: Node) -> bool:
	var branch: Node = mesh
	while branch.get_parent() != scene:
		branch = branch.get_parent()
		if branch == null:
			return false
	# These are all visual environment roots, including factory-created bodies.
	if branch.name in ["ArenaPresentation", "ArenaExterior", "TestArena", "Ground", "TrainingFloor", "Floor", "FactoryFloor", "PassageFloor"]:
		return true
	if branch.is_in_group("arena_solid") or branch.get_meta("blocks_navigation", false):
		return true
	# Actor names may change with builds or future factory waves. A scripted
	# actor can never become scenery merely because its name matches a prefix.
	if branch.get_script() != null or branch.is_in_group("prototype0_fx_budget") or branch.is_in_group("prototype0_gameplay_projectiles"):
		return false
	var label := String(branch.name)
	if scene.get_script().resource_path == "res://scripts/training_ground.gd":
		return label.begins_with("Fixed") or label.begins_with("Moving") or label.begins_with("Shooter") or label.ends_with("Wall") or label.ends_with("Crates")
	if scene.get_script().resource_path == "res://scripts/survival.gd":
		return label.begins_with("Wreck") or label.begins_with("BorderWreck") or label.begins_with("Scrap") or label.ends_with("Wall") or label.begins_with("Factory")
	return false

func _finish_mesh(mesh: MeshInstance3D, scene: Node) -> void:
	if mesh.mesh == null or mesh.has_meta("stylized_finish") or not _environment_mesh(mesh, scene):
		return
	var label := String(mesh.name)
	var parent_label := String(mesh.get_parent().name)
	if label == "Ground" or parent_label in ["TrainingFloor", "Floor", "FactoryFloor", "PassageFloor"]:
		_finish_floor(mesh)
		return
	var source := mesh.material_override as StandardMaterial3D
	var changed := false
	if source != null:
		var finish := _paint(source)
		if finish != null:
			mesh.material_override = finish
			changed = true
			if mesh.mesh is BoxMesh:
				var box := mesh.mesh as BoxMesh
				if minf(box.size.x, minf(box.size.y, box.size.z)) >= 0.18:
					mesh.mesh = beveled_box(box.size)
	else:
		for surface in mesh.mesh.get_surface_count():
			source = mesh.get_active_material(surface) as StandardMaterial3D
			if source != null:
				var finish := _paint(source)
				if finish != null:
					mesh.set_surface_override_material(surface, finish)
					changed = true
	if changed:
		mesh.set_meta("stylized_finish", true)

func _finish_floor(mesh: MeshInstance3D) -> void:
	var source := mesh.material_override
	var finish := ShaderMaterial.new()
	finish.shader = FLOOR
	finish.resource_name = "Painted courtyard / ground"
	finish.set_shader_parameter("concrete_detail", CONCRETE)
	if source is ShaderMaterial and source.shader.resource_path == "res://shaders/courtyard_ground.gdshader":
		for parameter in ["layout_albedo", "surface_normal"]:
			finish.set_shader_parameter(parameter, source.get_shader_parameter(parameter))
	elif source is StandardMaterial3D:
		finish.set_shader_parameter("use_layout", false)
		finish.set_shader_parameter("floor_tint", Color("#999486") if mesh.get_parent().name == "TrainingFloor" else Color("#8e968f"))
	else:
		return
	mesh.material_override = finish
	mesh.set_meta("stylized_finish", true)

func _paint(source: StandardMaterial3D) -> ShaderMaterial:
	# Glow, translucency, foliage and gameplay markers keep their own pipeline.
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.emission_enabled or source.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or source.albedo_color.a < 0.99:
		return null
	if source.uv1_triplanar and not source.uv1_world_triplanar:
		return null
	if source.cull_mode != BaseMaterial3D.CULL_BACK:
		return null
	if _materials.has(source):
		return _materials[source]
	var finish := ShaderMaterial.new()
	finish.shader = SURFACE
	finish.resource_name = "Painted courtyard / " + source.resource_name
	finish.set_shader_parameter("source_tint", source.albedo_color)
	finish.set_shader_parameter("vertex_tint", source.vertex_color_use_as_albedo)
	finish.set_shader_parameter("has_texture", source.albedo_texture != null)
	finish.set_shader_parameter("world_projection", source.uv1_world_triplanar)
	finish.set_shader_parameter("texture_scale", source.uv1_scale)
	finish.set_shader_parameter("texture_offset", source.uv1_offset)
	if source.albedo_texture != null:
		var texture_path := source.albedo_texture.resource_path
		var texture := source.albedo_texture
		if texture_path.ends_with("metal_cream.svg") or texture_path.ends_with("metal_rust.svg"):
			texture = PAINT
		elif texture_path.ends_with("steel_dark.svg"):
			texture = STEEL
		finish.set_shader_parameter("color_texture", texture)
		if texture != source.albedo_texture:
			finish.set_shader_parameter("world_projection", true)
			finish.set_shader_parameter("texture_scale", Vector3.ONE * 0.42)
		var pigment := Color("#c4b79c")
		if "steel" in texture_path:
			pigment = Color("#8dabb6")
		elif "rust" in texture_path:
			pigment = Color("#ae7656")
		elif "paint" in texture_path or "cream" in texture_path:
			pigment = Color("#d9c7a4")
		elif "banner" in texture_path:
			pigment = Color("#a75a47")
		finish.set_shader_parameter("pigment_color", pigment)
		finish.set_shader_parameter("pigment_strength", 0.12)
	else:
		finish.set_shader_parameter("has_texture", true)
		finish.set_shader_parameter("normalized_texture", true)
		finish.set_shader_parameter("color_texture", PAINT)
		finish.set_shader_parameter("world_projection", true)
		finish.set_shader_parameter("texture_scale", Vector3.ONE * 0.32)
	finish.set_shader_parameter("has_relief", source.normal_enabled and source.normal_texture != null)
	if source.normal_texture != null:
		finish.set_shader_parameter("relief_texture", source.normal_texture)
	finish.set_shader_parameter("relief_strength", source.normal_scale * 0.65)
	finish.set_shader_parameter("surface_roughness", clampf(source.roughness, 0.48, 0.96))
	finish.set_shader_parameter("surface_metallic", minf(source.metallic, 0.50))
	# Cloth/dust stay calm and matte; manufactured plates have stronger planes.
	var soft := "cloth" in source.resource_name or "sand" in source.resource_name
	finish.set_shader_parameter("sculpt_strength", 0.05 if soft else 0.15)
	_materials[source] = finish
	return finish

func beveled_box(size: Vector3) -> ArrayMesh:
	if _bevels.has(size):
		return _bevels[size]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var h := size * 0.5
	var cut := minf(0.10, minf(h.x, minf(h.y, h.z)) * 0.18)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			var points: Array[Vector3] = []
			normal[axis] = sign_value
			for signs in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = sign_value * h[axis]
				point[u] = signs.x * (h[u] - cut)
				point[v] = signs.y * (h[v] - cut)
				points.append(point)
			_polygon(points, normal, vertices, normals, uvs)
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for sa in [-1.0, 1.0]:
					for state in [0, 1]:
						var point := Vector3.ZERO
						point[axis] = sa * (h[axis] - cut)
						point[u] = su * (h[u] - cut * state)
						point[v] = sv * (h[v] - cut * (1 - state))
						points.append(point)
				var normal := Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				_polygon([points[0], points[1], points[3], points[2]], normal.normalized(), vertices, normals, uvs)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var signs := Vector3(sx, sy, sz)
				var points: Array[Vector3] = []
				for axis in range(3):
					var point := signs * (h - Vector3.ONE * cut)
					point[axis] = signs[axis] * h[axis]
					points.append(point)
				_polygon(points, signs.normalized(), vertices, normals, uvs)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = "Chamfered salvage block"
	_bevels[size] = mesh
	return mesh

func _polygon(points: Array[Vector3], normal: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array) -> void:
	for index in range(1, points.size() - 1):
		var triangle: Array[Vector3] = [points[0], points[index], points[index + 1]]
		if (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).dot(normal) > 0.0:
			var swap := triangle[1]
			triangle[1] = triangle[2]
			triangle[2] = swap
		for point in triangle:
			vertices.append(point)
			normals.append(normal)
			var axes := Vector2(point.z, -point.y) if absf(normal.x) > 0.7 else Vector2(point.x, point.z) if absf(normal.y) > 0.7 else Vector2(point.x, -point.y)
			uvs.append(axes * 0.42)
