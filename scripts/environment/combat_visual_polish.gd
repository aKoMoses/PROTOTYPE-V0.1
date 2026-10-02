extends Node

## A final presentation pass after each scene has built its lights and props.
## No screen-space effects: the same finishes work with the Mobile renderer.
var _finishes: Dictionary = {}

func _ready() -> void:
	call_deferred("_configure")

func _configure() -> void:
	var scene := get_parent()
	var sun := scene.get_node_or_null("ArenaKeyLight") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 0.86
		sun.light_color = Color("#ffcb87")
		sun.shadow_blur = 1.8
		var fill := scene.get_node_or_null("CoolFillLight") as DirectionalLight3D
		if fill != null:
			fill.light_energy = 0.14
		for node in scene.get_children():
			if node is WorldEnvironment:
				node.environment.ambient_light_color = Color("#849dbb")
				node.environment.ambient_light_energy = 0.26
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		_finish_mesh(mesh)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D and get_parent().is_ancestor_of(node):
		_finish_added.call_deferred(weakref(node))

func _finish_added(reference: WeakRef) -> void:
	var mesh := reference.get_ref() as MeshInstance3D
	if is_instance_valid(mesh) and mesh.is_inside_tree():
		_finish_mesh(mesh)

func _finish_mesh(node: MeshInstance3D) -> void:
	if not is_instance_valid(node) or node.mesh == null:
		return
	if node.material_override != null:
		node.material_override = _finish(node.material_override)
	elif node.material_override == null:
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface)
			if source != null and "Salvage /" in source.resource_name:
				node.set_surface_override_material(surface, _finish(source))

func _finish(source: Material) -> Material:
	if not "Salvage /" in source.resource_name:
		return source
	var key := source.get_instance_id()
	if _finishes.has(key):
		return _finishes[key]
	var material := source.duplicate() as Material
	material.resource_name = source.resource_name.replace("Salvage /", "Combat finish /")
	var roughness := 0.96
	var metallic := 0.0
	if "steel" in source.resource_name:
		roughness = 0.46
		metallic = 0.52
	elif "paint" in source.resource_name:
		roughness = 0.70
		metallic = 0.10
	elif not ("cloth" in source.resource_name or "sand" in source.resource_name):
		return source
	if material is StandardMaterial3D:
		material.roughness = roughness
		material.metallic = metallic
	elif material is ShaderMaterial and material.shader.resource_path == "res://shaders/stylized_salvage.gdshader":
		# Preserve the concurrent painted-surface treatment, including its textures.
		material.set_shader_parameter("surface_roughness", roughness)
		material.set_shader_parameter("surface_metallic", metallic)
	else:
		return source
	_finishes[key] = material
	return material
