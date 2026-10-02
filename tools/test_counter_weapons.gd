extends "res://tools/test_counter.gd"

const NETWORK_ACTOR := preload("res://scripts/network_player.gd")


class CleaveProbe extends StaticBody3D:
	var health := 1000.0
	func take_damage(amount: float, _source: String = "", _id: String = "") -> float:
		var applied := minf(health, amount)
		health -= applied
		return applied
	func get_health() -> float:
		return health


func weapon_prepare(weapon: String) -> CounterGuard:
	prepare()
	player.call("set_weapon", weapon)
	player.call("set_passive", "")
	player.call("set_touch_aim_vector", Vector2(0, -1))
	player.set_physics_process(true)
	target.call("set_duel_loadout", {"weapon": "blaster", "defensive": "counter", "passive": ""})
	target.set_process(false)
	target.global_position = Vector3(0, 0, -3.0)
	var result := COUNTER.ensure(target)
	result.cancel(true)
	return result


func emit_weapon(weapon: String) -> void:
	match weapon:
		"blaster": player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.FORWARD)
		"shotgun": player.call("_perform_shotgun_attack")
		"longshot": player.call("_perform_longshot_attack")
		"mekatana": player.call("_perform_mekatana_attack")
	await create_timer(0.65).timeout


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.get_node("Interface").call("_start_duel")
	scene.get_node("Interface").call("_begin_live_round")
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	for weapon in ["blaster", "shotgun", "longshot", "mekatana"]:
		var enemy_guard := weapon_prepare(weapon)
		if weapon == "mekatana":
			target.global_position.z = -2.0
		await physics_frame
		await physics_frame
		enemy_guard.begin()
		enemy_guard.update(0.08)
		var successes := enemy_guard.successes
		await emit_weapon(weapon)
		check(float(target.call("get_health")) == 1000, "real emitted %s intercepted" % weapon)
		check(enemy_guard.successes == successes + 1, "real %s triggers once" % weapon)
		if weapon == "longshot":
			check(int(player.call("get_longshot_cycle_count")) == 0 and player.get("_longshot_state").speed_remaining == 0.0, "counter grants neither precision nor hit mobility")
		check(not target.get("combat_state").has_effect(DATA.EFFECT_BURN), "intercepted %s adds no burn" % weapon)
		weapon_prepare(weapon)
		if weapon == "mekatana":
			target.global_position.z = -2.0
		await physics_frame
		await physics_frame
		guard.surcharge_remaining = 3.0
		var count := guard.explosions
		await emit_weapon(weapon)
		check(guard.surcharge_remaining == 0, "real %s consumes reward at emission" % weapon)
		check(guard.explosions == count + 1, "real %s explodes once" % weapon)
		check(float(target.call("get_health")) < 990, "real %s keeps primary damage plus explosion" % weapon)
		weapon_prepare(weapon)
		target.global_position = Vector3(7, 0, 0)
		await physics_frame
		guard.surcharge_remaining = 3.0
		count = guard.explosions
		await emit_weapon(weapon)
		check(guard.surcharge_remaining == 0 and guard.explosions == count, "missed %s loses reward without explosion" % weapon)
	await test_charged_and_obstacle()
	await test_execution_guard()
	await test_multiple_cleave()
	await test_three_fingers()
	await test_network_guard()
	if failures.is_empty():
		print("COUNTER WEAPONS TEST: PASS (%d checks)" % checks)
	else:
		for failure in failures:
			push_error("COUNTER WEAPONS: " + failure)
	quit(0 if failures.is_empty() else 1)


func test_multiple_cleave() -> void:
	weapon_prepare("mekatana")
	player.set_physics_process(false)
	target.global_position = Vector3(-0.55, 0, -1.5)
	var other := CleaveProbe.new()
	other.collision_layer = 2
	scene.add_child(other)
	other.global_position = Vector3(0.55, 0, -1.5)
	await physics_frame
	guard.surcharge_remaining = 3.0
	var explosions_before := guard.explosions
	var melee := MELEE.new()
	melee.configure(player, "player")
	melee.definition.dash_distance = [0.0, 0.0, 0.0]
	melee.start(Vector3.FORWARD)
	melee.update(0.23)
	check(guard.explosions == explosions_before + 1, "real two-target cleave emits one explosion")
	check(is_equal_approx(float(target.call("get_health")), 830), "cleave direct target receives one primary and one secondary hit")
	check(is_equal_approx(other.health, 830), "cleave second enemy receives secondary damage only once (health %.1f)" % other.health)
	melee.cancel()
	melee = null
	other.queue_free()
	await process_frame


