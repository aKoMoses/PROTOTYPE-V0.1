extends Control

## Visible room browser. The cloud relay is configured once for the project.

const BG := Color("#15191d")
const PANEL := Color("#24282b")
const CREAM := Color("#f3ddbb")
const CYAN := Color("#42d9e5")
const MUTED := Color("#bda995")

var _flow: Node
var _room_field: LineEdit
var _status: Label
var _room_status: Label
var _room_list: VBoxContainer
var _start_button: Button
var _leave_button: Button
var _create_button: Button
var _refresh_button: Button
var _refresh_clock := 0.0


func configure(flow: Node) -> void:
	_flow = flow
	_build()
	var session := get_node("/root/NetworkSession")
	session.connection_changed.connect(_on_connection_changed)
	session.rooms_changed.connect(_on_rooms_changed)
	session.room_changed.connect(_on_room_changed)
	_update_controls()


func refresh() -> void:
	_refresh_clock = 0.0
	_update_controls()
	var session := get_node("/root/NetworkSession")
	if session.connected:
		session.refresh_rooms()
	else:
		session.connect_to_service()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var session := get_node("/root/NetworkSession")
	if not session.connected or not session.current_room.is_empty():
		return
	_refresh_clock += delta
	if _refresh_clock >= 3.0:
		refresh()


func _build() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 90)
	outer.add_theme_constant_override("margin_right", 90)
	outer.add_theme_constant_override("margin_top", 38)
	outer.add_theme_constant_override("margin_bottom", 38)
	add_child(outer)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	outer.add_child(content)
	content.add_child(_label("MULTIJOUEUR  •  DUEL 1 CONTRE 1", 30, CREAM))
	content.add_child(_label("Crée un salon ; ton frère le verra ici et pourra le rejoindre.", 16, MUTED))
	_status = _label("Connexion…", 15, MUTED)
	content.add_child(_status)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	content.add_child(controls)
	_room_field = LineEdit.new()
	_room_field.placeholder_text = "Nom de ton salon"
	_room_field.text = "Mon salon"
	_room_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_room_field)
	_create_button = _button("CRÉER UN SALON", _create, 205)
	controls.add_child(_create_button)
	_refresh_button = _button("ACTUALISER", refresh, 150)
	controls.add_child(_refresh_button)
	var room_panel := PanelContainer.new()
	room_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color("#526b70")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	room_panel.add_theme_stylebox_override("panel", style)
	content.add_child(room_panel)
	var room_margin := MarginContainer.new()
	room_margin.add_theme_constant_override("margin_left", 16)
	room_margin.add_theme_constant_override("margin_right", 16)
	room_margin.add_theme_constant_override("margin_top", 12)
	room_margin.add_theme_constant_override("margin_bottom", 12)
	room_panel.add_child(room_margin)
	var room_contents := VBoxContainer.new()
	room_contents.add_theme_constant_override("separation", 8)
	room_margin.add_child(room_contents)
	room_contents.add_child(_label("SALONS OUVERTS", 19, CYAN))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_contents.add_child(scroll)
	_room_list = VBoxContainer.new()
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_room_list)
	_room_status = _label("Aucun salon rejoint.", 17, CREAM)
	content.add_child(_room_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	_start_button = _button("LANCER LE MATCH", _start_match, 230)
	actions.add_child(_start_button)
	_leave_button = _button("QUITTER LE SALON", _leave, 215)
	actions.add_child(_leave_button)
	actions.add_spacer(false)
	actions.add_child(_button("RETOUR AU MENU", _return_menu, 215))


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(value: String, callback: Callable, width: float) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(width, 44)
	button.pressed.connect(callback)
	return button


func _create() -> void:
	get_node("/root/NetworkSession").create_room(_room_field.text)


func _leave() -> void:
	get_node("/root/NetworkSession").leave_room()


func _start_match() -> void:
	get_node("/root/NetworkSession").start_match()


func _return_menu() -> void:
	_flow.call("_open_menu")


func _on_connection_changed(is_connected: bool, message: String) -> void:
	_status.text = message
	_update_controls()
	if not is_connected:
		_on_rooms_changed([])
		_on_room_changed({})


func _on_rooms_changed(rooms: Array) -> void:
	for child in _room_list.get_children():
		child.queue_free()
	if rooms.is_empty():
		var empty_message := "Aucun salon ouvert. Crée le premier." if get_node("/root/NetworkSession").connected else "Connexion nécessaire pour afficher les salons."
		_room_list.add_child(_label(empty_message, 17, MUTED))
		return
	for room_variant in rooms:
		var room: Dictionary = room_variant
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_room_list.add_child(row)
		var title := _label(str(room.get("title", "Salon")), 18, CREAM)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var room_title := str(room.get("title", ""))
		var join := _button("REJOINDRE", func() -> void:
			get_node("/root/NetworkSession").join_room(room_title)
		, 145)
		join.disabled = not get_node("/root/NetworkSession").current_room.is_empty()
		row.add_child(join)


func _on_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		_room_status.text = "Aucun salon rejoint."
	else:
		var players := 1 if int(room.get("guest_id", 0)) == 0 else 2
		var phase := str(room.get("phase", "waiting"))
		_room_status.text = "%s  •  %d/2 joueurs  •  %s" % [str(room.get("title", "Salon")), players, "en attente" if phase == "waiting" else phase]
	_update_controls()


func _update_controls() -> void:
	var session := get_node("/root/NetworkSession")
	var room: Dictionary = session.current_room
	var in_room := not room.is_empty()
	_create_button.disabled = not session.connected or in_room
	_refresh_button.disabled = not session.connected
	_leave_button.disabled = not in_room
	_start_button.disabled = not in_room or int(room.get("host_id", 0)) != session.local_peer_id() or int(room.get("guest_id", 0)) == 0 or str(room.get("phase", "")) not in ["waiting", "finished"]
