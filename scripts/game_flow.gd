class_name PrototypeGameFlow
extends CanvasLayer

## Navigation, loadout, HUD and round presentation. Combat remains in Player,
## TargetDummy and the existing state objects.

const LOADOUT := preload("res://scripts/loadout_state.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")

enum Screen { MENU, EQUIPMENT, SETTINGS, COMBAT, RESULT }

var main: Node
var player: Node
var target: Node
var touch_controls: Node
var current_screen := Screen.MENU
var loadout: Dictionary = LOADOUT.defaults()
var result_text := ""
var _round_resolved := false
var _pause_active := false
var _pause_started_msec := 0
var _settings: Dictionary = {"camera_shake": true, "touch_scale": 1.0}
var _screen_root: Control
var _hud: Control
var _menu_panel: PanelContainer
var _equipment_panel: PanelContainer
var _title_label: Label
var _status_label: Label
var _equipment_content: VBoxContainer
var _selection_buttons: Dictionary = {}
var _hud_labels: Dictionary = {}
var _pause_panel: PanelContainer
var _result_panel: PanelContainer
var _settings_panel: PanelContainer

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if touch_controls != null and touch_controls.has_method("set_control_scale"):
		touch_controls.call("set_control_scale", _settings.touch_scale)
	_show_screen(Screen.MENU)

func _process(_delta: float) -> void:
	if current_screen == Screen.COMBAT:
		_update_hud()
	if _pause_active:
		_update_pause_labels()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if current_screen == Screen.COMBAT:
			_toggle_pause()
		elif current_screen == Screen.SETTINGS:
			_show_screen(Screen.MENU)

func _build_ui() -> void:
	_screen_root = Control.new()
	_screen_root.name = "FlowRoot"
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen_root)
	_build_menu()
	_build_equipment()
	_build_settings()
	_build_hud()
	_build_pause()
	_build_result()

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
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item

func _button(text: String, callback: Callable, width := 280.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 48)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(PANEL_ALT, Color("#594649"), 8))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#49383c"), CYAN, 8))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("#1d555b"), CYAN, 8))
	button.add_theme_stylebox_override("focus", _panel_style(Color("#49383c"), CYAN, 8))
	button.pressed.connect(callback)
	return button

func _center_panel(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, height)
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL, Color("#705057"), 14))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position -= Vector2(width, height) * 0.5
	return panel

func _clear_screen() -> void:
	for child in _screen_root.get_children():
		child.visible = false

func _show_screen(screen: Screen) -> void:
	current_screen = screen
	_clear_screen()
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
		Screen.COMBAT:
			_hud.visible = true
			if touch_controls != null:
				touch_controls.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or _touch_preview_requested()
		Screen.RESULT:
			_result_panel.visible = true
		_:
			if touch_controls != null:
				touch_controls.visible = false
	if main != null and main.has_method("set_menu_mode"):
		main.call("set_menu_mode", screen != Screen.COMBAT)

func _touch_preview_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "touch_preview":
			return true
	return false

