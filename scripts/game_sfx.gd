extends Node

## Ben's selected game sounds. One player per action keeps overlapping
## combat events independent; short cooldowns tame pellet and burn bursts.
signal event_played(event_id: String)

const STREAMS := {
	"counter_intercept": preload("res://art/audio/game-sfx/counter-parry.wav"),
	"pyro_dash": preload("res://art/audio/game-sfx/pyro-dash-A.wav"),
	"javelin_teleport": preload("res://art/audio/game-sfx/javelin-teleport-A.wav"),
	"magnetic_absorb": preload("res://art/audio/game-sfx/magnetic-absorb-B.wav"),
	"robot_destruction": preload("res://art/audio/game-sfx/robot-destruction-B.wav"),
	"impact_robot": preload("res://art/audio/game-sfx/impact-robot-B.wav"),
	"impact_decor": preload("res://art/audio/game-sfx/impact-decor-A.wav"),
	"impact_critical": preload("res://art/audio/game-sfx/impact-critique-B.wav"),
	"damage_received": preload("res://art/audio/game-sfx/degats-recus-B.wav"),
	"repair_pickup": preload("res://art/audio/game-sfx/magnetic-absorb-B.wav"),
	"bush_entry": preload("res://art/audio/game-sfx/bush-entry-A.wav"),
	"bush_exit": preload("res://art/audio/game-sfx/bush-exit-B.wav"),
	"low_health": preload("res://art/audio/game-sfx/low-health-B.wav"),
	"baroud_activation": preload("res://art/audio/game-sfx/baroud-A.wav"),
}
const MODULE_STREAMS := {
	"projector_charge": preload("res://art/audio/game-sfx/projector-charge.wav"),
	"projector_wave": preload("res://art/audio/game-sfx/projector-wave.wav"),
	"projector_push": preload("res://art/audio/game-sfx/projector-push.wav"),
	"projector_passive": preload("res://art/audio/game-sfx/projector-passive.wav"),
	"permutation_send": preload("res://art/audio/game-sfx/permutation-send.wav"),
	"permutation_swap": preload("res://art/audio/game-sfx/permutation-swap.wav"),
	"permutation_shield": preload("res://art/audio/game-sfx/permutation-shield.wav"),
	"rocket_arm": preload("res://art/audio/game-sfx/rocket-arm.wav"),
	"rocket_launch": preload("res://art/audio/game-sfx/rocket-launch.wav"),
	"rocket_impact": preload("res://art/audio/game-sfx/rocket-impact.wav"),
	"rocket_destroyed": preload("res://art/audio/game-sfx/rocket-destroyed.wav"),
	"counter_guard": preload("res://art/audio/game-sfx/counter-guard.wav"),
	"counter_intercept": preload("res://art/audio/game-sfx/counter-parry.wav"),
	"counter_capture": preload("res://art/audio/game-sfx/counter-capture.wav"),
	"counter_release": preload("res://art/audio/game-sfx/counter-release.wav"),
}
var _module_voices: Array[AudioStreamPlayer3D] = []
const MIN_INTERVAL_MS := {
	"magnetic_absorb": 90,
	"robot_destruction": 80,
	"impact_robot": 90,
	"impact_decor": 90,
	"impact_critical": 80,
	"damage_received": 120,
	"repair_pickup": 100,
	"bush_entry": 650,
	"bush_exit": 650,
	"low_health": 8000,
	"baroud_activation": 500,
}
const FOOTSTEPS := [
	preload("res://art/audio/game-sfx/robot-footstep-B-01.wav"),
	preload("res://art/audio/game-sfx/robot-footstep-B-02.wav"),
	preload("res://art/audio/game-sfx/robot-footstep-B-03.wav"),
	preload("res://art/audio/game-sfx/robot-footstep-B-04.wav"),
]
const ENEMY_STREAMS := {
	"enemy_shot": preload("res://art/audio/game-sfx/enemy-shot-A.wav"),
	"enemy_melee": preload("res://art/audio/game-sfx/enemy-melee-A.wav"),
	"enemy_charge_warning": preload("res://art/audio/game-sfx/enemy-charge-warning-A.wav"),
}
var _enemy_voices: Array[AudioStreamPlayer] = []
var _step_player: AudioStreamPlayer
var _rustle: AudioStreamPlayer
var _step_distance := 0.0
var _step_clock := 0.0
var _last_step := -1
var _rustle_target := -60.0
var _quiet_until_ms := 0
var _bush_transition_ms := -100000

