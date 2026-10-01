extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var scene: Node3D
var hazards: Node3D
var player: CharacterBody3D
var bot: StaticBody3D
var flow: CanvasLayer


func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	hazards = scene.get_node("ArenaHazards")
	player = scene.get_node("Player")
	bot = scene.get_node("TargetDummy")
	flow = scene.get_node("Interface")
	player.set_physics_process(false)
	player.set_process(false)
	hazards.set_physics_process(false)
	_check(not hazards.visible and not bool(hazards.get("enabled")), "classic hides and disables every fixture")
	_check((hazards.get("_fixtures") as Array).size() == 6, "four tiles and two cannons exist")
	flow.call("_select_arena", "hazards")
	_check(scene.get("arena_variant") == "hazards" and hazards.visible, "menu selects the trapped arena")
	flow.call("_start_duel")
	bot.call("set_training_bot_enabled", false)
	hazards.call("advance", 20.0)
	_check(float(hazards.get("elapsed")) == 0.0, "countdown cannot start the hazard clock")
	flow.call("_begin_live_round")
	bot.call("set_training_bot_enabled", false)
	hazards.call("advance", 11.9)
	_check(int(hazards.call("get_snapshot").busy) == 0, "initial grace period")
	hazards.call("advance", 0.11)
	_check(int(hazards.call("get_snapshot").busy) == 1, "first isolated warning starts after grace")
	var elapsed_before := float(hazards.get("elapsed"))
	paused = true
	hazards.call("advance", 5.0)
	await process_frame
	_check(float(hazards.get("elapsed")) == elapsed_before, "pause freezes escalation and warnings")
	paused = false

	_reset()
	var tile: Vector3 = hazards.get("TILE_POSITIONS")[0]
	player.global_position = tile
	bot.global_position = tile + Vector3(0.7, 0, 0)
	var player_health := float(player.call("get_health"))
	var bot_health := float(bot.call("get_health"))
	var tile_visual := hazards.get_node("ElectricTile1")
	var louver := tile_visual.get_node("Louver0") as Node3D
	_check(is_zero_approx(louver.rotation.z), "tile shutters rest flat")
	hazards.call("warn_fixture", 0)
	hazards.call("advance", 0.8)
	_check(louver.rotation.z > 0.3, "warning mechanically opens the shutters")
	var open_angle := louver.rotation.z
	paused = true
	hazards.call("advance", 0.5)
	_check(is_equal_approx(louver.rotation.z, open_angle), "pause freezes the visible shutters")
	paused = false
	_check(float(player.call("get_health")) == player_health and float(bot.call("get_health")) == bot_health, "warnings deal no damage to either actor")
	hazards.call("advance", 0.81)
	_check(tile_visual.get_node("ElectricalDischarge").visible, "electrical arcs coincide with active damage")
	_check(is_equal_approx(player_health - float(player.call("get_health")), 65.0), "tile damages player once")
	_check(is_equal_approx(bot_health - float(bot.call("get_health")), 65.0), "same tile damages bot equally")
	hazards.call("advance", 0.2)
	hazards.call("advance", 0.2)
	_check(is_equal_approx(player_health - float(player.call("get_health")), 65.0), "staying on a live tile does not multiply damage")
	hazards.call("advance", 0.26)
	_check(not tile_visual.get_node("ElectricalDischarge").visible and louver.rotation.z > 0.0 and louver.rotation.z < open_angle, "discharge stops while shutters return smoothly")
	hazards.call("advance", 0.3)
	_check(is_zero_approx(louver.rotation.z), "idle frames finish the shutter return")

	_reset()
	player.global_position = tile + Vector3(5, 0, 0)
	bot.global_position = Vector3(20, 0, 20)
	player_health = float(player.call("get_health"))
	hazards.call("warn_fixture", 0)
	hazards.call("advance", 1.61)
	player.global_position = tile
	hazards.call("advance", 0.1)
	_check(is_equal_approx(player_health - float(player.call("get_health")), 65.0), "entering a tile during its discharge is dangerous")

	_reset()
	player.global_position = Vector3(20, 0, 20)
	bot.global_position = Vector3(20, 0, -20)
	var cannon_visual := hazards.get_node("WallCannon1")
	var barrel := cannon_visual.get_node("RetractableBarrel") as Node3D
	var rest_position := barrel.position.z
	hazards.call("warn_fixture", 4)
	hazards.call("advance", 0.8)
	_check(barrel.position.z > rest_position + 0.3, "cannon warning extends its real barrel")
	hazards.call("advance", 0.81)
	var firing: Dictionary = cannon_visual.call("get_presentation")
	_check(float(firing.flash) > 0.0 and float(firing.recoil) > 0.0, "projectile spawn triggers muzzle flash and recoil")
	var recoil_position := barrel.position.z
	paused = true
	hazards.call("advance", 0.1)
	_check(cannon_visual.call("get_presentation") == firing and barrel.position.z == recoil_position, "pause freezes cannon recoil and flash")
	paused = false
	hazards.call("advance", 0.1)
	_check(barrel.position.z > recoil_position and is_zero_approx(float(cannon_visual.call("get_presentation").flash)), "barrel recovers after its short flash")
	hazards.call("stop_round")
	_check(is_equal_approx(barrel.position.z, rest_position) and is_zero_approx(float(cannon_visual.call("get_presentation").recoil)), "round stop resets the mechanism immediately")

	for target_actor in [player, bot]:
		_reset()
		player.global_position = Vector3(20, 0, 20)
		bot.global_position = Vector3(20, 0, -20)
		target_actor.global_position = Vector3(-23, 0, -13)
		await physics_frame
		await physics_frame
		var before := float(target_actor.call("get_health"))
		hazards.call("warn_fixture", 4)
		hazards.call("advance", 1.61)
		for frame in range(28):
			await physics_frame
		_check(is_equal_approx(before - float(target_actor.call("get_health")), 35.0), "cannon projectile hits %s" % target_actor.name)

	_reset()
	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	cover.position = Vector3(-21, 0.85, -13)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 3)
	shape.shape = box
	cover.add_child(shape)
	scene.add_child(cover)
	player.global_position = Vector3(-18, 0, -13)
	bot.global_position = Vector3(20, 0, 20)
	await physics_frame
	await physics_frame
	player_health = float(player.call("get_health"))
	hazards.call("warn_fixture", 4)
	_check((hazards.call("threat_at", player.global_position) as Dictionary).is_empty(), "wall blocks the announced danger lane")
	hazards.call("advance", 1.61)
	for frame in range(35):
		await physics_frame
	_check(float(player.call("get_health")) == player_health, "projectiles stop at cover")
	cover.queue_free()
	await process_frame

	_reset()
	var controller := bot.get_node("TrainingBot")
	bot.global_position = tile
	player.global_position = Vector3(20, 0, 20)
	controller.set("training_stationary", false)
	controller.call("set_difficulty_profile", "normal")
	controller.call("_reset_duel_decisions")
	controller.set("_move_velocity", Vector3.ZERO)
	controller.set("_elapsed", 0.0)
	# The slowest chassis must be able to react and leave without using dash.
	var slow_loadout: Dictionary = LOADOUT.defaults()
	slow_loadout.robot = "puissant"
	bot.call("set_duel_loadout", slow_loadout)
	# Exercise a reaction, outside the deliberate every-eighth-warning mistake.
	hazards.set("_serial", 0)
	hazards.call("warn_fixture", 0)
	var before_position := bot.global_position
	controller.call("_update_hazard_avoidance", bot, 1.0 / 60.0)
	_check(bot.global_position == before_position, "bot does not anticipate the warning before its reaction delay")
	bot_health = float(bot.call("get_health"))
	for frame in range(98):
		controller.set("_elapsed", float(frame + 1) / 60.0)
		controller.call("_update_hazard_avoidance", bot, 1.0 / 60.0)
		hazards.call("advance", 1.0 / 60.0)
		await physics_frame
	_check(bot.global_position.distance_to(tile) > 2.0, "slow chassis leaves the announced tile")
	_check(float(bot.call("get_health")) == bot_health, "bot can escape before the discharge")

	_reset()
	hazards.set("elapsed", 35.0)
	_check(int(hazards.call("get_tier")) == 2 and is_equal_approx(float(hazards.call("get_interval")), 5.0), "middle escalation tier")
	hazards.set("elapsed", 65.0)
	hazards.set("_next_event_at", 0.0)
	hazards.set("_event_index", 1)
	hazards.call("advance", 0.01)
	_check(int(hazards.call("get_snapshot").busy) == 2, "late tier pairs one cannon and one separate tile")
	hazards.set("elapsed", 10000.0)
	_check(int(hazards.call("get_tier")) == 3 and is_equal_approx(float(hazards.call("get_interval")), 3.7), "escalation is capped")
	hazards.call("advance", 1.61)
	_check(int(hazards.call("get_snapshot").bolts) == 1, "late salvo begins")
	hazards.call("advance", 0.25)
	hazards.call("advance", 0.25)
	_check(int(hazards.call("get_snapshot").bolts) == 3, "late tier adds a third projectile")
	scene.call("stop_duel")
	_check(not bool(hazards.get("running")) and int(hazards.call("get_snapshot").bolts) == 0, "round end immediately removes hazard projectiles")
	scene.call("prepare_round", LOADOUT.defaults())
	_check(float(hazards.get("elapsed")) == 0.0 and int(hazards.call("get_snapshot").busy) == 0, "new round resets hazards")
	flow.call("_select_arena", "classic")
	scene.call("activate_round")
	hazards.call("advance", 120.0)
	_check(not hazards.visible and not bool(hazards.get("running")) and (hazards.call("get_threats") as Array).is_empty(), "classic remains free of hazards after switching back")
	scene.call("stop_duel")
	if failures.is_empty():
		print("ARENA HAZARDS TEST: PASS (selection, countdown, pause, neutral damage, cover, bot reaction, tiers, animated shutters, barrel, recoil, reset)")
		quit(0)
	else:
		for failure in failures:
			push_error("ARENA HAZARDS TEST: " + failure)
		quit(1)


func _reset() -> void:
	scene.call("prepare_round", LOADOUT.defaults())
	scene.call("activate_round")
	bot.call("set_training_bot_enabled", false)
	hazards.set("_next_event_at", 100000.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
