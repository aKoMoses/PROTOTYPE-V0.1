extends SceneTree

const ACTOR := preload("res://scripts/network_player.gd")
const DATA := preload("res://scripts/combat_data.gd")
var _failures := 0

class ActionRelay:
	extends Node
	var _phase := "live"
	var replica: Node
	var host: Node
	var requested: Array[String] = []
	func on_actor_action(actor: Node, action: String, data: Dictionary) -> void:
		if actor == replica:
			requested.append(action)
			host.call("receive_action", action, data)


func _initialize() -> void:
	# GD-Sync's autoloads require a current scene even for standalone test scripts.
	var fixture := Node.new()
	fixture.name = "NetworkTestFixture"
	root.add_child(fixture)
	current_scene = fixture
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("NETWORK COMBAT: " + description)


func _actor(scene: Node, actor_name: String, authority := true, remote := true) -> Node3D:
	var result := CharacterBody3D.new()
	result.name = actor_name
	result.set_script(ACTOR)
	result.set("authoritative", authority)
	result.set("remote_controlled", remote)
	scene.add_child(result)
	return result


func _reset(a: Node3D, b: Node3D, defensive := "static_shield", offensive := "javelin") -> void:
	for actor in [a, b]:
		actor.call("apply_loadout", {"robot": "polyvalent", "weapon": "blaster", "offensive": offensive,
			"defensive": defensive, "mobility": "pyro_boots", "passive": "omnivamp"})
		actor.call("reset_combat_state")
		actor.call("set_gameplay_enabled", true)
	a.position = Vector3(-3.5, 0.0, 17.0)
	b.position = Vector3(0.0, 0.0, 17.0)
	a.set("aim_direction", Vector3.RIGHT)
	b.set("aim_direction", Vector3.LEFT)


