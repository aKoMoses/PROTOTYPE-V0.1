extends SceneTree

## Headless AI-only soak: production survival terrain and the full production
## controller execute perception, searches, movement, dodges, charges and attack
## gates. Only projectile presentation is replaced with a counter, so skipped
## rendering/tweens cannot distort cache or node-growth measurements.

const SURVIVAL := preload("res://scripts/survival.gd")
const CONTROLLER := preload("res://scripts/training_bot.gd")
const BOT_COUNT := 12
const STEPS_PER_ROUND := 720
const ROUNDS := 3
const STEP_SECONDS := 0.05

class Arena extends SURVIVAL:
	func _ready() -> void:
		_build_world()

class SoakController extends CONTROLLER:
	var resolved_shots := 0
	func _spawn_attack_visual(_player: Node3D, _attack_id: String, _offset: Vector3 = Vector3.ZERO) -> void:
		resolved_shots += 1

class BotBody extends StaticBody3D:
	var combat_state := {"max_health": 1200.0}
	func get_health() -> float:
		return 1200.0
	func get_max_health() -> float:
		return 1200.0
	func is_training_bot_enabled() -> bool:
		return true
	func is_real_dead() -> bool:
		return false
	func is_action_locked() -> bool:
		return false
	func get_slow_percent() -> float:
		return 0.0
	func is_visible_to(_observer: Node3D) -> bool:
		return true

class PlayerBody extends CharacterBody3D:
	var hidden := false
	func is_visible_to(_observer: Node3D) -> bool:
		return not hidden
	func is_real_dead() -> bool:
		return false
	func take_damage(amount: float, _source: String, _attack: String) -> float:
		return amount

