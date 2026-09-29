extends SceneTree

const ACTOR := preload("res://scripts/network_player.gd")
const DATA := preload("res://scripts/combat_data.gd")
var _failures := 0


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


func _actor(scene: Node, actor_name: String, authority := true) -> Node3D:
	var result := CharacterBody3D.new()
	result.name = actor_name
	result.set_script(ACTOR)
	result.set("authoritative", authority)
	result.set("remote_controlled", true)
	scene.add_child(result)
	return result


func _reset(a: Node3D, b: Node3D, defensive := "static_shield", offensive := "modulo_drone") -> void:
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
	_check(is_equal_approx(float(b.call("get_health")), 980.0), "live host projectile hits once; an uncharged request cannot claim full charge")
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
	_check(is_equal_approx(float(b.call("get_health")), 980.0), "stasis blocks an actual incoming projectile")
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
	_check(float(b.call("get_health")) < 900.0, "drone damage and burn run on the host")
	_check(b.get("combat_state").has_effect(DATA.EFFECT_SPOTTED), "drone applies its reveal")
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
	_check(not bool(a.call("is_dash_active")) and float(a.call("get_module_cooldown", "pyro_boots")) <= cooldown, "duplicate dash cannot bypass cooldown")
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
