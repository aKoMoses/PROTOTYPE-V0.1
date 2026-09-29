class_name PrototypeGameFlow
extends CanvasLayer

## Navigation, loadout, HUD and round presentation. Combat remains in Player,
## TargetDummy and the existing state objects.

const LOADOUT := preload("res://scripts/loadout_state.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const EQUIPMENT_CARD := preload("res://scripts/equipment_card.gd")
const EQUIPMENT_ICONS := preload("res://scripts/equipment_icons.gd")
const COOLDOWN_RING := preload("res://scripts/cooldown_ring.gd")
const NETWORK_LOBBY := preload("res://scripts/network_lobby.gd")
const HUD_CONTROLLER := preload("res://scripts/hud_layout_controller.gd")
const HUD_EDITOR := preload("res://scripts/hud_editor.gd")
const TRIAL_PLAYER_SCRIPT := preload("res://scripts/player.gd")
const TRIAL_DUMMY_SCRIPT := preload("res://scripts/training_dummy.gd")
const HUD_VITALS_SCRIPT := preload("res://scripts/hud_vitals.gd")
var _equipment_icons = EQUIPMENT_ICONS.new()
const EQUIPMENT_FRAME: Texture2D = preload("res://art/ui/equipment-frame.png")
const SPELL_BAR_FRAME: Texture2D = preload("res://art/ui/spell-bar-frame.svg")
const JAVELIN_RECAST_ICON: Texture2D = preload("res://art/ui/icons/javelin-recast.svg")
const MATCH_SUMMARY_FRAME: Texture2D = preload("res://art/ui/match-summary-frame.svg")
const EQUIPMENT_CATEGORIES := [
	{"id": "robot", "title": "ROBOT"},
	{"id": "weapon", "title": "ARME"},
	{"id": "offensive", "title": "OFFENSIF"},
	{"id": "defensive", "title": "DÉFENSIF"},
	{"id": "mobility", "title": "MOBILITÉ"},
	{"id": "passive", "title": "PASSIF"},
]
const MENU_PANEL_TEXTURE: Texture2D = preload("res://art/ui/menu/menu-panel.png")
const MENU_BUTTON_PRIMARY_TEXTURE: Texture2D = preload("res://art/ui/menu/menu-button-primary.png")
const MENU_BUTTON_SECONDARY_TEXTURE: Texture2D = preload("res://art/ui/menu/menu-button-secondary.png")
const MENU_DISPLAY_FONT: Font = preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const COUNTDOWN_SECONDS := 3.0
const FIGHT_SECONDS := 0.9
const WINNER_FOCUS_SECONDS := 1.55
const COUNTDOWN_DIGITS := [
	preload("res://art/countdown/3.png"),
	preload("res://art/countdown/2.png"),
	preload("res://art/countdown/1.png"),
]
const COUNTDOWN_SOUNDS := [
	preload("res://art/audio/countdown-3.mp3"),
	preload("res://art/audio/countdown-2.mp3"),
	preload("res://art/audio/countdown-1.mp3"),
]
const FIGHT_IMAGE: Texture2D = preload("res://art/countdown/fight.png")
const FIGHT_SOUND: AudioStream = preload("res://art/audio/countdown-fight.mp3")
const MATCH_MUSIC_PATH := "res://son-musique/musiques/02_tambours_de_guerre_30s.wav"
const MENU_MUSIC_PATH := "res://art/audio/menu_poussiere_et_cambouis.wav"
const MENU_MUSIC_VOLUME_DB := -10.0
const VICTORY_SOUND: AudioStream = preload("res://son-musique/musiques/01_victoire_rock.wav")
const DEFEAT_SOUND: AudioStream = preload("res://son-musique/musiques/02_defaite_forge.wav")

enum Screen { MENU, EQUIPMENT, SETTINGS, COMBAT, RESULT, LOBBY }
enum RoundPhase { IDLE, COUNTDOWN, LIVE, ROUND_RESULT, MATCH_RESULT, FIGHT, WINNER_FOCUS }

var main: Node
var player: Node
var target: Node
var touch_controls: Node
var current_screen := Screen.MENU
var loadout: Dictionary = LOADOUT.defaults()
var result_text := ""
var _round_resolved := false
var round_phase := RoundPhase.IDLE
var player_round_score := 0
var bot_round_score := 0
var round_number := 0
var match_id := 0
var _countdown_remaining := 0.0
var _fight_remaining := 0.0
var _round_result_remaining := 0.0
var _winner_focus_remaining := 0.0
var _transition_release_remaining := 0.0
var _round_result_player_dead := false
var _round_result_bot_dead := false
var _pause_active := false
var _pause_started_msec := 0
var _javelin_recast_display_fraction := 0.0
var _settings: Dictionary = {"camera_shake": true, "touch_scale": 1.0}
var _screen_root: Control
var _hud: Control
var _menu_panel: Control
var _equipment_panel: Control
var _title_label: Label
var _status_label: Label
var _equipment_content: HBoxContainer
var _equipment_category_label: Label
var _equipment_category := "robot"
var _equipment_nav_buttons: Dictionary = {}
var _equipment_nav_icons: Dictionary = {}
var _equipment_preview_buttons: Dictionary = {}
var _equipment_preview_icons: Dictionary = {}
var _equipment_info_panel: PanelContainer
var _equipment_info_title: Label
var _equipment_info_description: Label
var _equipment_info_stats: Label
var _equipment_info_id := ""
var _selection_buttons: Dictionary = {}
var _selection_markers: Dictionary = {}
var _hud_labels: Dictionary = {}
var _countdown_overlay: Control
var _countdown_dim: ColorRect
var _countdown_glow: TextureRect
var _countdown_image: TextureRect
var _countdown_digit_index := -1
var _countdown_audio: AudioStreamPlayer
var _match_music: AudioStreamPlayer
var _menu_music: AudioStreamPlayer
var _menu_music_tween: Tween
var _menu_music_active := false
var _result_audio: AudioStreamPlayer
var _pause_panel: PanelContainer
var _result_panel: PanelContainer
var _transition_dim: ColorRect
var _settings_panel: PanelContainer
var _lobby_panel: Control
var _hud_controller
var _hud_editor
var _editor_from_pause := false
var _editor_test_started_msec := 0
var _editor_test_target_position := Vector3.ZERO
var _editor_test_target_enabled := false
var _editor_trial_player: CharacterBody3D
var _editor_trial_target: StaticBody3D
var _editor_original_player: Node
var _editor_player_process_mode := Node.PROCESS_MODE_INHERIT
var _editor_target_process_mode := Node.PROCESS_MODE_INHERIT
var _editor_existing_fx: Dictionary = {}
var _result_actions: Array[Control] = []
var _navigation_backdrop: TextureRect
var _touch_scale_label: Label

const BG := Color("#161417")
const PANEL := Color("#292327")
const PANEL_ALT := Color("#352b2d")
const CREAM := Color("#f3ddbb")
const MUTED := Color("#bda995")
const CYAN := Color("#42d9e5")
const RED := Color("#d95b4d")
const GREEN := Color("#69d687")
const AMBER := Color("#efb765")

func configure(owner: Node, player_node: Node, target_node: Node, touch_node: Node) -> void:
	main = owner
	player = player_node
	target = target_node
	touch_controls = touch_node
	loadout = LOADOUT.load_local()
	_load_settings()
	main.set_meta("camera_shake_enabled", bool(_settings.camera_shake))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_countdown_audio = AudioStreamPlayer.new()
	_countdown_audio.name = "CountdownAudio"
	_countdown_audio.volume_db = -8.0
	add_child(_countdown_audio)
	_match_music = AudioStreamPlayer.new()
	_match_music.name = "MatchMusic"
	_match_music.volume_db = -17.0
	if ResourceLoader.exists(MATCH_MUSIC_PATH):
		_match_music.stream = load(MATCH_MUSIC_PATH) as AudioStream
		if _match_music.stream is AudioStreamWAV:
			(_match_music.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(_match_music.stream as AudioStreamWAV).loop_begin = 0
			(_match_music.stream as AudioStreamWAV).loop_end = int(_match_music.stream.get_length() * (_match_music.stream as AudioStreamWAV).mix_rate)
	add_child(_match_music)
	_menu_music = AudioStreamPlayer.new()
	_menu_music.name = "MenuMusic"
	_menu_music.volume_db = -60.0
	_menu_music.stream = load(MENU_MUSIC_PATH) as AudioStream
	if _menu_music.stream is AudioStreamWAV:
		var menu_stream := _menu_music.stream as AudioStreamWAV
		menu_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# The tail blends into 4.0–4.75 s, so the opening build plays only once.
		menu_stream.loop_begin = int(4.75 * menu_stream.mix_rate)
		menu_stream.loop_end = int(menu_stream.get_length() * menu_stream.mix_rate)
	add_child(_menu_music)
	_result_audio = AudioStreamPlayer.new()
	_result_audio.name = "ResultAudio"
	_result_audio.volume_db = -6.0
	add_child(_result_audio)
	_build_ui()
	_setup_hud_editor()
	if touch_controls != null and touch_controls.has_method("set_control_scale"):
		touch_controls.call("set_control_scale", _settings.touch_scale)
	_show_screen(Screen.MENU)

func _process(delta: float) -> void:
	if not _pause_active and round_phase == RoundPhase.COUNTDOWN:
		_countdown_remaining = maxf(0.0, _countdown_remaining - delta)
		if _countdown_remaining <= 0.0:
			_begin_fight()
	elif not _pause_active and round_phase == RoundPhase.FIGHT:
		_fight_remaining = maxf(0.0, _fight_remaining - delta)
		if _fight_remaining <= 0.0:
			_begin_live_round()
	if not _pause_active and round_phase == RoundPhase.ROUND_RESULT:
		_round_result_remaining = maxf(0.0, _round_result_remaining - delta)
		if _transition_release_remaining > 0.0:
			_transition_release_remaining = maxf(0.0, _transition_release_remaining - delta)
			_transition_dim.modulate.a = _transition_release_remaining / 0.35
			_transition_dim.visible = _transition_release_remaining > 0.0
		_update_round_result_label()
		if _round_result_remaining <= 0.0:
			_start_next_round()
	if not _pause_active and round_phase == RoundPhase.WINNER_FOCUS:
		_winner_focus_remaining = maxf(0.0, _winner_focus_remaining - delta)
		_transition_dim.modulate.a = clampf((0.48 - _winner_focus_remaining) / 0.48, 0.0, 1.0)
		if _winner_focus_remaining <= 0.0:
			_show_round_result()
	if _pause_active:
		_update_pause_labels()
	if current_screen == Screen.COMBAT or (_hud_editor != null and _hud_editor.visible and _hud_editor.test_mode):
		_update_hud()
		_update_countdown_overlay()

func _unhandled_input(event: InputEvent) -> void:
	if _hud_editor != null and _hud_editor.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if current_screen == Screen.COMBAT:
			_toggle_pause()
		elif current_screen in [Screen.SETTINGS, Screen.EQUIPMENT, Screen.LOBBY]:
			_open_menu()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _screen_root != null:
		if _hud_editor != null and _hud_editor.visible:
			return
		if current_screen == Screen.COMBAT:
			_toggle_pause()
		elif current_screen in [Screen.SETTINGS, Screen.EQUIPMENT, Screen.LOBBY]:
			_open_menu()

func _build_ui() -> void:
	_screen_root = Control.new()
	_screen_root.name = "FlowRoot"
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen_root)
	_navigation_backdrop = TextureRect.new()
	_navigation_backdrop.name = "NavigationBackdrop"
	_navigation_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_navigation_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("#0b1015a0"), Color("#0b101518")])
	var backdrop_texture := GradientTexture2D.new()
	backdrop_texture.gradient = gradient
	backdrop_texture.fill_from = Vector2(0.0, 0.5)
	backdrop_texture.fill_to = Vector2(1.0, 0.5)
	_navigation_backdrop.texture = backdrop_texture
	_screen_root.add_child(_navigation_backdrop)
	_build_menu()
	_build_lobby()
	_build_equipment()
	_build_settings()
	_build_hud()
	_build_winner_transition()
	_build_pause()
	_build_result()
	_screen_root.resized.connect(func() -> void: _layout_navigation_panels.call_deferred())
	_layout_navigation_panels.call_deferred()

