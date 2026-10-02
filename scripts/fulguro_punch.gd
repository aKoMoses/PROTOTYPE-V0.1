class_name FulguroPunch
extends RefCounted
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")

const PASSIVE_HITS := preload("res://scripts/passive_state.gd")

## Shared rules for every FULGURO PUNCH user. Attackers own timing and visuals;
## this resolver owns the exact hit volume, wall occlusion and first-target rule.

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const COUNTER := preload("res://scripts/counter.gd")
const BODY_SAMPLE_HEIGHT := 0.86
const WALL_OPPOSITION_THRESHOLD := 0.45


static func definition() -> Dictionary:
	return COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]


static func flat_direction(value: Vector3) -> Vector3:
	var direction := value
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)


static func hit_radius(target: Node) -> float:
	if target != null and target.has_method("get_fulguro_hit_radius"):
		return maxf(0.05, float(target.call("get_fulguro_hit_radius")))
	if target != null and target.has_method("get_training_hit_radius"):
		return maxf(0.05, float(target.call("get_training_hit_radius")))
	if target is Node3D:
		var target_3d := target as Node3D
		return 0.70 * maxf(absf(target_3d.scale.x), absf(target_3d.scale.z))
	return 0.70


static func select_first_target(attacker: CollisionObject3D, candidates: Array, locked_direction: Vector3, strike_range: float = -1.0, strike_width: float = -1.0) -> Node:
	if attacker == null or not is_instance_valid(attacker):
		return null
	var values := definition()
	var direction := flat_direction(locked_direction)
	var reach := strike_range if strike_range > 0.0 else float(values.range)
	var width := strike_width if strike_width > 0.0 else float(values.width)
	var half_width := width * 0.5
	var best: Node = null
	var best_along := INF
	for candidate_value in candidates:
		var candidate := candidate_value as Node
		if candidate == null or candidate == attacker or not is_instance_valid(candidate) or not candidate is Node3D:
			continue
		if not candidate.has_method("take_damage") or not candidate.has_method("start_fulguro_projection"):
			continue
		if candidate.has_method("is_real_dead") and bool(candidate.call("is_real_dead")):
			continue
		if candidate.has_method("get_health") and float(candidate.call("get_health")) <= 0.0:
			continue
		var target_3d := candidate as Node3D
		var relative := target_3d.global_position - attacker.global_position
		relative.y = 0.0
		var along := direction.dot(relative)
		var radius := hit_radius(candidate)
		if along <= 0.02 or along - radius > reach:
			continue
		var lateral := (relative - direction * along).length()
		if lateral > half_width + radius:
			continue
		if not path_clear(attacker, candidate):
			continue
		if along < best_along:
			best = candidate
			best_along = along
	return best


