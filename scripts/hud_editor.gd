class_name PrototypeHudEditor
extends Control

signal saved(layout: Dictionary)
signal closed
signal test_started
signal test_finished

const LAYOUT := preload("res://scripts/hud_layout.gd")
const CYAN := Color("#42d9e5")
const CREAM := Color("#f3ddbb")
const DARK := Color("#1c2228f2")

var controller
var draft: Dictionary = {}
var saved_layout: Dictionary = {}
var selection := ""
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var grid_visible := true
var snap_enabled := true
var grid_step := 32.0
var test_mode := false
var _pointer := -99
var _pointer_start := Vector2.ZERO
var _pointer_offset := Vector2.ZERO
var _gesture_before: Dictionary = {}
var _dragging := false
var _slider_before: Dictionary = {}
var _panel_side := 1
var _top: HFlowContainer
var _top_backdrop: ColorRect
var _side: PanelContainer
var _test_bar: PanelContainer
var _name_label: Label
var _size_label: Label
var _size_slider: HSlider
var _opacity_label: Label
var _opacity_slider: HSlider
var _visible_toggle: CheckButton
var _lock_toggle: CheckButton
var _elements: OptionButton
var _profile: OptionButton
var _grid_toggle: CheckButton
var _snap_toggle: CheckButton
var _precision: OptionButton
var _conflict_label: Label
var _exit_dialog: ConfirmationDialog
var _preset_dialog: ConfirmationDialog
var _reset_dialog: ConfirmationDialog
var _discard_dialog: ConfirmationDialog
var _pending_preset := ""
var _profile_index := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_top.minimum_size_changed.connect(_place_ui)
	get_viewport().size_changed.connect(_place_ui)
	_place_ui()
	visible = false

func _notification(what: int) -> void:
	if not visible or _exit_dialog == null:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_request_exit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dragging:
			_remember(_gesture_before)
		_pointer = -99
		_dragging = false

func begin(value) -> void:
	controller = value
	saved_layout = LAYOUT.load_active()
	draft = saved_layout.duplicate(true)
	var families: Dictionary = LAYOUT.load_all().families
	var record: Dictionary = families.get(LAYOUT.family(), {})
	_pending_preset = str(record.get("active_slot", "standard"))
	_profile_index = ["standard", "gaucher", "personal_1", "personal_2"].find(_pending_preset)
	_profile.select(maxi(0, _profile_index))
	undo_stack.clear()
	redo_stack.clear()
	selection = ""
	test_mode = false
	visible = true
	controller.set_preview(true)
	_top.visible = true
	_side.visible = true
	_test_bar.visible = false
	controller.set_layout(draft)
	if controller.touch != null:
		controller.touch.call("set_editor_editing", true)
		controller.touch.visible = true
	_rebuild_elements()
	_refresh_selected()
	queue_redraw()
	if not FileAccess.file_exists("user://prototype0_hud_editor_seen"):
		var marker := FileAccess.open("user://prototype0_hud_editor_seen", FileAccess.WRITE)
		if marker != null:
			marker.store_string("1")
			marker.close()
		_hint("Touchez un élément pour le déplacer ou modifier sa taille.")

