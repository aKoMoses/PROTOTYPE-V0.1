extends Node

## Hosted lobby and two-player relay, through GD-Sync.

signal connection_changed(connected: bool, message: String)
signal rooms_changed(rooms: Array)
signal room_changed(room: Dictionary)
signal match_started(host_id: int, guest_id: int)
signal round_prepared(round_number: int, host_score: int, guest_score: int)
signal round_live
signal round_finished(host_score: int, guest_score: int, winner_id: int, match_over: bool)
signal opponent_state(position: Vector3, aim: Vector3, health: float, max_health: float, weapon: String)
signal opponent_hit(amount: float, source_id: String, attack_id: String)
signal opponent_effect(effect: String, duration: float, value: float)
signal pose_received(pose: Dictionary)
signal action_requested(request: Dictionary)
signal action_received(event: Dictionary)
signal combat_received(snapshot: Dictionary)

const KEY_STORE := preload("res://addons/GD-Sync/Scripts/KeyStore.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")

# Rooms contain exactly two humans. Broadcast reaches only the other peer and
# avoids the addon's target-id bit packing; every receiver checks the sender.

var connected := false
var current_room: Dictionary = {}
var _service: Node
var _connecting := false
var _phase := "waiting"
var _host_score := 0
var _guest_score := 0
var _round_number := 0
var _ready_ids: Dictionary = {}
var _match_generation := 0
var round_loadouts: Dictionary = {}
var _match_token := ""
var _combat_sequence := 0


func _ready() -> void:
	_service = get_node_or_null("/root/GDSync")
	if _service == null:
		return
	_service.connected.connect(_on_connected)
	_service.connection_failed.connect(_on_connection_failed)
	_service.disconnected.connect(_on_disconnected)
	_service.lobbies_received.connect(_on_lobbies_received)
	_service.lobby_created.connect(_on_lobby_created)
	_service.lobby_creation_failed.connect(_on_lobby_creation_failed)
	_service.lobby_joined.connect(_on_lobby_joined)
	_service.lobby_join_failed.connect(_on_lobby_join_failed)
	_service.client_joined.connect(_on_client_joined)
	_service.client_left.connect(_on_client_left)
	_service.host_changed.connect(_on_host_changed)
	for method_name in ["_remote_room_state", "_remote_start_match", "_host_match_ready",
		"_remote_round_prepared", "_remote_round_live", "_remote_round_finished",
		"_host_pose", "_host_action", "_remote_action", "_remote_combat"]:
		_service.expose_func(Callable(self, method_name))


func local_peer_id() -> int:
	return int(_service.get_client_id()) if _service != null else -1


func connect_to_service() -> void:
	if _service == null:
		connection_changed.emit(false, "Service multijoueur indisponible.")
		return
	if connected or _connecting:
		if connected:
			refresh_rooms()
		return
	var local_test := "--network-local-test" in OS.get_cmdline_user_args()
	if not local_test and not KEY_STORE.has_keys():
		connection_changed.emit(false, "Configuration requise : Projet > Outils > GD-Sync dans Godot.")
		return
	_connecting = true
	connection_changed.emit(false, "Connexion au service multijoueur…")
	if local_test:
		_service.start_local_multiplayer()
	else:
		_service.start_multiplayer()


func _on_connected() -> void:
	_connecting = false
	connected = true
	connection_changed.emit(true, "Connecté. Crée ou rejoins un salon.")
	refresh_rooms()


func _on_connection_failed(error: int) -> void:
	_connecting = false
	connected = false
	connection_changed.emit(false, "Connexion impossible (%d)." % error)


func _on_disconnected() -> void:
	_match_generation += 1
	_phase = "waiting"
	_connecting = false
	connected = false
	current_room = {}
	room_changed.emit({})
	connection_changed.emit(false, "Connexion au service perdue.")


func refresh_rooms() -> void:
	if connected:
		_service.get_public_lobbies()