func _layout_navigation_panels() -> void:
	# Scale navigation only. HUD geometry and saved touch layouts use their own
	# safe-area controller and remain independent of these decorative panels.
	var viewport_size := _screen_root.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var available := viewport_size - Vector2(32.0, 24.0)
	for panel in [_menu_panel, _equipment_panel, _settings_panel, _pause_panel, _result_panel]:
		if panel == null:
			continue
		var design: Vector2 = panel.get_meta("navigation_size", panel.custom_minimum_size)
		design = design.max(panel.get_combined_minimum_size())
		var factor := minf(1.0, minf(available.x / design.x, available.y / design.y))
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.size = design
		panel.scale = Vector2.ONE * factor
		panel.position = (viewport_size - design * factor) * 0.5
		if panel == _menu_panel:
			panel.position.x = 16.0 + maxf(0.0, viewport_size.x - 1280.0) * 0.10

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://prototype0_settings.cfg") == OK:
		_settings.camera_shake = bool(config.get_value("settings", "camera_shake", true))
		_settings.touch_scale = clampf(float(config.get_value("settings", "touch_scale", 1.0)), 0.85, 1.15)

func _save_settings() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var config := ConfigFile.new()
	config.set_value("settings", "camera_shake", _settings.camera_shake)
	config.set_value("settings", "touch_scale", _settings.touch_scale)
	config.save("user://prototype0_settings.cfg")

func _panel_style(color: Color, border: Color = Color("#594649"), radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	return style

func _label(text: String, size: int, color: Color = CREAM) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	if size >= 25:
		item.add_theme_font_override("font", MENU_DISPLAY_FONT)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item

func _button(text: String, callback: Callable, width := 280.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 48)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_font_override("font", MENU_DISPLAY_FONT)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(PANEL_ALT, Color("#594649"), 8))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#49383c"), CYAN, 8))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("#1d555b"), CYAN, 8))
	button.add_theme_stylebox_override("focus", _panel_style(Color("#49383c"), CYAN, 8))
	for state in ["normal", "hover", "pressed"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		style.content_margin_top = 11
		style.content_margin_bottom = 11
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color.TRANSPARENT
	focus_style.border_color = CYAN
	focus_style.set_border_width_all(2)
	focus_style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("focus", focus_style)
	button.pressed.connect(callback)
	return button

func _center_panel(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, height)
	panel.set_meta("navigation_size", Vector2(width, height))
	var frame_style := StyleBoxTexture.new()
	frame_style.texture = EQUIPMENT_FRAME
	# The source PNG includes transparent padding around the outer metal edge.
	# Crop it before nine-slicing so content margins refer to the actual plate.
	frame_style.region_rect = Rect2(48, 40, 1576, 860)
	frame_style.set_texture_margin_all(64)
	frame_style.content_margin_left = 32
	frame_style.content_margin_right = 32
	frame_style.content_margin_top = 30
	frame_style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", frame_style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position -= Vector2(width, height) * 0.5
	return panel

func _clear_screen() -> void:
	for child in _screen_root.get_children():
		child.visible = false

func _show_screen(screen: Screen) -> void:
	current_screen = screen
	if screen != Screen.RESULT:
		_result_audio.stop()
	_set_menu_music_active(screen in [Screen.MENU, Screen.EQUIPMENT, Screen.SETTINGS, Screen.LOBBY])
	_clear_screen()
	_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE if screen == Screen.COMBAT else Control.MOUSE_FILTER_STOP
	_navigation_backdrop.visible = screen != Screen.COMBAT
	if touch_controls != null:
		touch_controls.visible = false
	if _pause_active and screen != Screen.COMBAT:
		_end_pause(false)
	match screen:
		Screen.MENU:
			_menu_panel.visible = true
		Screen.EQUIPMENT:
			_equipment_panel.visible = true
			_refresh_equipment()
		Screen.SETTINGS:
			_settings_panel.visible = true
		Screen.LOBBY:
			_lobby_panel.visible = true
			_lobby_panel.call("refresh")
		Screen.COMBAT:
			_hud.visible = true
			if touch_controls != null:
				touch_controls.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested()
		Screen.RESULT:
			_result_panel.visible = true
	if main != null and main.has_method("set_menu_mode"):
		main.call("set_menu_mode", screen != Screen.COMBAT)
	if main != null and main.has_method("set_menu_showcase_enabled"):
		main.call("set_menu_showcase_enabled", screen == Screen.MENU)
	_layout_navigation_panels.call_deferred()

func _touch_preview_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "touch_preview":
			return true
	return false

func _build_menu() -> void:
	var panel_size := Vector2(620.0, 660.0)
	_menu_panel = Control.new()
	_menu_panel.name = "MainMenuPanel"
	_menu_panel.custom_minimum_size = panel_size
	_menu_panel.set_meta("navigation_size", panel_size)
	_menu_panel.size = panel_size
	_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_menu_panel.position = Vector2(-panel_size.x * 0.5 - 300.0, -panel_size.y * 0.5)
	_screen_root.add_child(_menu_panel)
	var plate := TextureRect.new()
	plate.name = "GeneratedMenuPlate"
	plate.texture = MENU_PANEL_TEXTURE
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_panel.add_child(plate)
	var box := VBoxContainer.new()
	box.name = "MenuContent"
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(136.0, 94.0)
	box.size = Vector2(422.0, 474.0)
	box.add_theme_constant_override("separation", 6)
	_menu_panel.add_child(box)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	_title_label = _label("PROTOTYPE ", 42, CREAM)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title_label.add_theme_font_override("font", MENU_DISPLAY_FONT)
	title.add_child(_title_label)
	var title_zero := _label("0", 42, CYAN)
	title_zero.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_zero.add_theme_font_override("font", MENU_DISPLAY_FONT)
	title.add_child(title_zero)
	box.add_child(title)
	var subtitle := _label("COMBAT DE ROBOTS  •  ARÈNE LOCALE", 16, CYAN)
	subtitle.add_theme_font_override("font", MENU_DISPLAY_FONT)
	box.add_child(subtitle)
	var divider := ColorRect.new()
	divider.color = Color("#3a4244")
	divider.custom_minimum_size = Vector2(0.0, 2.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(divider)
	var intro := _label("Choisis un duel, une survie ou un entraînement.", 16, CREAM)
	intro.custom_minimum_size = Vector2(0.0, 38.0)
	box.add_child(intro)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 2.0)
	box.add_child(spacer)
	box.add_child(_menu_art_button("JOUER", Callable(self, "_open_equipment"), MENU_BUTTON_PRIMARY_TEXTURE, 64.0))
	box.add_child(_menu_art_button("MULTIJOUEUR", Callable(self, "_open_lobby"), MENU_BUTTON_SECONDARY_TEXTURE, 56.0))
	box.add_child(_menu_art_button("MODE SURVIE", Callable(self, "_open_survival"), MENU_BUTTON_SECONDARY_TEXTURE, 56.0))
	box.add_child(_menu_art_button("TRAINING GROUND", Callable(self, "_open_training_ground"), MENU_BUTTON_SECONDARY_TEXTURE, 56.0))
	box.add_child(_menu_art_button("RÉGLAGES", Callable(self, "_open_settings"), MENU_BUTTON_SECONDARY_TEXTURE, 56.0))


func _build_lobby() -> void:
	_lobby_panel = NETWORK_LOBBY.new()
	_lobby_panel.name = "NetworkLobby"
	_lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.add_child(_lobby_panel)
	_lobby_panel.call("configure", self)


func _open_lobby() -> void:
	_show_screen(Screen.LOBBY)


func _menu_art_button(text: String, callback: Callable, texture: Texture2D, height: float) -> Control:
	var item := Control.new()
	item.custom_minimum_size = Vector2(0.0, height)
	var art := TextureRect.new()
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(40.0, 120.0 if text == "JOUER" else 140.0, 2100.0, 450.0 if text == "JOUER" else 430.0)
	art.texture = cropped
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(art)
	var button := Button.new()
	button.text = text
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_theme_font_size_override("font_size", 26 if text == "JOUER" else 21)
	button.add_theme_font_override("font", MENU_DISPLAY_FONT)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color.TRANSPARENT
	focus_style.border_color = CYAN
	focus_style.set_border_width_all(2)
	focus_style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.05, 0.92))
	button.add_theme_constant_override("outline_size", 2)
	button.pressed.connect(callback)
	var update_art := func() -> void:
		var level := 0.82 if button.button_pressed else 1.15 if button.is_hovered() or button.has_focus() else 1.0
		art.modulate = Color(level, level, level, 1.0)
	for state_signal in [button.mouse_entered, button.mouse_exited, button.focus_entered, button.focus_exited, button.button_down, button.button_up]:
		state_signal.connect(update_art)
	item.add_child(button)
	return item

