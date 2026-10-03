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
	var kits := get_nodes_in_group("repair_kits").filter(func(kit: Node): return kit.get_parent() == scene.get_node("CompactArenaStage"))
	check(kits.size() == 2 and kits[0].position.z > 6 and kits[1].position.z > 6 and is_zero_approx(kits[0].position.y), "exactly two real health boosts are placed in the lower basin")
	player.call("take_damage", 150.0, "test", "tideglass-health")
	player.global_position = kits[0].global_position
	await physics_frame
	var healed: float = kits[0].call("try_collect", player)
	check(healed > 0.0 or not bool(kits[0].call("is_available")), "injured player can actually collect a submerged health boost")
	check(TRAVERSAL.attack_blocked(player), "taking submerged health does not enable attacks")
	player.global_position = Vector3(-7.25, 1.35, -7.5)
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
	mechanisms.call("reset_round")
	check(is_equal_approx(basin.get("water_level"), -0.06) and not TRAVERSAL.attack_blocked(player), "round reset restores low tide and clears attack block")
	if DisplayServer.get_name() != "headless":
		await capture(flow)
	flow.call("_select_arena", "resonance")
	await process_frame
	check(TRAVERSAL.terrain(player) == null and is_zero_approx(player.global_position.y) and not TRAVERSAL.attack_blocked(player), "switching map clears tidal terrain and attack restriction")
	print("TIDEGLASS ARENA TEST: %s (%d failures; traversal, water combat, bot, health, cover, pause, reset, map switch)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(flow: Node) -> void:
	var directory := ProjectSettings.globalize_path("res://captures/tideglass-engloutie")
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join(".gdignore"), FileAccess.WRITE).close()
	for kit in get_nodes_in_group("repair_kits"):
		kit.call("reset_for_round", false)
	for label in scene.find_children("*", "Label3D", true, false):
		if label != basin.get("_status"):
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
		if state == "haute":
			player.global_position = Vector3(-8.125, 0, 6.75)
			mechanisms.call("advance", 11.0)
		for frame in range(15):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("maree-" + state + ".png"))
	# Production combat camera and HUD, with the player in the flooded basin.
	var rig := scene.get_node("CameraRig")
	rig.call("set_target", player)
	rig.get_node("Camera3D").current = true
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = true
	flow.set_process(true)
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("duel-camera.png"))
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
