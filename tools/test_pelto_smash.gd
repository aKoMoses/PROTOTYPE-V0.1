extends SceneTree

const PELTO_SMASH := preload("res://scripts/pelto_smash.gd")
const TARGET_DUMMY := preload("res://scripts/target_dummy.gd")
const AIM_MODIFIER := preload("res://scripts/player_aim_modifier.gd")

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
		_test_pose_continuity()
		await _test_held_aim_and_release(player, target, scene)
		await _test_tap_and_cancel(player, target)
		await _test_extended_range(player, target)
		await _test_touch_ownership(player, target, scene)
		await _test_turnaround_and_frame_steps(player, target, scene)
		await _test_network_aim(scene)
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
	if absf(float(values.max_range) - 9.0) > 0.01 or absf(float(values.width) - 2.5) > 0.01 or absf(float(values.front_thickness) - 0.7) > 0.01:
		_failures.append("Données : portée, largeur ou épaisseur du front incorrecte")
	if float(values.preparation) + float(values.impact_duration) + float(values.recovery) > 0.55:
		_failures.append("Fluidité : geste trop long")


func _test_pose_continuity() -> void:
	for boundary in [["preparation", "impact"], ["impact", "recovery"]]:
		if not AIM_MODIFIER.pelto_pose_weights(boundary[0], 1.0).is_equal_approx(AIM_MODIFIER.pelto_pose_weights(boundary[1], 0.0)):
			_failures.append("Animation : rupture entre %s et %s" % boundary)
	if not AIM_MODIFIER.pelto_pose_weights("recovery", 1.0).is_zero_approx():
		_failures.append("Animation : récupération ne revient pas à la pose neutre")


func _test_held_aim_and_release(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(8.0, 0.0, 0.0))
	if not bool(player.call("begin_touch_action", "offensive")):
		_failures.append("Visée : maintien refusé")
		return
	# Select the screen-space vector that points down the arena's clear lane.
	var screen_right: Vector3 = player.call("_camera_relative_direction", Vector2.RIGHT)
	var screen_down: Vector3 = player.call("_camera_relative_direction", Vector2.DOWN)
	player.call("set_pelto_touch_aim", Vector2(screen_right.dot(Vector3.FORWARD), screen_down.dot(Vector3.FORWARD)))
	var aimed: Vector3 = player.get("_pelto_direction")
	player.call("set_pelto_touch_aim", Vector2.ZERO)
	if not aimed.is_equal_approx(player.get("_pelto_direction")):
		_failures.append("Visée : la zone morte efface la dernière direction")
	await create_timer(0.38).timeout
	if not bool(player.call("is_pelto_preparing")):
		_failures.append("Visée : frappe avant le relâchement")
	target.global_position = aimed * 8.0
	player.call("end_touch_action", "offensive")
	player.set("aim_direction", -aimed)
	var wave := await _wait_for_wave_phase(scene, "outbound")
	if wave == null or not aimed.is_equal_approx(wave.get("direction")):
		_failures.append("Visée : le relâchement n'a pas verrouillé la direction")
	await _wait_for_health(target, 740.0)
	if absf(float(target.call("get_health")) - 740.0) > 1.0:
		_failures.append("Visée : cible à 8 m non touchée aux deux passages (PV=%.1f, direction=%s)" % [float(target.call("get_health")), aimed])
	await create_timer(0.4).timeout


func _test_tap_and_cancel(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -3.0))
	player.call("begin_touch_action", "offensive")
	player.call("end_touch_action", "offensive")
	if not bool(player.call("is_pelto_preparing")):
		_failures.append("Tap : la préparation minimale est sautée")
	await _wait_for_health(target, 740.0)
	await create_timer(0.4).timeout
	await _prepare(player, target, Vector3(0.0, 0.0, -3.0))
	player.call("begin_touch_action", "offensive")
	player.call("cancel_touch_action", "offensive")
	await create_timer(0.4).timeout
	if str(player.get("_pelto_phase")) != "" or float(target.call("get_health")) < 999.0:
		_failures.append("Visée : annulation tactile déclenche une vague")


