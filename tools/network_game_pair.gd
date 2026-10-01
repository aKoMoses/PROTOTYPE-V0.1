extends "res://scripts/main.gd"

var _role := ""
var _session: Node
var _service: Node
var _joining := false
var _started := false
var _running := false
var _seen_projectile := false
var _guest_verified := false
var _checks := 0
var _room_prefix := ""
var _rounds_finished := 0
var _first_round := 0
var _match_token := ""


func _ready() -> void:
	super._ready()
	var arguments := OS.get_cmdline_user_args()
	_role = "host" if "host" in arguments else "guest"
	for argument in arguments:
		if argument.begins_with("test-id="):
			_room_prefix = argument.trim_prefix("test-id=").substr(0, 16)
	_room_prefix = "Combat " + (_room_prefix if not _room_prefix.is_empty() else "authority test")
	_session = get_node("/root/NetworkSession")
	_service = get_node("/root/GDSync")
	_service.expose_func(Callable(self, "_guest_stage"))
	_service.expose_func(Callable(self, "_guest_result"))
	_session.connection_changed.connect(_on_connection)
	_session.rooms_changed.connect(_on_rooms)
	_session.room_changed.connect(_on_room)
	_session.round_live.connect(_on_live)
	_session.round_finished.connect(_on_finished)
	_session.action_requested.connect(func(value: Dictionary) -> void: print("TEST HOST REQUEST ", value.action))
	game_flow.set("loadout", {"robot": "polyvalent", "weapon": "blaster" if _role == "host" else "shotgun",
		"offensive": "javelin", "defensive": "magnetic_field" if _role == "host" else "static_shield",
		"mobility": "pyro_boots", "passive": "omnivamp"})
	_session.connect_to_service()
	await get_tree().create_timer(45.0).timeout
	_fail("timeout")


func _process(delta: float) -> void:
	super._process(delta)
	if _running and _role == "guest" and not get_tree().get_nodes_in_group("prototype0_gameplay_projectiles").is_empty():
		_seen_projectile = true


func _check(ok: bool, message: String) -> bool:
	if not ok:
		_fail(message)
		return false
	_checks += 1
	return true


func _on_connection(ok: bool, message: String) -> void:
	if ok and _role == "host":
		_session.create_room(_room_prefix)
	elif not ok and not message.begins_with("Connexion"):
		_fail(message)


func _on_rooms(rooms: Array) -> void:
	if _role != "guest" or _joining:
		return
	for room in rooms:
		if str(room.title).begins_with(_room_prefix + " "):
			_joining = true
			_session.join_room(str(room.title))
			return
	await get_tree().create_timer(0.25).timeout
	_session.refresh_rooms()


func _on_room(room: Dictionary) -> void:
	print("TEST ROOM [%s] phase=%s ready=%s" % [_role, room.get("phase", ""), _session.get("_ready_ids")])
	if _role == "host" and not _started and int(room.get("host_id", -1)) == _session.local_peer_id() and int(room.get("guest_id", 0)) != 0:
		_started = true
		_session.start_match()


func _on_live() -> void:
	print("TEST LIVE ", _role)
	if _running:
		if _rounds_finished == 1 and _role == "host":
			_run_draw.call_deferred()
		return
	_running = true
	await get_tree().process_frame
	var local: Node3D = network_match.get("_player")
	local.position = Vector3(-3.5 if _role == "host" else 0.0, 0.0, 17.0)
	local.call("set_aim_input", Vector2.RIGHT if _role == "host" else Vector2.LEFT)
	if _role == "host":
		_first_round = int(_session.get("_round_number"))
		_match_token = str(_session.get("_match_token"))
		_run_host.call_deferred()


func _stage(stage: String) -> void:
	print("TEST SEND STAGE ", stage)
	_service.call_func(Callable(self, "_guest_stage"), stage)