func _build_ui() -> void:
	_top_backdrop = ColorRect.new()
	_top_backdrop.color = DARK
	_top_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_backdrop)
	_top = HFlowContainer.new()
	_top.add_theme_constant_override("h_separation", 5)
	_top.add_theme_constant_override("v_separation", 5)
	add_child(_top)
	_top.add_child(_button("Enregistrer", _save))
	_top.add_child(_button("Tester", _start_test))
	_top.add_child(_button("Annuler geste", _undo))
	_top.add_child(_button("Rétablir", _redo))
	_top.add_child(_button("Quitter", _request_exit))
	_profile = OptionButton.new()
	for title in ["Standard", "Gaucher", "Personnel 1", "Personnel 2"]:
		_profile.add_item(title)
	_profile.item_selected.connect(_on_profile_selected)
	_top.add_child(_profile)
	_grid_toggle = CheckButton.new()
	_grid_toggle.text = "Grille"
	_grid_toggle.button_pressed = true
	_grid_toggle.toggled.connect(_on_grid_toggled)
	_top.add_child(_grid_toggle)
	_snap_toggle = CheckButton.new()
	_snap_toggle.text = "Aimant"
	_snap_toggle.button_pressed = true
	_snap_toggle.toggled.connect(func(value: bool) -> void: snap_enabled = value)
	_top.add_child(_snap_toggle)
	_precision = OptionButton.new()
	for precision_name in ["Fin", "Moyen", "Large"]:
		_precision.add_item(precision_name)
	_precision.select(1)
	_precision.item_selected.connect(_on_precision_selected)
	_top.add_child(_precision)
	_side = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = DARK
	style.border_color = CYAN
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	_side.add_theme_stylebox_override("panel", style)
	add_child(_side)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.add_child(side_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	side_scroll.add_child(column)
	var side_header := HBoxContainer.new()
	column.add_child(side_header)
	side_header.add_child(_label("Éléments", 20))
	side_header.add_child(_button("↔", _swap_panel))
	_elements = OptionButton.new()
	_elements.fit_to_longest_item = false
	_elements.custom_minimum_size.x = 240
	_elements.item_selected.connect(_on_element_selected)
	column.add_child(_elements)
	_name_label = _label("Aucun élément", 17)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_name_label)
	_size_label = _label("Taille : 100 %", 15)
	column.add_child(_size_label)
	var size_row := HBoxContainer.new()
	column.add_child(size_row)
	size_row.add_child(_button("−", func() -> void: _nudge_size(-0.05)))
	_size_slider = HSlider.new()
	_size_slider.custom_minimum_size = Vector2(170, 42)
	_size_slider.step = 0.01
	_size_slider.value_changed.connect(_on_size_changed)
	_size_slider.drag_started.connect(_on_slider_start)
	_size_slider.drag_ended.connect(_on_slider_end)
	size_row.add_child(_size_slider)
	size_row.add_child(_button("+", func() -> void: _nudge_size(0.05)))
	_opacity_label = _label("Opacité : 100 %", 15)
	column.add_child(_opacity_label)
	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.35
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.05
	_opacity_slider.custom_minimum_size = Vector2(230, 42)
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	_opacity_slider.drag_started.connect(_on_slider_start)
	_opacity_slider.drag_ended.connect(_on_slider_end)
	column.add_child(_opacity_slider)
	_visible_toggle = CheckButton.new()
	_visible_toggle.text = "Afficher"
	_visible_toggle.toggled.connect(_on_visible_toggled)
	column.add_child(_visible_toggle)
	_lock_toggle = CheckButton.new()
	_lock_toggle.text = "Verrouiller"
	_lock_toggle.toggled.connect(_on_lock_toggled)
	column.add_child(_lock_toggle)
	var order_row := HBoxContainer.new()
	order_row.add_child(_button("Devant", func() -> void: _change_order(1)))
	order_row.add_child(_button("Derrière", func() -> void: _change_order(-1)))
	column.add_child(order_row)
	column.add_child(_button("Réinitialiser cet élément", _reset_element))
	column.add_child(_button("Tout réinitialiser", func() -> void: _reset_dialog.popup_centered()))
	column.add_child(_button("Annuler le brouillon", func() -> void: _discard_dialog.popup_centered()))
	_conflict_label = _label("", 13)
	_conflict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_conflict_label)
	_test_bar = PanelContainer.new()
	_test_bar.add_theme_stylebox_override("panel", style)
	add_child(_test_bar)
	_test_bar.add_child(_button("Retour à l'édition", _finish_test))
	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.title = "Modifications non enregistrées"
	_exit_dialog.dialog_text = "Enregistrer avant de quitter ?"
	_exit_dialog.ok_button_text = "Enregistrer"
	_exit_dialog.cancel_button_text = "Poursuivre l'édition"
	_exit_dialog.add_button("Abandonner", false, "discard")
	_exit_dialog.confirmed.connect(_save_and_close)
	_exit_dialog.custom_action.connect(_on_exit_custom_action)
	add_child(_exit_dialog)
	_preset_dialog = ConfirmationDialog.new()
	_preset_dialog.title = "Changer de disposition"
	_preset_dialog.dialog_text = "Appliquer cette disposition ? L'action restera annulable."
	_preset_dialog.confirmed.connect(_apply_pending_preset)
	_preset_dialog.canceled.connect(_cancel_pending_preset)
	add_child(_preset_dialog)
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Réinitialiser"
	_reset_dialog.dialog_text = "Remettre tous les éléments à leur place d'origine ?"
	_reset_dialog.confirmed.connect(_reset_all)
	add_child(_reset_dialog)
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "Annuler le brouillon"
	_discard_dialog.dialog_text = "Revenir exactement à la dernière disposition enregistrée ?"
	_discard_dialog.confirmed.connect(_discard_draft)
	add_child(_discard_dialog)

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	return button

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", CREAM)
	return label