var _players: Dictionary = {}
var _last_played_ms: Dictionary = {}
var _paused := false
var _signature_streams: Dictionary = {}
var _signature_voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for kind in ["shotgun", "counter", "fulguro_punch", "longshot"]:
		_signature_streams[kind] = _make_signature_stream(kind)
	for index in range(4):
		var voice := AudioStreamPlayer.new()
		voice.name = "SuccessAccent%d" % index
		voice.max_polyphony = 1
		add_child(voice)
		_signature_voices.append(voice)
	for event_id in STREAMS:
		var player := AudioStreamPlayer.new()
		player.name = event_id.to_pascal_case()
		player.stream = STREAMS[event_id]
		player.max_polyphony = 4
		player.volume_db = -8.0
		if event_id == "repair_pickup":
			player.pitch_scale = 1.22
			player.volume_db = -6.0
		add_child(player)
		_players[event_id] = player
		if event_id in ["bush_entry", "bush_exit"]:
			player.volume_db = -19.0
			player.max_polyphony = 1
		elif event_id in ["low_health", "baroud_activation"]:
			player.volume_db = -10.0
			player.max_polyphony = 1
	_step_player = AudioStreamPlayer.new()
	_step_player.max_polyphony = 1
	add_child(_step_player)
	_rustle = AudioStreamPlayer.new()
	var loop := preload("res://art/audio/game-sfx/bush-movement-B.wav").duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	_rustle.stream = loop
	_rustle.volume_db = -60.0
	add_child(_rustle)
	# Four attack voices and two reserved warnings; never steal a warning for a shot.
	for index in range(6):
		var voice := AudioStreamPlayer.new()
		voice.max_polyphony = 1
		add_child(voice)
		_enemy_voices.append(voice)
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	_rustle.volume_db = move_toward(_rustle.volume_db, _rustle_target, delta * 100.0)
	if _rustle_target > -60.0 and not _rustle.playing:
		_rustle.play()
	elif _rustle.volume_db <= -59.0 and _rustle.playing:
		_rustle.stop()


func mark_combat() -> void:
	_quiet_until_ms = Time.get_ticks_msec() + 1000


func reset_locomotion() -> void:
	_step_distance = 0.0
	_step_clock = 0.0
	_rustle_target = -60.0
	_step_player.stop()
	_rustle.stop()
	_rustle.volume_db = -60.0


func update_locomotion(distance: float, delta: float, in_bush: bool, walking: bool) -> void:
	_step_clock += delta
	var moving := walking and distance > 0.003 and distance < 1.0
	var fighting := Time.get_ticks_msec() < _quiet_until_ms
	_rustle_target = (-32.0 if fighting else -25.0) if moving and in_bush else -60.0
	if not moving:
		_step_distance = 0.0
		return
	_step_distance += distance
	if _step_distance < 2.8 or _step_clock < 0.55 or _step_player.playing:
		return
	_step_distance = 0.0
	_step_clock = 0.0
	# Choose among the other three grains, with tiny pitch/volume variation.
	var index := randi_range(0, 3 if _last_step < 0 else 2)
	if _last_step >= 0 and index >= _last_step:
		index += 1
	_last_step = index
	_step_player.stream = FOOTSTEPS[index]
	_step_player.pitch_scale = randf_range(0.96, 1.04)
	_step_player.volume_db = (-32.0 if fighting else -25.0) + randf_range(-1.5, 0.0) - (3.0 if in_bush else 0.0)
	_step_player.play()
	event_played.emit("robot_footstep")


func play_enemy(event_id: String, position: Vector3, listener_position: Vector3) -> void:
	if not ENEMY_STREAMS.has(event_id):
		return
	var distance := position.distance_to(listener_position)
	if distance > 24.0:
		return
	var now := Time.get_ticks_msec()
	var interval := 100 if event_id == "enemy_shot" else 180 if event_id == "enemy_melee" else 100
	if now - int(_last_played_ms.get(event_id, -100000)) < interval:
		return
	var warning := event_id == "enemy_charge_warning"
	for index in range(4 if warning else 0, 6 if warning else 4):
		var voice := _enemy_voices[index]
		if voice.playing:
			continue
		_last_played_ms[event_id] = now
		voice.stream = ENEMY_STREAMS[event_id]
		voice.volume_db = (-9.0 if warning else -15.0) - 18.0 * clampf(distance / 24.0, 0.0, 1.0)
		voice.pitch_scale = 1.0 if warning else randf_range(0.97, 1.03)
		voice.play()
		mark_combat()
		event_played.emit(event_id)
		return


