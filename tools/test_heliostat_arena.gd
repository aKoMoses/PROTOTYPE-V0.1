extends SceneTree

const STAGE := preload("res://scripts/compact_arena_stage.gd")
const SOLAR := preload("res://scripts/heliostat_arena.gd")
const LIVE := preload("res://scripts/live_projectile.gd")
const LONGSHOT := preload("res://scripts/longshot_projectile.gd")
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var solar: Node3D
var player: CharacterBody3D
var bot: CharacterBody3D

class Fixture extends Node3D:
	var _arena_blockers: Array = []

class Fighter extends CharacterBody3D:
	var hp := 1000.0
	var _gameplay_enabled := true
	var _duel_paused := false
	var attacks: Dictionary = {}
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1
		var shape := CapsuleShape3D.new()
		shape.radius = 0.32
		shape.height = 1.8
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 0.9
		add_child(collision)
	func take_damage(amount: float, _source: String = "", attack_id: String = "") -> float:
		if attacks.has(attack_id):
			return 0.0
		attacks[attack_id] = true
		hp -= amount
		return amount
	func is_real_dead() -> bool:
		return hp <= 0
	func get_max_health() -> float:
		return 1000.0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("HELIOSTAT TEST: " + label)

func centroid(polygon: PackedVector2Array) -> Vector3:
	var value := Vector2.ZERO
	for point in polygon:
		value += point
	value /= polygon.size()
	return Vector3(value.x, 0, value.y)

func light_point() -> Vector3:
	var largest := 0.0
	var found := Vector3.ZERO
	for polygon in solar.get("light_polygons"):
		var area: float = absf((polygon[1] - polygon[0]).cross(polygon[3] - polygon[0]))
		if area > largest:
			largest = area
			found = centroid(polygon)
	return found

