extends SceneTree

## Offline regression: no external lobby or saved player data is required.
const SESSION := preload("res://scripts/network_session.gd")
const MATCH := preload("res://scripts/network_match.gd")
var failures: Array[String] = []
var live_count := 0

class RelayProbe:
	extends Node
	var sent: Array[String] = []
	var sender := 22
	var creations := 0
	var joins := 0
	var created_public := true
	var published := false
	var protocol := ""
	func get_sender_id() -> int: return sender
	func stop_multiplayer() -> void: pass
	func lobby_create(_title: String, _password: String, public: bool, _limit: int, _tags: Dictionary) -> void:
		creations += 1
		created_public = public
	func lobby_join(_title: String) -> void: joins += 1
	func lobby_get_tag(_key: String, _default: String) -> String: return protocol
	func lobby_set_visibility(public: bool) -> void: published = public
	func is_host() -> bool: return true
	func get_client_id() -> int: return 11
	func get_host() -> int: return 11
	func lobby_get_all_clients() -> Array: return [11, 22]
	func lobby_get_name() -> String: return "Probe"
	func lobby_leave() -> void: pass
	func get_public_lobbies() -> void: pass
	func call_func(callback: Callable, _a = null, _b = null, _c = null, _d = null, _e = null, _f = null) -> void:
		sent.append(str(callback.get_method()))

class FeedbackProbe:
	extends Control
	var actor: Node3D
	var target: Node3D
	var bindings := 0
	var registrations := 0
	func bind_actor(value: Node3D) -> void:
		actor = value
		bindings += 1
	func register_target(value: Node3D) -> void:
		target = value
		registrations += 1

class FlowProbe:
	extends CanvasLayer
	var opened := 0
	var stopped := 0
	var player: Node3D
	var target: Node3D
	var _combat_feedback := FeedbackProbe.new()
	func _open_lobby() -> void: opened += 1
	func _stop_match_music() -> void: stopped += 1
	func hide_network_precombat() -> void: pass

class PlayerProbe:
	extends CharacterBody3D
	var module_resets := 0
	func set_gameplay_enabled(_enabled: bool) -> void: pass
	func reset_module_state() -> void: module_resets += 1

class TargetProbe:
	extends StaticBody3D

class TouchProbe:
	extends Control
	var player: Node3D
	func set_player(value: Node3D) -> void: player = value

class CameraProbe:
	extends Node3D
	var target: Node3D
	func set_target(value: Node3D) -> void: target = value

class MainProbe:
	extends Node3D
	var cleared := 0
	func clear_transient_fx() -> void: cleared += 1

