extends SceneTree

## Runs the real duel flow, player input, projectiles and production bot for six
## seconds. Also verifies that the new presentation adds no physics/navigation
## objects and that the yard meshes/particle envelopes stay outside play.
const STEPS := 360
const PLAY_LIMIT := 27.8
var _failures: Array[String] = []
var _projectile_nodes := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(20260930)
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var presentation := scene.get_node_or_null("ArenaPresentation")
	_check(presentation != null, "visual presentation is missing")
	if presentation != null:
		_validate_presentation(presentation)
	var ground := scene.get_node_or_null("Ground") as MeshInstance3D
	_check(ground != null and ground.mesh is PlaneMesh, "movement ground mesh is missing")
	if ground != null and ground.mesh is PlaneMesh:
		_check((ground.mesh as PlaneMesh).size.is_equal_approx(Vector2(60.0, 60.0)), "ground footprint changed")
		_check(ground.global_position.is_equal_approx(Vector3.ZERO), "ground no longer lies at movement height")
	var flow := scene.get_node("Interface")
	scene.call("set_bot_build_seed", 42)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player") as CharacterBody3D
	var target := scene.get_node("TargetDummy") as Node3D
	var bot := target.get_node("TrainingBot")
	player.call("set_weapon", "blaster")
	player.call("clear_touch_inputs")
	player.global_position = Vector3(0.0, 0.0, 2.0)
	target.global_position = Vector3(3.5, 0.0, -2.0)
	target.call("set_training_bot_enabled", true)
	var player_started := player.global_position
	var target_started := target.global_position
	var previous_player := player_started
	var previous_target := target_started
	var player_distance := 0.0
	var bot_distance := 0.0
	var grounded := true
	var finite_and_bounded := true
	var perceived := false
	var seen_projectiles := {}
	var initial_shot_token := int(player.get("_blaster_attack_token"))
	var initial_health := float(player.call("get_health"))
	var initial_target_health := float(target.call("get_health"))
	var initial_bot_elapsed := float(bot.get("_elapsed"))
	node_added.connect(_on_node_added)
	var started := Time.get_ticks_msec()
	for step in range(STEPS):
		# Gentle left/right movement in the open centre corridor, using the same
		# touch API as Android. Short charge/release cycles use the normal gate.
		player.call("set_touch_move_vector", Vector2(0.45 if (step / 45) % 2 == 0 else -0.45, 0.0))
		var direction := target.global_position - player.global_position
		direction.y = 0.0
		player.call("set_touch_aim_vector", Vector2(direction.x, direction.z).normalized())
		player.call("set_touch_attack_held", step % 42 < 24)
		await physics_frame
		player_distance += previous_player.distance_to(player.global_position)
		bot_distance += previous_target.distance_to(target.global_position)
		previous_player = player.global_position
		previous_target = target.global_position
		grounded = grounded and absf(player.global_position.y) < 0.03 and absf(target.global_position.y) < 0.03
		finite_and_bounded = finite_and_bounded and player.global_position.is_finite() and target.global_position.is_finite() and maxf(absf(player.position.x), absf(player.position.z)) < PLAY_LIMIT and maxf(absf(target.position.x), absf(target.position.z)) < PLAY_LIMIT
		var diagnostic: Dictionary = bot.call("get_diagnostic_snapshot")
		perceived = perceived or bool(diagnostic.get("target_visible", false)) or bool(diagnostic.get("target_known", false))
		for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
			seen_projectiles[projectile.get_instance_id()] = true
		# Optional rendered snapshots exercise the actual moving combat camera,
		# fog of war and live effects; the headless gameplay assertions stay identical.
		if step in [120, 240, 359] and DisplayServer.get_name() != "headless":
			var capture_args := OS.get_cmdline_user_args()
			if capture_args.size() > 1:
				await RenderingServer.frame_post_draw
				var path := capture_args[1].path_join("arena-live-frame-%d.png" % step)
				_check(root.get_texture().get_image().save_png(path) == OK, "live frame capture failed")
	player.call("clear_touch_inputs")
	node_added.disconnect(_on_node_added)
	var shots := int(player.get("_blaster_attack_token")) - initial_shot_token
	var bot_elapsed := float(bot.get("_elapsed")) - initial_bot_elapsed
	_check(player_distance > 2.0, "live touch movement did not traverse the arena")
	_check(bot_distance > 0.5, "production bot did not navigate during live combat")
	_check(shots >= 2, "normal attack input did not produce multiple blaster shots")
	_check(_projectile_nodes > 0 or not seen_projectiles.is_empty(), "no real projectile nodes were observed")
	_check(bot_elapsed > 4.0 and perceived, "bot simulation/perception did not execute")
	_check(grounded, "actor height changed during movement")
	_check(finite_and_bounded, "actor escaped the arena or produced invalid coordinates")
	_check(not bool(player.call("is_real_dead")) and not bool(target.call("is_real_dead")), "smoke encounter ended before completing movement coverage")
	var report := {
		"result": "PASS" if _failures.is_empty() else "FAIL",
		"simulation_seconds": float(STEPS) / Engine.physics_ticks_per_second,
		"wall_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"input_api": ["set_touch_move_vector", "set_touch_aim_vector", "set_touch_attack_held"],
		"player_distance": player_distance,
		"bot_distance": bot_distance,
		"player_shots": shots,
		"projectile_nodes_created": _projectile_nodes,
		"projectiles_sampled": seen_projectiles.size(),
		"bot_active_seconds": bot_elapsed,
		"bot_perceived_player": perceived,
		"player_damage": initial_health - float(player.call("get_health")),
		"target_damage": initial_target_health - float(target.call("get_health")),
		"actors_grounded": grounded,
		"actors_finite_and_bounded": finite_and_bounded,
		"failures": _failures,
	}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		else:
			_check(false, "cannot write smoke report")
	print("ARENA ART LIVE COMBAT: %s" % JSON.stringify(report))
	for failure in _failures:
		push_error("ARENA ART LIVE COMBAT: %s" % failure)
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.1).timeout
	quit(0 if _failures.is_empty() else 1)


func _validate_presentation(presentation: Node) -> void:
	var yard := presentation.get_node_or_null("SalvageYard")
	_check(yard != null, "authored exterior yard is missing")
	var stack: Array[Node] = [presentation]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_check(not node is CollisionObject3D and not node is CollisionShape3D and not node is NavigationRegion3D and not node is NavigationObstacle3D, "%s adds gameplay physics/navigation" % node.name)
		if yard != null and (node == yard or yard.is_ancestor_of(node)):
			if node is MeshInstance3D and node.mesh != null:
				var bounds: AABB = node.global_transform * node.mesh.get_aabb()
				_check(not _intrudes_play(bounds), "%s mesh bounds enter the playable square" % node.name)
			if node is GPUParticles3D:
				var bounds: AABB = node.global_transform * node.visibility_aabb
				_check(not _intrudes_play(bounds), "%s particle envelope enters the playable square" % node.name)
		for child in node.get_children():
			stack.append(child)


func _intrudes_play(bounds: AABB) -> bool:
	return bounds.position.x < PLAY_LIMIT and bounds.end.x > -PLAY_LIMIT and bounds.position.z < PLAY_LIMIT and bounds.end.z > -PLAY_LIMIT


func _on_node_added(node: Node) -> void:
	if node is Node3D and "Projectile" in str(node.name):
		_projectile_nodes += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
