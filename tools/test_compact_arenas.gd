extends SceneTree

## End-to-end arena lifecycle with real physics queries and real duel actors.
const CATALOG := preload("res://scripts/compact_arena_catalog.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const ECLIPSE := preload("res://scripts/eclipse.gd")
const PERMUTATION := preload("res://scripts/permutation.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
const PROJECTILE := preload("res://scripts/live_projectile.gd")
const LONGSHOT := preload("res://scripts/longshot_projectile.gd")
const STAGE := preload("res://scripts/compact_arena_stage.gd")
const COMPACT_MECHANISMS := preload("res://scripts/compact_arena_mechanisms.gd")
const OPEN_MECHANISMS := preload("res://scripts/open_arena_mechanisms.gd")

class GeometryFixture extends Node3D:
	var _arena_blockers: Array[StaticBody3D] = []
var failures: Array[String] = []
var scene: Node3D
var player: CharacterBody3D
var bot: StaticBody3D
var flow: CanvasLayer
var _classic_geometry: Array = []


func _initialize() -> void:
	var startup := Node.new()
	root.add_child(startup)
	current_scene = startup
	call_deferred("_run")


func _run() -> void:
	if "geometry-only" in OS.get_cmdline_user_args():
		await _run_geometry_only()
		return
	scene = load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame
	player = scene.get_node("Player")
	bot = scene.get_node("TargetDummy")
	flow = scene.get_node("Interface")
	player.set_physics_process(false)
	player.set_process(false)
	flow.set_process(false)
	await _test_garage_selection()
	_classic_geometry = _solid_signature()
	for identifier in CATALOG.IDS:
		await _test_map(str(identifier))
	await _test_retained_test_arena()
	scene.call("set_arena_variant", "unknown-map")
	_check(str(scene.get("arena_variant")) == "classic", "invalid map selection falls back to classic")
	scene.call("stop_duel")
	for failure in failures:
		push_error("COMPACT ARENAS TEST: " + failure)
	print("COMPACT ARENAS TEST: %s (%d failures; %d compact maps, retained test arena, real collisions, lifecycle, traps, rotors, reactive waves, projectile pass-through, bot navigation, minimap, modules, garage selector, classic restoration)" % ["PASS" if failures.is_empty() else "FAIL", failures.size(), CATALOG.IDS.size()])
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null:
		sfx.call("clear")
	current_scene = null
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _run_geometry_only() -> void:
	# Independently query the actual authored shapes during visual work, even
	# when another contributor is temporarily editing the garage dependency.
	for identifier in CATALOG.IDS:
		var fixture := GeometryFixture.new()
		scene = fixture
		root.add_child(scene)
		current_scene = scene
		var definition := CATALOG.definition(str(identifier))
		var stage := STAGE.new()
		stage.arena_id = str(identifier)
		scene.add_child(stage)
		stage.set_process(false)
		for body in stage.find_children("*", "StaticBody3D", true, false):
			fixture._arena_blockers.append(body)
		var open_map: bool = definition.get("mechanism", "") == "open"
		var mechanisms: Node3D = OPEN_MECHANISMS.new() if open_map else COMPACT_MECHANISMS.new()
		mechanisms.set("arena_id", str(identifier))
		scene.add_child(mechanisms)
		mechanisms.set_physics_process(false)
		await physics_frame
		await physics_frame
		_check(str(stage.get_meta("arena_id", "")) == str(identifier) and stage.has_meta("mesh_count"), str(identifier) + ": stage finishes both collision and visual construction")
		await _test_geometry(str(identifier), definition, stage)
		if open_map:
			await _test_open_geometry(str(identifier), definition, mechanisms, stage)
		current_scene = null
		scene.queue_free()
		await process_frame
		await physics_frame
	for failure in failures:
		push_error("COMPACT ARENA GEOMETRY: " + failure)
	print("COMPACT ARENA GEOMETRY: %s (%d failures; %d authored maps, real floor/cover/edge collision queries)" % ["PASS" if failures.is_empty() else "FAIL", failures.size(), CATALOG.IDS.size()])
	quit(0 if failures.is_empty() else 1)


func _test_map(identifier: String) -> void:
	var definition: Dictionary = CATALOG.definition(identifier)
	var half: Vector2 = definition.half_size
	var open_map: bool = definition.get("mechanism", "") == "open"
	_check(half.x * half.y < 29.0 * 29.0 * 0.15, identifier + ": playable floor is less than 15% of classic")
	flow.call("_select_arena", identifier)
	flow.call("_start_duel")
	var mechanisms := scene.get_node_or_null("ArenaHazards")
	var stage := scene.get_node_or_null("CompactArenaStage")
	if mechanisms == null or stage == null:
		_check(false, identifier + ": active compact stage and mechanisms exist")
		return
	mechanisms.set_physics_process(false)
	bot.call("set_training_bot_enabled", false)
	await physics_frame
	await physics_frame
	_check(str(scene.get("arena_variant")) == identifier and stage.visible, identifier + ": selection reaches the playable map")
	_check(str(stage.get_meta("arena_id", "")) == identifier and stage.has_meta("mesh_count"), identifier + ": stage finishes collision and visual construction")
	_check(player.global_position.distance_to(definition.spawns[0]) < 0.01 and bot.global_position.distance_to(definition.spawns[1]) < 0.01, identifier + ": countdown places both actors at their authored spawns")
	_check(_actor_clear(player) and _actor_clear(bot), identifier + ": both spawn capsules are outside solid geometry")
	_check(_available_repairs() == 0, identifier + ": repairs cannot be collected during countdown")
	var countdown_player := player.global_position
	var fixture_point: Vector3 = definition.spawns[0] if open_map else definition.portals[0]
	player.global_position = fixture_point
	mechanisms.call("advance", 20.0)
	_check(is_zero_approx(float(mechanisms.get("elapsed"))) and player.global_position == fixture_point, identifier + ": countdown freezes mechanisms and actor transport")
	player.global_position = countdown_player
	await _test_geometry(identifier, definition, stage)
	_test_map_awareness(identifier, definition)
	flow.call("_begin_live_round")
	bot.call("set_training_bot_enabled", false)
	bot.call("set_duel_loadout", LOADOUT.defaults())
	_check(bool(mechanisms.get("running")), identifier + ": live round starts mechanisms")
	_check(_available_repairs() == definition.repairs.size(), identifier + ": only authored repairs activate")
	var projection_motion := Vector3(0.7, 0, 0)
	var projection: Dictionary = FULGURO.sweep_static_body(bot, projection_motion, 0.45, 1.8)
	_check(not bool(projection.collided) and (projection.travel as Vector3).distance_to(projection_motion) < 0.01, identifier + ": grounded Fulguro projection keeps its unobstructed travel")
	var source_position := player.global_position
	var victim_position := bot.global_position
	_check(PERMUTATION.exchange(player, bot) and player.global_position == victim_position and bot.global_position == source_position, identifier + ": grounded actors retain the existing Permutation exchange")
	for kit in get_nodes_in_group("repair_kits"):
		if bool(kit.call("is_available")):
			_check(absf(kit.global_position.x) < half.x and absf(kit.global_position.z) < half.y, identifier + ": active repair belongs to the current arena")
	if open_map:
		await _test_open_geometry(identifier, definition, mechanisms, stage)
		if identifier == "gyre":
			await _test_rotors(mechanisms)
		else:
			await _test_resonance(definition, mechanisms)
	else:
		await _test_warning_damage(identifier, definition, mechanisms)
		await _test_portals(identifier, definition, mechanisms)
		await _test_boost_collision(identifier, definition, mechanisms)
	if identifier == "clockwork":
		await _test_shutters(mechanisms, definition)
	await _test_bot_route(identifier, definition, mechanisms)
	scene.call("stop_duel")
	var stopped: Dictionary = mechanisms.call("get_snapshot")
	player.global_position = fixture_point
	mechanisms.call("advance", 30.0)
	_check(not bool(mechanisms.get("running")) and mechanisms.call("get_snapshot") == stopped and player.global_position == fixture_point, identifier + ": stop freezes every mechanism")
	_check(_available_repairs() == 0, identifier + ": stop disables repairs")
	scene.call("prepare_round", LOADOUT.defaults())
	_check(is_zero_approx(float(mechanisms.get("elapsed"))) and (mechanisms.call("get_threats") as Array).is_empty(), identifier + ": next round clears time, warnings and damage history")
	await _test_classic_restoration(identifier, stage)


func _test_geometry(identifier: String, definition: Dictionary, stage: Node) -> void:
	var half: Vector2 = definition.half_size
	for point in definition.spawns + definition.portals + definition.repairs + definition.boosts:
		var hit := _ray(point + Vector3(0, 0.5, 0), point - Vector3(0, 0.5, 0))
		_check(not hit.is_empty() and absf(float(hit.get("position", Vector3.INF).y)) < 0.025, identifier + ": functional points have a colliding floor with top at zero")
		if not hit.is_empty():
			_check(stage.is_ancestor_of(hit.collider), identifier + ": only current floor collides below functional points")
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var extent: float = half.x if axis.x != 0 else half.y
		var hit := _ray(axis * (extent - 2.0) + Vector3.UP, axis * (extent + 2.0) + Vector3.UP)
		_check(not hit.is_empty() and stage.is_ancestor_of(hit.get("collider")), identifier + ": cardinal boundary is a genuine current-map collision")
	for cover in definition.covers:
		var center: Vector3 = cover.position
		var hit := _ray(center + Vector3.UP * 3.0, center)
		_check(not hit.is_empty() and float(hit.get("position", Vector3.ZERO).y) > 1.0 and stage.is_ancestor_of(hit.get("collider")), identifier + ": authored cover blocks projectiles and bodies")
	var old_floor := _ray(Vector3(20, 2, 20), Vector3(20, -1, 20))
	_check(old_floor.is_empty(), identifier + ": classic floor has no stale collision outside the small map")


func _test_open_geometry(identifier: String, definition: Dictionary, mechanisms: Node, stage: Node) -> void:
	for fixture in ["portals", "boosts", "covers", "repairs", "hazards"]:
		_check((definition[fixture] as Array).is_empty(), identifier + ": no authored " + fixture)
	_check(get_nodes_in_group("repair_kits").is_empty(), identifier + ": neither current nor detached old repair kits remain collectible")
	var interior_blockers := 0
	for body in scene.get("_arena_blockers"):
		if not body.get_meta("invisible_safety_limit", false):
			interior_blockers += 1
	_check(interior_blockers == 0, identifier + ": bot receives no invented interior cover")
	var half: Vector2 = definition.half_size
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var cut_corner := Vector3(corner.x * (half.x - 0.6), 0, corner.y * (half.y - 0.6))
		_check(not _has_floor(cut_corner), identifier + ": clipped octagonal corner has no supporting floor")
	var outline := CATALOG.footprint(identifier)
	for index in range(outline.size()):
		var midpoint := (outline[index] + outline[(index + 1) % outline.size()]) * 0.5
		var outward := midpoint.normalized()
		var near_edge := midpoint - outward
		var beyond_edge := midpoint + outward
		var boundary := _ray(Vector3(near_edge.x, 1, near_edge.y), Vector3(beyond_edge.x, 1, beyond_edge.y))
		_check(not boundary.is_empty() and stage.is_ancestor_of(boundary.get("collider")), identifier + ": each octagonal edge stops a real ray")
	for z in [-5.0, 0.0, 5.0]:
		_check(_ray(Vector3(-6, 1, z), Vector3(6, 1, z)).is_empty(), identifier + ": combat lanes remain open without physical cover")
	_check((mechanisms.call("get_threats") as Array).is_empty(), identifier + ": fresh open arena has no stale old trap threat")


func _test_rotors(mechanisms: Node) -> void:
	_reset_live(mechanisms)
	player.global_position = Vector3(2, 0, 0)
	bot.global_position = Vector3(6, 0, 0)
	player.velocity = Vector3(0.7, 0, 0.2)
	var velocity_before := player.velocity
	var player_life := float(player.call("get_health"))
	var bot_life := float(bot.call("get_health"))
	mechanisms.call("advance", 3.9)
	_check(player.global_position == Vector3(2, 0, 0) and bot.global_position == Vector3(6, 0, 0), "gyre: grace period does not move either fighter")
	mechanisms.call("advance", 1.4)
	mechanisms.call("advance", 1.0)
	var snapshot: Dictionary = mechanisms.call("get_snapshot")
	_check(player.global_position.z * bot.global_position.z < 0.0 and absf(player.global_position.z) > 0.2 and absf(bot.global_position.z) > 0.4, "gyre: actual inner and outer fighters travel in opposite directions")
	_check(absf(Vector2(player.global_position.x, player.global_position.z).length() - 2.0) < 0.01 and absf(Vector2(bot.global_position.x, bot.global_position.z).length() - 6.0) < 0.01, "gyre: opposing transport preserves each orbit radius")
	_check(player.velocity == velocity_before and float(player.call("get_health")) == player_life and float(bot.call("get_health")) == bot_life, "gyre: transport preserves movement ownership and both fighters' health")
	var action_position := player.global_position
	player.set("_dash_active", true)
	mechanisms.call("advance", 0.3)
	_check(player.global_position == action_position, "gyre: an active dash retains exclusive ownership of fighter movement")
	player.set("_dash_active", false)
	snapshot = mechanisms.call("get_snapshot")
	var positions := [player.global_position, bot.global_position]
	paused = true
	mechanisms.call("advance", 10.0)
	_check(mechanisms.call("get_snapshot") == snapshot and player.global_position == positions[0] and bot.global_position == positions[1], "gyre: pause freezes visible ring angles, clocks and fighter transport")
	paused = false
	mechanisms.call("advance", 18.5)
	snapshot = mechanisms.call("get_snapshot")
	_check(float(snapshot.inner_rate) < 0.0 and float(snapshot.outer_rate) > 0.0, "gyre: timed reversal eventually swaps both rotation directions")
	var low_rate := _rotor_position_at_rate(mechanisms, 30)
	var high_rate := _rotor_position_at_rate(mechanisms, 120)
	_check(low_rate.distance_to(high_rate) < 0.015, "gyre: physical transport agrees at 30 and 120 updates per second")
	_reset_live(mechanisms)
	player.global_position = Vector3(2, 0, 0)
	bot.global_position = Vector3(7, 0, 2)
	var obstacle := _obstacle("RotorSafetyFixture", Vector3(2, 0.9, -1), Vector3(2, 1.8, 0.3))
	await physics_frame
	await physics_frame
	mechanisms.call("advance", 4.0)
	mechanisms.call("advance", 4.0)
	_check(_actor_clear(player) and player.global_position.z > -0.6 and player.global_position.z < -0.1, "gyre: rotating floor sweeps the fighter safely against a real obstacle")
	obstacle.queue_free()
	await process_frame
	await physics_frame
	# Real player movement runs between external transport steps.
	_reset_live(mechanisms)
	player.global_position = Vector3(2, 0, 0)
	bot.global_position = Vector3(-7, 0, -4)
	player.call("set_touch_move_vector", Vector2.ZERO)
	player.velocity = Vector3.ZERO
	mechanisms.call("advance", 5.3)
	var before_movement := player.global_position
	for frame in range(45):
		player.call("_update_movement", 1.0 / 60.0)
		mechanisms.call("advance", 1.0 / 60.0)
	_check(player.global_position.distance_to(before_movement) > 0.2 and _actor_clear(player), "gyre: normal grounded player physics does not erase the floor's transport")
	player.velocity = Vector3.ZERO


func _rotor_position_at_rate(mechanisms: Node, updates: int) -> Vector3:
	_reset_live(mechanisms)
	player.global_position = Vector3(2, 0, 0)
	bot.global_position = Vector3(-7, 0, -4)
	for frame in range(updates * 7):
		mechanisms.call("advance", 1.0 / float(updates))
	return player.global_position


func _test_resonance(definition: Dictionary, mechanisms: Node) -> void:
	_reset_live(mechanisms)
	var source: Vector3 = definition.resonators[0]
	player.global_position = source + Vector3(2, 0, 0)
	bot.global_position = source + Vector3(0, 0, 2)
	var player_before := player.global_position
	var bot_before := bot.global_position
	var player_life := float(player.call("get_health"))
	var bot_life := float(bot.call("get_health"))
	mechanisms.call("advance", 3.9)
	_check(not bool(mechanisms.call("trigger_resonator", 1)), "resonance: countdown grace rejects premature crystal shots")
	mechanisms.call("advance", 0.2)
	mechanisms.call("advance", 0.5)
	var snapshot: Dictionary = mechanisms.call("get_snapshot")
	_check((snapshot.waves as Array).size() == 1 and str(snapshot.waves[0].phase) == "warning" and player.global_position == player_before and bot.global_position == bot_before, "resonance: periodic crystal clearly warns before applying pressure")
	paused = true
	mechanisms.call("advance", 5.0)
	_check(mechanisms.call("get_snapshot") == snapshot and not bool(mechanisms.call("trigger_resonator", 1)), "resonance: pause freezes waves and rejects crystal activation")
	paused = false
	for frame in range(180):
		mechanisms.call("advance", 1.0 / 60.0)
	snapshot = mechanisms.call("get_snapshot")
	_check(player.global_position.distance_to(player_before) > 1.1 and bot.global_position.distance_to(bot_before) > 1.1, "resonance: expanding annulus really pushes both fighters outward")
	_check(float(player.call("get_health")) == player_life and float(bot.call("get_health")) == bot_life and int(snapshot.wave_hits) == 2, "resonance: wave is neutral, causes no damage and hits each fighter once")
	_check(_actor_clear(player) and _actor_clear(bot) and _has_floor(player.global_position) and _has_floor(bot.global_position), "resonance: pressure movement stays grounded outside solid geometry")
	await _test_crystal_projectile(definition, mechanisms, false)
	await _test_crystal_projectile(definition, mechanisms, true)
	await _test_pressure_collision(definition, mechanisms)
	_reset_live(mechanisms)
	mechanisms.call("advance", 4.1)
	_check(bool(mechanisms.call("trigger_resonator", 1)) and not bool(mechanisms.call("trigger_resonator", 1)), "resonance: a shot triggers a crystal once during its cooldown")
	_check(bool(mechanisms.call("trigger_resonator", 2)) and bool(mechanisms.call("trigger_resonator", 3)) and (mechanisms.call("get_snapshot") as Dictionary).waves.size() <= 4, "resonance: simultaneous crystal reactions remain bounded")
	mechanisms.call("reset_round")
	snapshot = mechanisms.call("get_snapshot")
	_check((snapshot.waves as Array).is_empty() and int(snapshot.wave_hits) == 0 and int(snapshot.shot_triggers) == 0, "resonance: round reset removes active waves, impulses and shot history")


func _test_crystal_projectile(definition: Dictionary, mechanisms: Node, longshot: bool) -> void:
	_reset_live(mechanisms)
	mechanisms.call("advance", 4.1)
	var source: Vector3 = definition.resonators[1]
	player.global_position = source + Vector3(-2, 0, 0)
	bot.global_position = source + Vector3(2, 0, 0)
	var receiver: Area3D
	for area in mechanisms.find_children("*", "Area3D", true, false):
		if area.get_meta("non_blocking_projectile_receiver", false) and Vector2(area.global_position.x - source.x, area.global_position.z - source.z).length() < 0.01:
			receiver = area
			break
	_check(receiver != null and not receiver.has_method("get_health") and not receiver.has_method("get_max_health") and not receiver.is_in_group("combatants"), "resonance: reactive crystal is a sensor without a fighter health identity")
	if receiver == null:
		return
	await physics_frame
	await physics_frame
	var before: Dictionary = mechanisms.call("get_snapshot")
	var player_life := float(player.call("get_health"))
	var bot_life := float(bot.call("get_health"))
	var shot: Node3D = LONGSHOT.new() if longshot else PROJECTILE.new()
	scene.add_child(shot)
	shot.global_position = source + Vector3(-2, 0.93, 0)
	shot.set_physics_process(false)
	var excluded: Array[RID] = [player.get_rid()]
	if longshot:
		shot.call("configure", Vector3.RIGHT, 80.0, 8.0, 1 | 2 | 4, excluded, 0.075)
	else:
		shot.call("configure", Vector3.RIGHT, 80.0, 8.0, 1 | 2 | 4, excluded)
	var result := {"hit": {}}
	shot.connect("finished", func(hit: Dictionary, _distance: float) -> void: result.hit = hit)
	shot.call("_physics_process", 0.1)
	var after: Dictionary = mechanisms.call("get_snapshot")
	_check(result.hit.get("collider") == bot, "resonance: %s passes through a crystal and reaches the real opponent behind it" % ("LONGSHOT sphere" if longshot else "ordinary projectile"))
	_check(int(after.shot_triggers) == int(before.shot_triggers) + 1, "resonance: actual projectile contact triggers exactly one crystal reaction")
	_check(float(player.call("get_health")) == player_life and float(bot.call("get_health")) == bot_life, "resonance: crystal contact alone grants no damage, healing or life-steal")
	await process_frame


func _test_pressure_collision(definition: Dictionary, mechanisms: Node) -> void:
	_reset_live(mechanisms)
	var source: Vector3 = definition.resonators[0]
	player.global_position = source + Vector3(2, 0, 0)
	bot.global_position = definition.spawns[1]
	var original := player.global_position
	var obstacle := _obstacle("WaveSafetyFixture", source + Vector3(2.8, 0.9, 0), Vector3(0.3, 1.8, 2))
	await physics_frame
	await physics_frame
	mechanisms.call("advance", 4.0)
	mechanisms.call("advance", 3.0)
	var travel := player.global_position.x - original.x
	_check(travel > 0.02 and travel < 0.5 and _actor_clear(player), "resonance: actual pressure impulse stops at a thin solid instead of crossing it")
	obstacle.queue_free()
	await process_frame
	await physics_frame
	_reset_live(mechanisms)
	player.global_position = Vector3(8.1, 0, 6.1)
	bot.global_position = definition.spawns[0]
	mechanisms.call("advance", 4.1)
	mechanisms.call("trigger_resonator", 1)
	mechanisms.call("advance", 2.5)
	_check(_actor_clear(player) and _has_floor(player.global_position) and Geometry2D.is_point_in_polygon(Vector2(player.global_position.x, player.global_position.z), CATALOG.footprint("resonance")), "resonance: outward pressure stays inside a clipped corner with real capsule clearance")


func _obstacle(label: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	obstacle.name = label
	obstacle.collision_layer = 1
	obstacle.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	obstacle.add_child(shape)
	scene.add_child(obstacle)
	return obstacle


func _test_retained_test_arena() -> void:
	scene.call("set_arena_variant", "test")
	scene.call("prepare_round", LOADOUT.defaults())
	await process_frame
	await physics_frame
	var terrain := scene.get_node_or_null("TestArena")
	_check(terrain != null and not scene.has_node("CompactArenaStage") and not scene.has_meta("arena_floor_rid") and not scene.has_meta("arena_outline"), "test arena: switching removes compact solids and compact support metadata")
	_check(scene.call("get_arena_half_size") == Vector2(17.4, 14.5), "test arena: brother's rectangular gameplay bounds remain intact")
	var tracker := scene.get_node("SightTracker")
	tracker.call("_cache_obstacles")
	_check(not (tracker.get("_walkable_polygons") as Array).is_empty() and not (tracker.get("_ramp_markers") as Array).is_empty(), "test arena: brother's elevated decks and uphill minimap arrows remain cached")
	if terrain != null:
		player.global_position = Vector3(-3.5, 2.4, 0.6)
		_check(ECLIPSE.fits(player, Vector3(-3.5, 2.4, 1.6)), "test arena: elevated Eclipse support remains traversable after compact maps")
		scene.call("set_arena_variant", "classic")
		await physics_frame
		_check(not terrain.visible and not terrain.is_inside_tree() and terrain.get_node("WestDeckCover").collision_layer == 0 and terrain.get_node("EastDeckCover").collision_layer == 0 and get_nodes_in_group("repair_kits").size() == 4, "test arena: inactive decks retain the old hidden/disabled API and leave the classic repair groups")
		scene.call("set_arena_variant", "hazards")
		_check(not terrain.visible and not terrain.is_inside_tree(), "test arena: original hazard court also keeps the test stage retired")
		scene.call("set_arena_variant", "test")
		_check(terrain.visible and terrain.is_inside_tree() and terrain.get_node("WestDeckCover").collision_layer == 1 and terrain.get_node("EastDeckCover").collision_layer == 1, "test arena: returning restores the same deck collision and appearance")
	scene.call("set_arena_variant", "resonance")
	scene.call("prepare_round", LOADOUT.defaults())
	await process_frame
	await physics_frame
	_check(not scene.has_node("TestArena") and _available_repairs() == 0 and get_nodes_in_group("bush_placeholder").is_empty(), "test arena: returning to an open compact map leaves no repair, bush or platform collision")
	_check(_has_floor(Vector3(-3.5, 0, 0.6)) and _ray(Vector3(-3.5, 3, 0.6), Vector3(-3.5, 1, 0.6)).is_empty(), "test arena: former elevated platform is replaced by the actual flat compact floor")
	scene.call("set_arena_variant", "classic")


func _test_garage_selection() -> void:
	flow.call("_open_equipment")
	await process_frame
	await process_frame
	var garage := flow.get("_forge_garage") as Control
	_check(garage != null and garage.is_visible_in_tree(), "garage: equipment opens the actual forge UI")
	if garage == null:
		return
	var selector := garage.get("_arena_selector") as OptionButton
	_check(selector != null and selector.is_visible_in_tree() and selector.item_count == 8 and selector.item_count == CATALOG.options().size(), "garage: visible arena selector contains all eight choices")
	if selector == null:
		return
	var navigation: Dictionary = garage.get("_nav")
	for button in navigation.values():
		_check(not selector.get_global_rect().intersects((button as Control).get_global_rect()), "garage: arena selector does not overlap " + str(button.text))
	var build_title := garage.get("_header_name") as Control
	_check(build_title != null and not selector.get_global_rect().intersects(build_title.get_global_rect()), "garage: arena selector %s does not overlap the build name %s" % [selector.get_global_rect(), build_title.get_global_rect() if build_title != null else Rect2()])
	for identifier in ["hazards", "test"] + CATALOG.IDS:
		var found := false
		for index in range(selector.item_count):
			if str(selector.get_item_metadata(index)) != str(identifier):
				continue
			found = true
			selector.item_selected.emit(index)
			_check(str(scene.get("arena_variant")) == identifier and str(flow.get("_arena_variant")) == identifier and str(selector.get_item_metadata(selector.selected)) == identifier, "garage: choosing " + str(identifier) + " reaches the matching scene and flow")
			break
		_check(found, "garage: retained or compact choice exists for " + str(identifier))
	selector.item_selected.emit(0)
	_check(str(scene.get("arena_variant")) == "classic", "garage: original classic choice remains usable")
	flow.call("_open_menu")
	await process_frame
	await physics_frame


func _test_warning_damage(identifier: String, definition: Dictionary, mechanisms: Node) -> void:
	_reset_live(mechanisms)
	var first: Dictionary = definition.hazards[0]
	player.global_position = first.position
	bot.global_position = first.position + Vector3(0.1, 0, 0.1)
	var player_before := float(player.call("get_health"))
	var bot_before := float(bot.call("get_health"))
	for frame in range(42):
		mechanisms.call("advance", 0.1)
		if not (mechanisms.call("get_threats") as Array).is_empty():
			break
	_check(not (mechanisms.call("get_threats") as Array).is_empty(), identifier + ": first trap announces danger after grace")
	mechanisms.call("advance", float(definition.warning) * 0.45)
	_check(float(player.call("get_health")) == player_before and float(bot.call("get_health")) == bot_before, identifier + ": warning harms neither actor")
	var snapshot: Dictionary = mechanisms.call("get_snapshot")
	paused = true
	mechanisms.call("advance", 5.0)
	await process_frame
	_check(mechanisms.call("get_snapshot") == snapshot, identifier + ": pause freezes hazard clocks and shutters")
	paused = false
	mechanisms.call("advance", float(definition.warning) * 0.60)
	var player_damage := player_before - float(player.call("get_health"))
	var bot_damage := bot_before - float(bot.call("get_health"))
	_check(is_equal_approx(player_damage, float(first.damage)) and is_equal_approx(bot_damage, float(first.damage)), identifier + ": active pulse damages player and bot equally")
	mechanisms.call("advance", 0.1)
	mechanisms.call("advance", 0.1)
	_check(is_equal_approx(player_before - float(player.call("get_health")), player_damage) and is_equal_approx(bot_before - float(bot.call("get_health")), bot_damage), identifier + ": a pulse cannot hit either actor twice")
	mechanisms.call("advance", float(definition.active) + 0.1)
	_check(str((mechanisms.call("get_snapshot") as Dictionary).phases[0]) == "idle", identifier + ": warning and pulse fully expire")


func _test_portals(identifier: String, definition: Dictionary, mechanisms: Node) -> void:
	for actor in [player, bot]:
		_reset_live(mechanisms)
		var other: Node3D = bot if actor == player else player
		other.global_position = definition.spawns[1] if actor == player else definition.spawns[0]
		actor.global_position = definition.portals[0]
		await physics_frame
		var before := float(actor.call("get_health"))
		mechanisms.call("advance", 0.02)
		var destination: Vector3 = actor.global_position
		_check(destination.distance_to(definition.portals[1]) < 2.5 and destination.distance_to(definition.portals[0]) > 8.0, identifier + ": paired portal transports " + str(actor.name))
		_check(_actor_clear(actor) and _has_floor(destination), identifier + ": portal exit is grounded and outside solid geometry")
		_check(float(actor.call("get_health")) == before, identifier + ": teleport preserves life")
		mechanisms.call("advance", 0.2)
		mechanisms.call("advance", 1.8)
		_check(actor.global_position.distance_to(destination) < 0.01, identifier + ": safe exit avoids an automatic return after cooldown")
		actor.global_position = definition.portals[0]
		var paused_at: Vector3 = actor.global_position
		paused = true
		mechanisms.call("advance", 2.0)
		_check(actor.global_position == paused_at, identifier + ": pause prevents teleportation")
		paused = false


func _test_boost_collision(identifier: String, definition: Dictionary, mechanisms: Node) -> void:
	_reset_live(mechanisms)
	var pad: Vector3 = definition.boosts[0]
	var obstacle := StaticBody3D.new()
	obstacle.name = "BoostSafetyFixture"
	obstacle.collision_layer = 1
	obstacle.position = pad + Vector3(0, 0.9, -2.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 1.8, 0.5)
	shape.shape = box
	obstacle.add_child(shape)
	scene.add_child(obstacle)
	player.global_position = pad
	bot.global_position = definition.spawns[1]
	await physics_frame
	await physics_frame
	var life := float(player.call("get_health"))
	mechanisms.call("advance", 0.02)
	for frame in range(20):
		mechanisms.call("advance", 0.02)
	var travelled := player.global_position.distance_to(pad)
	_check(travelled > 0.6 and travelled < 2.4 and _actor_clear(player), identifier + ": momentum rail moves the actor and sweeps against obstacles")
	_check(float(player.call("get_health")) == life, identifier + ": momentum rail preserves life")
	obstacle.queue_free()
	await process_frame
	await physics_frame


func _test_bot_route(identifier: String, definition: Dictionary, mechanisms: Node) -> void:
	_reset_live(mechanisms)
	mechanisms.call("stop_round")
	player.global_position = definition.spawns[0]
	bot.global_position = definition.spawns[1]
	await physics_frame
	var controller := bot.get_node("TrainingBot")
	var navigation = controller.get("_navigation")
	navigation.call("invalidate")
	var half: Vector2 = definition.half_size
	var stayed_inside := true
	var always_clear := true
	for frame in range(500):
		var time := float(frame) / 60.0
		controller.set("_elapsed", time)
		var direction: Vector3 = navigation.call("get_direction", bot, player.global_position, time, float(controller.get("duel_arena_limit")))
		controller.set("_move_velocity", direction * 5.0)
		controller.call("_move_bot", bot, 1.0 / 60.0)
		stayed_inside = stayed_inside and absf(bot.global_position.x) < half.x and absf(bot.global_position.z) < half.y
		always_clear = always_clear and _actor_clear(bot)
		if bot.global_position.distance_to(player.global_position) < 1.4:
			break
	_check(bot.global_position.distance_to(player.global_position) < 2.0 and stayed_inside and always_clear, identifier + ": actual bot route crosses the arena without leaving it or clipping cover")


func _test_shutters(mechanisms: Node, definition: Dictionary) -> void:
	_reset_live(mechanisms)
	var shutters: Array = mechanisms.get("_shutters")
	_check(shutters.size() == 2, "clockwork: two rhythmic gates exist")
	if shutters.is_empty():
		return
	var gate: Dictionary = shutters[0]
	player.global_position = gate.position
	bot.global_position = definition.spawns[1]
	mechanisms.call("advance", 4.0)
	mechanisms.call("advance", 1.7)
	await physics_frame
	_check(str(gate.phase) == "warning" and bool(gate.collision.disabled) and _actor_clear(player), "clockwork: occupied gate keeps warning without crushing the player")
	player.global_position = definition.spawns[0]
	mechanisms.call("advance", 0.1)
	var leaf := gate.leaves[0] as Node3D
	var paused_position := leaf.position
	paused = true
	mechanisms.call("advance", 0.5)
	_check(leaf.position == paused_position, "clockwork: pause freezes the visible gate slide")
	paused = false
	for frame in range(4):
		mechanisms.call("advance", 0.1)
	await physics_frame
	await physics_frame
	var at: Vector3 = gate.position
	_check(not bool(gate.collision.disabled) and not _ray(at + Vector3(0, 1, -1), at + Vector3(0, 1, 1)).is_empty(), "clockwork: empty gate finishes its slide and physically blocks passage")
	mechanisms.call("stop_round")
	await physics_frame
	await physics_frame
	_check(bool(gate.collision.disabled) and _ray(at + Vector3(0, 1, -1), at + Vector3(0, 1, 1)).is_empty(), "clockwork: stop immediately removes gate collision")


func _test_classic_restoration(identifier: String, former_stage: Node) -> void:
	scene.call("set_arena_variant", "classic")
	scene.call("prepare_round", LOADOUT.defaults())
	await process_frame
	await physics_frame
	await physics_frame
	_check(_solid_signature() == _classic_geometry, identifier + ": classic restores every original solid and removes all compact solids")
	_check(not is_instance_valid(former_stage) or not former_stage.is_inside_tree(), identifier + ": classic removes the former art stage")
	var hazards := scene.get_node("ArenaHazards")
	scene.call("activate_round")
	bot.call("set_training_bot_enabled", false)
	hazards.set_physics_process(false)
	hazards.call("advance", 30.0)
	_check(not bool(hazards.get("running")) and (hazards.call("get_threats") as Array).is_empty(), identifier + ": restored classic remains free of traps")
	_check(_available_repairs() == 4, identifier + ": classic restores its four repair kits")
	_check(player.position.distance_to(Vector3(-3.5, 0, 17)) < 0.01 and bot.position.distance_to(Vector3(3.5, 0, 15.5)) < 0.01, identifier + ": classic restores original duel spawns")
	scene.call("stop_duel")
	scene.call("set_arena_variant", "hazards")
	scene.call("prepare_round", LOADOUT.defaults())
	scene.call("activate_round")
	bot.call("set_training_bot_enabled", false)
	hazards = scene.get_node("ArenaHazards")
	hazards.set_physics_process(false)
	_check(bool(hazards.get("running")) and (hazards.get("_fixtures") as Array).size() == 6, identifier + ": original trapped court restores its six fixtures")
	hazards.call("advance", 12.1)
	_check(not (hazards.call("get_threats") as Array).is_empty(), identifier + ": original trapped court still starts its warnings")
	scene.call("stop_duel")
	scene.call("set_arena_variant", "classic")


func _reset_live(mechanisms: Node) -> void:
	scene.call("prepare_round", LOADOUT.defaults())
	scene.call("activate_round")
	bot.call("set_training_bot_enabled", false)
	bot.call("set_duel_loadout", LOADOUT.defaults())
	bot.call("reset_combat_state")
	mechanisms.set_physics_process(false)


func _test_map_awareness(identifier: String, definition: Dictionary) -> void:
	var half: Vector2 = definition.half_size
	var tracker := scene.get_node("SightTracker")
	var dimensions := Vector2(182, 182)
	var north_west: Vector2 = tracker.call("_map_point", Vector3(-half.x, 0, -half.y), dimensions)
	var south_east: Vector2 = tracker.call("_map_point", Vector3(half.x, 0, half.y), dimensions)
	var map_rect: Rect2 = tracker.call("_map_rect", dimensions)
	_check(north_west.distance_to(map_rect.position) < 0.01 and south_east.distance_to(map_rect.end) < 0.01, identifier + ": minimap scales to actual map bounds with uniform world scale")
	_check((tracker.get("_obstacle_polygons") as Array).size() >= definition.covers.size(), identifier + ": minimap caches the current cover geometry")
	var original := player.global_position
	player.global_position = Vector3(half.x - 2.0, 0, 0)
	var outside := Vector3(half.x + 1.2, 0, 0)
	_check(not ECLIPSE.fits(player, outside), identifier + ": Eclipse cannot bypass the small-map boundary")
	_check(ECLIPSE.fits(player, player.global_position), identifier + ": legal Eclipse endpoints remain available")
	if definition.get("mechanism", "") == "open":
		var outline: PackedVector2Array = scene.get_meta("arena_outline", PackedVector2Array())
		_check(outline == CATALOG.footprint(identifier) and outline.size() == 8, identifier + ": scene exposes the actual octagonal footprint")
		player.global_position = Vector3(half.x - 2.5, 0, half.y - 2.5)
		_check(not ECLIPSE.fits(player, Vector3(half.x - 0.8, 0, half.y - 0.8)), identifier + ": Eclipse rejects clipped corners inside the rectangular bounds")
		var edge := (outline[1] + outline[2]) * 0.5
		var inward := -edge.normalized()
		var near_edge := edge + inward * 0.1
		var origin := edge + inward * 2.0
		player.global_position = Vector3(origin.x, 0, origin.y)
		_check(not ECLIPSE.fits(player, Vector3(near_edge.x, 0, near_edge.y)), identifier + ": Eclipse reserves the capsule radius along diagonal edges")
	player.global_position = original


func _actor_clear(actor: CollisionObject3D) -> bool:
	for child in actor.get_children():
		if child is CollisionShape3D and child.shape != null and not child.disabled:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = child.global_transform
			query.collision_mask = 1 | 8
			var exclusions: Array[RID] = [actor.get_rid()]
			# The grounded capsule touches the floor; check horizontal penetration.
			var floor := scene.get_node_or_null("CompactArenaStage/CompactFloor") as CollisionObject3D
			if floor != null:
				exclusions.append(floor.get_rid())
			query.exclude = exclusions
			return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	return false


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func _has_floor(point: Vector3) -> bool:
	var hit := _ray(point + Vector3(0, 0.5, 0), point - Vector3(0, 0.5, 0))
	return not hit.is_empty() and absf(float(hit.position.y)) < 0.025


func _available_repairs() -> int:
	var count := 0
	for kit in get_nodes_in_group("repair_kits"):
		if bool(kit.call("is_available")):
			count += 1
	return count


func _solid_signature() -> Array:
	var result: Array = []
	for node in scene.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if (body.collision_layer & 1) == 0:
			continue
		var shapes: Array = []
		for child in body.get_children():
			if child is CollisionShape3D and not child.disabled:
				shapes.append([child.transform, child.shape.get_class(), child.shape.size if child.shape is BoxShape3D else str(child.shape)])
		result.append([str(scene.get_path_to(body)), body.transform, body.collision_layer, body.collision_mask, shapes])
	result.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