func play_event(event_id: String) -> void:
	if _paused or not _players.has(event_id):
		return
	var now := Time.get_ticks_msec()
	if event_id in ["bush_entry", "bush_exit"]:
		if now - _bush_transition_ms < 650:
			return
		_bush_transition_ms = now
	if now - int(_last_played_ms.get(event_id, -100000)) < int(MIN_INTERVAL_MS.get(event_id, 0)):
		return
	_last_played_ms[event_id] = now
	if event_id not in ["bush_entry", "bush_exit", "repair_pickup"]:
		mark_combat()
	(_players[event_id] as AudioStreamPlayer).play()
	event_played.emit(event_id)


func set_paused(value: bool) -> void:
	_paused = value
	for voice in _signature_voices:
		voice.stream_paused = value
	for voice in _module_voices:
		voice.stream_paused = value
	for player: AudioStreamPlayer in _players.values():
		player.stream_paused = value
	for voice in _enemy_voices:
		voice.stream_paused = value
	_step_player.stream_paused = value
	_rustle.stream_paused = value


func clear() -> void:
	# The autoload outlives every arena. Retire the old round's voices before
	# its scene is hidden or replaced, and allow the next round's first event.
	for voice in _signature_voices:
		voice.stop()
		voice.stream_paused = false
	for voice in _module_voices.duplicate():
		voice.stop()
		voice.queue_free()
	_module_voices.clear()
	for player: AudioStreamPlayer in _players.values():
		player.stop()
		player.stream_paused = false
	for voice in _enemy_voices:
		voice.stop()
		voice.stream_paused = false
	reset_locomotion()
	_step_player.stream_paused = false
	_rustle.stream_paused = false
	_quiet_until_ms = 0
	_bush_transition_ms = -100000
	_paused = false
	_last_played_ms.clear()


func play_module_event(event_id: String, position: Vector3) -> AudioStreamPlayer3D:
	if _paused or not MODULE_STREAMS.has(event_id) or _module_voices.size() >= 24:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.stream = MODULE_STREAMS[event_id]
	voice.volume_db = -7.0
	voice.unit_size = 5.0
	voice.max_distance = 28.0
	add_child(voice)
	voice.global_position = position
	_module_voices.append(voice)
	voice.finished.connect(func() -> void:
		_module_voices.erase(voice)
		voice.queue_free()
	)
	voice.play()
	mark_combat()
	event_played.emit(event_id)
	return voice


func stop_module_voice(voice: AudioStreamPlayer3D) -> void:
	if not is_instance_valid(voice) or voice.is_queued_for_deletion():
		return
	voice.stop()
	_module_voices.erase(voice)
	voice.queue_free()


func play_signature(kind: String) -> bool:
	if _paused or not _signature_streams.has(kind):
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get("signature", -100000)) < 160:
		return false
	for voice in _signature_voices:
		if voice.playing:
			continue
		voice.stream = _signature_streams[kind]
		voice.volume_db = -17.0 if kind in ["shotgun", "fulguro_punch"] else -20.0
		voice.play()
		_last_played_ms["signature"] = now
		event_played.emit("signature_" + kind)
		return true
	return false


func _make_signature_stream(kind: String) -> AudioStreamWAV:
	# Quiet, deterministic accents sit beneath the selected weapon/module WAVs.
	# Generate once, with attack/release envelopes; no files or random game state.
	var rate := 22050
	var duration := 0.24 if kind in ["counter", "longshot"] else 0.16
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	for index in range(samples):
		var time := float(index) / rate
		var envelope := minf(1.0, time / 0.004) * pow(1.0 - time / duration, 2.5)
		var value := 0.0
		match kind:
			"shotgun":
				value = sin(TAU * (150.0 * time - 200.0 * time * time)) * 0.75 + sin(TAU * 1300.0 * time) * exp(-time * 80.0) * 0.18
			"counter":
				value = (sin(TAU * 740.0 * time) + sin(TAU * 1110.0 * time) * 0.45) * 0.48
			"fulguro_punch":
				value = sin(TAU * 73.0 * time) * 0.7 + sin(TAU * 410.0 * time) * exp(-time * 28.0) * 0.23
			"longshot":
				value = sin(TAU * 1480.0 * time) * 0.50 + sin(TAU * 2220.0 * time) * 0.16
		bytes.encode_s16(index * 2, int(clampf(value * envelope, -1.0, 1.0) * 25000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
