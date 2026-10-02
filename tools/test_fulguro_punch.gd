extends SceneTree

const FULGURO := preload("res://scripts/fulguro_punch.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")

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
		player.call("set_gameplay_enabled", true)
		target.call("set_training_bot_enabled", false)
		player.set("training_instant_cooldowns", true)
		await _test_minimum_charge(player, target)
		await _test_held_charge(player, target)
		await _test_maximum_charge(player, target)
		await _test_free_projection(player, target)
		await _test_wall_crush(player, target, scene)
		await _test_oblique_wall_crush(player, target, scene)
		await _test_low_fps_sweep(player, target, scene)
		_test_crush_contact_filtering()
		await _test_wall_blocks_strike(player, target, scene)
		await _test_dash_interaction(player, target)
		await _test_hard_control_cancels(player, target)
		await _test_free_projection_buffer(player, target)
		await _test_wall_stun_buffer(player, target, scene)
		await _test_invalid_buffer(player, target)
		await _test_teleport_buffer(player, target)
		await _test_bot_uses_shared_punch(player, target)
		_test_death_clears_buffer(player)
	if _failures.is_empty():
		print("FULGURO PUNCH INTEGRATION TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("FULGURO PUNCH INTEGRATION TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node, target: Node, target_position: Vector3, aim: Vector3 = Vector3(0.0, 0.0, -1.0)) -> void:
	player.call("set_gameplay_enabled", true)
	player.call("apply_loadout", {
		"weapon": "blaster",
		"offensive": "fulguro_punch",
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
	# Set the deterministic test aim after the live mouse aim update for this frame.
	player.set("aim_direction", aim.normalized())
	player.set("_last_move_direction", aim.normalized())


func _test_minimum_charge(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -1.55))
	player.call("begin_touch_action", "offensive")
	player.call("end_touch_action", "offensive")
	await create_timer(0.20, true, false, false).timeout
	if absf(float(target.call("get_health")) - 1000.0) > 0.1:
		_failures.append("Charge minimale : frappe partie avant 0,35 s")
	await _wait_projection_cycle(target)
	if absf(float(target.call("get_health")) - 800.0) > 1.0:
		_failures.append("Charge minimale : dégâts de base incorrects")


func _test_held_charge(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -2.85))
	player.call("begin_touch_action", "offensive")
	await create_timer(0.72, true, false, false).timeout
	if str(player.get("_fulguro_phase")) != "preparation" or absf(float(target.call("get_health")) - 1000.0) > 0.1:
		_failures.append("Charge maintenue : départ automatique avant le plafond")
	player.call("end_touch_action", "offensive")
	await _wait_projection_cycle(target)
	var damage := 1000.0 - float(target.call("get_health"))
	if damage <= 200.0 or damage >= 400.0:
		_failures.append("Charge intermédiaire : dégâts non amplifiés (%.1f)" % damage)


func _test_maximum_charge(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -4.45))
	player.call("_begin_fulguro_charge")
	player.set("_fulguro_elapsed", 3.0)
	player.call("_update_fulguro_attack", 0.0)
	if absf(float(target.call("get_health")) - 600.0) > 1.0:
		_failures.append("Charge maximale : portée 4 m ou dégâts 400 incorrects")


func _test_free_projection(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -1.55))
	player.call("_perform_fulguro_punch")
	await _wait_projection_cycle(target)
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - 200.0) > 1.0:
		_failures.append("Projection libre : dégâts %.1f au lieu de 200" % damage)
	if bool(target.call("is_stunned")):
		_failures.append("Projection libre : stun ajouté sans collision")
	if float(target.global_position.z) > -5.3:
		_failures.append("Projection libre : distance insuffisante (z=%.2f)" % target.global_position.z)


func _test_wall_crush(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -1.45))
	var wall := _make_wall(scene, "FulguroWall", Vector3(0.0, 0.9, -3.25), Vector3(3.0, 1.8, 0.30))
	await process_frame
	player.call("_perform_fulguro_punch")
	await _wait_projection_cycle(target)
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - 350.0) > 1.0:
		_failures.append("Écrasement : dégâts %.1f au lieu de 350" % damage)
	if not bool(target.call("is_stunned")):
		_failures.append("Écrasement : stun mural absent")
	var remaining := float(target.get("combat_state").get_remaining("STUN"))
	if remaining < 0.65 or remaining > 0.76:
		_failures.append("Écrasement : stun restant %.3f s" % remaining)
	wall.queue_free()
	await process_frame


func _test_oblique_wall_crush(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -1.45))
	var wall := _make_wall(scene, "FulguroObliqueWall", Vector3(0.0, 0.9, -3.25), Vector3(3.0, 1.8, 0.30))
	wall.rotation.y = deg_to_rad(28.0)
	await process_frame
	player.call("_perform_fulguro_punch")
	await _wait_projection_cycle(target)
	if absf(float(target.call("get_health")) - 650.0) > 1.0 or not bool(target.call("is_stunned")):
		_failures.append("Écrasement oblique : dégâts ou stun incorrects")
	wall.queue_free()
	await process_frame


