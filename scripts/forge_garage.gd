extends Control

## A complete draft build. Only the end of the installation commits it.
signal equipment_selected(category: String, identifier: String)
signal build_saved(equipment: Dictionary)
signal test_requested(equipment: Dictionary)
signal settings_requested
signal back_requested
signal start_requested
signal arena_selected(identifier: String)

const STAGE := preload("res://scripts/forge_garage_stage.gd")
const ARENA_CATALOG := preload("res://scripts/compact_arena_catalog.gd")
const EQUIPMENT_FOCUS := preload("res://scripts/forge_garage_focus.gd")
const TRAINING_DEMO := preload("res://scripts/forge_training_demo.gd")
const INSTALLATION := preload("res://scripts/forge_build_installation.gd")
const MODULE_INSTALLATION := preload("res://scripts/forge_module_installation.gd")
const MODULE_STATIONS := preload("res://scripts/forge_module_stations.gd")
const WEAPON_RACK := preload("res://scripts/forge_weapon_rack.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const DATA := preload("res://scripts/combat_data.gd")
const ICONS := preload("res://scripts/equipment_icons.gd")
const DISPLAY_FONT := preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const BODY_FONT := preload("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
const RESPONSIVE_LAYOUT := preload("res://scripts/ui/forge_garage_layout.gd")
const DESIGN_SIZE := Vector2(1280, 720)
const EXPERIENCE := preload("res://scripts/review_preferences.gd")
const AMBER := Color("#f5b844")
const CREAM := Color("#eee5ce")
const CYAN := Color("#69e0e8")
const CATEGORY_TITLES := {"offensive": "OFFENSIF", "defensive": "DÉFENSIF", "mobility": "MOBILITÉ", "passive": "PASSIF"}
const TAGS := {
	"agile": "Rapidité", "polyvalent": "Équilibre", "puissant": "Résistance",
	"blaster": "Tir précis · charge", "shotgun": "Salves rapprochées", "mekatana": "Combo · mêlée", "longshot": "Longue portée",
	"rocket_basket": "Roquettes guidées", "javelin": "Marquage · recast", "fulguro_punch": "Charge · impact", "pelto_smash": "Vague · traction",
	"magnetic_field": "Mur protecteur", "static_shield": "Stase invulnérable", "projector": "Repousse · ralentit", "counter": "Garde · riposte",
	"pyro_boots": "Dash enflammé", "bio_injector": "Vitesse · attaques", "permutation": "Échange de positions", "eclipse": "Déplacement intangible",
	"baroud": "Dernière chance", "omnivamp": "Vol de vie", "auxiliary_reactor": "Recharge offensive", "tracker": "Révèle la cible", "alternator": "+15 % prochain coup", "inertia": "Ralentit après un dash",
}

var loadout: Dictionary = LOADOUT.defaults()
var stage
var focus
var installation: INSTALLATION
var module_installation: MODULE_INSTALLATION
var robot_buttons: Dictionary = {}
var weapon_buttons: Dictionary = {}
var module_buttons: Dictionary = {}
var arena_buttons: Dictionary = {}
var _arena_selector: OptionButton
var _selected_arena := "classic"
var library_path := LIBRARY.SAVE_PATH
var legacy_save_path := LOADOUT.SAVE_PATH
var build_name := "DUELLISTE"
var build_id := ""
var _library: Dictionary
var _active_loadout: Dictionary = {}
var _pending_library: Dictionary = {}
var _icons := ICONS.new()
var _ui: Control
var _stat_name: Label
var _health: Label
var _speed: Label
var _status: Label
var _training_demo: TRAINING_DEMO
var _module_panel: Panel
var _module_options: GridContainer
var _module_category := "passive"
var _category := "passive"
var _nav: Dictionary = {}
var _grids: Dictionary = {}
var _choices: Dictionary = {}
var _detail_icon: TextureRect
var _detail_title: Label
var _detail_description: Label
var _detail_stats: Label
var _missing_demo: Label
var _save_button: Button
var _build_selector: OptionButton
var _build_menu: MenuButton
var _rename_panel: Panel
var _name_input: LineEdit
var _notice_time := 0.0
var _rotating_robot := false
var _touch_index := -1
var _save_and_play := false
var _installation_controls: Control
var _installation_status: Label
var equip_button: Button
var _detail_panel: Panel
var _garage_return: Button
var _hub_caption: Label
var _hub_mode := true
var _preview_category := "passive"
var _preview_id := ""
var _cinema: Control
var _cinema_phase: Label
var _cinema_title: Label
var _cinema_progress: ProgressBar
var _catalog_tween: Tween
var _catalog_title: Label
var _presets: OptionButton
var _view := "hub"
var _compact_layout := false
var safe_area_override := Rect2()
var _header: Panel
var _header_title: Label
var _back_button: Button
var _save_state: Label
var _family_selector: OptionButton
var _footer: Panel
var _stats_panel: Panel
var _test_button: Button
var _demo_button: Button
var _builds_panel: Panel
var _builds_title: Label
var _build_actions: Array[Button] = []
var _equipment_display: Node3D
var _display_id := ""
var _arena_enabled := false


func _ready() -> void:
	name = "ForgeGarage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var custom_theme := Theme.new()
	custom_theme.default_font = BODY_FONT
	custom_theme.default_font_size = 16
	theme = custom_theme
	_library = LIBRARY.load_local(library_path, legacy_save_path)
	build_id = str(_library.active)
	for entry in _library.builds:
		if str(entry.id) == build_id:
			loadout = entry.loadout.duplicate(true)
			build_name = entry.name
	stage = STAGE.new()
	stage.name = "GarageStage"
	stage.automatic_service_enabled = false
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	stage.camera.position -= stage.camera.global_basis.x * 0.58
	stage.module_stations = MODULE_STATIONS.new()
	stage.module_stations.configure(stage)
	stage.world.add_child(stage.module_stations)
	stage.weapon_rack = WEAPON_RACK.new()
	stage.weapon_rack.configure(stage)
	stage.world.add_child(stage.weapon_rack)
	_build_interface()
	focus = EQUIPMENT_FOCUS.new()
	focus.name = "EquipmentFocus"
	focus.configure(stage, _module_panel, _ui)
	stage.add_child(focus)
	installation = INSTALLATION.new()
	installation.name = "BuildInstallation"
	installation.configure(stage, focus)
	add_child(installation)
	installation.completed.connect(_finish_save)
	installation.cancelled.connect(_cancel_save)
	module_installation = MODULE_INSTALLATION.new()
	module_installation.name = "ModuleInstallation"
	module_installation.configure(stage, focus)
	add_child(module_installation)
	module_installation.mounted.connect(_module_mounted)
	module_installation.completed.connect(_module_completed)
	module_installation.cancelled.connect(_module_cancelled)
	resized.connect(_layout)
	visibility_changed.connect(_sync_visibility)
	get_viewport().mouse_exited.connect(_clear_station_hover)
	_layout()
	_refresh()
	_show_garage(false)
	_sync_visibility()


func _process(delta: float) -> void:
	if installation != null and installation.active and _installation_status != null:
		_installation_status.text = "Installation · %.1f / 5 s" % installation.elapsed
	if module_installation != null and module_installation.active:
		_cinema_phase.text = {"approach": "MISE EN POSITION", "pickup": "PRISE AU RÂTELIER" if module_installation.category == "weapon" else "SAISIE DU MODULE", "lift": "LEVAGE", "carry": "TRANSFERT VERS LE ROBOT", "align": "ALIGNEMENT", "work": "VERROUILLAGE", "release": "ÉQUIPEMENT FIXÉ", "return": "RETRAIT DU BRAS"}.get(module_installation.phase, "INSTALLATION")
		_cinema_progress.value = clampf(module_installation.elapsed / module_installation.DURATION, 0.0, 1.0)
	if _notice_time > 0:
		_notice_time -= delta
		if _notice_time <= 0:
			_status.text = ""


func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or installation.active or module_installation.active:
		return
	if _hub_mode:
		var pointer := Vector2.ZERO
		var pressed := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			pointer = event.position
			pressed = event.pressed
		elif event is InputEventScreenTouch:
			pointer = event.position
			pressed = event.pressed
		if pressed:
			var selected := _pick_station(pointer)
			if not selected.is_empty():
				_open_station(selected)
				accept_event()
				return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and stage.robot.visible and stage.is_robot_at_position(event.position):
			module_installation.cancel(false)
			_touch_index = event.index
			_rotating_robot = true
			stage.begin_robot_rotation()
			accept_event()
		elif event.index == _touch_index and (not event.pressed or event.canceled):
			_stop_robot_rotation()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		stage.rotate_robot(event.relative.x * TAU * 2.0 / maxf(size.x, 1.0))
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed and stage.robot.visible and stage.is_robot_at_position(event.position):
			module_installation.cancel(false)
			_rotating_robot = true
			stage.begin_robot_rotation()
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			accept_event()
		elif not event.pressed and _rotating_robot:
			_stop_robot_rotation()
			accept_event()
	elif event is InputEventMouseMotion:
		if _rotating_robot:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				stage.rotate_robot(event.relative.x * TAU * 2.0 / maxf(size.x, 1.0))
			else:
				_stop_robot_rotation()
			accept_event()
		else:
			mouse_default_cursor_shape = Control.CURSOR_DRAG if stage.is_robot_at_position(event.position) else (Control.CURSOR_POINTING_HAND if _hub_mode and not _pick_station(event.position).is_empty() else Control.CURSOR_ARROW)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_stop_robot_rotation()
		if module_installation != null:
			module_installation.cancel()


func _stop_robot_rotation() -> void:
	_rotating_robot = false
	_touch_index = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	if stage != null:
		stage.end_robot_rotation()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not installation.active:
			if _rename_panel.visible:
				_rename_panel.hide()
			else:
				back_requested.emit()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _hub_mode and event is InputEventMouseMotion:
		# Track leaving a station even when a header/footer control owns the GUI event.
		_highlight_station(_pick_station(get_global_transform().affine_inverse() * event.position))
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if installation != null and installation.active:
			get_viewport().set_input_as_handled()
			return
		if module_installation != null and module_installation.active:
			module_installation.cancel()
		elif _training_demo != null and _training_demo._viewer.visible:
			_training_demo.close_enlarged()
		elif _rename_panel.visible:
			_rename_panel.hide()
		else:
			_request_back()
		get_viewport().set_input_as_handled()


func set_loadout(value: Dictionary) -> void:
	if installation != null and installation.active:
		return
	var equipment := LOADOUT.sanitize(value)
	if equipment == _active_loadout:
		return
	if module_installation != null:
		module_installation.cancel()
	_active_loadout = equipment.duplicate(true)
	loadout = equipment
	if _ui != null:
		_refresh()
		_show_detail(_category, str(loadout[_category]))


func draft_state() -> Dictionary:
	return {"loadout": loadout.duplicate(true), "name": build_name, "id": build_id}


func restore_draft(value: Dictionary) -> void:
	if installation.active:
		return
	module_installation.cancel()
	loadout = LOADOUT.sanitize(value.get("loadout", loadout))
	build_name = LIBRARY.normalize_name(str(value.get("name", build_name)))
	build_id = str(value.get("id", build_id))
	_refresh()
	_show_detail(_category, str(loadout[_category]))


func is_dirty() -> bool:
	if build_id != str(_library.active):
		return true
	for entry in _library.builds:
		if str(entry.id) == build_id:
			return entry.loadout != loadout or str(entry.name) != build_name
	return true


func set_arena_options(enabled: bool, selected: String = "classic") -> void:
	_arena_enabled = enabled
	_selected_arena = selected
	for identifier in arena_buttons:
		var button: Button = arena_buttons[identifier]
		button.visible = false
		button.add_theme_stylebox_override("normal", _style(identifier == selected))
	if _arena_selector != null:
		_arena_selector.visible = enabled and _view == "builds"
		for index in _arena_selector.item_count:
			if str(_arena_selector.get_item_metadata(index)) == selected:
				_arena_selector.select(index)
				_arena_selector.tooltip_text = str(ARENA_CATALOG.options()[index].description)


func _choose_arena(identifier: String) -> void:
	if installation.active or (module_installation != null and module_installation.active):
		set_arena_options(true, _selected_arena)
		return
	set_arena_options(true, identifier)
	arena_selected.emit(identifier)


func _select_equipment(category: String, identifier: String) -> void:
	if installation.active or module_installation.active:
		return
	if str(loadout.get(category, "")) == identifier:
		return
	if category == "weapon" or identifier in MODULE_INSTALLATION.REAL_MODULES:
		_hide_equipment_display()
		if category in CATEGORY_TITLES:
			_module_category = category
		_stop_robot_rotation()
		_training_demo.close_enlarged()
		if module_installation.begin(identifier, category):
			_ui.set_meta("preview_rect", Rect2(20, 70, _ui.size.x - 40, _ui.size.y - 150))
			_ui.hide()
			_cinema.show()
			_cinema_phase.text = "PRISE EN CHARGE"
			_cinema_title.text = "INSTALLATION  /  " + LOADOUT.display_name(identifier)
			_cinema_progress.value = 0.0
		else:
			_notice("Le bras n’a pas pu rejoindre cet équipement.")
		return
	loadout[category] = identifier
	loadout = LOADOUT.sanitize(loadout)
	_refresh()
	_show_detail(category, identifier)
	if category == "robot":
		if _compact_layout and not _hub_mode:
			_view = "detail"
		_layout()
		_focus_selection()
	elif category in CATEGORY_TITLES:
		module_installation.audio.play("lock")
	equipment_selected.emit(category, str(loadout[category]))


func _preview_equipment(category: String, identifier: String) -> void:
	if category in CATEGORY_TITLES or category == "weapon":
		if _compact_layout:
			_view = "detail"
		_show_detail(category, identifier)
		_layout()
		_focus_selection()
	else:
		_select_equipment(category, identifier)


func _equip_preview() -> void:
	if not _preview_id.is_empty():
		_select_equipment(_preview_category, _preview_id)


func _module_mounted(category: String, identifier: String) -> void:
	loadout[category] = identifier
	loadout = LOADOUT.sanitize(loadout)
	_refresh()
	equipment_selected.emit(category, str(loadout[category]))


func _module_completed(identifier: String) -> void:
	_cinema.hide()
	_ui.show()
	var kind: String = module_installation.category
	_open_station(kind)
	if _compact_layout:
		_view = "detail"
	_show_detail(kind, identifier)
	_layout()
	_focus_selection()
	_notice(LOADOUT.display_name(identifier) + " installé")


func _module_cancelled() -> void:
	if _cinema != null:
		_cinema.hide()
		_ui.show()
		_layout()
		if is_visible_in_tree():
			if _hub_mode:
				focus.show_garage()
			else:
				_focus_selection()


func _save_build() -> void:
	if installation.active or module_installation.active:
		return
	module_installation.cancel()
	_finish_rename()
	_stop_robot_rotation()
	_hide_equipment_display()
	_pending_library = LIBRARY.with_build(_library, build_id, build_name, loadout)
	_training_demo.close_enlarged()
	if not installation.begin(loadout):
		_notice("Bras indisponible. Réessaie.")
		return
	_save_button.disabled = true
	_ui.hide()
	_installation_controls.show()
	if bool(EXPERIENCE.read().quick):
		call_deferred("_skip_installation")


func _save_then_play() -> void:
	if installation.active or module_installation.active:
		return
	if not is_dirty():
		build_saved.emit(loadout.duplicate(true))
		start_requested.emit()
		return
	_save_and_play = true
	_save_build()
	if not installation.active:
		_save_and_play = false


func _skip_installation() -> void:
	if installation.active:
		installation.advance(INSTALLATION.DURATION)


func _finish_save() -> void:
	var saved := LIBRARY.save_local(_pending_library, library_path, legacy_save_path)
	if saved:
		_library = _pending_library
		build_id = str(_library.active)
		for entry in _library.builds:
			if str(entry.id) == build_id:
				loadout = entry.loadout.duplicate(true)
				build_name = entry.name
		_active_loadout = loadout.duplicate(true)
		build_saved.emit(loadout.duplicate(true))
		_notice("Build sauvegardé")
		get_node("/root/UiSfx").play("launch" if _save_and_play else "confirmation")
	else:
		_notice("Sauvegarde impossible. Réessaie.")
		get_node("/root/UiSfx").play("denied")
	_pending_library = {}
	_ui.show()
	_installation_controls.hide()
	_save_button.disabled = false
	_refresh()
	_show_detail(_category, str(loadout[_category]))
	var launch := _save_and_play and saved
	_layout()
	_focus_selection()
	stage.react_to_installation(saved)
	_save_and_play = false
	if launch:
		start_requested.emit()


func _cancel_save() -> void:
	_pending_library = {}
	_save_and_play = false
	_ui.show()
	_installation_controls.hide()
	_save_button.disabled = false
	_layout()
	_focus_selection()


func _test_build() -> void:
	if not installation.active and not module_installation.active:
		module_installation.cancel()
		_finish_rename()
		test_requested.emit(loadout.duplicate(true))


func _request_back() -> void:
	if installation.active or module_installation.active:
		return
	if _rename_panel.visible:
		_rename_panel.hide()
	elif _view == "detail" and _compact_layout:
		_show_catalog(_category)
		focus.show_station(_category) if _category != "robot" else focus.show_overview()
	elif not _hub_mode:
		_show_garage()
	else:
		back_requested.emit()


func _sync_visibility() -> void:
	var active := is_visible_in_tree()
	set_process(active)
	set_process_unhandled_key_input(active)
	if not active:
		_stop_robot_rotation()
		_hide_equipment_display()
		if module_installation != null:
			module_installation.cancel(false)
		if installation != null:
			installation.cancel()
	elif focus != null and module_installation != null and not module_installation.active:
		_show_garage(false)


func _layout() -> void:
	if _ui == null:
		return
	RESPONSIVE_LAYOUT.apply(self)
	if focus != null:
		focus.fit_layout()


func _style(active: bool = false, strong: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.075, 0.06, 0.94) if not active else Color(0.23, 0.16, 0.075, 0.96)
	style.border_color = AMBER if active else Color("#625544")
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8 if strong else 0
	return style


func _label(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color = CREAM, display: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if display:
		label.add_theme_font_override("font", DISPLAY_FONT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, pos: Vector2, dimensions: Vector2, callback: Callable, active: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = dimensions
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", DISPLAY_FONT)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", CREAM)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _style(active if state == "normal" else state != "disabled"))
	button.pressed.connect(callback)
	_ui.add_child(button)
	return button


func _panel(pos: Vector2, dimensions: Vector2, strong: bool = false) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.add_theme_stylebox_override("panel", _style(false, strong))
	_ui.add_child(panel)
	return panel


func _build_interface() -> void:
	_ui = Control.new()
	_ui.name = "GarageInterface"
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_header = _panel(Vector2.ZERO, Vector2(1280, 64))
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button = _button("‹", Vector2.ZERO, Vector2(48, 48), _request_back)
	_back_button.name = "GarageBack"
	_header_title = _label("GARAGE", Vector2.ZERO, Vector2(350, 50), 34, CREAM, true)
	_ui.add_child(_header_title)
	_save_state = _label("", Vector2.ZERO, Vector2(220, 30), 14, CYAN, true)
	_save_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_save_state)
	_module_panel = _panel(Vector2.ZERO, Vector2(320, 574))
	_module_panel.hide()
	_hub_caption = _label("", Vector2.ZERO, Vector2(250, 32), 20, CREAM, true)
	_ui.add_child(_hub_caption)
	for title in ["ARMES", "MODULES", "MES BUILDS"]:
		var button := _button("", Vector2.ZERO, Vector2(220, 130), _navigate.bind(title))
		button.name = "Garage" + title.to_pascal_case().replace(" ", "")
		button.mouse_entered.connect(func() -> void:
			if focus != null and _hub_mode:
				focus.set_station_hovered(true))
		button.mouse_exited.connect(func() -> void: _highlight_station(""))
		_nav[title] = button
		var icon := TextureRect.new()
		icon.name = "HubIcon"
		icon.texture = _icons.get_icon("blaster" if title == "ARMES" else ("auxiliary_reactor" if title == "MODULES" else loadout.robot))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var label := _label(title, Vector2.ZERO, Vector2(200, 30), 19, CREAM, true)
		label.name = "HubTitle"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(label)
	_catalog_title = _label("", Vector2.ZERO, Vector2(300, 30), 16, CREAM)
	_ui.add_child(_catalog_title)
	_garage_return = _back_button
	_family_selector = OptionButton.new()
	_family_selector.name = "EquipmentFamily"
	_family_selector.fit_to_longest_item = false
	_family_selector.clip_text = true
	_family_selector.add_theme_font_override("font", DISPLAY_FONT)
	_family_selector.add_theme_font_size_override("font_size", 16)
	for kind in ["weapon", "offensive", "defensive", "mobility", "passive", "robot"]:
		_family_selector.add_item("ARMES" if kind == "weapon" else ("CHÂSSIS" if kind == "robot" else CATEGORY_TITLES[kind]))
		_family_selector.set_item_metadata(_family_selector.item_count - 1, kind)
	_family_selector.item_selected.connect(func(index: int) -> void:
		_navigate("ROBOT") if str(_family_selector.get_item_metadata(index)) == "robot" else _open_station(str(_family_selector.get_item_metadata(index))))
	for state in ["normal", "hover", "pressed", "focus"]:
		_family_selector.add_theme_stylebox_override(state, _style(state != "normal"))
	_ui.add_child(_family_selector)
	for category in CATEGORY_TITLES:
		var button := _button(CATEGORY_TITLES[category], Vector2.ZERO, Vector2(145, 48), _open_modules.bind(category))
		button.hide()
		module_buttons[category] = button
	for category in ["robot", "weapon", "offensive", "defensive", "mobility", "passive"]:
		_build_catalog(category)
	_build_detail()
	_build_footer()
	_build_rename_panel()
	_build_experience_controls()
	_build_cinematic_interface()
	for id in ["classic", "hazards", "test"]:
		var button := _button(id, Vector2.ZERO, Vector2(109, 48), _choose_arena.bind(id))
		button.hide()
		arena_buttons[id] = button
	_arena_selector = OptionButton.new()
	_arena_selector.name = "ArenaSelector"
	_arena_selector.fit_to_longest_item = false
	_arena_selector.clip_text = true
	_arena_selector.add_theme_font_size_override("font_size", 16)
	_arena_selector.add_theme_color_override("font_color", CREAM)
	_arena_selector.add_theme_stylebox_override("normal", _style(false))
	_arena_selector.add_theme_stylebox_override("hover", _style(true))
	for choice in ARENA_CATALOG.options():
		_arena_selector.add_item("ARÈNE · " + str(choice.title))
		_arena_selector.set_item_metadata(_arena_selector.item_count - 1, str(choice.id))
	_arena_selector.item_selected.connect(func(index: int) -> void:
		_choose_arena(str(_arena_selector.get_item_metadata(index))))
	_builds_panel.add_child(_arena_selector)
	set_arena_options(false)


func _options(category: String) -> Array:
	return {"robot": LOADOUT.ROBOTS, "weapon": LOADOUT.WEAPONS, "offensive": LOADOUT.OFFENSIVE, "defensive": LOADOUT.DEFENSIVE, "mobility": LOADOUT.MOBILITY, "passive": LOADOUT.PASSIVES}.get(category, [])


func _build_catalog(category: String) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.name = category.to_pascal_case() + "Catalog"
	grid.add_theme_constant_override("v_separation", 12)
	grid.add_theme_constant_override("h_separation", 12)
	_ui.add_child(grid)
	_grids[category] = grid
	_choices[category] = {}
	for identifier in _options(category):
		var button := Button.new()
		button.name = "Garage%s" % str(identifier).to_pascal_case()
		button.custom_minimum_size = Vector2(190, 135)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = LOADOUT.category_description(identifier)
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, _style(state != "normal"))
		button.pressed.connect(_preview_equipment.bind(category, str(identifier)))
		button.gui_input.connect(_card_input.bind(category, str(identifier)))
		grid.add_child(button)
		var icon := TextureRect.new()
		icon.name = "EquipmentIcon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = _icons.get_icon(identifier)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var title := _label(LOADOUT.display_name(identifier).replace("RÉACTEUR AUXILIAIRE", "RÉACTEUR AUX.").replace("BAROUD D’HONNEUR", "BAROUD"), Vector2.ZERO, Vector2(180, 26), 16, CREAM, true)
		title.name = "CardTitle"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_child(title)
		var tag := _label(str(TAGS.get(identifier, "")), Vector2.ZERO, Vector2(180, 22), 14)
		tag.name = "CardTag"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(tag)
		var selected := _label("✓", Vector2.ZERO, Vector2(24, 26), 20, AMBER, true)
		selected.name = "Selected"
		button.add_child(selected)
		_choices[category][identifier] = button
		if category == "robot":
			robot_buttons[identifier] = button
		elif category == "weapon":
			weapon_buttons[identifier] = button
	grid.hide()