func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	for old_actor in [scene.get_node("Player"), scene.get_node("TargetDummy")]:
		old_actor.collision_layer = 0
		old_actor.hide()
		old_actor.set_physics_process(false)
		old_actor.set_process(false)
	var a := _actor(scene, "AuthorityA")
	var b := _actor(scene, "AuthorityB")
	var client := _actor(scene, "ClientReplica", false)
	client.collision_layer = 0
	client.position = Vector3(10.0, 0.0, 17.0)
	a.set("opponent", b)
	b.set("opponent", a)
	client.set("opponent", a)
	_reset(a, b)
	await physics_frame
	b.call("take_damage", 12.0, "player", "duplicate")
	b.call("take_damage", 12.0, "player", "duplicate")
	_check(is_equal_approx(float(b.call("get_health")), 988.0), "an attack id cannot damage twice")
	_reset(a, b)
	await physics_frame
	a.call("receive_action", "blaster", {"ratio": 1.0})
	await create_timer(0.65).timeout
	_check(is_equal_approx(float(b.call("get_health")), 1000.0 - CombatData.WEAPON_DEFINITIONS.blaster.damage), "live host projectile hits once; an uncharged request cannot claim full charge")
	client.call("receive_snapshot", b.call("network_snapshot"))
	var client_hp := float(client.call("get_health"))
	client.call("take_damage", 500.0, "fake", "fake")
	client.get("combat_state").apply_damage(500.0, "fake_burn")
	client.call("apply_burn", 3.5, 20.0, "fake")
	_check(is_equal_approx(float(client.call("get_health")), client_hp), "a client cannot resolve damage or burn independently")
	b.call("_activate_defensive_module")
	_check(float(b.get("_stasis_remaining")) > 0.0, "stasis activated by the host")
	a.call("receive_action", "blaster", {})
	await create_timer(0.6).timeout
	_check(is_equal_approx(float(b.call("get_health")), 1000.0 - CombatData.WEAPON_DEFINITIONS.blaster.damage), "stasis blocks an actual incoming projectile")
	_reset(a, b, "magnetic_field")
	await physics_frame
	b.call("_activate_defensive_module")
	await create_timer(0.3).timeout
	_check(is_instance_valid(b.get("_magnetic_wall")), "magnetic protection exists in the host world")
	a.call("receive_action", "blaster", {})
	await create_timer(0.6).timeout
	_check(is_equal_approx(float(b.call("get_health")), 1000.0), "magnetic wall absorbs the live projectile before the actor")
	_reset(a, b)
	await physics_frame
	a.call("_perform_offensive_module")
	await create_timer(0.85).timeout
	_check(float(b.call("get_health")) < 900.0, "offensive module damage runs on the host")
	b.call("apply_spotted", 5.0, "network_effect_test")
	client.call("receive_snapshot", b.call("network_snapshot"))
	_check(client.get("combat_state").has_effect(DATA.EFFECT_SPOTTED), "confirmed effects are replicated")
	_reset(a, b, "static_shield", "javelin")
	await physics_frame
	a.call("_perform_offensive_module")
	await create_timer(0.65).timeout
	_check(bool(b.call("has_javelin_mark")), "authoritative javelin marks the other player")
	var origin := a.position
	a.call("_perform_offensive_module")
	_check(a.position.distance_to(origin) > 0.5 and not b.call("has_javelin_mark"), "recast validates and clears the shared mark")
	_reset(a, b)
	await physics_frame
	a.set("_last_move_direction", Vector3.RIGHT)
	a.call("_activate_mobility_module")
	await create_timer(0.3).timeout
	_check(a.position.x > -1.0, "host dash uses the ordinary collision-aware movement")
	var cooldown := float(a.call("get_module_cooldown", "pyro_boots"))
	a.call("receive_action", "mobility", {})
	_check(bool(a.call("is_dash_active")) and int(a.call("get_pyro_charges")) == 0, "host accepts a second dash from its reserve charge")
	await create_timer(0.3).timeout
	a.call("receive_action", "mobility", {})
	_check(not bool(a.call("is_dash_active")) and float(a.call("get_module_cooldown", "pyro_boots")) <= cooldown, "third dash cannot bypass the two authoritative charges")
	_reset(a, b)
	b.position.x = -1.5
	b.call("set_weapon", "shotgun")
	await physics_frame
	b.call("receive_action", "shotgun", {})
	await create_timer(0.7).timeout
	_check(float(a.call("get_health")) < 950.0 and int(b.call("get_shotgun_ammo")) == 2, "shotgun uses physical pellets and authoritative ammunition")
	client.call("set_gameplay_enabled", true)
	client.call("set_weapon", "shotgun")
	client.call("receive_action", "shotgun", {}, true)
	_check(int(client.get("received_actions")) == 1 and bool(client.get("_shotgun_attack_busy")), "accepted remote attacks play through the existing visual controller")
	_reset(a, b)
	a.call("receive_action", "contact", {})
	a.call("receive_action", "charge", {})
	_check(bool(a.get("_blaster_charge_active")), "remote charge starts its visible controller")
	a.call("receive_action", "cancel", {})
	_check(not bool(a.get("_blaster_charge_active")) and float(a.get("_contact_started_at")) < 0.0, "interrupted touch charge cannot contaminate the next shot")
	_reset(a, b)
	await physics_frame
	# Desktop charge has no touch-contact fallback if its clock is lost.
	a.call("receive_action", "charge", {})
	var charge_started: float = a.get("_blaster_charge_started_at")
	await create_timer(1.05).timeout
	a.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	a.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(bool(a.get("_blaster_charge_active")) and is_equal_approx(float(a.get("_blaster_charge_started_at")), charge_started), "host focus loss and app suspension preserve the remote human's authoritative charge clock")
	a.call("receive_action", "blaster", {})
	await create_timer(0.65).timeout
	_check(is_equal_approx(float(b.call("get_health")), 1000.0 - CombatData.WEAPON_DEFINITIONS.blaster.max_damage), "remote release after host focus loss still delivers full Blaster damage")
	var local := _actor(scene, "LocalFocusProbe", true, false)
	local.collision_layer = 0
	local.set_process(false)
	local.set_physics_process(false)
	for notification in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		local.call("reset_combat_state")
		local.call("set_gameplay_enabled", true)
		local.call("_begin_blaster_charge")
		_check(bool(local.get("_blaster_charge_active")), "local network fighter starts its desktop charge before suspension")
		local.notification(notification)
		_check(not bool(local.get("_blaster_charge_active")), "local focus loss and app suspension retain desktop charge cancellation")
	local.call("set_gameplay_enabled", false)
	local.queue_free()
	_reset(a, b)
	b.call("set_passive", "baroud")
	b.call("take_damage", 2000.0, "test", "baroud_start")
	_check(b.get("passive_state").baroud_active and not b.call("is_real_dead"), "the host resolves lethal damage through Baroud")
	client.call("receive_snapshot", b.call("network_snapshot"))
	client.get("passive_state").process(5.0)
	_check(not client.call("is_real_dead"), "a replica cannot declare Baroud's death locally")
	b.get("passive_state").process(5.0)
	b.call("_finalize_passive_death")
	client.call("receive_snapshot", b.call("network_snapshot"))
	_check(client.call("is_real_dead"), "Baroud's final death arrives from the host")
	# Exercise the same begin/release/cancel API used by PC and touch input.
	_reset(a, b, "static_shield", "fulguro_punch")
	a.position.x = -1.5
	client.call("apply_loadout", {"weapon": "blaster", "offensive": "fulguro_punch"})
	client.call("reset_combat_state")
	client.call("set_gameplay_enabled", true)
	client.position = a.position
	client.set("aim_direction", Vector3.RIGHT)
	var relay := ActionRelay.new()
	scene.add_child(relay)
	relay.replica = client
	relay.host = a
	client.set("controller", relay)
	a.set("controller", relay)
	client.call("_begin_fulguro_charge")
	_check(relay.requested == ["fulguro_begin"] and a.call("is_fulguro_charging"), "guest Fulguro charge starts on the host")
	await create_timer(0.45).timeout
	client.call("_release_fulguro_charge")
	_check(relay.requested.has("fulguro_release") and a.get("_fulguro_release_requested"), "guest Fulguro release reaches the host")
	await create_timer(0.25).timeout
	_check(float(b.call("get_health")) < 1000.0 and float(a.get("_fulguro_strike_damage")) < float(DATA.MODULE_DEFINITIONS.fulguro_punch.damage_max), "host resolves Fulguro damage from its own charge time")
	_reset(a, b, "static_shield", "fulguro_punch")
	client.call("reset_combat_state")
	client.call("set_gameplay_enabled", true)
	client.call("_begin_fulguro_charge")
	client.call("_cancel_fulguro_attack")
	_check(relay.requested.has("fulguro_cancel") and not a.call("is_fulguro_charging"), "a lost touch contact cancels Fulguro on the host")
	client.set("controller", null)
	a.set("controller", null)
	# Both forced movement and its final correction come from the host.
	_reset(a, b)
	client.call("reset_combat_state")
	client.call("set_gameplay_enabled", true)
	b.call("start_pelto_pull", Vector3.LEFT, 1.5, 0.15, "test", "pull-test")
	client.call("receive_snapshot", b.call("network_snapshot"))
	_check(client.call("is_pelto_pulled"), "confirmed Pelto pull reaches the client")
	await create_timer(0.25).timeout
	_check(b.position.x < -1.0 and not b.call("is_pelto_pulled"), "host moves the remote human during Pelto's pull")
	client.call("receive_snapshot", b.call("network_snapshot"))
	_check(not client.call("is_pelto_pulled") and client.position.distance_to(b.position) < 0.01, "Pelto ends with the same position on both clients")
	_reset(a, b)
	b.call("_perform_static_shield")
	await create_timer(float(DATA.MODULE_DEFINITIONS.static_shield.minimum_duration) + 0.05).timeout
	b.call("apply_stun", 1.0, "test")
	b.call("receive_action", "stasis_exit", {})
	_check(float(b.get("_stasis_remaining")) <= 0.0, "guest can cancel Static Shield even while stunned")
	relay.queue_free()
	# Freeze cleanup before SceneTree exits so pending callbacks cannot hit freed actors.
	for actor in [a, b, client]:
		actor.call("set_gameplay_enabled", false)
		actor.call("reset_module_state")
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	scene.call("clear_transient_fx")
	await create_timer(0.2).timeout
	scene.queue_free()
	await process_frame
	await process_frame
	print("NETWORK COMBAT TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