func _on_lobbies_received(lobbies: Array) -> void:
	var rooms: Array = []
	for item_variant in lobbies:
		var item: Dictionary = item_variant
		if int(item.get("PlayerCount", 0)) >= 2 or not bool(item.get("Open", true)):
			continue
		rooms.append({"title": str(item.get("Name", "Salon")), "players": int(item.get("PlayerCount", 0))})
	rooms_changed.emit(rooms)


func create_room(title: String) -> void:
	if not connected or not current_room.is_empty():
		return
	var name := title.strip_edges().substr(0, 25)
	if name.length() < 3:
		name = "Mon salon"
	_service.lobby_create("%s %04d" % [name, randi_range(0, 9999)], "", true, 2)


func _on_lobby_created(name: String) -> void:
	_service.lobby_join(name)


func _on_lobby_creation_failed(_name: String, error: int) -> void:
	connection_changed.emit(connected, "Création du salon impossible (%d)." % error)


func join_room(title: String) -> void:
	if connected and current_room.is_empty():
		_service.lobby_join(title)


func _on_lobby_joined(_name: String) -> void:
	_match_generation += 1
	_phase = "waiting"
	_host_score = 0
	_guest_score = 0
	_round_number = 0
	_sync_room()
	refresh_rooms()


func _on_lobby_join_failed(_name: String, error: int) -> void:
	connection_changed.emit(connected, "Salon indisponible (%d). Actualise la liste." % error)


func leave_room() -> void:
	if current_room.is_empty():
		return
	_match_generation += 1
	_service.lobby_leave()
	_phase = "waiting"
	current_room = {}
	room_changed.emit({})
	refresh_rooms()


func _on_client_joined(_client_id: int) -> void:
	await get_tree().process_frame
	_sync_room()
	refresh_rooms()


func _on_client_left(client_id: int) -> void:
	if current_room.is_empty():
		return
	if client_id == int(current_room.get("host_id", -1)):
		leave_room()
		connection_changed.emit(connected, "L'hôte a quitté le salon.")
		return
	_match_generation += 1
	_phase = "waiting"
	_sync_room()
	connection_changed.emit(connected, "L'autre joueur a quitté le salon.")


func _on_host_changed(_is_host: bool, _new_host_id: int) -> void:
	if not current_room.is_empty():
		_sync_room()


func _sync_room() -> void:
	if _service == null or not connected:
		return
	var clients: Array = _service.lobby_get_all_clients()
	if clients.is_empty():
		return
	var host_id := int(_service.get_host())
	if host_id < 0 or not clients.has(host_id):
		return
	var guest_id := 0
	for id_variant in clients:
		if int(id_variant) != host_id:
			guest_id = int(id_variant)
			break
	current_room = {"title": str(_service.lobby_get_name()), "host_id": host_id,
		"guest_id": guest_id, "phase": _phase, "host_score": _host_score,
		"guest_score": _guest_score}
	room_changed.emit(current_room)
	if _service.is_host() and guest_id != 0:
		_service.call_func(Callable(self, "_remote_room_state"), current_room)


func _remote_room_state(room: Dictionary) -> void:
	if _service.get_sender_id() != int(current_room.get("host_id", _service.get_host())):
		return
	current_room = room
	room_changed.emit(room)


func start_match() -> void:
	if not connected or current_room.is_empty() or not _service.is_host():
		return
	var guest_id := int(current_room.get("guest_id", 0))
	if guest_id == 0 or _phase not in ["waiting", "finished"]:
		return
	_match_generation += 1
	_phase = "starting"
	_host_score = 0
	_guest_score = 0
	_round_number = 0
	_ready_ids.clear()
	round_loadouts.clear()
	_match_token = "%d-%d" % [Time.get_ticks_usec(), randi()]
	_combat_sequence = 0
	_sync_room()
	var host_id := local_peer_id()
	_service.call_func(Callable(self, "_remote_start_match"), host_id, guest_id, _match_token)
	match_started.emit(host_id, guest_id)


func _remote_start_match(host_id: int, guest_id: int, token: String) -> void:
	if _service.get_sender_id() != _service.get_host() or host_id != _service.get_host() or guest_id != local_peer_id():
		return
	_phase = "starting"
	_match_token = token
	_round_number = 0
	round_loadouts.clear()
	_combat_sequence = 0
	match_started.emit(host_id, guest_id)


