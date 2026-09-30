extends CanvasLayer

## Movement is locally responsive; the host runs both combat controllers and
## owns projectile collisions, health, effects, passives and round results.
const NETWORK_PLAYER := preload("res://scripts/network_player.gd")
const CREAM := Color("#f3ddbb")
const GREEN := Color("#69d687")
const RED := Color("#d95b4d")

var _main: Node3D
var _player: CharacterBody3D
var _target: CharacterBody3D
var _original_player: CharacterBody3D
var _original_target: StaticBody3D
var _actors: Node3D
var _flow: CanvasLayer
var _touch: Control
var _session: Node
var _host_id := 0
var _guest_id := 0
var _round_number := 0
var _host_score := 0
var _guest_score := 0
var _phase := "starting"
var _state_clock := 0.0
var _request_sequence := 0
var _last_request := 0
var _pose_sequence := 0
var _last_pose := 0
var _event_sequence := 0
var _last_event := 0
var _last_snapshot := 0
var _status: Label
var _cleanup_done := false


func configure(main: Node3D, host_id: int, guest_id: int) -> void:
	process_physics_priority = 30
	_main = main
	_original_player = main.get_node("Player")
	_original_target = main.get_node("TargetDummy")
	_flow = main.get_node("Interface")
	_touch = _flow.get_node("TouchControls")
	_session = get_node("/root/NetworkSession")
	_host_id = host_id
	_guest_id = guest_id
	_flow.call("_show_screen", 3)
	_original_player.call("set_gameplay_enabled", false)
	_original_player.hide()
	_original_player.collision_layer = 0
	_original_target.call("set_training_bot_enabled", false)
	_original_target.hide()
	_original_target.collision_layer = 0
	_original_target.set_process(false)
	_original_target.set_physics_process(false)
	_actors = Node3D.new()
	_actors.name = "NetworkActors"
	_main.add_child(_actors)
	_player = _make_actor("LocalFighter", _session.local_peer_id(), false)
	_target = _make_actor("RemoteFighter", _guest_id if _is_host() else _host_id, true)
	_player.set("opponent", _target)
	_target.set("opponent", _player)
	_player.call("apply_loadout", _flow.get("loadout"))
	_flow.set("player", _player)
	_flow.set("target", _target)
	_touch.call("set_player", _player)
	_main.get_node("CameraRig").call("set_target", _player)
	_retarget_vision(_player, _target, true)
	_flow.get_node("FlowRoot/CombatHUD/PauseButton").hide()
	_build_overlay()
	_flow.call("_start_match_music")
	_touch.visible = false
	_session.round_prepared.connect(_on_round_prepared)
	_session.round_live.connect(_on_round_live)
	_session.round_finished.connect(_on_round_finished)
	_session.pose_received.connect(_on_pose)
	_session.action_requested.connect(_on_action_requested)
	_session.action_received.connect(_on_action_received)
	_session.combat_received.connect(_on_combat_received)
	_session.connection_changed.connect(_on_connection_changed)
	_session.room_changed.connect(_on_room_changed)
	_session.match_ready(_flow.get("loadout"))


func _make_actor(actor_name: String, id: int, remote: bool) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.name = actor_name
	actor.set_script(NETWORK_PLAYER)
	actor.set("controller", self)
	actor.set("authoritative", _is_host())
	actor.set("remote_controlled", remote)
	actor.set("peer_id", id)
	_actors.add_child(actor)
	actor.call("set_gameplay_enabled", false)
	return actor


