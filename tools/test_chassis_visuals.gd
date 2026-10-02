extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	var originals := _material_signature(rig)
	var reference_originals := _surface_overrides(reference_rig)
	var initial_scale := rig.scale
	var initial_strides: Dictionary = rig.get("_locomotion_reference_speeds").duplicate()
	var original_meshes := _mesh_resources(rig)
	var body_shapes := player.find_children("*", "CollisionShape3D", true, false)
	var original_shape: Shape3D = body_shapes[0].shape
	var clips := rig.animation_player.get_animation_list()
	var weight := preload("res://scripts/mecha_weight_modifier.gd").new()
	rig.skeleton.add_child(weight)
	var weapons: Dictionary = {}
	for weapon in [&"blaster", &"shotgun", &"longshot", &"mekatana"]:
		weapons[weapon] = rig.get_weapon_socket(weapon)
	player.call("set_gameplay_enabled", true)
	await physics_frame
	await process_frame
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
	for entry in [["agile", 0.95, 800.0, 6.0], ["puissant", 1.05, 1200.0, 4.0], ["puissant", 1.05, 1200.0, 4.0], ["agile", 0.95, 800.0, 6.0], ["polyvalent", 1.0, 1000.0, 5.0], ["puissant", 1.05, 1200.0, 4.0]]:
		var identifier: String = entry[0]
		player.call("set_robot", identifier)
		rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		_check(rig.scale.is_equal_approx(initial_scale * float(entry[1])), "uniform visual scale: " + identifier)
		_check(player.scale == Vector3.ONE and body_shapes[0].shape == original_shape, "physics shape retained: " + identifier)
		_check((_mesh_resources(rig) != original_meshes) == (identifier == "puissant"), "correct authored geometry: " + identifier)
		_check(rig.model_axis_correction.get_node("ImportedAnimatedModel").scene_file_path == rig.CHASSIS_VISUALS.model_path(identifier), "correct model resource: " + identifier)
		_check(rig.animation_tree.active and rig.skeleton.get_bone_count() == 65, "animation rig ready: " + identifier)
		_check(is_instance_valid(weight) and weight.get_parent() == rig.skeleton and weight.get("_hips") >= 0, "external weight modifier survives model switch: " + identifier)
		_check(rig.detected_animation_names.size() == (97 if identifier == "puissant" else 9), "authored animations retained: " + identifier)
		_check(float(player.call("get_max_health")) == float(entry[2]) and float(player.call("get_current_move_speed")) == float(entry[3]), "existing chassis stats: " + identifier)
		for state in initial_strides:
			if identifier != "puissant":
				_check(is_equal_approx(float(rig.get("_locomotion_reference_speeds")[state]), float(initial_strides[state]) * float(entry[1])), "stride remains proportional: " + identifier)
			else:
				_check(float(rig.get("_locomotion_reference_speeds")[state]) > 0.05, "authored orange stride measured: " + String(state))
		_check(_surface_overrides(reference_rig) == reference_originals and reference_rig.scale == initial_scale, "other player remains original: " + identifier)
		if identifier == "polyvalent":
			_check(_material_signature(rig) == originals, "Polyvalent restores original finish")
		elif identifier == "agile":
			_check(_material_signature(rig) != originals, "Agile paint is installed")
		else:
			for material in _surface_overrides(rig):
				_check(material is StandardMaterial3D, "authored orange paint retained")
		for weapon in weapons:
			_check(rig.get_weapon_socket(weapon) == weapons[weapon], "existing weapon nodes survive swap: " + str(weapon))
		for weapon in [&"blaster", &"shotgun", &"longshot"]:
			var socket := rig.get_weapon_socket(weapon)
			_check(socket != null and socket.get_parent() == rig.right_hand_attachment and rig.get_weapon_muzzle(weapon) != null, "hand and muzzle retained: " + identifier + " / " + str(weapon))
			player.call("set_weapon", weapon)
			pose.weapon = weapon
			rig.set_aim_enabled(true)
			rig.configure_left_hand_support(weapon)
			for frame in range(45):
				await process_frame
				player.call("_update_weapon_ambient_motion", 1.0 / 60.0)
				var movement := Vector3.ZERO if frame < 15 else (Vector3.RIGHT if frame < 30 else Vector3.BACK)
				if frame == 20:
					rig.play_shot_kick()
				rig.update_visual_state(movement, Vector3.FORWARD, movement.length() * float(entry[3]), float(entry[3]), 1.0 / 60.0)
				rig.animation_tree.advance(1.0 / 60.0)
				rig.skeleton.advance(1.0 / 60.0)
				await rig.skeleton.skeleton_updated
			_check((pose.forward as Vector3).dot(Vector3.FORWARD) > 0.99999, "scaled muzzle aims forward: " + identifier + " / " + str(weapon))
			print("CHASSIS AIM ", identifier, " / ", weapon, " dot=", (pose.forward as Vector3).dot(Vector3.FORWARD), " support=", rig.aim_modifier.support_enabled, " error=", rig.aim_modifier.left_grip_error)
			if rig.aim_modifier.support_enabled and (weapon != &"longshot" or identifier == "puissant"):
				_check(rig.aim_modifier.left_grip_reachable and rig.aim_modifier.left_grip_error < 0.003, "support hand follows scaled weapon: " + identifier + " / " + str(weapon))
		if identifier == "puissant":
			var presence_clip := rig.presence_modifier.library.get_animation(&"look_around")
			var authored_clip := rig.animation_player.get_animation(&"look_around")
			_check(presence_clip.get_track_count() == authored_clip.get_track_count() and presence_clip.track_get_key_value(0, 0) == authored_clip.track_get_key_value(0, 0), "presence uses orange model's own animations")
			_check(rig.play_action(&"cheer"), "orange victory playable")
			var victory := rig.animation_player.get_animation("context/cheer")
			var authored_victory := rig.animation_player.get_animation("cheer")
			_check(victory.track_get_key_value(1, 0) == authored_victory.track_get_key_value(1, 0), "victory uses authored orange clip")
			rig.play_action(&"idle")
			rig.set_bush_concealed(true)
			player.call("set_robot", "puissant")
			_check(rig.get("_bush_concealed"), "concealment survives reselection")
			rig.set_bush_concealed(false)
	player.call("set_robot", "unknown")
	_check(rig.scale == initial_scale and _material_signature(rig) == originals and rig.animation_player.get_animation_list() == clips, "invalid chassis returns to original Polyvalent")
	await _check_presentations()
	await _check_network(stage)
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


