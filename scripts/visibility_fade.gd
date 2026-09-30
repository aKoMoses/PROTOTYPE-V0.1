extends Node

## Per-actor fading that also works with the Mobile renderer. Imported/shared
## materials stay untouched; runtime popup and status fades compose with vision.
## SceneTree restores before presentation updates, then this late process pass
## fades the final colors (including temporary VFXManager hit overlays).

var _opacity := 1.0
var _silhouette := 0.0
var _detail_opacity := 1.0
var _body_root: Node
var _applied := false
var _entries: Dictionary = {}
var _watched: Dictionary = {}
var _frame_tree: SceneTree


func configure(roots: Array) -> void:
	reset()
	process_priority = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	for root: Variant in roots:
		if root is Node and is_instance_valid(root):
			if _body_root == null:
				_body_root = root
			_watch(root)
	if is_inside_tree():
		_frame_tree = get_tree()
		if not _frame_tree.process_frame.is_connected(restore):
			_frame_tree.process_frame.connect(restore)
	set_process(true)


func apply_opacity(weight: float) -> void:
	apply_presentation(weight, 0.0, weight)


func apply_presentation(weight: float, silhouette: float, detail_opacity: float) -> void:
	restore()
	_opacity = clampf(weight, 0.0, 1.0)
	_silhouette = clampf(silhouette, 0.0, 1.0)
	_detail_opacity = clampf(detail_opacity, 0.0, 1.0)
	# Fully hidden actors are gated by their presentation roots. Both endpoints
	# keep normal material rendering, with no recursive tree scans each frame.
	if _opacity <= 0.0 or (_opacity >= 1.0 and _silhouette <= 0.0 and _detail_opacity >= 1.0):
		return
	_apply_cached(false)


func restore() -> void:
	if not _applied:
		return
	for entry: Dictionary in _entries.values():
		_restore_entry(entry)
	_applied = false


func reset() -> void:
	restore()
	for entry: Dictionary in _entries.values():
		_restore_assignments(entry)
	for record: Dictionary in _watched.values():
		var node := record.node.get_ref() as Node
		if not is_instance_valid(node):
			continue
		if node.child_entered_tree.is_connected(_watch):
			node.child_entered_tree.disconnect(_watch)
		if node.tree_exiting.is_connected(record.exiting):
			node.tree_exiting.disconnect(record.exiting)
	_entries.clear()
	_watched.clear()
	_opacity = 1.0
	_silhouette = 0.0
	_detail_opacity = 1.0
	_body_root = null


func get_debug_counts() -> Dictionary:
	var materials := 0
	for entry: Dictionary in _entries.values():
		materials += entry.materials.size()
	return {"visuals": _entries.size(), "materials": materials, "opacity": _opacity, "silhouette": _silhouette, "detail_opacity": _detail_opacity}


func _process(_delta: float) -> void:
	if _opacity <= 0.0 or (_opacity >= 1.0 and _silhouette <= 0.0 and _detail_opacity >= 1.0):
		return
	# DamagePopup and StatusVFX update after their target's _process. Refade
	# their final values after those updates and VFXManager's priority-100 pass.
	restore()
	_apply_cached(true)


func _exit_tree() -> void:
	reset()
	if _frame_tree != null and _frame_tree.process_frame.is_connected(restore):
		_frame_tree.process_frame.disconnect(restore)
	_frame_tree = null


func _watch(node: Node) -> void:
	# Health UI is rendered to a viewport texture, then faded through its
	# Sprite3D outside that viewport. Its many 2D controls need no watchers.
	if node == self or node is Viewport or _watched.has(node.get_instance_id()):
		return
	var key := node.get_instance_id()
	var exiting := _forget.bind(key)
	_watched[key] = {"node": weakref(node), "exiting": exiting}
	node.child_entered_tree.connect(_watch)
	node.tree_exiting.connect(exiting)
	if node is MeshInstance3D or node is GPUParticles3D or node is Sprite3D or node is AnimatedSprite3D or node is Label3D:
		_cache_visual(node)
	for child: Node in node.get_children():
		_watch(child)


func _forget(key: int) -> void:
	if _entries.has(key):
		_restore_entry(_entries[key])
		_restore_assignments(_entries[key])
		_entries.erase(key)
	if _watched.has(key):
		var node := _watched[key].node.get_ref() as Node
		if is_instance_valid(node) and node.child_entered_tree.is_connected(_watch):
			node.child_entered_tree.disconnect(_watch)
		_watched.erase(key)


