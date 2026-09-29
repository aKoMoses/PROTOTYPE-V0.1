extends SceneTree

const PELTO_SMASH := preload("res://scripts/pelto_smash.gd")
const TARGET_DUMMY := preload("res://scripts/target_dummy.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player ou TargetDummy introuvable")
	else:
		_test_central_values()
		await _test_shotgun_restores_to_hand(player, target)
		await _test_multiple_targets_progressively(player, target, scene)
		await _test_two_passes(player, target)
		await _test_lateral_exit_avoids_return(player, target)
		await _test_return_only_entry(player, target, scene)
		await _test_caster_motion_does_not_steer(player, target)
		await _test_wall_stops_wave(player, target, scene)
		await _test_hard_control_cancels_windup(player, target)
		await _test_dash_interrupts_pull(player, target)
		await _test_low_fps_sweep(player, target, scene)
		await _test_bot_uses_pelto(player, target)
	if _failures.is_empty():
		print("PELTO SMASH INTEGRATION TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("PELTO SMASH INTEGRATION TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _test_central_values() -> void:
	var values: Dictionary = PELTO_SMASH.definition()
	if absf(float(values.outbound_damage) + float(values.return_damage) - 260.0) > 0.01:
		_failures.append("Données : le total des deux passages n'est pas 260/1000 PV")
	if absf(float(values.max_range) - 7.0) > 0.01 or absf(float(values.width) - 2.5) > 0.01 or absf(float(values.front_thickness) - 0.7) > 0.01:
		_failures.append("Données : portée, largeur ou épaisseur du front incorrecte")


func _test_shotgun_restores_to_hand(player: Node, target: Node) -> void:
	player.call("set_gameplay_enabled", true)
	player.call("apply_loadout", {
		"weapon": "shotgun",
		"offensive": "pelto_smash",
		"defensive": "magnetic_field",
		"mobility": "pyro_boots",
		"passive": "omnivamp",
	})
	player.call("reset_combat_state")
	player.set("training_instant_cooldowns", true)
	target.call("set_training_bot_enabled", false)
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("_reset_weapon_pose_to_locomotion", true)
	for _frame in range(12):
		await process_frame
	var rig := player.get_node("VisualRoot") as PlayerVisualRig
	var shotgun_pivot := player.get("_shotgun_pivot") as Node3D
	var right_grip := shotgun_pivot.find_child("RightHandGrip", true, false) as Marker3D
	var right_hand_index := rig.get_right_hand_bone_index()
	var shotgun_socket := rig.get_weapon_socket(&"shotgun")
	var carry_transform: Transform3D = shotgun_socket.get_meta("weapon_carry_transform", shotgun_socket.transform)
	var resting_hand := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(right_hand_index)
	player.call("_perform_pelto_smash")
	for _frame in range(12):
		await process_frame
	var pelto_hand := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(right_hand_index)
	player.call("_cancel_pelto_smash")
	var stayed_hidden_until_skeleton_refresh := not shotgun_pivot.visible
	for _frame in range(3):
		await process_frame
	var restored_hand := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(right_hand_index)
	print("[PeltoWeaponRestore] pelto_offset=%.6f restored_offset=%.6f grip_error=%.6f" % [resting_hand.origin.distance_to(pelto_hand.origin), resting_hand.origin.distance_to(restored_hand.origin), restored_hand.origin.distance_to(right_grip.global_position)])
	if resting_hand.origin.distance_to(pelto_hand.origin) <= 0.02:
		_failures.append("Visuel shotgun : la pose Pelto de la main droite n'a pas été exercée par le test")
	if not stayed_hidden_until_skeleton_refresh:
		_failures.append("Visuel shotgun : l'arme réapparaît avant la mise à jour du squelette")
	if restored_hand.origin.distance_to(right_grip.global_position) > 0.001:
		_failures.append("Visuel shotgun : la poignée n'est pas resynchronisée après la pose Pelto")
	player.call("reset_combat_state")
	player.call("_reset_weapon_pose_to_locomotion", true)
	for _frame in range(2):
		await process_frame
	player.call("_perform_pelto_smash")
	var cast_seen := false
	var hidden_during_cast := true
	var finished := false
	var first_visible_socket_restored := false
	var maximum_visible_grip_error := 0.0
	var post_cast_frames := 0
	for _frame in range(240):
		await process_frame
		var phase := str(player.get("_pelto_phase"))
		if phase != "":
			cast_seen = true
			hidden_during_cast = hidden_during_cast and not shotgun_pivot.visible
		elif cast_seen:
			if not finished:
				first_visible_socket_restored = shotgun_socket.transform.is_equal_approx(carry_transform)
			finished = true
			post_cast_frames += 1
			var hand_world := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(right_hand_index)
			maximum_visible_grip_error = maxf(maximum_visible_grip_error, hand_world.origin.distance_to(right_grip.global_position))
			if post_cast_frames >= 12:
				break
	if not cast_seen or not hidden_during_cast:
		_failures.append("Visuel shotgun : l'arme n'est pas restée masquée pendant Pelto Smash")
	if not finished or not shotgun_pivot.visible:
		_failures.append("Visuel shotgun : l'arme n'est pas réapparue après Pelto Smash")
	if not first_visible_socket_restored:
		_failures.append("Visuel shotgun : l'arme réapparaît avant le rétablissement de sa pose portée")
	if maximum_visible_grip_error > 0.001:
		_failures.append("Visuel shotgun : la poignée flotte après Pelto Smash (erreur %.4f m)" % maximum_visible_grip_error)


func _prepare(player: Node, target: Node, target_position: Vector3) -> void:
	player.call("set_gameplay_enabled", true)
	player.call("apply_loadout", {
		"weapon": "blaster",
		"offensive": "pelto_smash",
		"defensive": "magnetic_field",
		"mobility": "pyro_boots",
		"passive": "omnivamp",
	})
	player.call("reset_combat_state")
	player.set("training_instant_cooldowns", true)
	player.global_position = Vector3.ZERO
	target.call("set_training_bot_enabled", false)
	target.call("reset_combat_state")
	target.global_position = target_position
	target.rotation = Vector3.ZERO
	await process_frame
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))