func _test_extended_range(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -8.2))
	_cast(player)
	await _wait_for_health(target, 740.0)
	if absf(float(target.call("get_health")) - 740.0) > 1.0:
		_failures.append("Portée : cible à 8,2 m hors de la vague")
	await create_timer(0.4).timeout


func _test_touch_ownership(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -3.0))
	var controls: Node = scene.get_node("Interface/TouchControls")
	controls.call("reset_inputs")
	var centers: Dictionary = controls.call("_action_centers")
	controls.call("_begin_touch", 70, centers.offensive)
	controls.call("_begin_touch", 71, centers.offensive)
	controls.call("_end_touch", 71)
	if bool(player.get("_pelto_release_requested")):
		_failures.append("Tactile : un doigt refusé a relâché le sort")
	controls.call("_update_touch", 70, centers.offensive + Vector2(80, 0))
	if (player.get("_pelto_module_aim") as Vector3).length_squared() < 0.5:
		_failures.append("Tactile : glissement du bouton non transmis à la visée")
	controls.call("reset_inputs")
	if str(player.get("_pelto_phase")) != "":
		_failures.append("Tactile : perte du contact ne termine pas la préparation")
	await physics_frame
	player.call("begin_touch_action", "offensive")
	player.call("_update_pelto_attack", 3.1)
	if bool(player.call("is_pelto_preparing")):
		_failures.append("Visée : maintien maximal ne libère pas le joueur")
	await create_timer(1.6).timeout


func _test_turnaround_and_frame_steps(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -3.0))
	var waves: Array[Node] = []
	for index in range(2):
		var wave := PELTO_SMASH.new()
		scene.add_child(wave)
		wave.configure(player, Vector3.ZERO, Vector3.FORWARD, "test", "pelto:turn:%d" % index, 0.0)
		wave.set_physics_process(false)
		wave.set_process(false)
		waves.append(wave)
	var duration := float(waves[0].get("_max_distance")) / 13.0
	waves[0].call("_physics_process", duration * 0.5)
	for step in range(30):
		waves[1].call("_physics_process", duration / 60.0)
	if absf(float(waves[0].get("travel_distance")) - float(waves[1].get("travel_distance"))) > 0.001:
		_failures.append("Fluidité : vitesse dépendante de la fréquence physique")
	waves[0].call("_physics_process", duration * 0.5)
	var endpoint := float(waves[0].get("travel_distance"))
	waves[0].call("_physics_process", 0.08)
	waves[0].call("_physics_process", 0.01)
	if endpoint - float(waves[0].get("travel_distance")) > 0.015:
		_failures.append("Fluidité : retour démarre avec une rupture de vitesse")
	for wave in waves:
		wave.queue_free()
	await process_frame


func _test_network_aim(scene: Node) -> void:
	var actor: Node = load("res://scripts/network_player.gd").new()
	actor.set("remote_controlled", true)
	scene.add_child(actor)
	actor.call("apply_loadout", {"weapon": "blaster", "offensive": "pelto_smash", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "omnivamp"})
	actor.call("set_gameplay_enabled", true)
	await physics_frame
	actor.set("aim_direction", Vector3.FORWARD)
	actor.call("receive_action", "pelto_begin", {"held": true})
	actor.call("_update_pelto_attack", 0.4)
	if not bool(actor.call("is_pelto_preparing")):
		_failures.append("Réseau : maintien du sort non conservé")
	actor.set("aim_direction", Vector3.RIGHT)
	actor.call("receive_action", "pelto_release", {})
	actor.call("_update_pelto_attack", 0.01)
	if not (actor.get("_pelto_direction") as Vector3).is_equal_approx(Vector3.RIGHT) or str(actor.get("_pelto_phase")) != "impact":
		_failures.append("Réseau : direction de relâchement non conservée")
	actor.call("reset_combat_state")
	await physics_frame
	actor.call("receive_action", "pelto_begin", {"held": true})
	actor.call("receive_action", "pelto_cancel", {})
	if str(actor.get("_pelto_phase")) != "":
		_failures.append("Réseau : annulation du sort non transmise")
	actor.call("set_gameplay_enabled", false)
	actor.call("reset_module_state")
	for frame in range(3):
		await process_frame
	actor.queue_free()
	await process_frame


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
	wave.call("_physics_process", 0.50)
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
