extends Node

## Approved Stable Audio ambience. Levels are baked into the WAVs, below music.
signal cue_played(cue: String)

const BED := preload("res://art/audio/garage-ambience/ventilation.wav")
const ACCENTS := {
	"pressure": preload("res://art/audio/garage-ambience/pressure.wav"),
	"metal": preload("res://art/audio/garage-ambience/metal.wav"),
}
const MIN_INTERVAL := 10.0
const MAX_INTERVAL := 18.0
const FADE_SECONDS := 1.5

var bed: AudioStreamPlayer
var accent: AudioStreamPlayer
var active := false
var remaining := 0.0
var _garage: Control
var _fade: Tween
var _random := RandomNumberGenerator.new()
var _last_cue := ""


func _ready() -> void:
	name = "GarageAmbience"
	_garage = get_parent() as Control
	_random.randomize()
	bed = AudioStreamPlayer.new()
	bed.name = "Ventilation"
	bed.bus = &"Effects"
	var loop := BED.duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(round(loop.get_length() * loop.mix_rate))
	bed.stream = loop
	add_child(bed)
	accent = AudioStreamPlayer.new()
	accent.name = "DistantWorkshop"
	accent.bus = &"Effects"
	accent.volume_db = 0.0
	add_child(accent)
	if _garage != null:
		_garage.visibility_changed.connect(_sync_visibility)
		_sync_visibility()
	else:
		set_process(false)


func _sync_visibility() -> void:
	set_active(_garage.is_visible_in_tree())


func set_active(enabled: bool) -> void:
	if active == enabled:
		return
	active = enabled
	set_process(active)
	if _fade != null:
		_fade.kill()
	accent.stop()
	remaining = _random.randf_range(MIN_INTERVAL, MAX_INTERVAL) if active else 0.0
	if active:
		bed.volume_db = -60.0
		bed.play()
		_fade = create_tween()
		_fade.tween_property(bed, "volume_db", 0.0, FADE_SECONDS)
	else:
		bed.stop()


func _process(delta: float) -> void:
	if not active:
		return
	# Leave installation contacts readable; ambient details wait until later.
	if _workshop_busy():
		accent.stop()
		remaining = maxf(remaining, MIN_INTERVAL)
		return
	remaining -= delta
	if remaining > 0.0:
		return
	var cue := "pressure" if _random.randf() < 0.5 else "metal"
	if cue == _last_cue:
		cue = "metal" if cue == "pressure" else "pressure"
	_last_cue = cue
	accent.stream = ACCENTS[cue]
	accent.play()
	cue_played.emit(cue)
	remaining = _random.randf_range(MIN_INTERVAL, MAX_INTERVAL)


func _workshop_busy() -> bool:
	if _garage == null:
		return false
	for property in ["installation", "module_installation"]:
		var operation = _garage.get(property)
		if operation != null and operation.active:
			return true
	return false