func _place_ui() -> void:
	var safe := LAYOUT.safe_rect(get_viewport())
	_top.position = safe.position
	_top.size = Vector2(safe.size.x, maxf(50.0, _top.get_combined_minimum_size().y))
	_top_backdrop.position = Vector2.ZERO
	_top_backdrop.size = Vector2(get_viewport_rect().size.x, _top.position.y + _top.size.y + 8.0)
	var side_width := minf(290.0, safe.size.x)
	var side_y := _top.position.y + _top.size.y + 12.0
	_side.position = Vector2(safe.position.x if _panel_side == 0 else safe.end.x - side_width, side_y)
	_side.size = Vector2(side_width, minf(640.0, maxf(1.0, safe.end.y - side_y)))
	_test_bar.position = Vector2(safe.get_center().x - 105, safe.position.y)
	_test_bar.size = Vector2(210, 54)
	queue_redraw()

func _swap_panel() -> void:
	_panel_side = 1 - _panel_side
	_place_ui()

func _on_grid_toggled(value: bool) -> void:
	grid_visible = value
	queue_redraw()

func _on_precision_selected(index: int) -> void:
	grid_step = [16.0, 32.0, 64.0][index]
	queue_redraw()

func _save_and_close() -> void:
	if _save():
		_close()

func _on_exit_custom_action(action: StringName) -> void:
	if action == &"discard":
		_discard_and_close()

func _rebuild_elements() -> void:
	_elements.clear()
	if controller == null:
		return
	var names := LAYOUT.names()
	for identifier in controller.ids():
		_elements.add_item(str(names.get(identifier, identifier)))
		_elements.set_item_metadata(_elements.item_count - 1, identifier)

func _on_element_selected(index: int) -> void:
	select(str(_elements.get_item_metadata(index)))

func select(identifier: String) -> void:
	selection = identifier
	for i in range(_elements.item_count):
		if str(_elements.get_item_metadata(i)) == identifier:
			_elements.select(i)
			break
	_refresh_selected()
	queue_redraw()

func _refresh_selected() -> void:
	var enabled := selection != "" and draft.has(selection)
	_name_label.text = str(LAYOUT.names().get(selection, selection)) if enabled else "Aucun élément"
	_size_slider.editable = enabled
	_opacity_slider.editable = enabled
	_visible_toggle.disabled = not enabled or LAYOUT.is_required(selection)
	_lock_toggle.disabled = not enabled
	if not enabled:
		return
	var item: Dictionary = draft[selection]
	var limits := LAYOUT.size_limits(selection)
	_size_slider.set_block_signals(true)
	_size_slider.min_value = limits.x
	_size_slider.max_value = limits.y
	_size_slider.set_value_no_signal(float(item.s))
	_size_slider.set_block_signals(false)
	_opacity_slider.set_value_no_signal(float(item.o))
	_visible_toggle.set_pressed_no_signal(bool(item.v))
	_lock_toggle.set_pressed_no_signal(bool(item.l))
	_size_label.text = "Taille : %d %%" % int(round(float(item.s) * 100.0))
	_opacity_label.text = "Opacité : %d %%" % int(round(float(item.o) * 100.0))
	_update_conflicts()

