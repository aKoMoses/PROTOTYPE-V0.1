extends CanvasLayer

## This HUD stores observations, never the current position of a hidden actor.
## The amber marker is a fading memory with growing uncertainty, not a radar.
const HUD_LAYOUT := preload("res://scripts/hud_layout.gd")
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")
const CYAN := Color("#42d9e5")
const RED := Color("#f07869")
const AMBER := Color("#efb565")
const ARENA_HALF_EXTENT := 29.0
const MEMORY_SECONDS := 7.0
const PANEL_SIZE := Vector2(208.0, 208.0)

var _scene: Node3D
var _player: Node3D
var _target: Node3D
var _panel: Control
var _map: Control
var _known := false
var _opponent_visible := false
var _active := false
var _network_round := false
var _age := 0.0
var _last_position := Vector3.ZERO
var _player_position := Vector3.ZERO
var _target_epoch := -1
var _player_epoch := -1
var _visibility_weight := 0.0
var _vision_radius := VISIBILITY_STATE.DEFAULT_VISION_RADIUS
var _vision_fade_width := VISIBILITY_STATE.DEFAULT_VISION_FADE_WIDTH
var _clock := 0.0
var _obstacle_polygons: Array[PackedVector2Array] = []
var _walkable_polygons: Array[PackedVector2Array] = []
var _ramp_markers: Array[Dictionary] = []
var _bush_markers: Array[Dictionary] = []
var _repair_positions: Array[Vector3] = []


class SightPanel extends Control:

	func _draw() -> void:
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color("#10191bea")
		plate.border_color = Color("#526267b0")
		plate.set_border_width_all(1)
		plate.set_corner_radius_all(8)
		draw_style_box(plate, Rect2(Vector2.ZERO, size))


class ArenaMap extends Control:
	var tracker


	func _draw() -> void:
		if tracker != null:
			tracker._draw_map(self)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	_panel = SightPanel.new()
	_panel.name = "SightPanel"
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var arena_map := ArenaMap.new()
	arena_map.tracker = self
	_map = arena_map
	_map.name = "ArenaMap"
	_map.position = Vector2(13.0, 13.0)
	_map.size = Vector2(182.0, 182.0)
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_map)
	_update_layout()
	get_viewport().size_changed.connect(_update_layout)


func configure(scene: Node3D, player: Node3D, target: Node3D, network_round: bool = false) -> void:
	_disconnect_death(_player)
	_disconnect_death(_target)
	_scene = scene
	_player = player
	_target = target
	_network_round = network_round
	_connect_death(_player)
	_connect_death(_target)
	_target_epoch = _read_epoch(_target)
	_player_epoch = _read_epoch(_player)
	reset_tracking()
	_cache_obstacles()


func _connect_death(actor: Node) -> void:
	if is_instance_valid(actor) and actor.has_signal("died") and not actor.is_connected("died", _on_actor_died):
		actor.connect("died", _on_actor_died)


func _disconnect_death(actor: Node) -> void:
	if is_instance_valid(actor) and actor.has_signal("died") and actor.is_connected("died", _on_actor_died):
		actor.disconnect("died", _on_actor_died)


func _on_actor_died() -> void:
	reset_tracking()
	_active = false
	if _panel != null:
		_panel.visible = false


func reset_tracking() -> void:
	_known = false
	_opponent_visible = false
	_age = 0.0
	_last_position = Vector3.ZERO
	_visibility_weight = 0.0
	if _map != null:
		_map.queue_redraw()


func clear_tracking() -> void:
	reset_tracking()


func get_tracking_state() -> Dictionary:
	return {
		"known": _known,
		"visible": _opponent_visible,
		"active": _active,
		"age": _age,
		"last_position": _last_position,
		"expires_after": MEMORY_SECONDS,
		"uncertainty": _memory_uncertainty(),
	}


func _read_epoch(actor: Node) -> int:
	return int(actor.call("get_visibility_epoch")) if is_instance_valid(actor) and actor.has_method("get_visibility_epoch") else -1


