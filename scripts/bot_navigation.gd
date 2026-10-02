extends RefCounted

## Clearance-aware navigation for the authored arena and the survival yard.
## A shared, lazy grid amortises physics queries across bots. Routes retain their
## waypoints while a target moves slightly, so an enemy commits to a detour
## rather than switching sides every tactical decision. Movement still uses the
## controller's swept collision check; this helper never teleports an actor.

const CELL_SIZE := 1.0
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const CLEARANCE_MARGIN := 0.14
const DEPARTURE_MARGIN := 0.04
const ROUTE_REFRESH_SECONDS := 0.80
const DESTINATION_REPLAN_DISTANCE := 1.6
const MAX_SEARCH_EXPANSIONS := 4096
const MAX_SHARED_GRIDS := 8
const MAX_DISTANCE_CACHE := 32
const GEOMETRY_REFRESH_SECONDS := 0.75
const NEIGHBOURS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]

static var _shared_grids: Dictionary = {}
static var _world_geometry: Dictionary = {}

var _path: Array[Vector3] = []
var arena_center := Vector3.ZERO
var _waypoint := 0
var _destination := Vector3.INF
var _route_key := ""
var _planned_at := -100.0
var _last_origin := Vector3.INF
var _reachable := false
var _path_length := INF
var _last_expansions := 0
var _distance_cache: Dictionary = {}


func invalidate(clear_shared: bool = false) -> void:
	_path.clear()
	_waypoint = 0
	_destination = Vector3.INF
	_route_key = ""
	_planned_at = -100.0
	_last_origin = Vector3.INF
	_reachable = false
	_path_length = INF
	_distance_cache.clear()
	if clear_shared:
		_shared_grids.clear()
		_world_geometry.clear()


func get_direction(body: CollisionObject3D, destination: Vector3, now: float, arena_limit: float = 27.0) -> Vector3:
	var context := _context(body, arena_limit)
	if context.is_empty() or not destination.is_finite():
		return Vector3.ZERO
	var origin := _flat(body.global_position)
	var goal := _clamp_point(destination, arena_limit)
	if origin.distance_squared_to(goal) < 0.04:
		return Vector3.ZERO
	# The direct sweep is both a fast path and a way to leave a completed detour.
	if _point_clear(context, goal) and _segment_clear(context, origin, goal):
		_path.assign([goal])
		_waypoint = 0
		_destination = goal
		_route_key = str(context.key)
		_planned_at = now
		_reachable = true
		_path_length = origin.distance_to(goal)
		_last_origin = origin
		return (goal - origin).normalized()
	var displaced := _last_origin.is_finite() and origin.distance_squared_to(_last_origin) > 9.0
	var needs_route := _route_key != str(context.key) or not _destination.is_finite() or goal.distance_to(_destination) > DESTINATION_REPLAN_DISTANCE or displaced or now < _planned_at or now - _planned_at >= ROUTE_REFRESH_SECONDS
	if needs_route:
		_path = _find_path(context, origin, goal)
		_waypoint = 0
		_destination = goal
		_route_key = str(context.key)
		_planned_at = now
		_reachable = not _path.is_empty()
		_path_length = _measure_path(origin, _path)
	_last_origin = origin
	if _path.is_empty():
		return Vector3.ZERO
	while _waypoint < _path.size() - 1 and origin.distance_to(_path[_waypoint]) < 0.48:
		_waypoint += 1
	# Look ahead only through a swept, fully clear segment; no corner cutting.
	var furthest := mini(_waypoint + 3, _path.size() - 1)
	for index in range(furthest, _waypoint, -1):
		if _segment_clear(context, origin, _path[index]):
			_waypoint = index
			break
	if not _segment_clear(context, origin, _path[_waypoint]):
		# A temporary displacement can put a retained waypoint behind a corner.
		# Replan once immediately instead of steering into it until the timer ends.
		# A newly added or moved wall must invalidate the shared terrain as well
		# as this route; otherwise A* would repeatedly reuse its old clear edge.
		_geometry_revision(body, true)
		context = _context(body, arena_limit)
		_route_key = str(context.key)
		_path = _find_path(context, origin, goal)
		_waypoint = 0
		_reachable = not _path.is_empty()
		_path_length = _measure_path(origin, _path)
		_planned_at = now
		if _path.is_empty():
			return Vector3.ZERO
	return (_path[_waypoint] - origin).normalized()


