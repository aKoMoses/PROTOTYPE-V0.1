extends SceneTree

const LIVE := preload("res://scripts/live_projectile.gd")
const LONGSHOT := preload("res://scripts/longshot_projectile.gd")

var failures: Array[String] = []
var scene: Node3D
var mechanisms: Node3D
var clock: Node3D
var player: CharacterBody3D
var bot: StaticBody3D
var capture_directory := ""

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_select_arena", "clockwork")
	flow.call("_start_duel")
	flow.set_process(false)
	player = scene.get_node("Player")
	bot = scene.get_node("TargetDummy")
	player.set_physics_process(false)
	player.set_process(false)
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.call("set_training_bot_enabled", false)
	mechanisms = scene.get_node("ArenaHazards")
	mechanisms.set_physics_process(false)
	clock = mechanisms.get("_clockwork")
	var command: StaticBody3D = clock.get("command")
	await physics_frame
	var before: Dictionary = mechanisms.call("get_snapshot")
	mechanisms.call("advance", 20.0)
	_check(before == mechanisms.call("get_snapshot"), "countdown freezes all mechanisms")
	_check(not bool(clock.call("request_sweep")), "countdown refuses command impacts")
	flow.call("_begin_live_round")
	bot.call("set_training_bot_enabled", false)
	_check(mechanisms.get("_fixtures").is_empty() and mechanisms.get("_boosts").is_empty() and mechanisms.get("_shutters").is_empty(), "old lanes, boosts and gates removed")
	_check((scene.get("_arena_blockers") as Array).has(clock.get("covers")[0]), "moving covers registered for navigation and minimap")
	player.global_position = Vector3(2.8, 0, 0)
	bot.global_position = Vector3(-2.8, 0, 0)
	await physics_frame
	var hp := float(player.call("get_health"))
	var start := player.global_position
	mechanisms.call("advance", 4.2)
	_check(clock.get("phase") == "ready" and (mechanisms.call("get_threats") as Array).is_empty(), "armed clock waits for an impact without a live threat")
	mechanisms.call("advance", 20.0)
	_check(clock.get("phase") == "ready" and int(clock.get("activations")) == 0 and player.global_position == start, "clock never starts a sweep automatically")
	paused = true
	_check(not bool(clock.call("request_sweep")), "pause refuses a command and does not queue it")
	paused = false
	var projectile := LIVE.new()
	scene.add_child(projectile)
	projectile.global_position = Vector3(0, 1.1, -2.5)
	projectile.configure(Vector3(0, 0, 1), 50.0, 6.0, 1 | 2 | 4 | 8, [])
	projectile.set_physics_process(false)
	projectile.call("_physics_process", 0.10)
	_check(int(clock.get("activations")) == 1, "physical blaster or shotgun projectile operates the spindle command")
	_check(clock.get("phase") == "warning" and clock.get("warning_sector").visible and not (mechanisms.call("get_threats") as Array).is_empty(), "warning shows sector and bot threats")
	for index in range(6):
		command.call("projectile_impact", command.global_position)
	_check(int(clock.get("activations")) == 1, "pellets cannot queue multiple sweeps or shorten the warning")
	_check(player.global_position == start and float(player.call("get_health")) == hp, "warning neither pushes nor damages")
	var frozen: Dictionary = mechanisms.call("get_snapshot")
	paused = true
	mechanisms.call("advance", 8.0)
	_check(frozen == mechanisms.call("get_snapshot"), "pause freezes arm, covers and cycle")
	paused = false
	mechanisms.call("advance", 2.95)
	_check(player.global_position.distance_to(start) > 1.0 and int(clock.get("pushes")) == 1, "sweep continuously carries actor on its path")
	_check(float(player.call("get_health")) == hp, "sweep causes no health damage")
	_check(bot.global_position == Vector3(-2.8, 0, 0), "opposite half remains safe")
	mechanisms.call("advance", 1.1)
	_check(int(clock.get("pushes")) == 1, "continuous contact counts as one affected actor")
	# The old west/east wall blocks this line; the north/south layout opens it.
	_check(not _ray(Vector3(-6, 1, 1.2), Vector3(6, 1, 1.2)).is_empty(), "initial cover layout blocks side firing line")
	player.global_position = Vector3(-7.5, 0, 6.875)
	bot.global_position = Vector3(7.5, 0, -6.875)
	await physics_frame
	mechanisms.call("advance", 3.1)
	await physics_frame
	_check(int(clock.get("cycles")) == 1 and is_equal_approx(float(clock.get("cover_angle")), PI * 0.5), "covers rotate exactly one quarter turn")
	_check(_ray(Vector3(-6, 1, 1.2), Vector3(6, 1, 1.2)).is_empty(), "rotated covers open previous firing line")
	_check(not _ray(Vector3(1.2, 1, -6), Vector3(1.2, 1, 6)).is_empty(), "rotated covers block new firing line")
	_check(not bool(clock.call("request_sweep")), "cover rotation and recharge reject premature commands")
	mechanisms.call("advance", 10.0)
	_check(clock.get("phase") == "ready" and int(clock.get("activations")) == 1, "clock rearms after rotation without starting another sweep")
	# Occupied rotation must wait, rather than crush or overlap a fighter.
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	clock.set("phase", "rotate")
	clock.set("remaining", 2.0)
	player.global_position = Vector3(4.4, 0, 0.8)
	await physics_frame
	mechanisms.call("advance", 0.4)
	_check(is_zero_approx(float(clock.get("cover_angle"))) and clock.get("phase") == "rotate", "occupied cover path waits safely")
	player.global_position = Vector3(-7.5, 0, 6.875)
	await physics_frame
	mechanisms.call("advance", 2.1)
	_check(int(clock.get("cycles")) == 1, "rotation resumes when fighter leaves")
	mechanisms.call("stop_round")
	before = mechanisms.call("get_snapshot")
	mechanisms.call("advance", 15.0)
	_check(before == mechanisms.call("get_snapshot") and is_zero_approx(float(clock.get("cover_angle"))), "stop freezes and restores initial geometry")
	# Check a push near a solid is collision-limited, never a teleport through it.
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	player.global_position = Vector3(3.4, 0, -2.5)
	await physics_frame
	clock.set("arm_angle", atan2(-2.5, 3.4))
	for frame in range(90):
		clock.call("_push_actors", 1.0 / 60.0)
	_check(player.global_position.z < -1.75, "push stops before solid cover")
	_check(float(player.call("get_health")) == hp, "collision-limited push still causes no damage")
	# Regression: one contact must keep moving the actor across successive
	# real physics frames, rather than spend a single impulse and ignore it.
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	clock.set("phase", "sweep")
	clock.set("remaining", 2.2)
	clock.set("sweep_start", -0.2)
	clock.set("arm_angle", -0.2)
	player.global_position = Vector3(2.8, 0, 0)
	bot.global_position = Vector3(-7.5, 0, -6.875)
	await physics_frame
	start = player.global_position
	mechanisms.call("advance", 1.0 / 60.0)
	var first_contact := player.global_position
	_check(first_contact.distance_to(start) > 0.01 and first_contact.distance_to(start) < 0.35, "first contact is a small continuous step, not an impulse")
	for frame in range(30):
		await physics_frame
		mechanisms.call("advance", 1.0 / 60.0)
	_check(player.global_position.distance_to(first_contact) > 1.0, "same actor keeps being pushed after first contact")
	_check(absf(Vector2(player.global_position.x, player.global_position.z).length() - 2.8) < 0.25, "robot follows sweep arc instead of being expelled radially")
	_check(float(player.call("get_health")) == hp, "sustained contact causes no damage")
	player.global_position = Vector3(-7.5, 0, 6.875)
	await physics_frame
	start = player.global_position
	mechanisms.call("advance", 0.2)
	_check(player.global_position == start, "push stops when robot leaves arm contact")
	await _test_commands()
	if not OS.get_cmdline_user_args().is_empty() and DisplayServer.get_name() != "headless":
		capture_directory = OS.get_cmdline_user_args()[0]
		await _capture(flow)
	for failure in failures:
		push_error("CLOCKWORK TEST: " + failure)
	print("CLOCKWORK TEST: %s (%d failures; physical command, telegraph, weapons, bot, non-damaging push, pause, real rotating solids, safe occupancy, lifecycle)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	scene.call("stop_duel")
	scene.call("set_arena_variant", "classic")
	await process_frame
	var residual := false
	for body in get_nodes_in_group("arena_solid"):
		if str(body.name).begins_with("PivotCover") or str(body.name) == "ClockSpindle":
			residual = true
	_check(not residual, "map change removes moving solids")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_commands() -> void:
	var command: StaticBody3D = clock.get("command")
	player.global_position = Vector3(2.8, 0, 0)
	bot.global_position = Vector3(-6, 0, -6)
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	mechanisms.call("advance", 6.05)
	await physics_frame
	_check(mechanisms.call("get_bot_control_target", bot, Vector3.INF, "hard") == null, "bot cannot trigger against an unknown opponent")
	_check(mechanisms.call("get_bot_control_target", bot, player.global_position, "hard") == command, "bot selects command when observed opponent is in the next sweep and bot is safe")
	_check(mechanisms.call("get_bot_control_target", bot, Vector3(-2.8, 0, 0), "hard") == null, "bot ignores command when observed opponent is on the safe half")
	_check(mechanisms.call("get_bot_control_target", bot, player.global_position, "easy") == null, "easy bot gets fewer trigger opportunities")
	var longshot := LONGSHOT.new()
	scene.add_child(longshot)
	longshot.global_position = Vector3(0, 1.1, -2.5)
	longshot.configure(Vector3(0, 0, 1), 50.0, 6.0, 1 | 2 | 4 | 8, [], 0.15, false)
	longshot.set_physics_process(false)
	longshot.call("_physics_process", 0.10)
	_check(int(clock.get("activations")) == 1, "physical Longshot volume triggers the same command")
	await process_frame
	# The real melee controller must discover and strike this non-combat target.
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	mechanisms.call("advance", 4.1)
	player.call("apply_loadout", {"robot": "balanced", "weapon": "mekatana", "offensive": "javelin", "defensive": "bio_injector", "mobility": "pyro_boots", "passive": "alternator"})
	player.global_position = Vector3(0, 0, -2.4)
	player.set("aim_direction", Vector3(0, 0, 1))
	await physics_frame
	player.call("_perform_mekatana_attack")
	for tick in range(60):
		player.call("_update_mekatana_attack", 1.0 / 60.0)
		if int(clock.get("activations")) > 0:
			break
	_check(int(clock.get("activations")) == 1, "actual Mekatana cleave can activate the command")
	player.call("_cancel_mekatana_attack")
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	player.global_position = Vector3(-7.5, 0, 6.875)
	bot.global_position = Vector3(7.5, 0, -6.875)
	mechanisms.call("advance", 4.1)
	command.call("take_damage", 100.0, "player", "clock:one-cleave")
	mechanisms.call("advance", 10.0)
	command.call("take_damage", 100.0, "player", "clock:one-cleave")
	_check(clock.get("phase") == "ready" and int(clock.get("activations")) == 1, "late repeated hit id cannot start a second cycle after rearming")
	command.call("take_damage", 100.0, "player", "clock:next-cleave")
	_check(int(clock.get("activations")) == 2, "new independent hit can trigger the next sweep")
	var controller := bot.get_node("TrainingBot")
	controller.set_physics_process(false)
	var equipment := controller.get_node("DuelEquipment")
	for weapon in ["blaster", "shotgun", "longshot"]:
		mechanisms.call("reset_round")
		mechanisms.call("start_round")
		mechanisms.call("advance", 6.05)
		player.global_position = Vector3(2.8, 0, 0)
		bot.global_position = Vector3(-3, 0, -3)
		bot.call("set_duel_profile", weapon)
		equipment.set("next_attack_at", 0.0)
		var perception := {"arena_control_target": command, "line_of_fire": false, "velocity": Vector3.ZERO}
		var tuning := {"aim_error_degrees": 0.0, "position_quality": 1.0, "module_skill": 0.0}
		await physics_frame
		for frame in range(180):
			equipment.call("tick", 1.0 / 60.0, 10.0 + frame / 60.0, false, player.global_position, bot, player, controller, perception, tuning)
			await physics_frame
			if int(clock.get("activations")) > 0:
				break
		_check(int(clock.get("activations")) == 1, "real bot " + weapon + " fires its normal projectile to trigger the clock")
		equipment.call("cancel_action", "clock command test ended")
		for child in scene.get_children():
			if child.get_script() != null and child.get_script().resource_path in ["res://scripts/live_projectile.gd", "res://scripts/longshot_projectile.gd"]:
				child.queue_free()
		await process_frame
	# Run the complete brain without injecting an arena-control perception.
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	mechanisms.call("advance", 6.05)
	player.global_position = Vector3(2.8, 0, 0)
	bot.global_position = Vector3(-3, 0, -3)
	bot.call("set_duel_profile", "blaster")
	controller.call("reset_clock")
	controller.call("set_difficulty_profile", "hard")
	controller.set("training_stationary", true)
	controller.call("set_enabled", true)
	controller.set_physics_process(false)
	equipment.set("next_attack_at", 0.0)
	scene.get_node("FogOfWar").call("set_enabled", false)
	await physics_frame
	for frame in range(240):
		controller.call("_physics_process", 1.0 / 60.0)
		await physics_frame
		if int(clock.get("activations")) > 0:
			break
	_check(int(clock.get("activations")) == 1, "complete bot brain observes opponent, selects command and triggers a physical shot")
	controller.call("set_enabled", false)
	controller.set("training_stationary", false)
	mechanisms.call("set_enabled", false)
	_check(command.collision_layer == 0 and not bool(clock.call("request_sweep")), "disabled arena removes command collisions and refuses impacts")
	mechanisms.call("set_enabled", true)

func _capture(flow: Node) -> void:
	DirAccess.make_dir_recursive_absolute(capture_directory)
	scene.set("_menu_showcase_active", false)
	scene.set_process(false)
	scene.get_node("CompactArenaStage").set_process(false)
	scene.get_node("CameraRig").set_process(false)
	scene.get_node("FogOfWar").call("set_enabled", false)
	root.get_node("FramePacing").visible = false
	for node in scene.get_children():
		if node is CanvasLayer:
			node.visible = false
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 28, 21)
	camera.fov = 40
	camera.look_at(Vector3(0, 0, -0.5))
	camera.current = true
	player.call("reset_combat_state")
	player.call("apply_loadout", {"robot": "balanced", "weapon": "blaster", "offensive": "javelin", "defensive": "bio_injector", "mobility": "pyro_boots", "passive": "alternator"})
	player.get("_attack_label").text = ""
	player.global_position = Vector3(2.8, 0, 0)
	bot.global_position = Vector3(-7, 0, -7)
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	for sample in [{"name": "clockwork-ready", "delta": 4.6}, {"name": "clockwork-warning", "delta": 0.6}, {"name": "clockwork-sweep", "delta": 2.4}, {"name": "clockwork-rotated", "delta": 4.3}]:
		if sample.name == "clockwork-warning":
			clock.get("command").call("projectile_impact", Vector3.UP)
		mechanisms.call("advance", sample.delta)
		player.call("_update_world_ui_anchor")
		for frame in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join(sample.name + ".png"))
	if OS.get_cmdline_user_args().has("loop"):
		var frames := capture_directory.path_join("frames")
		DirAccess.make_dir_recursive_absolute(frames)
		mechanisms.call("reset_round")
		mechanisms.call("start_round")
		mechanisms.call("advance", 4.1)
		player.global_position = Vector3(2.8, 0, 0)
		bot.global_position = Vector3(-7, 0, -7)
		for index in range(200):
			if index == 24:
				clock.get("command").call("projectile_impact", Vector3.UP)
			mechanisms.call("advance", 0.05)
			player.call("_update_world_ui_anchor")
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(frames.path_join("frame-%03d.png" % index))
