extends "res://scripts/ui/industrial_screen.gd"

const PORTRAITS := preload("res://art/ui/industrial/room-portraits.png")
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
var _browser: Control
var _joined: Control
var _connection_badge: Label
var _guest_status: Label
var _guest_portrait: TextureRect
var _host_label: Label
var _guest_label: Label
var _joined_hint: Label

func configure(flow: Node) -> void:
	_flow = flow
	_build()
	var session := get_node("/root/NetworkSession")
	session.connection_changed.connect(_on_connection_changed)
	session.rooms_changed.connect(_on_rooms_changed)
	session.room_changed.connect(_on_room_changed)
	session.lobby_busy_changed.connect(func(_busy: bool) -> void: _update_controls())
	_on_rooms_changed([])
	_on_room_changed(session.current_room)
	_update_controls()

func refresh() -> void:
	_refresh_clock = 0.0
	_update_controls()
	var session := get_node("/root/NetworkSession")
	_on_room_changed(session.current_room)
	if session.connected:
		session.refresh_rooms()
	else:
		session.connect_to_service()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var session := get_node("/root/NetworkSession")
	if not session.connected or session.lobby_busy or not session.current_room.is_empty():
		return
	_refresh_clock += delta
	if _refresh_clock >= 3.0:
		refresh()

func _portrait(parent: Node, first: bool, rect: Rect2) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = PORTRAITS
	atlas.region = Rect2(375, 325, 250, 225) if first else Rect2(1054, 325, 250, 225)
	return icon(parent, atlas, rect)