func route_distance(body: CollisionObject3D, destination: Vector3, now: float, arena_limit: float = 27.0) -> float:
	var context := _context(body, arena_limit)
	if context.is_empty() or not destination.is_finite():
		return INF
	var origin := _flat(body.global_position)
	# Unlike movement, scoring must reject goals outside the playable map.
	if absf(destination.x - arena_center.x) > arena_limit or absf(destination.z - arena_center.z) > arena_limit:
		return INF
	var goal := _flat(destination)
	if not _point_clear(context, goal):
		return INF
	if _segment_clear(context, origin, goal):
		return origin.distance_to(goal)
	var key := "%s/%s/%s" % [context.key, _cell(context, origin), _cell(context, goal)]
	var cached: Dictionary = _distance_cache.get(key, {})
	if not cached.is_empty() and now >= float(cached.at) and now - float(cached.at) < ROUTE_REFRESH_SECONDS:
		return float(cached.distance)
	var path := _find_path(context, origin, goal)
	var distance := _measure_path(origin, path)
	if _distance_cache.size() >= MAX_DISTANCE_CACHE:
		_distance_cache.clear()
	_distance_cache[key] = {"at": now, "distance": distance}
	return distance


func is_destination_clear(body: CollisionObject3D, destination: Vector3, arena_limit: float = 27.0) -> bool:
	var context := _context(body, arena_limit)
	return not context.is_empty() and destination.is_finite() and _point_clear(context, _flat(destination))


func is_segment_clear(body: CollisionObject3D, origin: Vector3, destination: Vector3, arena_limit: float = 27.0) -> bool:
	var context := _context(body, arena_limit)
	return not context.is_empty() and origin.is_finite() and destination.is_finite() and (_point_clear(context, _flat(destination)) or _physical_point_clear(context, _flat(destination))) and _segment_clear(context, _flat(origin), _flat(destination))


func get_debug_state() -> Dictionary:
	return {"reachable": _reachable, "waypoints": _path.size(), "waypoint": _waypoint, "path_length": _path_length, "expansions": _last_expansions, "destination": _destination}


func get_cache_stats() -> Dictionary:
	var cells := 0
	var edges := 0
	for grid in _shared_grids.values():
		cells += (grid.cells as Dictionary).size()
		edges += (grid.edges as Dictionary).size()
	return {"grids": _shared_grids.size(), "cells": cells, "edges": edges, "distance_entries": _distance_cache.size(), "geometry_worlds": _world_geometry.size()}


func _geometry_revision(body: CollisionObject3D, force: bool = false) -> int:
	var world_key := str(body.get_world_3d().get_rid().get_id())
	var now := float(Time.get_ticks_msec()) * 0.001
	var record: Dictionary = _world_geometry.get(world_key, {})
	if not force and not record.is_empty() and now - float(record.checked_at) < GEOMETRY_REFRESH_SECONDS:
		return int(record.revision)
	var scene := body.get_tree().current_scene
	var signature: Array = []
	if scene != null:
		for value in scene.find_children("*", "StaticBody3D", true, false):
			var solid := value as StaticBody3D
			if solid.collision_layer & 1 == 0 or solid.get_world_3d() != body.get_world_3d():
				continue
			for child in solid.get_children():
				var collision := child as CollisionShape3D
				if collision == null or collision.shape == null:
					continue
				var dimensions: Variant = collision.shape.get_rid()
				if collision.shape is BoxShape3D:
					dimensions = (collision.shape as BoxShape3D).size
				elif collision.shape is CapsuleShape3D:
					var capsule := collision.shape as CapsuleShape3D
					dimensions = Vector2(capsule.radius, capsule.height)
				elif collision.shape is SphereShape3D:
					dimensions = (collision.shape as SphereShape3D).radius
				elif collision.shape is CylinderShape3D:
					var cylinder := collision.shape as CylinderShape3D
					dimensions = Vector2(cylinder.radius, cylinder.height)
				signature.append([solid.get_instance_id(), collision.disabled, collision.global_transform, dimensions])
	var fingerprint := signature.hash()
	var revision := int(record.get("revision", 0))
	if not record.is_empty() and fingerprint != int(record.fingerprint):
		revision += 1
		for key in _shared_grids.keys():
			if str(key).begins_with(world_key + "/"):
				_shared_grids.erase(key)
	if not _world_geometry.has(world_key) and _world_geometry.size() >= MAX_SHARED_GRIDS:
		_world_geometry.erase(_world_geometry.keys()[0])
	_world_geometry[world_key] = {"fingerprint": fingerprint, "revision": revision, "checked_at": now}
	return revision


