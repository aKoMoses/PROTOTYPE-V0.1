extends SceneTree

const TRAVERSAL := preload("res://scripts/arena_traversal.gd")
var failures: Array[String] = []
var scene: Node3D
var player: CharacterBody3D
var bot: StaticBody3D
var basin: Node3D
var mechanisms: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_select_arena", "tideglass")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	player = scene.get("player")
	bot = scene.get("target")
	player.set_physics_process(false)
	bot.call("set_training_bot_enabled", false)
	mechanisms = scene.get_node("ArenaHazards")
	mechanisms.set_physics_process(false)
	basin = TRAVERSAL.terrain(player)
	check(basin != null and basin.get("surfaces").size() == 7, "three islands, bridge and three ramps expose actual walking surfaces")
	check(is_equal_approx(player.global_position.y, 1.35) and is_equal_approx(bot.global_position.y, 1.35), "both fighters spawn on dry islands")
	await physics_frame
	await physics_frame
	var origin := player.global_position
	var destination := bot.global_position
	check(preload("res://scripts/permutation.gd").exchange(player, bot) and player.global_position == destination and bot.global_position == origin, "Permutation exchanges two valid raised island endpoints")
	check(preload("res://scripts/permutation.gd").exchange(player, bot), "Permutation returns fighters to their original islands")
	for ramp in basin.get("ramps"):
		var start: Vector2 = ramp.start
		var direction: Vector2 = ramp.direction
		var length: float = ramp.length
		player.global_position = Vector3(start.x, 1.35, start.y)
		for tick in range(85):
			var requested := Vector3(direction.x, 0, direction.y) * (length + 0.3) / 85
			player.velocity = TRAVERSAL.motion(player, requested) * 60
			player.move_and_slide()
			TRAVERSAL.snap(player)
		check(is_zero_approx(player.global_position.y), "actual player descends each ramp into the basin")
		for tick in range(85):
			var requested := -Vector3(direction.x, 0, direction.y) * (length + 0.3) / 85
			player.velocity = TRAVERSAL.motion(player, requested) * 60
			player.move_and_slide()
			TRAVERSAL.snap(player)
		check(is_equal_approx(player.global_position.y, 1.35), "actual player climbs back onto each island")
	check(not basin.call("segment_walkable", Vector3(0, 0, -5), Vector3(-4, 1.35, -5)), "vertical island faces cannot be climbed or dashed through")
	player.global_position = Vector3(0, 0, -5)
	check(not TRAVERSAL.attack_blocked(player), "dry basin permits attacks at low tide")
	var kits := get_nodes_in_group("repair_kits").filter(func(kit: Node): return kit.get_parent() == scene.get_node("CompactArenaStage"))
	check(kits.size() == 2 and kits[0].position.z > 6 and kits[1].position.z > 6 and is_zero_approx(kits[0].position.y), "exactly two real health boosts are placed in the lower basin")
	# Control collection and recharge explicitly so actual pickups are measured,
	# rather than accepting a pickup that might have happened on another frame.
	for kit in kits:
		kit.set_physics_process(false)
		kit.set_process(false)
	mechanisms.call("advance", 0.001)
	var maximum: float = player.call("get_max_health")
	player.call("take_damage", maximum * 0.8, "test", "tideglass-low-health")
	player.global_position = kits[0].global_position
	await physics_frame
	var low_healed: float = kits[0].call("try_collect", player)
	check(is_equal_approx(low_healed, maximum * 0.30), "dry basin keeps its ordinary 30 percent health pickup")
	check(float(kits[0].call("try_collect", player)) == 0.0, "basin reward cannot be collected twice")
	player.call("reset_combat_state")
	player.global_position = Vector3(0, 0, -5)
	var low: Vector3 = basin.get("barges")[0].body.position
	mechanisms.call("advance", 11.0)
	check(basin.get("phase") == "haute" and is_equal_approx(basin.get("water_level"), 0.9), "round time genuinely fills basin to high tide")
	check(TRAVERSAL.attack_blocked(player), "water blocks player attacks")
	check(basin.get("barges")[0].body.position.distance_to(low) > 2, "floating covers move in both height and horizontal position")
	var controls := player.get_node("ControlsComponent")
	check(int(player.call("_try_begin_weapon_action", "blaster")) == 0, "weapon ownership cannot be acquired under water")
	check(not bool(controls.call("request_module_command", "offensive")), "offensive casts are refused without consuming cooldown in water")
	player.call("apply_loadout", {"robot": "balanced", "weapon": "longshot", "offensive": "javelin", "defensive": "bio_injector", "mobility": "pyro_boots", "passive": "alternator"})
	player.call("_perform_longshot_attack")
	check(not player.get("_longshot_attack_busy"), "actual longshot refuses to prepare in water")
	var before_move := player.global_position
	player.set("_touch_move_vector", Vector2(0.7, 0))
	player.call("_update_movement", 1.0 / 60)
	check(player.global_position.distance_to(before_move) > 0.001, "water leaves ordinary movement enabled")
	player.set("_touch_move_vector", Vector2.ZERO)
	bot.global_position = Vector3(0, 0, -5)
	var controller := bot.get_node("TrainingBot")
	var equipment: Node = controller.get("_duel_equipment")
	var serial: int = equipment.get("_shot_serial")
	equipment.call("_fire", bot, player)
	check(int(equipment.get("_shot_serial")) == serial, "actual bot cannot fire in water")
	player.global_position = kits[1].global_position
	player.call("heal", maximum, "test")
	check(float(kits[1].call("try_collect", player)) == 0.0 and bool(kits[1].call("is_available")), "full-health fighter cannot waste a flooded reward")
	player.call("take_damage", maximum * 0.8, "test", "tideglass-health")
	await physics_frame
	var healed: float = kits[1].call("try_collect", player)
	check(is_equal_approx(healed, maximum * 0.30), "submerged health pickup remains separate from offensive sap")
	check(TRAVERSAL.attack_blocked(player), "taking submerged health does not enable attacks")
	player.global_position = Vector3(-7.25, 1.35, -7.5)
	kits[0].call("_process", 19.9)
	check(not bool(kits[0].call("is_available")), "basin reward stays unavailable until recharge completes")
	kits[0].call("_process", 0.11)
	check(bool(kits[0].call("is_available")), "ordinary health pickup returns after twenty seconds")
	check(not TRAVERSAL.attack_blocked(player), "dry island restores attack availability at high tide")
	player.call("_perform_longshot_attack")
	check(player.get("_longshot_attack_busy"), "longshot can prepare on an island")
	player.global_position = Vector3(0, 0, -5)
	controls.call("advance_input_time", 0.016)
	check(not player.get("_longshot_attack_busy"), "entering water cancels a shot already in preparation")
	var clock: float = basin.get("elapsed")
	paused = true
	mechanisms.call("advance", 2.0)
	check(is_equal_approx(basin.get("elapsed"), clock), "pausing freezes tide and cover movement")
	paused = false
	# Exercise the real navigation grid and StaticBody bot mover over the ramps.
	bot.global_position = Vector3(-8, 0, 8)
	player.global_position = Vector3(-7.25, 1.35, -7.5)
	var navigation = controller.get("_navigation")
	navigation.call("invalidate", true)
	var reached := false
	for tick in range(750):
		var direction: Vector3 = navigation.call("get_direction", bot, player.global_position, float(tick) / 60, 12.0)
		controller.set("_move_velocity", direction * 5)
		controller.call("_move_bot", bot, 1.0 / 60)
		if bot.global_position.y > 1.3 and bot.global_position.distance_to(player.global_position) < 1.8:
			reached = true
			break
	if not reached:
		print("BOT NAV: ", bot.global_position, " ", navigation.call("get_debug_state"))
	check(reached, "bot finds the access ramp and reaches a dry island")
	mechanisms.call("advance", 13.01)
	check(not TRAVERSAL.attack_blocked(player), "receding water removes the combat restriction")
	mechanisms.call("reset_round")
	check(is_equal_approx(basin.get("water_level"), -0.06) and not TRAVERSAL.attack_blocked(player), "round reset restores low tide and clears attack block")
	check(is_equal_approx(float(kits[0].get("heal_fraction")), 0.30) and is_equal_approx(float(kits[1].get("heal_fraction")), 0.30), "both ordinary health pickups retain their original strength")
	await test_sap()
	if DisplayServer.get_name() != "headless":
		await capture(flow)
	flow.call("_select_arena", "resonance")
	await process_frame
	check(TRAVERSAL.terrain(player) == null and is_zero_approx(player.global_position.y) and not TRAVERSAL.attack_blocked(player), "switching map clears tidal terrain and attack restriction")
	print("TIDEGLASS ARENA TEST: %s (%d failures; traversal, water combat, offensive sap, real damage, bot delivery, health, pause, reset, map switch)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func test_sap() -> void:
	var sap: Node3D = basin.get("sap")
	player.call("reset_combat_state")
	player.call("set_passive", "alternator")
	bot.call("reset_combat_state")
	bot.global_position = Vector3(7.25, 1.35, -7.5)
	player.global_position = Vector3.ZERO
	mechanisms.call("reset_round")
	check(not bool(sap.call("try_collect", player)), "countdown cannot award sap")
	mechanisms.call("start_round")
	player.global_position = Vector3(-7.25, 1.35, -7.5)
	mechanisms.call("advance", 11.0)
	player.global_position = Vector3.ZERO
	mechanisms.call("advance", 0.001)
	var carried: Dictionary = sap.call("status", player)
	var carrier_fx: Node3D = sap.get("_effects").get(player.get_instance_id())
	check(carrier_fx != null and carrier_fx.visible and carrier_fx.get_node("CarriedSeed").visible, "collecting sap creates a visible seed around the carrier")
	var seed_at: Vector3 = carrier_fx.get_node("CarriedSeed").position
	check(not carried.is_empty() and carried.phase == "carried", "healthy fighter automatically collects the contested sap in flooded basin")
	check(is_equal_approx(float(player.call("get_health")), float(player.call("get_max_health"))), "sap collection needs no injury or healing")
	check(TRAVERSAL.attack_blocked(player) and is_equal_approx(float(player.call("emit_passive_weapon").multiplier), 1.0), "carrying sap in water neither enables attacks nor grants early power")
	bot.global_position = Vector3.ZERO
	check(not bool(sap.call("try_collect", bot)), "same shared sap cannot be collected by the opponent too")
	bot.global_position = Vector3(7.25, 1.35, -7.5)
	paused = true
	mechanisms.call("advance", 3.0)
	check(carried == sap.call("status", player), "pause freezes sap transport window")
	check(seed_at == carrier_fx.get_node("CarriedSeed").position, "pause freezes the actual carried seed animation")
	paused = false
	mechanisms.call("advance", 2.0)
	check(float(sap.call("status", player).get("remaining", 0.0)) > 12.9, "trip through water uses the transport window instead of offensive duration")
	player.global_position = Vector3(0, 1.35, 5.5)
	await physics_frame
	mechanisms.call("advance", 1.0 / 60.0)
	var powered: Dictionary = sap.call("status", player)
	check(powered.get("phase") == "active" and float(powered.get("remaining", 0.0)) > 9.9, "reaching a raised island starts ten fresh seconds of power")
	check(carrier_fx.get_node("LivingSapFilaments").visible and carrier_fx.get_node("EmpoweredWeapon").visible and not carrier_fx.get_node("CarriedSeed").visible, "delivery replaces carried seed with body filaments and weapon energy")
	var attack: Dictionary = player.call("emit_passive_weapon")
	check(is_equal_approx(float(attack.multiplier), 1.35), "shared weapon context snapshots 35 percent sap bonus")
	var before: float = bot.call("get_health")
	player.call("passive_weapon_damage", bot, 100.0, "player", "sap:real-hit", attack)
	check(is_equal_approx(before - float(bot.call("get_health")), 135.0), "real hostile weapon hit applies 135 damage instead of 100")
	var runtime: PassiveState = player.get("passive_state")
	runtime.alternator_remaining = 3.0
	var combined: Dictionary = player.call("emit_passive_weapon")
	check(is_equal_approx(float(combined.multiplier), 1.35 * 1.30), "sap composes with Alternator without replacing or consuming its own duration")
	paused = true
	mechanisms.call("advance", 12.0)
	check(powered == sap.call("status", player), "pause freezes active sap duration")
	paused = false
	mechanisms.call("advance", 10.1)
	check(sap.call("status", player).is_empty() and is_equal_approx(float(player.call("emit_passive_weapon").multiplier), 1.0), "sap expires and later attacks return to normal damage")
	check(not carrier_fx.visible and carrier_fx.is_queued_for_deletion(), "expired power also removes its visual effect")
	before = bot.call("get_health")
	player.call("passive_weapon_damage", bot, 100.0, "player", "sap:late-projectile", attack)
	check(is_equal_approx(before - float(bot.call("get_health")), 135.0), "projectile already fired retains its snapshotted damage after buff expires")
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	player.global_position = Vector3.ZERO
	mechanisms.call("advance", 0.001)
	check(not bool(sap.call("try_collect", player)), "holding a charge never stacks a second pickup")
	player.global_position = Vector3(0, 1.35, 5.5)
	mechanisms.call("advance", 0.001)
	check(not sap.call("status", player).is_empty(), "low tide sap still requires delivery to an island")
	mechanisms.call("stop_round")
	check(sap.call("status", player).is_empty() and is_equal_approx(runtime.arena_weapon_multiplier, 1.0), "round end removes carried and active sap power")
	mechanisms.call("start_round")
	player.global_position = Vector3.ZERO
	mechanisms.call("advance", 0.001)
	sap.call("advance", 15.1)
	check(sap.call("status", player).is_empty(), "undelivered sap expires instead of being hoarded in the basin")
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	player.global_position = Vector3.ZERO
	mechanisms.call("advance", 0.001)
	player.call("take_damage", float(player.call("get_max_health")) * 2.0, "test", "sap:death")
	mechanisms.call("advance", 0.001)
	check(sap.call("status", player).is_empty() and is_equal_approx(runtime.arena_weapon_multiplier, 1.0), "death removes the carried reward")
	player.call("reset_combat_state")
	bot.call("reset_combat_state")
	player.global_position = Vector3(-7.25, 1.35, -7.5)
	bot.global_position = Vector3(7.25, 1.35, -7.5)
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	var controller := bot.get_node("TrainingBot")
	controller.set("_next_tactical_decision_at", 0.0)
	controller.set("_perception", {"bot_health_fraction": 1.0})
	controller.set("_has_last_observed_position", false)
	controller.set("_has_angle_destination", false)
	await physics_frame
	controller.get("_navigation").call("invalidate", true)
	var delivered := false
	for tick in range(900):
		controller.set("_elapsed", 30.0 + tick / 60.0)
		controller.call("_update_duel_decision", bot, player)
		controller.call("_update_duel_movement", bot, player.global_position, false, 1.0 / 60.0)
		mechanisms.call("advance", 1.0 / 60.0)
		if sap.call("status", bot).get("phase") == "active":
			delivered = true
			break
	if not delivered:
		print("SAP BOT: ", bot.global_position, " charge=", sap.call("status", bot), " goal=", sap.call("get_bot_destination", bot), " intent=", controller.get("_current_intent"), " nav=", controller.get("_navigation").call("get_debug_state"))
	check(delivered, "real healthy bot descends a ramp, contests sap and carries it onto an island")
	var bot_attack: Dictionary = bot.call("emit_passive_weapon")
	check(is_equal_approx(float(bot_attack.get("multiplier", 1.0)), 1.35), "bot receives the same offensive reward as the player")
	var bot_fx: Node3D = sap.get("_effects").get(bot.get_instance_id())
	bot.global_position = Vector3(40, 1.35, 0)
	sap.call("advance", 0.001)
	check(bot_fx != null and not bot_fx.visible, "enemy sap aura cannot reveal an actor beyond vision range")
	bot.global_position = player.global_position + Vector3(1.8, 0, 0)
	await physics_frame
	sap.call("advance", 0.001)
	check(bot_fx.visible, "visible opponent displays the same sap aura")
	mechanisms.call("reset_round")
	check(sap.call("status", bot).is_empty() and is_equal_approx(float(bot.call("emit_passive_weapon").get("multiplier", 1.0)), 1.0), "new round clears the bot reward as well")

func capture(flow: Node) -> void:
	root.get_node("FramePacing").visible = false
	var directory := ProjectSettings.globalize_path("res://captures/tideglass-engloutie")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		directory = args[0]
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join(".gdignore"), FileAccess.WRITE).close()
	player.call("heal", player.call("get_max_health"), "capture")
	for kit in get_nodes_in_group("repair_kits"):
		kit.call("reset_for_round", true)
	for label in scene.find_children("*", "Label3D", true, false):
		if label != basin.get("_status") and label.name != "SapReward":
			label.visible = false
	for readout in [player.get_node_or_null("WorldUIAnchor/PlayerHealthReadout"), bot.get_node_or_null("TargetHealthReadout")]:
		if readout != null:
			readout.hide()
	for child in scene.get_children():
		if child.name.begins_with("Damage") or child.name.begins_with("Floating"):
			child.queue_free()
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	var fog := scene.get_node_or_null("FogOfWar")
	if fog != null:
		fog.call("set_enabled", false)
	scene.set_process(false)
	scene.get_node("CameraRig").set_process(false)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 34, 27)
	camera.fov = 44
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.current = true
	player.global_position = Vector3(-7.25, 1.35, -7.5)
	bot.global_position = Vector3(7.25, 1.35, -7.5)
	for state in ["basse", "haute"]:
		mechanisms.call("reset_round")
		mechanisms.call("start_round")
		mechanisms.call("advance", 0.001)
		if state == "haute":
			player.global_position = Vector3(-8.125, 0, 6.75)
			mechanisms.call("advance", 11.0)
		for frame in range(15):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("maree-" + state + ".png"))
	# Production combat camera and HUD, with the player in the flooded basin.
	player.global_position = Vector3.ZERO
	mechanisms.call("advance", 0.001)
	mechanisms.call("advance", 0.001)
	var rig := scene.get_node("CameraRig")
	rig.call("set_target", player)
	rig.get_node("Camera3D").current = true
	for tick in range(120):
		rig.call("_process", 1.0 / 60.0)
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = true
	flow.set_process(true)
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("duel-camera.png"))
	player.global_position = Vector3(0, 1.35, 5.5)
	mechanisms.call("advance", 0.016)
	mechanisms.call("advance", 0.016)
	for tick in range(120):
		rig.call("_process", 1.0 / 60.0)
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("sap-active.png"))
	if args.has("vfx-loop"):
		var frames := directory.path_join("vfx-frames")
		DirAccess.make_dir_recursive_absolute(frames)
		for index in range(72):
			mechanisms.call("advance", 1.0 / 30.0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(frames.path_join("frame-%03d.png" % index))
	flow.set_process(false)
	# Capture the production solo selection view as well as the overhead layout.
	camera.queue_free()
	flow.call("_open_solo_setup")
	for readout in [player.get_node_or_null("WorldUIAnchor/PlayerHealthReadout"), bot.get_node_or_null("TargetHealthReadout")]:
		if readout != null:
			readout.hide()
	for child in scene.get_children():
		if child is CanvasLayer and child != flow:
			child.visible = false
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("selection.png"))
