extends Node

## Approved map themes; the existing match player still owns result ducking.
const TRACKS := {
	"heliostat": {"selection": "res://art/audio/maps/heliostat_selection.wav", "combat": "res://art/audio/maps/heliostat_combat.wav", "alternate": "res://art/audio/maps/heliostat_combat_alternate.wav"},
	"tideglass": {"selection": "res://art/audio/maps/tideglass_selection.wav", "combat": "res://art/audio/maps/tideglass_combat.wav", "alternate": "res://art/audio/maps/tideglass_combat_alternate.wav"},
	"clockwork": {"selection": "res://art/audio/maps/clockwork_selection.wav", "combat": "res://art/audio/maps/clockwork_combat.wav", "alternate": "res://art/audio/maps/clockwork_combat_alternate.wav"},
}
const COMBAT_SWITCH_SECONDS := 30.0
const LOOP_BEGIN_SECONDS := 0.12
const SELECTION_VOLUME_DB := -12.0
const COMBAT_VOLUME_DB := -11.0
var _match_player: AudioStreamPlayer
var _fallback_stream: AudioStream
var _fallback_volume := -17.0
var _players: Array[AudioStreamPlayer] = []
var _active_player := 0
var _selection_path := ""
var _fade: Tween
var _streams := {}
var _combat_arena := ""
var _round_elapsed := 0.0
var _combat_index := 0

func configure(match_player: AudioStreamPlayer) -> void:
	name = "ArenaMusic"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_match_player = match_player
	_fallback_stream = match_player.stream
	_fallback_volume = match_player.volume_db
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "SelectionTheme%d" % index
		player.bus = &"Music"
		player.volume_db = -60.0
		add_child(player)
		_players.append(player)

func has_theme(arena: String) -> bool:
	return TRACKS.has(arena)

func _loop_stream(path: String) -> AudioStream:
	if not _streams.has(path):
		var stream := load(path) as AudioStreamWAV
		if stream == null:
			return null
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = int(LOOP_BEGIN_SECONDS * stream.mix_rate)
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
		_streams[path] = stream
	return _streams[path]

func select(arena: String) -> bool:
	if not has_theme(arena):
		stop_selection(0.25)
		return false
	var path: String = TRACKS[arena].selection
	if _selection_path == path and _players[_active_player].playing:
		return true # Preserve the clock across menu, preparation and countdown.
	var stream := _loop_stream(path)
	if stream == null:
		stop_selection()
		return false
	if _fade != null:
		_fade.kill()
	var previous := _players[_active_player]
	_active_player = 1 - _active_player
	var next := _players[_active_player]
	next.stop()
	next.stream = stream
	next.stream_paused = false
	next.volume_db = -60.0
	next.play()
	_selection_path = path
	_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_parallel(true)
	_fade.tween_property(next, "volume_db", SELECTION_VOLUME_DB, 0.30)
	_fade.tween_property(previous, "volume_db", -60.0, 0.30)
	_fade.chain().tween_callback(previous.stop)
	return true

func stop_selection(duration := 0.0) -> void:
	_selection_path = ""
	if _fade != null:
		_fade.kill()
	if duration <= 0.0:
		for player in _players:
			player.stop()
		return
	_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_parallel(true)
	for player in _players:
		_fade.tween_property(player, "volume_db", -60.0, duration)
	_fade.chain().tween_callback(func() -> void:
		for player in _players:
			player.stop())

func start_combat(arena: String) -> void:
	stop_selection(0.18)
	stop_combat()
	_combat_arena = arena if has_theme(arena) else ""
	if has_theme(arena):
		# Cache the next track before live play so the timed switch needs no disk load.
		_loop_stream(TRACKS[arena].alternate)
	_match_player.stream = _loop_stream(TRACKS[arena].combat) if has_theme(arena) else _fallback_stream
	_match_player.volume_db = COMBAT_VOLUME_DB if has_theme(arena) else _fallback_volume
	_match_player.stream_paused = false
	if _match_player.stream != null:
		_match_player.play() # No entrance fade: the approved first attack lands on Fight.

func stop_combat() -> void:
	_match_player.stop()
	_combat_arena = ""
	_round_elapsed = 0.0
	_combat_index = 0

func advance_round(delta: float) -> void:
	if _combat_arena.is_empty() or delta <= 0.0 or get_tree().paused or _match_player.stream_paused or not _match_player.playing:
		return
	_round_elapsed += delta
	var next_index := floori(_round_elapsed / COMBAT_SWITCH_SECONDS) % 2
	if next_index == _combat_index:
		return
	_combat_index = next_index
	var key := "combat" if _combat_index == 0 else "alternate"
	_match_player.stop()
	_match_player.stream = _loop_stream(TRACKS[_combat_arena][key])
	_match_player.play() # Keep the current mix level and restart the new phrase at its attack.

func set_paused(value: bool) -> void:
	for player in _players:
		player.stream_paused = value
