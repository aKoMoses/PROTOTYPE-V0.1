extends SceneTree

var _heard: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player or TargetDummy missing")
	else:
		root.get_node("GameSfx").connect("event_played", func(event_id: String) -> void: _heard.append(event_id))
		player.call("set_gameplay_enabled", true)
		target.call("set_training_bot_enabled", false)
		player.global_position = Vector3.ZERO
		player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
		player.set("_offensive_module_id", "javelin")
		target.global_position = Vector3(0.0, 0.0, -2.0)
		player.set_physics_process(false)
		await physics_frame
		await physics_frame
		player.call("_perform_javelin")
		# The real launch now advances the charge in the Player physics loop,
		# which this fixture disables to keep both collision actors stationary.
		player.call("_update_javelin_charge", 1.0)
		for _frame in range(240):
			await physics_frame
			if bool(target.call("has_javelin_mark")):
				break
		player.call("_perform_javelin")
		await process_frame
		_expect("javelin_teleport")
		player.call("reset_combat_state")
		target.call("reset_combat_state")

		player.set("_last_move_direction", Vector3.RIGHT)
		player.call("_perform_mobility_module")
		_expect("pyro_dash")

		target.call("take_damage", 10.0, "player", "sfx:normal")
		_expect("impact_robot")
		target.call("take_damage", 10.0, "player", "sfx:critical")
		_expect("impact_critical")
		target.call("take_damage", 2000.0, "player", "sfx:kill")
		_expect("robot_destruction")
		player.call("take_damage", 10.0, "sfx", "received")
		_expect("damage_received")

		var decor := StaticBody3D.new()
		decor.name = "SoundTestDecor"
		scene.add_child(decor)
		player.call("_contact_fx", {"position": Vector3.ZERO, "normal": Vector3.UP, "collider": decor}, Color.WHITE)
		_expect("impact_decor")
		var wall := Area3D.new()
		wall.name = "MagneticField"
		scene.add_child(wall)
		player.call("_contact_fx", {"position": Vector3.ZERO, "normal": Vector3.UP, "collider": wall}, Color.WHITE)
		_expect("magnetic_absorb")
		decor.queue_free()
		wall.queue_free()
		await _test_new_sounds(player, target, scene)
		await create_timer(4.0).timeout

	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("clear")
	root.get_node("GameSfx").call("clear")
	current_scene = null
	scene.queue_free()
	# Let deferred audio/presentation cleanup complete before shutting down.
	for frame in 3:
		await process_frame
	if _failures.is_empty():
		print("GAME SFX TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("GAME SFX TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _expect(event_id: String) -> void:
	if not _heard.has(event_id):
		_failures.append("Missing combat sound: " + event_id)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_new_sounds(player: Node3D, target: Node3D, scene: Node) -> void:
	var sfx := root.get_node("GameSfx")
	sfx.call("reset_locomotion")
	_heard.clear()
	for frame in range(120):
		sfx.call("update_locomotion", 0.0, 1.0 / 60.0, false, true)
	_check(not _heard.has("robot_footstep"), "No footsteps while stationary")
	sfx.call("update_locomotion", 12.0, 0.6, false, true)
	sfx.call("update_locomotion", 0.8, 0.6, false, false)
	_check(not _heard.has("robot_footstep"), "No footsteps for teleports or dashes")
	var previous := -1
	for step in range(12):
		(sfx.get("_step_player") as AudioStreamPlayer).stop()
		for frame in range(40):
			sfx.call("update_locomotion", 0.08, 1.0 / 60.0, false, true)
		var index := int(sfx.get("_last_step"))
		_check(index != previous, "Footstep must change grain")
		previous = index
	_expect("robot_footstep")
	_check(_heard.count("robot_footstep") <= 12, "Footstep cadence bounded")
	sfx.call("update_locomotion", 0.1, 0.02, true, true)
	sfx.call("_process", 0.4)
	_check((sfx.get("_rustle") as AudioStreamPlayer).playing, "Moving in bushes starts rustle")
	sfx.call("update_locomotion", 0.0, 0.02, true, true)
	sfx.call("_process", 0.4)
	_check(not (sfx.get("_rustle") as AudioStreamPlayer).playing, "Stopping fades rustle to silence")

	# Real occupancy transitions; changing between overlapping bushes is silent.
	player.call("reset_combat_state")
	player.global_position = Vector3(50, 0, 50)
	player.call("_sync_bush_state")
	_heard.clear()
	var bush := Node3D.new()
	scene.add_child(bush)
	bush.add_to_group("bush_placeholder")
	bush.set_meta("bush_radius", 2.0)
	bush.global_position = player.global_position
	player.call("_sync_bush_state")
	_expect("bush_entry")
	player.global_position.x += 4.0
	player.call("_sync_bush_state")
	_check(not _heard.has("bush_exit"), "Bush edge chatter suppressed")
	await create_timer(0.7).timeout
	player.global_position = bush.global_position
	player.call("_sync_bush_state")
	await create_timer(0.7).timeout
	player.global_position.x += 4.0
	player.call("_sync_bush_state")
	_expect("bush_exit")
	bush.queue_free()

	player.call("set_passive", "")
	player.call("reset_combat_state")
	player.set("training_invulnerable", false)
	_heard.clear()
	player.call("take_damage", player.call("get_max_health") * 0.8, "sfx", "low1")
	_expect("low_health")
	player.call("take_damage", 1.0, "sfx", "low2")
	_check(_heard.count("low_health") == 1, "Low health alert does not repeat on each hit")
	player.call("heal", player.call("get_max_health") * 0.1)
	_check(not bool(player.get("_low_health_sound_armed")), "Small heals cannot rearm alert")
	player.call("heal", player.call("get_max_health") * 0.3)
	_check(bool(player.get("_low_health_sound_armed")), "Recovery above 40 percent rearms alert")
	player.call("set_passive", "baroud")
	player.call("reset_combat_state")
	player.call("take_damage", 5000.0, "sfx", "baroud1")
	_expect("baroud_activation")
	player.call("take_damage", 1.0, "sfx", "baroud2")
	_check(_heard.count("baroud_activation") == 1, "Baroud only sounds at activation")
	player.call("reset_combat_state")
	player.global_position = Vector3.ZERO
	target.call("reset_combat_state")
	target.global_position = Vector3(0, 0, -1.5)
	var bot: Node = target.get_node("TrainingBot")
	bot.set_physics_process(false)
	bot.call("cancel_action")
	bot.set("survival_role", "chaser")
	bot.set("_next_attack_at", 0.0)
	bot.call("_update_survival_bot", target, player, 0.01)
	bot.call("_update_survival_bot", target, player, 0.6)
	_expect("enemy_melee")
	bot.call("cancel_action")
	bot.set("survival_role", "charger")
	bot.set("_next_attack_at", 0.0)
	bot.call("_update_survival_bot", target, player, 0.01)
	_expect("enemy_charge_warning")
	bot.call("cancel_action")
	bot.call("_spawn_attack_visual", player, "sfx:shot")
	_expect("enemy_shot")
	var before := _heard.size()
	sfx.call("play_enemy", "enemy_shot", Vector3(100, 0, 100), Vector3.ZERO)
	_check(_heard.size() == before, "Distant enemies are silent")
	# A busy attack mix cannot consume warning slots or restart busy voices.
	var voices: Array = sfx.get("_enemy_voices")
	var cooldowns: Dictionary = sfx.get("_last_played_ms")
	for voice in voices:
		voice.stop()
	for index in range(4):
		cooldowns.erase("enemy_shot")
		sfx.call("play_enemy", "enemy_shot", Vector3.ZERO, Vector3.ZERO)
	before = _heard.size()
	cooldowns.erase("enemy_shot")
	sfx.call("play_enemy", "enemy_shot", Vector3.ZERO, Vector3.ZERO)
	_check(_heard.size() == before, "Attack voice cap drops excess sounds")
	cooldowns.erase("enemy_charge_warning")
	sfx.call("play_enemy", "enemy_charge_warning", Vector3.ZERO, Vector3.ZERO)
	_check(_heard.size() == before + 1 and voices[4].playing, "Warnings survive attack saturation")
	for voice in voices:
		voice.stop()
	cooldowns.erase("enemy_shot")
	sfx.call("play_enemy", "enemy_shot", Vector3(20, 0, 0), Vector3.ZERO)
	_check(voices[0].volume_db < -25.0, "Enemy distance attenuates volume")
	_check(voices[0].bus == &"Effects", "Sound obeys effects volume settings")

	# Exercise the real player physics path, then stop while gameplay stays active.
	player.call("reset_combat_state")
	player.global_position = Vector3(50, 0, 50)
	player.set_physics_process(true)
	player.call("set_move_input", Vector2.RIGHT)
	_heard.clear()
	for frame in range(100):
		await physics_frame
	var steps := _heard.count("robot_footstep")
	_check(steps >= 1 and steps <= 3, "Actual movement produces sparse footsteps")
	player.call("set_move_input", Vector2.ZERO)
	for frame in range(40):
		await physics_frame
	_check(_heard.count("robot_footstep") == steps, "Actual stopped player produces no extra footsteps")
	player.set_physics_process(false)
	player.call("set_gameplay_enabled", false)
	_check(not (sfx.get("_rustle") as AudioStreamPlayer).playing, "Menus stop movement audio")