func match_ready(loadout: Dictionary = {}) -> void:
	if _phase != "starting":
		return
	if _service.is_host():
		_accept_ready(local_peer_id(), loadout)
	else:
		_service.call_func(Callable(self, "_host_match_ready"), local_peer_id(), loadout, _match_token)


func _host_match_ready(peer_id: int, loadout: Dictionary, token: String) -> void:
	if _service.get_sender_id() != peer_id or token != _match_token:
		return
	_accept_ready(peer_id, loadout)


func _accept_ready(peer_id: int, loadout: Dictionary) -> void:
	if not _service.is_host() or _phase != "starting" or peer_id not in [int(current_room.host_id), int(current_room.guest_id)]:
		return
	_ready_ids[peer_id] = true
	round_loadouts[peer_id] = LOADOUT.sanitize(loadout)
	if _ready_ids.size() == 2:
		_host_prepare_round()


func _host_prepare_round() -> void:
	if not _service.is_host() or int(current_room.get("guest_id", 0)) == 0:
		return
	var generation := _match_generation
	_round_number += 1
	_phase = "countdown"
	_sync_room()
	_service.call_func(Callable(self, "_remote_round_prepared"), _round_number, _host_score, _guest_score, round_loadouts, _match_token)
	round_prepared.emit(_round_number, _host_score, _guest_score)
	var prepared_token := _match_token
	var prepared_round := _round_number
	await get_tree().create_timer(3.5).timeout
	if generation != _match_generation or _phase != "countdown" or current_room.is_empty() or prepared_token != _match_token or prepared_round != _round_number:
		return
	_phase = "live"
	_sync_room()
	_service.call_func(Callable(self, "_remote_round_live"), _round_number, _match_token)
	round_live.emit()


func _remote_round_prepared(number: int, host_score: int, guest_score: int, loadouts: Dictionary, token: String) -> void:
	if not _from_host(token) or number <= _round_number:
		return
	_round_number = number
	round_loadouts = loadouts
	_phase = "countdown"
	round_prepared.emit(number, host_score, guest_score)


func _remote_round_live(number: int, token: String) -> void:
	if not _from_host(token) or number != _round_number or _phase != "countdown":
		return
	_phase = "live"
	round_live.emit()


func report_death() -> void:
	# Death is now determined from both host combat states after the physics tick.
	pass


func finish_authoritative_round(host_dead: bool, guest_dead: bool) -> void:
	if not _service.is_host() or _phase != "live" or current_room.is_empty() or not (host_dead or guest_dead):
		return
	var generation := _match_generation
	_phase = "round_result"
	var winner_id := 0 if host_dead and guest_dead else int(current_room.guest_id) if host_dead else int(current_room.host_id)
	if winner_id != 0 and winner_id == int(current_room.host_id):
		_host_score += 1
	elif winner_id != 0:
		_guest_score += 1
	var over := _host_score >= 3 or _guest_score >= 3
	if over:
		_phase = "finished"
	_sync_room()
	_service.call_func(Callable(self, "_remote_round_finished"), _host_score, _guest_score, winner_id, over, _round_number, _match_token)
	round_finished.emit(_host_score, _guest_score, winner_id, over)
	if not over:
		var finished_token := _match_token
		var finished_round := _round_number
		await get_tree().create_timer(2.0).timeout
		if generation == _match_generation and _phase == "round_result" and not current_room.is_empty() and finished_token == _match_token and finished_round == _round_number:
			_host_prepare_round()


func _remote_round_finished(host_score: int, guest_score: int, winner_id: int, over: bool, number: int, token: String) -> void:
	if not _from_host(token) or number != _round_number or _phase != "live":
		return
	_phase = "finished" if over else "round_result"
	round_finished.emit(host_score, guest_score, winner_id, over)


func _other_id() -> int:
	if current_room.is_empty():
		return 0
	return int(current_room.guest_id) if local_peer_id() == int(current_room.host_id) else int(current_room.host_id)


