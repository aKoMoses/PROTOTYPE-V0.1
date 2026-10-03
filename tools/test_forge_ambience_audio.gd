extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
var failures: Array[String] = []
var cues: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var parent := Control.new()
	root.add_child(parent)
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	garage.library_path = "user://ambience-builds-" + suffix + ".cfg"
	garage.legacy_save_path = "user://ambience-loadout-" + suffix + ".cfg"
	garage.hide()
	parent.add_child(garage)
	await process_frame
	var audio = garage.get_node("GarageAmbience")
	audio.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	check(not audio.active and not audio.bed.playing, "garage created hidden stays silent")
	check(audio.bed.bus == &"Effects" and audio.accent.bus == &"Effects", "ambience follows effects volume")
	check(audio.bed.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ventilation loops")
	check(audio.bed.stream.loop_end > 0, "loop includes the complete prepared sound")
	check(is_equal_approx(audio.accent.volume_db, 0.0), "approved baked levels are not boosted")
	garage.show()
	check(audio.active and audio.bed.playing, "entering garage starts the bed")
	check(audio.remaining >= 10.0 and audio.remaining <= 18.0, "first accent has a quiet delay")
	# Control simulated time without waiting through long real-time intervals.
	audio.set_process(false)
	for index in 8:
		audio._process(audio.remaining + 0.01)
		check(cues.size() == index + 1, "one accent per interval")
		check(audio.remaining >= 10.0 and audio.remaining <= 18.0, "sparse irregular interval")
		if cues.size() > 1:
			check(cues[-1] != cues[-2], "no identical consecutive accents")
	var count := cues.size()
	garage.module_installation.active = true
	audio.remaining = 0.0
	audio._process(30.0)
	check(cues.size() == count and not audio.accent.playing, "installation suppresses ambient accents")
	check(audio.remaining >= 10.0, "installation leaves a quiet recovery period")
	garage.module_installation.active = false
	garage.hide()
	check(not audio.active and not audio.bed.playing and not audio.accent.playing, "leaving stops every sound")
	audio._process(60.0)
	check(cues.size() == count, "hidden garage cannot emit an accent")
	garage.show()
	check(audio.active and audio.bed.playing and audio.remaining >= 10.0, "reopening resets quiet delay")
	# Parent visibility also hides the garage, as screen switches do.
	parent.hide()
	check(not audio.active and not audio.bed.playing, "hidden ancestor stops ambience")
	parent.show()
	check(audio.active and audio.bed.playing, "visible ancestor restarts ambience")
	if "--record" in OS.get_cmdline_user_args():
		audio.set_process(false)
		await create_timer(1.7).timeout
		check(is_equal_approx(audio.bed.volume_db, 0.0), "fade reaches the approved baked bed level")
		var bus := AudioServer.get_bus_index("Effects")
		var recorder := AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus, recorder)
		recorder.set_recording_active(true)
		await create_timer(1.0).timeout
		audio._process(audio.remaining + 0.01)
		await create_timer(1.5).timeout
		garage.hide()
		await create_timer(0.5).timeout
		recorder.set_recording_active(false)
		var recording := recorder.get_recording()
		check(recording != null and recording.data.size() > 44, "engine mixer produces an ambience recording")
		if recording != null:
			recording.save_to_wav("res://audio-lab/garage-ambience/reports/runtime-ambience.wav")
		AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	var weak_voice: WeakRef = weakref(audio.bed)
	parent.queue_free()
	await process_frame
	check(weak_voice.get_ref() == null, "closing frees ambience voices")
	for failure in failures:
		push_error(failure)
	print("FORGE AMBIENCE AUDIO TEST: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
