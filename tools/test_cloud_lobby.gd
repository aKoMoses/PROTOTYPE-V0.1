extends Node

var _session: Node
var _role := ""
var _started := false
var _joining := false
var _prepared := false
var _live := false


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	_role = "host" if "host" in arguments else "guest" if "guest" in arguments else ""
	if _role.is_empty():
		_fail("role requis")
		return
	_session = get_node("/root/NetworkSession")
	_session.connection_changed.connect(_on_connection)
	_session.rooms_changed.connect(_on_rooms)
	_session.room_changed.connect(_on_room)
	_session.match_started.connect(_on_match)
	_session.round_prepared.connect(_on_prepared)
	_session.round_live.connect(_on_live)
	_session.round_finished.connect(_on_finished)
	_session.connect_to_service()
	await get_tree().create_timer(20.0).timeout
	_fail("timeout")


func _on_connection(ok: bool, message: String) -> void:
	print("TEST %s connection %s %s" % [_role, ok, message])
	if ok and _role == "host":
		_session.create_room("Salon test")
	elif not ok and not message.begins_with("Connexion"):
		_fail(message)


func _on_rooms(rooms: Array) -> void:
	print("TEST %s rooms %d" % [_role, rooms.size()])
	if _role != "guest" or _joining:
		return
	if rooms.is_empty():
		await get_tree().create_timer(0.3).timeout
		_session.refresh_rooms()
		return
	_joining = true
	_session.join_room(str(rooms[0].title))


func _on_room(room: Dictionary) -> void:
	print("TEST %s room %s" % [_role, room])
	if _role == "host" and not _started and int(room.get("guest_id", 0)) != 0:
		_started = true
		_session.start_match()


func _on_match(host_id: int, guest_id: int) -> void:
	print("TEST %s match %d %d" % [_role, host_id, guest_id])
	if host_id == guest_id or host_id < 0 or guest_id < 0:
		_fail("IDs invalides")
	else:
		_session.match_ready()


func _on_prepared(number: int, host_score: int, guest_score: int) -> void:
	_prepared = number == 1 and host_score == 0 and guest_score == 0
	if not _prepared:
		_fail("préparation invalide")


func _on_live() -> void:
	_live = true
	if _role == "guest":
		_session.report_death()


func _on_finished(host_score: int, guest_score: int, winner_id: int, over: bool) -> void:
	if not _prepared or not _live or host_score != 1 or guest_score != 0 or winner_id < 0 or over:
		_fail("résultat invalide")
		return
	print("CLOUD LOBBY TEST: PASS [%s]" % _role)
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("CLOUD LOBBY TEST: FAIL [%s] %s" % [_role, message])
	get_tree().quit(1)