func _remember(before: Dictionary) -> void:
	if JSON.stringify(before) == JSON.stringify(draft):
		return
	undo_stack.append(before.duplicate(true))
	if undo_stack.size() > 40:
		undo_stack.pop_front()
	redo_stack.clear()
	_update_conflicts()

func _apply_draft() -> void:
	controller.set_layout(draft)
	queue_redraw()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(draft.duplicate(true))
	draft = undo_stack.pop_back()
	_apply_draft()
	_refresh_selected()

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(draft.duplicate(true))
	draft = redo_stack.pop_back()
	_apply_draft()
	_refresh_selected()

func _on_slider_start() -> void:
	_slider_before = draft.duplicate(true)

func _on_slider_end(_changed: bool) -> void:
	_remember(_slider_before)
	_slider_before = {}

func _on_size_changed(value: float) -> void:
	if selection == "":
		return
	var before := draft.duplicate(true) if _slider_before.is_empty() else {}
	draft[selection].s = value
	_apply_draft()
	_refresh_selected()
	if not before.is_empty():
		_remember(before)

func _nudge_size(amount: float) -> void:
	if selection == "":
		return
	var limits := LAYOUT.size_limits(selection)
	_size_slider.value = clampf(float(draft[selection].s) + amount, limits.x, limits.y)

func _on_opacity_changed(value: float) -> void:
	if selection == "":
		return
	var before := draft.duplicate(true) if _slider_before.is_empty() else {}
	draft[selection].o = value
	_apply_draft()
	_refresh_selected()
	if not before.is_empty():
		_remember(before)

func _on_visible_toggled(value: bool) -> void:
	if selection == "" or LAYOUT.is_required(selection):
		return
	var before := draft.duplicate(true)
	draft[selection].v = value
	_apply_draft()
	_remember(before)

func _on_lock_toggled(value: bool) -> void:
	if selection == "":
		return
	var before := draft.duplicate(true)
	draft[selection].l = value
	_apply_draft()
	_remember(before)

func _change_order(direction: int) -> void:
	if selection == "":
		return
	var before := draft.duplicate(true)
	draft[selection].z = clampi(int(draft[selection].z) + direction, -50, 50)
	_apply_draft()
	_remember(before)

func _reset_element() -> void:
	if selection == "":
		return
	var before := draft.duplicate(true)
	draft[selection] = LAYOUT.standard()[selection]
	_apply_draft()
	_refresh_selected()
	_remember(before)

func _reset_all() -> void:
	var before := draft.duplicate(true)
	draft = LAYOUT.standard()
	_apply_draft()
	_refresh_selected()
	_remember(before)

func _discard_draft() -> void:
	draft = saved_layout.duplicate(true)
	undo_stack.clear()
	redo_stack.clear()
	_apply_draft()
	_refresh_selected()

func _on_profile_selected(index: int) -> void:
	_pending_preset = ["standard", "gaucher", "personal_1", "personal_2"][index]
	_preset_dialog.popup_centered()

func _apply_pending_preset() -> void:
	var before := draft.duplicate(true)
	draft = LAYOUT.preset(_pending_preset)
	_profile_index = _profile.selected
	_apply_draft()
	_refresh_selected()
	_remember(before)

func _cancel_pending_preset() -> void:
	_profile.select(maxi(0, _profile_index))
	_pending_preset = ["standard", "gaucher", "personal_1", "personal_2"][maxi(0, _profile_index)]

