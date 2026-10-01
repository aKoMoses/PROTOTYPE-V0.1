extends SceneTree

## Local authority/replica checks. This does not substitute a two-device
## internet session; it exercises the same action and pose packet handlers.
const ACTOR := preload("res://scripts/network_player.gd")
const MATCH := preload("res://scripts/network_match.gd")
var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _host: CharacterBody3D
var _target: CharacterBody3D
var _replica: CharacterBody3D
var _recorder: Recorder


class Recorder extends Node:
	var _phase := "live"
	var events: Array[Dictionary] = []
	func on_actor_action(actor: Node, action: String, data: Dictionary) -> void:
		events.append({"actor": actor, "action": action, "data": data.duplicate(true)})


func _initialize() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	current_scene = _scene
	_run.call_deferred()


func _actor(label: String, authority: bool) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.name = label
	actor.set_script(ACTOR)
	actor.set("authoritative", authority)
	actor.set("remote_controlled", true)
	actor.set("controller", _recorder)
	_scene.add_child(actor)
	actor.set_physics_process(false)
	return actor


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)


func _reset() -> void:
	for actor in [_host, _target, _replica]:
		actor.call("apply_loadout", {"weapon": "mekatana", "offensive": "javelin", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
		actor.call("reset_combat_state")
		actor.call("set_gameplay_enabled", true)
		actor.set("aim_direction", Vector3.RIGHT)
	_host.global_position = Vector3.ZERO
	_target.global_position = Vector3(2.7, 0.0, 0.0)
	_replica.global_position = Vector3(10.0, 0.0, 0.0)
	_replica.collision_layer = 0
	_recorder.events.clear()
	await physics_frame
	await process_frame


func _run() -> void:
	_recorder = Recorder.new()
	_scene.add_child(_recorder)
	_host = _actor("MekatanaHost", true)
	_target = _actor("MekatanaTarget", true)
	_replica = _actor("MekatanaReplica", false)
	_host.set("opponent", _target)
	_target.set("opponent", _host)
	_replica.set("opponent", _target)
	await _reset()
	var attack: RefCounted = _host.get("_mekatana_attack")
	_host.call("receive_action", "mekatana", {"step": 2})
	_check(attack.is_busy() and int(attack.step) == 0 and str(attack.phase) == "preparation", "host accepts melee request and derives the combo rank from its own state")
	_host.call("receive_action", "mekatana", {"step": 1})
	_check(_recorder.events.size() == 1 and _recorder.events[0].action == "mekatana" and int(_recorder.events[0].data.step) == 0, "duplicate request cannot start another slash or another accepted event")
	var match_controller := MATCH.new()
	match_controller.set("_target", _host)
	var locked_position := _host.global_position
	match_controller.call("_set_remote_pose", {"position": Vector3(20.0, 0.0, 0.0), "aim": Vector3.BACK, "velocity": Vector3.BACK * 5.0})
	_check(_host.global_position.is_equal_approx(locked_position) and Vector3(_host.get("aim_direction")).is_equal_approx(Vector3.RIGHT) and Vector3(attack.direction).is_equal_approx(Vector3.RIGHT), "pose packets cannot teleport or rotate an admitted preparation")
	_host.call("_update_movement", 0.12)
	_check(str(attack.phase) == "active" and is_equal_approx(_host.global_position.x, 1.3) and is_equal_approx(float(_target.call("get_health")), 1000.0), "authoritative doubled dash runs before active damage")
	var active_position := _host.global_position
	match_controller.call("_set_remote_pose", {"position": Vector3(20.0, 0.0, 0.0), "aim": Vector3.BACK})
	_check(_host.global_position.is_equal_approx(active_position) and Vector3(_host.get("aim_direction")).is_equal_approx(Vector3.RIGHT), "active slash also keeps the accepted remote pose locked")
	_host.call("_update_movement", 0.02)
	_check(is_equal_approx(float(_target.call("get_health")), 935.0), "host alone applies the first 65-damage melee hit")
	_host.call("_update_movement", 0.5)
	for rank in [1, 2]:
		_target.global_position = _host.global_position + Vector3.RIGHT * (float(attack.definition.dash_distance[rank]) + 1.4)
		await physics_frame
		await process_frame
		_host.call("receive_action", "mekatana", {"step": 0})
		_check(int(attack.step) == rank, "host retains its authoritative combo rank despite client rank data")
		_host.call("_update_movement", 1.0)
	_check(is_equal_approx(float(_target.call("get_health")), 685.0), "authoritative network actor resolves all per-target multipliers")
	match_controller.free()
	await _reset()
	_target.global_position = _replica.global_position + Vector3.RIGHT * 4.0
	await physics_frame
	await process_frame
	_replica.call("receive_action", "mekatana", {"step": 2}, true)
	var replica_attack: RefCounted = _replica.get("_mekatana_attack")
	_check(replica_attack.is_busy() and int(replica_attack.step) == 2 and not bool(replica_attack.damage_enabled), "reliable visual event displays the host's third swing with damage disabled")
	_replica.call("_update_movement", 1.0)
	_check(is_equal_approx(float(_target.call("get_health")), 1000.0) and _recorder.events.is_empty(), "visual replica never deals damage or rebroadcasts an accepted action")
	_replica.call("receive_snapshot", _host.call("network_snapshot"))
	_check(str(_replica.call("get_weapon_id")) == "mekatana", "Mekatana equipment survives host snapshot replication")
	await _reset()
	_host.call("receive_action", "mekatana", {})
	_host.call("_update_movement", 0.42)
	_host.call("_update_movement", 0.80)
	_replica.call("receive_action", "mekatana", {"step": 2}, true)
	_replica.call("receive_snapshot", _host.call("network_snapshot"))
	_check(not replica_attack.is_busy() and int(replica_attack.next_step) == 1 and absf(float(replica_attack.combo_remaining) - float(attack.combo_remaining)) < 0.00001, "host snapshot corrects a replica's divergent combo rank and deadline")
	_check(str(_replica.call("get_action_owner")) == "", "idle confirmed snapshot releases replica weapon ownership")
	await physics_frame
	await process_frame
	_target.global_position = _host.global_position + Vector3.RIGHT * 1.4
	_host.call("receive_action", "mekatana", {})
	_host.call("_update_movement", 0.08)
	_replica.call("receive_snapshot", _host.call("network_snapshot"))
	_check(str(replica_attack.phase) == "preparation" and int(replica_attack.step) == 1 and absf(float(replica_attack.get("_elapsed")) - 0.08) < 0.00001 and Vector3(replica_attack.direction).is_equal_approx(Vector3.RIGHT), "active snapshot restores the exact accepted rank, phase clock and direction")
	_check(str(_replica.call("get_action_owner")) == "mekatana" and not bool(replica_attack.damage_enabled), "restored active replica owns the weapon gate but cannot resolve damage")
	var authoritative_before: Dictionary = attack.presentation_snapshot()
	attack.restore_presentation({"phase": "active", "step": 2, "next_step": 2, "elapsed": 0.01, "direction": Vector3.BACK})
	var forged_snapshot: Dictionary = _replica.call("network_snapshot")
	forged_snapshot.mekatana = {"phase": "active", "step": 2}
	_host.call("receive_snapshot", forged_snapshot)
	_check(attack.presentation_snapshot() == authoritative_before, "authoritative hit timeline cannot be replaced by replica presentation data")
	await _reset()
	_host.call("receive_action", "mekatana", {})
	_host.call("_update_movement", 0.06)
	_host.call("apply_stun", 0.5, "mekatana_network_test")
	_host.call("_update_movement", 1.0)
	_check(not attack.is_busy() and int(attack.next_step) == 0 and is_equal_approx(float(_target.call("get_health")), 1000.0), "authoritative interruption removes the prepared hit and combo")
	await _reset()
	_host.call("receive_action", "mekatana", {})
	_host.call("_update_movement", 0.06)
	_host.call("receive_action", "weapon", {"weapon": "blaster"})
	_host.call("_update_movement", 1.0)
	_check(not attack.is_busy() and str(_host.call("get_weapon_id")) == "blaster" and is_equal_approx(float(_target.call("get_health")), 1000.0), "network weapon change cancels a pending melee hit")
	await _reset()
	_replica.call("receive_action", "mekatana", {"step": 1}, true)
	_host.call("take_damage", 5000.0, "mekatana_network_test", "mekatana_network_death")
	_replica.call("receive_snapshot", _host.call("network_snapshot"))
	_check(bool(_replica.call("is_real_dead")) and not replica_attack.is_busy() and int(replica_attack.next_step) == 0, "confirmed death snapshot cancels replica melee visuals and sequence")
	for actor in [_host, _target, _replica]:
		actor.call("set_gameplay_enabled", false)
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	current_scene = null
	_scene.queue_free()
	await process_frame
	await process_frame
	attack = null
	replica_attack = null
	if _failures.is_empty():
		print("MEKATANA NETWORK TEST: PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error("MEKATANA NETWORK: " + failure)
		quit(1)