static func path_clear(attacker: CollisionObject3D, target: Node) -> bool:
	if attacker == null or target == null or not target is CollisionObject3D:
		return false
	var target_body := target as CollisionObject3D
	var world := attacker.get_world_3d()
	if world == null:
		return true
	var from := attacker.global_position + Vector3.UP * BODY_SAMPLE_HEIGHT
	var to := target_body.global_position + Vector3.UP * BODY_SAMPLE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [attacker.get_rid(), target_body.get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


static func resolve_strike(attacker: CollisionObject3D, candidates: Array, locked_direction: Vector3, direct_damage: float, wall_damage: float, wall_stun: float, source_id: String, attack_id: String, strike_range: float = -1.0, strike_width: float = -1.0) -> Node:
	var target := select_first_target(attacker, candidates, locked_direction, strike_range, strike_width)
	if target == null:
		return null
	if attacker.has_method("register_offensive_attack"):
		attacker.call("register_offensive_attack", attack_id)
	var attack := {"id": "%d:%s" % [attacker.get_instance_id(), attack_id], "counter_trigger": bool(definition().get("counter_trigger", false)), "owner": weakref(attacker)}
	var shield_before := PASSIVE_HITS.shield_health(target)
	var applied := COUNTER.impact(target, direct_damage, source_id, attack_id, attack, target.global_position + Vector3.UP * BODY_SAMPLE_HEIGHT)
	if attacker.has_method("on_direct_offensive_hit"):
		attacker.call("on_direct_offensive_hit", attack_id, PASSIVE_HITS.accepted_damage(target, applied, shield_before), target)
	if applied <= 0.0:
		return null
	if target.has_method("flash_impact"):
		target.call("flash_impact", false)
	var values := definition()
	var dead := target.has_method("is_real_dead") and bool(target.call("is_real_dead"))
	if not dead:
		target.call(
			"start_fulguro_projection",
			flat_direction(locked_direction),
			float(values.max_knockback_distance),
			float(values.max_knockback_duration),
			wall_damage,
			wall_stun,
			source_id,
			attack_id
		)
	return target


static func sweep_static_body(body: CollisionObject3D, motion: Vector3, radius: float, height: float) -> Dictionary:
	if body != null:
		motion = ARENA_TRAVERSAL.motion(body, motion)
	var clear_result := {"travel": motion, "collided": false, "collider": null, "normal": Vector3.ZERO, "position": body.global_position + motion}
	if body == null or motion.length_squared() <= 0.0000001:
		return clear_result
	var world := body.get_world_3d()
	if world == null:
		return clear_result
	var shape := CapsuleShape3D.new()
	shape.radius = maxf(0.05, radius)
	shape.height = maxf(shape.radius * 2.0, height)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3.UP * (shape.height * 0.5))
	query.motion = motion
	query.margin = 0.025
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var excluded: Array[RID] = [body.get_rid()]
	excluded.append_array(ARENA_TRAVERSAL.exclusions(body))
	var scene := body.get_tree().current_scene
	if scene != null and scene.has_meta("arena_floor_rid"):
		var floor_rid: RID = scene.get_meta("arena_floor_rid")
		if not excluded.has(floor_rid):
			excluded.append(floor_rid)
	query.exclude = excluded
	var cast := world.direct_space_state.cast_motion(query)
	if cast.is_empty() or float(cast[0]) >= 0.999:
		return clear_result
	var safe_fraction := clampf(float(cast[0]), 0.0, 1.0)
	var direction := flat_direction(motion)
	var side := Vector3(-direction.z, 0.0, direction.x)
	var ray_length := motion.length() + radius + 0.18
	var closest_hit: Dictionary = {}
	var closest_distance := INF
	for lateral_value in [0.0, radius * 0.72, -radius * 0.72]:
		var lateral := float(lateral_value)
		var from: Vector3 = body.global_position + Vector3.UP * BODY_SAMPLE_HEIGHT + side * lateral
		var ray := PhysicsRayQueryParameters3D.create(from, from + direction * ray_length)
		ray.collision_mask = 1
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		ray.exclude = excluded
		var hit := world.direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			continue
		var distance: float = from.distance_to(Vector3(hit.position))
		if distance < closest_distance:
			closest_hit = hit
			closest_distance = distance
	var safe_travel := motion * maxf(0.0, safe_fraction - 0.002)
	return {
		"travel": safe_travel,
		"collided": true,
		"collider": closest_hit.get("collider", null),
		"normal": Vector3(closest_hit.get("normal", Vector3.ZERO)),
		"position": Vector3(closest_hit.get("position", body.global_position + safe_travel)),
	}


static func is_crushing_wall(collider: Object, collision_normal: Vector3, projection_direction: Vector3) -> bool:
	if collider == null or not collider is StaticBody3D:
		return false
	var body := collider as StaticBody3D
	if (body.collision_layer & 1) == 0 or bool(body.get_meta("fulguro_non_solid", false)):
		return false
	var normal := collision_normal.normalized() if collision_normal.length_squared() > 0.001 else Vector3.ZERO
	return normal.dot(-flat_direction(projection_direction)) >= WALL_OPPOSITION_THRESHOLD