func _cast(player: Node) -> void:
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("_perform_pelto_smash")


func _test_two_passes(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -3.0))
	_cast(player)
	await _wait_for_health(target, 840.0)
	if absf(float(target.call("get_health")) - 840.0) > 1.0:
		_failures.append("Aller : dégâts progressifs ou touche unique incorrects")
	if not target.call("get_active_effect_types").has("SLOW"):
		_failures.append("Aller : ralentissement absent")
	await _wait_for_health(target, 740.0)
	if absf(float(target.call("get_health")) - 740.0) > 1.0:
		_failures.append("Retour : total supérieur ou inférieur à 260")
	await _wait_for_pull_end(target)
	if target.global_position.z <= -2.25:
		_failures.append("Retour : traction de 0,9 m absente (z=%.2f)" % target.global_position.z)


func _test_multiple_targets_progressively(player: Node, target: Node, scene: Node) -> void:
	var far_target := TARGET_DUMMY.new()
	far_target.name = "PeltoFarTarget"
	scene.add_child(far_target)
	await process_frame
	await _prepare(player, target, Vector3(0.0, 0.0, -2.0))
	far_target.call("set_training_bot_enabled", false)
	far_target.call("reset_combat_state")
	far_target.global_position = Vector3(0.0, 0.0, -5.0)
	_cast(player)
	await _wait_for_health(target, 840.0)
	if float(far_target.call("get_health")) < 999.5:
		_failures.append("Progression : deux cibles distantes ont été touchées simultanément")
	await _wait_for_health(far_target, 840.0)
	if absf(float(far_target.call("get_health")) - 840.0) > 1.0:
		_failures.append("Progression : la cible distante n'a pas été atteinte par le front")
	far_target.queue_free()
	await process_frame


func _test_lateral_exit_avoids_return(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -3.0))
	_cast(player)
	await _wait_for_health(target, 840.0)
	target.global_position.x = 4.0
	await create_timer(1.0, true, false, false).timeout
	if absf(float(target.call("get_health")) - 840.0) > 1.0:
		_failures.append("Sortie latérale : le retour a touché hors de la bande")


