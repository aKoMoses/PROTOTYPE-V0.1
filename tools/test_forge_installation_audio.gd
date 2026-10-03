extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
var garage
var events: Array[Dictionary] = []
var failures: Array[String] = []
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://garage-audio-" + suffix + ".cfg", "user://garage-audio-loadout-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage.module_installation.audio.cue_played.connect(_record)
	for voice in garage.module_installation.audio.voices.values():
		check(voice.bus == &"Effects" and voice.stream != null, "imported sound uses Effects bus")
	garage._preview_equipment("weapon", "mekatana")
	check(events.is_empty(), "preview does not announce an installation")
	_cycle("weapon", "mekatana")
	_cycle("offensive", "rocket_basket")
	garage._select_equipment("defensive", "projector")
	_cycle("defensive", "magnetic_field")
	garage._select_equipment("mobility", "eclipse")
	_cycle("mobility", "pyro_boots")
	_cycle("mobility", "bio_injector")
	_cycle("passive", "auxiliary_reactor")
	# Cancel while welding: no mounting cue and no hanging sound.
	events.clear()
	garage._select_equipment("weapon", "longshot")
	_advance_to(5.0)
	check(_count("weld") == 1 and _count("lock") == 0, "welding precedes successful mounting")
	garage.module_installation.cancel()
	check(str(garage.loadout.weapon) == "mekatana", "cancel preserves previous equipment")
	_check_stopped("cancel")
	# Skipping traverses geometry silently, retaining just the successful latch.
	garage._select_equipment("weapon", "longshot")
	_advance_to(1.0)
	events.clear()
	garage.module_installation.finish_now()
	check(events.size() == 1 and _count("lock") == 1, "skip plays only the final latch")
	check(str(garage.loadout.weapon) == "longshot", "skip actually installs the weapon")
	garage.module_installation.finish_now()
	check(events.size() == 1, "finishing twice does not duplicate the latch")
	garage._select_equipment("weapon", "mekatana")
	_advance_to(5.6)
	check(garage.module_installation.mounted_module, "mount contact reached before late skip")
	events.clear()
	garage.module_installation.finish_now()
	check(events.is_empty(), "late skip does not replay an already heard latch")
	# Generic nonphysical modules use only the fitting cue, once per change.
	events.clear()
	garage._select_equipment("defensive", "projector")
	check(events.size() == 1 and _count("lock") == 1, "direct module installation has one latch")
	garage._select_equipment("defensive", "projector")
	check(events.size() == 1, "selecting equipped module stays silent")
	garage._select_equipment("weapon", "longshot")
	_advance_to(0.4)
	garage.hide()
	garage.module_installation.advance(0.1)
	_check_stopped("leaving garage")
	check(not garage.module_installation.active, "hidden garage cancels installation")
	garage.queue_free()
	await process_frame
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("FORGE INSTALLATION AUDIO TEST: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)


func _cycle(category: String, identifier: String) -> void:
	events.clear()
	garage._select_equipment(category, identifier)
	check(garage.module_installation.active, "installation starts: " + identifier)
	_advance_to(8.0)
	check(not garage.module_installation.active, "installation completes: " + identifier)
	check(_count("pickup") == 1 and _count("weld") == 1 and _count("lock") == 1, "single contact cues: " + identifier)
	for event in events:
		if event.cue == "pickup":
			check(event.reached and not event.mounted, "pickup matches actual grasp")
		elif event.cue == "weld":
			check(event.phase == "work" and event.sparks, "weld matches visible sparks")
		elif event.cue == "lock":
			check(event.mounted, "latch follows actual mounting contact")
		elif event.cue == "arm":
			check(event.phase in ["approach", "lift", "carry", "align", "return"], "servo accompanies movement")
	_check_stopped("completion")


func _advance_to(seconds: float) -> void:
	var installation = garage.module_installation
	for frame in 500:
		if not installation.active or installation.elapsed >= seconds:
			break
		installation.advance(1.0 / 60.0)


func _record(cue: String) -> void:
	var installation = garage.module_installation
	events.append({"cue": cue, "phase": installation.phase, "elapsed": installation.elapsed,
		"reached": installation.reached_module, "mounted": installation.mounted_module,
		"sparks": garage.stage.arm.particles.emitting})


func _count(cue: String) -> int:
	var count := 0
	for event in events:
		if event.cue == cue:
			count += 1
	return count


func _check_stopped(context: String) -> void:
	for voice in garage.module_installation.audio.voices.values():
		check(not voice.playing, "sound stopped after " + context)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
