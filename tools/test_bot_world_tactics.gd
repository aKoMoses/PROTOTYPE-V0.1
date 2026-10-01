extends SceneTree

const REPAIR_KIT := preload("res://scenes/repair_kit.tscn")
var _failures: Array[String] = []
var _finished := false
var _scene: Node3D
var _player: Node3D
var _target: Node3D
var _bot: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	_player = _scene.get_node_or_null("Player")
	_target = _scene.get_node_or_null("TargetDummy")
	_bot = _target.get_node_or_null("TrainingBot") if _target != null else null
	if _player == null or _target == null or _bot == null:
		_check(false, "combat actors must initialise")
		_report()
		return
	_player.set_physics_process(false)
	_target.call("set_training_bot_enabled", false)
	_target.call("set_duel_mode", true)
	_bot.call("set_difficulty_profile", "normal")
	# Retain the actual combat actors and UI; replace arena blockers with explicit
	# fixtures so a route's required detour and sight lines are unambiguous.
	for child in _scene.get_children():
		if child is StaticBody3D and child != _target:
			child.queue_free()
	for kit in get_nodes_in_group("repair_kits"):
		kit.call("set_collection_active", false)
	await physics_frame
	_bot.get("_navigation").invalidate(true)
	_test_delayed_observations()
	_test_unseen_search()
	await _test_retreat_cover()
	await _test_repair_detour()
	await _test_survival_detour()
	await _test_hidden_combat_reactions()
	await _test_repair_respawn_and_contest()
	await _test_dash_and_stasis_ownership()
	_finished = true
	_scene.queue_free()
	await process_frame
	_report()


func _test_delayed_observations() -> void:
	_bot.call("reset_clock")
	_target.global_position = Vector3(-8, 0, 0)
	_player.global_position = Vector3(8, 0, 0)
	_player.call("reset_combat_state")
	_bot.call("_update_duel_perception", _target, _player, true)
	_player.set("_blaster_charge_active", true)
	_player.set("_shotgun_reloading", true)
	_player.call("take_damage", 400.0, "tactics_test", "observed_health")
	_bot.set("_elapsed", 0.10)
	_bot.call("_update_duel_perception", _target, _player, true)
	var early: Dictionary = _bot.get("_perception")
	_check(not bool(early.visible) and not bool(early.target_charging) and not bool(early.target_reloading), "new charge / reload state cannot skip the reaction delay")
	_check(is_equal_approx(float(early.target_health_fraction), 1.0), "new target damage is not known before its observation matures")
	_bot.set("_elapsed", 0.24)
	_bot.call("_update_duel_perception", _target, _player, true)
	var first_seen: Dictionary = _bot.get("_perception")
	_check(bool(first_seen.visible) and not bool(first_seen.target_charging) and not bool(first_seen.target_reloading), "first reacted sample retains the older weapon state")
	_bot.set("_elapsed", 0.35)
	_bot.call("_update_duel_perception", _target, _player, true)
	var matured: Dictionary = _bot.get("_perception")
	_check(bool(matured.target_charging) and bool(matured.target_reloading), "visible weapon state becomes usable after its reaction delay")
	_check(is_equal_approx(float(matured.target_health_fraction), 0.60), "reacted health comes from the observed damage sample")
	var remembered: Vector3 = _bot.get("_last_observed_position")
	_player.global_position = Vector3(-23, 0, -19)
	_player.call("take_damage", 200.0, "tactics_test", "hidden_health")
	_player.set("_blaster_charge_active", false)
	_player.set("_shotgun_reloading", false)
	_bot.set("_elapsed", 0.50)
	_bot.call("_update_duel_perception", _target, _player, false)
	var hidden: Dictionary = _bot.get("_perception")
	_check(Vector3(_bot.get("_last_observed_position")) == remembered, "hidden movement does not update remembered target position")
	_check(is_equal_approx(float(hidden.target_health_fraction), 0.60), "hidden damage does not update target health knowledge")
	_check(not bool(hidden.target_charging) and not bool(hidden.target_reloading), "lost sight stops immediate weapon-state reactions")
	_bot.set("_elapsed", 4.50)
	_bot.call("_update_duel_perception", _target, _player, false)
	_check(not bool(_bot.get("_has_last_observed_position")), "unseen target memory expires rather than tracking forever")
	_player.call("reset_combat_state")


