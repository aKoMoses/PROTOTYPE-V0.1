extends "res://scripts/main.gd"

var _role := ""
var _session: Node
var _joining := false
var _started := false
var _hit_checked := false


func _ready() -> void:
	super._ready()
	var arguments := OS.get_cmdline_user_args()
	_role = "host" if "host" in arguments else "guest" if "guest" in arguments else ""
	_session = get_node("/root/NetworkSession")
	_session.connection_changed.connect(_on_connection)
	_session.rooms_changed.connect(_on_rooms)
	_session.room_changed.connect(_on_room)
	_session.round_live.connect(_on_live)
	_session.opponent_hit.connect(_on_hit)
	_session.round_finished.connect(_on_finished)
	game_flow.set("loadout", {"robot": "polyvalent", "weapon": "blaster", "offensive": "modulo_drone", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	_session.connect_to_service()
	await get_tree().create_timer(20.0).timeout
	_fail("timeout")


func _on_connection(ok: bool, message: String) -> void:
	if ok and _role == "host":
		_session.create_room("Combat test")
	elif not ok and not message.begins_with("Connexion"):
		_fail(message)


func _on_rooms(rooms: Array) -> void:
	if _role != "guest" or _joining:
		return
	if rooms.is_empty():
		await get_tree().create_timer(0.25).timeout
		_session.refresh_rooms()
		return
	_joining = true
	_session.join_room(str(rooms[0].title))


func _on_room(room: Dictionary) -> void:
	if _role == "host" and not _started and int(room.get("host_id", -1)) == _session.local_peer_id() and int(room.get("guest_id", 0)) != 0:
		_started = true
		_session.start_match()


func _on_live() -> void:
	await get_tree().process_frame
	if network_match == null:
		_fail("contrôleur de match absent")
		return
	if not bool(player.call("is_gameplay_enabled")):
		_fail("joueur inactif")
		return
	if _role == "host":
		await get_tree().create_timer(0.3).timeout
		target.call("take_damage", 50.0, "player", "network_test_hit")


func _on_hit(amount: float, _source: String, _attack: String) -> void:
	if _role != "guest" or amount != 50.0:
		return
	await get_tree().process_frame
	if float(player.call("get_health")) >= float(player.call("get_max_health")):
		_fail("dégât distant non appliqué")
		return
	_hit_checked = true
	player.call("take_damage", 2000.0, "test", "network_test_death")
	if not bool(player.call("is_real_dead")):
		_fail("mort locale non appliquée")


func _on_finished(host_score: int, guest_score: int, winner_id: int, over: bool) -> void:
	if host_score != 1 or guest_score != 0 or winner_id != int(_session.current_room.host_id) or over:
		_fail("résultat de match incorrect")
		return
	if _role == "guest" and not _hit_checked:
		_fail("résultat reçu avant les dégâts")
		return
	print("NETWORK GAME TEST: PASS [%s]" % _role)
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("NETWORK GAME TEST: FAIL [%s] %s" % [_role, message])
	get_tree().quit(1)
