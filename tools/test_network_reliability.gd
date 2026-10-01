extends SceneTree

## Offline regression: no external lobby or saved player data is required.
const SESSION := preload("res://scripts/network_session.gd")
const MATCH := preload("res://scripts/network_match.gd")
var failures: Array[String] = []
var live_count := 0

class RelayProbe:
	extends Node
	var sent: Array[String] = []
	func is_host() -> bool: return true
	func get_client_id() -> int: return 11
	func get_host() -> int: return 11
	func lobby_get_all_clients() -> Array: return [11, 22]
	func lobby_get_name() -> String: return "Probe"
	func lobby_leave() -> void: pass
	func get_public_lobbies() -> void: pass
	func call_func(callback: Callable, _a = null, _b = null, _c = null, _d = null, _e = null, _f = null) -> void:
		sent.append(str(callback.get_method()))

class FlowProbe:
	extends CanvasLayer
	var opened := 0
	var stopped := 0
	var player: Node3D
	var target: Node3D
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