func _test_unseen_search() -> void:
	_bot.call("reset_clock")
	_target.global_position = Vector3(-8, 0, 0)
	_player.global_position = Vector3(22, 0, 22)
	_bot.set("_elapsed", 1.0)
	_bot.set("_search_index", 0)
	_bot.call("_select_tactical_destination", _target, _player)
	var first: Vector3 = _bot.get("_tactical_destination")
	_bot.call("reset_clock")
	_bot.set("_elapsed", 1.0)
	_bot.set("_search_index", 0)
	_player.global_position = Vector3(-22, 0, -22)
	_bot.call("_select_tactical_destination", _target, _player)
	_check(Vector3(_bot.get("_tactical_destination")) == first, "unseen search chooses the same sector regardless of hidden player position")
	_check(first.distance_to(_target.global_position) > 10.0, "unseen search leaves the spawn neighbourhood")
	var extremes := Vector4(0, 0, 0, 0)
	for sector in range(9):
		_bot.set("_elapsed", 12.0 + float(sector) * 11.0)
		var destination: Vector3 = _bot.call("_select_search_destination", _target)
		extremes.x = minf(extremes.x, destination.x)
		extremes.y = maxf(extremes.y, destination.x)
		extremes.z = minf(extremes.z, destination.z)
		extremes.w = maxf(extremes.w, destination.z)
	_check(extremes.x < -15.0 and extremes.y > 15.0 and extremes.z < -15.0 and extremes.w > 15.0, "search sweep includes every side of the map and its distant repair lanes")
	_check(not bool(_bot.get("_has_last_observed_position")), "sector search never manufactures target knowledge")


func _test_retreat_cover() -> void:
	var cover := _wall(Vector3.ZERO, Vector3(8.0, 2.0, 1.0))
	await physics_frame
	_bot.call("reset_clock")
	_bot.get("_navigation").invalidate(true)
	_target.call("reset_combat_state")
	_target.call("take_damage", 800.0, "tactics_test", "retreat_health")
	_target.global_position = Vector3(0, 0, -2)
	_player.global_position = Vector3(0, 0, -4)
	_bot.set("_elapsed", 1.0)
	_bot.call("_update_duel_perception", _target, _player, true)
	_bot.set("_elapsed", 1.30)
	_bot.call("_update_duel_perception", _target, _player, true)
	_bot.call("_update_duel_decision", _target, _player)
	_check(str(_bot.call("get_current_intent")) in ["break_line", "retreat"], "critically damaged bot prioritises a safer position")
	var destination: Vector3 = _bot.get("_tactical_destination")
	_check(bool(_bot.get("_has_tactical_destination")), "retreat has a reachable destination")
	_check(not bool(_bot.call("_duel_path_clear", _target, destination, _player.global_position)), "retreat selects actual cover that blocks the known threat's shot")
	var cover_reached := false
	for step in range(220):
		_bot.set("_elapsed", 1.35 + float(step) * 0.05)
		_bot.call("_update_duel_movement", _target, _player.global_position, true, 0.05)
		if not bool(_bot.call("_duel_path_clear", _target, _target.global_position, _player.global_position)):
			cover_reached = true
			break
		if step % 5 == 0:
			await physics_frame
	_check(cover_reached, "retreat follows its detour until the robot is protected by cover")
	cover.queue_free()
	await physics_frame
	_target.call("reset_combat_state")