func _material_signature(rig: PlayerVisualRig) -> Array:
	var result: Array = []
	for material in _surface_overrides(rig):
		if material is StandardMaterial3D:
			result.append([material.albedo_texture, material.albedo_color, material.roughness, material.metallic])
		else:
			result.append(material)
	return result


func _check_presentations() -> void:
	var garage := preload("res://scripts/forge_garage_stage.gd").new()
	var card := preload("res://scripts/robot_forge_preview.gd").new()
	var portrait := preload("res://scripts/ui/combat_portrait.gd").new()
	root.add_child(garage)
	root.add_child(card)
	root.add_child(portrait)
	await process_frame
	garage.set_process(false)
	garage.set_mobility_module("bio_injector")
	for identifier in ["puissant", "polyvalent", "agile", "puissant"]:
		garage.set_chassis(identifier)
		card.set_chassis(identifier)
		portrait.set_chassis(identifier)
		var path := PlayerVisualRig.CHASSIS_VISUALS.model_path(identifier)
		_check(garage.robot_model.scene_file_path == path and card._model.scene_file_path == path and portrait._model.scene_file_path == path, "garage/card/portrait show selected model: " + identifier)
		_check(garage.robot_animator.is_playing() and card._clips.size() == 6, "showroom animations available: " + identifier)
		_check(garage.module_visuals.mobility_id == "bio_injector" and garage.module_visuals.mounts.bio.visible, "installed module retained in garage: " + identifier)
		var bounds: AABB = garage.call("_bounds", garage.robot_model)
		_check(is_equal_approx(bounds.size.y * garage.robot.scale.x, 3.05 * float(PlayerVisualRig.CHASSIS_VISUALS.SCALE_FACTORS[identifier])), "garage model height normalized: " + identifier)
		for weapon in ["blaster", "shotgun", "longshot", "mekatana"]:
			garage.set_weapon(weapon)
			_check(garage.weapon_socket != null and garage.weapon_socket.global_transform.is_finite(), "garage weapon attached: " + identifier + "/" + weapon)
	garage.queue_free()
	card.queue_free()
	portrait.queue_free()
	await process_frame


func _check_network(stage: Node3D) -> void:
	var host := preload("res://scripts/network_player.gd").new()
	var replica := preload("res://scripts/network_player.gd").new()
	replica.authoritative = false
	replica.remote_controlled = true
	stage.add_child(host)
	stage.add_child(replica)
	await process_frame
	for actor in [host, replica]:
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.set_gameplay_enabled(true)
		actor.set_robot("puissant")
		actor._visual_rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_check(host._visual_rig.presence_modifier.autonomous and not replica._visual_rig.presence_modifier.autonomous, "network authority retained after chassis switch")
	host.take_damage(10.0, "fixture", "powerful-network-impact")
	var packet: Dictionary = host.network_snapshot()
	replica.receive_snapshot(packet)
	_check(replica._visual_rig.presence_modifier.hit_clip == host._visual_rig.presence_modifier.hit_clip and packet.presence.hit_clip != "", "orange impact synchronized to replica")
	_check(replica._visual_rig.model_axis_correction.get_node("ImportedAnimatedModel").scene_file_path == PlayerVisualRig.CHASSIS_VISUALS.POWERFUL_MODEL_PATH, "remote player shows orange model")
	_check(replica._visibility_fade.get_debug_counts().visuals >= 63, "network visibility watches replaced body meshes")
	replica._visibility_fade.apply_opacity(0.4)
	replica._visibility_fade.restore()
	host.queue_free()
	replica.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
