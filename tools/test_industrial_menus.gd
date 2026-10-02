extends SceneTree

const SESSION := preload("res://scripts/network_session.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var checks := 0
var _saved: Dictionary = {}

class FakeSession extends "res://scripts/network_session.gd":
	var peer := 77
	var requested_create := ""
	var requested_join := ""
	var requested_start := false
	func _ready() -> void:
		pass
	func local_peer_id() -> int:
		return peer
	func refresh_rooms() -> void:
		pass
	func connect_to_service() -> void:
		pass
	func create_room(value: String) -> void:
		requested_create = value
	func join_room(value: String) -> void:
		requested_join = value
	func start_match() -> void:
		requested_start = true
	func match_ready(_loadout: Dictionary = {}) -> void:
		pass
	func leave_room() -> void:
		current_room = {}
		room_changed.emit({})

func _initialize() -> void:
	for path in ["user://prototype0_settings.cfg", LOADOUT.SAVE_PATH]:
		_saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_open_settings")
	var settings: Control = flow.get("_settings_panel")
	await _click(Vector2(610, 201))
	check(settings.get("_pages")[1].visible, "mouse click opens commands tab")
	await _click(Vector2(930, 201))
	check(settings.get("_pages")[2].visible, "mouse click opens interface tab")
	await _click(Vector2(300, 201))
	check(settings.get("_pages")[0].visible, "mouse click restores audio tab")
	var preferences: Node = root.get_node("GamePreferences")
	preferences.call("reset_bindings", false)
	var effects: float = preferences.get("effects_volume")
	(settings.find_child("MusicVolume", true, false) as HSlider).value = 37
	check(is_equal_approx(float(preferences.get("music_volume")), 0.37) and is_equal_approx(float(preferences.get("effects_volume")), effects), "music changes independently")
	(settings.find_child("EffectsVolume", true, false) as HSlider).value = 62
	check(is_equal_approx(float(preferences.get("effects_volume")), 0.62), "effects slider is live")
	(settings.find_child("CameraShake", true, false) as CheckButton).button_pressed = false
	(settings.find_child("TouchScale", true, false) as HSlider).value = 1.1
	var saved := ConfigFile.new()
	saved.load("user://prototype0_settings.cfg")
	check(is_equal_approx(float(saved.get_value("settings", "touch_scale")), 1.1), "touch size persists")
	check(is_equal_approx(float(flow.get("touch_controls").get("control_scale")), 1.1), "touch size applies to real controls")
	settings.call("_select_page", 1)
	settings.call("_begin_capture", "offensive")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_C
	settings.call("_input", key)
	check(str(preferences.call("key_label", "offensive")) == "C", "commands tab rebinds actual combat input")
	settings.call("_begin_capture", "defensive")
	settings.call("_input", key)
	check(str(preferences.call("key_label", "defensive")) != "C", "duplicate binding rejected")
	key.keycode = KEY_ESCAPE
	settings.call("_input", key)
	check(str(settings.get("_capture_action")).is_empty() and int(flow.get("current_screen")) == 2, "Escape cancels capture without leaving settings")
	settings.call("_begin_capture", "offensive")
	flow.call("_open_menu")
	check(str(settings.get("_capture_action")).is_empty(), "hidden settings cancel pending binding")
	flow.call("_open_settings")
	settings.call("_select_page", 2)
	check(bool(settings.get("_pages")[2].visible), "interface tab opens")
	settings.find_child("CustomizeInterface", true, false).pressed.emit()
	check(bool(flow.get("_hud_editor").visible), "interface editor opens from settings")
	flow.get("_hud_editor").hide()
	flow.call("_on_hud_editor_closed")
	check(settings.visible, "interface editor returns to settings")
	var actual_session: Node = root.get_node("NetworkSession")
	root.remove_child(actual_session)
	var session := FakeSession.new()
	session.name = "NetworkSession"
	root.add_child(session)
	session.connected = true
	var lobby: Control = flow.get("_lobby_panel")
	flow.call("_open_lobby")
	lobby.call("_on_rooms_changed", [{"title": "Test room", "players": 1}])
	(lobby.find_child("JoinRoom", true, false) as Button).pressed.emit()
	check(session.requested_join == "Test room", "join button submits correct room identity")
	lobby.find_child("RoomName", true, false).text = "Test create"
	lobby.find_child("CreateRoom", true, false).pressed.emit()
	check(session.requested_create == "Test create", "create button submits typed name")
	session.current_room = {"title": "Test", "host_id": 77, "guest_id": 0, "phase": "waiting"}
	lobby.call("_on_room_changed", session.current_room)
	check(lobby.get("_joined").visible and not lobby.get("_browser").visible, "joined room replaces browser")
	check(lobby.get("_start_button").disabled, "host cannot start without opponent")
	session.current_room.guest_id = 88
	lobby.call("_on_room_changed", session.current_room)
	check(not lobby.get("_start_button").disabled, "host can start with two players")
	session.peer = 88
	lobby.call("_on_room_changed", session.current_room)
	check(lobby.get("_start_button").disabled and lobby.get("_guest_label").text == "Vous", "guest identity and launch authority are correct")
	lobby.get("_leave_button").pressed.emit()
	# The actual session delivers this signal in production; fake events are explicit.
	lobby.call("_on_room_changed", session.current_room)
	check(lobby.get("_browser").visible, "leaving restores browser")
	session.connected = false
	lobby.call("_on_connection_changed", false, "Connexion perdue")
	check(lobby.get("_create_button").disabled and lobby.get("_refresh_button").disabled, "offline controls disabled")
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 540), Vector2i(800, 600)]:
		root.size = dimensions
		await process_frame
		for screen in [settings, lobby, flow.get("_precombat_overlay")]:
			var bounds: Rect2 = screen.get("canvas").get_global_rect()
			check(bounds.position.x >= -1 and bounds.position.y >= -1 and bounds.end.x <= dimensions.x+1 and bounds.end.y <= dimensions.y+1, "screen stays inside "+str(dimensions))
	root.size = Vector2i(1280, 720)
	flow.call("_start_duel")
	await process_frame
	var precombat: Control = flow.get("_precombat_overlay")
	check(precombat.visible and not bool(scene.get_node("Player").call("is_gameplay_enabled")), "solo precombat locks combat input")
	check(precombat.get("opponent_loadout") == LOADOUT.sanitize(scene.get("_bot_build")), "solo reveals real selected bot loadout")
	check(precombat.get("_rows")[0].size() == 6 and precombat.get("_rows")[1].size() == 6, "both complete loadouts have six slots")
	flow.call("_process", 8.1)
	flow.call("_process", 1.0)
	check(not precombat.visible and bool(scene.get_node("Player").call("is_gameplay_enabled")), "solo intro releases combat")
	flow.call("_return_menu")
	# Exercise the actual network controller with two different loadouts, from both seats.
	for peer in [77, 88]:
		session.peer = peer
		session.connected = true
		session.current_room = {"title": "Network test", "host_id": 77, "guest_id": 88, "phase": "starting"}
		session.round_loadouts = {77: LOADOUT.defaults(), 88: {"robot": "agile", "weapon": "longshot", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"}}
		scene.call("_on_network_match_started", 77, 88)
		await process_frame
		session.round_prepared.emit(1, 0, 0)
		await process_frame
		check(precombat.visible and precombat.get("local_loadout") == LOADOUT.sanitize(session.round_loadouts[peer]), "network local build matches seat "+str(peer))
		var opponent_id := 88 if peer == 77 else 77
		check(precombat.get("opponent_loadout") == LOADOUT.sanitize(session.round_loadouts[opponent_id]), "network opponent loadout matches seat "+str(peer))
		var network: Node = scene.get("network_match")
		network.call("_process", 20.0)
		check(precombat.visible and not bool(network.get("_player").call("is_gameplay_enabled")), "local countdown cannot activate online combat")
		session.round_live.emit()
		check(not precombat.visible and bool(network.get("_player").call("is_gameplay_enabled")), "host signal activates combat")
		network.call("_finish_to_lobby", "Test terminé")
		await process_frame
		check(not precombat.visible, "leaving network clears precombat")
	scene.queue_free()
	await process_frame
	root.remove_child(session)
	session.queue_free()
	root.add_child(actual_session)
	_restore()
	preferences.call("load_preferences")
	print("INDUSTRIAL MENUS TEST: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _restore() -> void:
	for path in _saved:
		if _saved[path] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(_saved[path])

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event)
	await process_frame
	event.pressed = false
	root.push_input(event)
	await process_frame
