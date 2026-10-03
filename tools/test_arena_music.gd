extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const MUSIC := preload("res://scripts/arena_music.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var existed := FileAccess.file_exists(LOADOUT.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH) if existed else PackedByteArray()
	var library_existed := FileAccess.file_exists(LIBRARY.SAVE_PATH)
	var library_saved := FileAccess.get_file_as_bytes(LIBRARY.SAVE_PATH) if library_existed else PackedByteArray()
	var library := LIBRARY.with_build(LIBRARY.load_local(), "", "TEST MUSIQUE", LOADOUT.defaults())
	LIBRARY.save_local(library)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var music: Node = flow.get("_arena_music")
	var match_player: AudioStreamPlayer = flow.get("_match_music")
	flow.set_process(false) # Drive actual transitions without waiting for the full intro.
	for arena in ["heliostat", "tideglass", "clockwork"]:
		flow.call("_select_arena", arena)
		flow.call("_open_solo_setup")
		await create_timer(0.5).timeout
		var selection: AudioStreamPlayer = music.get("_players")[music.get("_active_player")]
		assert(selection.playing and selection.stream.resource_path == MUSIC.TRACKS[arena].selection)
		assert(not (flow.get("_menu_music") as AudioStreamPlayer).playing)
		assert(not match_player.playing)
		assert(selection.stream.loop_begin == int(0.12 * selection.stream.mix_rate))
		selection.seek(7.0)
		await create_timer(0.10).timeout
		var clock := selection.get_playback_position()
		flow.call("_launch_solo")
		await create_timer(0.10).timeout
		assert(flow.call("get_round_phase_name") == "COUNTDOWN")
		assert(not match_player.playing)
		assert(music.get("_players")[music.get("_active_player")] == selection)
		assert(selection.get_playback_position() >= clock - 0.05)
		flow.call("_toggle_pause")
		assert(selection.stream_paused)
		await create_timer(0.1, true).timeout
		flow.call("_resume")
		assert(not selection.stream_paused)
		flow.call("_begin_fight")
		assert(match_player.playing and match_player.stream.resource_path == MUSIC.TRACKS[arena].combat)
		assert(match_player.get_playback_position() < 0.15)
		await create_timer(0.3).timeout
		for player in music.get("_players"):
			assert(not player.playing)
		flow.call("_begin_live_round")
		match_player.seek(8.0)
		await create_timer(0.1).timeout
		flow.call("_toggle_pause")
		assert(match_player.stream_paused)
		flow.call("_resume")
		assert(not match_player.stream_paused)
		# Seek near the boundary: the audio mixer must actually wrap to the baked loop.
		match_player.seek(match_player.stream.get_length() - 0.1)
		var deadline := Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < deadline:
			await process_frame
			if match_player.get_playback_position() < 1.0:
				break
		assert(match_player.playing and match_player.get_playback_position() < 1.0)
		# Drive the real flow clock, independently of seeking the looping audio.
		flow.call("_process", 29.9)
		assert(match_player.stream.resource_path == MUSIC.TRACKS[arena].combat)
		flow.call("_toggle_pause")
		flow.call("_process", 90.0)
		assert(is_equal_approx(float(music.get("_round_elapsed")), 29.9))
		flow.call("_resume")
		flow.call("_process", 0.1)
		assert(match_player.stream.resource_path == MUSIC.TRACKS[arena].alternate)
		assert(match_player.get_playback_position() < 0.15)
		flow.call("_process", 29.9)
		assert(match_player.stream.resource_path == MUSIC.TRACKS[arena].alternate)
		flow.call("_process", 0.1)
		assert(match_player.stream.resource_path == MUSIC.TRACKS[arena].combat)
		flow.call("_process", 30.0)
		assert(match_player.stream.resource_path == MUSIC.TRACKS[arena].alternate)
		flow.call("_process", 30.0)
		assert(match_player.stream.resource_path == MUSIC.TRACKS[arena].combat)
		flow.set("round_phase", flow.RoundPhase.ROUND_RESULT)
		flow.set("_round_result_remaining", 10.0)
		flow.call("_process", 1.0)
		assert(is_equal_approx(float(music.get("_round_elapsed")), 120.0))
		flow.call("_start_next_round")
		assert(is_zero_approx(float(music.get("_round_elapsed"))))
		assert(not match_player.playing and flow.call("get_round_phase_name") == "COUNTDOWN")
		selection = music.get("_players")[music.get("_active_player")]
		assert(selection.playing and selection.stream.resource_path == MUSIC.TRACKS[arena].selection)
		flow.call("_begin_fight")
		assert(match_player.playing and match_player.get_playback_position() < 0.15)
		assert(match_player.stream.resource_path == MUSIC.TRACKS[arena].combat)
		flow.call("_show_final_result")
		assert(not match_player.playing)
		for player in music.get("_players"):
			assert(not player.playing)
		flow.call("_return_menu")
		await create_timer(0.5).timeout
		assert((flow.get("_menu_music") as AudioStreamPlayer).playing)
		print("ARENA MUSIC: " + arena + " PASS")
	# Changing maps selects another theme; maps without an approved theme retain the common menu.
	flow.call("_select_arena", "heliostat")
	flow.call("_open_solo_setup")
	flow.call("_select_arena", "tideglass")
	flow.call("_preview_solo_arena")
	assert(music.get("_selection_path") == MUSIC.TRACKS.tideglass.selection)
	flow.call("_select_arena", "classic")
	flow.call("_preview_solo_arena")
	await create_timer(0.4).timeout
	for player in music.get("_players"):
		assert(not player.playing)
	assert((flow.get("_menu_music") as AudioStreamPlayer).playing)
	flow.call("_start_duel")
	assert(match_player.playing and match_player.stream.resource_path == flow.MATCH_MUSIC_PATH)
	assert(is_equal_approx(match_player.volume_db, -17.0))
	flow.call("_return_menu")
	flow.call("_set_menu_music_active", false)
	flow.call("_set_garage_music_active", false)
	(flow.get("_result_audio") as AudioStreamPlayer).stop()
	(flow.get("_countdown_audio") as AudioStreamPlayer).stop()
	await create_timer(0.5).timeout
	if existed:
		var file := FileAccess.open(LOADOUT.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved)
	else:
		DirAccess.remove_absolute(LOADOUT.SAVE_PATH)
	if library_existed:
		var file := FileAccess.open(LIBRARY.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(library_saved)
	else:
		DirAccess.remove_absolute(LIBRARY.SAVE_PATH)
	scene.queue_free()
	await process_frame
	print("ARENA MUSIC TEST: PASS (selection continuity, Fight attack, pause, loop, alternation at 30/60/90/120 seconds, next round reset, results, map change, classic fallback)")
	quit()