func _save() -> bool:
	if not LAYOUT.save_active(draft, LAYOUT.family(), _pending_preset):
		_hint("Enregistrement impossible.")
		get_node("/root/UiSfx").play("denied")
		return false
	saved_layout = draft.duplicate(true)
	saved.emit(saved_layout)
	_hint("Disposition enregistrée.")
	get_node("/root/UiSfx").play("confirmation")
	return true

func _request_exit() -> void:
	if test_mode:
		_finish_test()
		return
	if JSON.stringify(draft) != JSON.stringify(saved_layout):
		_exit_dialog.popup_centered()
	else:
		_close()

func _discard_and_close() -> void:
	_discard_draft()
	_close()

func _close() -> void:
	_pointer = -99
	controller.set_preview(false)
	if controller.touch != null:
		controller.touch.call("set_editor_editing", false)
	visible = false
	closed.emit()

func _start_test() -> void:
	if test_mode:
		return
	test_mode = true
	_top.visible = false
	_side.visible = false
	_test_bar.visible = true
	if controller.touch != null:
		controller.touch.call("set_editor_editing", false)
		controller.touch.call("set_editor_test", true)
	test_started.emit()
	queue_redraw()

func _finish_test() -> void:
	if not test_mode:
		return
	test_mode = false
	if controller.touch != null:
		controller.touch.call("set_editor_test", false)
		controller.touch.call("set_editor_editing", true)
	_top.visible = true
	_side.visible = true
	_test_bar.visible = false
	test_finished.emit()
	_apply_draft()
	queue_redraw()

func _hint(value: String) -> void:
	_conflict_label.text = value

func _update_conflicts() -> void:
	if controller == null:
		return
	var ids: Array = controller.ids().filter(func(identifier: String) -> bool: return identifier in LAYOUT.TOUCH_IDS)
	var count := 0
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			if bool(draft[ids[i]].v) and bool(draft[ids[j]].v) and _touch_conflict(ids[i], ids[j]):
				count += 1
	_conflict_label.text = "%d conflit(s) tactiles" % count if count > 0 else "Aucun conflit tactile"

func _touch_conflict(first: String, second: String) -> bool:
	var one: Rect2 = controller.widget_rect(first)
	var two: Rect2 = controller.widget_rect(second)
	return one.get_center().distance_to(two.get_center()) < one.size.x * 0.5 + two.size.x * 0.5