func _build_equipment() -> void:
	_equipment_panel = Control.new()
	_equipment_panel.name = "EquipmentPanel"
	_equipment_panel.custom_minimum_size = Vector2(1170, 650)
	_equipment_panel.set_meta("navigation_size", Vector2(1170, 650))
	_equipment_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_equipment_panel.position -= Vector2(585, 325)
	_screen_root.add_child(_equipment_panel)
	var frame := TextureRect.new()
	frame.texture = EQUIPMENT_FRAME
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equipment_panel.add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 58)
	margin.add_theme_constant_override("margin_right", 58)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 70)
	_equipment_panel.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 21)
	margin.add_child(columns)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 218
	sidebar.add_theme_constant_override("separation", 11)
	columns.add_child(sidebar)
	sidebar.add_child(_label("FORGE", 25, CREAM))
	var accent := ColorRect.new()
	accent.color = AMBER
	accent.custom_minimum_size = Vector2(38, 3)
	sidebar.add_child(accent)
	for item in EQUIPMENT_CATEGORIES:
		_add_equipment_nav_button(sidebar, str(item.id), str(item.title))
	var divider := ColorRect.new()
	divider.color = Color("#59483b")
	divider.custom_minimum_size.x = 2
	columns.add_child(divider)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	_equipment_category_label = _label("", 21, AMBER)
	right.add_child(_equipment_category_label)
	_equipment_content = HBoxContainer.new()
	_equipment_content.custom_minimum_size.y = 292
	_equipment_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_equipment_content.add_theme_constant_override("separation", 16)
	right.add_child(_equipment_content)
	var preview := PanelContainer.new()
	var preview_style := _panel_style(Color("#15191c"), Color("#69543e"), 5)
	preview_style.content_margin_left = 9
	preview_style.content_margin_right = 9
	preview_style.content_margin_top = 5
	preview_style.content_margin_bottom = 5
	preview.add_theme_stylebox_override("panel", preview_style)
	right.add_child(preview)
	var preview_items := HBoxContainer.new()
	preview_items.add_theme_constant_override("separation", 7)
	preview.add_child(preview_items)
	for item in EQUIPMENT_CATEGORIES:
		_add_equipment_preview(preview_items, str(item.id), str(item.title))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	actions.add_child(_button("RETOUR", Callable(self, "_open_menu"), 204))
	var start := _button("ENTRER DANS L’ARÈNE", Callable(self, "_start_duel"), 340)
	start.add_theme_stylebox_override("normal", _panel_style(Color("#124a53"), CYAN, 5))
	start.add_theme_stylebox_override("hover", _panel_style(Color("#1d606a"), Color.WHITE, 5))
	actions.add_child(start)
	right.add_child(actions)
	_build_equipment_info_bubble()
	_open_equipment_category("robot")

