extends SceneTree

const AI_PROFILE := preload("res://scripts/bot_ai_profile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var easy := AI_PROFILE.values("easy")
	var normal := AI_PROFILE.values("normal")
	var hard := AI_PROFILE.values("hard")
	_check(float(easy.reaction_delay) > float(normal.reaction_delay) and float(normal.reaction_delay) > float(hard.reaction_delay), "profiles improve reaction without changing combat stats")
	_check(float(easy.aim_error_degrees) > float(normal.aim_error_degrees) and float(normal.aim_error_degrees) > float(hard.aim_error_degrees), "profiles expose progressive aim limits")
	_check(int(easy.candidate_count) < int(hard.candidate_count), "hard profile evaluates more positions")

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.get_node_or_null("Player") as Node3D
	var target := scene.get_node_or_null("TargetDummy") as Node3D
	if player == null or target == null:
		failures.append("duel actors missing")
		_finish()
		return
	target.call("set_duel_mode", true)
	target.call("set_bot_difficulty", "hard")
	target.call("set_duel_loadout", {"weapon": "blaster", "offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "omnivamp"})
	target.call("set_bot_diagnostics_enabled", true)
	target.global_position = Vector3(0.0, 0.0, 16.0)
	player.global_position = Vector3(0.0, 0.0, 23.0)
	target.call("set_training_bot_enabled", true)
	for _frame in range(12):
		await physics_frame
	var snapshot: Dictionary = target.call("get_bot_diagnostic_snapshot")
	_check(str(snapshot.get("difficulty", "")) == "hard", "difficulty reaches the tactical controller")
	_check(bool(snapshot.get("target_known", false)) and bool(snapshot.get("target_visible", false)), "perception publishes only a reacted visible target")
	_check(not str(snapshot.get("intent", "")).is_empty(), "decision publishes a persistent intent")
	_check((snapshot.get("destination", Vector3.INF) as Vector3).is_finite(), "decision selects an accessible combat destination")
	_check(target.get_node_or_null("TrainingBot/BotAIDiagnostic") != null, "optional diagnostic label is available")

	var configured: Dictionary = target.call("get_duel_loadout")
	_check(str(configured.offensive) == "javelin" and str(configured.defensive) == "static_shield" and str(configured.mobility) == "pyro_boots" and str(configured.passive) == "omnivamp", "all module categories are routed to bot execution")
	target.call("set_training_bot_enabled", false)
	await _test_vision_and_firing_obstacles(scene, player, target)
	scene.queue_free()
	await process_frame
	_finish()


func _test_vision_and_firing_obstacles(scene: Node, player: Node3D, target: Node3D) -> void:
	player.call("reset_combat_state")
	target.call("reset_combat_state")
	player.call("set_gameplay_enabled", false)
	target.global_position = Vector3(0, 0, 16)
	player.global_position = Vector3(0, 0, 23)
	target.call("set_duel_loadout", {"weapon": "blaster", "offensive": "modulo_drone", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"})
	target.call("set_training_bot_enabled", true)
	var bot := target.get_node("TrainingBot")
	bot.set_physics_process(false)
	bot.set("training_stationary", true)
	var equipment: Node = bot.get("_duel_equipment")
	# Keep mobility from changing this sightline; attacks/modules remain ready.
	equipment.set("module_cooldowns", {"bio_injector": 100.0})
	var field := Area3D.new()
	field.name = "TestTransparentMagneticField"
	field.collision_layer = 8
	field.collision_mask = 0
	field.monitoring = false
	field.monitorable = true
	field.add_child(_obstacle_shape())
	scene.add_child(field)
	field.global_position = Vector3(0, 1.2, 19.5)
	await physics_frame
	await physics_frame
	_check(bool(player.call("is_visible_to", target)) and bool(target.call("is_visible_to", player)), "magnetic field remains transparent to actor visibility")
	_check(bool(bot.call("_line_of_sight_clear", target, player)), "bot vision ignores projectile-only magnetic fields")
	_check(not bool(bot.call("_weapon_line_of_fire_clear", target, player, player.global_position)), "magnetic field still blocks the bot's firing line")
	for _step in range(12):
		bot.call("_physics_process", 0.05)
	var perception: Dictionary = bot.get("_perception")
	_check(bool(perception.get("visible", false)) and bool(perception.get("known", false)), "bot perceives and remembers an enemy across a magnetic field")
	_check(not bool(perception.get("line_of_fire", true)), "vision across a magnetic field does not grant a firing lane")
	_check(is_zero_approx(float(equipment.get("charge_remaining"))) and str(equipment.get("pending_module")).is_empty() and int(equipment.get("_shot_serial")) == 0, "bot starts no charge, offensive module or shot into a blocked magnetic firing lane")
	# Older call sites omit line_of_fire. A charge must still use the firing
	# helper when a shield appears while the target itself remains visible.
	_check(bool(equipment.call("_begin_weapon_action")), "legacy charge fixture acquires its weapon action")
	equipment.set("charge_duration", 0.4)
	equipment.set("charge_remaining", 0.4)
	equipment.call("tick", 0.25, 1.0, true, player.global_position, target, player, bot, {}, bot.get("_tuning"))
	_check(is_zero_approx(float(equipment.get("charge_remaining"))) and int(equipment.get("_shot_serial")) == 0, "legacy charge cancels when a magnetic field blocks fire without blocking vision")
	# The live projectile reports the first physical surface, independently of vision.
	var health_before := float(player.call("get_health"))
	var impact_origin := target.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(impact_origin, player.global_position + Vector3.UP * 0.92)
	query.collision_mask = 1 | 4 | 8
	query.collide_with_areas = true
	query.exclude = [target.get_rid()]
	var impact_hit: Dictionary = target.get_world_3d().direct_space_state.intersect_ray(query)
	_check(impact_hit.get("collider") == field, "the pending projectile reaches the magnetic field before the player")
	if not impact_hit.is_empty():
		bot.call("_resolve_projectile", impact_hit, impact_origin.distance_to(impact_hit.position), player, scene, "transparent_field_impact")
	_check(is_equal_approx(float(player.call("get_health")), health_before), "transparent field still absorbs a pending training projectile before damage")
	field.queue_free()
	await physics_frame
	await physics_frame
	var wall := StaticBody3D.new()
	wall.name = "TestStrictVisionWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.add_child(_obstacle_shape())
	scene.add_child(wall)
	wall.global_position = Vector3(0, 1.2, 19.5)
	await physics_frame
	await physics_frame
	player.call("_mark_combat_event")
	target.call("mark_combat_event")
	player.call("apply_spotted", 4.0, "strict_los_test")
	target.call("apply_spotted", 4.0, "strict_los_test")
	_check(not bool(player.call("is_visible_to", target)) and not bool(target.call("is_visible_to", player)), "solid wall blocks both actor views despite combat and SPOTTED reveals")
	var last_seen: Vector3 = bot.get("_last_observed_position")
	player.global_position.x = 1.0
	for _step in range(6):
		bot.call("_physics_process", 0.05)
	perception = bot.get("_perception")
	_check(not bool(perception.get("visible", true)) and not bool(perception.get("raw_visible", true)), "combat and SPOTTED cannot give bot perception through a solid wall")
	_check(Vector3(bot.get("_last_observed_position")) == last_seen, "wall-hidden movement cannot refresh the bot's last seen position")
	_check(int(equipment.get("_shot_serial")) == 0 and str(equipment.get("pending_module")).is_empty(), "wall-hidden reveal cannot start a targeted shot or offensive module")
	target.call("set_training_bot_enabled", false)
	bot.set("training_stationary", false)
	wall.queue_free()
	await physics_frame


func _obstacle_shape() -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.25)
	collision.shape = box
	return collision


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("BOT TACTICS TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		print("BOT TACTICS TEST: FAIL (%d)" % failures.size())
		quit(1)
