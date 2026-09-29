extends SceneTree

## Isolated presentation regression: no Player, arena or saved preferences.
const STATUS_VFX := preload("res://scripts/status_vfx.gd")
var _failures: Array[String] = []
var _checks := 0
var _stage: Node3D


func _initialize() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	current_scene = _stage
	call_deferred("_run")


func _run() -> void:
	var actor := Node3D.new()
	_stage.add_child(actor)
	var status := STATUS_VFX.new()
	status.configure(actor)
	status.sync(["STUN"])
	status.set_process(false)
	status._process(0.01)
	_check(status._stun_arcs.visible, "STUN starts an electrical pulse")
	status._process(0.12)
	_check(status._stun_remaining == 0.0 and status._stun_timer > 0.0, "test reaches the quiet gap between STUN pulses")
	_check(not status._stun_arcs.visible, "electrical arcs stop when their pulse expires")
	_check(status.get_active_effects() == ["STUN"], "quiet gap keeps the authoritative STUN indicator active")
	status._process(0.25)
	_check(status._stun_arcs.visible, "next STUN pulse resumes normally")
	status.clear()
	_check(not status._stun_arcs.visible and status.get_active_effects().is_empty(), "reset clears STUN pulses and indicators")
	actor.queue_free()
	await process_frame

	var sfx := root.get_node("GameSfx")
	var player := sfx.get_node("PyroDash") as AudioStreamPlayer
	sfx.call("play_event", "pyro_dash")
	_check(player.playing, "combat sound begins on its confirmed event")
	_check(sfx.has_method("set_paused"), "combat sound exposes pause lifecycle")
	_check(sfx.has_method("clear"), "combat sound exposes round/scene cleanup")
	if sfx.has_method("set_paused") and sfx.has_method("clear"):
		sfx.call("set_paused", true)
		_check(player.stream_paused, "pause suspends the currently playing sound")
		var received := []
		sfx.connect("event_played", func(event_id: String) -> void: received.append(event_id))
		sfx.call("play_event", "javelin_teleport")
		_check(received.is_empty(), "paused combat rejects stale sound requests")
		sfx.call("set_paused", false)
		_check(not player.stream_paused and player.playing, "resume continues the suspended sound")
		sfx.call("set_paused", true)
		sfx.call("clear")
		var cleared := true
		for sound: AudioStreamPlayer in sfx.get("_players").values():
			cleared = cleared and not sound.playing and not sound.stream_paused
		_check(cleared and sfx.get("_last_played_ms").is_empty(), "scene/round reset stops all sounds and cooldown history")
		sfx.call("play_event", "javelin_teleport")
		_check(received == ["javelin_teleport"], "new round can play its first event immediately")
		sfx.call("clear")
	else:
		player.stop()
	_stage.queue_free()
	current_scene = null
	await process_frame
	# AudioServer retires stopped playback on its next mixer tick. Give it that
	# tick before terminating the engine, just as normal menu navigation does.
	await create_timer(0.10).timeout
	print("PRESENTATION LIFECYCLE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)
		push_error("FAIL: " + label)
