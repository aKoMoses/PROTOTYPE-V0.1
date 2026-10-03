extends SceneTree

## The real garage and Player loadout paths, without touching user save files.
const STAGE := preload("res://scripts/forge_garage_stage.gd")
const PLAYER := preload("res://scripts/player.gd")
const FULL_LOADOUT := {
	"mobility": "pyro_boots", "offensive": "rocket_basket",
	"defensive": "magnetic_field", "passive": "auxiliary_reactor",
}
const CATEGORY_IDS := {
	"mobility": ["pyro_boots", "bio_injector", "permutation", "eclipse"],
	"offensive": ["rocket_basket", "javelin", "fulguro_punch", "pelto_smash"],
	"defensive": ["magnetic_field", "static_shield", "projector", "counter"],
	"passive": ["auxiliary_reactor", "baroud", "omnivamp", "tracker", "alternator", "inertia"],
}
const MOUNT_IDS := {
	"pyro_left": "pyro_boots", "pyro_right": "pyro_boots",
	"bio": "bio_injector", "rocket": "rocket_basket",
	"magnetic": "magnetic_field", "reactor": "auxiliary_reactor",
	"fulguro": "fulguro_punch", "static": "static_shield",
	"javelin": "javelin", "projector": "projector",
	"pelto_smash": "pelto_smash", "counter": "counter",
	"permutation": "permutation", "eclipse": "eclipse",
	"baroud": "baroud", "omnivamp": "omnivamp", "tracker": "tracker",
	"alternator": "alternator", "inertia": "inertia",
}
# Keep each physical accessory around 35 cm on the largest chassis. The
# centimetre tolerance accommodates its animated world-axis bounding box.
const MAX_MOUNT_EXTENT := 0.36
# The approved spherical shoulder eye has a taller pedestal than flat inserts.
const MAX_TRACKER_EXTENT := 0.40
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage = STAGE.new()
	root.add_child(stage)
	await process_frame
	stage.set_process(false)
	var modules = stage.module_visuals
	check(modules.mounts.size() == 19, "nineteen physical mounts for all eighteen authored modules")
	check(not modules.is_processing() and not modules.is_physics_processing(), "accessories require no new frame processing")
	for key in MOUNT_IDS:
		check(modules.mounts.has(key), "mount exists: " + key)
		if not modules.mounts.has(key):
			continue
		var mount: Node3D = modules.mounts[key]
		var attachment := mount.get_parent() as BoneAttachment3D
		check(attachment != null and attachment.get_parent() == stage.skeleton and attachment.bone_idx >= 0, "real skeletal mount: " + key)
		_check_geometry(mount, key)
	for category in CATEGORY_IDS:
		for identifier in CATEGORY_IDS[category]:
			var equipment := FULL_LOADOUT.duplicate()
			equipment[category] = identifier
			stage.set_equipped_modules(equipment)
			_check_visibility(modules, equipment, "garage " + category + " " + identifier)
	stage.set_equipped_modules(FULL_LOADOUT)
	var bio_loadout := FULL_LOADOUT.duplicate()
	bio_loadout.mobility = "bio_injector"
	stage.set_equipped_modules(bio_loadout)
	_check_visibility(modules, bio_loadout, "simultaneous Bio and other three categories")
	var yaw_before: Transform3D = modules.mounts.bio.global_transform
	stage.rotate_robot(0.7)
	check(modules.mounts.bio.global_position.distance_to(yaw_before.origin) > 0.1, "accessories follow robot yaw")
	stage.rotate_robot(-0.7)
	stage.set_equipped_modules(FULL_LOADOUT)
	var attachment: BoneAttachment3D = modules.mounts.pyro_left.get_parent()
	var bind: Transform3D = modules.mounts.pyro_left.transform
	stage.robot_animator.advance(0.55)
	stage.skeleton.force_update_all_bone_transforms()
	await process_frame
	var pose: Transform3D = stage.skeleton.global_transform * stage.skeleton.get_bone_global_pose(attachment.bone_idx)
	check(modules.mounts.pyro_left.global_transform.is_equal_approx(pose * bind), "imported Pyro follows the animated foot")
	var source_meshes := _mesh_resources(stage.robot_model)
	var original_scale: Vector3 = stage.robot.scale
	var mount_scales: Dictionary = {}
	var accessory_meshes: Dictionary = {}
	for key in MOUNT_IDS:
		mount_scales[key] = modules.mounts[key].global_basis.get_scale()
		accessory_meshes[key] = _mesh_resources(modules.mounts[key])
	stage.set_chassis("puissant")
	modules = stage.module_visuals
	check(stage.robot_model.scene_file_path == "res://art/player_mecha_puissant.glb" and _mesh_resources(stage.robot_model) != source_meshes, "powerful chassis uses its authored orange model")
	check(modules.equipment_ids == FULL_LOADOUT and modules.skeleton == stage.skeleton, "all equipped accessories survive rebuilding the orange chassis skeleton")
	_check_visibility(modules, FULL_LOADOUT, "orange chassis retains full equipment")
	var powerful_bindings := {}
	for key in ["javelin", "projector", "pelto_smash", "counter", "permutation", "eclipse", "reactor", "baroud", "omnivamp", "tracker", "alternator", "inertia"]:
		powerful_bindings[key] = modules.mounts[key].transform
	for key in MOUNT_IDS:
		check(_mesh_resources(modules.mounts[key]) == accessory_meshes[key], "chassis replacement preserves shared accessory geometry: " + key)
		check(modules.mounts[key].global_basis.get_scale().is_equal_approx(mount_scales[key] * stage.robot.scale.x / original_scale.x), "accessory scale follows chassis normalization: " + key)
		var mount_bounds := _world_bounds(modules.mounts[key])
		var longest := maxf(mount_bounds.size.x, maxf(mount_bounds.size.y, mount_bounds.size.z))
		print("MODULE FIT ", key, " powerful_world_size=", mount_bounds.size)
		check(longest > 0.01 and longest <= (MAX_TRACKER_EXTENT if key == "tracker" else MAX_MOUNT_EXTENT), "compact physical accessory on powerful chassis: " + key)
	for identifier in modules.MODEL_PATHS:
		var bounds: AABB = modules.module_bounds(identifier)
		check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.x > 0.01 and bounds.size.y > 0.01 and bounds.size.z > 0.01 and bounds.size.length() < 3.0, "finite useful robot-space bounds: " + identifier)
		check(modules.service_point(identifier).is_finite(), "finite service point: " + identifier)
		var triangles: int = modules.triangle_count(identifier)
		print("MODULE GEOMETRY ", identifier, " triangles=", triangles, " bounds=", bounds)
		check(triangles > 256 and triangles < 24000, "bounded imported geometry: " + identifier)
		var path: String = modules.MODEL_PATHS[identifier]
		check(path.begins_with("res://art/modules/") and path.ends_with(".glb") and ResourceLoader.exists(path, "PackedScene"), "authored imported GLB source: " + identifier)
		var display: Node3D = modules.create_display(identifier)
		check(display != null and not display.is_processing(), "static storage display exists: " + identifier)
		if display != null:
			var first_mount: Node3D
			for key in MOUNT_IDS:
				if MOUNT_IDS[key] == identifier:
					first_mount = modules.mounts[key]
					break
			check(_mesh_resources(display) == _mesh_resources(first_mount) and _materials(display) == _materials(first_mount), "storage and installed module share authored meshes and materials: " + identifier)
			display.free()
	var punch_loadout := FULL_LOADOUT.duplicate()
	punch_loadout.offensive = "fulguro_punch"
	punch_loadout.defensive = "static_shield"
	var javelin_loadout := FULL_LOADOUT.duplicate()
	javelin_loadout.offensive = "javelin"
	javelin_loadout.defensive = "projector"
	var phase_loadout := FULL_LOADOUT.merged({"offensive": "pelto_smash", "defensive": "counter", "mobility": "permutation"}, true)
	var eclipse_loadout := phase_loadout.merged({"mobility": "eclipse"}, true)
	var maximal_loadout := javelin_loadout.merged({"defensive": "static_shield", "mobility": "permutation"}, true)
	var budget_kits := [FULL_LOADOUT, punch_loadout, javelin_loadout, phase_loadout, eclipse_loadout, maximal_loadout]
	for passive in CATEGORY_IDS.passive:
		budget_kits.append(maximal_loadout.merged({"passive": passive}, true))
	budget_kits.append(bio_loadout)
	for equipment in budget_kits:
		stage.set_equipped_modules(equipment)
		var module_triangles := 0
		for key in modules.mounts:
			if modules.mounts[key].visible:
				module_triangles += _triangle_count(modules.mounts[key], false)
		print("FULL EQUIPPED MODULES triangles=", module_triangles, " complete_robot=", _triangle_count(stage.robot, true), " mobility=", equipment.mobility)
		check(module_triangles > 0 and module_triangles <= 30000, "compact simultaneous module budget including double Pyro: " + str(equipment.mobility))
	var second = STAGE.new()
	root.add_child(second)
	await process_frame
	second.set_process(false)
	second.set_equipped_modules(FULL_LOADOUT)
	for key in MOUNT_IDS:
		check(_mesh_resources(second.module_visuals.mounts[key]) == _mesh_resources(modules.mounts[key]), "geometry resources shared across robot instances: " + key)
		check(_materials(second.module_visuals.mounts[key]) == _materials(modules.mounts[key]), "opaque material resources shared across robot instances: " + key)
	check(modules.mounts.bio.visible and not second.module_visuals.mounts.bio.visible and second.module_visuals.mounts.pyro_left.visible, "equipped visibility is instance-local")
	second.queue_free()
	stage.queue_free()
	await process_frame
	var scene := Node3D.new()
	var player = PLAYER.new()
	var other = PLAYER.new()
	player.name = "Player"
	scene.add_child(player)
	scene.add_child(other)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	for actor in [player, other]:
		actor.set_gameplay_enabled(false)
		actor.set_process(false)
		actor.set_physics_process(false)
	for category in CATEGORY_IDS:
		for identifier in CATEGORY_IDS[category]:
			var equipment := FULL_LOADOUT.duplicate()
			equipment[category] = identifier
			player.apply_loadout(equipment)
			_check_visibility(player._visual_rig.module_visuals, equipment, "real Player " + category + " " + identifier)
			check(player._visual_rig.module_visuals.equipment_ids.get(category) == identifier, "Player synchronizes category state: " + category + " " + identifier)
	player.apply_loadout(javelin_loadout.merged({"robot": "puissant"}, true))
	for key in powerful_bindings:
		check(player._visual_rig.module_visuals.mounts[key].transform.is_equal_approx(powerful_bindings[key]), "real Player and garage use the same fitted powerful socket: " + key)
	player.apply_loadout(bio_loadout.merged({"robot": "polyvalent"}, true))
	other.apply_loadout(bio_loadout)
	var original_materials: Dictionary = {}
	var original_signatures: Dictionary = {}
	for key in MOUNT_IDS:
		original_materials[key] = _materials(player._visual_rig.module_visuals.mounts[key])
		original_signatures[key] = _material_signatures(other._visual_rig.module_visuals.mounts[key])
	player._visual_rig.set_bush_concealed(true)
	for key in MOUNT_IDS:
		for material in _materials(player._visual_rig.module_visuals.mounts[key]):
			check(material is StandardMaterial3D and is_equal_approx(material.albedo_color.a, player._visual_rig.BUSH_CONCEALED_ALPHA), "camouflage reaches imported accessory materials: " + key)
		check(_material_signatures(other._visual_rig.module_visuals.mounts[key]) == original_signatures[key], "camouflage leaves shared source materials immutable: " + key)
		check(_materials(player._visual_rig.module_visuals.mounts[key]) != _materials(other._visual_rig.module_visuals.mounts[key]), "camouflage material copies remain instance-local: " + key)
	player._visual_rig.set_bush_concealed(false)
	for key in MOUNT_IDS:
		check(_materials(player._visual_rig.module_visuals.mounts[key]) == original_materials[key], "camouflage restores exact source resources: " + key)
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("ROBOT MODULE VISUALS TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)


func _check_visibility(modules, equipment: Dictionary, label: String) -> void:
	for key in MOUNT_IDS:
		var identifier: String = MOUNT_IDS[key]
		check(modules.mounts[key].visible == equipment.values().has(identifier), label + " equipped visibility: " + key)


func _check_geometry(mount: Node3D, label: String) -> void:
	var meshes := mount.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "imported mesh instances exist: " + label)
	for node in mount.find_children("*", "Node", true, false):
		check(node.get_script() == null and not node.is_processing() and not node.is_physics_processing(), "static imported detail: " + label + " " + str(node.name))
	for child in meshes:
		var mesh: Mesh = child.mesh
		check(mesh is ArrayMesh and not mesh is PrimitiveMesh, "authored geometry replaces primitive batches: " + label)
		for surface in mesh.get_surface_count():
			var material: Material = child.get_active_material(surface)
			check(material is StandardMaterial3D and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(material.albedo_color.a, 1.0), "opaque imported material: " + label + " " + str(surface))
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			check(not indices.is_empty() and indices.size() % 3 == 0, "indexed triangle geometry: " + label + " " + str(surface))
			check(normals.size() == vertices.size(), "normal for every vertex: " + label + " " + str(surface))
			var finite_vertices := true
			var finite_normals := true
			var valid_indices := true
			var referenced: Dictionary = {}
			for vertex in vertices:
				finite_vertices = finite_vertices and vertex.is_finite()
			for normal in normals:
				finite_normals = finite_normals and normal.is_finite() and normal.length_squared() > 0.5 and normal.length_squared() < 1.5
			for index in indices:
				valid_indices = valid_indices and index >= 0 and index < vertices.size()
				referenced[index] = true
			check(finite_vertices and finite_normals and valid_indices, "finite vertices, useful normals and valid indices: " + label + " " + str(surface))
			check(referenced.size() == vertices.size(), "every imported vertex referenced: " + label + " " + str(surface))


func _mesh_resources(node: Node3D) -> Array:
	var result: Array = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		result.append(child.mesh)
	return result


func _world_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var next: AABB = child.global_transform * child.mesh.get_aabb()
		result = next if first else result.merge(next)
		first = false
	return result


func _materials(node: Node3D) -> Array:
	var result: Array = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		for surface in child.mesh.get_surface_count():
			result.append(child.get_active_material(surface))
	return result


func _material_signatures(node: Node3D) -> Array:
	var result: Array = []
	for material in _materials(node):
		result.append([material, material.albedo_color, material.transparency, material.roughness, material.metallic, material.emission_enabled, material.emission, material.emission_energy_multiplier])
	return result


func _triangle_count(node: Node3D, visible_only: bool) -> int:
	var total := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if visible_only and not child.is_visible_in_tree():
			continue
		for surface in child.mesh.get_surface_count():
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			total += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