func _test_low_fps_sweep(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3.ZERO)
	var wall := _make_wall(scene, "FulguroSweepWall", Vector3(0.0, 0.9, -2.4), Vector3(3.0, 1.8, 0.30))
	await process_frame
	var result: Dictionary = FULGURO.sweep_static_body(target, Vector3(0.0, 0.0, -4.0), 0.70, 1.8)
	if not bool(result.get("collided", false)) or result.get("collider") != wall or Vector3(result.get("travel", Vector3.ZERO)).length() >= 3.95:
		_failures.append("Balayage basse fréquence : mur traversé sur une étape de 4 m")
	wall.queue_free()
	await process_frame


func _test_crush_contact_filtering() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var trigger := Area3D.new()
	var character := CharacterBody3D.new()
	var direction := Vector3.FORWARD
	if not FULGURO.is_crushing_wall(wall, Vector3.BACK, direction):
		_failures.append("Filtre écrasement : collision frontale rejetée")
	if not FULGURO.is_crushing_wall(wall, Vector3(0.72, 0.0, 0.69).normalized(), direction):
		_failures.append("Filtre écrasement : collision oblique rejetée")
	if FULGURO.is_crushing_wall(wall, Vector3.RIGHT, direction) or FULGURO.is_crushing_wall(wall, Vector3.UP, direction):
		_failures.append("Filtre écrasement : contact latéral ou sol accepté")
	if FULGURO.is_crushing_wall(trigger, Vector3.BACK, direction) or FULGURO.is_crushing_wall(character, Vector3.BACK, direction):
		_failures.append("Filtre écrasement : trigger ou personnage accepté")
	wall.free()
	trigger.free()
	character.free()


func _test_wall_blocks_strike(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -2.0))
	var wall := _make_wall(scene, "FulguroOccluder", Vector3(0.0, 0.9, -0.95), Vector3(2.5, 1.8, 0.24))
	await process_frame
	player.call("_perform_fulguro_punch")
	await create_timer(0.48, true, false, false).timeout
	if absf(float(target.call("get_health")) - 1000.0) > 0.1:
		_failures.append("Mur interposé : cible touchée à travers le mur")
	wall.queue_free()
	await process_frame


func _test_dash_interaction(player: Node, target: Node) -> void:
	var dash_distance := float(COMBAT_DATA.MODULE_DEFINITIONS.pyro_boots.dash_distance)
	await _prepare(player, target, Vector3(0.0, 0.0, 1.45), Vector3.BACK)
	# Keep the final hit/projection in the open lane with the longer dash.
	var dash_origin := Vector3(0.0, 0.0, -dash_distance)
	player.global_position = dash_origin
	player.call("_perform_pyro_boots", Vector3.BACK)
	await create_timer(0.04, true, false, false).timeout
	# The live mouse sampler continues during the dash; emulate a held right-stick
	# direction on the exact frame where the attack locks its aim.
	player.set("aim_direction", Vector3.BACK)
	player.call("_perform_fulguro_punch")
	await create_timer(0.22, true, false, false).timeout
	if bool(player.call("is_dash_active")):
		_failures.append("Dash + frappe : dash prolongé par le module")
	if absf(player.global_position.distance_to(dash_origin) - dash_distance) > 0.30:
		_failures.append("Dash + frappe : distance dash altérée (z=%.2f)" % player.global_position.z)
	await _wait_projection_cycle(target)
	if absf(float(target.call("get_health")) - 800.0) > 1.0:
		_failures.append("Dash + frappe : frappe non résolue depuis la position courante")


func _test_hard_control_cancels(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -1.45))
	player.call("_perform_fulguro_punch")
	await create_timer(0.08, true, false, false).timeout
	player.set("_stasis_remaining", 0.50)
	await create_timer(0.42, true, false, false).timeout
	if str(player.get("_fulguro_phase")) != "" or absf(float(target.call("get_health")) - 1000.0) > 0.1:
		_failures.append("Contrôle dur : préparation non annulée")


func _test_free_projection_buffer(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(12.0, 0.0, 12.0), Vector3.BACK)
	player.set("training_instant_cooldowns", false)
	player.set("_last_move_direction", Vector3.BACK)
	player.call("start_fulguro_projection", Vector3.RIGHT, 4.0, 0.35, 150.0, 0.75, "test", "buffer_free")
	player.call("_activate_mobility_module")
	if str(player.call("get_buffered_defensive_action")) != "dash" or float(player.call("get_module_cooldown", "pyro_boots")) > 0.0:
		_failures.append("Buffer libre : dash non mémorisé ou cooldown consommé trop tôt")
	await create_timer(0.68, true, false, false).timeout
	if str(player.call("get_buffered_defensive_action")) != "" or float(player.call("get_module_cooldown", "pyro_boots")) <= 0.0:
		_failures.append("Buffer libre : dash non consommé à la reprise")
	if player.global_position.x < 3.7 or player.global_position.z < 2.6:
		_failures.append("Buffer libre : projection/dash incomplets (%s)" % player.global_position)


