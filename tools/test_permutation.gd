extends SceneTree

const MARK := preload("res://scripts/permutation.gd")
const DATA := preload("res://scripts/combat_data.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const MELEE := preload("res://scripts/mekatana_attack.gd")
var _failures: Array[String] = []
var _scene: Node3D
var _cast_checks_completed := false

class Fighter extends CharacterBody3D:
	var alive := true
	var enabled := true
	var incarnation := 0
	var relocations := 0
	var cast_token := 91
	var charge := 0.77
	func is_real_dead() -> bool: return not alive
	func is_gameplay_enabled() -> bool: return enabled
	func get_visibility_epoch() -> int: return incarnation
	func on_permutation_relocated() -> void: relocations += 1
	func take_damage(_amount: float, _source: String = "", _attack: String = "") -> float: return 0.0


func _initialize() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	current_scene = _scene
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
		push_error("PERMUTATION: " + label)


func _fighter(at: Vector3) -> Fighter:
	var actor := Fighter.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	actor.add_child(collision)
	_scene.add_child(actor)
	actor.position = at
	return actor


func _mark(a: Node3D, b: Node3D, authority := true) -> Node3D:
	var mark := MARK.new()
	mark.configure(a, b, authority)
	_scene.add_child(mark)
	mark.set_physics_process(false)
	return mark


func _block(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 4.0, 8.0)
	collision.shape = shape
	body.add_child(collision)
	_scene.add_child(body)
	body.position = at + Vector3.UP * 2.0
	return body


func _run() -> void:
	_test_shield_state()
	var a := _fighter(Vector3.ZERO)
	var b := _fighter(Vector3(20.0, 0.0, 0.0))
	await physics_frame
	_check(MARK.can_activate(a, b), "inclusive 20 m activation boundary")
	b.position.x = 20.01
	_check(not MARK.can_activate(a, b), "reject beyond activation range")
	b.position.x = 18.0
	var wall := _block(Vector3(9.0, 0.0, 0.0))
	await physics_frame
	var mark := _mark(a, b)
	mark.call("_physics_process", 0.10)
	_check(a.position == Vector3.ZERO and a.relocations == 0, "exchange is delayed")
	a.position.z = 2.0
	b.position = Vector3(22.0, 0.0, 3.0)
	await physics_frame
	for _frame in range(35):
		if not mark.is_queued_for_deletion(): mark.call("_physics_process", 0.016)
	_check(a.position == Vector3(22.0, 0.0, 3.0) and b.position == Vector3(0.0, 0.0, 2.0), "homing through walls swaps current positions beyond launch range")
	_check(b.cast_token == 91 and b.charge == 0.77 and a.relocations == 1 and b.relocations == 1, "no enemy cast state is changed")
	wall.queue_free()
	await physics_frame
	a.position = Vector3.ZERO
	b.position = Vector3(2.0, 0.0, 0.0)
	mark = _mark(a, b)
	mark.call("_physics_process", 0.05)
	_check(a.position == Vector3.ZERO, "nearby targets still have minimum travel delay")
	b.position.x = 10000.0
	await physics_frame
	for _second in range(160):
		if not mark.is_queued_for_deletion(): mark.call("_physics_process", 1.0)
	_check(a.position.x == 10000.0 and b.position.x == 0.0, "mark has no maximum travel distance or timeout")
	await physics_frame
	a.position = Vector3.ZERO
	b.position = Vector3(4.0, 0.0, 0.0)
	mark = _mark(a, b, false)
	mark.call("_physics_process", 0.30)
	_check(a.position.x == 0.0 and b.position.x == 4.0, "visual replica cannot exchange positions")
	await physics_frame
	mark = _mark(a, b)
	b.incarnation += 1
	mark.call("_physics_process", 1.0)
	_check(a.position.x == 0.0 and mark.is_queued_for_deletion(), "respawn invalidates an old mark")
	await physics_frame
	mark = _mark(a, b)
	b.alive = false
	mark.call("_physics_process", 1.0)
	_check(mark.is_queued_for_deletion() and a.position.x == 0.0, "dead target is not exchanged")
	b.alive = true
	await physics_frame
	var removed := _fighter(Vector3(3.0, 0.0, 0.0))
	mark = _mark(a, removed)
	removed.queue_free()
	await physics_frame
	mark.call("_physics_process", 0.20)
	_check(mark.is_queued_for_deletion() and a.position.x == 0.0, "removed target safely clears a mark")
	await physics_frame
	wall = _block(b.position)
	await physics_frame
	_check(not MARK.exchange(a, b) and a.position.x == 0.0 and b.position.x == 4.0, "blocked endpoint rejects the whole exchange atomically")
	wall.queue_free()
	await physics_frame
	mark = _mark(a, b)
	mark.set_physics_process(true)
	paused = true
	var before := mark.position
	await create_timer(0.18, true).timeout
	_check(mark.position == before and a.position.x == 0.0, "pause freezes the mark")
	paused = false
	await create_timer(0.25).timeout
	_check(a.position.x == 4.0, "mark resumes after pause")
	# Teleport rebasing preserves a real melee cast and its combo history.
	var melee := MELEE.new()
	melee.configure(a, "test", Callable())
	melee.phase = "active"
	melee.next_step = 2
	melee.combo_remaining = 1.7
	melee._history[b.get_instance_id()] = 3
	b.position.x = 77.0
	melee.rebase_after_teleport()
	_check(melee.phase == "active" and melee.next_step == 2 and melee._history[b.get_instance_id()] == 3 and melee._previous_positions[b.get_instance_id()] == b.position, "melee sweep cache rebased without cancel or combo loss")
	melee = null
	a.queue_free()
	b.queue_free()
	await physics_frame
	if not OS.get_cmdline_user_args().has("--core-only"):
		await _test_live_controllers()
	root.get_node("GameSfx").call("clear")
	# Let the audio thread retire the stopped arrival sound before shutdown.
	await create_timer(0.12).timeout
	if _failures.is_empty():
		print("PERMUTATION TEST: PASS")
		quit(0)
	else:
		print("PERMUTATION TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _network_actor(script: Script, authority := true) -> Node3D:
	var actor := CharacterBody3D.new()
	actor.set_script(script)
	actor.set("authoritative", authority)
	actor.set("remote_controlled", true)
	_scene.add_child(actor)
	actor.call("apply_loadout", {"mobility": "permutation", "weapon": "blaster", "passive": "omnivamp"})
	actor.call("reset_combat_state")
	actor.call("set_gameplay_enabled", true)
	return actor


func _test_shield_state() -> void:
	var state := CombatState.new(100.0)
	state.grant_shield(150.0, 3.0)
	_check(state.apply_damage(70.0, "test", "shield-hit") == 0.0 and state.health == 100.0 and state.shield_health == 80.0, "shield absorbs damage before HP")
	state.apply_damage(70.0, "test", "shield-hit")
	_check(state.shield_health == 80.0, "duplicate impact cannot consume shield twice")
	_check(state.apply_damage(100.0, "test", "overflow") == 20.0 and state.health == 80.0 and state.shield_health == 0.0, "only shield overflow reaches HP")
	state.reset()
	state.grant_shield(150.0, 1.0)
	state.apply_burn(3.0, 20.0, "burn")
	state.update(0.5)
	_check(state.shield_health == 140.0 and state.health == 100.0, "burn consumes shield")
	state.update(1.0)
	_check(state.shield_health == 0.0 and state.shield_remaining == 0.0 and state.health == 90.0, "burn frame split respects exact shield expiry")
	state.grant_shield(150.0, 3.0)
	state.grant_shield(150.0, 3.0)
	_check(state.shield_health == 150.0, "shield refresh never stacks")
	state.reset()
	_check(state.shield_health == 0.0, "reset removes protection")
	state.apply_damage(100.0)
	state.grant_shield(150.0, 3.0)
	_check(state.shield_health == 0.0, "shield cannot resurrect a dead fighter")
	var duel := preload("res://scripts/duel_bot_state.gd").new(100.0)
	duel.passive.configure("baroud")
	duel.grant_shield(150.0, 3.0)
	duel.apply_damage(120.0, "test", "bot-shield")
	duel.apply_damage(120.0, "test", "bot-shield")
	_check(duel.health == 100.0 and duel.shield_health == 30.0 and not duel.passive.baroud_active, "bot shield precedes Baroud and deduplicates")
	duel.apply_damage(80.0, "test", "bot-overflow")
	_check(duel.health == 50.0 and not duel.passive.baroud_active, "bot passive sees only shield overflow")
	var replica := preload("res://scripts/network_combat_state.gd").new(100.0)
	replica.authoritative = false
	replica.grant_shield(150.0, 3.0)
	_check(replica.shield_health == 0.0, "replica cannot grant its own shield")


func _test_live_controllers() -> void:
	var script := load("res://scripts/network_player.gd") as Script
	_check(script != null and script.can_instantiate(), "network player compiles")
	if script == null or not script.can_instantiate(): return
	var a := _network_actor(script)
	var b := _network_actor(script)
	a.set("opponent", b)
	b.set("opponent", a)
	b.position.x = 12.0
	await physics_frame
	b.call("receive_action", "charge", {})
	var started: float = b.get("_blaster_charge_started_at")
	var generation: int = b.get("_action_gate").get_generation()
	a.call("_perform_mobility_module")
	_check(a.get("combat_state").shield_health == 0.0, "preparation grants no shield")
	_check(a.position.x == 0.0 and float(a.call("get_module_cooldown", "permutation")) > 11.9, "accepted cast starts cooldown but no immediate teleport")
	await create_timer(0.50).timeout
	_check(a.position.x == 12.0 and b.position.x == 0.0, "real host actors exchange")
	_check(bool(b.get("_blaster_charge_active")) and float(b.get("_blaster_charge_started_at")) == started and b.get("_action_gate").get_generation() == generation, "charged blaster and action ownership survive enemy permutation")
	_check(float(a.call("get_permutation_speed_remaining")) > 2.7 and is_equal_approx(float(a.call("get_current_move_speed")), 6.75), "caster gets 35 percent movement only")
	_check(is_equal_approx(float(b.call("get_current_move_speed")), float(DATA.MOVE_SPEED) * float(DATA.WEAPON_DEFINITIONS.blaster.charge_slow_multiplier)), "enemy retains its ordinary charge movement without receiving the boost")
	a.call("apply_slow", 1.0, 30.0, "test")
	_check(is_equal_approx(float(a.call("get_current_move_speed")), 4.725), "permutation speed respects SLOW")
	var replica := _network_actor(script, false)
	replica.set("opponent", b)
	replica.call("receive_snapshot", a.call("network_snapshot"), false)
	_check(replica.position == a.position and float(replica.call("get_permutation_speed_remaining")) > 0.0, "snapshot relocates a predicted local player even with unconfirmed inputs")
	_check(a.get("combat_state").shield_health == 150.0 and b.get("combat_state").shield_health == 0.0, "only successful caster receives shield")
	_check(replica.get("combat_state").shield_health == 150.0, "host shield pool reaches replica")
	replica.call("take_damage", 50.0, "test", "client-hit")
	_check(replica.get("combat_state").shield_health == 150.0, "replica damage cannot spend authoritative shield")
	a.set("passive_state", preload("res://scripts/passive_state.gd").new())
	a.get("passive_state").configure("baroud")
	a.get("combat_state").health = 100.0
	a.call("take_damage", 120.0, "test", "player-shield")
	a.call("take_damage", 120.0, "test", "player-shield")
	_check(a.get("combat_state").health == 100.0 and a.get("combat_state").shield_health == 30.0 and not a.get("passive_state").baroud_active, "player shield avoids premature Baroud and duplicate drain")
	a.call("take_damage", 80.0, "test", "player-overflow")
	_check(a.get("combat_state").health == 50.0, "real player overflow applied exactly once")
	a.get("combat_state").grant_shield(50.0, 0.12)
	var protected_time: float = a.get("combat_state").shield_remaining
	paused = true
	await create_timer(0.16, true).timeout
	_check(a.get("combat_state").shield_health == 50.0 and a.get("combat_state").shield_remaining == protected_time, "pause freezes real shield lifetime")
	paused = false
	await create_timer(0.16).timeout
	_check(a.get("combat_state").shield_health == 0.0, "real shield expires after pause resumes")
	_check(not bool(replica.call("receive_permutation_relocation", Vector3(90.0, 0.0, 0.0), 1)), "duplicate/older relocation cannot move replica again")
	await _test_enemy_casts(a, b)
	_check(_cast_checks_completed, "all enemy cast checks completed")
	var matcher := CanvasLayer.new()
	matcher.set_script(load("res://scripts/network_match.gd"))
	_scene.add_child(matcher)
	matcher.set("_target", a)
	var host_position := a.position
	matcher.call("_set_remote_pose", {"position": Vector3(30.0, 0.0, 0.0), "aim": Vector3.RIGHT, "relocation": 0})
	_check(a.position == host_position, "stale guest pose cannot undo host exchange")
	matcher.set("_cleanup_done", true)
	matcher.queue_free()
	a.call("reset_combat_state")
	a.position = Vector3.ZERO
	b.call("reset_combat_state")
	b.position.x = 21.0
	await physics_frame
	a.call("_perform_mobility_module")
	_check(float(a.call("get_module_cooldown", "permutation")) == 0.0 and not a.call("is_module_busy"), "out-of-range rejection consumes no cooldown or action")
	_check(a.get("combat_state").shield_health == 0.0, "rejected permutation grants no shield")
	b.position.x = 15.0
	a.call("apply_stun", 0.4, "test")
	a.call("_perform_mobility_module")
	_check(float(a.call("get_module_cooldown", "permutation")) == 0.0, "STUN blocks activation")
	a.call("reset_combat_state")
	await physics_frame
	a.call("_perform_mobility_module")
	await create_timer(0.23).timeout
	a.call("set_gameplay_enabled", false)
	await create_timer(0.40).timeout
	_check(a.position.x == 0.0 and b.position.x == 15.0 and not is_instance_valid(a.get("_permutation_mark")), "round end clears a live mark")
	_check(a.get("combat_state").shield_health == 0.0, "cancelled mark grants no shield")
	_check(LOADOUT.sanitize({"mobility": "permutation"}).mobility == "permutation", "loadout accepts and preserves the new mobility module")
	await _test_bot(a)
	for actor in [a, b, replica]:
		actor.call("set_gameplay_enabled", false)
		actor.queue_free()
	await physics_frame


func _test_enemy_casts(a: Node3D, b: Node3D) -> void:
	for entry in [
		["fulguro_punch", "blaster", "_begin_fulguro_charge", "_fulguro_phase"],
		["javelin", "blaster", "_begin_javelin_charge", "_javelin_charging"],
		["pelto_smash", "blaster", "_perform_pelto_smash", "_pelto_phase"],
		["javelin", "shotgun", "_perform_shotgun_attack", "_shotgun_attack_busy"],
		["javelin", "mekatana", "_perform_mekatana_attack", "_mekatana_action_token"],
		["javelin", "blaster", "_perform_static_shield", "_stasis_remaining"],
	]:
		a.call("reset_combat_state")
		b.call("apply_loadout", {"mobility": "pyro_boots", "weapon": entry[1], "offensive": entry[0], "defensive": "static_shield", "passive": "omnivamp"})
		b.call("reset_combat_state")
		a.position = Vector3.ZERO
		b.position = Vector3(8.0, 0.0, 0.0)
		await physics_frame
		b.call(entry[2])
		var before: Variant = b.get(entry[3])
		var generation: int = b.get("_action_gate").get_generation()
		_check(str(before) not in ["", "false", "0", "0.0", "<null>"], "%s starts before displacement" % entry[2])
		_check(MARK.exchange(a, b), "exchange during %s succeeds" % entry[2])
		_check(b.get(entry[3]) == before and b.get("_action_gate").get_generation() == generation, "%s preserves its state and token" % entry[2])
		if entry[1] == "mekatana":
			_check(b.get("_mekatana_attack").is_busy(), "enemy melee controller keeps its current phase")
		b.call("reset_combat_state")
	a.call("reset_combat_state")
	b.call("apply_loadout", {"weapon": "blaster", "mobility": "permutation", "passive": "omnivamp"})
	b.call("reset_combat_state")
	a.position = Vector3(12.0, 0.0, 0.0)
	b.position = Vector3.ZERO
	a.set("_permutation_revision", 1)
	_cast_checks_completed = true
	await physics_frame


func _test_bot(player: Node3D) -> void:
	var target_script := load("res://scripts/target_dummy.gd")
	var bot := StaticBody3D.new()
	bot.set_script(target_script)
	_scene.add_child(bot)
	var controller := bot.get_node("TrainingBot")
	var equipment: Node = controller.get("_duel_equipment")
	equipment.call("set_loadout", {"mobility": "permutation", "weapon": "blaster"})
	_check(equipment.call("get_loadout").mobility == "permutation", "bot accepts permutation")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.position = Vector3(8.0, 0.0, 0.0)
	bot.position = Vector3.ZERO
	await physics_frame
	var perception := {"visible": true, "position": player.position, "intent": "pressure", "target_charging": true}
	_check(bool(equipment.call("_consider_module_use", 4.0, 8.0, bot, player, controller, perception, {})), "bot selects a tactical permutation")
	equipment.call("_resolve_pending_module", bot, player, controller, false)
	await create_timer(0.30).timeout
	_check(bot.position.x == 8.0 and player.position.x == 0.0 and float(equipment.get("permutation_speed_remaining")) > 0.0, "bot mark keeps its target after sight loss and grants its own speed")
	_check(bot.get("combat_state").shield_health == 150.0 and player.get("combat_state").shield_health == 0.0, "bot receives its own success shield")
	bot.call("take_damage", 75.0, "test", "bot-live-shield")
	_check(bot.get("combat_state").shield_health == 75.0 and bot.get("combat_state").health == DATA.MAX_HEALTH, "live bot shield absorbs before HP")
	equipment.call("reset")
	_check(bot.get("combat_state").shield_health == 0.0, "bot equipment reset clears success shield")
	bot.call("reset_combat_state")
	bot.queue_free()
