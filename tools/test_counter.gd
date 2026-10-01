extends SceneTree

const COUNTER := preload("res://scripts/counter.gd")
const DATA := preload("res://scripts/combat_data.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
const MELEE := preload("res://scripts/mekatana_attack.gd")
var failures: Array[String] = []
var checks := 0
var player: Node3D
var target: Node3D
var scene: Node
var guard: CounterGuard


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func prepare() -> void:
	player.call("set_robot", DATA.DEFAULT_ROBOT)
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.set("_defensive_module_id", "counter")
	player.call("set_passive", "")
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3.FORWARD)
	target.call("reset_combat_state")
	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(0, 0, -1.6)
	guard = COUNTER.component(player)


func payload(id: String, weapon: String = "blaster") -> Dictionary:
	return COUNTER.weapon_attack(target, id, DATA.WEAPON_DEFINITIONS[weapon])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	prepare()
	check(player.call("_perform_counter"), "activation accepted")
	check(is_equal_approx(float(player.call("get_module_cooldown", "counter")), 8.0), "cooldown begins at activation")
	check(guard.phase == "preparation" and is_equal_approx(guard.movement_multiplier(), 0.5), "unprotected preparation slowed")
	check(COUNTER.impact(player, 20, "test", "prep", payload("prep"), Vector3.UP) == 20, "preparation takes damage")
	guard.update(0.08)
	check(guard.phase == "guard" and guard._outline.visible, "guard visual matches protection")
	var volley := payload("volley", "shotgun")
	var successes := guard.successes
	for i in range(6):
		check(COUNTER.impact(player, 20, "test", "pellet:%d" % i, volley, Vector3.UP) == 0, "entire triggering volley intercepted")
	check(guard.successes == successes + 1 and guard.phase == "recovery", "single success immediately ends guard")
	check(not guard._outline.visible and guard.surcharge_remaining == 3.0, "reward granted once and outline removed")
	check(COUNTER.impact(player, 20, "test", "next", payload("next"), Vector3.UP) == 20, "next separate attack dangerous during recovery")
	guard.update(0.12)
	check(str(player.call("get_action_owner")) == "", "success recovery releases action gate")
	var cooldown := float(player.call("get_module_cooldown", "counter"))
	check(not player.call("_perform_counter"), "cooldown rejects repeated activation")
	player.call("_update_module_cooldowns", 1.0)
	check(absf(float(player.call("get_module_cooldown", "counter")) - cooldown + 1.0) < 0.001, "cooldown independent of guard state")
	guard.update(3.0)
	check(guard.surcharge_remaining == 0.0, "unspent reward expires")
	prepare()
	player.call("_perform_counter")
	guard.update(0.88)
	check(guard.phase == "recovery" and guard.surcharge_remaining == 0.0, "empty guard expires without reward")
	check(COUNTER.impact(player, 20, "test", "expired", payload("expired"), Vector3.UP) == 20, "expired guard unprotected")
	guard.update(0.20)
	check(guard.phase == "" and str(player.call("get_action_owner")) == "", "failure recovery releases actions")
	prepare()
	player.call("apply_burn", 1.0, 20.0, "test_burn")
	player.call("_perform_counter")
	guard.update(0.08)
	var health: float = player.call("get_health")
	player.get("combat_state").update(0.1)
	check(float(player.call("get_health")) < health and guard.phase == "guard", "existing burn bypasses guard without purge")
	var bypass := {"id": "pelto", "counter_trigger": DATA.MODULE_DEFINITIONS.pelto_smash.counter_trigger}
	check(COUNTER.impact(player, 160, "test", "pelto", bypass, Vector3.UP) == 160, "Pelto damage bypasses guard")
	player.call("start_pelto_pull", Vector3.RIGHT, 0.9, 0.15)
	check(guard.phase == "", "bypassing pull interrupts guard")
	prepare()
	player.call("_perform_counter")
	guard.update(0.08)
	player.call("apply_stun", 0.2, "test")
	check(guard.phase == "" and not player.call("_perform_counter"), "stun interrupts and prevents activation")
	prepare()
	player.call("_perform_counter")
	guard.update(0.08)
	var impact := FULGURO.resolve_strike(target, [player], Vector3.BACK, 200, 150, 0.75, "test", "fulguro")
	check(impact == null and not player.call("is_fulguro_projected"), "counter Fulguro without residual projection")
	check(float(player.call("get_health")) == 1000, "counter Fulguro cancels direct damage")
	prepare()
	player.call("_perform_counter")
	guard.update(0.08)
	var melee := MELEE.new()
	melee.configure(target, "test")
	melee.damage_enabled = true
	melee.target_mask = 4
	melee.definition.dash_distance = [0.0, 0.0, 0.0]
	check(melee.start(Vector3.BACK), "melee starts")
	melee.update(0.15)
	check(float(player.call("get_health")) == 1000 and guard.phase == "recovery", "melee intercepted")
	melee.cancel()
	melee = null
	prepare()
	guard.surcharge_remaining = 3.0
	player.call("_begin_blaster_charge")
	check(guard.surcharge_remaining == 3.0, "charging without emission preserves reward")
	player.call("_cancel_blaster_charge")
	var attack: Dictionary = player.call("emit_passive_weapon")
	check(guard.surcharge_remaining == 0 and attack.counter_attack.surcharge, "actual emission consumes reward")
	guard.update(4.0)
	var before: float = target.call("get_health")
	var explosion_count := guard.explosions
	for i in range(6):
		player.call("passive_weapon_damage", target, 20, "player", "boost:%d" % i, attack, target.global_position + Vector3.UP * 0.85)
	check(absf(before - float(target.call("get_health")) - 130.0) < 0.01, "six primary hits plus only one 10-damage explosion including direct target")
	check(guard.explosions == explosion_count + 1, "one explosion for composed/perforating attack")
	check(float(player.call("get_health")) == 1000, "owner immune to own explosion")
	prepare()
	guard.surcharge_remaining = 3.0
	attack = player.call("emit_passive_weapon")
	var target_guard := COUNTER.ensure(target)
	target_guard.begin()
	target_guard.update(0.08)
	player.call("passive_weapon_damage", target, 20, "player", "countered", attack)
	check(float(target.call("get_health")) == 1000 and bool(attack.counter_attack.resolved), "countered boosted attack loses reward without explosion")
	prepare()
	guard.surcharge_remaining = 3.0
	attack = player.call("emit_passive_weapon")
	COUNTER.invalidate(attack.counter_attack)
	before = target.call("get_health")
	player.call("passive_weapon_damage", target, 20, "player", "wall-pellet", attack)
	check(before - float(target.call("get_health")) == 20, "wall neutralizes reward across remaining pellets")
	await test_obstacles()
	await test_inputs()
	await test_bot()
	prepare()
	player.call("_perform_counter")
	guard.surcharge_remaining = 3.0
	player.call("take_damage", 2000, "test", "death")
	check(guard.phase == "" and guard.surcharge_remaining == 0, "death clears phase and reward")
	prepare()
	check(guard.phase == "" and guard.surcharge_remaining == 0, "respawn clears phase and reward")
	if failures.is_empty():
		print("COUNTER TEST: PASS (%d checks)" % checks)
	else:
		for failure in failures:
			push_error("COUNTER: " + failure)
	quit(0 if failures.is_empty() else 1)