var failures: Array[String] = []
var scene: Node3D
var player: PlayerBody
var bodies: Array[BotBody] = []
var controllers: Array[SoakController] = []
var hazards: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(20260930)
	scene = Arena.new()
	root.add_child(scene)
	current_scene = scene
	# Disabling process_mode would remove inherited collision objects from the
	# physics server. Stop callbacks only, retaining the real terrain broadphase.
	scene.set_process(false)
	scene.set_physics_process(false)
	player = PlayerBody.new()
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 0
	_add_capsule(player)
	scene.add_child(player)
	for index in range(BOT_COUNT):
		var body := BotBody.new()
		body.name = "SoakBot%d" % index
		body.collision_layer = 2
		body.collision_mask = 0
		var role: String = ["chaser", "shooter", "charger", "boss"][index % 4]
		body.scale = Vector3.ONE * {"chaser": 1.0, "shooter": 0.86, "charger": 1.18, "boss": 1.5}[role]
		# Opposing sides of the three production wrecks force real detours in
		# the opening remembered-target pursuit, rather than only direct sweeps.
		body.position = Vector3([-15.0, -11.0, -3.0, 3.0, 11.0, 15.0][index % 6], 0.0, -5.0 if index < 6 else 9.0)
		_add_capsule(body)
		scene.add_child(body)
		body.add_to_group("prototype0_combat_bots")
		var controller := SoakController.new()
		controller.name = "TrainingBot"
		body.add_child(controller)
		controller.survival_role = role
		controller.training_attack_damage = 0.0
		controller.training_attack_interval = 2.6 if role == "boss" else 3.2 if role == "charger" else 1.5 if role == "chaser" else 2.5
		controller.set_enabled(true)
		controller.set_physics_process(false)
		controller._last_observed_position = Vector3(12.0, 0.0, -4.5)
		controller._has_last_observed_position = true
		controller._last_seen_at = 0.0
		bodies.append(body)
		controllers.append(controller)
	for index in range(2):
		var hazard := Node3D.new()
		hazard.name = "SoakProjectile%d" % index
		hazard.set_meta("ai_projectile_velocity", Vector3.FORWARD * 10.0)
		hazard.set_meta("ai_projectile_radius", 0.18)
		hazard.set_meta("ai_projectile_source", player.get_instance_id())
		scene.add_child(hazard)
		hazard.add_to_group("prototype0_gameplay_projectiles")
		hazards.append(hazard)
	await physics_frame
	controllers[0]._navigation.invalidate(true)
	var starting_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var walked: PackedFloat64Array = []
	walked.resize(BOT_COUNT)
	var memories: PackedFloat64Array = []
	var cache_history: Array[Dictionary] = []
	var dodges := 0
	var charges := 0
	var searches := 0
	var collisions := 0
	var all_finite := true
	var all_bounded := true
	for round_index in range(ROUNDS):
		# Replay a complete encounter with the terrain caches retained. A warmed
		# replay must reuse its coverage rather than keep allocating new maps.
		for index in range(BOT_COUNT):
			bodies[index].position = Vector3([-15.0, -11.0, -3.0, 3.0, 11.0, 15.0][index % 6], 0.0, -5.0 if index < 6 else 9.0)
			controllers[index].set_enabled(true)
			controllers[index].set_physics_process(false)
			controllers[index]._last_observed_position = Vector3(12.0, 0.0, -4.5)
			controllers[index]._has_last_observed_position = true
			controllers[index]._last_seen_at = 0.0
		var samples: PackedFloat64Array = []
		for phase in range(STEPS_PER_ROUND):
			var angle := TAU * float(phase) / float(STEPS_PER_ROUND)
			player.position = Vector3(cos(angle), 0.0, sin(angle)) * 13.0
			player.hidden = phase < 60 or (phase >= 240 and phase < 420)
			for hazard_index in range(hazards.size()):
				var hazard := hazards[hazard_index]
				if phase % 100 == 0:
					var target := bodies[(phase / 100 + hazard_index * 4) % BOT_COUNT]
					var direction := Vector3(cos(angle + float(hazard_index)), 0.0, sin(angle + float(hazard_index)))
					hazard.position = target.position - direction * 5.0 + Vector3.UP * 0.7
					hazard.set_meta("ai_projectile_velocity", direction * 10.0)
				hazard.position += Vector3(hazard.get_meta("ai_projectile_velocity")) * STEP_SECONDS
			var started_at := Time.get_ticks_usec()
			for index in range(BOT_COUNT):
				var previous := bodies[index].position
				controllers[index]._physics_process(STEP_SECONDS)
				walked[index] += previous.distance_to(bodies[index].position)
			samples.append(float(Time.get_ticks_usec() - started_at) / 1000.0)
			for index in range(BOT_COUNT):
				var controller := controllers[index]
				dodges += 1 if controller._dodge_remaining > 0.0 else 0
				charges += 1 if controller._charge_remaining > 0.0 else 0
				searches += 1 if not controller._has_last_observed_position else 0
				all_finite = all_finite and bodies[index].position.is_finite()
				all_bounded = all_bounded and maxf(absf(bodies[index].position.x), absf(bodies[index].position.z)) <= 21.001
				if phase % 20 == 0:
					var query: PhysicsShapeQueryParameters3D = controller._bot_shape_query(bodies[index])
					# Contact padding is a conservative navigation guard. Test the
					# actual collision volume here to distinguish touch from clipping.
					query.margin = 0.0
					var contacts := bodies[index].get_world_3d().direct_space_state.intersect_shape(query, 1)
					if not contacts.is_empty():
						collisions += 1
						print("AI SOAK contact: round %d phase %d bot %d role %s position %s obstacle %s charge %.2f" % [round_index + 1, phase, index, controller.survival_role, bodies[index].position, contacts[0].collider.name, controller._charge_remaining])
			if phase % 120 == 0:
				await physics_frame
		var summary := _summary(samples)
		var memory := float(Performance.get_monitor(Performance.MEMORY_STATIC))
		var cache: Dictionary = controllers[0]._navigation.get_cache_stats()
		memories.append(memory)
		cache_history.append(cache)
		print("AI SOAK round %d: %d bots / mean %.3f ms / p95 %.3f ms / max %.3f ms / static %.2f MiB / cache %s" % [round_index + 1, BOT_COUNT, summary.mean, summary.p95, summary.max, memory / 1048576.0, cache])
	var shots := 0
	for controller in controllers:
		shots += controller.resolved_shots
	print("AI SOAK activity: %.0f simulated seconds / %d ranged attacks / %d charge ticks / %d dodge ticks / %d search ticks / %.1f m walked" % [ROUNDS * STEPS_PER_ROUND * STEP_SECONDS, shots, charges, dodges, searches, _sum(walked)])
	_check(all_finite and all_bounded, "all survival roles retain finite positions inside the yard")
	_check(collisions == 0, "soak has no body/terrain overlap (%d contacts)" % collisions)
	_check(shots > 0 and charges > 0 and dodges > 0 and searches > 0, "soak exercises shooting, charging, projectile evasion and unseen-target searches")
	for index in range(BOT_COUNT):
		_check(walked[index] > 20.0, "survival bot %d meaningfully traverses the map" % index)
	_check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == starting_nodes, "AI decisions create no growing node population")
	_check(memories[2] - memories[1] < 0.25 * 1048576.0, "warmed replay has no meaningful static memory growth")
	_check(int(cache_history[2].grids) <= 4, "twelve scaled bots share only the four expected clearance maps")
	_check(int(cache_history[0].cells) > 100 and int(cache_history[0].edges) > 100, "opening cover pursuits exercise A* and warm shared terrain caches")
	_check(int(cache_history[2].cells) == int(cache_history[1].cells) and int(cache_history[2].edges) == int(cache_history[1].edges), "repeated warmed encounters allocate no additional terrain-cache entries")
	_check(int(cache_history[2].cells) <= 4 * 43 * 43 and int(cache_history[2].edges) <= 4 * 43 * 43 * 4, "terrain cells and cached edges remain bounded by the yard dimensions")
	current_scene = null
	scene.queue_free()
	controllers[0]._navigation.invalidate(true)
	await process_frame
	if failures.is_empty():
		print("BOT AI SOAK TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BOT AI SOAK TEST: FAIL (%d)" % failures.size())
		quit(1)


func _add_capsule(body: CollisionObject3D) -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.7
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	body.add_child(collision)


func _summary(values: PackedFloat64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	return {"mean": _sum(values) / float(values.size()), "p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "max": sorted[-1]}


func _sum(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
