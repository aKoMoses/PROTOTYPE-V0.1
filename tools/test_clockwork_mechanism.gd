extends SceneTree

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
	await physics_frame
	var before: Dictionary = mechanisms.call("get_snapshot")
	mechanisms.call("advance", 20.0)
	_check(before == mechanisms.call("get_snapshot"), "countdown freezes all mechanisms")
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
	_check(clock.get("phase") == "warning" and clock.get("warning_sector").visible and not (mechanisms.call("get_threats") as Array).is_empty(), "warning shows sector and bot threats")
	_check(player.global_position == start and float(player.call("get_health")) == hp, "warning neither pushes nor damages")
	var frozen: Dictionary = mechanisms.call("get_snapshot")
	paused = true
	mechanisms.call("advance", 8.0)
	_check(frozen == mechanisms.call("get_snapshot"), "pause freezes arm, covers and cycle")
	paused = false
	mechanisms.call("advance", 2.75)
	_check(player.global_position.distance_to(start) > 1.0 and int(clock.get("pushes")) == 1, "sweep continuously carries actor on its path")
	_check(float(player.call("get_health")) == hp, "sweep causes no health damage")
	_check(bot.global_position == Vector3(-2.8, 0, 0), "opposite half remains safe")
	mechanisms.call("advance", 1.1)
	_check(int(clock.get("pushes")) == 1, "continuous contact counts as one affected actor")
	# The old west/east wall blocks this line; the north/south layout opens it.
	_check(not _ray(Vector3(-6, 1, 0.8), Vector3(6, 1, 0.8)).is_empty(), "initial cover layout blocks side firing line")
	player.global_position = Vector3(-7.5, 0, 6.875)
	bot.global_position = Vector3(7.5, 0, -6.875)
	await physics_frame
	mechanisms.call("advance", 3.1)
	await physics_frame
	_check(int(clock.get("cycles")) == 1 and is_equal_approx(float(clock.get("cover_angle")), PI * 0.5), "covers rotate exactly one quarter turn")
	_check(_ray(Vector3(-6, 1, 0.8), Vector3(6, 1, 0.8)).is_empty(), "rotated covers open previous firing line")
	_check(not _ray(Vector3(0.8, 1, -6), Vector3(0.8, 1, 6)).is_empty(), "rotated covers block new firing line")
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
	if not OS.get_cmdline_user_args().is_empty() and DisplayServer.get_name() != "headless":
		capture_directory = OS.get_cmdline_user_args()[0]
		await _capture(flow)
	for failure in failures:
		push_error("CLOCKWORK TEST: " + failure)
	print("CLOCKWORK TEST: %s (%d failures; warning, non-damaging push, pause, real rotating solids, safe occupancy, lifecycle)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
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

func _capture(flow: Node) -> void:
	DirAccess.make_dir_recursive_absolute(capture_directory)
	scene.set("_menu_showcase_active", false)
	scene.set_process(false)
	scene.get_node("CompactArenaStage").set_process(false)
	scene.get_node("CameraRig").set_process(false)
	scene.get_node("FogOfWar").call("set_enabled", false)
	for node in scene.get_children():
		if node is CanvasLayer:
			node.visible = false
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 34, 26)
	camera.fov = 40
	camera.look_at(Vector3(0, 0, -0.5))
	camera.current = true
	player.global_position = Vector3(-7.5, 0, 6.875)
	bot.global_position = Vector3(7.5, 0, -6.875)
	mechanisms.call("reset_round")
	mechanisms.call("start_round")
	for sample in [{"name": "clockwork-warning", "delta": 4.6}, {"name": "clockwork-sweep", "delta": 2.1}, {"name": "clockwork-rotated", "delta": 4.5}]:
		mechanisms.call("advance", sample.delta)
		for frame in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join(sample.name + ".png"))