func test_charged_and_obstacle() -> void:
	weapon_prepare("blaster")
	await physics_frame
	guard.surcharge_remaining = 3.0
	player.call("_fire_blaster_projectile", 50.0, 1.0, Vector3.FORWARD)
	await create_timer(0.4).timeout
	check(is_equal_approx(float(target.call("get_health")), 870.0), "fully charged blaster adds only fixed 80")
	weapon_prepare("longshot")
	player.get("_longshot_state").hits = 2
	await physics_frame
	guard.surcharge_remaining = 3.0
	await emit_weapon("longshot")
	check(is_equal_approx(float(target.call("get_health")), 1000.0 - float(DATA.WEAPON_DEFINITIONS.longshot.damage) * float(DATA.WEAPON_DEFINITIONS.longshot.enhanced_damage_multiplier) - float(DATA.MODULE_DEFINITIONS.counter.surcharge_damage)), "execution Longshot adds fixed surcharge once")
	weapon_prepare("blaster")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0, 1, -1.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.25)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	await physics_frame
	await physics_frame
	guard.surcharge_remaining = 3.0
	var explosions_before := guard.explosions
	await emit_weapon("blaster")
	check(guard.surcharge_remaining == 0 and guard.explosions == explosions_before, "real wall collision consumes reward without explosion")
	check(float(target.call("get_health")) == 1000, "wall-stopped boosted projectile deals no damage")
	wall.queue_free()
	await process_frame


func test_execution_guard() -> void:
	var enemy_guard := weapon_prepare("longshot")
	var behind := CleaveProbe.new()
	behind.collision_layer = 2
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.5)
	collision.shape = box
	behind.add_child(collision)
	scene.add_child(behind)
	behind.position = Vector3(0, 1, -6)
	await physics_frame
	await physics_frame
	player.get("_longshot_state").hits = 2
	enemy_guard.begin()
	enemy_guard.update(0.08)
	await emit_weapon("longshot")
	check(float(target.call("get_health")) == 1000 and behind.health == 1000, "real Counter stops execution before the next victim")
	check(int(player.call("get_longshot_cycle_count")) == 0 and player.get("_longshot_state").speed_remaining == 0.0, "blocked execution is consumed and grants no mobility")
	behind.queue_free()
	await process_frame


func test_three_fingers() -> void:
	prepare()
	var controls: Node = scene.get_node("Interface/TouchControls")
	controls.set("player", player)
	controls.set("force_preview", true)
	controls.show()
	await process_frame
	var layout: Dictionary = controls.call("_layout_for_safe_rect", controls.call("_safe_rect"))
	var buttons: Dictionary = controls.call("_action_centers")
	check(controls.call("_begin_touch", 51, layout.move), "movement finger accepted")
	controls.call("_update_touch", 51, layout.move + Vector2(20, -10))
	check(controls.call("_begin_touch", 52, layout.aim), "aim finger accepted")
	controls.call("_update_touch", 52, layout.aim + Vector2(35, -25))
	var aim: Vector2 = player.get("_touch_aim_vector")
	check(controls.call("_begin_touch", 53, buttons.defensive), "counter finger accepted")
	player.call("_update_debug_effects")
	check(guard.phase == "preparation", "module finger starts COUNTER")
	check(int(controls.get("_aim_touch")) == 52 and player.get("_touch_aim_vector") == aim, "module retains right finger and independent aim")
	controls.call("_end_touch", 53)
	check(int(controls.get("_aim_touch")) == 52 and int(controls.get("_joystick_touch")) == 51, "module release retains both joysticks")
	guard.update(1.08)
	controls.call("_end_touch", 52)
	controls.call("_end_touch", 51)
	check(player.get("_touch_fire_requests").is_empty(), "release after counter produces no stored shot")
	controls.hide()


