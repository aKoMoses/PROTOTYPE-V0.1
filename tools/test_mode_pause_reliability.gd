extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/survival.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	scene._choose_weapon("blaster")
	scene._begin_wave_combat()
	var player: Node3D = scene.player
	var target: Node3D = scene.get_training_targets()[0]
	for enemy in scene.get_training_targets():
		enemy.set_training_bot_enabled(false)
	target.apply_javelin_mark(4.0, "player")
	player._javelin_mark_target = target
	player._blaster_next_attack_ready_at = Time.get_ticks_msec() / 1000.0 + 1.0
	var before_mark: float = target.get_javelin_mark_remaining()
	var before_cadence: float = player._blaster_next_attack_ready_at - Time.get_ticks_msec() / 1000.0
	var sound := root.get_node("GameSfx")
	sound.clear()
	sound.play_event("pyro_dash")
	scene._pause_run()
	_check(sound._players.pyro_dash.stream_paused, "pause Survie suspend les sons de combat en cours")
	await create_timer(0.35).timeout
	scene._resume_run()
	_check(not sound._players.pyro_dash.stream_paused, "reprise Survie reprend les sons suspendus")
	var after_mark: float = target.get_javelin_mark_remaining()
	var after_cadence: float = player._blaster_next_attack_ready_at - Time.get_ticks_msec() / 1000.0
	_check(absf(before_mark - after_mark) < 0.035, "pause Survie conserve la durée de marque Javelin")
	_check(absf(before_cadence - after_cadence) < 0.035, "pause Survie conserve la cadence restante du Blaster")
	current_scene = null
	scene.queue_free()
	await process_frame
	var training := load("res://scenes/training_ground.tscn").instantiate() as Node3D
	root.add_child(training)
	current_scene = training
	await physics_frame
	sound.clear()
	sound.play_event("pyro_dash")
	training._toggle_menu()
	_check(sound._players.pyro_dash.stream_paused, "menu Training suspend les sons de combat")
	training._toggle_menu()
	_check(not sound._players.pyro_dash.stream_paused, "retour Training reprend les sons de combat")
	training._toggle_menu()
	training._reset_trial()
	await process_frame
	_check(sound._paused and not sound._players.pyro_dash.playing, "reset depuis menu retire les anciennes voix et reste suspendu")
	paused = false
	sound.clear()
	current_scene = null
	training.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	for failure in failures:
		push_error(failure)
	print("MODE PAUSE RELIABILITY TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