func _build_overlay() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var leave := Button.new()
	leave.text = "QUITTER"
	leave.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leave.position = Vector2(-132, 18)
	leave.custom_minimum_size = Vector2(112, 44)
	leave.pressed.connect(_leave_match)
	root.add_child(leave)
	_status = Label.new()
	_status.text = "En attente de l’autre joueur…"
	_status.add_theme_font_size_override("font_size", 25)
	_status.add_theme_color_override("font_color", CREAM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_status.offset_left = -380
	_status.offset_right = 380
	_status.offset_top = 82
	root.add_child(_status)


func _is_host() -> bool:
	return _session.local_peer_id() == _host_id


func _my_spawn() -> Vector3:
	return Vector3(-3.5, 0.0, 17.0) if _is_host() else Vector3(3.5, 0.0, 15.5)


func _other_spawn() -> Vector3:
	return Vector3(3.5, 0.0, 15.5) if _is_host() else Vector3(-3.5, 0.0, 17.0)


func _process(delta: float) -> void:
	if _phase == "closed" or _player == null:
		return
	_target.call("update_remote_visibility", delta)
	var labels: Dictionary = _flow.get("_hud_labels")
	labels.match.text = "%d — %d" % [_host_score if _is_host() else _guest_score, _guest_score if _is_host() else _host_score]
	labels.match_round.text = "MANCHE %d" % maxi(1, _round_number)
	labels.phase.text = "COMBAT" if _phase == "live" else "PRÉPARATION" if _phase == "countdown" else "RÉSULTAT"


func _physics_process(delta: float) -> void:
	if _phase not in ["countdown", "live"]:
		return
	_state_clock += delta
	if _is_host() and _phase == "live":
		var host_dead := bool(_player.call("is_real_dead"))
		var guest_dead := bool(_target.call("is_real_dead"))
		if host_dead or guest_dead:
			_publish_snapshot(true)
			_session.finish_authoritative_round(host_dead, guest_dead)
			return
	if _state_clock < 0.05:
		return
	_state_clock = 0.0
	if _is_host():
		_publish_snapshot()
	elif _phase == "live":
		_pose_sequence += 1
		_session.send_pose({"sequence": _pose_sequence, "position": _player.global_position,
			"aim": _player.get("aim_direction"), "velocity": _player.velocity})


func _publish_snapshot(reliable := false) -> void:
	_session.publish_combat({"host": _player.call("network_snapshot"),
		"guest": _target.call("network_snapshot"), "ack": _last_request}, reliable)


func _on_round_prepared(number: int, host_score: int, guest_score: int) -> void:
	_round_number = number
	_host_score = host_score
	_guest_score = guest_score
	_phase = "countdown"
	_last_request = 0
	_request_sequence = 0
	_last_pose = 0
	_pose_sequence = 0
	_main.call("clear_transient_fx")
	for actor in [_player, _target]:
		actor.call("set_gameplay_enabled", false)
		actor.call("apply_loadout", _session.round_loadouts.get(int(actor.get("peer_id")), {}))
		actor.call("reset_combat_state")
	_player.position = _my_spawn()
	_target.position = _other_spawn()
	_touch.visible = false
	_status.text = "MANCHE %d · PRÉPAREZ-VOUS" % number
	_status.add_theme_color_override("font_color", CREAM)
	_flow.get_node("FlowRoot/CombatHUD/SpellBar").show()


func _on_round_live() -> void:
	_phase = "live"
	_player.call("set_gameplay_enabled", true)
	_target.call("set_gameplay_enabled", true)
	_touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_status.text = ""


func _on_round_finished(host_score: int, guest_score: int, winner_id: int, match_over: bool) -> void:
	_phase = "finished" if match_over else "round_result"
	_host_score = host_score
	_guest_score = guest_score
	_player.call("set_gameplay_enabled", false)
	_target.call("set_gameplay_enabled", false)
	_touch.visible = false
	_status.text = "ÉGALITÉ" if winner_id == 0 else ("MATCH GAGNÉ" if winner_id == _session.local_peer_id() else "MATCH PERDU") if match_over else ("MANCHE GAGNÉE" if winner_id == _session.local_peer_id() else "MANCHE PERDUE")
	_status.add_theme_color_override("font_color", CREAM if winner_id == 0 else GREEN if winner_id == _session.local_peer_id() else RED)
	_flow.get_node("FlowRoot/CombatHUD/SpellBar").hide()


func _valid_pose(packet: Dictionary) -> bool:
	var position: Variant = packet.get("position")
	var aim: Variant = packet.get("aim")
	return position is Vector3 and aim is Vector3 and position.is_finite() and aim.is_finite() and absf(position.x) <= 31.0 and absf(position.z) <= 31.0 and absf(position.y) < 0.1 and aim.length_squared() > 0.001


func _set_remote_pose(packet: Dictionary) -> void:
	_target.call("_set_aim_direction", packet.aim.normalized())
	var speed: Variant = packet.get("velocity", Vector3.ZERO)
	if speed is Vector3 and speed.is_finite():
		_target.set("remote_velocity", speed.limit_length(20.0))
		if speed.length_squared() > 0.001:
			_target.set("_last_move_direction", speed.normalized())
	if not bool(_target.call("is_dash_active")) and not _target.get("_mekatana_attack").is_direction_locked() and float(_target.get("_stasis_remaining")) <= 0.0 and not _target.get("combat_state").is_stunned():
		_target.global_position = packet.position


func _on_pose(pose: Dictionary) -> void:
	if not _is_host() or _phase != "live" or not _valid_pose(pose) or int(pose.get("sequence", 0)) <= _last_pose:
		return
	_last_pose = int(pose.sequence)
	_set_remote_pose(pose)


func on_actor_action(actor: Node3D, action: String, data: Dictionary) -> void:
	if _phase != "live":
		return
	if _is_host():
		_event_sequence += 1
		var value := data.duplicate(true)
		value.position = actor.global_position
		_session.publish_action({"sequence": _event_sequence, "peer": actor.get("peer_id"),
			"action": action, "data": value, "position": actor.global_position, "aim": actor.get("aim_direction")})
	elif actor == _player:
		_request_sequence += 1
		_session.request_action({"sequence": _request_sequence, "action": action, "data": data,
			"position": data.get("origin", actor.global_position) if action == "javelin_recast" else actor.global_position,
			"aim": actor.get("aim_direction"), "velocity": actor.velocity})


func _on_action_requested(request: Dictionary) -> void:
	if not _is_host() or _phase != "live" or not _valid_pose(request) or int(request.get("sequence", 0)) <= _last_request:
		return
	_last_request = int(request.sequence)
	_set_remote_pose(request)
	_target.call("receive_action", str(request.get("action", "")), request.get("data", {}))
	_publish_snapshot(true)


func _on_action_received(event: Dictionary) -> void:
	if _is_host() or _phase != "live" or not _valid_pose(event) or int(event.get("sequence", 0)) <= _last_event:
		return
	_last_event = int(event.sequence)
	if int(event.peer) == _session.local_peer_id():
		if str(event.action) == "javelin_recast":
			_player.global_position = event.position
		return
	_target.global_position = event.position
	_target.set("aim_direction", event.aim.normalized())
	_target.call("receive_action", str(event.action), event.data, true)


func _on_combat_received(snapshot: Dictionary) -> void:
	if _is_host() or int(snapshot.get("sequence", 0)) <= _last_snapshot:
		return
	_last_snapshot = int(snapshot.sequence)
	_player.call("receive_snapshot", snapshot.guest, int(snapshot.ack) >= _request_sequence)
	_target.call("receive_snapshot", snapshot.host)
	_set_remote_pose(snapshot.host)


func _on_connection_changed(is_connected: bool, message: String) -> void:
	if not is_connected:
		_finish_to_lobby(message)


func _on_room_changed(room: Dictionary) -> void:
	if room.is_empty() or int(room.get("guest_id", 0)) == 0:
		_finish_to_lobby("L’autre joueur a quitté le match.")


func _leave_match() -> void:
	_session.leave_room()
	_finish_to_lobby("Match quitté.")


func _finish_to_lobby(message: String) -> void:
	if not is_inside_tree() or _phase == "closed":
		return
	_phase = "closed"
	_cleanup_actors()
	_flow.call("_stop_match_music")
	_flow.call("_open_lobby")
	_flow.get_node("FlowRoot/NetworkLobby").call("_on_connection_changed", _session.connected, message)
	queue_free()


func _cleanup_actors() -> void:
	if _cleanup_done:
		return
	_cleanup_done = true
	for actor in [_player, _target]:
		if is_instance_valid(actor):
			actor.call("set_gameplay_enabled", false)
			actor.call("reset_module_state")
	_touch.visible = false
	_touch.call("set_player", _original_player)
	_flow.set("player", _original_player)
	_flow.set("target", _original_target)
	_original_player.collision_layer = 4
	_original_player.show()
	_original_target.collision_layer = 2
	_original_target.show()
	_original_target.set_process(true)
	_original_target.set_physics_process(true)
	_main.get_node("CameraRig").call("set_target", _original_player)
	_retarget_vision(_original_player, _original_target, false)
	_flow.get_node("FlowRoot/CombatHUD/PauseButton").show()
	_flow.get_node("FlowRoot/CombatHUD/SpellBar").show()
	_main.call("clear_transient_fx")
	if is_instance_valid(_actors):
		_actors.queue_free()


func _retarget_vision(player: Node3D, target: Node3D, network_round: bool) -> void:
	var tracker := _main.get_node_or_null("SightTracker")
	if tracker != null:
		tracker.call("configure", _main, player, target, network_round)
	var fog := _main.get_node_or_null("FogOfWar")
	if fog != null:
		fog.call("configure", player, _main.get_node("CameraRig/Camera3D"))
		fog.call("set_enabled", false)
	for bush in get_tree().get_nodes_in_group("bush_placeholder"):
		for visual in bush.get_children():
			if visual.has_method("set_local_player"):
				visual.call("set_local_player", player)


func _exit_tree() -> void:
	if not _cleanup_done and is_instance_valid(_main) and _main.is_inside_tree():
		_cleanup_actors()
