extends Control

signal expanded_changed(expanded: bool)
signal reset_requested

const WINDOW_SECONDS := 5.0
const BACKGROUND := Color("#1c2429ef")
const CREAM := Color("#f4ead6")
const CYAN := Color("#6fe0eb")
const MUTED := Color("#a9b7b7")

var _expanded := true
var _started := false
var _elapsed := 0.0
var _refresh_clock := 0.0
var _total_damage := 0.0
var _total_by_target: Dictionary = {}
var _sources_all: Dictionary = {}
var _sources_by_target: Dictionary = {}
var _recent_hits: Array[Dictionary] = []
var _target_names: Dictionary = {}
var _target_order: Array[int] = []
var _selected_target_id := -1

var _panel: PanelContainer
var _chip: Button
var _dps_value: Label
var _total_value: Label
var _time_value: Label
var _target_picker: OptionButton
var _empty_label: Label
var _source_rows: Array[HBoxContainer] = []
var _source_names: Array[Label] = []
var _source_bars: Array[ProgressBar] = []
var _source_percents: Array[Label] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_panel()
	_expanded = not (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"))
	_apply_expanded()
	_refresh()

func _process(delta: float) -> void:
	if not _started or get_tree().paused:
		return
	_elapsed += delta
	_refresh_clock += delta
	if _refresh_clock >= 0.1:
		_refresh_clock = 0.0
		_purge_recent_hits()
		_refresh()

func register_target(target: Node, title: String) -> void:
	var target_id := target.get_instance_id()
	if _target_names.has(target_id):
		return
	_target_names[target_id] = title
	_target_order.append(target_id)
	_rebuild_target_picker()

func unregister_target(target: Node) -> void:
	var target_id := target.get_instance_id()
	_target_names.erase(target_id)
	_target_order.erase(target_id)
	if _selected_target_id == target_id:
		_selected_target_id = -1
	_rebuild_target_picker()

func record_damage(amount: float, source_id: String, attack_id: String, target: Node) -> void:
	if amount <= 0.0 or not source_id.begins_with("player") or not is_instance_valid(target):
		return
	if not _started:
		_started = true
		_elapsed = 0.0
	var target_id := target.get_instance_id()
	var category := _damage_category(source_id, attack_id)
	_total_damage += amount
	_total_by_target[target_id] = float(_total_by_target.get(target_id, 0.0)) + amount
	_sources_all[category] = float(_sources_all.get(category, 0.0)) + amount
	var target_sources: Dictionary = _sources_by_target.get(target_id, {})
	target_sources[category] = float(target_sources.get(category, 0.0)) + amount
	_sources_by_target[target_id] = target_sources
	_recent_hits.append({"time": _elapsed, "amount": amount, "target_id": target_id})
	_refresh()

func reset_measurement() -> void:
	_started = false
	_elapsed = 0.0
	_refresh_clock = 0.0
	_total_damage = 0.0
	_total_by_target.clear()
	_sources_all.clear()
	_sources_by_target.clear()
	_recent_hits.clear()
	_refresh()

func get_total_damage(target: Node = null) -> float:
	if target == null:
		return _total_damage
	return float(_total_by_target.get(target.get_instance_id(), 0.0))

func get_elapsed() -> float:
	return _elapsed

func get_recent_dps() -> float:
	_purge_recent_hits()
	var recent_damage := 0.0
	for hit in _recent_hits:
		if _selected_target_id == -1 or int(hit.target_id) == _selected_target_id:
			recent_damage += float(hit.amount)
	return recent_damage / maxf(1.0, minf(WINDOW_SECONDS, _elapsed)) if _started else 0.0

func get_source_damage(category: String) -> float:
	return float(_sources_all.get(category, 0.0))

func set_target_filter(target: Node = null) -> void:
	_selected_target_id = target.get_instance_id() if target != null and is_instance_valid(target) else -1
	_rebuild_target_picker()

func is_expanded() -> bool:
	return _expanded

func toggle_panel() -> void:
	set_expanded(not _expanded)

func set_expanded(value: bool) -> void:
	if _expanded == value:
		return
	_expanded = value
	_apply_expanded()
	expanded_changed.emit(_expanded)

func _damage_category(source_id: String, attack_id: String) -> String:
	if source_id.begins_with("player:") and attack_id == "":
		return "Brûlure"
	if attack_id.begins_with("blaster:"):
		return "Blaster"
	if attack_id.begins_with("shotgun:"):
		return "Shotgun"
	if attack_id.begins_with("longshot:"):
		return "Longshot"
	if attack_id.begins_with("modulo_drone:"):
		return "Drone"
	if attack_id.begins_with("javelin:"):
		return "Javelin"
	if attack_id.begins_with("legacy_attack:"):
		return "Axe"
	return "Autre"

func _purge_recent_hits() -> void:
	while not _recent_hits.is_empty() and float(_recent_hits[0].time) < _elapsed - WINDOW_SECONDS:
		_recent_hits.pop_front()

func _rebuild_target_picker() -> void:
	if _target_picker == null:
		return
	_target_picker.clear()
	_target_picker.add_item("Toutes les cibles")
	var selected_index := 0
	for target_id in _target_order:
		_target_picker.add_item(str(_target_names[target_id]))
		if target_id == _selected_target_id:
			selected_index = _target_picker.item_count - 1
	_target_picker.select(selected_index)
	_refresh()

func _on_target_selected(index: int) -> void:
	_selected_target_id = -1 if index == 0 else _target_order[index - 1]
	_refresh()

func _refresh() -> void:
	if _dps_value == null or _chip == null or _empty_label == null:
		return
	var total := _total_damage if _selected_target_id == -1 else float(_total_by_target.get(_selected_target_id, 0.0))
	_dps_value.text = str(roundi(get_recent_dps()))
	_total_value.text = str(roundi(total))
	_time_value.text = "%02d:%02d" % [int(_elapsed / 60.0), int(_elapsed) % 60]
	_chip.text = "DÉGÂTS  %d  •  K" % roundi(_total_damage)
	var sources: Dictionary = _sources_all if _selected_target_id == -1 else _sources_by_target.get(_selected_target_id, {})
	var categories: Array[String] = []
	for category in sources.keys():
		categories.append(str(category))
	categories.sort_custom(func(a: String, b: String) -> bool: return float(sources[a]) > float(sources[b]))
	_empty_label.visible = categories.is_empty()
	for index in range(_source_rows.size()):
		var row := _source_rows[index]
		row.visible = index < categories.size()
		if not row.visible:
			continue
		var category := categories[index]
		var share := 100.0 * float(sources[category]) / maxf(0.001, total)
		_source_names[index].text = category
		_source_bars[index].value = share
		_source_percents[index].text = "%d %%" % roundi(share)

func _apply_expanded() -> void:
	if _panel == null or _chip == null:
		return
	_panel.visible = _expanded
	_chip.visible = not _expanded

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MeterPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -346.0
	_panel.offset_right = -16.0
	_panel.offset_top = -420.0
	_panel.offset_bottom = -16.0
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_panel.offset_left = -346.0
		_panel.offset_right = -16.0
		_panel.offset_top = 78.0
		_panel.offset_bottom = 434.0
	_panel.add_theme_stylebox_override("panel", _box(BACKGROUND, Color("#b89b78"), 2, 8))
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	heading.add_child(_label("KIKIMÈTRE", 23, CREAM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	var hide := _button("K  MASQUER")
	hide.custom_minimum_size = Vector2(92, 34)
	hide.pressed.connect(toggle_panel)
	heading.add_child(hide)
	column.add_child(HSeparator.new())
	var dps_row := HBoxContainer.new()
	column.add_child(dps_row)
	dps_row.add_child(_label("DPS 5 s", 20, CYAN))
	var dps_spacer := Control.new()
	dps_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dps_row.add_child(dps_spacer)
	_dps_value = _label("0", 34, CYAN)
	dps_row.add_child(_dps_value)
	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 22)
	column.add_child(summary)
	var total_column := VBoxContainer.new()
	total_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(total_column)
	total_column.add_child(_label("DÉGÂTS", 13, MUTED))
	_total_value = _label("0", 21, CREAM)
	total_column.add_child(_total_value)
	var time_column := VBoxContainer.new()
	time_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(time_column)
	time_column.add_child(_label("TEMPS", 13, MUTED))
	_time_value = _label("00:00", 21, CREAM)
	time_column.add_child(_time_value)
	_target_picker = OptionButton.new()
	_target_picker.custom_minimum_size.y = 38
	_target_picker.add_theme_stylebox_override("normal", _box(Color("#252e33"), Color("#697d81"), 1, 5))
	_target_picker.add_theme_color_override("font_color", CREAM)
	_target_picker.item_selected.connect(_on_target_selected)
	column.add_child(_target_picker)
	_rebuild_target_picker()
	var sources_title := _label("RÉPARTITION", 13, MUTED)
	column.add_child(sources_title)
	_empty_label = _label("Aucun dégât pour cet essai", 13, MUTED)
	column.add_child(_empty_label)
	for _index in range(4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		column.add_child(row)
		_source_rows.append(row)
		var name := _label("", 13, CREAM)
		name.custom_minimum_size.x = 78
		row.add_child(name)
		_source_names.append(name)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(128, 15)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", _box(Color("#4f463c"), Color.TRANSPARENT, 0, 3))
		bar.add_theme_stylebox_override("fill", _box(CYAN, Color.TRANSPARENT, 0, 3))
		row.add_child(bar)
		_source_bars.append(bar)
		var percent := _label("", 13, CREAM)
		percent.custom_minimum_size.x = 38
		row.add_child(percent)
		_source_percents.append(percent)
	var reset := _button("NOUVEL ESSAI  F5")
	reset.custom_minimum_size.y = 38
	reset.pressed.connect(func() -> void: reset_requested.emit())
	column.add_child(reset)
	_chip = _button("DÉGÂTS  0  •  K")
	_chip.name = "MeterChip"
	_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_chip.offset_left = -190.0
	_chip.offset_right = -16.0
	_chip.offset_top = -57.0
	_chip.offset_bottom = -16.0
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_chip.offset_left = -190.0
		_chip.offset_right = -16.0
		_chip.offset_top = 78.0
		_chip.offset_bottom = 119.0
	_chip.pressed.connect(toggle_panel)
	add_child(_chip)

func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 38
	button.add_theme_stylebox_override("normal", _box(Color("#2a343a"), Color("#71898a"), 1, 5))
	button.add_theme_stylebox_override("hover", _box(Color("#3b5960"), CYAN, 1, 5))
	button.add_theme_color_override("font_color", CREAM)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

func _box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