func _build_menu() -> void:
	_menu_panel = _center_panel(560, 430)
	_screen_root.add_child(_menu_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_menu_panel.add_child(box)
	_title_label = _label("PROTOTYPE 0", 42, CREAM)
	box.add_child(_title_label)
	var subtitle := _label("DUEL DE ROBOTS  •  ARÈNE LOCALE", 16, CYAN)
	box.add_child(subtitle)
	box.add_child(_label("Un combat 1v1 contre un bot. Choisis ton équipement puis entre dans l’arène.", 18, MUTED))
	box.add_child(Control.new())
	box.add_child(_button("JOUER", Callable(self, "_open_equipment"), 400))
	box.add_child(_button("RÉGLAGES", Callable(self, "_open_settings"), 400))
	var hint := _label("Souris / clavier ou contrôles tactiles • version prototype", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

func _build_equipment() -> void:
	_equipment_panel = _center_panel(1000, 640)
	_equipment_panel.name = "EquipmentPanel"
	_screen_root.add_child(_equipment_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_equipment_panel.add_child(outer)
	outer.add_child(_label("ÉQUIPEMENT", 32, CREAM))
	outer.add_child(_label("Un choix par catégorie • les valeurs viennent des données de combat", 14, MUTED))
	_equipment_content = VBoxContainer.new()
	_equipment_content.add_theme_constant_override("separation", 7)
	outer.add_child(_equipment_content)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	actions.add_child(_button("RETOUR", Callable(self, "_open_menu"), 220))
	actions.add_child(_button("ENTRER DANS L’ARÈNE", Callable(self, "_start_duel"), 330))
	outer.add_child(actions)

func _selection_row(category: String, title: String, ids: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var heading := _label(title, 15, AMBER)
	heading.custom_minimum_size = Vector2(120, 56)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(heading)
	_selection_buttons[category] = {}
	for identifier in ids:
		var button := Button.new()
		button.custom_minimum_size = Vector2(300, 56)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func() -> void:
			loadout[category] = identifier
			_refresh_equipment()
		)
		_selection_buttons[category][identifier] = button
		row.add_child(button)
	_equipment_content.add_child(row)

func _refresh_equipment() -> void:
	for child in _equipment_content.get_children():
		child.queue_free()
	_selection_buttons.clear()
	_selection_row("weapon", "ARME", LOADOUT.WEAPONS)
	_selection_row("offensive", "OFFENSIF", LOADOUT.OFFENSIVE)
	_selection_row("defensive", "DÉFENSIF", LOADOUT.DEFENSIVE)
	_selection_row("mobility", "MOBILITÉ", LOADOUT.MOBILITY)
	_selection_row("passive", "PASSIF", LOADOUT.PASSIVES)
	for category in _selection_buttons.keys():
		for identifier in _selection_buttons[category].keys():
			var button: Button = _selection_buttons[category][identifier]
			var active := str(loadout.get(category, "")) == str(identifier)
			var description := LOADOUT.category_description(identifier)
			var stats := LOADOUT.stat_line(identifier)
			# Keep the card readable on a 1280×720 landscape viewport. The full
			# values remain available in CombatData and the card keeps the useful
			# decision numbers without forcing the panel off-screen.
			button.tooltip_text = description + "  " + stats
			if description.length() > 25:
				description = description.left(25) + "…"
			if stats.length() > 16:
				stats = stats.left(16) + "…"
			button.text = ("◆ " if active else "◇ ") + LOADOUT.display_name(identifier) + "\n" + description + "  " + stats
			button.add_theme_color_override("font_color", CYAN if active else CREAM)
			button.add_theme_stylebox_override("normal", _panel_style(Color("#1d555b") if active else PANEL_ALT, CYAN if active else Color("#594649"), 8))

func _build_settings() -> void:
	_settings_panel = _center_panel(620, 390)
	_screen_root.add_child(_settings_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_settings_panel.add_child(box)
	box.add_child(_label("RÉGLAGES", 32, CREAM))
	box.add_child(_label("Options limitées au prototype", 14, MUTED))
	var shake := CheckButton.new()
	shake.name = "CameraShake"
	shake.text = "Secousses de caméra"
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
	)
	box.add_child(_label("Taille des contrôles tactiles", 16, MUTED))
	box.add_child(touch)
	box.add_child(_button("RETOUR", Callable(self, "_open_menu"), 300))

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "CombatHUD"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.add_child(_hud)
	var top_left := PanelContainer.new()
	top_left.position = Vector2(22, 18)
	top_left.custom_minimum_size = Vector2(285, 108)
	top_left.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.07, 0.08, 0.86), Color("#5f4c4b"), 9))
	_hud.add_child(top_left)
	var left_box := VBoxContainer.new()
	top_left.add_child(left_box)
	_hud_labels.player = _label("JOUEUR", 18, CREAM)
	left_box.add_child(_hud_labels.player)
	_hud_labels.player_effects = _label("", 14, CYAN)
	left_box.add_child(_hud_labels.player_effects)
	_hud_labels.weapon = _label("", 14, AMBER)
	left_box.add_child(_hud_labels.weapon)
	_hud_labels.passive = _label("", 14, MUTED)
	left_box.add_child(_hud_labels.passive)
	var top_right := PanelContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.position = Vector2(-315, 18)
	top_right.custom_minimum_size = Vector2(290, 108)
	top_right.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.07, 0.08, 0.86), Color("#5f4c4b"), 9))
	_hud.add_child(top_right)
	var right_box := VBoxContainer.new()
	top_right.add_child(right_box)
	_hud_labels.enemy = _label("BOT", 18, RED)
	right_box.add_child(_hud_labels.enemy)
	_hud_labels.enemy_effects = _label("", 14, AMBER)
	right_box.add_child(_hud_labels.enemy_effects)
	var pause := _button("Ⅱ  PAUSE", Callable(self, "_toggle_pause"), 150)
	pause.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-170, 138)
	pause.custom_minimum_size = Vector2(148, 40)
	_hud.add_child(pause)
	var modules := HBoxContainer.new()
	modules.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	modules.position = Vector2(22, -120)
	modules.add_theme_constant_override("separation", 8)
	_hud.add_child(modules)
	for key in ["offensive", "defensive", "mobility"]:
		var module_label := _label("", 14, CREAM)
		module_label.custom_minimum_size = Vector2(205, 44)
		module_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		module_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		module_label.add_theme_stylebox_override("normal", _panel_style(Color(0.08, 0.07, 0.08, 0.90), Color("#594649"), 8))
		modules.add_child(module_label)
		_hud_labels[key] = module_label
	var dev := _label("", 12, Color(1, 1, 1, 0.45))
	dev.position = Vector2(22, 140)
	dev.name = "DevDiagnostics"
	dev.visible = false
	_hud.add_child(dev)
	_hud_labels.dev = dev

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
	box.add_child(_button("RECOMMENCER", Callable(self, "_restart"), 300))
	box.add_child(_button("RETOUR AU MENU", Callable(self, "_return_menu"), 300))

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
	box.add_child(_button("REJOUER", Callable(self, "_restart"), 340))
	box.add_child(_button("MODIFIER L’ÉQUIPEMENT", Callable(self, "_open_equipment"), 340))
	box.add_child(_button("RETOUR AU MENU", Callable(self, "_return_menu"), 340))