func _card_input(event: InputEvent, category: String, identifier: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		_preview_equipment(category, identifier)
		_select_equipment(category, identifier)
		get_viewport().set_input_as_handled()


func _build_detail() -> void:
	_detail_panel = _panel(Vector2.ZERO, Vector2(400, 280))
	_detail_panel.name = "EquipmentDetail"
	_detail_icon = TextureRect.new()
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(_detail_icon)
	_detail_title = _label("", Vector2.ZERO, Vector2(300, 56), 24, CREAM, true)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_panel.add_child(_detail_title)
	var scroll := ScrollContainer.new()
	scroll.name = "DescriptionScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(scroll)
	_detail_description = _label("", Vector2.ZERO, Vector2(300, 100), 17)
	_detail_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(_detail_description)
	_detail_stats = _label("", Vector2.ZERO, Vector2(300, 40), 15, CYAN)
	_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_stats.max_lines_visible = 2
	_detail_stats.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_stats.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.add_child(_detail_stats)
	equip_button = _button("INSTALLER", Vector2.ZERO, Vector2(240, 52), _equip_preview, true)
	equip_button.name = "EquipModule"
	equip_button.reparent(_detail_panel)
	_primary_style(equip_button)
	_demo_button = _button("▶  VOIR EN ACTION", Vector2.ZERO, Vector2(240, 48), _open_demo)
	_demo_button.name = "EquipmentDemo"
	_demo_button.reparent(_detail_panel)
	_training_demo = TRAINING_DEMO.new()
	_training_demo.position = Vector2(-1000, -1000)
	_training_demo.size = Vector2(239, 147)
	_ui.add_child(_training_demo)
	_training_demo.hide()
	_training_demo._viewer.visibility_changed.connect(func() -> void:
		if not _training_demo._viewer.visible:
			_training_demo.hide())
	_missing_demo = _label("", Vector2.ZERO, Vector2(230, 30), 14)
	_detail_panel.add_child(_missing_demo)
	_missing_demo.hide()


func _open_demo() -> void:
	if not TRAINING_DEMO.CLIPS.has(_preview_id):
		return
	_training_demo.show()
	_training_demo.show_enlarged()
	var unit := _ui.scale.y
	_training_demo._close_button.size = Vector2(128, 48) * unit
	_training_demo._close_button.position.y = 4 * unit


func _primary_style(button: Button) -> void:
	button.add_theme_color_override("font_color", Color("#292017"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := _style(true)
		style.bg_color = Color("#696456") if state == "disabled" else (AMBER if state == "normal" else Color("#ffd484"))
		style.border_color = Color("#ffdf93")
		button.add_theme_stylebox_override(state, style)


func _build_footer() -> void:
	_stats_panel = _panel(Vector2.ZERO, Vector2(400, 36))
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_name = _label("", Vector2.ZERO, Vector2(150, 28), 16, CREAM, true)
	_health = _label("", Vector2.ZERO, Vector2(100, 26), 15)
	_speed = _label("", Vector2.ZERO, Vector2(100, 26), 15)
	for label in [_stat_name, _health, _speed]:
		_stats_panel.add_child(label)
	_footer = _panel(Vector2.ZERO, Vector2(1280, 72))
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_test_button = _button("TESTER", Vector2.ZERO, Vector2(150, 52), _test_build)
	_test_button.name = "GarageTest"
	_save_button = _button("JOUER", Vector2.ZERO, Vector2(240, 52), _save_then_play, true)
	_save_button.name = "GarageSaveAndPlay"
	_save_button.tooltip_text = "Sauvegarder le build puis lancer le duel"
	_primary_style(_save_button)
	_status = _label("", Vector2.ZERO, Vector2(430, 28), 15, CYAN)
	_ui.add_child(_status)
	_builds_panel = _panel(Vector2.ZERO, Vector2(540, 500), true)
	_builds_panel.name = "BuildLibrary"
	_builds_title = _label("MES BUILDS", Vector2.ZERO, Vector2(380, 32), 22, CREAM, true)
	_builds_panel.add_child(_builds_title)
	_build_selector = OptionButton.new()
	_build_selector.name = "SavedBuilds"
	_build_selector.add_theme_font_override("font", DISPLAY_FONT)
	_build_selector.add_theme_font_size_override("font_size", 18)
	_build_selector.clip_text = true
	_build_selector.fit_to_longest_item = false
	_build_selector.add_theme_color_override("font_color", CREAM)
	for state in ["normal", "hover", "pressed", "focus"]:
		_build_selector.add_theme_stylebox_override(state, _style(state != "normal"))
	_build_selector.item_selected.connect(_select_build)
	_builds_panel.add_child(_build_selector)
	for action in [{"title": "RENOMMER", "callback": _rename_build}, {"title": "NOUVEAU", "callback": _new_build}, {"title": "DUPLIQUER", "callback": _duplicate_build}, {"title": "SAUVEGARDER", "callback": _save_build}]:
		var button := _button(action.title, Vector2.ZERO, Vector2(200, 48), action.callback)
		button.reparent(_builds_panel)
		_build_actions.append(button)
		if action.title == "SAUVEGARDER":
			_primary_style(button)
	var chassis := _button("CHANGER DE CHÂSSIS", Vector2.ZERO, Vector2(280, 48), _navigate.bind("ROBOT"))
	chassis.name = "ChassisPicker"
	chassis.reparent(_builds_panel)
	_nav["ROBOT"] = chassis
	_build_menu = MenuButton.new()
	_build_menu.name = "BuildActions"
	_ui.add_child(_build_menu)
	var popup := _build_menu.get_popup()
	for item in ["Renommer", "Créer un build", "Dupliquer", "Sauvegarder"]:
		popup.add_item(item)
	popup.id_pressed.connect(_build_action)
	_build_menu.hide()


func _build_experience_controls() -> void:
	_presets = OptionButton.new()
	_presets.name = "RecommendedBuilds"
	_presets.fit_to_longest_item = false
	_presets.clip_text = true
	_presets.add_theme_font_size_override("font_size", 16)
	_presets.add_item("BUILDS CONSEILLÉS")
	_presets.set_item_disabled(0, true)
	for title in EXPERIENCE.PRESETS:
		_presets.add_item(title)
	_presets.item_selected.connect(func(index: int) -> void:
		if installation.active or index < 1:
			return
		module_installation.cancel()
		build_id = ""
		build_name = str(EXPERIENCE.PRESETS.keys()[index - 1])
		loadout = EXPERIENCE.PRESETS[build_name].duplicate(true)
		_refresh()
		_notice("Build conseillé · tester ou sauvegarder")
		_presets.select(0))
	_builds_panel.add_child(_presets)
	_installation_controls = Control.new()
	_installation_controls.name = "InstallationControls"
	_installation_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_installation_controls)
	_installation_status = _label("Installation", Vector2(650, 669), Vector2(350, 35), 18, CYAN)
	_installation_controls.add_child(_installation_status)
	var skip := Button.new()
	skip.name = "SkipInstallation"
	skip.text = "PASSER"
	skip.position = Vector2(1060, 660)
	skip.size = Vector2(204, 47)
	skip.pressed.connect(_skip_installation)
	_installation_controls.add_child(skip)
	_installation_controls.hide()


func _build_rename_panel() -> void:
	_rename_panel = _panel(Vector2(70, 590), Vector2(330, 59), true)
	_rename_panel.name = "RenameBuild"
	_name_input = LineEdit.new()
	_name_input.position = Vector2(9, 10)
	_name_input.size = Vector2(254, 38)
	_name_input.max_length = 28
	_name_input.text_submitted.connect(func(_text: String) -> void: _finish_rename())
	_rename_panel.add_child(_name_input)
	var done := Button.new()
	done.text = "✓"
	done.position = Vector2(273, 10)
	done.size = Vector2(47, 38)
	done.pressed.connect(_finish_rename)
	_rename_panel.add_child(done)
	_rename_panel.hide()


func _rename_build() -> void:
	if installation.active:
		return
	_name_input.text = build_name
	_rename_panel.show()
	_name_input.grab_focus()
	_name_input.select_all()


func _finish_rename() -> void:
	if not _rename_panel.visible:
		return
	build_name = LIBRARY.normalize_name(_name_input.text)
	_rename_panel.hide()
	_refresh_build_names()


func _new_build() -> void:
	if installation.active:
		return
	module_installation.cancel()
	build_id = ""
	build_name = "BUILD %d" % int(_library.next_id)
	loadout = LOADOUT.defaults()
	_refresh()
	_show_detail(_category, str(loadout[_category]))
	_rename_build()


func _duplicate_build() -> void:
	if installation.active:
		return
	build_id = ""
	build_name = LIBRARY.normalize_name(build_name + " COPIE")
	_refresh_build_names()
	_rename_build()


func _select_build(index: int) -> void:
	if installation.active or index < 0 or index >= _library.builds.size():
		return
	module_installation.cancel()
	var entry: Dictionary = _library.builds[index]
	build_id = entry.id
	build_name = entry.name
	loadout = entry.loadout.duplicate(true)
	_refresh()
	_show_detail(_category, str(loadout[_category]))


func _refresh_build_names() -> void:
	_build_selector.clear()
	var selected := -1
	for entry in _library.builds:
		_build_selector.add_item(build_name if entry.id == build_id else str(entry.name))
		if entry.id == build_id:
			selected = _build_selector.item_count - 1
	if selected == -1:
		_build_selector.add_item(build_name)
		selected = _build_selector.item_count - 1
	_build_selector.select(selected)
	_build_selector.set_item_text(selected, build_name + (" •" if is_dirty() else ""))
	_hub_caption.text = build_name
	_save_state.text = "BROUILLON •" if is_dirty() else "SAUVEGARDÉ"
	_save_state.add_theme_color_override("font_color", AMBER if is_dirty() else CYAN)


func _build_action(id: int) -> void:
	if installation.active or module_installation.active:
		return
	match id:
		0: _rename_build()
		1: _new_build()
		2: _duplicate_build()
		3: _save_build()


func _notice(text: String) -> void:
	_status.text = text
	_notice_time = 3.5


func _build_cinematic_interface() -> void:
	_cinema = Control.new()
	_cinema.name = "ModuleInstallationOverlay"
	_cinema.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cinema)
	for y in [0.0, 628.0]:
		var bar := ColorRect.new()
		bar.position = Vector2(0, y)
		bar.size = Vector2(1280, 92)
		bar.color = Color(0.02, 0.025, 0.025, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cinema.add_child(bar)
	_cinema_title = _label("INSTALLATION", Vector2(36, 22), Vector2(1100, 28), 20, CREAM, true)
	_cinema.add_child(_cinema_title)
	_cinema_phase = _label("", Vector2(36, 646), Vector2(800, 28), 18, CREAM, true)
	_cinema.add_child(_cinema_phase)
	_cinema_progress = ProgressBar.new()
	_cinema_progress.position = Vector2(36, 688)
	_cinema_progress.size = Vector2(1208, 3)
	_cinema_progress.max_value = 1.0
	_cinema_progress.show_percentage = false
	_cinema_progress.add_theme_font_size_override("font_size", 1)
	_cinema_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	_cinema_progress.add_theme_stylebox_override("fill", fill)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0.25, 0.24, 0.21)
	_cinema_progress.add_theme_stylebox_override("background", empty)
	_cinema.add_child(_cinema_progress)
	_cinema_progress.set_deferred("size", Vector2(1208, 3))
	var skip := _button("TERMINER  ›", Vector2(1054, 638), Vector2(190, 40), func() -> void: module_installation.finish_now())
	skip.reparent(_cinema, false)
	skip.position = Vector2(1054, 638)
	_cinema.hide()


func _show_garage(animated: bool = true) -> void:
	if installation != null and installation.active:
		return
	if module_installation != null and module_installation.active:
		module_installation.cancel(false)
	_hub_mode = true
	_view = "hub"
	_hide_equipment_display()
	_training_demo.close_enlarged()
	_training_demo.hide()
	_layout()
	if focus != null:
		focus.set_process(is_visible_in_tree())
		focus.show_garage(animated)
	_highlight_station("")


func _open_modules(category: String) -> void:
	if not CATEGORY_TITLES.has(category) or installation.active or module_installation.active:
		return
	_module_category = category
	_show_catalog(category)
	_focus_selection()


func _open_weapon_rack() -> void:
	if installation.active or module_installation.active:
		return
	_show_catalog("weapon")
	_focus_selection()


func _open_station(category: String) -> void:
	if category == "weapon":
		_open_weapon_rack()
	else:
		_open_modules(category)


func _pick_station(point: Vector2) -> String:
	var rack_hit: String = stage.weapon_rack.pick(point)
	return rack_hit if not rack_hit.is_empty() else stage.module_stations.pick(point)


func _highlight_station(category: String) -> void:
	stage.module_stations.highlight(category if category != "weapon" else "")
	stage.weapon_rack.highlight(category if category == "weapon" else "")
	if focus != null:
		var navigation_hovered := false
		for button: Button in _nav.values():
			navigation_hovered = navigation_hovered or (button.is_visible_in_tree() and button.is_hovered())
		focus.set_station_hovered(_hub_mode and (not category.is_empty() or navigation_hovered))


func _clear_station_hover() -> void:
	if _hub_mode:
		_highlight_station("")


func _open_weapon_info(identifier: String) -> void:
	_show_detail("weapon", identifier)


func _navigate(title: String) -> void:
	if installation != null and installation.active or module_installation != null and module_installation.active:
		return
	if title == "MES BUILDS":
		_show_builds()
	elif title == "MODULES":
		_open_modules(_module_category)
	elif title == "ARMES":
		_open_weapon_rack()
	else:
		_show_catalog("robot")
		_focus_selection()


func _show_builds() -> void:
	if installation.active or module_installation.active:
		return
	_hub_mode = false
	_view = "builds"
	_hide_equipment_display()
	_training_demo.close_enlarged()
	_training_demo.hide()
	_refresh_build_names()
	_layout()
	focus.show_garage()


func _hide_equipment_display() -> void:
	if _equipment_display != null:
		_equipment_display.hide()
	if stage != null:
		stage.robot.show()


func _focus_selection() -> void:
	if focus == null or _view not in ["catalog", "detail"]:
		return
	if _compact_layout and _view == "catalog":
		_hide_equipment_display()
		if _category == "robot":
			focus.show_overview()
		else:
			focus.show_station(_category)
		return
	var bounds: AABB = stage.robot.global_transform * stage._robot_pick_bounds
	bounds = bounds.grow(0.25)
	if _category == "weapon":
		if _equipment_display == null:
			_equipment_display = Node3D.new()
			_equipment_display.name = "CatalogWeaponDisplay"
			_equipment_display.position = Vector3(0, 1.9, 0)
			stage.world.add_child(_equipment_display)
		if _display_id != _preview_id:
			for child in _equipment_display.get_children():
				child.free()
			var model := (stage.WEAPON_MODELS[_preview_id] as PackedScene).instantiate() as Node3D
			_equipment_display.add_child(model)
			var raw: AABB = stage._bounds(model)
			model.position -= raw.get_center()
			var longest := maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
			var axis := Vector3.RIGHT if raw.size.x == longest else (Vector3.UP if raw.size.y == longest else Vector3.BACK)
			_equipment_display.basis = Basis(Quaternion(axis, Vector3.RIGHT)).scaled(Vector3.ONE * 2.8 / maxf(longest, 0.001))
			_display_id = _preview_id
		_equipment_display.show()
		stage.robot.hide()
		bounds = (_equipment_display.global_transform * stage._bounds(_equipment_display)).grow(0.35)
	else:
		_hide_equipment_display()
	focus.show_catalog_preview(_category, _preview_id, bounds)


func _show_catalog(kind: String) -> void:
	_hub_mode = false
	_view = "catalog"
	_category = kind
	_module_options = _grids[kind]
	_training_demo.close_enlarged()
	_training_demo.hide()
	_hide_equipment_display()
	_show_detail(kind, str(loadout[kind]))
	_layout()
	if not _compact_layout:
		_focus_selection()


func _show_detail(category: String, identifier: String) -> void:
	if installation != null and installation.active or module_installation != null and module_installation.active:
		return
	_preview_category = category
	_preview_id = identifier
	stage.module_stations.highlight_item(identifier if category in CATEGORY_TITLES else "")
	stage.weapon_rack.highlight_item(identifier if category == "weapon" else "")
	equip_button.disabled = str(loadout.get(category, "")) == identifier
	equip_button.text = "INSTALLÉ  ✓" if equip_button.disabled else "INSTALLER"
	_detail_icon.texture = _icons.get_icon(identifier)
	_detail_title.text = LOADOUT.display_name(identifier)
	_detail_description.text = LOADOUT.category_description(identifier)
	_detail_description.get_parent().scroll_vertical = 0
	_detail_stats.text = _stat_summary(identifier)
	_detail_stats.tooltip_text = LOADOUT.stat_line(identifier)
	_training_demo.show_equipment(identifier)
	_training_demo.hide()
	_demo_button.disabled = not TRAINING_DEMO.CLIPS.has(identifier)
	for kind in _choices:
		for id in _choices[kind]:
			var button: Button = _choices[kind][id]
			button.add_theme_stylebox_override("normal", _style(kind == category and id == identifier))
	_refresh_build_names()


func _stat_summary(identifier: String) -> String:
	var data: Dictionary = DATA.MODULE_DEFINITIONS.get(identifier, {})
	match identifier:
		"alternator": return "Sous %.0f s" % float(data.duration)
		"auxiliary_reactor": return "−%.2f s · toutes les %.2f s" % [float(data.reduction), float(data.interval)]
		"tracker": return "%d impacts · révélé %.0f s" % [int(data.hits), float(data.duration)]
		"inertia": return "Sous %.1f s · slow %.0f s" % [float(data.window), float(data.slow_duration)]
	return LOADOUT.stat_line(identifier)


func _refresh() -> void:
	var id: String = loadout.robot
	var definition: Dictionary = DATA.ROBOT_DEFINITIONS[id]
	_stat_name.text = LOADOUT.display_name(id)
	_health.text = "%d PV" % int(definition.max_health)
	_speed.text = ("%.1f m/s" % float(definition.move_speed)).replace(".", ",")
	for category in _choices:
		for identifier in _choices[category]:
			var button: Button = _choices[category][identifier]
			var selected := str(loadout[category]) == str(identifier)
			button.add_theme_stylebox_override("normal", _style(selected))
			button.get_node("Selected").visible = selected
	if stage.chassis_id != id:
		stage.set_chassis(id)
	if stage.weapon_id != str(loadout.weapon):
		stage.set_weapon(str(loadout.weapon))
	stage.set_equipped_modules(loadout)
	if module_installation != null and not module_installation.active:
		module_installation.sync_loadout(loadout)
	_refresh_build_names()