func _context(body: CollisionObject3D, arena_limit: float) -> Dictionary:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d() == null or arena_limit < 1.0:
		return {}
	var terrain := ARENA_TRAVERSAL.terrain(body)
	if terrain != null:
		arena_limit = minf(arena_limit, float(terrain.call("navigation_extent")))
	var collision: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			collision = child as CollisionShape3D
			break
	if collision == null or collision.shape == null:
		return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.transform = collision.global_transform
	# Projectiles, robots and effects are deliberately excluded from the shared
	# terrain map. The controller handles crowds, threats and temporary shields.
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var excluded: Array[RID] = [body.get_rid()]
	excluded.append_array(ARENA_TRAVERSAL.exclusions(body))
	var scene := body.get_tree().current_scene
	if scene != null and scene.has_meta("arena_floor_rid"):
		excluded.append(scene.get_meta("arena_floor_rid"))
	query.exclude = excluded
	# Godot's motion sweep does not expand all shape types by query.margin.
	# Inflate the actual query resource so occupancy and sweeps agree at corners.
	query.margin = 0.0
	var shape_signature: String
	if collision.shape is CapsuleShape3D:
		var capsule := collision.shape as CapsuleShape3D
		shape_signature = "capsule/%.3f/%.3f/%s" % [capsule.radius, capsule.height, collision.global_basis.get_scale()]
	else:
		# Current robots use capsules. Other shapes remain correct and private.
		shape_signature = "%s/%s" % [collision.shape.get_rid().get_id(), collision.global_basis]
	var offset := collision.global_position - body.global_position
	var revision := _geometry_revision(body)
	var key := "%s/%s/%s/%.2f/%s/%s" % [body.get_world_3d().get_rid().get_id(), revision, shape_signature, arena_limit, offset, arena_center]
	if terrain != null:
		key += "/terrain:%d" % terrain.get_instance_id()
	if not _shared_grids.has(key):
		if _shared_grids.size() >= MAX_SHARED_GRIDS:
			var oldest_key := ""
			var oldest_time := INF
			for grid_key in _shared_grids:
				var candidate_time := float(_shared_grids[grid_key].touched)
				if candidate_time < oldest_time:
					oldest_time = candidate_time
					oldest_key = str(grid_key)
			_shared_grids.erase(oldest_key)
		_shared_grids[key] = {"cells": {}, "edges": {}, "touched": 0.0, "shape": _clearance_shape(collision.shape)}
	var grid: Dictionary = _shared_grids[key]
	query.shape = grid.shape
	grid.touched = Time.get_ticks_msec() * 0.001
	var departure_query := PhysicsShapeQueryParameters3D.new()
	departure_query.shape = collision.shape
	departure_query.transform = collision.global_transform
	departure_query.collision_mask = 1
	departure_query.collide_with_areas = false
	departure_query.exclude = excluded
	departure_query.margin = DEPARTURE_MARGIN
	return {"key": key, "query": query, "departure_query": departure_query, "offset": offset, "space": body.get_world_3d().direct_space_state, "limit": arena_limit, "center": arena_center, "size": int(floor(arena_limit * 2.0 / CELL_SIZE)) + 1, "grid": grid, "terrain": ARENA_TRAVERSAL.terrain(body)}


func _clearance_shape(original: Shape3D) -> Shape3D:
	var shape := original.duplicate() as Shape3D
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		capsule.height += CLEARANCE_MARGIN * 2.0
		capsule.radius += CLEARANCE_MARGIN
	elif shape is SphereShape3D:
		(shape as SphereShape3D).radius += CLEARANCE_MARGIN
	elif shape is BoxShape3D:
		(shape as BoxShape3D).size += Vector3.ONE * CLEARANCE_MARGIN * 2.0
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		cylinder.height += CLEARANCE_MARGIN * 2.0
		cylinder.radius += CLEARANCE_MARGIN
	return shape