func _test_return_only_entry(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(4.0, 0.0, -3.0))
	_cast(player)
	var wave := await _wait_for_wave_phase(scene, "return")
	if wave == null:
		_failures.append("Entrée retour : phase retour non observée")
		return
	target.global_position = Vector3(0.0, 0.0, -3.0)
	await _wait_for_health(target, 900.0)
	if absf(float(target.call("get_health")) - 900.0) > 1.0:
		_failures.append("Entrée retour : la cible n'a pas reçu exactement les 100 dégâts retour")


func _test_caster_motion_does_not_steer(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -5.0))
	_cast(player)
	await create_timer(0.50, true, false, false).timeout
	player.global_position = Vector3(5.0, 0.0, 0.0)
	await _wait_for_health(target, 840.0)
	if absf(float(target.call("get_health")) - 840.0) > 1.0:
		_failures.append("Trajectoire : le déplacement du lanceur a guidé ou annulé la vague")


func _test_wall_stops_wave(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -4.0))
	var wall := _make_wall(scene, "PeltoWall", Vector3(0.0, 0.9, -1.8), Vector3(3.2, 1.8, 0.25))
	wall.rotation.y = deg_to_rad(25.0)
	await process_frame
	_cast(player)
	await create_timer(1.4, true, false, false).timeout
	if absf(float(target.call("get_health")) - 1000.0) > 0.1:
		_failures.append("Mur : dégâts appliqués à travers l'obstacle")
	wall.queue_free()
	await process_frame


func _test_hard_control_cancels_windup(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -3.0))
	_cast(player)
	await create_timer(0.20, true, false, false).timeout
	player.call("apply_stun", 0.5, "test")
	await create_timer(0.50, true, false, false).timeout
	if str(player.get("_pelto_phase")) != "" or absf(float(target.call("get_health")) - 1000.0) > 0.1:
		_failures.append("Interruption : une vague a été créée après contrôle dur avant impact")


func _test_dash_interrupts_pull(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(9.0, 0.0, 9.0))
	player.call("start_pelto_pull", Vector3.RIGHT, 0.9, 0.15, "test", "test:pull")
	player.call("_perform_pyro_boots", Vector3.BACK)
	if bool(player.call("is_pelto_pulled")) or not bool(player.call("is_dash_active")):
		_failures.append("Traction : le dash disponible ne l'interrompt pas")


func _test_low_fps_sweep(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -5.2))
	var wave := PELTO_SMASH.new()
	scene.add_child(wave)
	wave.call("configure", player, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), "test", "pelto:low_fps")
	wave.set_physics_process(false)
	wave.call("_physics_process", 0.70)
	if absf(float(target.call("get_health")) - 840.0) > 1.0:
		_failures.append("Basse fréquence : le balayage a manqué une cible entre deux positions")
	wave.queue_free()
	await process_frame


func _test_bot_uses_pelto(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, 6.0))
	target.call("set_training_bot_enabled", true)
	var bot: Node = target.get_node("TrainingBot")
	bot.call("_begin_attack", target, player)
	if str(bot.get("_attack_mode")) != "pelto":
		_failures.append("Bot : PELTO SMASH non sélectionné à moyenne portée")
	else:
		await _wait_for_health(player, 840.0)
		if float(player.call("get_health")) > 841.0:
			_failures.append("Bot : la vague partagée n'a pas touché le joueur")
	target.call("set_training_bot_enabled", false)


func _wait_for_health(actor: Node, expected_or_lower: float) -> void:
	for _frame in range(240):
		await process_frame
		if float(actor.call("get_health")) <= expected_or_lower + 0.5:
			return


func _wait_for_pull_end(actor: Node) -> void:
	for _frame in range(60):
		await process_frame
		if not actor.has_method("is_pelto_pulled") or not bool(actor.call("is_pelto_pulled")):
			return


func _wait_for_wave_phase(scene: Node, wanted_phase: String) -> Node:
	for _frame in range(240):
		await process_frame
		for child in scene.get_children():
			if child is PeltoSmashWave and str(child.get("phase")) == wanted_phase:
				return child
	return null


func _make_wall(scene: Node, wall_name: String, wall_position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = wall_name
	wall.position = wall_position
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	scene.add_child(wall)
	return wall