func _process(delta: float) -> void:
	_clock += delta
	if not is_instance_valid(_scene) or not is_instance_valid(_player) or not is_instance_valid(_target):
		_suspend(true)
		return
	var target_epoch := _read_epoch(_target)
	var player_epoch := _read_epoch(_player)
	if target_epoch != _target_epoch or player_epoch != _player_epoch:
		reset_tracking()
		_target_epoch = target_epoch
		_player_epoch = player_epoch
	# Network rounds share the same actors but do not set Main.duel_active.
	var duel := bool(_scene.get("duel_active")) if "duel_active" in _scene else false
	var network_round := _network_round or (bool(_target.get("network_proxy")) if "network_proxy" in _target else false)
	if not duel and not network_round:
		_suspend(true)
		return
	if _actor_dead(_player) or _actor_dead(_target):
		_suspend(true)
		return
	# Freeze the memory clock while paused or during round transitions. Epochs
	# above still clear old-round observations, even with a paused scene tree.
	if get_tree().paused or not _player.has_method("is_gameplay_enabled") or not bool(_player.call("is_gameplay_enabled")):
		_suspend(false)
		return
	_active = true
	_panel.visible = true
	_player_position = _player.global_position
	_vision_radius = maxf(0.1, VISIBILITY_STATE.observer_radius(_player))
	_vision_fade_width = clampf(VISIBILITY_STATE.observer_fade_width(_player), 0.0, _vision_radius)
	_visibility_weight = clampf(float(_target.call("get_visibility_weight", _player)), 0.0, 1.0) if _target.has_method("get_visibility_weight") else 0.0
	_opponent_visible = _visibility_weight > 0.01
	if _opponent_visible:
		# This is the only target-position read. A lost or initially concealed
		# fighter cannot move the remembered marker or its uncertainty centre.
		_last_position = _target.global_position
		_known = true
		_age = 0.0
	elif _known:
		_age += maxf(delta, 0.0)
		if _age >= MEMORY_SECONDS:
			reset_tracking()
	_map.queue_redraw()


func _actor_dead(actor: Node) -> bool:
	return actor.has_method("is_real_dead") and bool(actor.call("is_real_dead"))


func _suspend(clear_memory: bool) -> void:
	_active = false
	if clear_memory:
		reset_tracking()
	if _panel != null:
		_panel.visible = false


func _update_layout() -> void:
	if _panel == null or not is_inside_tree():
		return
	var safe: Rect2 = HUD_LAYOUT.safe_rect(get_viewport())
	var factor := clampf(minf(safe.size.y / 720.0, safe.size.x / 1050.0), 0.60, 1.0)
	_panel.scale = Vector2.ONE * factor
	var margin := 16.0 * factor
	# Leave the pause/quit controls above the map, including touch layouts.
	var top := maxf(82.0 * factor, 72.0)
	_panel.position = Vector2(safe.end.x - PANEL_SIZE.x * factor - margin, safe.position.y + top)


func _cache_obstacles() -> void:
	_obstacle_polygons.clear()
	_walkable_polygons.clear()
	_ramp_markers.clear()
	_bush_markers.clear()
	_repair_positions.clear()
	if not is_instance_valid(_scene):
		return
	var test_arena: Node3D = _scene.get_node_or_null("TestArena") if _scene.get("arena_variant") == "test" else null
	var floors: Array = test_arena.get("surfaces") if test_arena != null else []
	if test_arena != null:
		# Cache fixed map features only. Pickup availability and concealed actor
		# positions never drive these markers, so they cannot act as a radar.
		for bush in get_tree().get_nodes_in_group("bush_placeholder"):
			if test_arena.is_ancestor_of(bush):
				_bush_markers.append({"position": bush.get_meta("bush_center", bush.global_position), "radius": float(bush.get_meta("bush_radius", 0.0))})
		for kit in get_tree().get_nodes_in_group("repair_kits"):
			if test_arena.is_ancestor_of(kit):
				_repair_positions.append(kit.global_position)
	# Arena geometry is static. Read it once; actor nodes are never enumerated.
	var blockers: Array = []
	if "_arena_blockers" in _scene:
		blockers.assign(_scene.get("_arena_blockers"))
	for blocker in blockers:
		if not is_instance_valid(blocker) or bool(blocker.get_meta("invisible_safety_limit", false)):
			continue
		for child in blocker.get_children():
			if not child is CollisionShape3D:
				continue
			var polygon := PackedVector2Array()
			if child.shape is BoxShape3D:
				var shape_size: Vector3 = child.shape.size
				for sign_pair in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
					var point: Vector3 = child.global_transform * Vector3(sign_pair.x * shape_size.x * 0.5, 0.0, sign_pair.y * shape_size.z * 0.5)
					polygon.append(Vector2(point.x, point.z))
			elif child.shape is ConvexPolygonShape3D and floors.has(blocker):
				var high_points := Vector2.ZERO
				var high_count := 0
				var highest := -INF
				for vertex in child.shape.points:
					var point: Vector3 = child.global_transform * vertex
					polygon.append(Vector2(point.x, point.z))
					if point.y > highest + 0.001:
						highest = point.y
						high_points = Vector2.ZERO
						high_count = 0
					if absf(point.y - highest) < 0.001:
						high_points += Vector2(point.x, point.z)
						high_count += 1
				polygon = Geometry2D.convex_hull(polygon)
				if polygon.size() > 1 and polygon[0] == polygon[-1]:
					polygon.remove_at(polygon.size() - 1)
				var centre := Vector2.ZERO
				for point in polygon:
					centre += point
				centre /= maxf(1, polygon.size())
				_ramp_markers.append({"position": Vector3(centre.x, 0, centre.y), "direction": (high_points / maxf(1, high_count) - centre).normalized()})
			if polygon.size() < 3:
				continue
			if floors.has(blocker):
				_walkable_polygons.append(polygon)
			else:
				_obstacle_polygons.append(polygon)