func _test_wall_stun_buffer(player: Node, target: Node, scene: Node) -> void:
	await _prepare(player, target, Vector3(12.0, 0.0, 12.0), Vector3.BACK)
	player.set("training_instant_cooldowns", false)
	var wall := _make_wall(scene, "PlayerFulguroWall", Vector3(1.55, 0.9, 0.0), Vector3(0.28, 1.8, 3.0))
	await process_frame
	player.set("_last_move_direction", Vector3.BACK)
	player.call("start_fulguro_projection", Vector3.RIGHT, 4.0, 0.35, 150.0, 0.75, "test", "buffer_wall")
	player.call("_activate_mobility_module")
	await _wait_projection_end(player)
	if float(player.call("get_module_cooldown", "pyro_boots")) > 0.0 or not bool(player.get("combat_state").is_stunned()):
		_failures.append("Buffer mur : exécuté avant la fin du stun")
	await create_timer(0.40, true, false, false).timeout
	if float(player.call("get_module_cooldown", "pyro_boots")) > 0.0:
		_failures.append("Buffer mur : cooldown consommé pendant le stun")
	await create_timer(0.48, true, false, false).timeout
	if float(player.call("get_module_cooldown", "pyro_boots")) <= 0.0 or str(player.call("get_buffered_defensive_action")) != "":
		_failures.append("Buffer mur : dash non exécuté après 0,75 s")
	wall.queue_free()
	await process_frame


func _test_invalid_buffer(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(12.0, 0.0, 12.0))
	player.set("training_instant_cooldowns", false)
	player.call("start_fulguro_projection", Vector3.RIGHT, 4.0, 0.35, 150.0, 0.75, "test", "buffer_invalid")
	player.call("_activate_mobility_module")
	player.call("_start_module_cooldown", "pyro_boots", 2.0)
	player.call("_start_module_cooldown", "pyro_boots", 2.0)
	await create_timer(0.46, true, false, false).timeout
	if str(player.call("get_buffered_defensive_action")) != "" or bool(player.call("is_dash_active")):
		_failures.append("Buffer invalide : commande non supprimée")


func _test_teleport_buffer(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, -2.0))
	player.set("_offensive_module_id", "javelin")
	target.call("apply_javelin_mark", 2.5, "test")
	player.set("_javelin_mark_target", target)
	player.call("start_fulguro_projection", Vector3.LEFT, 4.0, 0.35, 150.0, 0.75, "test", "buffer_teleport")
	player.call("_perform_offensive_module")
	if str(player.call("get_buffered_defensive_action")) != "teleport" or not bool(target.call("has_javelin_mark")):
		_failures.append("Buffer téléportation : commande ou marque perdue à la mémorisation")
	await create_timer(0.46, true, false, false).timeout
	if bool(target.call("has_javelin_mark")) or str(player.call("get_buffered_defensive_action")) != "":
		_failures.append("Buffer téléportation : réactivation non consommée à la reprise")


func _test_bot_uses_shared_punch(player: Node, target: Node) -> void:
	await _prepare(player, target, Vector3(0.0, 0.0, 1.6), Vector3.BACK)
	target.call("set_training_bot_enabled", true)
	var bot: Node = target.get_node("TrainingBot")
	bot.call("_begin_attack", target, player)
	await _wait_until_projected(player)
	if float(player.call("get_health")) > 801.0 or not bool(player.call("is_fulguro_projected")):
		_failures.append("Bot : FULGURO PUNCH n’utilise pas les règles partagées")
	target.call("set_training_bot_enabled", false)


func _test_death_clears_buffer(player: Node) -> void:
	player.call("set_gameplay_enabled", true)
	player.set("_mobility_module_id", "pyro_boots")
	player.set("_last_move_direction", Vector3.RIGHT)
	player.call("start_fulguro_projection", Vector3.BACK, 4.0, 0.35, 150.0, 0.75, "test", "buffer_death")
	player.call("_activate_mobility_module")
	player.call("take_damage", 5000.0, "test", "lethal")
	if str(player.call("get_buffered_defensive_action")) != "":
		_failures.append("Mort : buffer défensif non vidé")


func _wait_projection_end(actor: Node) -> void:
	for _frame in range(120):
		await process_frame
		if not bool(actor.call("is_fulguro_projected")):
			return
	_failures.append("Projection non terminée dans le délai de test")


func _wait_projection_cycle(actor: Node) -> void:
	var began := false
	for _frame in range(360):
		await process_frame
		if bool(actor.call("is_fulguro_projected")):
			began = true
		elif began:
			return
	_failures.append("Cycle de projection non observé dans le délai de test")


func _wait_until_projected(actor: Node) -> void:
	for _frame in range(300):
		await process_frame
		if bool(actor.call("is_fulguro_projected")):
			return
	_failures.append("Début de projection non observé dans le délai de test")


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
