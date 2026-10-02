extends SceneTree

const DATA := preload("res://scripts/combat_data.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const HUD := preload("res://scripts/passive_hud.gd")
const NETWORK := preload("res://scripts/network_player.gd")
var failures: Array[String] = []
var player: Node3D
var target: Node3D
var serial := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	call_deferred("_run")


func _run() -> void:
	var script: Script = load("res://scripts/player.gd")
	if script == null or not script.can_instantiate():
		push_error("Player does not compile")
		quit(1)
		return
	player = script.new()
	player.name = "Player"
	current_scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	target = load("res://scripts/target_dummy.gd").new()
	target.name = "TargetDummy"
	current_scene.add_child(target)
	target.call("set_duel_mode", true)
	target.call("set_training_bot_enabled", false)
	target.set_process(false)
	target.set_physics_process(false)
	await process_frame
	_test_volley()
	_test_offensive()
	await _test_execution()
	await _test_dash()
	_test_rejections()
	_test_absorbing_shields()
	_test_bots()
	_test_network()
	await _test_hud()
	for failure in failures:
		push_error(failure)
	print("FOUR PASSIVE COMBAT: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	current_scene.queue_free()
	await process_frame
	await process_frame
	root.get_node("GameSfx").call("clear")
	await create_timer(0.20).timeout
	quit(0 if failures.is_empty() else 1)


func setup(passive: String, weapon: String = "blaster") -> void:
	for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
		projectile.free()
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.call("set_weapon", weapon)
	player.call("set_passive", passive)
	player.set("_offensive_module_id", "javelin")
	player.global_position = Vector3.ZERO
	target.call("reset_combat_state")
	target.global_position = Vector3(0, 0, -2)
	target.get("combat_state").max_health = 10000.0
	target.get("combat_state").health = 10000.0
	player.set("aim_direction", Vector3.FORWARD)
	player.get("_counter").cancel(true)
	var guard := target.get_node_or_null("CounterGuard")
	if guard != null:
		guard.cancel(true)


func hit(attack: Dictionary, amount: float = 20.0) -> float:
	serial += 1
	return float(player.call("passive_weapon_damage", target, amount, "player", "new_passive:%d" % serial, attack))


func salvo() -> Dictionary:
	serial += 1
	return {"id": serial, "hits_by_target": {}, "credited": {}, "passive_attack": player.call("emit_passive_weapon")}


func _test_volley() -> void:
	setup("auxiliary_reactor", "shotgun")
	player.get("_module_cooldowns")["javelin"] = 5.0
	var volley := salvo()
	for pellet in 6:
		player.call("_resolve_shotgun_projectile", volley, pellet, true, target, 2.0)
	check(is_equal_approx(float(player.call("get_module_cooldown", "javelin")), 4.40), "Real Shotgun: one reactor reduction")
	setup("tracker", "shotgun")
	volley = salvo()
	for pellet in 6:
		player.call("_resolve_shotgun_projectile", volley, pellet, true, target, 2.0)
	check(int(player.get("passive_state").tracker_count) == 1, "Real Shotgun: one tracker mark; critical and burn excluded")
	for shot in 1:
		hit(player.call("emit_passive_weapon"))
	check(bool(target.get("combat_state").is_spotted()), "Real combat: second distinct attack reveals")
	check(player.call("get_tracker_locations").has(target), "Real combat: source has locator target")
	setup("alternator", "shotgun")
	player.call("register_offensive_attack", "boost")
	player.call("on_direct_offensive_hit", "boost", 10.0)
	volley = salvo()
	var before := float(target.call("get_health"))
	for pellet in 6:
		player.call("_resolve_shotgun_projectile", volley, pellet, true, target, 2.0)
	var expected := 6.0 * 28.0 * 1.30 * DATA.CRIT_MULTIPLIER
	check(absf(before - float(target.call("get_health")) - expected) < 0.01, "Real Shotgun: every direct component and critical get exactly +30%")


func _test_offensive() -> void:
	setup("alternator")
	var wave: Node3D = load("res://scripts/pelto_smash.gd").new()
	current_scene.add_child(wave)
	wave.call("configure", player, Vector3.ZERO, Vector3.FORWARD, "player", "test_pelto:1")
	wave.set_physics_process(false)
	wave.call("_apply_hit", target, false)
	check(float(player.get("passive_state").alternator_remaining) == 3.0, "Real Pelto outbound arms")
	player.get("passive_state").process(1.0)
	var attack: Dictionary = player.call("emit_passive_weapon")
	check(is_equal_approx(float(attack.multiplier), 1.30), "Real module then weapon")
	wave.call("_apply_hit", target, true)
	check(float(player.get("passive_state").alternator_remaining) == 0.0, "Real Pelto return cannot rearm consumed bonus")
	wave.queue_free()


func _test_execution() -> void:
	setup("alternator")
	player.call("register_offensive_attack", "execution")
	player.call("on_direct_offensive_hit", "execution", 20.0)
	player.set("_blaster_next_attack_ready_at", Time.get_ticks_msec() / 1000.0 + 10.0)
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.FORWARD)
	check(float(player.get("passive_state").alternator_remaining) == 3.0, "Actual refused Blaster command preserves bonus")
	player.call("reset_blaster_state")
	player.call("_begin_blaster_charge")
	player.call("_cancel_blaster_charge")
	check(float(player.get("passive_state").alternator_remaining) == 3.0, "Interrupted charge preserves bonus")
	await physics_frame
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.FORWARD)
	await create_timer(0.35).timeout
	check(float(player.get("passive_state").alternator_remaining) == 0.0, "Actual emitted Blaster consumes bonus")
	setup("alternator", "mekatana")
	player.call("register_offensive_attack", "slash")
	player.call("on_direct_offensive_hit", "slash", 20.0)
	player.call("_perform_mekatana_attack")
	player.call("_cancel_mekatana_attack")
	check(float(player.get("passive_state").alternator_remaining) == 3.0, "Cancelled melee preparation preserves bonus")
	await physics_frame
	player.call("_perform_mekatana_attack")
	player.get("_mekatana_attack").update(0.13)
	check(float(player.get("passive_state").alternator_remaining) == 0.0, "Actual slash transition consumes bonus")
	player.call("_cancel_mekatana_attack")
	setup("alternator", "longshot")
	player.call("register_offensive_attack", "longshot")
	player.call("on_direct_offensive_hit", "longshot", 20.0)
	player.call("_perform_longshot_attack")
	await create_timer(0.2).timeout
	check(float(player.get("passive_state").alternator_remaining) == 0.0 and int(player.call("get_longshot_shots_fired")) == 1, "Actual Longshot emission consumes bonus once")


