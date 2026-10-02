extends Node3D

## Continuous sphere sweeps preserve the projectile's physical diameter at any
## tick rate. Damage distance ends at the exact surface point projected along
## the shot's path from the muzzle, independent of the shooter. Centre travel
## controls range and is retained in the collision for diagnostics.
signal finished(hit: Dictionary, distance: float)
signal impacted(hit: Dictionary, distance: float)
signal advanced(start: Vector3, end: Vector3)

const CONTACT_TOLERANCE := 0.0005
const COLLISION_MARGIN := 0.00001
const MAGNETIC_WALL := preload("res://scripts/magnetic_wall.gd")
const HOMING_ROCKET := preload("res://scripts/homing_rocket.gd")

var _direction := Vector3.FORWARD
var _speed := 1.0
var _range := 1.0
var _radius := 0.075
var _distance := 0.0
var _origin := Vector3.ZERO
var _configured := false
var _finished := false
var _cast: ShapeCast3D
var _overlap_query: PhysicsShapeQueryParameters3D
var _excluded: Array[RID] = []
var _piercing := false


func _ready() -> void:
	process_physics_priority = 20
	add_to_group("prototype0_gameplay_projectiles")
	_create_cast()


func _create_cast() -> void:
	if _cast != null:
		return
	_cast = ShapeCast3D.new()
	_cast.name = "ContinuousCollision"
	_cast.enabled = false
	_cast.collide_with_areas = true
	_cast.collide_with_bodies = true
	_cast.margin = COLLISION_MARGIN
	_cast.max_results = 8
	_cast.shape = SphereShape3D.new()
	add_child(_cast)
	_overlap_query = PhysicsShapeQueryParameters3D.new()
	_overlap_query.collide_with_areas = true
	_overlap_query.collide_with_bodies = true
	_overlap_query.margin = COLLISION_MARGIN
	_overlap_query.shape = _cast.shape


func configure(direction: Vector3, speed: float, max_range: float, collision_mask: int, excluded: Array[RID], radius: float, piercing: bool = false) -> void:
	_create_cast()
	_direction = direction.normalized() if direction.length_squared() > 0.000001 else Vector3.FORWARD
	_speed = maxf(0.01, speed)
	_range = maxf(0.01, max_range)
	_radius = maxf(0.001, radius)
	_distance = 0.0
	_origin = global_position
	_finished = false
	_configured = true
	(_cast.shape as SphereShape3D).radius = _radius
	_cast.collision_mask = collision_mask
	_overlap_query.collision_mask = collision_mask
	_excluded = excluded.duplicate()
	_piercing = piercing
	_overlap_query.exclude = _excluded
	_cast.clear_exceptions()
	for excluded_rid in excluded:
		_cast.add_exception_rid(excluded_rid)
	set_meta("ai_projectile_velocity", _direction * _speed)
	set_meta("ai_projectile_endpoint", _origin + _direction * _range)
	set_meta("ai_projectile_radius", _radius)


func resolve_muzzle_guard(support: Vector3) -> void:
	if _finished or not _configured or not is_inside_tree():
		return
	# A barrel can extend beyond cover while its holder remains behind it. The
	# projectile still originates at the muzzle, but this obstruction ends it
	# immediately, without granting travel or damage bonuses along the barrel.
	var obstruction := _sweep(support, _origin - support)
	while _non_blocking_receiver(obstruction) != null:
		_exclude_target(_non_blocking_receiver(obstruction))
		obstruction = _sweep(support, _origin - support)
	if not obstruction.is_empty():
		obstruction["muzzle_blocked"] = true
		_finish(obstruction)


func _physics_process(delta: float) -> void:
	if _finished or not _configured or delta <= 0.0:
		return
	var step := minf(_speed * delta, maxf(0.0, _range - _distance))
	# Continue the unused part of the same tick after each pierced actor. Walls
	# are swept again, including thin walls immediately behind the victim.
	while step > 0.000001 and not _finished:
		var start := global_position
		var hit := _sweep(start, _direction * step)
		if hit.is_empty():
			global_position = start + _direction * step
			_distance += step
			advanced.emit(start, global_position)
			break
		var receiver := _non_blocking_receiver(hit)
		if receiver != null:
			if receiver.has_method("projectile_impact"):
				receiver.call("projectile_impact", hit["position"])
			_exclude_target(receiver)
			continue
		var traveled := clampf(float(hit.get("travel", 0.0)), 0.0, step)
		hit["center_distance"] = _distance + traveled
		global_position = start + _direction * traveled
		var impact_distance := _distance if bool(hit.get("started_overlapping", false)) else clampf(_distance + ((hit["position"] as Vector3) - start).dot(_direction), 0.0, _range)
		_distance += traveled
		advanced.emit(start, global_position)
		var target := _pierce_target(hit)
		_contact(hit, impact_distance)
		if not _piercing or target == null or bool(hit.get("stop_piercing", false)):
			_distance = impact_distance
			_finish(hit, false)
			return
		_exclude_target(target)
		var contact_rid: RID = hit.get("rid", RID())
		if contact_rid.is_valid() and not _excluded.has(contact_rid):
			_excluded.append(contact_rid)
		step -= traveled
	if _distance >= _range - 0.000001:
		_finish({})


func _non_blocking_receiver(hit: Dictionary) -> CollisionObject3D:
	var receiver := hit.get("collider") as CollisionObject3D
	return receiver if receiver != null and receiver.get_meta("non_blocking_projectile_receiver", false) else null