func test_obstacles() -> void:
	prepare()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0, 0.9, -0.8)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 2, 0.15)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	await physics_frame
	await physics_frame
	var before: float = target.call("get_health")
	COUNTER.explode(player, Vector3(0, 0.85, 0), {"id": "occluded", "radius": 2.2, "damage": 10.0})
	check(float(target.call("get_health")) == before, "explosion blocked by solid obstacle")
	wall.queue_free()
	await physics_frame
	await physics_frame
	COUNTER.explode(player, Vector3(0, 0.85, 0), {"id": "clear", "radius": 2.2, "damage": 10.0})
	check(float(target.call("get_health")) == before - 10, "clear explosion applies fixed damage")


func test_inputs() -> void:
	prepare()
	player.call("set_touch_move_vector", Vector2(0.4, 0.5))
	player.call("set_touch_aim_vector", Vector2(0.7, -0.6))
	player.call("begin_touch_fire")
	check(player.call("_perform_counter"), "module can suspend held weapon contact")
	check(player.get("_touch_aim_vector") == Vector2(0.7, -0.6), "independent right aim remains")
	check(player.get("_touch_move_vector") == Vector2(0.4, 0.5), "independent left movement remains")
	check(not player.get("_touch_fire_active") and player.get("_touch_fire_requests").is_empty(), "no deferred fire request")
	check(int(player.call("_try_begin_weapon_action", "blaster")) == 0, "weapon blocked during preparation")
	check(not player.call("begin_touch_action", "mobility"), "mobility blocked during guard action")
	guard.update(1.08)
	player.call("end_touch_fire")
	check(player.get("_touch_fire_requests").is_empty(), "original touch release cannot fire after recovery")
	player.call("reset_combat_state")
	player.get("_action_gate").try_acquire(2, "other_module", -1, true)
	check(not player.call("_perform_counter"), "cannot cancel incompatible module cast")
	player.call("reset_combat_state")
	player.get("_action_gate").try_acquire(1, "blaster", -1, true)
	check(not player.call("_perform_counter"), "same-frame accepted weapon retains priority")


func test_bot() -> void:
	prepare()
	target.call("set_duel_loadout", {"weapon": "blaster", "defensive": "counter", "passive": ""})
	var controller: Node = target.get("_training_bot")
	var equipment: Node = controller.get("_duel_equipment")
	equipment.call("tick", 0.01, 2.0, true, Vector3.ZERO, target, player, controller, {"target_charging": true, "target_aiming_at_bot": true, "line_of_fire": true}, {"module_skill": 1.0})
	var bot_guard := COUNTER.component(target)
	check(bot_guard != null and bot_guard.phase == "preparation", "equipped bot counters observable threat")
	check(float(equipment.call("get_module_cooldown", "counter")) > 7.9, "bot uses independent cooldown")
	equipment.call("cancel_action")
	check(bot_guard.phase == "", "bot interruption clears guard")
	equipment.call("reset")
	equipment.call("tick", 0.01, 3.0, true, Vector3.ZERO, target, player, controller, {"target_counter_guard": true, "line_of_fire": true}, {"module_skill": 0.0})
	check(float(equipment.get("charge_remaining")) == 0, "bot suspends upcoming weapon fire facing visible guard")