func _map_point(world: Vector3, dimensions: Vector2) -> Vector2:
	var extents := _map_half_extents()
	var rect := _map_rect(dimensions)
	return (Vector2(world.x, world.z) + extents) / (extents * 2.0) * rect.size + rect.position


func _map_extent() -> float:
	return _map_half_extents().x


func _map_half_extents() -> Vector2:
	if is_instance_valid(_scene) and _scene.get("arena_variant") == "test":
		var arena := _scene.get_node_or_null("TestArena")
		if arena != null:
			return arena.call("map_half_extents")
	return Vector2.ONE * ARENA_HALF_EXTENT


func _map_rect(dimensions: Vector2) -> Rect2:
	var span := _map_half_extents() * 2.0
	var scale_factor := minf(dimensions.x / span.x, dimensions.y / span.y)
	var size := span * scale_factor
	return Rect2((dimensions - size) * 0.5, size)


func _memory_uncertainty() -> float:
	return minf(11.0, 1.5 + _age * 1.55) if _known and not _opponent_visible else 0.0


func _memory_alpha() -> float:
	return 1.0 - smoothstep(2.0, MEMORY_SECONDS, _age)


func _dashed_circle(canvas: Control, centre: Vector2, radius: float, tint: Color, width: float = 1.0) -> void:
	for index in range(24):
		var start := float(index) * TAU / 24.0
		canvas.draw_arc(centre, radius, start, start + TAU / 39.0, 4, tint, width, true)