func _update_hud() -> void:
	if player == null or target == null:
		return
	var p_hp := float(player.call("get_health"))
	var p_max := float(player.call("get_max_health"))
	var e_hp := float(target.call("get_health"))
	var e_max := float(target.call("get_max_health"))
	_hud_labels.player.text = "JOUEUR   %d / %d PV" % [roundi(p_hp), roundi(p_max)]
	_hud_labels.enemy.text = "BOT   %d / %d PV" % [roundi(e_hp), roundi(e_max)]
	_hud_labels.player_effects.text = _effects_text(player)
	_hud_labels.enemy_effects.text = _effects_text(target)
	var weapon_id := str(player.call("get_weapon_id"))
	var weapon_text := LOADOUT.display_name(weapon_id)
	if weapon_id == "shotgun":
		weapon_text += "   •   %d / 3" % int(player.call("get_shotgun_ammo"))
		if bool(player.call("is_shotgun_reloading")):
			weapon_text += "   RECHARGE"
	_hud_labels.weapon.text = weapon_text
	var passive_id := str(player.call("get_passive_id"))
	var passive_text := LOADOUT.display_name(passive_id)
	if passive_id == "baroud" and float(player.call("get_baroud_remaining")) > 0.0:
		passive_text += "   •   %d PV / %.1fs" % [roundi(float(player.call("get_baroud_health"))), float(player.call("get_baroud_remaining"))]
	_hud_labels.passive.text = passive_text
	var modules := {"offensive": str(player.call("get_offensive_module_id")), "defensive": str(player.call("get_defensive_module_id")), "mobility": str(player.call("get_mobility_module_id"))}
	for key in modules.keys():
		var identifier: String = modules[key]
		var cooldown := float(player.call("get_module_cooldown", identifier))
		_hud_labels[key].text = "%s  %s" % [_module_icon(key), LOADOUT.display_name(identifier)]
		if cooldown > 0.0:
			_hud_labels[key].text += "\n%.1fs" % cooldown
			_hud_labels[key].add_theme_color_override("font_color", MUTED)
		else:
			_hud_labels[key].text += "\nPRÊT"
			_hud_labels[key].add_theme_color_override("font_color", CYAN)