func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


func _clamp_point(value: Vector3, limit: float) -> Vector3:
	return Vector3(clampf(value.x, arena_center.x - limit, arena_center.x + limit), 0.0, clampf(value.z, arena_center.z - limit, arena_center.z + limit))


func _cell(context: Dictionary, point: Vector3) -> Vector2i:
	var local := point - (context.center as Vector3)
	return Vector2i(roundi((local.x + float(context.limit)) / CELL_SIZE), roundi((local.z + float(context.limit)) / CELL_SIZE))


func _point(context: Dictionary, cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * CELL_SIZE - float(context.limit), 0.0, float(cell.y) * CELL_SIZE - float(context.limit)) + (context.center as Vector3)


func _point_clear(context: Dictionary, point: Vector3) -> bool:
	var local := point - (context.center as Vector3)
	if absf(local.x) > float(context.limit) or absf(local.z) > float(context.limit):
		return false
	var terrain: Node3D = context.terrain
	if terrain != null and not bool(terrain.call("segment_walkable", point, point)):
		return false
	var query: PhysicsShapeQueryParameters3D = context.query
	query.transform.origin = _surface_point(context, point) + (context.offset as Vector3)
	query.motion = Vector3.ZERO
	return (context.space as PhysicsDirectSpaceState3D).intersect_shape(query, 1).is_empty()


