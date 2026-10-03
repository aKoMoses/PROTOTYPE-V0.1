extends Node

## Short workshop gestures driven by the actual pickup and mounting contacts.
signal cue_played(cue: String)

const STREAMS := {
	"arm": preload("res://art/audio/garage-sfx/01-bras-mecanique.wav"),
	"pickup": preload("res://art/audio/garage-sfx/02-prise-pince.wav"),
	"weld": preload("res://art/audio/garage-sfx/03-soudure.wav"),
	"lock": preload("res://art/audio/garage-sfx/04-verrouillage.wav"),
}
const LEVELS := {"arm": -7.0, "pickup": -3.0, "weld": -6.0, "lock": -3.0}
# Skip audition padding; retain a short lead-in before each contact transient.
const STARTS := {"arm": 0.06, "pickup": 0.10, "weld": 0.08, "lock": 0.08}
const MOVEMENT_PHASES := ["approach", "lift", "carry", "align", "return"]

var suppressed := false
var voices: Dictionary = {}
var _welding := false


func _ready() -> void:
	for cue in STREAMS:
		var voice := AudioStreamPlayer.new()
		voice.name = "Garage" + str(cue).capitalize()
		voice.bus = &"Effects"
		voice.volume_db = float(LEVELS[cue])
		voice.stream = STREAMS[cue]
		add_child(voice)
		voices[cue] = voice


func enter_phase(phase: String) -> void:
	(voices["arm"] as AudioStreamPlayer).stop()
	if phase != "work":
		set_welding(false)
	if phase in MOVEMENT_PHASES:
		play("arm")


func set_welding(emitting: bool) -> void:
	if emitting == _welding:
		return
	_welding = emitting
	if emitting:
		play("weld")
	else:
		(voices["weld"] as AudioStreamPlayer).stop()


func play(cue: String) -> void:
	if suppressed or not voices.has(cue):
		return
	(voices[cue] as AudioStreamPlayer).play(float(STARTS[cue]))
	cue_played.emit(cue)


func stop_all() -> void:
	_welding = false
	for voice in voices.values():
		(voice as AudioStreamPlayer).stop()