func _draw() -> void:
	if controller == null or test_mode or not visible:
		return
	var safe := LAYOUT.safe_rect(get_viewport())
	draw_rect(safe, Color(CYAN.r, CYAN.g, CYAN.b, 0.55), false, 2.0)
	if grid_visible:
		var step := grid_step * safe.size.y / 720.0
		var x := safe.position.x
		while x < safe.end.x:
			draw_line(Vector2(x, safe.position.y), Vector2(x, safe.end.y), Color(0.7, 0.8, 0.8, 0.12), 1.0)
			x += step
		var y := safe.position.y
		while y < safe.end.y:
			draw_line(Vector2(safe.position.x, y), Vector2(safe.end.x, y), Color(0.7, 0.8, 0.8, 0.12), 1.0)
			y += step
	var touch_ids: Array = controller.ids().filter(func(identifier: String) -> bool: return identifier in LAYOUT.TOUCH_IDS)
	for i in range(touch_ids.size()):
		var first: String = touch_ids[i]
		if not bool(draft[first].v):
			continue
		for j in range(i + 1, touch_ids.size()):
			var second: String = touch_ids[j]
			if bool(draft[second].v) and _touch_conflict(first, second):
				draw_rect(controller.widget_rect(first), Color("#e98959"), false, 2.0)
				draw_rect(controller.widget_rect(second), Color("#e98959"), false, 2.0)
	if selection != "":
		var rect: Rect2 = controller.widget_rect(selection)
		draw_rect(rect.grow(4), CYAN if bool(draft[selection].v) else Color("#efb765"), false, 3.0)
		draw_line(Vector2(rect.get_center().x, safe.position.y), Vector2(rect.get_center().x, safe.end.y), Color(CYAN.r, CYAN.g, CYAN.b, 0.22), 1.0)
		draw_line(Vector2(safe.position.x, rect.get_center().y), Vector2(safe.end.x, rect.get_center().y), Color(CYAN.r, CYAN.g, CYAN.b, 0.22), 1.0)
		if bool(draft[selection].l):
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, -8), "VERROUILLÉ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CREAM)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _exit_dialog.visible or _preset_dialog.visible or _reset_dialog.visible or _discard_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_request_exit()
		get_viewport().set_input_as_handled()
		return
	if test_mode:
		return
	var index := -99
	var point := Vector2.ZERO
	var pressed := false
	var released := false
	var moved := false
	if event is InputEventScreenTouch:
		index = event.index
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		index = event.index
		point = event.position
		moved = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
		index = -2
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and _pointer == -2:
		index = -2
		point = event.position
		moved = true
	else:
		return
	if pressed:
		if _top.get_global_rect().has_point(point) or _side.get_global_rect().has_point(point):
			return
		_pointer = index
		_pointer_start = point
		_dragging = false
		_gesture_before = draft.duplicate(true)
		var hit := _hit_widget(point)
		select(hit)
		_pointer_offset = controller.widget_rect(hit).get_center() - point if hit != "" else Vector2.ZERO
		get_viewport().set_input_as_handled()
	elif moved and index == _pointer:
		if selection != "" and not bool(draft[selection].l):
			if point.distance_to(_pointer_start) > 12.0:
				_dragging = true
				var target := point + _pointer_offset
				if snap_enabled:
					target = _snap_target(target)
				controller.set_widget_center(selection, target)
				draft = controller.layout.duplicate(true)
				queue_redraw()
		get_viewport().set_input_as_handled()
	elif released and index == _pointer:
		_pointer = -99
		if _dragging:
			_remember(_gesture_before)
		get_viewport().set_input_as_handled()

func _hit_widget(point: Vector2) -> String:
	var ids: Array = controller.ids()
	ids.reverse()
	var best := ""
	var best_order := -1000
	for identifier in ids:
		if not bool(draft[identifier].v):
			continue
		var order := int(draft[identifier].z)
		if order > best_order and controller.widget_rect(identifier).grow(7).has_point(point):
			best = identifier
			best_order = order
	return best

func _snap_target(target: Vector2) -> Vector2:
	var safe := LAYOUT.safe_rect(get_viewport())
	var threshold := maxf(8.0, safe.size.y * 0.014)
	var step := grid_step * safe.size.y / 720.0
	var result := target
	var selected_rect: Rect2 = controller.widget_rect(selection)
	var half := selected_rect.size * 0.5
	var x_guides := [safe.get_center().x, safe.position.x + half.x, safe.end.x - half.x]
	var y_guides := [safe.get_center().y, safe.position.y + half.y, safe.end.y - half.y]
	for identifier in controller.ids():
		if identifier == selection or not bool(draft[identifier].v):
			continue
		var rect: Rect2 = controller.widget_rect(identifier)
		x_guides.append_array([rect.get_center().x, rect.position.x - half.x, rect.end.x + half.x])
		y_guides.append_array([rect.get_center().y, rect.position.y - half.y, rect.end.y + half.y])
	var best_x := threshold
	for guide in x_guides:
		var distance := absf(float(guide) - target.x)
		if distance < best_x:
			best_x = distance
			result.x = float(guide)
	var best_y := threshold
	for guide in y_guides:
		var distance := absf(float(guide) - target.y)
		if distance < best_y:
			best_y = distance
			result.y = float(guide)
	if best_x == threshold:
		var grid_x := safe.position.x + roundf((target.x - safe.position.x) / step) * step
		if absf(grid_x - target.x) < threshold:
			result.x = grid_x
	if best_y == threshold:
		var grid_y := safe.position.y + roundf((target.y - safe.position.y) / step) * step
		if absf(grid_y - target.y) < threshold:
			result.y = grid_y
	return result
