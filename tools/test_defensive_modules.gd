extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player ou TargetDummy introuvable")
	else:
		target.call("set_training_bot_enabled", false)
		player.set_physics_process(false)
		await _test_magnetic_field(player, target, scene)
		await _test_invalid_magnetic_placement(player, scene)
		player.set_physics_process(true)
		await _test_static_shield(player)
	if _failures.is_empty():
		print("P0-107 DEFENSIVE MODULES TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-107 DEFENSIVE MODULES TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node, target: Node) -> void:
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("reset_combat_state")
	player.call("set_touch_aim_vector", Vector2(0, -1))
	target.global_position = Vector3(0.0, 0.0, -3.0)
	target.call("reset_combat_state")


func _test_magnetic_field(player: Node, target: Node, scene: Node) -> void:
	_prepare(player, target)
	player.set("_defensive_module_id", "magnetic_field")
	player.call("_perform_defensive_module")
	await create_timer(0.35, true, false, false).timeout
	var wall: Node = player.get("_magnetic_wall")
	if wall == null or not is_instance_valid(wall):
		_failures.append("Magnetic Field : mur non créé après la préparation")
		return
	if float(player.call("get_module_cooldown", "magnetic_field")) < 11.0:
		_failures.append("Magnetic Field : cooldown absent")
	player.call("set_weapon", "shotgun")
	player.call("_perform_shotgun_attack")
	await create_timer(0.70, true, false, false).timeout
	if float(target.call("get_health")) >= 999.0:
		_failures.append("Magnetic Field : les tirs du propriétaire ne traversent pas")
	var sight_exclusions: Array[RID] = [target.get_rid()]
	var target_visible: bool = player.call("_solid_path_clear", player.global_position, target.global_position, sight_exclusions)
	if not target_visible:
		_failures.append("Magnetic Field : la vision est bloquée par le mur")
	await create_timer(2.45, true, false, false).timeout
	if player.get("_magnetic_wall") != null and is_instance_valid(player.get("_magnetic_wall")):
		_failures.append("Magnetic Field : mur non retiré après sa durée")
	# Le propriétaire reste libre de ses déplacements.
	player.set("_defensive_module_id", "magnetic_field")
	player.call("reset_combat_state")
	player.global_position = Vector3.ZERO
	player.set("_last_move_direction", Vector3(0.0, 0.0, -1.0))
	var body_start: Vector3 = player.global_position
	player.velocity = Vector3(0.0, 0.0, -5.0)
	player.move_and_slide()
	if player.global_position.z >= body_start.z - 0.01:
		_failures.append("Magnetic Field : déplacement bloqué par le mur")


func _test_invalid_magnetic_placement(player: Node, scene: Node) -> void:
	player.call("reset_combat_state")
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	var blocker := StaticBody3D.new()
	blocker.name = "TestMagneticPlacementBlocker"
	blocker.position = Vector3(0.0, 0.6, -0.8)
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.2, 0.25)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	await process_frame
	player.set("_defensive_module_id", "magnetic_field")
	player.call("_perform_defensive_module")
	await process_frame
	if float(player.call("get_module_cooldown", "magnetic_field")) > 0.01:
		_failures.append("Magnetic Field : placement invalide consomme le cooldown")
	if player.get("_magnetic_wall") != null:
		_failures.append("Magnetic Field : mur créé malgré une obstruction")
	blocker.queue_free()
	await process_frame


func _test_static_shield(player: Node) -> void:
	player.call("reset_combat_state")
	player.global_position = Vector3.ZERO
	player.set("_defensive_module_id", "static_shield")
	player.call("_perform_defensive_module")
	var stasis := float(player.call("get_stasis_remaining"))
	if stasis < 1.4:
		_failures.append("Static Shield : stase immédiate absente")
	var before := float(player.call("get_health"))
	if float(player.call("take_damage", 100.0, "test", "stasis_damage")) != 0.0:
		_failures.append("Static Shield : dégâts acceptés pendant la stase")
	if float(player.call("heal", 100.0, "test")) != 0.0:
		_failures.append("Static Shield : soin accepté pendant la stase")
	player.call("apply_burn", 0.6, 100.0, "test_burn")
	await create_timer(0.45, true, false, false).timeout
	if absf(float(player.call("get_health")) - before) > 0.01:
		_failures.append("Static Shield : BURN inflige des dégâts pendant la stase")
	await create_timer(1.20, true, false, false).timeout
	if float(player.call("get_stasis_remaining")) > 0.01:
		_failures.append("Static Shield : stase ne se termine pas")
	if float(player.call("get_module_cooldown", "static_shield")) < 16.0:
		_failures.append("Static Shield : cooldown absent ou trop court")
	player.call("reset_combat_state")
	player.call("set_weapon", "shotgun")
	player.set("_shotgun_ammo", 0)
	player.call("_start_shotgun_reload")
	await create_timer(0.25, true, false, false).timeout
	var reload_before := float(player.get("_shotgun_reload_remaining"))
	player.set("_defensive_module_id", "static_shield")
	player.call("_perform_defensive_module")
	await create_timer(0.70, true, false, false).timeout
	var reload_during := float(player.get("_shotgun_reload_remaining"))
	if reload_before - reload_during > 0.05:
		_failures.append("Static Shield : recharge Shotgun non suspendue")
	await create_timer(2.50, true, false, false).timeout
	if bool(player.call("is_shotgun_reloading")):
		_failures.append("Static Shield : recharge Shotgun ne reprend pas après la stase")
	player.call("reset_combat_state")
	player.call("apply_stun", 0.6, "test_stun")
	player.call("_perform_defensive_module")
	if float(player.call("get_stasis_remaining")) > 0.01:
		_failures.append("Static Shield : activation autorisée sous STUN")