class LobbyProbe:
	extends Control
	var notifications := 0
	func _on_connection_changed(_connected: bool, _message: String) -> void:
		notifications += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var relay := RelayProbe.new()
	root.add_child(relay)
	var session := SESSION.new()
	root.add_child(session)
	session._service = relay
	session.connected = true
	session.current_room = {"host_id": 11, "guest_id": 22}
	session.set_process(false)
	# Rapid taps cannot create multiple rooms or race a second join request.
	session.current_room = {}
	session.create_room("Test rapide")
	session.create_room("Deuxième clic")
	session.join_room("Autre salon")
	_check(relay.creations == 1 and relay.joins == 0 and session.lobby_busy, "un seul salon est créé même lors d'appuis répétés")
	_check(not relay.created_public, "le salon attend son créateur avant d'apparaître dans la liste")
	relay.protocol = session.compatibility_id()
	session._on_lobby_joined("Test rapide")
	_check(relay.published and not session.current_room.is_empty(), "le salon devient public une fois le créateur installé")
	session.leave_room()
	session._on_lobby_creation_failed("Test", 1)
	_check(not session.lobby_busy, "une erreur de salon permet de réessayer")
	session.join_room("Test")
	session.join_room("Test")
	_check(relay.joins == 1, "un seul appel pour rejoindre le salon")
	session._on_lobby_join_failed("Test", 1)
	var listed: Array = []
	session.rooms_changed.connect(func(rooms: Array) -> void: listed.assign(rooms))
	session._on_lobbies_received([
		{"Name": "Compatible", "PlayerCount": 1, "Tags": {"p0_protocol": session.compatibility_id()}},
		{"Name": "Ancienne version", "PlayerCount": 1, "Tags": {}},
		{"Name": "Complet", "PlayerCount": 2}])
	_check(listed.size() == 2 and listed[0].compatible and not listed[1].compatible, "la liste distingue les versions incompatibles et les salons pleins")
	session.current_room = {"host_id": 11, "guest_id": 22}
	session.start_match()
	var start_token: String = session._match_token
	session.match_ready({"weapon": "shotgun"})
	session._process(session.HANDSHAKE_INTERVAL)
	_check(relay.sent.count("_remote_start_match") == 2, "le lancement est renvoyé tant que l'invité n'a pas confirmé")
	session._process(session.MATCH_LOAD_TIMEOUT)
	_check(session._phase == "waiting" and session.current_room.phase == "waiting" and not session.current_room.is_empty(), "un chargement bloqué revient au salon sans attente infinie")
	_check(session._retired_tokens.has(start_token), "un lancement expiré ne peut pas reprendre plus tard")
	# Both players must accept a rematch; messages from an old match are ignored.
	session._phase = "finished"
	session._match_token = "finished-match"
	session.request_rematch()
	_check(session._phase == "finished" and session._rematch_ids.size() == 1, "la revanche attend l'accord des deux joueurs")
	session._host_rematch("old-match")
	_check(session._rematch_ids.size() == 1, "une ancienne demande de revanche est ignorée")
	session._host_return_to_room("finished-match")
	_check(session._phase == "waiting" and not session.current_room.is_empty(), "l'invité peut ramener les deux joueurs au salon")
	session.current_room = {"host_id": 11, "guest_id": 22}
	session.round_live.connect(func() -> void: live_count += 1)
	# The old countdown must not complete a replacement match's countdown.
	session._host_prepare_round()
	await create_timer(0.2).timeout
	session.leave_room()
	session.current_room = {"host_id": 11, "guest_id": 22}
	session.start_match()
	session._host_prepare_round()
	await create_timer(session.round_intro_seconds(1) - 0.16).timeout
	_check(live_count == 0 and session._phase == "countdown", "un ancien décompte ne démarre pas le nouveau match")
	await create_timer(0.25).timeout
	_check(live_count == 1 and session._phase == "live", "le nouveau match conserve son propre décompte de pré-combat")
	# leave_room emits synchronously, then the leave button closes once more.
	var controller := MATCH.new()
	var flow := FlowProbe.new()
	flow.add_child(flow._combat_feedback)
	var flow_root := Control.new()
	flow_root.name = "FlowRoot"
	flow.add_child(flow_root)
	var lobby := LobbyProbe.new()
	lobby.name = "NetworkLobby"
	flow_root.add_child(lobby)
	var hud := Control.new()
	hud.name = "CombatHUD"
	flow_root.add_child(hud)
	var pause_button := Button.new()
	pause_button.name = "PauseButton"
	hud.add_child(pause_button)
	var spell_bar := Control.new()
	spell_bar.name = "SpellBar"
	hud.add_child(spell_bar)
	var main := MainProbe.new()
	var camera := CameraProbe.new()
	camera.name = "CameraRig"
	main.add_child(camera)
	var original_player := PlayerProbe.new()
	var original_target := TargetProbe.new()
	main.add_child(original_player)
	main.add_child(original_target)
	var actors := Node3D.new()
	main.add_child(actors)
	var player := PlayerProbe.new()
	var target := PlayerProbe.new()
	actors.add_child(player)
	actors.add_child(target)
	var touch := TouchProbe.new()
	root.add_child(flow)
	root.add_child(main)
	root.add_child(touch)
	root.add_child(controller)
	controller._main = main
	controller._player = player
	controller._target = target
	controller._original_player = original_player
	controller._original_target = original_target
	controller._actors = actors
	controller._flow = flow
	controller._touch = touch
	controller._session = session
	controller._phase = "live"
	session.room_changed.connect(controller._on_room_changed)
	controller._leave_match()
	_check(flow.opened == 1 and flow.stopped == 1, "quitter ferme le match et ouvre le salon une seule fois")
	_check(controller._phase == "closed" and controller._cleanup_done, "le contrôleur fermé termine son nettoyage une seule fois")
	_check(player.module_resets == 1 and target.module_resets == 1 and main.cleared == 1, "les deux combattants réseau et leurs effets sont nettoyés une seule fois")
	_check(touch.player == original_player and camera.target == original_player and flow.player == original_player and flow.target == original_target, "les contrôles, la caméra et le HUD retrouvent les acteurs locaux")
	_check(flow._combat_feedback.actor == original_player and flow._combat_feedback.target == original_target and flow._combat_feedback.bindings == 1 and flow._combat_feedback.registrations == 1, "le feedback retrouve les acteurs locaux une seule fois")
	_check(lobby.notifications == 1, "la fermeture synchrone ne notifie le salon qu'une fois")
	await process_frame
	# Autoloads also support SceneTree scripts with no current scene at startup.
	var sdk := root.get_node("GDSync")
	_check(sdk._session_controller.synced_time > 0.0, "SessionController termine son initialisation sans scène courante")
	_check(sdk._node_tracker.root_instantiator.replicate_settings != null, "NodeInstantiator termine son initialisation sans cible initiale")
	session.queue_free()
	relay.queue_free()
	flow.queue_free()
	main.queue_free()
	touch.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("NETWORK RELIABILITY TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