func _test_repair_detour() -> void:
	var barrier := _wall(Vector3.ZERO, Vector3(0.2, 2.0, 24.0))
	var kit := REPAIR_KIT.instantiate() as Node3D
	kit.position = Vector3(8, 0, 0)
	kit.name = "TestRepairBeyondWall"
	_scene.add_child(kit)
	kit.call("set_collection_active", true)
	_target.global_position = Vector3(-8, 0, 0)
	_player.global_position = Vector3(-20, 0, -20)
	_target.call("reset_combat_state")
	_target.call("take_damage", 600.0, "tactics_test", "repair_health")
	_bot.call("reset_clock")
	_bot.get("_navigation").invalidate(true)
	await physics_frame
	var healed := false
	var furthest_z := 0.0
	var sought_kit := false
	for step in range(460):
		_bot.set("_elapsed", 1.0 + float(step) * 0.05)
		var seeking := bool(_bot.call("_update_repair_target", _target, _player))
		sought_kit = sought_kit or seeking
		if seeking:
			_bot.call("_advance_repair_seek", _target, 0.05)
		furthest_z = maxf(furthest_z, absf(_target.global_position.z))
		if float(_target.call("get_health")) > 400.0:
			healed = true
			break
		if step % 5 == 0:
			await physics_frame
	_check(sought_kit, "injured bot selects a distant available kit behind an obstacle")
	_check(furthest_z > 12.5, "repair path goes around the long wall instead of pushing into it")
	_check(healed and is_equal_approx(float(_target.call("get_health")), 700.0), "repair detour reaches the kit and applies the shared 30 percent heal")
	print("Repair route final position %s, maximum detour %.2f m, PV %.0f" % [_target.global_position, furthest_z, float(_target.call("get_health"))])
	barrier.queue_free()
	kit.queue_free()
	await physics_frame
	_target.call("reset_combat_state")


func _test_survival_detour() -> void:
	var barrier := _wall(Vector3.ZERO, Vector3(0.2, 2.0, 24.0))
	_target.global_position = Vector3(-8, 0, 0)
	_player.global_position = Vector3(8, 0, 0)
	_bot.call("reset_clock")
	_bot.get("_navigation").invalidate(true)
	_bot.set("survival_role", "chaser")
	_bot.set("_next_attack_at", 10000.0)
	await physics_frame
	var reached := false
	var furthest_z := 0.0
	for step in range(500):
		_bot.call("_update_survival_bot", _target, _player, 0.05)
		furthest_z = maxf(furthest_z, absf(_target.global_position.z))
		if _target.global_position.distance_to(_player.global_position) < 2.1:
			reached = true
			break
		if step % 5 == 0:
			await physics_frame
	_check(furthest_z > 12.5 and furthest_z <= 21.0, "survival chaser uses a legal whole-map detour")
	_check(reached, "survival chaser reaches melee range after navigating around cover")
	print("Survival route final position %s, maximum detour %.2f m" % [_target.global_position, furthest_z])
	_bot.set("survival_role", "")
	barrier.queue_free()
	await physics_frame


