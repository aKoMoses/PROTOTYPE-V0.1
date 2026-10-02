extends SceneTree
var failures: Array[String] = []
var output := "C:/Users/BOTTEROOOW/.codex/visualizations/2026/09/30/01a0f348-336a-71d1-ad00-fc2ee371ec86"
func _initialize() -> void:
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player: CharacterBody3D = scene.get("player")
	var gate: CollisionShape3D = scene.get_node("FactoryGate/GateCollision")
	check(not gate.disabled, "porte initialement fermee")
	scene.call("_choose_weapon", "blaster")
	scene.call("_clear_enemies")
	scene.set("wave", 6)
	scene.set("_state", "reward")
	var progression: SurvivalProgression = scene.get("progression")
	# Build the real preceding rewards before choosing the sixth one.
	for wave in range(1, 6):
		progression.apply_reward(wave, progression.reward_choices(wave)[0])
	player.call("configure_survival_build", progression.build())
	player.combat_state.health = 400
	var actor_id := player.get_instance_id()
	var stats = scene.get("stats")
	stats.kills = 26
	stats.damage["blaster"] = 1234
	scene.get("_reward_overlay").visible = false
	await capture(scene, Vector3(-5, 0, -8), "survie-casse.png")
	await capture(scene, Vector3(18, 0, 0), "survie-porte-fermee.png")
	var choice: Dictionary = progression.reward_choices(6)[0]
	scene.call("_choose_reward", choice)
	var build := progression.build().duplicate(true)
	var health: float = player.call("get_health")
	check(is_equal_approx(health, 500), "soin habituel vague 6")
	await create_timer(1.3).timeout
	check(gate.disabled and scene.get("wave") == 6, "porte ouverte et vague 7 en attente")
	check(scene.call("get_training_targets").is_empty(), "passage sans ennemis")
	scene.call("_pause_run")
	scene.call("_resume_run")
	check(scene.get("_state") == "transition", "pause preserve la transition")
	await capture(scene, Vector3(27, 0, 0), "survie-portail.png")
	player.position = Vector3(20, 0, 0)
	player.velocity = Vector3.ZERO
	# Cross using the player's physics body, including doorway collisions.
	for frame in range(120):
		player.velocity = Vector3(8, 0, 0)
		player.move_and_slide()
		await physics_frame
		if scene.get("wave") == 7:
			break
	check(scene.get("wave") == 7 and scene.get("arena_center") == Vector3(54, 0, 0), "traversee physique lance la vague 7")
	check(player.get_instance_id() == actor_id and progression.build() == build, "personnage et build conserves")
	check(is_equal_approx(float(player.call("get_health")), health) and stats.kills == 26 and stats.damage.get("blaster") == 1234, "PV et statistiques conserves")
	check(not gate.disabled, "porte refermee derriere le joueur")
	for point in scene.get("_spawn_positions") + scene.get("_reinforcement_positions"):
		check(point.x > 31 and point.x < 77, "apparition dans usine")
	scene.call("_begin_wave_combat")
	scene.call("_spawn_reinforcements")
	await physics_frame
	var enemies: Array = scene.call("get_training_targets")
	for enemy in enemies:
		var bot: Node = enemy.get_node("TrainingBot")
		check(bot.get("survival_arena_center") == Vector3(54, 0, 0), "limites bots usine")
		enemy.call("set_training_bot_enabled", false)
	var bot: Node = enemies[0].get_node("TrainingBot")
	enemies[0].position = Vector3(74, 0, 0)
	bot.set("_move_velocity", Vector3(18, 0, 0))
	bot.call("_move_bot", enemies[0], 0.3)
	check(enemies[0].position.x <= 75.01 and enemies[0].position.x > 54, "bot borne dans la seconde zone")
	enemies[0].position = Vector3(54, 0, 3)
	player.survival_evolution_effects.call("_push", enemies[0], Vector3(53, 0, 3), 2.0)
	check(enemies[0].position.x > 54, "repoussement evolue reste dans usine")
	check(player.survival_evolution_effects.call("_landing_clear", Vector3(54,0,3)), "javelin evolue valide dans usine")
	check(player.call("_magnetic_placement_valid", Vector3(54,0,0), Vector3(54,0,3)), "module valide dans usine")
	scene.set("wave", 8)
	scene.call("_create_repair")
	check(scene.get("_repair").position.x > 31, "reparation dans usine")
	scene.set("wave", 7)
	await capture(scene, Vector3(54, 0, -5), "survie-usine.png")
	player.position = Vector3(54, 0, 0)
	player.set_gameplay_enabled(true)
	enemies[1].position = Vector3(54, 0, -4)
	await physics_frame
	var target_health: float = enemies[1].call("get_health")
	player.set("_blaster_next_attack_ready_at", -1.0)
	player.call("_fire_blaster_projectile", 50.0, 0.0, Vector3.FORWARD)
	await create_timer(0.5).timeout
	check(float(enemies[1].call("get_health")) < target_health, "tir reel atteint ennemi dans usine")
	paused = false
	scene.queue_free()
	await process_frame
	var fresh: Node3D = load("res://scenes/survival.tscn").instantiate()
	root.add_child(fresh)
	current_scene = fresh
	await physics_frame
	check(fresh.get("arena_center") == Vector3.ZERO and not fresh.get_node("FactoryGate/GateCollision").disabled, "nouvelle partie casse et porte fermee")
	fresh.queue_free()
	await process_frame
	if failures.is_empty():
		print("SURVIVAL ZONES: PASS")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(value: bool, description: String) -> void:
	if not value:
		failures.append(description)
func capture(scene: Node3D, at: Vector3, filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player: Node3D = scene.get("player")
	player.position = at
	scene.get_node("CameraRig").call("set_target", player)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + filename)
