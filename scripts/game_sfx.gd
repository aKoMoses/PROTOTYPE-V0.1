extends Node

## Ben's selected game sounds. One player per action keeps overlapping
## combat events independent; short cooldowns tame pellet and burn bursts.
signal event_played(event_id: String)

const STREAMS := {
	"pyro_dash": preload("res://art/audio/game-sfx/pyro-dash-A.wav"),
	"javelin_teleport": preload("res://art/audio/game-sfx/javelin-teleport-A.wav"),
	"magnetic_absorb": preload("res://art/audio/game-sfx/magnetic-absorb-B.wav"),
	"robot_destruction": preload("res://art/audio/game-sfx/robot-destruction-B.wav"),
	"impact_robot": preload("res://art/audio/game-sfx/impact-robot-B.wav"),
	"impact_decor": preload("res://art/audio/game-sfx/impact-decor-A.wav"),
	"impact_critical": preload("res://art/audio/game-sfx/impact-critique-B.wav"),
	"damage_received": preload("res://art/audio/game-sfx/degats-recus-B.wav"),
	"repair_pickup": preload("res://art/audio/game-sfx/magnetic-absorb-B.wav"),
}
const MIN_INTERVAL_MS := {
	"magnetic_absorb": 90,
	"robot_destruction": 80,
	"impact_robot": 90,
	"impact_decor": 90,
	"impact_critical": 80,
	"damage_received": 120,
	"repair_pickup": 100,
}

var _players: Dictionary = {}
var _last_played_ms: Dictionary = {}


func _ready() -> void:
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


func play_event(event_id: String) -> void:
	if not _players.has(event_id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get(event_id, -100000)) < int(MIN_INTERVAL_MS.get(event_id, 0)):
		return
	_last_played_ms[event_id] = now
	(_players[event_id] as AudioStreamPlayer).play()
	event_played.emit(event_id)
