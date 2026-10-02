extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stage = preload("res://scripts/forge_garage_stage.gd").new()
	root.add_child(stage)
	await process_frame
	stage.set_process(false)
	var modules = stage.module_visuals
	check(modules.mounts.size() == 3, "two ankle mounts and one torso mount")
	for identifier in ["pyro_boots", "bio_injector", "permutation", "eclipse"]:
		stage.set_mobility_module(identifier)
		for key in modules.mounts:
			var expected: bool = identifier == ("bio_injector" if key == "bio" else "pyro_boots")
			check(modules.mounts[key].visible == expected, "equipped accessory only: " + identifier + " " + key)
	for key in modules.mounts:
		var mount: Node3D = modules.mounts[key]
		var attachment := mount.get_parent() as BoneAttachment3D
		check(attachment != null and attachment.get_parent() == stage.skeleton and attachment.bone_idx >= 0, "real skeletal mount: " + key)
		for child in mount.get_children():
			if child is MeshInstance3D:
				check(child.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque material: " + key + " " + str(child.name))
				var arrays: Array = child.mesh.surface_get_arrays(0)
				var referenced: Dictionary = {}
				for vertex in arrays[Mesh.ARRAY_INDEX]:
					referenced[vertex] = true
				check(referenced.size() == arrays[Mesh.ARRAY_VERTEX].size(), "material batches reference every part of the geometry: " + key + " " + str(child.name))
	var yaw_before: Transform3D = modules.mounts.bio.global_transform
	stage.rotate_robot(0.7)
	check(modules.mounts.bio.global_position.distance_to(yaw_before.origin) > 0.1, "modules follow robot yaw")
	stage.rotate_robot(-0.7)
	stage.set_mobility_module("pyro_boots")
	var attachment: BoneAttachment3D = modules.mounts.pyro_left.get_parent()
	var bind: Transform3D = modules.mounts.pyro_left.transform
	stage.robot_animator.advance(0.55)
	stage.skeleton.force_update_all_bone_transforms()
	await process_frame
	var pose: Transform3D = stage.skeleton.global_transform * stage.skeleton.get_bone_global_pose(attachment.bone_idx)
	check(modules.mounts.pyro_left.global_transform.is_equal_approx(pose * bind), "accessory follows the animated foot")
	stage.set_chassis("puissant")
	modules = stage.module_visuals
	check(modules.mobility_id == "pyro_boots" and modules.mounts.pyro_left.visible and modules.skeleton == stage.skeleton, "accessories rebuilt on the orange chassis skeleton")
	for identifier in ["pyro_boots", "bio_injector"]:
		var triangles: int = modules.triangle_count(identifier)
		print("MODULE GEOMETRY ", identifier, " triangles=", triangles)
		check(triangles > 0 and triangles < 2500, "bounded geometry: " + identifier)
	var second = preload("res://scripts/forge_garage_stage.gd").new()
	root.add_child(second)
	await process_frame
	second.set_process(false)
	check(second.module_visuals.mounts.bio.get_node("steel").mesh == modules.mounts.bio.get_node("steel").mesh, "mesh resources shared across robots")
	second.set_mobility_module("bio_injector")
	check(not modules.mounts.bio.visible and second.module_visuals.mounts.bio.visible, "visibility is instance-local")
	second.queue_free()
	stage.queue_free()
	await process_frame
	var scene := Node3D.new()
	var player = load("res://scripts/player.gd").new()
	player.name = "Player"
	scene.add_child(player)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	for identifier in ["pyro_boots", "bio_injector", "eclipse"]:
		player.apply_loadout({"mobility": identifier})
		check(player._visual_rig.module_visuals.mobility_id == identifier, "production Player synchronizes accessories: " + identifier)
	player.apply_loadout({"mobility": "bio_injector"})
	player._visual_rig.set_bush_concealed(true)
	var material: StandardMaterial3D = player._visual_rig.module_visuals.mounts.bio.get_node("steel").material_override
	check(is_equal_approx(material.albedo_color.a, player._visual_rig.BUSH_CONCEALED_ALPHA), "accessories participate in camouflage")
	player._visual_rig.set_bush_concealed(false)
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("ROBOT MODULE VISUALS TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