func _cache_visual(node: Node) -> void:
	var entry := {"node": weakref(node), "materials": [], "slots": [], "color_active": false, "outline_active": false, "overlay_active": false, "overlay_source": null, "overlay_copy": null}
	entry.body = node == _body_root or (_body_root != null and _body_root.is_ancestor_of(node))
	_entries[node.get_instance_id()] = entry
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if _supports_material(instance.material_override):
			var local := _local_material(instance.material_override, entry)
			entry.slots.append({"kind": "override", "source": instance.material_override, "local": local})
			instance.material_override = local
		elif instance.material_override == null and instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				var source := instance.get_active_material(surface)
				if source != null and not _supports_material(source):
					continue
				var local := _local_material(source, entry)
				entry.slots.append({"kind": "surface", "index": surface, "source": instance.get_surface_override_material(surface), "local": local})
				instance.set_surface_override_material(surface, local)
		entry.override_assignment = instance.material_override
		entry.surface_assignments = []
		if instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				entry.surface_assignments.append(instance.get_surface_override_material(surface))
	elif node is GPUParticles3D:
		var particles := node as GPUParticles3D
		for pass_index in range(particles.draw_passes):
			var source_mesh := particles.get_draw_pass_mesh(pass_index)
			if source_mesh == null:
				continue
			var local_mesh := source_mesh.duplicate(false) as Mesh
			for surface in range(source_mesh.get_surface_count()):
				var source := source_mesh.surface_get_material(surface)
				if source != null and not _supports_material(source):
					continue
				local_mesh.surface_set_material(surface, _local_material(source, entry))
			entry.slots.append({"kind": "draw_pass", "index": pass_index, "source": source_mesh, "local": local_mesh})
			particles.set_draw_pass_mesh(pass_index, local_mesh)


func _supports_material(material: Material) -> bool:
	if material is BaseMaterial3D:
		return true
	if material is ShaderMaterial and material.shader != null:
		for uniform in material.shader.get_shader_uniform_list():
			if str(uniform.name) == "visibility_opacity":
				return true
	return false


func _local_material(source: Material, entry: Dictionary) -> Material:
	var local := source.duplicate(false) as Material if source != null else StandardMaterial3D.new()
	entry.materials.append({"material": local, "active": false})
	return local


func _refresh_material_assignments(entry: Dictionary, node: MeshInstance3D) -> Dictionary:
	var changed: bool = node.material_override != entry.override_assignment
	if node.mesh != null:
		changed = changed or node.mesh.get_surface_count() != entry.surface_assignments.size()
		if not changed:
			for surface in range(node.mesh.get_surface_count()):
				if node.get_surface_override_material(surface) != entry.surface_assignments[surface]:
					changed = true
					break
	if changed:
		# Chassis selection replaces surface overrides after the watcher was set up.
		# Retire our copies without replacing any newly assigned external material.
		_restore_entry(entry)
		_restore_assignments(entry)
		_cache_visual(node)
		return _entries[node.get_instance_id()]
	return entry


func _apply_cached(include_overlays: bool) -> void:
	for cached_entry: Dictionary in _entries.values():
		var entry := cached_entry
		var node := entry.node.get_ref() as Node3D
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		if node is MeshInstance3D:
			entry = _refresh_material_assignments(entry, node)
		var opacity := _opacity if bool(entry.body) else _detail_opacity
		var silhouette := _silhouette if bool(entry.body) else 0.0
		for record: Dictionary in entry.materials:
			_fade_material(record, opacity, silhouette)
		if node is Sprite3D or node is AnimatedSprite3D or node is Label3D:
			entry.color = node.modulate
			var color: Color = entry.color
			color.a *= opacity
			entry.faded_color = color
			node.modulate = color
			entry.color_active = true
			if node is Label3D:
				entry.outline = node.outline_modulate
				var outline: Color = entry.outline
				outline.a *= opacity
				entry.faded_outline = outline
				node.outline_modulate = outline
				entry.outline_active = true
		if include_overlays and node is MeshInstance3D:
			_fade_overlay(node, entry, opacity, silhouette)
	_applied = true


