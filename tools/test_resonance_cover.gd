extends SceneTree

const CATALOG := preload("res://scripts/compact_arena_catalog.gd")
const STAGE := preload("res://scripts/compact_arena_stage.gd")
const MECHANISMS := preload("res://scripts/open_arena_mechanisms.gd")
var failures: Array[String] = []

class Arena extends Node3D:
	var arena_variant := "resonance"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func actor(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 2
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	body.add_child(collider)
	current_scene.add_child(body)
	return body

func run() -> void:
	var arena := Arena.new()
	root.add_child(arena)
	current_scene = arena
	var stage := STAGE.new()
	stage.arena_id = "resonance"
	arena.add_child(stage)
	var definition := CATALOG.definition("resonance")
	check(definition.covers.size() == 3, "three physical refuge walls")
	var wall: Dictionary = definition.covers[0]
	var normal := Vector3.BACK.rotated(Vector3.UP, deg_to_rad(float(wall.yaw)))
	var sheltered := actor(wall.position * Vector3(1, 0, 1) + normal * 1.6)
	var source: Vector3 = definition.resonators[0]
	var exposed := actor(source + Vector3(0, 0, 2))
	var mechanisms := MECHANISMS.new()
	mechanisms.arena_id = "resonance"
	arena.add_child(mechanisms)
	mechanisms.set_physics_process(false)
	mechanisms.configure(sheltered, exposed)
	mechanisms.set_enabled(true)
	mechanisms.reset_round()
	mechanisms.start_round()
	await physics_frame
	await physics_frame
	mechanisms.advance(4.1)
	check(mechanisms.get_snapshot().waves.is_empty(), "first automatic pulse no longer fires immediately after grace")
	check(not mechanisms._pressure_visible(source, sheltered.global_position), "authored wall shields its rear from this crystal")
	check(mechanisms._pressure_visible(source, exposed.global_position), "adjacent lane remains exposed")
	var sheltered_before := sheltered.global_position
	var exposed_before := exposed.global_position
	check(mechanisms.trigger_resonator(0), "shot triggers a pulse")
	check(not mechanisms.trigger_resonator(0), "crystal cooldown prevents repeated shot activation")
	mechanisms.advance(0.6)
	check(sheltered.global_position == sheltered_before and exposed.global_position == exposed_before, "visible warning precedes any impulse")
	mechanisms.advance(1.4)
	check(sheltered.global_position.is_equal_approx(sheltered_before), "sheltered actor is not pushed through the wall")
	check(exposed.global_position.distance_to(exposed_before) > 4.0, "open-lane actor receives the full 4.2 metre impulse")
	check(mechanisms.threat_at(sheltered.global_position, 20).is_empty(), "bot considers the rear of the wall safe from the wave")
	var waves: Array = mechanisms.get("_waves")
	check(not waves.is_empty() and waves[0].limits.size() == MECHANISMS.WAVE_SEGMENTS + 1, "visible wave has a collision-clipped radial profile")
	var mesh := mechanisms._clipped_wave_mesh(waves[0].limits, 5.0, true)
	check(mesh.get_surface_count() == 1 and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() < MECHANISMS.WAVE_SEGMENTS * 4, "wave display removes arcs occluded by refuge walls")
	mechanisms.advance(1.5)
	var snapshot := mechanisms.get_snapshot()
	check(snapshot.chain_triggers > 0, "unobstructed crystals can still react in a chain")
	check(snapshot.waves.size() <= MECHANISMS.MAX_WAVES, "chain reactions respect the simultaneous wave cap")
	mechanisms.reset_round()
	mechanisms.start_round()
	sheltered.global_position = definition.spawns[0]
	exposed.global_position = definition.spawns[1]
	mechanisms.advance(25.9)
	check(mechanisms.get_snapshot().periodic_triggers == 0, "automatic activation is delayed until 26 seconds")
	mechanisms.advance(0.2)
	check(mechanisms.get_snapshot().periodic_triggers == 1, "automatic pulse still starts after its longer delay")
	mechanisms.stop_round()
	check(mechanisms.get_snapshot().waves.is_empty(), "stopping the round removes waves")
	print("RESONANCE COVER TEST: %s (%d failures; real refuge collisions, warning, full push, clipped visuals, chain reactions, delayed automatic pulses)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
