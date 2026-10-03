extends CanvasLayer

## Local presentation only: never slows the simulation or network timers.
signal focus_ready

const WIN_SOUND := preload("res://art/audio/round-results/round-win-forge.wav")
const LOSS_SOUND := preload("res://art/audio/round-results/round-loss.wav")
const IMPACT_HOLD := 0.08
const DEATH_READ_TIME := 0.55

var _title: Label
var _score: Label
var _flash: ColorRect
var _audio: AudioStreamPlayer
var _elapsed := -1.0
var _focused := false
var _audio_started := false
var _paused_visuals: Array[Dictionary] = []
var _camera: Node
var _camera_processing := false
var _music: AudioStreamPlayer
var _music_volume := 0.0


func _ready() -> void:
	layer = 25
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	_title = _label(root, -44, 4, 32)
	_score = _label(root, 6, 40, 22)
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Effects"
	_audio.volume_db = -5.0
	add_child(_audio)
	hide()


func _label(root: Control, top: float, bottom: float, size: int) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.anchor_top = 0.20
	label.anchor_bottom = 0.20
	label.offset_left = -310
	label.offset_right = 310
	label.offset_top = top
	label.offset_bottom = bottom
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color("#171718"))
	label.add_theme_constant_override("outline_size", 8)
	root.add_child(label)
	return label


func begin(outcome: int, own_score: int, other_score: int, actors: Array, camera: Node, music: AudioStreamPlayer = null, match_over := false) -> void:
	reset()
	_elapsed = 0.0
	var color := Color("#8fe6aa") if outcome > 0 else Color("#f28a79") if outcome < 0 else Color("#efd5ac")
	_title.text = ("MATCH REMPORTÉ" if match_over else "MANCHE REMPORTÉE") if outcome > 0 else ("MATCH PERDU" if match_over else "MANCHE PERDUE") if outcome < 0 else "ÉGALITÉ"
	_title.add_theme_color_override("font_color", color)
	_title.modulate.a = 0.0
	_score.text = "%d  —  %d" % [own_score, other_score]
	_score.modulate.a = 0.0
	_flash.color = Color(color, 0.10)
	_audio.stream = WIN_SOUND if outcome > 0 else LOSS_SOUND if outcome < 0 else null
	_camera = camera
	if is_instance_valid(_camera):
		_camera_processing = _camera.is_processing()
		_camera.set_process(false)
	_music = music
	if is_instance_valid(_music):
		_music_volume = _music.volume_db
		_music.volume_db -= 8.0
	# Pause only visual animation for the decisive impact, after inputs stop.
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var visual: Node = actor.get_node_or_null("VisualRoot")
		if visual == null:
			continue
		if visual.has_method("play_action") and visual.get("_active_action") == &"fall":
			# The player fall is a 3 s clip; finish its collapse while the arena
			# is still visible, with the same ~1.2 s cadence as the solo bot.
			visual.call("play_action", &"fall", 0.10, 2.5)
		var tree: AnimationTree = visual.get("animation_tree")
		_paused_visuals.append({"actor": actor, "processing": actor.is_processing(), "tree": tree, "mode": tree.process_mode if tree != null else 0})
		actor.set_process(false)
		if tree != null:
			# Keep the mixer and its callback mode intact: changing either can
			# reset state-machine playback. Suspend just its node processing.
			tree.process_mode = Node.PROCESS_MODE_DISABLED
	show()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	_flash.color.a = 0.10 * maxf(0.0, 1.0 - _elapsed / IMPACT_HOLD)
	if _elapsed >= IMPACT_HOLD:
		_restore_visuals()
		if not _audio_started:
			_audio_started = true
			if _audio.stream != null:
				_audio.play()
	_title.modulate.a = clampf((_elapsed - IMPACT_HOLD) / 0.14, 0.0, 1.0)
	_score.modulate.a = clampf((_elapsed - DEATH_READ_TIME) / 0.20, 0.0, 1.0)
	if _elapsed >= DEATH_READ_TIME and not _focused:
		_focused = true
		_restore_camera()
		focus_ready.emit()
	if _elapsed >= 1.65:
		_title.modulate.a *= maxf(0.0, (1.95 - _elapsed) / 0.30)
		_score.modulate.a *= maxf(0.0, (1.95 - _elapsed) / 0.30)
	if _elapsed >= 1.95:
		reset()


func _restore_visuals() -> void:
	for value in _paused_visuals:
		if is_instance_valid(value.actor):
			value.actor.set_process(value.processing)
		if is_instance_valid(value.tree):
			value.tree.process_mode = value.mode
	_paused_visuals.clear()


func _restore_camera() -> void:
	if is_instance_valid(_camera):
		_camera.set_process(_camera_processing)
	_camera = null


func reset() -> void:
	_restore_visuals()
	_restore_camera()
	if is_instance_valid(_music):
		_music.volume_db = _music_volume
	_music = null
	_elapsed = -1.0
	_focused = false
	_audio_started = false
	if _audio != null:
		_audio.stop()
	hide()


func _exit_tree() -> void:
	reset()