func _fade_material(record: Dictionary, opacity: float, silhouette: float) -> void:
	if record.material is ShaderMaterial:
		var shader_material: ShaderMaterial = record.material
		record.opacity = float(shader_material.get_shader_parameter("visibility_opacity"))
		var original_silhouette: Variant = shader_material.get_shader_parameter("visibility_silhouette")
		record.silhouette = float(original_silhouette) if original_silhouette != null else 0.0
		record.faded_opacity = float(record.opacity) * opacity
		record.faded_silhouette = 1.0 - (1.0 - float(record.silhouette)) * (1.0 - silhouette)
		shader_material.set_shader_parameter("visibility_opacity", record.faded_opacity)
		if original_silhouette != null:
			shader_material.set_shader_parameter("visibility_silhouette", record.faded_silhouette)
		record.active = true
		return
	var material: BaseMaterial3D = record.material
	record.color = material.albedo_color
	record.transparency = material.transparency
	record.emission = material.emission
	record.emission_energy = material.emission_energy_multiplier
	var color: Color = record.color
	# A muted cool shape keeps the robot readable without its normal bright
	# armour and weapon lights. The original materials are restored each frame.
	color = color.lerp(Color(0.32, 0.39, 0.48, color.a), silhouette * 0.88)
	color.a *= opacity
	record.faded_color = color
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	record.faded_emission = material.emission * (1.0 - silhouette)
	record.faded_emission_energy = material.emission_energy_multiplier * (1.0 - silhouette)
	material.emission = record.faded_emission
	material.emission_energy_multiplier = record.faded_emission_energy
	record.active = true


func _fade_overlay(node: MeshInstance3D, entry: Dictionary, opacity: float, silhouette: float) -> void:
	var source := node.material_overlay as BaseMaterial3D
	if source == null:
		return
	if entry.overlay_source != source:
		entry.overlay_source = source
		entry.overlay_copy = source.duplicate(false) as BaseMaterial3D
	var local: BaseMaterial3D = entry.overlay_copy
	var color := source.albedo_color
	color.a *= opacity * (1.0 - silhouette)
	local.albedo_color = color
	local.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_overlay = local
	entry.overlay_active = true


func _restore_entry(entry: Dictionary) -> void:
	for record: Dictionary in entry.materials:
		if not record.active:
			continue
		if record.material is ShaderMaterial:
			var shader_material: ShaderMaterial = record.material
			if is_equal_approx(float(shader_material.get_shader_parameter("visibility_opacity")), float(record.faded_opacity)):
				shader_material.set_shader_parameter("visibility_opacity", record.opacity)
			var current_silhouette: Variant = shader_material.get_shader_parameter("visibility_silhouette")
			if current_silhouette != null and is_equal_approx(float(current_silhouette), float(record.faded_silhouette)):
				shader_material.set_shader_parameter("visibility_silhouette", record.silhouette)
			record.active = false
			continue
		var material: BaseMaterial3D = record.material
		# Preserve external animation changes made since our previous application.
		if material.albedo_color == record.faded_color:
			material.albedo_color = record.color
		if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			material.transparency = record.transparency
		if material.emission == record.faded_emission:
			material.emission = record.emission
		if is_equal_approx(material.emission_energy_multiplier, record.faded_emission_energy):
			material.emission_energy_multiplier = record.emission_energy
		record.active = false
	var node := entry.node.get_ref() as Node3D
	if not is_instance_valid(node):
		return
	if entry.color_active:
		if node.modulate == entry.faded_color:
			node.modulate = entry.color
		entry.color_active = false
	if entry.outline_active:
		if node.outline_modulate == entry.faded_outline:
			node.outline_modulate = entry.outline
		entry.outline_active = false
	if entry.overlay_active:
		if node.material_overlay == entry.overlay_copy:
			node.material_overlay = entry.overlay_source
		entry.overlay_active = false


func _restore_assignments(entry: Dictionary) -> void:
	var node := entry.node.get_ref() as Node3D
	if not is_instance_valid(node):
		return
	for slot: Dictionary in entry.slots:
		match slot.kind:
			"override":
				if node.material_override == slot.local:
					node.material_override = slot.source
			"surface":
				if node.get_surface_override_material(slot.index) == slot.local:
					node.set_surface_override_material(slot.index, slot.source)
			"draw_pass":
				if node.get_draw_pass_mesh(slot.index) == slot.local:
					node.set_draw_pass_mesh(slot.index, slot.source)