func _effects_text(actor: Node) -> String:
	var effects: Array = actor.call("get_active_effect_types")
	return "ÉTATS : " + (" / ".join(effects) if not effects.is_empty() else "—")

func _module_icon(category: String) -> String:
	return {"offensive": "✦", "defensive": "◇", "mobility": "➤"}.get(category, "•")

func _open_menu() -> void:
	_end_pause(false)
	_show_screen(Screen.MENU)

func _open_equipment() -> void:
	loadout = LOADOUT.sanitize(loadout)
	_show_screen(Screen.EQUIPMENT)

func _open_settings() -> void:
	_show_screen(Screen.SETTINGS)

func _start_duel() -> void:
	loadout = LOADOUT.sanitize(loadout)
	LOADOUT.save_local(loadout)
	_round_resolved = false
	result_text = ""
	if main != null and main.has_method("start_duel"):
		main.call("start_duel", loadout)
	_show_screen(Screen.COMBAT)

func on_actor_died(actor: Node) -> void:
	if _round_resolved or current_screen != Screen.COMBAT:
		return
	if main != null:
		main.call_deferred("resolve_round")

func resolve_round(player_dead: bool, target_dead: bool) -> void:
	if _round_resolved:
		return
	_round_resolved = true
	_pause_active = false
	get_tree().paused = false
	if player_dead and target_dead:
		result_text = "ÉGALITÉ"
	elif target_dead:
		result_text = "VICTOIRE"
	else:
		result_text = "DÉFAITE"
	_hud_labels.result_title.text = result_text
	_hud_labels.result_title.add_theme_color_override("font_color", GREEN if result_text == "VICTOIRE" else RED if result_text == "DÉFAITE" else AMBER)
	_hud_labels.result_detail.text = "Manche terminée • équipement conservé : %s" % LOADOUT.display_name(str(loadout.weapon))
	_show_screen(Screen.RESULT)
	if main != null and main.has_method("stop_duel"):
		main.call("stop_duel")

func _toggle_pause() -> void:
	if current_screen != Screen.COMBAT or _round_resolved:
		return
	if _pause_active:
		_resume()
	else:
		_pause_active = true
		_pause_started_msec = Time.get_ticks_msec()
		if touch_controls != null and touch_controls.has_method("reset_inputs"):
			touch_controls.call("reset_inputs")
		get_tree().paused = true
		_pause_panel.visible = true

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
	if resume_game and main != null and main.has_method("shift_pause_timers"):
		main.call("shift_pause_timers", elapsed)
	if touch_controls != null and touch_controls.has_method("reset_inputs"):
		touch_controls.call("reset_inputs")

func _update_pause_labels() -> void:
	if _hud_labels.has("pause_status"):
		_hud_labels.pause_status.text = "La manche est suspendue."

func _restart() -> void:
	_end_pause(false)
	_round_resolved = false
	if main != null and main.has_method("restart_duel"):
		main.call("restart_duel", loadout)
	_show_screen(Screen.COMBAT)

func _return_menu() -> void:
	_end_pause(false)
	_round_resolved = false
	if main != null and main.has_method("stop_duel"):
		main.call("stop_duel")
	_show_screen(Screen.MENU)