func _wall(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at + Vector3.UP * dimensions.y * 0.5
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	collision.shape = box
	body.add_child(collision)
	_scene.add_child(body)
	return body


func _test_hidden_combat_reactions() -> void:
	_bot.call("reset_clock")
	_target.global_position = Vector3(-8, 0, 0)
	var remembered := Vector3(8, 0, 0)
	_player.global_position = Vector3(20, 0, -16)
	_bot.set("survival_role", "shooter")
	_bot.set("_last_observed_position", remembered)
	_bot.set("_has_last_observed_position", true)
	_bot.set("_charge_target", remembered)
	_bot.call("_spawn_attack_visual", _player, "hidden_aim_fixture")
	var projectile := _scene.get_node_or_null("TrainingBotProjectile") as Node3D
	if projectile == null:
		_check(false, "survival ranged shot fixture must create its projectile")
	else:
		var expected := (remembered + Vector3.UP * 0.92 - projectile.global_position).normalized()
		var actual := -projectile.global_basis.z.normalized()
		_check(actual.dot(expected) > 0.999, "survival projectile keeps the remembered aim when the target moves unseen")
	# Let its callback and tween release their actor references naturally.
	await create_timer(0.25).timeout
	_bot.set("survival_role", "")
	var barrier := _wall(Vector3.ZERO, Vector3(0.2, 2.0, 24.0))
	_player.global_position = remembered
	# Acquire the real combat action without starting an audio stream in the
	# headless fixture; attack commitment reads this shared action gate.
	var charge_token: int = _player.call("_try_begin_weapon_action", "blaster")
	_player.set("_blaster_action_token", charge_token)
	_player.set("_blaster_charge_active", true)
	_check(bool(_player.call("is_attack_committed")), "hidden defensive-buffer fixture must have a committed charge")
	_bot.set("_perception", {"visible": false, "target_charging": false})
	_target.set("_fulguro_wall_stun_active", true)
	_target.call("apply_stun", 1.0, "hidden_buffer_fixture")
	await physics_frame
	_bot.call("_consider_buffered_dodge", _target, _player)
	_check(str(_target.call("get_buffered_defensive_action")).is_empty(), "a wall-stunned bot does not buffer against an unseen attack input")
	_target.set("_fulguro_wall_stun_active", false)
	_target.call("reset_combat_state")
	_player.call("reset_combat_state")
	barrier.queue_free()
	await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _prepare_manual_duel(bot_position: Vector3, player_position: Vector3) -> void:
	_target.call("reset_combat_state")
	_player.call("reset_combat_state")
	_target.global_position = bot_position
	_player.global_position = player_position
	_target.call("set_duel_mode", true)
	_target.call("set_training_bot_enabled", true)
	_bot.set_physics_process(false)
	_bot.get("_navigation").invalidate(true)
	var equipment: Node = _bot.get("_duel_equipment")
	equipment.set("next_attack_at", 10000.0)
	equipment.set("_next_module_at", 10000.0)


func _test_repair_respawn_and_contest() -> void:
	var kit := REPAIR_KIT.instantiate() as Node3D
	kit.position = Vector3(8, 0, 0)
	kit.name = "TestReturningRepair"
	_scene.add_child(kit)
	kit.set_process(false)
	kit.call("set_collection_active", true)
	# Consume the real point first, then exercise its late recharge window.
	_player.call("reset_combat_state")
	_player.call("take_damage", 500.0, "tactics_test", "respawn_consumer")
	_player.global_position = kit.global_position
	_check(float(kit.call("try_collect", _player)) > 0.0, "respawn fixture consumes a real kit")
	_prepare_manual_duel(Vector3.ZERO, Vector3(-23, 0, -23))
	_target.call("take_damage", 600.0, "tactics_test", "returning_kit_health")
	kit.set("_respawn_remaining", 7.0)
	await physics_frame
	_bot.call("_physics_process", 0.05)
	_check(_bot.call("get_repair_target") == null, "a kit unavailable for more than six seconds is not a repair objective")
	kit.set("_respawn_remaining", 3.0)
	var planned_return := false
	var waited_on_pad := false
	var recovered := false
	for step in range(100):
		kit.call("_process", 0.05)
		_bot.call("_physics_process", 0.05)
		if _bot.call("get_repair_target") == kit and str(_bot.call("get_current_intent")) == "seek_heal":
			planned_return = true
		if not bool(kit.call("is_available")) and _target.global_position.distance_to(kit.global_position) < float(kit.call("get_collection_radius")) + 0.1:
			waited_on_pad = waited_on_pad or is_equal_approx(float(_target.call("get_health")), 400.0)
		if float(_target.call("get_health")) > 400.0:
			recovered = true
			break
		if step % 5 == 0:
			await physics_frame
	_check(planned_return, "injured bot plans its trip before an imminent kit respawn")
	_check(waited_on_pad, "bot arrives and waits without receiving unavailable healing")
	_check(recovered and is_equal_approx(float(_target.call("get_health")), 700.0), "bot collects the returning kit once it becomes available")

	# A partly injured bot can deny a needed heal to a visibly injured opponent.
	_prepare_manual_duel(Vector3.ZERO, Vector3(12, 0, 0))
	kit.position = Vector3(5, 0, 0)
	kit.call("reset_for_round", true)
	_target.call("take_damage", 250.0, "tactics_test", "contest_bot_health")
	_player.call("take_damage", 650.0, "tactics_test", "contest_target_health")
	_bot.set("_elapsed", 1.0)
	_bot.call("_update_duel_perception", _target, _player, false)
	_bot.call("_update_duel_decision", _target, _player)
	_check(str(_bot.call("get_current_intent")) != "control_repair", "hidden opponent damage cannot trigger kit denial")
	_bot.call("_update_duel_perception", _target, _player, true)
	_bot.set("_elapsed", 1.30)
	_bot.call("_update_duel_perception", _target, _player, true)
	_bot.call("_update_duel_decision", _target, _player)
	_check(str(_bot.call("get_current_intent")) == "control_repair", "observed low-health opponent makes a contested available kit worth controlling")
	_check(Vector3(_bot.get("_tactical_destination")) == kit.global_position, "kit denial intent routes to the contested point")
	var denied := false
	for step in range(75):
		_bot.call("_physics_process", 0.05)
		_target.force_update_transform()
		await physics_frame
		await process_frame
		if float(_target.call("get_health")) > 750.0:
			denied = not bool(kit.call("is_available"))
			break
	_check(denied and is_equal_approx(float(_target.call("get_health")), 1000.0), "bot reaches and consumes the contested heal before its opponent")
	print("Contested kit final position %s, PV %.0f, available %s, intent %s" % [_target.global_position, float(_target.call("get_health")), str(kit.call("is_available")), str(_bot.call("get_current_intent"))])
	_target.call("set_training_bot_enabled", false)
	kit.queue_free()
	await physics_frame


func _test_dash_and_stasis_ownership() -> void:
	_prepare_manual_duel(Vector3(-8, 0, 0), Vector3(-23, 0, -23))
	_target.call("set_duel_loadout", {"weapon": "blaster", "offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "omnivamp"})
	var equipment: Node = _bot.get("_duel_equipment")
	equipment.set("next_attack_at", 10000.0)
	equipment.set("_next_module_at", 10000.0)
	_bot.set("_dodge_remaining", 0.30)
	_bot.set("_dodge_direction", Vector3.FORWARD)
	_bot.set("_move_velocity", Vector3.FORWARD * 7.2)
	var started := bool(equipment.call("_try_tactical_dash", _target, _bot, Vector3.RIGHT))
	_check(started, "Pyro fixture starts a real dash while an ordinary dodge is active")
	var before := _target.global_position
	var remaining_before := float(equipment.get("dash_remaining"))
	_bot.call("_physics_process", 0.05)
	_check(_target.global_position.x > before.x + 0.5 and absf(_target.global_position.z - before.z) < 0.05, "Pyro movement overrides the old ordinary dodge direction")
	_check(float(equipment.get("dash_remaining")) < remaining_before and is_zero_approx(float(_bot.get("_dodge_remaining"))), "Pyro travel clock advances and consumes stale ordinary dodge state")
	_bot.set("_dodge_remaining", 0.25)
	_bot.set("_move_velocity", Vector3.FORWARD * 7.2)
	equipment.call("_activate_static_shield", _target)
	var shield_position := _target.global_position
	_bot.call("_physics_process", 0.05)
	_check(_target.global_position.is_equal_approx(shield_position), "stasis prevents travel from both movement sources")
	_check(is_zero_approx(float(_bot.get("_dodge_remaining"))) and not bool(equipment.call("is_dashing")), "stasis clears ordinary dodge and Pyro travel instead of postponing them")
	# Finish the visual tween before destroying its actor fixture.
	await create_timer(1.65).timeout
	_target.call("set_training_bot_enabled", false)
	_target.call("reset_combat_state")


func _report() -> void:
	if not _finished:
		_failures.append("world-tactics test did not complete all scenarios")
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("BOT WORLD TACTICS TEST: %s" % ("PASS" if _failures.is_empty() else "FAIL (%d)" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)