func _run() -> void:
	scene = Fixture.new()
	root.add_child(scene)
	current_scene = scene
	var stage := STAGE.new()
	stage.arena_id = "heliostat"
	scene.add_child(stage)
	stage.set_process(false)
	player = Fighter.new()
	bot = Fighter.new()
	scene.add_child(player)
	scene.add_child(bot)
	bot.position = Vector3(12, 0, -10)
	solar = SOLAR.new()
	solar.arena_id = "heliostat"
	scene.add_child(solar)
	solar.set_physics_process(false)
	solar.call("configure", player, bot)
	solar.call("set_stage", stage)
	solar.call("set_enabled", true)
	await physics_frame
	var idle: Dictionary = solar.call("get_snapshot")
	solar.call("advance", 15.0)
	check(idle == solar.call("get_snapshot"), "countdown freezes radiation and mirrors")
	solar.call("start_round")
	solar.call("advance", 4.5)
	check(solar.get("phase") == "warning" and (solar.call("get_threats") as Array).size() == 1, "solar warning before first damage")
	check(player.get("hp") == 1000.0 and float(solar.call("get_heat", player)) == 0.0, "warning never heats or hurts")
	check(stage.get("_definition").covers.size() == 3 and stage.get("_definition").repairs.is_empty(), "three covers, no generic health pads")
	check(solar.get("_fixtures").is_empty() and solar.get("_portals").is_empty() and solar.get("_boosts").is_empty(), "old lanes portals and boosts removed")
	var before_pause: Dictionary = solar.call("get_snapshot")
	paused = true
	solar.call("advance", 10.0)
	check(before_pause == solar.call("get_snapshot"), "pause freezes warning and heat")
	paused = false
	solar.call("advance", 1.01)
	check(solar.get("phase") == "active" and int(solar.get("_active_mirror")) == 0, "directly lit left mirror captures sunlight")
	var mirror: StaticBody3D = solar.get("mirrors")[0]
	var initial_dir: Vector2 = mirror.call("get_direction")
	mirror.call("projectile_impact", mirror.global_position)
	check(mirror.get("pending") >= 0 and mirror.call("get_direction") == initial_dir, "impact announces orientation before applying it")
	for index in range(6):
		mirror.call("projectile_impact", mirror.global_position)
	solar.call("advance", 0.40)
	check(mirror.get("rotations") == 0 and not (solar.get("preview_polygons") as Array).is_empty(), "six pellets create one pending turn with preview")
	check((solar.call("get_threats") as Array).size() == 2, "lit mirror announces its next dangerous footprint to bot")
	var predicted := false
	for polygon in solar.get("_pending_footprints").get(0, []):
		var point := centroid(polygon)
		if not solar.call("exposure_at", point, 0.0):
			var warning: Dictionary = solar.call("threat_at", point, 0.0)
			predicted = warning.get("phase", "") == "warning" and warning.get("mirror_index", -1) == 0
			if predicted:
				break
	check(predicted, "bot sees the upcoming redirected beam before it becomes damaging")
	var pending_pause: Dictionary = solar.call("get_snapshot")
	paused = true
	check(not mirror.call("request_turn"), "paused command rejects impacts")
	solar.call("advance", 3.0)
	check(pending_pause == solar.call("get_snapshot"), "pause freezes an in-progress mirror rotation")
	paused = false
	solar.call("advance", 0.41)
	check(mirror.get("rotations") == 1 and mirror.call("get_direction") != initial_dir, "orientation commits after 0.8 seconds")
	check(not mirror.call("request_turn"), "mirror remains locked two seconds after turn")
	solar.call("advance", 2.05)
	check(mirror.call("request_turn"), "either combatant may turn it after lock expires")
	solar.call("reset_round")
	solar.call("start_round")
	solar.call("advance", 6.05)
	bot.position = Vector3(5, 0, -6)
	await physics_frame
	var mirror_dir: Vector2 = mirror.call("next_direction")
	var observed_enemy := mirror.position + Vector3(mirror_dir.x, 0, mirror_dir.y) * 10.0
	check(solar.call("get_bot_mirror_target", bot, observed_enemy, "hard") == mirror, "bot selects lit mirror when next trajectory exposes observed opponent")
	check(solar.call("get_bot_mirror_target", bot, observed_enemy, "easy") == null, "easy bot gets fewer strategic mirror opportunities")
	solar.call("reset_round")
	solar.call("start_round")
	solar.call("advance", 11.5)
	check(int(solar.get("_active_mirror")) == -1, "unlit mirrors do not invent secondary beams")
	check(not (solar.get("shadow_polygons") as Array).is_empty(), "opaque covers cast explicit solar refuges")
	var blocked_points := 0
	for polygon in solar.get("shadow_polygons"):
		if not solar.call("exposure_at", centroid(polygon), 0.0):
			blocked_points += 1
	check(blocked_points > 10, "rendered blue refuge centroids are mechanically protected")
	var old_shadows: Array = (solar.get("shadow_polygons") as Array).duplicate(true)
	solar.call("advance", 1.0)
	check(old_shadows != solar.get("shadow_polygons"), "sweeping head moves the actual cover shadows")
	player.set("hp", 1000.0)
	solar.get("heat").clear()
	for index in range(84):
		player.position = light_point()
		solar.call("advance", 1.0 / 60.0)
	check(player.get("hp") == 1000.0 and float(solar.call("get_heat", player)) > 0.60, "quick exposure builds heat without instant damage")
	for index in range(110):
		player.position = light_point()
		solar.call("advance", 1.0 / 60.0)
	check(float(player.get("hp")) < 1000.0 and float(solar.call("get_heat", player)) > 0.98, "sustained exposure burns using unique arena damage ids")
	var burnt_hp := float(player.get("hp"))
	player.position = Vector3(12, 0, -10)
	solar.call("advance", 0.6)
	check(player.get("hp") == burnt_hp and float(solar.call("get_heat", player)) < 0.85, "safe ground stops burns and cools gradually")
	solar.call("reset_round")
	check(float(solar.call("get_heat", player)) == 0.0 and not (solar.get("_light_mesh") as MeshInstance3D).visible, "round reset clears all heat and radiation")
	check(mirror.get("preset") == 1 and mirror.get("pending") == -1 and mirror.get("rotations") == 0, "round reset restores mirror orientation and locks")
	# Real collision sweeps, not synthetic calls to the command method.
	solar.call("start_round")
	solar.call("advance", 4.1)
	player.position = Vector3(12, 0, -10)
	await physics_frame
	var projectile := LIVE.new()
	scene.add_child(projectile)
	projectile.position = mirror.position + Vector3(0, 1.1, -2.5)
	projectile.configure(Vector3(0, 0, 1), 50.0, 6.0, 1 | 2 | 8, [])
	projectile.set_physics_process(false)
	projectile.call("_physics_process", 0.10)
	check(mirror.get("pending") >= 0, "physical blaster/shotgun projectile hits the command receiver")
	await process_frame
	solar.call("reset_round")
	solar.call("start_round")
	solar.call("advance", 4.1)
	var longshot := LONGSHOT.new()
	scene.add_child(longshot)
	longshot.position = mirror.position + Vector3(0, 1.1, -2.5)
	longshot.configure(Vector3(0, 0, 1), 50.0, 6.0, 1 | 2 | 4 | 8, [], 0.15, false)
	longshot.set_physics_process(false)
	longshot.call("_physics_process", 0.10)
	check(mirror.get("pending") >= 0, "physical Longshot projectile hits the same receiver")
	await process_frame
	solar.call("reset_round")
	solar.call("start_round")
	solar.call("advance", 4.1)
	mirror.call("take_damage", 100.0, "player", "melee:1")
	check(mirror.get("pending") >= 0, "melee callback operates command without combat rewards")
	solar.call("advance", 0.81)
	var stop_snapshot: Dictionary = solar.call("get_snapshot")
	solar.call("stop_round")
	check(not mirror.call("request_turn"), "result screen ignores late hits")
	solar.call("advance", 5.0)
	check(float(solar.get("elapsed")) == float(stop_snapshot.elapsed) and (solar.get("light_polygons") as Array).is_empty(), "result screen stops radiation and time")
	solar.call("set_enabled", false)
	check(mirror.collision_layer == 0 and (mirror.get_node("MirrorPedestal") as StaticBody3D).collision_layer == 0, "disabled mode removes hidden mirror collisions")
	scene.queue_free()
	await process_frame
	await _production_bot()
	for failure in failures:
		print("FAILED: " + failure)
	print("HELIOSTAT ARENA TEST: %s (%d checks; %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _production_bot() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_select_arena", "heliostat")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	player = scene.get_node("Player")
	var target := scene.get_node("TargetDummy") as Node3D
	player.set_process(false)
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_process(false)
	target.set_physics_process(false)
	var controller := target.get_node("TrainingBot")
	controller.set_process(false)
	controller.set_physics_process(false)
	var equipment := controller.get_node("DuelEquipment")
	solar = scene.get_node("ArenaHazards")
	solar.set_physics_process(false)
	check(solar.get_script().resource_path == "res://scripts/heliostat_arena.gd", "real duel selects specialized solar controller")
	var mirror: Node3D = solar.get("mirrors")[0]
	for weapon in ["blaster", "shotgun", "longshot"]:
		solar.call("reset_round")
		solar.call("start_round")
		solar.call("advance", 6.05)
		player.position = Vector3(-3, 0, 7)
		target.position = Vector3(-7, 0, -8.8)
		target.call("set_duel_profile", weapon)
		equipment.set("next_attack_at", 0.0)
		var perception := {"arena_control_target": mirror, "line_of_fire": false, "velocity": Vector3.ZERO}
		var tuning := {"aim_error_degrees": 0.0, "position_quality": 1.0, "module_skill": 0.0}
		await physics_frame
		for frame in range(180):
			equipment.call("tick", 1.0 / 60.0, 10.0 + frame / 60.0, false, player.position, target, player, controller, perception, tuning)
			await physics_frame
			if int(mirror.get("pending")) >= 0:
				break
		check(int(mirror.get("pending")) >= 0, "real bot " + weapon + " fires its normal projectile at a command")
		equipment.call("cancel_action", "test ended")
		# Remove shots still in flight so the next weapon trial is independent.
		for child in scene.get_children():
			if child.get_script() != null and child.get_script().resource_path in ["res://scripts/live_projectile.gd", "res://scripts/longshot_projectile.gd"]:
				child.queue_free()
		await process_frame
	solar.call("reset_round")
	solar.call("start_round")
	solar.call("advance", 12.6)
	target.position = light_point()
	await physics_frame
	controller.set("_elapsed", 10.0)
	controller.set("_hazard_threat_id", (solar.call("get_threats") as Array)[0].id)
	controller.set("_hazard_observed_at", 9.0)
	var prior := target.position
	check(bool(controller.call("_update_hazard_avoidance", target, 1.0 / 30.0)) and target.position != prior, "real bot moves away from an exposed solar footprint")
	scene.call("stop_duel")