func _build_equipment_info_bubble() -> void:
	_equipment_info_panel = PanelContainer.new()
	_equipment_info_panel.name = "EquipmentInfoBubble"
	_equipment_info_panel.position = Vector2(772, 155)
	_equipment_info_panel.custom_minimum_size.x = 322
	var style := _panel_style(Color("#171b1f"), CYAN, 6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_equipment_info_panel.add_theme_stylebox_override("panel", style)
	_equipment_panel.add_child(_equipment_info_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	_equipment_info_panel.add_child(content)
	_equipment_info_title = _label("", 17, CREAM)
	content.add_child(_equipment_info_title)
	_equipment_info_description = _label("", 13, CREAM)
	content.add_child(_equipment_info_description)
	_equipment_info_stats = _label("", 13, CYAN)
	content.add_child(_equipment_info_stats)
	_equipment_info_panel.visible = false

func _show_equipment_info(identifier: String) -> void:
	if _equipment_info_panel.visible and _equipment_info_id == identifier:
		_equipment_info_panel.visible = false
		_equipment_info_id = ""
		return
	_equipment_info_id = identifier
	_equipment_info_title.text = LOADOUT.display_name(identifier)
	_equipment_info_description.text = LOADOUT.category_description(identifier)
	_equipment_info_stats.text = LOADOUT.stat_line(identifier)
	_equipment_info_panel.visible = true

func _add_equipment_nav_button(parent: VBoxContainer, category: String, title: String) -> void:
	var button := Button.new()
	button.name = "%sTab" % category.to_pascal_case()
	button.custom_minimum_size.y = 61
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 13
	content.offset_right = -12
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(39, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var label := _label(title, 15, CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	button.pressed.connect(func() -> void: _open_equipment_category(category))
	_equipment_nav_buttons[category] = button
	_equipment_nav_icons[category] = icon

func _add_equipment_preview(parent: HBoxContainer, category: String, title: String) -> void:
	var button := EQUIPMENT_CARD.new() as Button
	button.name = "%sPreview" % category.to_pascal_case()
	button.custom_minimum_size = Vector2(0, 76)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 5
	content.offset_bottom = -5
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 1)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var label := _label(title, 10, AMBER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 43)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	button.pressed.connect(func() -> void: _open_equipment_category(category))
	_equipment_preview_buttons[category] = button
	_equipment_preview_icons[category] = icon

func _equipment_options(category: String) -> Array:
	match category:
		"robot": return LOADOUT.ROBOTS
		"weapon": return LOADOUT.WEAPONS
		"offensive": return LOADOUT.OFFENSIVE
		"defensive": return LOADOUT.DEFENSIVE
		"mobility": return LOADOUT.MOBILITY
		"passive": return LOADOUT.PASSIVES
	return []

func _open_equipment_category(category: String) -> void:
	_equipment_category = category
	_equipment_info_panel.visible = false
	_equipment_info_id = ""
	for item in EQUIPMENT_CATEGORIES:
		if str(item.id) == category:
			_equipment_category_label.text = str(item.title)
			break
	for child in _equipment_content.get_children():
		child.free()
	_selection_buttons.clear()
	_selection_markers.clear()
	_selection_buttons[category] = {}
	_selection_markers[category] = {}
	for identifier in _equipment_options(category):
		_add_equipment_choice(category, str(identifier))
	_refresh_equipment()

func _add_equipment_choice(category: String, identifier: String) -> void:
	var button := EQUIPMENT_CARD.new() as Button
	button.name = "%sOption" % identifier.to_pascal_case()
	button.custom_minimum_size = Vector2(0, 292)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = "%s\n%s\n%s" % [LOADOUT.display_name(identifier), LOADOUT.category_description(identifier), LOADOUT.stat_line(identifier)]
	_equipment_content.add_child(button)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12 if category == "robot" else 18
	content.offset_right = -12 if category == "robot" else -18
	content.offset_top = 12 if category == "robot" else 18
	content.offset_bottom = -10 if category == "robot" else -16
	content.add_theme_constant_override("separation", 3 if category == "robot" else 5)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var info := Button.new()
	info.name = "Info"
	info.text = "i"
	info.anchor_left = 1.0
	info.anchor_right = 1.0
	info.offset_left = -37.0
	info.offset_right = -10.0
	info.offset_top = 10.0
	info.offset_bottom = 37.0
	info.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", CYAN)
	var info_style := _panel_style(Color("#17262a"), Color("#638087"), 14)
	info_style.set_content_margin_all(0)
	for state in ["normal", "hover", "pressed", "focus"]:
		info.add_theme_stylebox_override(state, info_style)
	button.add_child(info)
	info.pressed.connect(func() -> void: _show_equipment_info(identifier))
	var icon := TextureRect.new()
	icon.texture = _equipment_icon(identifier)
	# Multi-line module names still need room for the equipped marker inside
	# the card. The expanding image takes the remaining space, without overflow.
	icon.custom_minimum_size.y = 150 if category == "offensive" else 160
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var name_label := _label(LOADOUT.display_name(identifier), 19 if category in ["robot", "offensive"] else 21, CREAM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)
	if category == "robot":
		var definition: Dictionary = COMBAT_DATA.ROBOT_DEFINITIONS[identifier]
		var stats := _label("%d PV  ·  %.1f m/s" % [int(definition.max_health), float(definition.move_speed)], 14, CREAM)
		stats.name = "RobotStats"
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(stats)
	var marker := _label("", 13, CYAN)
	marker.custom_minimum_size.y = 21
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(marker)
	button.pressed.connect(func() -> void:
		loadout[category] = identifier
		LOADOUT.save_local(loadout)
		_equipment_info_panel.visible = false
		_equipment_info_id = ""
		_refresh_equipment()
	)
	_selection_buttons[category][identifier] = button
	_selection_markers[category][identifier] = marker

func _equipment_icon(identifier: String) -> Texture2D:
	return _equipment_icons.get_icon(identifier)

func _equipment_card_style(active: bool, hover: bool = false) -> StyleBoxFlat:
	var background := Color("#123039") if active else Color("#1c1d1f")
	var border := CYAN if active else Color("#8c6745")
	if hover:
		background = Color("#19464e") if active else Color("#2b2825")
		border = Color.WHITE if active else AMBER
	var style := _panel_style(background, border, 5)
	style.set_content_margin_all(0)
	return style

func _refresh_equipment() -> void:
	for item in EQUIPMENT_CATEGORIES:
		var category := str(item.id)
		var chosen := str(loadout.get(category, ""))
		var selected := category == _equipment_category
		var tab: Button = _equipment_nav_buttons[category]
		tab.add_theme_stylebox_override("normal", _equipment_tab_style(selected))
		tab.add_theme_stylebox_override("hover", _equipment_tab_style(true))
		tab.add_theme_stylebox_override("pressed", _equipment_tab_style(true))
		tab.add_theme_stylebox_override("focus", _equipment_tab_style(true))
		(_equipment_nav_icons[category] as TextureRect).texture = _equipment_icon(chosen)
		var preview: Button = _equipment_preview_buttons[category]
		preview.tooltip_text = "%s\n%s\n%s" % [LOADOUT.display_name(chosen), LOADOUT.category_description(chosen), LOADOUT.stat_line(chosen)]
		preview.add_theme_stylebox_override("normal", _equipment_preview_style(selected))
		preview.add_theme_stylebox_override("hover", _equipment_preview_style(true))
		preview.add_theme_stylebox_override("pressed", _equipment_preview_style(true))
		preview.add_theme_stylebox_override("focus", _equipment_preview_style(true))
		(_equipment_preview_icons[category] as TextureRect).texture = _equipment_icon(chosen)
	for category in _selection_buttons.keys():
		for identifier in _selection_buttons[category].keys():
			var button: Button = _selection_buttons[category][identifier]
			var active := str(loadout.get(category, "")) == str(identifier)
			var marker: Label = _selection_markers[category][identifier]
			marker.text = "✓  ÉQUIPÉ" if active else ""
			button.add_theme_stylebox_override("normal", _equipment_card_style(active))
			button.add_theme_stylebox_override("hover", _equipment_card_style(active, true))
			button.add_theme_stylebox_override("pressed", _equipment_card_style(true))
			button.add_theme_stylebox_override("focus", _equipment_card_style(active, true))

func _equipment_tab_style(active: bool) -> StyleBoxFlat:
	var style := _panel_style(Color("#30251e") if active else Color("#1c1c1e"), AMBER if active else Color("#574b43"), 5)
	style.set_content_margin_all(0)
	return style

func _equipment_preview_style(active: bool) -> StyleBoxFlat:
	var style := _panel_style(Color("#123039") if active else Color("#1a1d1f"), CYAN if active else Color("#5b4b3b"), 4)
	style.set_content_margin_all(0)
	return style

func _build_settings() -> void:
	_settings_panel = _center_panel(620, 470)
	_screen_root.add_child(_settings_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_settings_panel.add_child(box)
	box.add_child(_label("RÉGLAGES", 32, CREAM))
	box.add_child(_label("CONFORT ET INTERFACE", 14, CYAN))
	var shake := CheckButton.new()
	shake.name = "CameraShake"
	shake.text = "Secousses de caméra"
	shake.add_theme_font_size_override("font_size", 18)
	shake.add_theme_color_override("font_color", CREAM)
	shake.button_pressed = bool(_settings.camera_shake)
	shake.toggled.connect(func(value: bool) -> void:
		_settings.camera_shake = value
		_save_settings()
		if main != null:
			main.set_meta("camera_shake_enabled", value)
	)
	box.add_child(shake)
	var touch := HSlider.new()
	touch.name = "TouchScale"
	touch.min_value = 0.85
	touch.max_value = 1.15
	touch.step = 0.05
	touch.value = float(_settings.touch_scale)
	touch.tooltip_text = "Taille des contrôles tactiles"
	touch.value_changed.connect(func(value: float) -> void:
		_settings.touch_scale = clampf(value, 0.85, 1.15)
		_save_settings()
		if touch_controls != null and touch_controls.has_method("set_control_scale"):
			touch_controls.call("set_control_scale", _settings.touch_scale)
		_touch_scale_label.text = "Taille des contrôles tactiles  ·  %d %%" % roundi(_settings.touch_scale * 100.0)
	)
	_touch_scale_label = _label("Taille des contrôles tactiles  ·  %d %%" % roundi(_settings.touch_scale * 100.0), 16, CREAM)
	box.add_child(_touch_scale_label)
	box.add_child(touch)
	box.add_child(_label("INTERFACE", 18, CYAN))
	box.add_child(_button("PERSONNALISER L'INTERFACE", Callable(self, "_open_hud_editor"), 300))
	box.add_child(_button("RETOUR", Callable(self, "_open_menu"), 300))

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "CombatHUD"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(_hud)
	var score_panel := Control.new()
	score_panel.name = "MatchSummary"
	score_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_panel.position = Vector2(-230, 12)
	score_panel.size = Vector2(460, 60)
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(score_panel)
	var vitals := Control.new()
	vitals.name = "PlayerVitals"
	vitals.set_script(HUD_VITALS_SCRIPT)
	vitals.position = Vector2(22, 102)
	vitals.size = Vector2(280, 90)
	vitals.call("set_player", player)
	_hud.add_child(vitals)
	var score_backdrop := TextureRect.new()
	score_backdrop.texture = MATCH_SUMMARY_FRAME
	score_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	score_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	score_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	score_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_panel.add_child(score_backdrop)
	_hud_labels.match = _label("0 — 0", 27, CREAM)
	_hud_labels.match.position = Vector2(168, 7)
	_hud_labels.match.size = Vector2(124, 46)
	_hud_labels.match.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_labels.match.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_panel.add_child(_hud_labels.match)
	_hud_labels.match_round = _label("MANCHE 1", 14, CREAM)
	_hud_labels.match_round.position = Vector2(32, 15)
	_hud_labels.match_round.size = Vector2(130, 30)
	_hud_labels.match_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_labels.match_round.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_panel.add_child(_hud_labels.match_round)
	_hud_labels.phase = _label("PRÉPARATION", 13, CYAN)
	_hud_labels.phase.position = Vector2(298, 15)
	_hud_labels.phase.size = Vector2(130, 30)
	_hud_labels.phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_labels.phase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_labels.phase.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hud_labels.phase.clip_text = true
	score_panel.add_child(_hud_labels.phase)
	var pause := _button("Ⅱ", Callable(self, "_toggle_pause"), 44)
	pause.name = "PauseButton"
	pause.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-58, 18)
	pause.custom_minimum_size = Vector2(44, 44)
	pause.tooltip_text = "Pause (Échap)"
	pause.add_theme_font_size_override("font_size", 20)
	var pause_style := _panel_style(Color("#211c1c"), Color("#a87a50"), 6)
	pause_style.set_content_margin_all(0)
	pause.add_theme_stylebox_override("normal", pause_style)
	_hud.add_child(pause)
	var spell_frame := Control.new()
	spell_frame.name = "SpellBar"
	spell_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spell_frame.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spell_frame.offset_left = -284.0
	spell_frame.offset_top = -82.0
	spell_frame.offset_right = 284.0
	spell_frame.offset_bottom = -10.0
	_hud.add_child(spell_frame)
	var spell_slots := [
		{"id": "offensive", "key": "A"},
		{"id": "defensive", "key": "E"},
		{"id": "mobility", "key": "R"},
	]
	for index in range(3):
		var slot: Dictionary = spell_slots[index]
		var module_id: String = slot["id"]
		var slot_content := Control.new()
		slot_content.name = "%sSlot" % module_id.capitalize()
		slot_content.position = Vector2(float(index) * 192.0, 0.0)
		slot_content.size = Vector2(184.0, 72.0)
		slot_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spell_frame.add_child(slot_content)
		var slot_backdrop := TextureRect.new()
		slot_backdrop.texture = SPELL_BAR_FRAME
		slot_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
		slot_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_content.add_child(slot_backdrop)
		var placeholder := TextureRect.new()
		placeholder.position = Vector2(13.0, 12.0)
		placeholder.size = Vector2(42.0, 48.0)
		placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		placeholder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_content.add_child(placeholder)
		_hud_labels["%s_icon" % module_id] = placeholder
		var cooldown_ring := Control.new()
		cooldown_ring.name = "CooldownRing"
		cooldown_ring.set_script(COOLDOWN_RING)
		cooldown_ring.position = Vector2(10.0, 9.0)
		cooldown_ring.size = Vector2(48.0, 54.0)
		cooldown_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_content.add_child(cooldown_ring)
		_hud_labels["%s_ring" % module_id] = cooldown_ring
		var key_label := _label(str(slot["key"]), 13, AMBER)
		key_label.position = Vector2(63.0, 9.0)
		key_label.size = Vector2(23.0, 23.0)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_content.add_child(key_label)
		var module_label := _label("", 11, CREAM)
		module_label.position = Vector2(88.0, 9.0)
		module_label.size = Vector2(89.0, 23.0)
		module_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		module_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		module_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		module_label.clip_text = true
		module_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_content.add_child(module_label)
		_hud_labels[module_id] = module_label
		var status := _label("", 13, CYAN)
		status.position = Vector2(63.0, 39.0)
		status.size = Vector2(112.0, 22.0)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_content.add_child(status)
		_hud_labels["%s_status" % module_id] = status
		if module_id == "offensive":
			var recast_frame := Panel.new()
			recast_frame.name = "JavelinRecastFrame"
			recast_frame.position = Vector2(10.0, 9.0)
			recast_frame.size = Vector2(48.0, 54.0)
			recast_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var frame_style := StyleBoxFlat.new()
			frame_style.bg_color = Color.TRANSPARENT
			frame_style.border_color = Color("#efb765", 0.8)
			frame_style.set_border_width_all(1)
			frame_style.set_corner_radius_all(4)
			recast_frame.add_theme_stylebox_override("panel", frame_style)
			recast_frame.visible = false
			slot_content.add_child(recast_frame)
			_hud_labels.offensive_recast_frame = recast_frame
			var recast_track := ColorRect.new()
			recast_track.name = "JavelinRecastTrack"
			recast_track.position = Vector2(12.0, 66.0)
			recast_track.size = Vector2(160.0, 3.0)
			recast_track.color = Color("#5f4737")
			recast_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
			recast_track.visible = false
			slot_content.add_child(recast_track)
			_hud_labels.offensive_recast_track = recast_track
			var recast_fill := ColorRect.new()
			recast_fill.name = "JavelinRecastFill"
			recast_fill.color = AMBER
			recast_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			recast_track.add_child(recast_fill)
			_hud_labels.offensive_recast_fill = recast_fill
	var dev := _label("", 12, Color(1, 1, 1, 0.45))
	dev.position = Vector2(22, 140)
	dev.name = "DevDiagnostics"
	dev.visible = false
	_hud.add_child(dev)
	_hud_labels.dev = dev
	_build_countdown_overlay()

func _build_countdown_overlay() -> void:
	_countdown_overlay = Control.new()
	_countdown_overlay.name = "CountdownOverlay"
	_countdown_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(_countdown_overlay)
	_countdown_dim = ColorRect.new()
	_countdown_dim.color = Color(0.04, 0.04, 0.06, 0.52)
	_countdown_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_overlay.add_child(_countdown_dim)
	_countdown_glow = TextureRect.new()
	_countdown_glow.name = "CountdownGlow"
	_countdown_glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_glow.offset_left = -230
	_countdown_glow.offset_top = -230
	_countdown_glow.offset_right = 230
	_countdown_glow.offset_bottom = 230
	_countdown_glow.pivot_offset = Vector2(230, 230)
	_countdown_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_countdown_glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_countdown_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_overlay.add_child(_countdown_glow)
	_countdown_image = TextureRect.new()
	_countdown_image.name = "CountdownDigit"
	_countdown_image.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_image.offset_left = -230
	_countdown_image.offset_top = -230
	_countdown_image.offset_right = 230
	_countdown_image.offset_bottom = 230
	_countdown_image.pivot_offset = Vector2(230, 230)
	_countdown_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_countdown_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_countdown_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_overlay.add_child(_countdown_image)
	_countdown_overlay.visible = false

func _update_countdown_overlay() -> void:
	if _countdown_overlay == null:
		return
	var showing_intro := round_phase == RoundPhase.COUNTDOWN or round_phase == RoundPhase.FIGHT
	if current_screen == Screen.COMBAT and round_phase in [RoundPhase.COUNTDOWN, RoundPhase.FIGHT, RoundPhase.LIVE]:
		_hud.visible = not showing_intro
	_countdown_overlay.visible = current_screen == Screen.COMBAT and not _pause_active and showing_intro
	if not _countdown_overlay.visible:
		return
	if round_phase == RoundPhase.FIGHT:
		if _countdown_digit_index != 3:
			_countdown_digit_index = 3
			_set_countdown_sprite(FIGHT_IMAGE, Vector2(900, 390))
			_play_countdown_sound(FIGHT_SOUND)
		var fight_beat := 1.0 - _fight_remaining / FIGHT_SECONDS
		var fight_impact := 1.0 - pow(1.0 - clampf(fight_beat / 0.28, 0.0, 1.0), 3.0)
		var fight_opacity := clampf(fight_beat / 0.07, 0.0, 1.0) * clampf((1.0 - fight_beat) / 0.26, 0.0, 1.0)
		_countdown_image.scale = Vector2.ONE * lerpf(1.45, 1.0, fight_impact)
		_countdown_image.rotation_degrees = 0.0
		_countdown_image.modulate.a = fight_opacity
		_countdown_glow.scale = _countdown_image.scale * 1.06
		_countdown_glow.modulate = Color(CYAN.r, CYAN.g, CYAN.b, fight_opacity * 0.35)
		_countdown_dim.modulate.a = 0.55 + 0.45 * fight_opacity
		return
	var number := ceili(_countdown_remaining)
	var index := clampi(3 - number, 0, 2)
	if index != _countdown_digit_index:
		_countdown_digit_index = index
		_set_countdown_sprite(COUNTDOWN_DIGITS[index], Vector2(460, 460))
		_play_countdown_sound(COUNTDOWN_SOUNDS[index])
	var beat := 1.0 - (_countdown_remaining - float(number - 1))
	var impact := 1.0 - pow(1.0 - clampf(beat / 0.22, 0.0, 1.0), 3.0)
	var settle := clampf((beat - 0.22) / 0.20, 0.0, 1.0)
	var scale_value := lerpf(1.58, 0.92, impact) if beat < 0.22 else lerpf(0.92, 1.0, settle)
	var opacity := clampf(beat / 0.08, 0.0, 1.0) * clampf((1.0 - beat) / 0.20, 0.0, 1.0)
	_countdown_image.scale = Vector2.ONE * scale_value
	_countdown_image.rotation_degrees = lerpf(-5.0 if index % 2 == 0 else 5.0, 0.0, impact)
	_countdown_image.modulate.a = opacity
	_countdown_glow.scale = Vector2.ONE * (scale_value + 0.08)
	_countdown_glow.modulate = Color(CYAN.r, CYAN.g, CYAN.b, opacity * (0.18 + 0.20 * (1.0 - impact)))
	_countdown_dim.modulate.a = 0.65 + 0.35 * opacity

func _set_countdown_sprite(texture: Texture2D, dimensions: Vector2) -> void:
	for sprite in [_countdown_glow, _countdown_image]:
		sprite.texture = texture
		sprite.offset_left = -dimensions.x * 0.5
		sprite.offset_top = -dimensions.y * 0.5
		sprite.offset_right = dimensions.x * 0.5
		sprite.offset_bottom = dimensions.y * 0.5
		sprite.pivot_offset = dimensions * 0.5

func _play_countdown_sound(sound: AudioStream) -> void:
	_countdown_audio.stop()
	_countdown_audio.stream = sound
	_countdown_audio.play()

func _set_menu_music_active(active: bool) -> void:
	if _menu_music_active == active or _menu_music.stream == null:
		return
	_menu_music_active = active
	if _menu_music_tween != null:
		_menu_music_tween.kill()
	_menu_music_tween = create_tween()
	if active:
		if not _menu_music.playing:
			_menu_music.volume_db = -60.0
			_menu_music.play()
		_menu_music_tween.tween_property(_menu_music, "volume_db", MENU_MUSIC_VOLUME_DB, 0.8)
	else:
		_menu_music_tween.tween_property(_menu_music, "volume_db", -60.0, 0.45)
		_menu_music_tween.tween_callback(_menu_music.stop)

func _start_match_music() -> void:
	if _match_music.stream == null:
		return
	_match_music.stop()
	_match_music.stream_paused = false
	_match_music.play()

func _stop_match_music() -> void:
	_match_music.stop()

func _build_pause() -> void:
	_pause_panel = _center_panel(430, 310)
	_screen_root.add_child(_pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_pause_panel.add_child(box)
	box.add_child(_label("PAUSE", 32, CREAM))
	_hud_labels.pause_status = _label("", 14, MUTED)
	box.add_child(_hud_labels.pause_status)
	box.add_child(_button("REPRENDRE", Callable(self, "_resume"), 300))
	box.add_child(_button("PERSONNALISER L'INTERFACE", Callable(self, "_open_hud_editor"), 300))
	box.add_child(_button("RECOMMENCER", Callable(self, "_restart"), 300))
	box.add_child(_button("RETOUR AU MENU", Callable(self, "_return_menu"), 300))

func _build_winner_transition() -> void:
	_transition_dim = ColorRect.new()
	_transition_dim.name = "WinnerTransition"
	_transition_dim.color = Color("#090b10")
	_transition_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_dim.visible = false
	_transition_dim.modulate.a = 0.0
	_screen_root.add_child(_transition_dim)


func _build_result() -> void:
	_result_panel = _center_panel(560, 390)
	_screen_root.add_child(_result_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 15)
	_result_panel.add_child(box)
	_hud_labels.result_title = _label("", 40, CREAM)
	_hud_labels.result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hud_labels.result_title)
	_hud_labels.result_detail = _label("", 16, MUTED)
	_hud_labels.result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hud_labels.result_detail)
	var replay := _button("REJOUER", Callable(self, "_restart"), 340)
	var equipment := _button("MODIFIER L’ÉQUIPEMENT", Callable(self, "_open_equipment"), 340)
	var menu := _button("RETOUR AU MENU", Callable(self, "_return_menu"), 340)
	_result_actions = [replay, equipment, menu]
	box.add_child(replay)
	box.add_child(equipment)
	box.add_child(menu)

func _update_hud() -> void:
	if player == null or target == null:
		return
	_hud_labels.match.text = "%d — %d" % [player_round_score, bot_round_score]
	_hud_labels.match_round.text = "MANCHE %d" % maxi(1, round_number)
	_hud_labels.phase.text = _phase_text()
	_hud_labels.phase.add_theme_color_override("font_color", AMBER if round_phase == RoundPhase.COUNTDOWN else CYAN)
	var spell_modules := {
		"offensive": str(player.call("get_offensive_module_id")),
		"defensive": str(player.call("get_defensive_module_id")),
		"mobility": str(player.call("get_mobility_module_id")),
	}
	if not _pause_active:
		_javelin_recast_display_fraction = float(player.call("get_javelin_recast_fraction"))
	for key in spell_modules.keys():
		var identifier: String = spell_modules[key]
		var cooldown := float(player.call("get_module_cooldown", identifier))
		_hud_labels[key].text = LOADOUT.display_name(identifier)
		_hud_labels["%s_icon" % key].texture = _equipment_icons.get_icon(identifier)
		var recast_active: bool = key == "offensive" and identifier == "javelin" and _javelin_recast_display_fraction > 0.0
		var fulguro_charging: bool = key == "offensive" and identifier == "fulguro_punch" and player.has_method("is_fulguro_charging") and bool(player.call("is_fulguro_charging"))
		var fulguro_charge := float(player.call("get_fulguro_charge_fraction")) if fulguro_charging else 0.0
		var pelto_preparing: bool = key == "offensive" and identifier == "pelto_smash" and player.has_method("is_pelto_preparing") and bool(player.call("is_pelto_preparing"))
		var pelto_preparation := float(player.call("get_pelto_preparation_fraction")) if pelto_preparing else 0.0
		var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get(identifier, {})
		_hud_labels["%s_ring" % key].set_cooldown(0.0 if fulguro_charging or pelto_preparing else cooldown, float(definition.get("cooldown", 1.0)), recast_active)
		if key == "offensive":
			_hud_labels.offensive_recast_frame.visible = recast_active
			_hud_labels.offensive_recast_track.visible = recast_active
			if recast_active:
				_hud_labels.offensive_recast_fill.size = Vector2(160.0 * _javelin_recast_display_fraction, 3.0)
		if recast_active:
			_hud_labels["%s_status" % key].text = "A →"
			_hud_labels["%s_status" % key].add_theme_color_override("font_color", AMBER)
			_hud_labels[key].add_theme_color_override("font_color", CREAM)
			_hud_labels["%s_icon" % key].texture = JAVELIN_RECAST_ICON
			_hud_labels["%s_icon" % key].modulate = Color.WHITE
		elif fulguro_charging:
			_hud_labels["%s_status" % key].text = "CHARGE %d%%" % int(round(fulguro_charge * 100.0))
			_hud_labels["%s_status" % key].add_theme_color_override("font_color", Color("#ffb34f"))
			_hud_labels[key].add_theme_color_override("font_color", Color("#fff0b0"))
			_hud_labels["%s_icon" % key].modulate = Color("#ffcb78")
		elif pelto_preparing:
			_hud_labels["%s_status" % key].text = "FRAPPE %d%%" % int(round(pelto_preparation * 100.0))
			_hud_labels["%s_status" % key].add_theme_color_override("font_color", Color("#d9a060"))
			_hud_labels[key].add_theme_color_override("font_color", Color("#f4d4a2"))
			_hud_labels["%s_icon" % key].modulate = Color("#e3b06e")
		elif cooldown > 0.0:
			_hud_labels["%s_status" % key].text = "%.1f s" % cooldown
			_hud_labels["%s_status" % key].add_theme_color_override("font_color", CYAN)
			_hud_labels[key].add_theme_color_override("font_color", CREAM)
			_hud_labels["%s_icon" % key].modulate = Color("#b7aaa0")
		else:
			_hud_labels["%s_status" % key].text = "PRÊT"
			_hud_labels["%s_status" % key].add_theme_color_override("font_color", CYAN)
			_hud_labels[key].add_theme_color_override("font_color", CREAM)
			_hud_labels["%s_icon" % key].modulate = Color.WHITE

func _effects_text(actor: Node) -> String:
	var effects: Array = actor.call("get_active_effect_types")
	return "ÉTATS : " + (" / ".join(effects) if not effects.is_empty() else "—")

func _phase_text() -> String:
	match round_phase:
		RoundPhase.COUNTDOWN:
			return ""
		RoundPhase.FIGHT:
			return "FIGHT"
		RoundPhase.LIVE:
			return "COMBAT"
		RoundPhase.WINNER_FOCUS:
			return ""
		RoundPhase.ROUND_RESULT:
			return "FIN DE MANCHE"
		RoundPhase.MATCH_RESULT:
			return "FIN DU MATCH"
		_:
			return "PRÉPARATION"


func get_match_score() -> Vector2i:
	return Vector2i(player_round_score, bot_round_score)


func get_round_phase_name() -> String:
	return RoundPhase.keys()[round_phase]

func _open_menu() -> void:
	_end_pause(false)
	_countdown_audio.stop()
	_stop_match_music()
	round_phase = RoundPhase.IDLE
	if main != null and main.has_method("stop_duel"):
		main.call("stop_duel")
	if main != null and main.has_method("reset_round_camera"):
		main.call("reset_round_camera")
	_show_screen(Screen.MENU)

func _open_equipment() -> void:
	_end_pause(false)
	if round_phase == RoundPhase.MATCH_RESULT:
		round_phase = RoundPhase.IDLE
		if main != null and main.has_method("stop_duel"):
			main.call("stop_duel")
	loadout = LOADOUT.sanitize(loadout)
	_show_screen(Screen.EQUIPMENT)

func _open_settings() -> void:
	_show_screen(Screen.SETTINGS)

func _setup_hud_editor() -> void:
	_hud_controller = Node.new()
	_hud_controller.name = "HudLayoutController"
	_hud_controller.set_script(HUD_CONTROLLER)
	add_child(_hud_controller)
	_hud_controller.bind_touch(touch_controls as Control)
	_hud_controller.register("match_summary", _hud.get_node("MatchSummary"))
	_hud_controller.register("player_vitals", _hud.get_node("PlayerVitals"))
	_hud_controller.register("pause", _hud.get_node("PauseButton"))
	_hud_controller.register("spell_bar", _hud.get_node("SpellBar"))
	for category in ["offensive", "defensive", "mobility"]:
		_hud_controller.register("%s_slot" % category, _hud.get_node("SpellBar/%sSlot" % category.capitalize()))
	_hud_editor = Control.new()
	_hud_editor.name = "HudEditor"
	_hud_editor.set_script(HUD_EDITOR)
	add_child(_hud_editor)
	_hud_editor.saved.connect(_on_hud_saved)
	_hud_editor.closed.connect(_on_hud_editor_closed)
	_hud_editor.test_started.connect(_on_hud_test_started)
	_hud_editor.test_finished.connect(_on_hud_test_finished)

func _open_hud_editor() -> void:
	if _hud_editor == null or _hud_editor.visible:
		return
	_editor_from_pause = _pause_active
	if touch_controls != null and touch_controls.has_method("reset_inputs"):
		touch_controls.call("reset_inputs")
	if _editor_from_pause:
		_pause_panel.visible = false
	else:
		_settings_panel.visible = false
		if main != null and main.has_method("set_menu_showcase_enabled"):
			main.call("set_menu_showcase_enabled", false)
	_hud.visible = true
	_update_hud()
	if not _editor_from_pause:
		_hud_labels.match.text = "1 — 2"
		_hud_labels.match_round.text = "MANCHE 3"
		_hud_labels.phase.text = "COMBAT"
		_hud.get_node("PlayerVitals").call("set_example", true)
		_hud_labels.defensive_status.text = "2.4 s"
	_hud_editor.begin(_hud_controller)

func _on_hud_saved(_layout: Dictionary) -> void:
	_hud_controller.apply()

func _on_hud_editor_closed() -> void:
	_hud.get_node("PlayerVitals").call("set_example", false)
	if _editor_from_pause:
		_pause_panel.visible = true
		get_tree().paused = true
	else:
		_hud.visible = false
		_settings_panel.visible = true
		if main != null and main.has_method("set_menu_mode"):
			main.call("set_menu_mode", true)
	if touch_controls != null:
		touch_controls.visible = _editor_from_pause and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested())

func _on_hud_test_started() -> void:
	_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editor_test_started_msec = Time.get_ticks_msec()
	_editor_original_player = player
	_editor_player_process_mode = player.process_mode
	_editor_target_process_mode = target.process_mode
	_editor_test_target_position = (target as Node3D).global_position
	_editor_test_target_enabled = bool(target.call("is_training_bot_enabled"))
	_editor_existing_fx.clear()
	for group in ["prototype0_gameplay_projectiles", "prototype0_fx_budget"]:
		for node in get_tree().get_nodes_in_group(group):
			_editor_existing_fx[node.get_instance_id()] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	(player as Node3D).visible = false
	(target as Node3D).global_position = Vector3(5000, 0, 5000)
	target.call("set_training_bot_enabled", false)
	target.process_mode = Node.PROCESS_MODE_DISABLED
	_editor_trial_player = CharacterBody3D.new()
	_editor_trial_player.name = "HudTrialPlayer"
	_editor_trial_player.set_script(TRIAL_PLAYER_SCRIPT)
	_editor_trial_player.position = (player as Node3D).global_position if _editor_from_pause else Vector3.ZERO
	main.add_child(_editor_trial_player)
	_editor_trial_player.call("apply_loadout", loadout)
	_editor_trial_player.call("set_training_options", true, false, true)
	_editor_trial_player.call("set_gameplay_enabled", true)
	_editor_trial_target = StaticBody3D.new()
	_editor_trial_target.name = "HudTrialTarget"
	_editor_trial_target.set_script(TRIAL_DUMMY_SCRIPT)
	_editor_trial_target.position = _editor_trial_player.position + Vector3(5, 0, -5)
	main.add_child(_editor_trial_target)
	player = _editor_trial_player
	touch_controls.call("set_player", _editor_trial_player)
	_hud.get_node("PlayerVitals").call("set_player", player)
	_hud.get_node("PlayerVitals").call("set_example", false)
	var rig := main.get_node_or_null("CameraRig")
	if rig != null:
		rig.call("set_target", _editor_trial_player)
	get_tree().paused = false
	_hud.visible = true
	_update_hud()

func _on_hud_test_finished() -> void:
	_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE if current_screen == Screen.COMBAT else Control.MOUSE_FILTER_STOP
	if touch_controls != null:
		touch_controls.call("reset_inputs")
	if _editor_trial_player != null and is_instance_valid(_editor_trial_player):
		_editor_trial_player.call("set_gameplay_enabled", false)
		_editor_trial_player.queue_free()
	_editor_trial_player = null
	if _editor_trial_target != null and is_instance_valid(_editor_trial_target):
		_editor_trial_target.queue_free()
	_editor_trial_target = null
	for group in ["prototype0_gameplay_projectiles", "prototype0_fx_budget"]:
		for node in get_tree().get_nodes_in_group(group):
			if _editor_existing_fx.has(node.get_instance_id()):
				node.process_mode = _editor_existing_fx[node.get_instance_id()]
			else:
				node.queue_free()
	_editor_existing_fx.clear()
	player = _editor_original_player
	touch_controls.call("set_player", player)
	_hud.get_node("PlayerVitals").call("set_player", player)
	_hud.get_node("PlayerVitals").call("set_example", not _editor_from_pause)
	(player as Node3D).visible = true
	player.process_mode = _editor_player_process_mode
	(target as Node3D).global_position = _editor_test_target_position
	target.call("set_training_bot_enabled", _editor_test_target_enabled)
	target.process_mode = _editor_target_process_mode
	var rig := main.get_node_or_null("CameraRig")
	if rig != null:
		rig.call("set_target", player)
	if _editor_from_pause:
		get_tree().paused = true
	else:
		main.call("set_menu_mode", true)
	_hud.visible = true
	_update_hud()

func _open_training_ground() -> void:
	_end_pause(false)
	_stop_match_music()
	get_tree().change_scene_to_file("res://scenes/training_ground.tscn")

func _open_survival() -> void:
	_end_pause(false)
	_stop_match_music()
	get_tree().change_scene_to_file("res://scenes/survival.tscn")

func _start_duel() -> void:
	loadout = LOADOUT.sanitize(loadout)
	LOADOUT.save_local(loadout)
	match_id += 1
	player_round_score = 0
	bot_round_score = 0
	round_number = 1
	_round_resolved = false
	result_text = ""
	round_phase = RoundPhase.COUNTDOWN
	if main != null and main.has_method("start_duel"):
		main.call("start_duel", loadout)
	_show_screen(Screen.COMBAT)
	_begin_round_countdown()
	_start_match_music()

func on_actor_died(actor: Node) -> void:
	if _round_resolved or current_screen != Screen.COMBAT or round_phase != RoundPhase.LIVE:
		return
	if main != null:
		main.call_deferred("resolve_round")

func resolve_round(player_dead: bool, target_dead: bool) -> void:
	if _round_resolved or round_phase != RoundPhase.LIVE:
		return
	_round_resolved = true
	_round_result_player_dead = player_dead
	_round_result_bot_dead = target_dead
	if player_dead and target_dead:
		result_text = "ÉGALITÉ"
	elif target_dead:
		result_text = "VICTOIRE"
		player_round_score += 1
	else:
		result_text = "DÉFAITE"
		bot_round_score += 1
	_round_result_remaining = 0.0
	_hud_labels.result_title.text = result_text
	_hud_labels.result_title.add_theme_color_override("font_color", GREEN if result_text == "VICTOIRE" else RED if result_text == "DÉFAITE" else AMBER)
	_hud_labels.result_detail.text = "Score %d — %d • équipement conservé : %s" % [player_round_score, bot_round_score, LOADOUT.display_name(str(loadout.weapon))]
	_set_result_actions_visible(false)
	_hud.visible = false
	_result_panel.visible = false
	if touch_controls != null:
		touch_controls.visible = false
	if main != null and main.has_method("stop_duel"):
		main.call("stop_duel")
	if player_dead == target_dead:
		_show_round_result()
	else:
		round_phase = RoundPhase.WINNER_FOCUS
		_winner_focus_remaining = WINNER_FOCUS_SECONDS
		_transition_dim.visible = true
		_transition_dim.modulate.a = 0.0
		if main != null and main.has_method("focus_round_winner"):
			main.call("focus_round_winner", target_dead)


func _show_round_result() -> void:
	round_phase = RoundPhase.ROUND_RESULT
	_round_result_remaining = 2.0
	_transition_release_remaining = 0.35 if _transition_dim.visible else 0.0
	_hud.visible = true
	_result_panel.visible = true
	_update_round_result_label()


func _begin_round_countdown() -> void:
	round_phase = RoundPhase.COUNTDOWN
	_countdown_remaining = COUNTDOWN_SECONDS
	_fight_remaining = 0.0
	_countdown_digit_index = -1
	_countdown_audio.stop()
	_round_resolved = false
	_result_panel.visible = false
	_transition_dim.visible = false
	_transition_dim.modulate.a = 0.0
	_transition_release_remaining = 0.0
	_set_result_actions_visible(false)
	if main != null and main.has_method("prepare_round"):
		main.call("prepare_round", loadout)
	if main != null and main.has_method("set_menu_mode"):
		main.call("set_menu_mode", false)
	if touch_controls != null:
		touch_controls.visible = false
	_update_countdown_overlay()


func _begin_fight() -> void:
	if round_phase != RoundPhase.COUNTDOWN:
		return
	round_phase = RoundPhase.FIGHT
	_countdown_remaining = 0.0
	_fight_remaining = FIGHT_SECONDS
	_update_countdown_overlay()


func _begin_live_round() -> void:
	if round_phase != RoundPhase.COUNTDOWN and round_phase != RoundPhase.FIGHT:
		return
	round_phase = RoundPhase.LIVE
	_countdown_remaining = 0.0
	_fight_remaining = 0.0
	if main != null and main.has_method("activate_round"):
		main.call("activate_round")
	if touch_controls != null:
		touch_controls.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested()
	_update_countdown_overlay()


func _start_next_round() -> void:
	if round_phase != RoundPhase.ROUND_RESULT:
		return
	if player_round_score >= 3 or bot_round_score >= 3:
		_show_final_result()
		return
	round_number += 1
	_round_result_remaining = 0.0
	_result_panel.visible = false
	_begin_round_countdown()


func _show_final_result() -> void:
	if round_phase == RoundPhase.MATCH_RESULT:
		return
	_stop_match_music()
	_set_menu_music_active(false)
	_countdown_audio.stop()
	_result_audio.stream = VICTORY_SOUND if player_round_score >= 3 else DEFEAT_SOUND
	_result_audio.play()
	round_phase = RoundPhase.MATCH_RESULT
	current_screen = Screen.RESULT
	_round_resolved = true
	_result_panel.visible = true
	_hud.visible = false
	_navigation_backdrop.visible = true
	if touch_controls != null:
		touch_controls.visible = false
	_set_result_actions_visible(true)
	_result_actions[0].grab_focus()
	_hud_labels.result_title.text = "MATCH GAGNÉ" if player_round_score >= 3 else "MATCH PERDU"
	_hud_labels.result_title.add_theme_color_override("font_color", GREEN if player_round_score >= 3 else RED)
	_hud_labels.result_detail.text = "Score final  %d — %d" % [player_round_score, bot_round_score]
	if main != null and main.has_method("set_menu_mode"):
		main.call("set_menu_mode", true)


func _update_round_result_label() -> void:
	if not _hud_labels.has("result_detail") or round_phase != RoundPhase.ROUND_RESULT:
		return
	_hud_labels.result_detail.text = "%s\nScore %d — %d\nProchaine manche dans %.1f s" % [result_text, player_round_score, bot_round_score, _round_result_remaining]


func _set_result_actions_visible(visible: bool) -> void:
	for control in _result_actions:
		if control != null and is_instance_valid(control):
			control.visible = visible

func _toggle_pause() -> void:
	if current_screen != Screen.COMBAT or round_phase == RoundPhase.IDLE or round_phase == RoundPhase.MATCH_RESULT:
		return
	if _pause_active:
		_resume()
	else:
		_pause_active = true
		_pause_started_msec = Time.get_ticks_msec()
		if player != null and player.has_method("reset_desktop_inputs"):
			player.call("reset_desktop_inputs")
		if touch_controls != null and touch_controls.has_method("reset_inputs"):
			touch_controls.call("reset_inputs")
		get_tree().paused = true
		_countdown_audio.stream_paused = true
		_match_music.stream_paused = true
		_set_combat_audio_paused(true)
		if touch_controls != null:
			touch_controls.visible = false
		_navigation_backdrop.visible = true
		_pause_panel.visible = true
		_layout_navigation_panels.call_deferred()
		_update_countdown_overlay()

func _resume() -> void:
	_end_pause(true)

func _end_pause(resume_game: bool) -> void:
	if not _pause_active:
		get_tree().paused = false
		_pause_panel.visible = false
		return
	var elapsed := float(Time.get_ticks_msec() - _pause_started_msec) / 1000.0
	_pause_active = false
	_pause_panel.visible = false
	get_tree().paused = false
	_countdown_audio.stream_paused = false
	_match_music.stream_paused = false
	_set_combat_audio_paused(false)
	if current_screen == Screen.COMBAT:
		_navigation_backdrop.visible = false
	if not resume_game:
		_countdown_audio.stop()
	if resume_game and round_phase == RoundPhase.LIVE and main != null and main.has_method("shift_pause_timers"):
		main.call("shift_pause_timers", elapsed)
	if touch_controls != null and touch_controls.has_method("reset_inputs"):
		touch_controls.call("reset_inputs")
		if resume_game and current_screen == Screen.COMBAT and round_phase == RoundPhase.LIVE:
			touch_controls.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested()
	_update_countdown_overlay()

func _set_combat_audio_paused(value: bool) -> void:
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null and sfx.has_method("set_paused"):
		sfx.call("set_paused", value)

func _update_pause_labels() -> void:
	if _hud_labels.has("pause_status"):
		_hud_labels.pause_status.text = "La manche est suspendue."

func _restart() -> void:
	_end_pause(false)
	match_id += 1
	player_round_score = 0
	bot_round_score = 0
	round_number = 1
	_round_resolved = false
	result_text = ""
	if main != null and main.has_method("start_duel"):
		main.call("start_duel", loadout)
	_show_screen(Screen.COMBAT)
	_begin_round_countdown()
	_start_match_music()

func _return_menu() -> void:
	_end_pause(false)
	_countdown_audio.stop()
	_stop_match_music()
	_round_resolved = false
	round_phase = RoundPhase.IDLE
	if main != null and main.has_method("stop_duel"):
		main.call("stop_duel")
	if main != null and main.has_method("reset_round_camera"):
		main.call("reset_round_camera")
	_show_screen(Screen.MENU)
