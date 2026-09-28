extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("_choose_weapon", "blaster")
	await process_frame
	_check_stage(scene, 0, "res://son-musique/musiques/survie_early_loop.wav")

	# Reward choices pause combat while their quieter bed remains audible.
	scene.call("_enter_reward_music")
	paused = true
	await create_timer(0.9).timeout
	var reward := scene.get("_reward_music") as AudioStreamPlayer
	_check(reward.playing and reward.stream != null, "respiration active pendant le choix")
	_check(reward.volume_db > -25.0 and reward.volume_db < -23.0, "respiration au niveau prévu")
	paused = false
	scene.call("_leave_reward_music")
	scene.call("_play_music_for_wave", 5)
	_check_stage(scene, 1, "res://son-musique/musiques/la_forge_semballe_loop.wav")
	await create_timer(1.4).timeout
	_check(not (scene.get("_other_music") as AudioStreamPlayer).playing, "ancienne variation arrêtée après transition")
	_check(not reward.playing, "respiration arrêtée après le choix")
	_check(absf((scene.get("_music") as AudioStreamPlayer).volume_db + 17.0) < 0.1, "thème central au bon niveau")
	var center := scene.get("_music") as AudioStreamPlayer
	center.seek(59.8)
	await create_timer(0.6).timeout
	var loop_position := center.get_playback_position()
	_check(center.playing and loop_position >= 20.0 and loop_position < 21.5, "boucle repart après l'introduction")

	scene.call("_enter_reward_music")
	paused = true
	await create_timer(0.9).timeout
	paused = false
	scene.call("_leave_reward_music")
	scene.call("_play_music_for_wave", 9)
	_check_stage(scene, 2, "res://son-musique/musiques/survie_late_loop.wav")
	await create_timer(1.4).timeout
	_check(absf((scene.get("_music") as AudioStreamPlayer).volume_db + 15.5) < 0.1, "variation finale au bon niveau")

	scene.set("_state", "combat")
	scene.call("_pause_run")
	_check(paused and (scene.get("_music") as AudioStreamPlayer).stream_paused, "musique suspendue avec la pause")
	scene.call("_resume_run")
	_check(not paused and not (scene.get("_music") as AudioStreamPlayer).stream_paused, "musique reprise avec le combat")
	scene.call("_stop_all_music")
	_check(not (scene.get("_music") as AudioStreamPlayer).playing and not reward.playing, "musiques arrêtées au résultat")
	current_scene = null
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("SURVIVAL MUSIC TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_stage(scene: Node, expected_stage: int, expected_path: String) -> void:
	var music := scene.get("_music") as AudioStreamPlayer
	_check(int(scene.get("_music_stage")) == expected_stage, "étape musicale %d" % expected_stage)
	_check(music.stream != null and music.stream.resource_path == expected_path and music.playing, "piste %d active" % expected_stage)
	if music.stream is AudioStreamWAV:
		var wav := music.stream as AudioStreamWAV
		_check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_begin == 20 * wav.mix_rate and wav.loop_end == 60 * wav.mix_rate, "boucle de piste %d" % expected_stage)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