func _draw_map(canvas: Control) -> void:
	var dimensions := canvas.size
	var extent := _map_extent()
	var map_rect := _map_rect(dimensions)
	var pixels_per_unit := map_rect.size.x / (extent * 2.0)
	canvas.draw_rect(Rect2(Vector2.ZERO, dimensions), Color("#182225"))
	for index in range(1, 6):
		var offset := map_rect.size * float(index) / 6.0
		canvas.draw_line(map_rect.position + Vector2(offset.x, 0.0), map_rect.position + Vector2(offset.x, map_rect.size.y), Color("#8ebbc00c"), 1.0)
		canvas.draw_line(map_rect.position + Vector2(0.0, offset.y), map_rect.position + Vector2(map_rect.size.x, offset.y), Color("#8ebbc00c"), 1.0)
	var player_point := _map_point(_player_position, dimensions)
	var inner_radius := maxf(0.0, _vision_radius - _vision_fade_width)
	# Layered low-opacity discs express the same soft radial boundary as the
	# fighter fade; their centre is the player's live, locally known position.
	for index in range(10):
		var radius := lerpf(_vision_radius, inner_radius, float(index) / 9.0)
		canvas.draw_circle(player_point, radius * pixels_per_unit, Color(CYAN, 0.008))
	canvas.draw_circle(player_point, inner_radius * pixels_per_unit, Color(CYAN, 0.035))
	canvas.draw_arc(player_point, inner_radius * pixels_per_unit, 0.0, TAU, 64, Color(CYAN, 0.16), 1.0, true)
	_dashed_circle(canvas, player_point, _vision_radius * pixels_per_unit, Color(CYAN, 0.25))
	for polygon in _walkable_polygons:
		var points := PackedVector2Array()
		for point in polygon:
			points.append(_map_point(Vector3(point.x, 0, point.y), dimensions))
		canvas.draw_colored_polygon(points, Color("#70868c66"))
		points.append(points[0])
		canvas.draw_polyline(points, Color("#a4b5b470"), 1.0, true)
	for polygon in _obstacle_polygons:
		var points := PackedVector2Array()
		for point in polygon:
			points.append(_map_point(Vector3(point.x, 0, point.y), dimensions))
		canvas.draw_colored_polygon(points, Color("#485055"))
		points.append(points[0])
		canvas.draw_polyline(points, Color("#7f8d903a"), 1.0, true)
	_draw_landmarks(canvas, pixels_per_unit)
	canvas.draw_rect(Rect2(map_rect.position + Vector2.ONE, map_rect.size - Vector2.ONE * 2.0), Color("#7b929658"), false, 1.0)
	if _known:
		var opponent_point := _map_point(_last_position, dimensions)
		if _opponent_visible:
			canvas.draw_circle(opponent_point, 6.5, Color(RED, _visibility_weight * 0.16))
			canvas.draw_circle(opponent_point, 3.3, Color(RED, _visibility_weight))
			canvas.draw_arc(opponent_point, 5.5, 0.0, TAU, 24, Color(RED, _visibility_weight * 0.7), 1.0, true)
		else:
			var alpha := _memory_alpha()
			var uncertainty_radius := _memory_uncertainty() * pixels_per_unit
			canvas.draw_circle(opponent_point, uncertainty_radius, Color(AMBER, alpha * 0.065))
			_dashed_circle(canvas, opponent_point, uncertainty_radius, Color(AMBER, alpha * 0.5))
			canvas.draw_arc(opponent_point, 5.0 + sin(_clock * 3.0) * 0.5, 0.0, TAU, 28, Color(AMBER, alpha), 1.7, true)
			canvas.draw_line(opponent_point + Vector2(-2.0, 0.0), opponent_point + Vector2(2.0, 0.0), Color(AMBER, alpha), 1.0)
			canvas.draw_line(opponent_point + Vector2(0.0, -2.0), opponent_point + Vector2(0.0, 2.0), Color(AMBER, alpha), 1.0)
			canvas.draw_arc(opponent_point, 8.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(1.0 - _age / MEMORY_SECONDS, 0.001, 1.0), 32, Color(AMBER, alpha * 0.7), 1.3, true)
	var aim := Vector3.FORWARD
	if is_instance_valid(_player) and "aim_direction" in _player:
		aim = _player.get("aim_direction")
	var heading := Vector2(aim.x, aim.z).normalized()
	if heading.length_squared() < 0.1:
		heading = Vector2.UP
	var side := heading.orthogonal()
	canvas.draw_circle(player_point, 7.0, Color(CYAN, 0.16))
	canvas.draw_colored_polygon(PackedVector2Array([player_point + heading * 6.0, player_point - heading * 3.0 + side * 3.2, player_point - heading * 3.0 - side * 3.2]), CYAN)


func _draw_landmarks(canvas: Control, pixels_per_unit: float) -> void:
	for bush in _bush_markers:
		var centre := _map_point(bush.position, canvas.size)
		var radius := float(bush.radius) * pixels_per_unit
		canvas.draw_circle(centre, radius, Color("#91a46f50"))
		canvas.draw_arc(centre, radius, 0, TAU, 24, Color("#a6b989a0"), 1.0, true)
	for ramp in _ramp_markers:
		var centre := _map_point(ramp.position, canvas.size)
		var heading: Vector2 = ramp.direction
		var tip := centre + heading * 3.8
		var tint := Color("#d8cfb8bd")
		canvas.draw_line(centre - heading * 3.8, tip, tint, 1.2, true)
		for side in [-1.0, 1.0]:
			canvas.draw_line(tip, tip - heading * 2.8 + heading.orthogonal() * side * 2.4, tint, 1.2, true)
	for position in _repair_positions:
		var centre := _map_point(position, canvas.size)
		canvas.draw_rect(Rect2(centre - Vector2.ONE * 4.5, Vector2.ONE * 9), Color("#172b29"))
		canvas.draw_rect(Rect2(centre - Vector2.ONE * 4.5, Vector2.ONE * 9), Color("#85b3a7a0"), false, 1.0)
		canvas.draw_line(centre - Vector2(2.6, 0), centre + Vector2(2.6, 0), Color("#b9d9c4"), 1.8)
		canvas.draw_line(centre - Vector2(0, 2.6), centre + Vector2(0, 2.6), Color("#b9d9c4"), 1.8)