func _physical_point_clear(context: Dictionary, point: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = context.departure_query
	query.transform.origin = _surface_point(context, point) + (context.offset as Vector3)
	query.motion = Vector3.ZERO
	return (context.space as PhysicsDirectSpaceState3D).intersect_shape(query, 1).is_empty()


func _segment_clear(context: Dictionary, origin: Vector3, destination: Vector3) -> bool:
	var surface: Node3D = context.terrain
	if surface != null:
		if not bool(surface.call("segment_walkable", origin, destination)):
			return false
		var steps := maxi(1, ceili(origin.distance_to(destination) / 0.4))
		var height_query: PhysicsShapeQueryParameters3D = context.departure_query
		for index in range(steps):
			var start := _surface_point(context, origin.lerp(destination, float(index) / steps))
			var end := _surface_point(context, origin.lerp(destination, float(index + 1) / steps))
			height_query.transform.origin = start + (context.offset as Vector3)
			height_query.motion = end - start
			if not (context.space as PhysicsDirectSpaceState3D).intersect_shape(height_query, 1).is_empty():
				return false
			var cast := (context.space as PhysicsDirectSpaceState3D).cast_motion(height_query)
			if cast.size() < 2 or cast[0] < 0.999:
				return false
		return true
	var local := destination - (context.center as Vector3)
	if absf(local.x) > float(context.limit) or absf(local.z) > float(context.limit):
		return false
	var query: PhysicsShapeQueryParameters3D = context.query
	query.transform.origin = origin + (context.offset as Vector3)
	query.motion = Vector3.ZERO
	if not (context.space as PhysicsDirectSpaceState3D).intersect_shape(query, 1).is_empty():
		# A robot pushed close to cover may be inside our extra route padding,
		# while its actual collision volume remains clear. Give it a short safe
		# departure to the clearance grid instead of freezing beside the wall.
		# Limiting this to local connections also prevents cast_motion (which
		# ignores initial overlaps) from treating the wall as a clear shortcut.
		if origin.distance_squared_to(destination) > 9.0 or not _physical_point_clear(context, origin):
			return false
		query = context.departure_query
		query.transform.origin = origin + (context.offset as Vector3)
	query.motion = destination - origin
	var sweep := (context.space as PhysicsDirectSpaceState3D).cast_motion(query)
	return sweep.size() >= 2 and sweep[0] >= 0.999


func _surface_point(context: Dictionary, point: Vector3) -> Vector3:
	var surface: Node3D = context.terrain
	if surface != null:
		point.y = float(surface.call("height_at", point))
	return point


func _cell_clear(context: Dictionary, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(context.size) or cell.y >= int(context.size):
		return false
	var cells: Dictionary = context.grid.cells
	if not cells.has(cell):
		cells[cell] = _point_clear(context, _point(context, cell))
	return bool(cells[cell])


func _edge_clear(context: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	var edge_key := Vector4i(from.x, from.y, to.x, to.y) if from.x < to.x or (from.x == to.x and from.y < to.y) else Vector4i(to.x, to.y, from.x, from.y)
	var edges: Dictionary = context.grid.edges
	if not edges.has(edge_key):
		edges[edge_key] = _segment_clear(context, _point(context, from), _point(context, to))
	return bool(edges[edge_key])


func _connected_cell(context: Dictionary, point: Vector3) -> Vector2i:
	var center := _cell(context, point)
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for x in range(center.x - 2, center.x + 3):
		for z in range(center.y - 2, center.y + 3):
			var candidate := Vector2i(x, z)
			var distance := _point(context, candidate).distance_squared_to(point)
			if distance >= best_distance or not _cell_clear(context, candidate):
				continue
			if _segment_clear(context, point, _point(context, candidate)):
				best = candidate
				best_distance = distance
	return best


func _find_path(context: Dictionary, origin: Vector3, destination: Vector3) -> Array[Vector3]:
	_last_expansions = 0
	var result: Array[Vector3] = []
	if (not _point_clear(context, origin) and not _physical_point_clear(context, origin)) or not _point_clear(context, destination):
		return result
	var start := _connected_cell(context, origin)
	var goal := _connected_cell(context, destination)
	if start.x < 0 or goal.x < 0:
		return result
	var open: Array = []
	_heap_push(open, [start, _heuristic(start, goal)])
	var scores: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	var closed: Dictionary = {}
	var found := false
	while not open.is_empty() and _last_expansions < MAX_SEARCH_EXPANSIONS:
		var entry: Array = _heap_pop(open)
		var current: Vector2i = entry[0]
		if closed.has(current):
			continue
		if current == goal:
			found = true
			break
		closed[current] = true
		_last_expansions += 1
		for offset in NEIGHBOURS:
			var next: Vector2i = current + offset
			if closed.has(next) or not _cell_clear(context, next):
				continue
			# A diagonal must have clear orthogonal neighbours as well as a sweep.
			# This protects thin walls and scaled actors in narrow intersections.
			if offset.x != 0 and offset.y != 0 and (not _cell_clear(context, current + Vector2i(offset.x, 0)) or not _cell_clear(context, current + Vector2i(0, offset.y))):
				continue
			if not _edge_clear(context, current, next):
				continue
			var next_score := float(scores[current]) + (1.41421356237 if offset.x != 0 and offset.y != 0 else 1.0)
			if next_score >= float(scores.get(next, INF)):
				continue
			scores[next] = next_score
			previous[next] = current
			_heap_push(open, [next, next_score + _heuristic(next, goal)])
	if not found:
		return result
	var route: Array[Vector3] = [destination]
	var cursor := goal
	while cursor != start:
		route.push_front(_point(context, cursor))
		cursor = previous[cursor]
	route.push_front(_point(context, start))
	# Greedy swept smoothing keeps turns wide enough for the actual capsule.
	var anchor := origin
	var index := 0
	while index < route.size():
		var furthest := index
		for candidate in range(route.size() - 1, index, -1):
			if _segment_clear(context, anchor, route[candidate]):
				furthest = candidate
				break
		if anchor.distance_squared_to(route[furthest]) > 0.001:
			result.append(route[furthest])
		anchor = route[furthest]
		index = furthest + 1
	return result


func _heuristic(from: Vector2i, to: Vector2i) -> float:
	var x := absi(from.x - to.x)
	var y := absi(from.y - to.y)
	return float(maxi(x, y)) + 0.41421356237 * float(mini(x, y))


func _measure_path(origin: Vector3, path: Array[Vector3]) -> float:
	if path.is_empty():
		return INF
	var distance := 0.0
	var previous := origin
	for point in path:
		distance += previous.distance_to(point)
		previous = point
	return distance


func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if float(heap[parent][1]) <= float(entry[1]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry


func _heap_pop(heap: Array) -> Array:
	var first: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return first
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and float(heap[child + 1][1]) < float(heap[child][1]):
			child += 1
		if float(last[1]) <= float(heap[child][1]):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return first