func _build() -> void:
	title_label.text = "MULTIJOUEUR"
	subtitle_label.text = "DUEL 1 CONTRE 1"
	subtitle_label.position.x = 527
	_connection_badge = text(canvas, "● HORS LIGNE", Rect2(956, 125, 165, 30), 15, MUTED, true)
	_browser = Control.new()
	_browser.name = "RoomBrowser"
	canvas.add_child(_browser)
	var create := section(_browser, "CRÉER UN SALON", Rect2(165, 190, 330, 346))
	text(create, "Nom du salon", Rect2(22, 75, 285, 36), 18)
	_room_field = LineEdit.new()
	_room_field.name = "RoomName"
	_room_field.position = Vector2(22, 116)
	_room_field.size = Vector2(286, 44)
	_room_field.text = "Mon salon"
	_room_field.max_length = 25
	_room_field.placeholder_text = "Nom du salon"
	_room_field.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#151c20")
		style.border_color = CYAN if state == "focus" else Color("#606a6c")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 12
		style.content_margin_right = 12
		_room_field.add_theme_stylebox_override(state, style)
	create.add_child(_room_field)
	_create_button = button(create, "CRÉER LE SALON", Rect2(22, 180, 286, 50), _create, true)
	_create_button.name = "CreateRoom"
	_portrait(create, true, Rect2(28, 253, 100, 78))
	text(create, "VS", Rect2(137, 262, 44, 45), 23, MUTED, true)
	_portrait(create, false, Rect2(202, 253, 100, 78))
	var rooms := section(_browser, "SALONS OUVERTS", Rect2(512, 190, 606, 346))
	_refresh_button = button(rooms, "↻  ACTUALISER", Rect2(406, 11, 183, 40), refresh)
	_refresh_button.add_theme_font_size_override("font_size", 15)
	_refresh_button.name = "RefreshRooms"
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(16, 71)
	scroll.size = Vector2(574, 257)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rooms.add_child(scroll)
	_room_list = VBoxContainer.new()
	_room_list.name = "OpenRooms"
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_room_list)
	_status = text(_browser, "Choisis un salon ou crée le tien.", Rect2(185, 580, 630, 45), 16, MUTED)
	button(_browser, "RETOUR AU MENU", Rect2(856, 583, 248, 44), _return_menu).name = "LobbyReturn"
	_joined = Control.new()
	_joined.name = "JoinedRoom"
	canvas.add_child(_joined)
	var host := plate(_joined, Rect2(170, 195, 421, 310))
	text(host, "HÔTE", Rect2(115, 15, 190, 34), 19, MUTED, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait(host, true, Rect2(110, 63, 200, 166))
	_host_label = text(host, "Vous", Rect2(20, 220, 381, 47), 30, CREAM, true)
	_host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text(host, "● CONNECTÉ", Rect2(20, 267, 381, 30), 17, CYAN, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var guest := plate(_joined, Rect2(686, 195, 421, 310))
	text(guest, "INVITÉ", Rect2(115, 15, 190, 34), 19, MUTED, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guest_portrait = _portrait(guest, false, Rect2(110, 63, 200, 166))
	_guest_label = text(guest, "Adversaire", Rect2(20, 220, 381, 47), 30, CREAM, true)
	_guest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guest_status = text(guest, "EN ATTENTE", Rect2(20, 267, 381, 30), 17, MUTED, true)
	_guest_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text(_joined, "VS", Rect2(603, 302, 72, 74), 38, MUTED, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_status = text(_joined, "1 / 2 JOUEURS", Rect2(440, 512, 400, 39), 20, CYAN, true)
	_room_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leave_button = button(_joined, "QUITTER LE SALON", Rect2(189, 582, 265, 46), _leave)
	_leave_button.name = "LeaveRoom"
	_joined_hint = text(_joined, "L’hôte lance le duel.", Rect2(462, 570, 340, 64), 15, MUTED)
	_joined_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_joined_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_button = button(_joined, "LANCER LE MATCH", Rect2(817, 580, 287, 50), _start_match, true)
	_start_button.name = "StartMatch"
	footer()

func _create() -> void:
	get_node("/root/NetworkSession").create_room(_room_field.text)

func _leave() -> void:
	get_node("/root/NetworkSession").leave_room()

func _start_match() -> void:
	get_node("/root/NetworkSession").start_match()

func _return_menu() -> void:
	_flow.call("_open_menu")

func _on_connection_changed(is_connected: bool, message: String) -> void:
	if is_visible_in_tree():
		for failure in ["impossible", "indisponible", "incompatible", "trop longue", "Configuration requise"]:
			if message.contains(failure):
				get_node("/root/UiSfx").play("denied")
				break
	# Project configuration belongs in the editor, never in the player's menu.
	_status.text = "Le multijoueur est indisponible sur cette version." if message.begins_with("Configuration requise") else message
	if not get_node("/root/NetworkSession").current_room.is_empty():
		_joined_hint.text = _status.text
	_update_controls()
	if not is_connected:
		_on_rooms_changed([])
		_on_room_changed({})

func _on_rooms_changed(rooms: Array) -> void:
	for child in _room_list.get_children():
		_room_list.remove_child(child)
		child.queue_free()
	if rooms.is_empty():
		var empty := Control.new()
		empty.custom_minimum_size = Vector2(540, 184)
		_room_list.add_child(empty)
		var online: bool = get_node("/root/NetworkSession").connected
		text(empty, "Aucun salon ouvert" if online else "Connexion en cours…", Rect2(10, 35, 520, 42), 22, CREAM, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text(empty, "Crée le premier salon." if online else "Les salons apparaîtront ici.", Rect2(10, 85, 520, 42), 17, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	for room in rooms:
		var row := Control.new()
		row.custom_minimum_size = Vector2(540, 76)
		_room_list.add_child(row)
		var card := plate(row, Rect2(0, 0, 550, 76))
		_portrait(card, true, Rect2(10, 9, 59, 58))
		var room_title := str(room.get("title", "Salon"))
		text(card, room_title, Rect2(84, 10, 285, 29), 20, CREAM, true).tooltip_text = room_title
		var compatible := bool(room.get("compatible", false))
		text(card, "En attente · %d / 2" % int(room.get("players", 1)) if compatible else "Version différente du jeu", Rect2(84, 40, 285, 25), 16, MUTED)
		var join := button(card, "REJOINDRE", Rect2(376, 17, 161, 43), func() -> void:
			get_node("/root/NetworkSession").join_room(room_title)
		)
		join.name = "JoinRoom"
		join.set_meta("compatible", compatible)
		join.disabled = not compatible or get_node("/root/NetworkSession").lobby_busy or not get_node("/root/NetworkSession").current_room.is_empty()
		if not compatible:
			join.tooltip_text = "Installez tous les deux la même version du jeu."

func _on_room_changed(room: Dictionary) -> void:
	var in_room := not room.is_empty()
	_browser.visible = not in_room
	_joined.visible = in_room
	title_label.text = str(room.get("title", "Salon")).to_upper() if in_room else "MULTIJOUEUR"
	title_label.add_theme_font_size_override("font_size", 30 if in_room else 39)
	title_label.size.x = 720 if in_room else 385
	subtitle_label.visible = not in_room
	if in_room:
		var has_guest := int(room.get("guest_id", 0)) != 0
		var am_host: bool = get_node("/root/NetworkSession").local_peer_id() == int(room.get("host_id", -1))
		_host_label.text = "Vous" if am_host else "Adversaire"
		_guest_label.text = "Adversaire" if am_host else "Vous"
		_guest_portrait.modulate.a = 1.0 if has_guest else 0.22
		_guest_status.text = "● CONNECTÉ" if has_guest else "EN ATTENTE"
		_guest_status.add_theme_color_override("font_color", CYAN if has_guest else MUTED)
		_room_status.text = "%d / 2 JOUEURS" % (2 if has_guest else 1)
		_joined_hint.text = "Vous pouvez lancer le duel." if am_host and has_guest else "En attente d'un deuxième joueur." if am_host else "L'hôte lance le duel."
	_update_controls()

func _update_controls() -> void:
	var session := get_node("/root/NetworkSession")
	var room: Dictionary = session.current_room
	var in_room := not room.is_empty()
	_connection_badge.text = "● EN LIGNE" if session.connected else "● HORS LIGNE"
	_connection_badge.add_theme_color_override("font_color", CYAN if session.connected else MUTED)
	_create_button.disabled = not session.connected or in_room
	_create_button.disabled = _create_button.disabled or session.lobby_busy
	_create_button.text = "CONNEXION…" if session.lobby_busy else "CRÉER LE SALON"
	_refresh_button.disabled = session._connecting or session.lobby_busy
	_refresh_button.text = "↻  ACTUALISER" if session.connected else "RÉESSAYER"
	_leave_button.disabled = not in_room
	_start_button.disabled = not session.connected or not in_room or int(room.get("host_id", -1)) < 0 or int(room.get("host_id", -1)) != session.local_peer_id() or int(room.get("guest_id", 0)) == 0 or str(room.get("phase", "")) not in ["waiting", "finished"]
	for item in [_create_button, _refresh_button, _leave_button, _start_button]:
		item.queue_redraw()
	for row in _room_list.get_children():
		for join in row.find_children("JoinRoom", "Button", true, false):
			join.disabled = not session.connected or session.lobby_busy or in_room or not bool(join.get_meta("compatible", false))