func _pierce_target(hit: Dictionary) -> Node:
	var collider := hit.get("collider") as Node
	if collider is CollisionObject3D and (collider.collision_layer & 1) != 0:
		return null
	while collider != null and not collider.has_method("take_damage"):
		collider = collider.get_parent()
	if collider != null and collider.is_in_group("prototype0_homing_rockets"):
		return null
	return collider


func _exclude_target(target: Node) -> void:
	if target is CollisionObject3D and not _excluded.has(target.get_rid()):
		_excluded.append(target.get_rid())
	for child in target.get_children():
		_exclude_target(child)


func _sweep(start: Vector3, motion: Vector3) -> Dictionary:
	# Refresh every sweep: a wall can deploy while this shot is already flying.
	_overlap_query.exclude = HOMING_ROCKET.owned_exclusions(self, MAGNETIC_WALL.owned_exclusions(self, _excluded))
	_cast.clear_exceptions()
	for excluded_rid in _overlap_query.exclude:
		_cast.add_exception_rid(excluded_rid)
	# cast_motion ignores existing overlaps. The zero-length shape query must
	# precede every sweep, including the very first tick and the muzzle guard.
	var overlap := _overlap_at(start)
	if not overlap.is_empty():
		overlap["travel"] = 0.0
		overlap["started_overlapping"] = true
		return overlap
	var hit := _cast_at(start, motion)
	if hit.is_empty():
		return {}
	var length := motion.length()
	if length <= 0.000001:
		hit["travel"] = 0.0
		return hit
	var direction := motion / length
	var safe_distance := length * _cast.get_closest_collision_safe_fraction()
	var unsafe_distance := length * _cast.get_closest_collision_unsafe_fraction()
	# Large low-frequency steps have a wider numerical bracket. Refine only a
	# confirmed contact, so a thin wall cannot turn that error into extra range.
	for _iteration in range(4):
		var bracket := unsafe_distance - safe_distance
		if bracket <= CONTACT_TOLERANCE:
			break
		var refined := _cast_at(start + direction * safe_distance, direction * bracket)
		if refined.is_empty():
			break
		hit = refined
		var previous_safe := safe_distance
		safe_distance = previous_safe + bracket * _cast.get_closest_collision_safe_fraction()
		unsafe_distance = previous_safe + bracket * _cast.get_closest_collision_unsafe_fraction()
	# Projecting the surface point plus its sphere radius gives the contact
	# centre, keeping damage tied to actual flight rather than a chord to a
	# collider or the shooter's current position.
	var normal: Vector3 = hit["normal"]
	var center: Vector3 = (hit["position"] as Vector3) + normal * _radius
	var contact_travel := clampf((center - start).dot(direction), safe_distance, unsafe_distance)
	hit["travel"] = clampf(contact_travel, 0.0, length)
	return hit


func _overlap_at(start: Vector3) -> Dictionary:
	_overlap_query.transform = Transform3D(Basis.IDENTITY, start)
	var space := get_world_3d().direct_space_state
	var overlaps := space.intersect_shape(_overlap_query, 8)
	if overlaps.is_empty():
		return {}
	var contact := space.get_rest_info(_overlap_query)
	if not contact.is_empty():
		var collider := instance_from_id(int(contact["collider_id"]))
		var normal: Vector3 = contact["normal"]
		return {"collider": collider, "collider_id": contact["collider_id"],
			"rid": contact["rid"], "shape": contact["shape"],
			"position": contact["point"], "normal": normal.normalized() if not normal.is_zero_approx() else -_direction}
	# Deep containment can have no manifold surface; it is nevertheless an
	# immediate obstruction, so a missing normal must never allow an escape.
	var overlap: Dictionary = overlaps[0]
	return {"collider": overlap["collider"], "collider_id": overlap["collider_id"],
		"rid": overlap["rid"], "shape": overlap["shape"], "position": start, "normal": -_direction}


func _cast_at(start: Vector3, motion: Vector3) -> Dictionary:
	_cast.global_transform = Transform3D(Basis.IDENTITY, start)
	_cast.target_position = motion
	_cast.force_shapecast_update()
	if not _cast.is_colliding():
		return {}
	var nearest := -1
	var nearest_distance := INF
	for index in range(_cast.get_collision_count()):
		var collider := _cast.get_collider(index)
		if not is_instance_valid(collider):
			continue
		var point := _cast.get_collision_point(index)
		var distance := start.distance_squared_to(point)
		if distance < nearest_distance:
			nearest = index
			nearest_distance = distance
	if nearest < 0:
		return {}
	var normal := _cast.get_collision_normal(nearest)
	if normal.is_zero_approx():
		normal = -motion.normalized() if not motion.is_zero_approx() else -_direction
	return {"collider": _cast.get_collider(nearest), "collider_id": _cast.get_collider(nearest).get_instance_id(),
		"rid": _cast.get_collider_rid(nearest), "shape": _cast.get_collider_shape(nearest),
		"position": _cast.get_collision_point(nearest), "normal": normal.normalized()}


func _contact(hit: Dictionary, distance: float) -> void:
	var collider: Object = hit.get("collider")
	if is_instance_valid(collider) and collider.has_method("projectile_impact"):
		collider.call("projectile_impact", hit["position"])
	impacted.emit(hit, distance)


func _finish(hit: Dictionary, notify_contact: bool = true) -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	if notify_contact and not hit.is_empty():
		_contact(hit, _distance)
	finished.emit(hit, _distance)
	queue_free()