func _run_host() -> void:
	print("TEST HOST SCENARIO")
	await get_tree().create_timer(0.5).timeout
	var local: Node3D = network_match.get("_player")
	var remote: Node3D = network_match.get("_target")
	if not _check(str(remote.call("get_weapon_id")) == "shotgun", "guest loadout missing on host"):
		return
	local.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.RIGHT)
	await get_tree().create_timer(0.7).timeout
	if not _check(is_equal_approx(float(remote.call("get_health")), 980.0), "host projectile did not hit the guest"):
		return
	_stage("shield")
	await get_tree().create_timer(0.3).timeout
	if not _check(float(remote.get("_stasis_remaining")) > 0.0, "guest shield not reproduced on host"):
		return
	local.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.RIGHT)
	_stage("fake")
	await get_tree().create_timer(0.6).timeout
	if not _check(is_equal_approx(float(remote.call("get_health")), 980.0) and is_equal_approx(float(local.call("get_health")), 1000.0), "shield or client damage authority failed"):
		return
	await get_tree().create_timer(0.9).timeout
	_stage("shoot")
	await get_tree().create_timer(0.8).timeout
	if not _check(float(local.call("get_health")) < 980.0 and int(remote.call("get_shotgun_ammo")) == 2, "guest shotgun was not resolved on host"):
		return
	await get_tree().create_timer(3.6).timeout
	local.call("_activate_defensive_module")
	await get_tree().create_timer(0.3).timeout
	var before := float(local.call("get_health"))
	_stage("shoot")
	_stage("capture")
	await get_tree().create_timer(0.65).timeout
	if not _check(is_equal_approx(float(local.call("get_health")), before), "host magnetic wall did not absorb guest pellets"):
		return
	await get_tree().create_timer(2.0).timeout
	local.call("_perform_offensive_module")
	await get_tree().create_timer(0.8).timeout
	if not _check(float(remote.call("get_health")) < 900.0 and bool(remote.call("has_javelin_mark")), "javelin damage and mark missing on host"):
		return
	local.set("_last_move_direction", Vector3.RIGHT)
	local.call("_activate_mobility_module")
	await get_tree().create_timer(0.4).timeout
	_stage("verify")
	await get_tree().create_timer(0.4).timeout
	if not _check(_guest_verified, "guest did not confirm health, projectiles and remote actions"):
		return
	remote.call("take_damage", 2000.0, "test", "host_test_death")


func _guest_stage(stage: String) -> void:
	print("TEST STAGE [%s] %s" % [_role, stage])
	if _role != "guest":
		return
	var local: Node3D = network_match.get("_player")
	var remote: Node3D = network_match.get("_target")
	match stage:
		"shield":
			local.call("_activate_defensive_module")
			print("TEST GUEST SHIELD ", local.get("_stasis_remaining"), " seq=", network_match.get("_request_sequence"))
		"shoot": local.call("_perform_shotgun_attack")
		"fake":
			var before := float(local.call("get_health"))
			local.call("take_damage", 2000.0, "fake", "fake_local_death")
			_session.send_hit(200.0, "fake", "fake_remote_damage")
			_session.report_death()
			_check(is_equal_approx(float(local.call("get_health")), before), "client altered health locally")
		"capture":
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://captures/network_multiplayer.png")
		"verify":
			var valid := _seen_projectile and int(remote.get("received_actions")) >= 4 and float(local.call("get_health")) < 900.0
			_check(valid, "guest presentation or confirmed state missing")
			_service.call_func(Callable(self, "_guest_result"), valid)


func _guest_result(ok: bool) -> void:
	_guest_verified = ok


func _run_draw() -> void:
	await get_tree().create_timer(0.3).timeout
	var local: Node = network_match.get("_player")
	var remote: Node = network_match.get("_target")
	_check(is_equal_approx(float(local.call("get_health")), 1000.0) and is_equal_approx(float(remote.call("get_health")), 1000.0), "round did not reset both actors")
	_check(not _session.call("_packet_valid", {"token": _match_token, "round": _first_round}), "previous-round packet accepted")
	_check(not _session.call("_packet_valid", {"token": "old_match", "round": _session.get("_round_number")}), "previous-match packet accepted")
	local.call("take_damage", 2000.0, "test", "draw_host")
	remote.call("take_damage", 2000.0, "test", "draw_guest")


func _on_finished(host_score: int, guest_score: int, winner_id: int, over: bool) -> void:
	var expected_winner := int(_session.current_room.host_id) if _rounds_finished == 0 else 0
	if not _check(host_score == 1 and guest_score == 0 and winner_id == expected_winner and not over, "round result differs from host resolution"):
		return
	var local: Node = network_match.get("_player")
	if _role == "guest" and not _check(bool(local.call("is_real_dead")), "round finished before authoritative death arrived"):
		return
	_rounds_finished += 1
	if _rounds_finished < 2:
		return
	await get_tree().create_timer(0.4).timeout
	network_match.call("_finish_to_lobby", "Test terminé.")
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(game_flow.get("player") == get_node("Player") and game_flow.get("target") == get_node("TargetDummy") and get_node_or_null("NetworkActors") == null, "leaving a match did not restore the solo actors"):
		return
	_session.leave_room()
	print("NETWORK GAME TEST: PASS [%s] checks=%d" % [_role, _checks])
	for audio in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("NETWORK GAME TEST: FAIL [%s] %s" % [_role, message])
	get_tree().quit(1)
