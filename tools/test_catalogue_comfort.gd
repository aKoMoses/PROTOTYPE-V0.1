extends SceneTree

const DATA := preload("res://scripts/combat_data.gd")
const NETWORK := preload("res://scripts/network_player.gd")
const WALL := preload("res://scripts/magnetic_wall.gd")
const PYRO := preload("res://scripts/pyro_boots.gd")
const TOUCH := preload("res://scripts/touch_module_visual.gd")
var failures: Array[String] = []
var checks := 0
var player: Node3D
var target: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func setup(mobility: String = "pyro_boots") -> void:
	player.call("apply_loadout", {"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": mobility, "passive": "inertia"})
	player.call("reset_combat_state")
	player.set_physics_process(false)
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3.FORWARD)
	target.call("reset_combat_state")
	target.global_position = Vector3(0, 0, -1.5)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.set_process(false)

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.get_node("Interface").call("_start_duel")
	scene.get_node("Interface").call("_begin_live_round")
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	setup()
	player.call("_activate_defensive_module")
	check(float(player.call("take_damage", 100.0, "test", "protected")) == 0.0, "stasis still protects")
	player.set("_stasis_remaining", 1.01)
	player.call("_activate_defensive_module")
	check(float(player.call("get_stasis_remaining")) > 0.0, "exit refused before 0.5 seconds")
	player.set("_stasis_remaining", 1.0)
	var touch := TOUCH.new()
	touch.update(player, 0.0, true)
	check(bool(touch.states.defensive.recast) and not bool(touch.states.defensive.unavailable), "touch button offers exit at boundary")
	var cooldown := float(player.call("get_module_cooldown", "static_shield"))
	player.call("_activate_defensive_module")
	check(float(player.call("get_stasis_remaining")) == 0.0, "second defensive command exits")
	check(float(player.call("get_module_cooldown", "static_shield")) == cooldown, "exit does not refund cooldown")
	check(float(player.call("take_damage", 100.0, "test", "after_exit")) == 100.0, "damage resumes immediately")
	setup()
	player.call("_activate_defensive_module")
	player.set("_stasis_remaining", 1.0)
	await physics_frame
	await process_frame
	check(bool(player.call("begin_touch_action", "defensive")), "touch exit command accepted during stasis")
	player.call("_update_debug_effects")
	check(float(player.call("get_stasis_remaining")) == 0.0, "touch command actually exits stasis")
	setup()
	target.get("combat_state").grant_shield(500.0, 5.0)
	var token := int(player.get("_javelin_launch_token"))
	player.call("_on_javelin_finished", {"collider": target, "position": target.global_position + Vector3.UP}, 1.0, token)
	check(float(target.call("get_health")) == 1000.0 and float(target.get("combat_state").shield_health) == 360.0, "javelin is absorbed by shield")
	check(bool(player.call("_has_live_javelin_mark")), "absorbed javelin still marks")
	target.global_position.z = -4.0
	await physics_frame
	player.call("_recast_javelin")
	check(player.global_position.length() > 1.0 and not bool(player.call("_has_live_javelin_mark")), "shield mark allows one real recast")
	check(float(player.get("passive_state").inertia_remaining) == 0.0, "offensive teleport does not arm inertia")
	setup()
	await physics_frame
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	check(float(target.call("get_health")) == 940.0, "actual dash deals departure damage")
	check(float(player.get("passive_state").inertia_remaining) == 0.0, "inertia waits for dash completion")
	player.call("_update_dash", 0.18)
	check(float(player.get("passive_state").inertia_remaining) > 0.0, "completed dash arms inertia")
	setup()
	player.set_meta("combat_team", 1)
	target.set_meta("combat_team", 1)
	PYRO.departure(player, [target, target], "test", "friendly")
	check(float(target.call("get_health")) == 1000.0, "departure excludes teammates")
	player.remove_meta("combat_team")
	target.remove_meta("combat_team")
	var barrier := StaticBody3D.new()
	barrier.position = Vector3(0, 1, -0.8)
	barrier.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 2, 0.2)
	collision.shape = box
	barrier.add_child(collision)
	scene.add_child(barrier)
	await physics_frame
	PYRO.departure(player, [target], "test", "covered")
	check(float(target.call("get_health")) == 1000.0, "departure cannot damage through cover")
	barrier.position.z = -2.1
	await physics_frame
	var placement := WALL.find_placement(player, Vector3.FORWARD, 2.0, 4.0, 2.4)
	check(placement.is_finite() and placement.z > -1.9, "wall placement adjusts before nearby obstacle")
	barrier.position.z = -0.8
	await physics_frame
	check(not WALL.find_placement(player, Vector3.FORWARD, 2.0, 4.0, 2.4).is_finite(), "wall never jumps across obstruction")
	player.call("apply_loadout", {"defensive": "magnetic_field"})
	player.call("_perform_magnetic_field")
	check(float(player.call("get_module_cooldown", "magnetic_field")) == 0.0, "failed placement consumes no cooldown")
	barrier.queue_free()
	await physics_frame
	for mobility in ["bio_injector", "permutation", "eclipse"]:
		setup(mobility)
		target.global_position.z = -4.0
		await physics_frame
		match mobility:
			"bio_injector": player.call("_perform_bio_injector")
			"permutation":
				player.call("_perform_permutation")
				await create_timer(0.5).timeout
			"eclipse":
				check(bool(player.call("_perform_eclipse", Vector3(-3, 0, 0))), "eclipse accepts destination")
				player.get("_eclipse").update(player, 0.3)
		check(float(player.get("passive_state").inertia_remaining) > 0.0, mobility + " arms inertia on success")
		var attack: Dictionary = player.call("emit_passive_weapon")
		check(bool(attack.slow) and float(attack.slow_percent) == 25.0 and float(attack.slow_duration) == 1.5, mobility + " stamps strengthened slow")
		check(not bool(player.call("emit_passive_weapon").slow), mobility + " reward consumed once")
	setup("bio_injector")
	player.get("_module_cooldowns")["bio_injector"] = 1.0
	player.call("_perform_bio_injector")
	check(float(player.get("passive_state").inertia_remaining) == 0.0, "rejected Bio grants no inertia")
	setup("eclipse")
	check(bool(player.call("_perform_eclipse", Vector3(-3, 0, 0))), "cancellable eclipse begins")
	player.get("_eclipse").cancel(player)
	check(float(player.get("passive_state").inertia_remaining) == 0.0, "cancelled eclipse grants no inertia")
	setup("permutation")
	player.call("_perform_permutation")
	player.call("apply_stun", 0.3, "test")
	await create_timer(0.5).timeout
	check(float(player.get("passive_state").inertia_remaining) == 0.0, "interrupted permutation grants no inertia")
	var host := NETWORK.new()
	host.remote_controlled = true
	scene.add_child(host)
	host.call("apply_loadout", {"defensive": "static_shield", "passive": "inertia"})
	host.set_physics_process(false)
	host.call("_perform_static_shield")
	host.call("receive_action", "stasis_exit", {}, false)
	check(float(host.call("get_stasis_remaining")) > 0.0, "host rejects premature network exit")
	host.set("_stasis_remaining", 1.0)
	host.call("receive_action", "stasis_exit", {}, false)
	check(float(host.call("get_stasis_remaining")) == 0.0, "host accepts network exit after minimum")
	var replica := NETWORK.new()
	replica.authoritative = false
	replica.remote_controlled = true
	scene.add_child(replica)
	replica.set_physics_process(false)
	replica.global_position = Vector3.ZERO
	target.call("reset_combat_state")
	target.global_position = Vector3(0, 0, -1)
	PYRO.departure(replica, [target], "test", "replica")
	check(float(target.call("get_health")) == 1000.0, "replica departure applies no damage")
	replica.set("_stasis_remaining", 1.0)
	replica.call("receive_action", "stasis_exit", {}, true)
	check(float(replica.call("get_stasis_remaining")) == 0.0, "replica displays confirmed network exit")
	host.call("apply_loadout", {"mobility": "pyro_boots", "passive": "omnivamp"})
	host.call("reset_combat_state")
	host.set_physics_process(false)
	host.call("set_gameplay_enabled", true)
	host.set_physics_process(false)
	host.global_position = Vector3.ZERO
	host.get("combat_state").health = 600.0
	var victim := NETWORK.new()
	victim.remote_controlled = true
	scene.add_child(victim)
	victim.set_physics_process(false)
	victim.call("set_gameplay_enabled", true)
	victim.set_physics_process(false)
	victim.global_position = Vector3(0, 0, -1.5)
	victim.opponent = host
	host.opponent = victim
	await physics_frame
	PYRO.departure(host, [victim, victim], "player", "network_pyro", Callable(host, "_credit_pyro_damage"))
	check(float(victim.call("get_health")) == 940.0, "network departure damages one victim once: %.1f" % float(victim.call("get_health")))
	check(float(host.call("get_health")) == 609.0, "network departure heals Omnivamp only once: %.1f" % float(host.call("get_health")))
	for failure in failures:
		push_error("CATALOGUE: " + failure)
	print("CATALOGUE COMFORT TEST: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
