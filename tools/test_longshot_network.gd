extends SceneTree

const ACTOR := preload("res://scripts/network_player.gd")
const DATA := preload("res://scripts/combat_data.gd")
var _checks := 0
var _failures: Array[String] = []

class Recorder:
	extends Node
	var _phase := "live"
	var events: Array[Dictionary] = []
	func on_actor_action(actor: Node, action: String, data: Dictionary) -> void:
		events.append({"actor": actor, "action": action, "data": data.duplicate(true)})


func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "LongshotNetworkFixture"
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("LONGSHOT NETWORK: " + label)


func _actor(label: String, authority: bool, recorder: Node) -> Node3D:
	var actor: Node3D = ACTOR.new()
	actor.name = label
	actor.set("authoritative", authority)
	actor.set("remote_controlled", true)
	actor.set("controller", recorder)
	current_scene.add_child(actor)
	actor.call("apply_loadout", {"weapon": "longshot", "passive": "omnivamp"})
	actor.call("set_gameplay_enabled", true)
	actor.set_physics_process(false)
	return actor


func _run() -> void:
	var recorder := Recorder.new()
	current_scene.add_child(recorder)
	var host := _actor("Host", true, recorder)
	var target := _actor("Target", true, recorder)
	var replica := _actor("Replica", false, recorder)
	host.set("opponent", target)
	target.set("opponent", host)
	replica.set("opponent", target)
	replica.set("collision_layer", 0)
	replica.position = Vector3(40, 0, 0)
	target.position = Vector3(0, 0, -8)
	host.set("aim_direction", Vector3.FORWARD)
	host.call("_update_robot_motion", 0.2)
	await physics_frame
	await process_frame
	# A malicious request for shot five is still shot one on the host.
	host.call("receive_action", "longshot", {"enhanced": true, "shot_number": 5})
	await create_timer(0.35).timeout
	_check(int(host.call("get_longshot_shots_fired")) == 1, "host commits one real shot")
	var fired: Array = recorder.events.filter(func(e: Dictionary) -> bool: return e.action == "longshot_fired" and e.actor == host)
	_check(fired.size() == 1 and not bool(fired[0].data.enhanced), "host ignores client's enhanced flag")
	_check(float(target.call("get_health")) < 920.0 and float(target.call("get_health")) > 850.0, "normal host projectile damages once")
	_check(int(host.call("get_longshot_cycle_count")) == 1, "only successful host damage earns an impact")
	host.call("receive_action", "longshot", {"enhanced": true})
	await create_timer(0.12).timeout
	_check(int(host.call("get_longshot_shots_fired")) == 1, "repeated request during recovery is refused")
	replica.call("receive_snapshot", host.call("network_snapshot"))
	_check(int(replica.call("get_longshot_shots_fired")) == 1, "authoritative cycle is replicated")
	_check(int(replica.call("get_longshot_cycle_count")) == 1 and is_equal_approx(float(replica.call("get_current_move_speed")), float(host.call("get_current_move_speed"))), "earned impacts and mobility follow host snapshot")
	_check(float(replica.get("_longshot_next_attack_ready_at")) > Time.get_ticks_msec() / 1000.0, "remaining recovery is replicated")
	var replica_hp: float = replica.call("get_health")
	replica.call("take_damage", 200.0, "fake", "fake_longshot")
	_check(is_equal_approx(float(replica.call("get_health")), replica_hp), "replica cannot resolve damage")
	# Snapshot precedes the reliable visual event: never commit the cycle twice.
	host.get("_longshot_state").shots_fired = 4
	host.get("_longshot_state").hits = 2
	replica.call("receive_snapshot", host.call("network_snapshot"))
	_check(bool(replica.call("is_longshot_enhanced_ready")), "ready state follows host snapshot")
	replica.call("receive_action", "longshot_fired", {"enhanced": false, "shot_number": 4}, true)
	await create_timer(0.15).timeout
	_check(int(replica.call("get_longshot_shots_fired")) == 4, "late visual event leaves confirmed cycle intact")
	host.set("_longshot_next_attack_ready_at", -10.0)
	host.call("receive_action", "longshot", {"enhanced": false, "shot_number": 1})
	await create_timer(0.20).timeout
	fired = recorder.events.filter(func(e: Dictionary) -> bool: return e.action == "longshot_fired" and e.actor == host)
	_check(fired.size() == 2 and bool(fired[-1].data.enhanced), "host execution ignores client denial")
	_check(int(host.call("get_longshot_cycle_count")) == 0, "execution consumes impacts and cannot charge itself")
	replica.call("receive_snapshot", host.call("network_snapshot"))
	replica.call("receive_action", "longshot_fired", {"enhanced": true, "shot_number": 5}, true)
	await create_timer(0.15).timeout
	_check(int(replica.call("get_longshot_shots_fired")) == 5, "enhanced visual event after snapshot does not double advance")
	host.call("set_weapon", "blaster")
	replica.call("receive_snapshot", host.call("network_snapshot"))
	_check(str(replica.call("get_weapon_id")) == "blaster" and int(replica.call("get_longshot_shots_fired")) == 5, "weapon switch snapshot preserves LONGSHOT instance")
	host.call("set_weapon", "longshot")
	host.call("reset_combat_state")
	replica.call("receive_snapshot", host.call("network_snapshot"))
	_check(int(replica.call("get_longshot_shots_fired")) == 0, "new round snapshot resets cycle")
	await physics_frame
	await process_frame
	host.call("receive_action", "longshot", {})
	host.call("receive_action", "cancel", {})
	await create_timer(0.16).timeout
	_check(int(host.call("get_longshot_shots_fired")) == 0, "remote cancellation before emission never advances cycle")
	await create_timer(0.7).timeout
	current_scene.queue_free()
	current_scene = null
	await process_frame
	print("LONGSHOT NETWORK: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