func network_actor(actor_name: String, authority: bool) -> Node3D:
	var actor := CharacterBody3D.new()
	actor.name = actor_name
	actor.set_script(NETWORK_ACTOR)
	actor.set("authoritative", authority)
	actor.set("remote_controlled", true)
	scene.add_child(actor)
	actor.call("apply_loadout", {"weapon": "blaster", "defensive": "counter", "passive": "omnivamp"})
	actor.call("reset_combat_state")
	actor.call("set_gameplay_enabled", true)
	return actor


func test_network_guard() -> void:
	player.collision_layer = 0
	target.collision_layer = 0
	var host := network_actor("CounterHost", true)
	var enemy := network_actor("CounterEnemy", true)
	var client := network_actor("CounterReplica", false)
	client.collision_layer = 0
	host.global_position = Vector3(0, 0, 17)
	enemy.global_position = Vector3(-3.5, 0, 17)
	host.set("opponent", enemy)
	enemy.set("opponent", host)
	client.set("opponent", enemy)
	enemy.set("aim_direction", Vector3.RIGHT)
	host.set("aim_direction", Vector3.LEFT)
	await physics_frame
	host.call("receive_action", "defensive", {})
	await create_timer(0.1).timeout
	client.call("receive_snapshot", host.call("network_snapshot"))
	check(client.call("is_counter_guarding"), "host guard phase replicated")
	enemy.call("receive_action", "blaster", {"surcharge": true, "ratio": 1.0})
	await create_timer(0.3).timeout
	check(float(host.call("get_health")) == 1000 and float(host.call("get_surcharge_remaining")) > 0, "host alone intercepts real projectile and grants charge")
	client.call("receive_snapshot", host.call("network_snapshot"))
	check(float(client.call("get_surcharge_remaining")) > 0 and not client.call("is_counter_guarding"), "reward and end of protection replicated")
	var client_guard := COUNTER.component(client)
	var attack := COUNTER.weapon_attack(enemy, "fake-client-hit", DATA.WEAPON_DEFINITIONS.blaster)
	check(not client_guard.intercept(attack), "replica cannot award success independently")
	host.call("receive_action", "blaster", {})
	await create_timer(0.35).timeout
	check(is_equal_approx(float(enemy.call("get_health")), 1000.0 - float(DATA.WEAPON_DEFINITIONS.blaster.damage) - float(DATA.MODULE_DEFINITIONS.counter.surcharge_damage)), "network return weapon applies primary plus fixed surcharge")
	check(float(host.call("get_surcharge_remaining")) == 0, "network host consumes reward once")
	client.call("receive_snapshot", host.call("network_snapshot"))
	check(float(client.call("get_surcharge_remaining")) == 0, "consumption replicated")
	# Secondary damage must bypass COUNTER and never heal the firing Omnivamp actor.
	host.call("take_damage", 100, "test", "wound")
	var health_before: float = host.call("get_health")
	var enemy_guard := COUNTER.component(enemy)
	enemy_guard.begin()
	enemy_guard.update(0.08)
	var enemy_before: float = enemy.call("get_health")
	COUNTER.explode(host, enemy.global_position + Vector3.UP * 0.85, {"id": "secondary", "radius": 2.2, "damage": 10.0})
	check(float(enemy.call("get_health")) == enemy_before - 10 and enemy_guard.phase == "guard", "secondary explosion bypasses counter without rewarding it")
	check(float(host.call("get_health")) == health_before, "secondary explosion grants no Omnivamp healing")
	host.set_meta("combat_team", "allied")
	enemy.set_meta("combat_team", "allied")
	enemy_before = enemy.call("get_health")
	COUNTER.explode(host, enemy.global_position + Vector3.UP * 0.85, {"id": "ally", "radius": 2.2, "damage": 10.0})
	check(float(enemy.call("get_health")) == enemy_before, "secondary explosion respects team rules")
	for actor in [host, enemy, client]:
		actor.call("set_gameplay_enabled", false)
		actor.queue_free()
	await process_frame
