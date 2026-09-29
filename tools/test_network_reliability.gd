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
	func call_func(callback: Callable, _a = null, _b = null, _c = null, _d = null) -> void:
		sent.append(str(callback.get_method()))

class FlowProbe:
	extends CanvasLayer
	var opened := 0
	var stopped := 0
	func _open_lobby() -> void: opened += 1
	func _stop_match_music() -> void: stopped += 1

class PlayerProbe:
	extends CharacterBody3D
	func set_gameplay_enabled(_enabled: bool) -> void: pass

class TargetProbe:
	extends StaticBody3D
	var network_proxy := true
	func set_training_bot_enabled(_enabled: bool) -> void: pass
	func set_duel_mode(_enabled: bool) -> void: pass

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
	await create_timer(3.34).timeout
	_check(live_count == 0 and session._phase == "countdown", "un ancien décompte ne démarre pas le nouveau match")
	await create_timer(0.25).timeout
	_check(live_count == 1 and session._phase == "live", "le nouveau match conserve ses propres 3,5 secondes")
	# leave_room emits synchronously, then the leave button closes once more.
	var controller := MATCH.new()
	var flow := FlowProbe.new()
	var flow_root := Control.new()
	flow_root.name = "FlowRoot"
	flow.add_child(flow_root)
	var player := PlayerProbe.new()
	var target := TargetProbe.new()
	var touch := Control.new()
	root.add_child(flow)
	root.add_child(player)
	root.add_child(target)
	root.add_child(touch)
	root.add_child(controller)
	controller._player = player
	controller._target = target
	controller._flow = flow
	controller._touch = touch
	controller._session = session
	controller._phase = "live"
	session.room_changed.connect(controller._on_room_changed)
	controller._leave_match()
	_check(flow.opened == 1 and flow.stopped == 1, "quitter ferme le match et ouvre le salon une seule fois")
	await process_frame
	# Autoloads also support SceneTree scripts with no current scene at startup.
	var sdk := root.get_node("GDSync")
	_check(sdk._session_controller.synced_time > 0.0, "SessionController termine son initialisation sans scène courante")
	_check(sdk._node_tracker.root_instantiator.replicate_settings != null, "NodeInstantiator termine son initialisation sans cible initiale")
	session.queue_free()
	relay.queue_free()
	flow.queue_free()
	player.queue_free()
	target.queue_free()
	touch.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("NETWORK RELIABILITY TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
