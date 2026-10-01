extends SceneTree

## Deterministic physics fixtures exercise the shared melee rules. Integration
## cases below use the real player and its existing desktop/touch entry points.
const LOADOUT := preload("res://scripts/loadout_state.gd")
const HUD := preload("res://scripts/hud_vitals.gd")
var _failures: Array[String] = []
var _checks := 0
var _arena: TestArena
var _actor: TestActor
var _targets: Array[TestTarget] = []
var _attack: RefCounted
var _motion_total := Vector3.ZERO
var _player_steps: Array[int] = []


class TestArena extends Node3D:
	var targets: Array = []
	func get_training_targets() -> Array:
		return targets


class TestActor extends CharacterBody3D:
	var aim_direction := Vector3.FORWARD
	var _last_move_direction := Vector3.FORWARD
	var weapon_id := "mekatana"
	var hud_state: Dictionary = {}
	func get_weapon_id() -> String:
		return weapon_id
	func get_health() -> float:
		return 1000.0
	func get_max_health() -> float:
		return 1000.0
	func get_mekatana_state() -> Dictionary:
		return hud_state
	func is_real_dead() -> bool:
		return false


class TestTarget extends StaticBody3D:
	var health := 10000.0
	var rejected := false
	var after_hit: Callable
	var hits: Array[Dictionary] = []
	func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
		if rejected:
			return 0.0
		hits.append({"damage": amount, "source": source_id, "id": attack_id})
		health -= amount
		if after_hit.is_valid():
			after_hit.call()
		return amount
	func get_health() -> float:
		return health
	func is_real_dead() -> bool:
		return health <= 0.0
	func get_training_hit_radius() -> float:
		return 0.30
	func get_fulguro_hit_radius() -> float:
		return 0.30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var core := load("res://scripts/mekatana_attack.gd") as Script
	if core == null:
		push_error("MEKATANA core unavailable")
		quit(1)
		return
	_arena = TestArena.new()
	root.add_child(_arena)
	current_scene = _arena
	_actor = TestActor.new()
	_actor.collision_layer = 2
	_actor.collision_mask = 1 | 2
	_add_shape(_actor, Vector3.ZERO, 0.28)
	_arena.add_child(_actor)
	for index in range(3):
		var target := TestTarget.new()
		target.name = "Target%d" % index
		target.collision_layer = 2
		target.collision_mask = 0
		_add_shape(target, Vector3.ZERO, 0.30)
		_arena.add_child(target)
		target.add_to_group("prototype0_combat_bots")
		target.add_to_group("training_targets")
		_targets.append(target)
	_arena.targets = _targets
	_attack = core.new()
	_attack.configure(_actor, "test_mekatana", _record_motion)
	await _reset_fixture()
	await _test_combo_damage()
	await _test_misses_and_target_history()
	await _test_rejected_hit()
	await _test_inactive_target_filter()
	await _test_cleave_duplicates()
	await _test_combo_timing()
	await _test_active_window_and_direction()
	await _test_dash_lengths_and_range()
	await _test_wall_and_moving_target()
	await _test_cancel()
	await _test_reentrant_cancel()
	_test_loadout_and_hud()
	_attack.cancel()
	_attack = null
	_arena.queue_free()
	await process_frame
	_targets.clear()
	_actor = null
	_arena = null
	await _test_player_integration()
	if _failures.is_empty():
		print("MEKATANA TEST: PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("MEKATANA TEST: FAIL (%d / %d checks)" % [_failures.size(), _checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _add_shape(body: CollisionObject3D, offset: Vector3, radius: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 1.4
	shape.shape = capsule
	shape.position = offset + Vector3.UP * 0.7
	body.add_child(shape)
	return shape


func _record_motion(motion: Vector3) -> Vector3:
	_motion_total += motion
	return Vector3.ZERO


func _real_motion(motion: Vector3) -> Vector3:
	var before := _actor.global_position
	_actor.move_and_collide(motion)
	_motion_total += motion
	return _actor.global_position - before


func _sync_physics() -> void:
	await physics_frame
	await physics_frame


func _reset_fixture() -> void:
	_attack.cancel()
	_attack.configure(_actor, "test_mekatana", _record_motion)
	_actor.global_position = Vector3.ZERO
	_actor.rotation = Vector3.ZERO
	_actor.aim_direction = Vector3.FORWARD
	_motion_total = Vector3.ZERO
	for index in _targets.size():
		_targets[index].global_position = Vector3(0.0, 0.0, -1.3) if index == 0 else Vector3(10.0 + index, 0.0, 10.0)
		_targets[index].hits.clear()
		_targets[index].health = 10000.0
		_targets[index].rejected = false
		_targets[index].after_hit = Callable()
		_targets[index].collision_layer = 2
	await _sync_physics()


func _strike() -> void:
	_check(_attack.start(Vector3.FORWARD), "an available combo step starts")
	_attack.update(1.0)
	_check(not _attack.is_busy(), "large frame advances all phases without leaving a delayed slash")


func _damage(target: TestTarget, index: int) -> float:
	return float(target.hits[index].damage) if target.hits.size() > index else -1.0


func _test_combo_damage() -> void:
	await _reset_fixture()
	for _step in range(3):
		_strike()
	_check(_targets[0].hits.size() == 3, "three successful slashes hit the same target exactly three times")
	_check(is_equal_approx(_damage(_targets[0], 0), 65.0) and is_equal_approx(_damage(_targets[0], 1), 90.0) and is_equal_approx(_damage(_targets[0], 2), 160.0), "same-target full combo deals 65 + 90 + 160")
	_check(int(_attack.next_step) == 0, "third slash resets the next step")
	_strike()
	_check(is_equal_approx(_damage(_targets[0], 3), 65.0), "a fresh sequence clears all preceding hit bonuses")


func _test_misses_and_target_history() -> void:
	await _reset_fixture()
	_targets[0].global_position = Vector3(10.0, 0.0, 10.0)
	await _sync_physics()
	_strike()
	_check(int(_attack.next_step) == 1, "first slash in empty space still advances the combo")
	_targets[0].global_position = Vector3(0.0, 0.0, -1.3)
	await _sync_physics()
	_strike()
	_strike()
	_check(is_equal_approx(_damage(_targets[0], 0), 75.0) and is_equal_approx(_damage(_targets[0], 1), 125.0), "first missed, second hit: third receives only the intermediate multiplier")
	await _reset_fixture()
	_strike()
	_targets[0].global_position = Vector3(10.0, 0.0, 10.0)
	await _sync_physics()
	_strike()
	_targets[0].global_position = Vector3(0.0, 0.0, -1.3)
	await _sync_physics()
	_strike()
	_check(is_equal_approx(_damage(_targets[0], 1), 100.0), "first hit, second missed: third remains at base damage")
	await _reset_fixture()
	_strike()
	_targets[0].global_position = Vector3(10.0, 0.0, 10.0)
	_targets[1].global_position = Vector3(0.0, 0.0, -1.3)
	await _sync_physics()
	_strike()
	_strike()
	_check(is_equal_approx(_damage(_targets[1], 0), 75.0) and is_equal_approx(_damage(_targets[1], 1), 125.0), "switching target does not transfer the first target's history")


func _test_rejected_hit() -> void:
	await _reset_fixture()
	_targets[0].rejected = true
	_strike()
	_targets[0].rejected = false
	_strike()
	_strike()
	_check(_targets[0].hits.size() == 2 and is_equal_approx(_damage(_targets[0], 0), 75.0) and is_equal_approx(_damage(_targets[0], 1), 125.0), "combat-rejected overlap is not recorded as a first hit")


func _test_cleave_duplicates() -> void:
	await _reset_fixture()
	_targets[0].global_position = Vector3(-0.75, 0.0, -1.3)
	_targets[1].global_position = Vector3(0.0, 0.0, -1.3)
	_targets[2].global_position = Vector3(0.75, 0.0, -1.3)
	var duplicate := _add_shape(_targets[0], Vector3(0.08, 0.0, 0.0), 0.3)
	await _sync_physics()
	for _step in range(3):
		_check(_attack.start(Vector3.FORWARD), "wide slash begins")
		for _frame in range(60):
			_attack.update(1.0 / 60.0)
	for target in _targets:
		_check(target.hits.size() == 3 and is_equal_approx(_damage(target, 2), 160.0), "all three cleaves, including vertical third, hit one time per target despite multiple colliders")
	duplicate.queue_free()
	await _sync_physics()


func _test_inactive_target_filter() -> void:
	await _reset_fixture()
	_targets[0].collision_layer = 0
	await _sync_physics()
	_strike()
	_check(_targets[0].hits.is_empty(), "hidden scene originals with collision layer zero cannot receive melee hits")
	_targets[0].collision_layer = 4
	await _sync_physics()
	_strike()
	_check(_targets[0].hits.size() == 1 and is_equal_approx(_damage(_targets[0], 0), 75.0), "active player-layer target is eligible and hidden originals add no history")


func _test_combo_timing() -> void:
	await _reset_fixture()
	_check(_attack.start(Vector3.FORWARD), "timing first step begins")
	_attack.update(0.22)
	_check(str(_attack.phase) == "recovery" and absf(float(_attack.combo_remaining) - 2.5) < 0.002, "2.5-second continuation window opens at active phase end")
	_check(not _attack.start(Vector3.FORWARD), "recovery cannot be skipped")
	_attack.update(0.20)
	_check(absf(float(_attack.combo_remaining) - 2.3) < 0.002, "recovery consumes the continuation window")
	_attack.update(2.25)
	_check(_attack.start(Vector3.FORWARD) and int(_attack.step) == 1, "second step is accepted just before expiration")
	_attack.update(0.145)
	_check(int(_attack.step) == 1 and is_equal_approx(_damage(_targets[0], 1), 90.0), "accepted step retains its rank when preparation finishes after old deadline")
	_attack.update(1.0)
	_attack.update(2.6)
	_check(_attack.start(Vector3.FORWARD) and int(_attack.step) == 0, "waiting longer than 2.5 seconds resets to first")
	_attack.update(1.0)
	_check(is_equal_approx(_damage(_targets[0], 2), 65.0), "expired sequence clears per-target damage history")


func _test_active_window_and_direction() -> void:
	await _reset_fixture()
	_check(_attack.start(Vector3.FORWARD), "preparation begins")
	_check(_targets[0].hits.is_empty() and _attack.is_direction_locked(), "attack press causes no damage and locks aim")
	_attack.update(0.119)
	_check(_targets[0].hits.is_empty() and str(_attack.phase) == "preparation", "preparation applies no damage")
	_actor.aim_direction = Vector3.BACK
	_attack.update(0.006)
	_check(_targets[0].hits.size() == 1 and is_equal_approx(_damage(_targets[0], 0), 65.0), "active damage follows the captured aim despite later reorientation")
	_attack.update(0.20)
	var before := _targets[0].hits.size()
	_targets[1].global_position = Vector3(0.0, 0.0, -1.3)
	await _sync_physics()
	_attack.update(0.5)
	_check(_targets[0].hits.size() == before and _targets[1].hits.is_empty(), "recovery has no damage window")
	_check(absf(_motion_total.length() - 1.30) < 0.001, "doubled first dash distance is integrated only during preparation")
	_targets[0].global_position = Vector3(0.0, 0.0, 1.3)
	await _sync_physics()
	_check(_attack.start(Vector3.BACK), "next step accepts a new aim")
	_attack.update(1.0)
	_check(is_equal_approx(_damage(_targets[0], 1), 90.0), "next swing is independently reoriented")


func _test_dash_lengths_and_range() -> void:
	await _reset_fixture()
	_targets[0].global_position = Vector3.FORWARD * 4.05
	await _sync_physics()
	_attack.configure(_actor, "test_mekatana", _real_motion)
	for rank in range(3):
		_actor.global_position = Vector3.ZERO
		await _sync_physics()
		_check(_attack.start(Vector3.FORWARD) and int(_attack.step) == rank, "longer dash retains admitted combo rank")
		_attack.update(float(_attack.definition.preparation[rank]))
		_check(absf(_actor.global_position.length() - [1.30, 1.90, 2.60][rank]) < 0.001, "each unobstructed dash travels its doubled distance")
		_check(_targets[0].hits.size() == maxi(0, rank - 1), "longer preparation still does not deal damage")
		_attack.update(float(_attack.definition.active[rank]) + float(_attack.definition.recovery[rank]))
		_check(_targets[0].hits.size() == rank, "increasing dash reach brings distant target into later melee cleaves")
	_check(is_equal_approx(_damage(_targets[0], 0), 75.0) and is_equal_approx(_damage(_targets[0], 1), 125.0), "extended reach keeps per-target second-only third bonus")


func _wall(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	_arena.add_child(body)
	return body


func _test_wall_and_moving_target() -> void:
	await _reset_fixture()
	var wall := _wall(Vector3(0.0, 0.8, -0.8), Vector3(2.6, 1.6, 0.2))
	await _sync_physics()
	_attack.configure(_actor, "test_mekatana", _real_motion)
	_strike()
	_check(_actor.global_position.z > -0.5 and _targets[0].hits.is_empty(), "dash respects the wall and cleave does not damage through cover")
	wall.queue_free()
	await _reset_fixture()
	var low_wall := _wall(Vector3(0.0, 0.15, -0.8), Vector3(0.5, 0.3, 0.2))
	_targets[0].global_position = Vector3(0.8, 0.0, -1.3)
	await _sync_physics()
	_attack.configure(_actor, "test_mekatana", _real_motion)
	_strike()
	_check(_actor.global_position.z > -0.5 and _targets[0].hits.size() == 1, "being stopped during dash still permits a slash from the reached position")
	low_wall.queue_free()
	await _reset_fixture()
	_targets[0].global_position = Vector3(-4.0, 0.0, -1.3)
	await _sync_physics()
	_check(_attack.start(Vector3.FORWARD), "moving-target attack begins")
	_attack.update(0.121)
	_check(_targets[0].hits.is_empty(), "target outside the cleave is not hit at active start")
	_targets[0].global_position = Vector3(4.0, 0.0, -1.3)
	await _sync_physics()
	_attack.update(0.075)
	_check(_targets[0].hits.size() == 1, "sweep catches a moving target crossing the active cleave within one low-FPS frame")
	_attack.update(0.5)
	_check(_targets[0].hits.size() == 1, "moving target is still hit only once in the slash")


func _test_cancel() -> void:
	await _reset_fixture()
	_check(_attack.start(Vector3.FORWARD), "cancel fixture starts preparation")
	_attack.update(0.06)
	_attack.cancel()
	_attack.update(2.0)
	_check(not _attack.is_busy() and int(_attack.next_step) == 0 and _targets[0].hits.is_empty(), "interrupt cancels preparation, pending damage and the combo")
	_strike()
	_attack.cancel()
	_strike()
	_check(is_equal_approx(_damage(_targets[0], 1), 65.0), "cancel clears successful prior hit history")


func _test_loadout_and_hud() -> void:
	var build := LOADOUT.defaults()
	build.weapon = "mekatana"
	_check(LOADOUT.is_valid(build) and LOADOUT.sanitize(build).weapon == "mekatana", "loadout sanitization accepts Mekatana")
	var path := "user://mekatana_validation_loadout.cfg"
	_check(LOADOUT.save_local(build, path) and LOADOUT.load_local(path).weapon == "mekatana", "Mekatana selection survives save and reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(LOADOUT.display_name("mekatana") == "MEKATANA" and LOADOUT.stat_line("mekatana").contains("65 / 75 / 100"), "equipment description exposes central balancing values")
	var hud := HUD.new()
	hud.set_player(_actor)
	root.add_child(hud)
	_actor.hud_state = {"phase": "active", "step": 2, "next_step": 0, "combo_remaining": 0.0}
	hud.call("_refresh")
	var label := hud.get("_weapon") as Label
	_check(label.text.contains("3 / 3") and label.text.contains("SLASH") and not label.text.contains("CHARGE"), "HUD displays third swing without blaster charge or ammunition")
	_actor.hud_state = {"phase": "", "step": 0, "next_step": 1, "combo_remaining": 1.4}
	hud.call("_refresh")
	_check(label.text.contains("SUIVANT 2") and label.text.contains("1.4 s"), "HUD shows the real continuation deadline")
	hud.queue_free()


func _test_reentrant_cancel() -> void:
	await _reset_fixture()
	_targets[1].global_position = Vector3(0.7, 0.0, -1.3)
	_targets[0].after_hit = Callable(_attack, "cancel")
	await _sync_physics()
	_check(_attack.start(Vector3.FORWARD), "retaliation fixture starts the slash")
	_attack.update(1.0)
	_check(_targets[0].hits.size() == 1 and _targets[1].hits.is_empty() and not _attack.is_busy() and int(_attack.next_step) == 0, "cancellation inside a successful target hit stops the cleave before another target or deferred phase")
	_check((_attack.get("_history") as Dictionary).is_empty() and (_attack.get("_swing_hits") as Dictionary).is_empty(), "reentrant cancellation cannot resurrect hit history")
	_attack.update(1.0)
	_check(_targets[0].hits.size() == 1 and _targets[1].hits.is_empty(), "retaliation leaves no delayed damage")
	_targets[0].after_hit = Callable()


func _test_player_integration() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.get_node_or_null("Player")
	var target := scene.get_node_or_null("TargetDummy")
	var controls := scene.get_node_or_null("Interface/TouchControls")
	if player == null or target == null or controls == null or not player.has_method("get_mekatana_state"):
		_check(false, "player, dummy and touch integration API are available")
		scene.queue_free()
		await process_frame
		return
	target.call("set_training_bot_enabled", false)
	var attack: RefCounted = player.get("_mekatana_attack")
	if attack == null:
		_check(false, "real player owns the shared Mekatana timeline")
		scene.queue_free()
		await process_frame
		return
	var record_slash := func(index: int) -> void: _player_steps.append(index)
	attack.slash_started.connect(record_slash)
	var flow := scene.get_node("Interface")
	flow.call("_open_equipment")
	await process_frame
	var choices: Dictionary = flow.get("_forge_garage").get("weapon_buttons")
	_check(choices.has("mekatana"), "the real equipment selector exposes Mekatana")
	if choices.has("mekatana"):
		(choices["mekatana"] as Button).pressed.emit()
		_check(str(flow.get("loadout").weapon) == "mekatana" and LOADOUT.load_local().weapon == "mekatana", "real selection equips and persists Mekatana")
	flow.call("_open_menu")
	await _prepare_player(player, target, controls)
	await _desktop_key(true)
	await _wait_player_slashes(3)
	await _desktop_key(false)
	await create_timer(0.90).timeout
	_check(_player_steps == [0, 1, 2], "PC held attack uses the three sequential slashes and release stops future attacks")
	_check(not attack.is_busy() and not bool(player.call("is_blaster_charging")), "PC release leaves no queued slash or blaster charge")
	await _prepare_player(player, target, controls)
	controls.visible = true
	var aim_center: Vector2 = controls.call("_aim_center")
	_check(bool(controls.call("_begin_touch", 101, aim_center + Vector2(0.0, -35.0))), "existing mobile aim stick accepts the attack contact")
	await _wait_player_slashes(3)
	controls.call("_end_touch", 101)
	await create_timer(0.90).timeout
	_check(_player_steps == [0, 1, 2], "mobile held contact chains exactly three slashes and release stops the next")
	_check((player.get("_touch_fire_requests") as Array).is_empty() and not bool(player.get("_touch_attack_held")), "mobile release leaves no buffered shot or held attack")
	await _prepare_player(player, target, controls)
	var projectile_count := get_nodes_in_group("prototype0_gameplay_projectiles").size()
	for rank in range(3):
		var aim: Vector3 = player.get("aim_direction")
		target.global_position = player.global_position + aim * (float(attack.definition.dash_distance[rank]) + 1.4)
		await physics_frame
		await process_frame
		player.call("begin_touch_fire")
		await create_timer(0.04).timeout
		player.call("end_touch_fire")
		await _wait_player_slashes(rank + 1)
		await create_timer(0.85).timeout
	_check(_player_steps == [0, 1, 2] and absf(float(target.call("get_health")) - 685.0) < 0.01, "real player and combat state apply the 315-damage full combo to one moving target")
	_check(get_nodes_in_group("prototype0_gameplay_projectiles").size() == projectile_count and (target.call("get_active_effect_types") as Array).is_empty(), "real Mekatana produces no projectile or electrical gameplay status")
	await _prepare_player(player, target, controls)
	controls.visible = true
	aim_center = controls.call("_aim_center")
	controls.call("_begin_touch", 102, aim_center + Vector2(0.0, -35.0))
	await create_timer(0.04).timeout
	_check(str(player.call("get_mekatana_state").phase) == "preparation", "short mobile contact engages preparation")
	controls.call("_end_touch", 102)
	await create_timer(0.80).timeout
	_check(_player_steps == [0], "releasing during preparation does not cancel the committed swing or schedule a second")
	await _prepare_player(player, target, controls)
	controls.visible = true
	var actions: Dictionary = controls.call("_action_centers")
	controls.call("_begin_touch", 103, actions.offensive)
	controls.call("_end_touch", 103)
	await create_timer(0.55).timeout
	_check(_player_steps.is_empty(), "module button never triggers a Mekatana slash")
	for ending in ["stun", "weapon", "death", "reset", "disable"]:
		await _prepare_player(player, target, controls)
		player.call("begin_touch_fire")
		await create_timer(0.04).timeout
		_check(attack.is_busy() and str(attack.phase) == "preparation", "lifecycle case engages the real preparation: " + ending)
		match ending:
			"stun":
				player.call("apply_stun", 0.5, "mekatana_test")
			"weapon":
				player.call("set_weapon", "blaster")
			"death":
				player.call("take_damage", 5000.0, "mekatana_test", "mekatana_test_death")
			"reset":
				player.call("reset_combat_state")
			"disable":
				player.call("set_gameplay_enabled", false)
		await create_timer(0.70).timeout
		_check(_player_steps.is_empty() and not attack.is_busy() and int(attack.next_step) == 0 and float(attack.combo_remaining) <= 0.0, "lifecycle clears the slash, combo and deferred input: " + ending)
		if ending == "death":
			_check(bool(player.call("is_real_dead")), "death test uses a real lethal hit")
	await _prepare_player(player, target, controls)
	player.call("begin_touch_fire")
	await _wait_player_slashes(1)
	player.call("end_touch_fire")
	await create_timer(0.45).timeout
	_check(_player_steps == [0] and int(attack.next_step) == 1, "successful player swing retains a continuation window")
	player.call("reset_combat_state")
	_check(int(attack.next_step) == 0 and float(attack.combo_remaining) <= 0.0, "combat restart also clears successful hit sequence state")
	await _desktop_key(false)
	controls.call("reset_inputs")
	attack.slash_started.disconnect(record_slash)
	player.call("set_gameplay_enabled", false)
	root.get_node("GameSfx").call("clear")
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	current_scene = null
	scene.queue_free()
	await process_frame
	await create_timer(0.10).timeout


func _prepare_player(player: Node, target: Node, controls: Node) -> void:
	await _desktop_key(false)
	controls.call("reset_inputs")
	player.call("apply_loadout", {"weapon": "mekatana", "offensive": "modulo_drone", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.set("training_invulnerable", false)
	player.set("training_instant_cooldowns", false)
	player.global_position = Vector3.ZERO
	target.call("reset_combat_state")
	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(10.0, 0.0, 10.0)
	player.call("set_aim_input", Vector2(0.0, -1.0))
	_player_steps.clear()
	await physics_frame
	await process_frame


func _desktop_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	await physics_frame
	await process_frame


func _wait_player_slashes(count: int) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while _player_steps.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_player_steps.size() >= count, "player commits %d expected slash(es) within deadline" % count)