func _test_dash() -> void:
	setup("inertia")
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	player.call("_cancel_dash")
	check(float(player.get("passive_state").inertia_remaining) == 0.0, "Cancelled actual dash does not arm")
	await physics_frame
	player.get("_module_cooldowns")["pyro_boots"] = 0.0
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	player.call("_update_dash", 0.3)
	check(float(player.get("passive_state").inertia_remaining) == 2.5, "Actual completed dash arms")
	var attack: Dictionary = player.call("emit_passive_weapon")
	hit(attack)
	check(float(target.get("combat_state").get_slow_percent()) == 25.0, "Actual next weapon applies configured SLOW")
	setup("inertia", "mekatana")
	player.call("_perform_mekatana_attack")
	player.get("_mekatana_attack").update(0.13)
	check(float(player.get("passive_state").inertia_remaining) == 0.0, "Attack's built-in dash excluded")
	player.call("_cancel_mekatana_attack")


func _test_rejections() -> void:
	setup("tracker")
	target.set_meta("duel_static_shield", true)
	hit(player.call("emit_passive_weapon"))
	check(int(player.get("passive_state").tracker_count) == 0, "Invulnerability rejected")
	target.remove_meta("duel_static_shield")
	var guard = load("res://scripts/counter.gd").ensure(target)
	guard.begin()
	guard.update(0.08)
	var blocked: Dictionary = player.call("emit_passive_weapon")
	check(hit(blocked) == 0.0 and int(player.get("passive_state").tracker_count) == 0, "Counter rejected")
	guard.cancel(true)
	player.set_meta("combat_team", "same")
	target.set_meta("combat_team", "same")
	check(hit(player.call("emit_passive_weapon")) == 0.0 and int(player.get("passive_state").tracker_count) == 0, "Ally rejected")
	player.remove_meta("combat_team")
	target.remove_meta("combat_team")
	setup("alternator")
	player.set_meta("combat_team", "same")
	target.set_meta("combat_team", "same")
	player.call("register_offensive_attack", "friendly_module")
	player.call("on_direct_offensive_hit", "friendly_module", 20.0, target)
	check(float(player.get("passive_state").alternator_remaining) == 0.0, "Friendly module hit cannot arm alternator")
	player.remove_meta("combat_team")
	target.remove_meta("combat_team")
	setup("tracker")
	target.call("apply_burn", 1.0, 20.0, "player:test")
	target.get("combat_state").update(1.0)
	check(int(player.get("passive_state").tracker_count) == 0, "Burn gives no tracker mark")


