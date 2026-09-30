extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
var _failures: Array[String] = []


func _initialize() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player: CharacterBody3D = PLAYER.new()
	var reference: CharacterBody3D = PLAYER.new()
	stage.add_child(player)
	stage.add_child(reference)
	player.call("set_gameplay_enabled", false)
	reference.call("set_gameplay_enabled", false)
	await process_frame
	var rig := player.get_node("VisualRoot") as PlayerVisualRig
	var reference_rig := reference.get_node("VisualRoot") as PlayerVisualRig
	var originals := _surface_overrides(rig)
	var reference_originals := _surface_overrides(reference_rig)
	var initial_scale := rig.scale
	var initial_strides: Dictionary = rig.get("_locomotion_reference_speeds").duplicate()
	var original_meshes := _mesh_resources(rig)
	var body_shapes := player.find_children("*", "CollisionShape3D", true, false)
	var original_shape: Shape3D = body_shapes[0].shape
	var clips := rig.animation_player.get_animation_list()
	player.call("set_gameplay_enabled", true)
	player.set_process(false)
	player.set_physics_process(false)
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var pose: Dictionary = {"weapon": &"blaster", "forward": Vector3.ZERO}
	rig.skeleton.skeleton_updated.connect(func() -> void:
		var muzzle := rig.get_weapon_muzzle(pose.weapon)
		if muzzle != null:
			pose.forward = -muzzle.global_basis.z.normalized()
	)
	for entry in [["agile", 0.95, 800.0, 6.0], ["puissant", 1.05, 1200.0, 4.0], ["agile", 0.95, 800.0, 6.0], ["polyvalent", 1.0, 1000.0, 5.0]]:
		var identifier: String = entry[0]
		player.call("set_robot", identifier)
		_check(rig.scale.is_equal_approx(initial_scale * float(entry[1])), "uniform visual scale: " + identifier)
		_check(player.scale == Vector3.ONE and body_shapes[0].shape == original_shape, "physics shape retained: " + identifier)
		_check(_mesh_resources(rig) == original_meshes, "authored meshes retained: " + identifier)
		_check(rig.animation_player.get_animation_list() == clips and rig.animation_tree.active, "animation rig retained: " + identifier)
		_check(float(player.call("get_max_health")) == float(entry[2]) and float(player.call("get_current_move_speed")) == float(entry[3]), "existing chassis stats: " + identifier)
		for state in initial_strides:
			_check(is_equal_approx(float(rig.get("_locomotion_reference_speeds")[state]), float(initial_strides[state]) * float(entry[1])), "stride remains proportional: " + identifier)
		_check(_surface_overrides(reference_rig) == reference_originals and reference_rig.scale == initial_scale, "other player remains original: " + identifier)
		if identifier == "polyvalent":
			_check(_surface_overrides(rig) == originals, "Polyvalent restores original material references")
		else:
			_check(_surface_overrides(rig) != originals, "variant paint is installed: " + identifier)
		for weapon in [&"blaster", &"shotgun"]:
			var socket := rig.get_weapon_socket(weapon)
			_check(socket != null and socket.get_parent() == rig.right_hand_attachment and rig.get_weapon_muzzle(weapon) != null, "hand and muzzle retained: " + identifier + " / " + str(weapon))
			player.call("set_weapon", weapon)
			pose.weapon = weapon
			rig.set_aim_enabled(true)
			rig.configure_left_hand_support(weapon)
			for frame in range(45):
				await process_frame
				player.call("_update_weapon_ambient_motion", 1.0 / 60.0)
				rig.update_visual_state(Vector3.ZERO, Vector3.FORWARD, 0.0, float(entry[3]), 1.0 / 60.0)
				rig.animation_tree.advance(1.0 / 60.0)
				rig.skeleton.advance(1.0 / 60.0)
				await rig.skeleton.skeleton_updated
			_check((pose.forward as Vector3).dot(Vector3.FORWARD) > 0.99999, "scaled muzzle aims forward: " + identifier + " / " + str(weapon))
			_check(rig.aim_modifier.left_grip_reachable and rig.aim_modifier.left_grip_error < 0.003, "support hand follows scaled weapon: " + identifier + " / " + str(weapon))
	player.call("set_robot", "unknown")
	_check(rig.scale == initial_scale and _surface_overrides(rig) == originals, "invalid chassis returns to the original Polyvalent")
	stage.queue_free()
	for frame in range(3):
		await process_frame
	for failure in _failures:
		push_error(failure)
	print("CHASSIS VISUALS TEST: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)


func _surface_overrides(rig: PlayerVisualRig) -> Array:
	var result: Array = []
	for mesh in rig.model_axis_correction.find_children("tripo_part_*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			result.append(mesh.get_surface_override_material(surface))
	return result


func _mesh_resources(rig: PlayerVisualRig) -> Array:
	var result: Array = []
	for mesh in rig.model_axis_correction.find_children("tripo_part_*", "MeshInstance3D", true, false):
		result.append(mesh.mesh)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