func send_state(position: Vector3, aim: Vector3, health: float, max_health: float, weapon: String) -> void:
	var other := _other_id()
	if _phase in ["countdown", "live"] and other != 0:
		_service.call_func(Callable(self, "_remote_state"), position, aim, health, max_health, weapon)


func _remote_state(position: Vector3, aim: Vector3, health: float, max_health: float, weapon: String) -> void:
	if _phase in ["countdown", "live"] and position.is_finite() and aim.is_finite():
		opponent_state.emit(position, aim, clampf(health, 0.0, 5000.0), clampf(max_health, 1.0, 5000.0), weapon)


func send_hit(amount: float, source_id: String, attack_id: String) -> void:
	# Legacy proxies cannot submit damage to the other human.
	pass


func _remote_hit(amount: float, source_id: String, attack_id: String) -> void:
	if _phase == "live" and is_finite(amount) and amount > 0.0 and amount <= 250.0:
		opponent_hit.emit(amount, source_id, attack_id)


func send_effect(effect: String, duration: float, value: float = 0.0) -> void:
	pass


func _from_host(token: String) -> bool:
	return not current_room.is_empty() and token == _match_token and _service.get_sender_id() == int(current_room.host_id)


func _packet_valid(packet: Dictionary) -> bool:
	return str(packet.get("token", "")) == _match_token and int(packet.get("round", -1)) == _round_number


func _stamp(packet: Dictionary) -> Dictionary:
	var result := packet.duplicate(true)
	result.token = _match_token
	result.round = _round_number
	return result


func send_pose(pose: Dictionary) -> void:
	if _phase == "live" and not _service.is_host() and not current_room.is_empty():
		_service.call_func_unreliable(Callable(self, "_host_pose"), _stamp(pose))


func _host_pose(pose: Dictionary) -> void:
	if _phase == "live" and _service.is_host() and _packet_valid(pose) and _service.get_sender_id() == int(current_room.get("guest_id", 0)):
		pose_received.emit(pose)


func request_action(request: Dictionary) -> void:
	if _phase == "live" and not _service.is_host() and not current_room.is_empty():
		_service.call_func(Callable(self, "_host_action"), _stamp(request))


func _host_action(request: Dictionary) -> void:
	if _phase == "live" and _service.is_host() and _packet_valid(request) and _service.get_sender_id() == int(current_room.get("guest_id", 0)):
		action_requested.emit(request)


func publish_action(event: Dictionary) -> void:
	if _phase == "live" and _service.is_host():
		_service.call_func(Callable(self, "_remote_action"), _stamp(event))


func _remote_action(event: Dictionary) -> void:
	if _phase == "live" and _packet_valid(event) and _from_host(str(event.token)):
		action_received.emit(event)


func publish_combat(snapshot: Dictionary, reliable := false) -> void:
	if _phase not in ["countdown", "live"] or not _service.is_host():
		return
	_combat_sequence += 1
	var packet := _stamp(snapshot)
	packet.sequence = _combat_sequence
	# These contain full effect/passive state. Compress below the relay MTU so
	# a single snapshot does not require fragmented unreliable packets.
	var buffer := var_to_bytes(packet).compress(FileAccess.COMPRESSION_DEFLATE)
	if reliable:
		_service.call_func(Callable(self, "_remote_combat"), buffer)
	else:
		_service.call_func_unreliable(Callable(self, "_remote_combat"), buffer)


func _remote_combat(buffer: PackedByteArray) -> void:
	if current_room.is_empty() or _service.get_sender_id() != int(current_room.host_id):
		return
	var decoded: Variant = bytes_to_var(buffer.decompress_dynamic(32768, FileAccess.COMPRESSION_DEFLATE))
	if not decoded is Dictionary:
		return
	var snapshot: Dictionary = decoded
	if _phase in ["countdown", "live"] and _packet_valid(snapshot) and _from_host(str(snapshot.token)):
		combat_received.emit(snapshot)


func _remote_effect(effect: String, duration: float, value: float) -> void:
	if _phase == "live" and effect in ["burn", "slow", "stun", "spotted"]:
		opponent_effect.emit(effect, duration, value)