func _test_absorbing_shields() -> void:
	setup("auxiliary_reactor")
	target.get("combat_state").grant_shield(200.0, 5.0)
	player.get("_module_cooldowns")["javelin"] = 5.0
	check(hit(player.call("emit_passive_weapon")) == 0.0, "Absorbed direct hit causes no HP loss")
	check(is_equal_approx(float(player.call("get_module_cooldown", "javelin")), 4.40), "Absorbed direct hit triggers reactor")
	setup("tracker")
	target.get("combat_state").grant_shield(200.0, 5.0)
	for shot in 3:
		hit(player.call("emit_passive_weapon"))
	check(bool(target.get("combat_state").is_spotted()), "Three absorbed attacks reveal target")
	setup("inertia")
	target.get("combat_state").grant_shield(200.0, 5.0)
	player.get("passive_state").dash_finished(true)
	hit(player.call("emit_passive_weapon"))
	check(is_equal_approx(float(target.get("combat_state").get_slow_percent()), 25.0), "Absorbed attack applies frozen slow")
	setup("alternator")
	target.get("combat_state").grant_shield(500.0, 5.0)
	var wave: Node3D = load("res://scripts/pelto_smash.gd").new()
	current_scene.add_child(wave)
	wave.call("configure", player, Vector3.ZERO, Vector3.FORWARD, "player", "absorbed_module")
	wave.set_physics_process(false)
	wave.call("_apply_hit", target, false)
	check(float(player.get("passive_state").alternator_remaining) == 3.0, "Absorbed module primary hit arms alternator")
	wave.queue_free()


func _test_bots() -> void:
	var build := LOADOUT.defaults()
	build.offensive = "javelin"
	build.passive = "auxiliary_reactor"
	target.call("set_duel_loadout", build)
	var equipment: Node = target.get("_training_bot").get("_duel_equipment")
	check(str(equipment.get("passive_id")) == "auxiliary_reactor", "Bot accepts new passive selection")
	equipment.get("module_cooldowns")["javelin"] = 4.0
	var attack: Dictionary = target.call("emit_passive_weapon")
	for pellet in 6:
		target.call("passive_weapon_damage", player, 10.0, "duel_bot", "bot_test:%d" % pellet, attack)
	check(is_equal_approx(float(equipment.call("get_module_cooldown", "javelin")), 3.40), "Bot shares reactor deduplication")
	build.passive = "tracker"
	target.call("set_duel_loadout", build)
	for shot in 2:
		target.call("passive_weapon_damage", player, 10.0, "duel_bot", "tracker_bot:%d" % shot, target.call("emit_passive_weapon"))
	check(bool(player.get("combat_state").is_spotted()), "Bot tracker shares distinct attack threshold")
	build.passive = "alternator"
	target.call("set_duel_loadout", build)
	target.call("register_offensive_attack", "bot_module")
	target.call("on_direct_offensive_hit", "bot_module", 10.0, player)
	attack = target.call("emit_passive_weapon")
	check(is_equal_approx(float(attack.multiplier), 1.30), "Bot alternator stamps the same multiplier")
	build.passive = "inertia"
	target.call("set_duel_loadout", build)
	equipment.call("_start_dash", Vector3.RIGHT)
	equipment.call("advance_dash", target, null, 0.3)
	check(float(target.call("get_passive_runtime").inertia_remaining) == 2.5, "Bot completed dash arms same state")
	target.call("reset_combat_state")
	check(float(target.call("get_passive_runtime").inertia_remaining) == 0.0, "Bot respawn clears readiness")


func _test_network() -> void:
	var replica := NETWORK.new()
	replica.name = "Replica"
	replica.authoritative = false
	current_scene.add_child(replica)
	replica.set_physics_process(false)
	replica.set_process(false)
	replica.set_passive("auxiliary_reactor")
	replica._module_cooldowns["javelin"] = 3.0
	check(replica.passive_weapon_damage(target, 20.0, "replica", "unauthorized", {}) == 0.0, "Replica cannot decide hits")
	check(replica.get_module_cooldown("javelin") == 3.0, "Replica cannot reduce cooldown")
	replica.passive_state.restore_snapshot({"alternator": 2.0, "marks": 2, "reveal": 2.5})
	check(float(replica.get_passive_status().alternator) == 2.0, "Replica HUD receives host state")
	replica.queue_free()


func _test_hud() -> void:
	var layer := CanvasLayer.new()
	current_scene.add_child(layer)
	var bar := Control.new()
	bar.size = Vector2(568, 72)
	layer.add_child(bar)
	var controller = load("res://scripts/hud_layout_controller.gd").new()
	current_scene.add_child(controller)
	var widget := HUD.attach(bar, player, controller)
	controller.call("register", "spell_bar", bar)
	check(controller.call("ids").has("passive_slot"), "HUD customizer includes passive")
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(2340, 1080)]:
		root.content_scale_size = dimensions
		controller.call("apply")
		await process_frame
		var rect: Rect2 = controller.call("widget_rect", "passive_slot")
		check(rect.size.x > 0.0 and rect.size.y > 0.0, "Mobile HUD remains measurable")
	check(widget.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Passive HUD never captures action input")
	layer.queue_free()
	controller.queue_free()
