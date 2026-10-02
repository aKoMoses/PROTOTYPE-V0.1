extends RefCounted

## Destination selection and particle-only transit. The actor stays at its
## departure point until arrival; its body and all attached visuals disappear.
const DATA := preload("res://scripts/combat_data.gd")
const TERRAIN := preload("res://scripts/arena_traversal.gd")
const TINT := Color("#a996ff")
var aiming := false
var travelling := false
var touch_owned := false
var destination := Vector3.ZERO
var origin := Vector3.ZERO
var remaining := 0.0
var serial := 0
var _completed_serial := 0
var _action_token := 0
var _touch_vector := Vector2.ZERO
var _has_touch_vector := false
var _requested_destination := Vector3.ZERO
var _old_layer := 0
var _old_mask := 0
var _old_visible := true
var _preview: Node3D
var _range_ring: MeshInstance3D
var _target_ring: MeshInstance3D
var _target_disc: MeshInstance3D
var _caption: Label3D
var _flight: Node3D
var _particles: Array[MeshInstance3D] = []
var _range_center := Vector3.INF
var _target_center := Vector3.INF


func begin(actor: CharacterBody3D, from_touch: bool = false) -> bool:
	if aiming or travelling or actor.call("_action_incapacitated") or actor.get("_dash_active") or actor.get("_pelto_pull_active") or not actor.call("_module_ready", "eclipse"):
		return false
	_action_token = int(actor.call("_try_begin_module_action", "eclipse"))
	if _action_token == 0:
		return false
	aiming = true
	touch_owned = from_touch
	_has_touch_vector = false
	destination = actor.global_position + actor.get("aim_direction") * float(DATA.MODULE_DEFINITIONS.eclipse.max_range)
	_build_preview(actor)
	update_aim(actor)
	return true


func set_touch_vector(actor: CharacterBody3D, value: Vector2) -> void:
	if not aiming or not touch_owned or not value.is_finite():
		return
	_touch_vector = value.limit_length(1.0)
	_has_touch_vector = true
	update_aim(actor)


func update_aim(actor: CharacterBody3D) -> void:
	if not aiming:
		return
	var max_range := float(DATA.MODULE_DEFINITIONS.eclipse.max_range)
	var offset: Vector3 = actor.get("aim_direction") * max_range
	if touch_owned:
		if _has_touch_vector:
			offset = actor.call("_camera_relative_direction", _touch_vector) * max_range * _touch_vector.length()
	else:
		var camera := actor.get_viewport().get_camera_3d()
		if camera != null:
			var screen := actor.get_viewport().get_mouse_position()
			var ray := camera.project_ray_normal(screen)
			var start := camera.project_ray_origin(screen)
			if absf(ray.y) > 0.001:
				var distance := (actor.global_position.y - start.y) / ray.y
				if distance > 0.0:
					offset = start + ray * distance - actor.global_position
					if TERRAIN.terrain(actor) != null:
						offset = pointer_destination(actor, start, ray) - actor.global_position
	var sticks := Input.get_connected_joypads()
	if not touch_owned and not sticks.is_empty():
		var stick := Vector2(Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_Y)).limit_length(1.0)
		if stick.length() > 0.15:
			offset = actor.call("_camera_relative_direction", stick) * max_range * stick.length()
	offset.y = 0.0
	_requested_destination = surface_destination(actor, actor.global_position + offset.limit_length(max_range))
	destination = resolve_destination(actor, _requested_destination)
	if offset.length_squared() > 0.01:
		actor.call("_set_aim_direction", offset.normalized())
	var valid := destination.is_finite()
	if not valid:
		destination = _requested_destination
	var color := TINT if valid else Color("#ff635d")
	_range_ring.global_position = actor.global_position + Vector3.UP * 0.045
	_target_ring.global_position = destination + Vector3.UP * 0.08
	_target_disc.global_position = destination + Vector3.UP * 0.06
	_update_surface_preview(actor)
	_caption.global_position = destination + Vector3.UP * 0.75
	_caption.text = "ÉCLIPSE · RELÂCHER" if valid else "ARRIVÉE BLOQUÉE"
	_caption.modulate = color
	_target_ring.material_override.albedo_color = Color(color, 0.95)
	_target_disc.material_override.albedo_color = Color(color, 0.13)


func release(actor: CharacterBody3D) -> bool:
	if not aiming:
		return false
	update_aim(actor)
	var at := _requested_destination
	var accepted := bool(actor.call("_perform_eclipse", at))
	if not accepted:
		cancel(actor)
	return accepted


func depart(actor: CharacterBody3D, at: Vector3, from_snapshot: bool = false) -> bool:
	if travelling or not at.is_finite() or (TERRAIN.terrain(actor) == null and absf(at.y - actor.global_position.y) > 0.1) or actor.call("_action_incapacitated") or actor.get("_dash_active") or actor.get("_pelto_pull_active") or not actor.call("_module_ready", "eclipse"):
		return false
	# Validate the requested cast, not the exit: obstacles can extend its range.
	if not from_snapshot and cast_distance(actor, at) > float(DATA.MODULE_DEFINITIONS.eclipse.max_range) + 0.05:
		return false
	var arrival := resolve_destination(actor, at)
	if not arrival.is_finite():
		return false
	if not aiming:
		_action_token = int(actor.call("_try_begin_module_action", "eclipse"))
	if _action_token == 0:
		return false
	aiming = false
	touch_owned = false
	_free_visuals()
	serial += 1
	origin = actor.global_position
	destination = arrival
	remaining = float(DATA.MODULE_DEFINITIONS.eclipse.travel_duration)
	travelling = true
	_old_layer = actor.collision_layer
	_old_mask = actor.collision_mask
	_old_visible = actor.visible
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.hide()
	actor.velocity = Vector3.ZERO
	actor.call("_mark_combat_event")
	actor.call("_start_module_cooldown", "eclipse", float(DATA.MODULE_DEFINITIONS.eclipse.cooldown))
	_build_flight(actor)
	return true


func update(actor: CharacterBody3D, delta: float) -> void:
	if aiming:
		if actor.call("_action_incapacitated") or (not touch_owned and Input.is_key_pressed(KEY_ESCAPE)):
			cancel(actor)
		else:
			update_aim(actor)
	if not travelling:
		return
	remaining = maxf(0.0, remaining - delta)
	var progress := 1.0 - remaining / float(DATA.MODULE_DEFINITIONS.eclipse.travel_duration)
	for index in range(_particles.size()):
		var phase := float(index) * 2.39996
		var t := clampf(progress - float(index % 7) * 0.022, 0.0, 1.0)
		var spread := sin(t * PI) * (0.15 + float(index % 5) * 0.08)
		_particles[index].global_position = origin.lerp(destination, t) + Vector3(cos(phase + t * 12.0) * spread, 0.8 + sin(phase + t * 9.0) * spread, sin(phase + t * 12.0) * spread)
	if remaining <= 0.0:
		arrive(actor)


func arrive(actor: CharacterBody3D) -> void:
	if not travelling:
		return
	var arrival := resolve_destination(actor, destination)
	var accepted := arrival.is_finite()
	actor.global_position = arrival if accepted else origin
	destination = actor.global_position
	_completed_serial = serial
	_restore_body(actor)
	_free_visuals()
	actor.call("_end_module_action", _action_token, "eclipse")
	_action_token = 0
	if accepted:
		burst(actor.get_tree().current_scene, actor.global_position)
		actor.call("_on_eclipse_arrived", origin, actor.global_position)


func cancel(actor: CharacterBody3D) -> void:
	if travelling:
		_completed_serial = serial
		_restore_body(actor)
	if aiming or _action_token != 0:
		actor.call("_end_module_action", _action_token, "eclipse")
	_action_token = 0
	aiming = false
	touch_owned = false
	_free_visuals()


func _restore_body(actor: CharacterBody3D) -> void:
	travelling = false
	remaining = 0.0
	actor.collision_layer = _old_layer
	actor.collision_mask = _old_mask
	actor.visible = _old_visible
	actor.velocity = Vector3.ZERO


func _free_visuals() -> void:
	for effect in [_preview, _flight]:
		if is_instance_valid(effect):
			effect.queue_free()
	_preview = null
	_flight = null
	_particles.clear()


static func fits(actor: CharacterBody3D, at: Vector3, check_range: bool = true) -> bool:
	if not at.is_finite() or (TERRAIN.terrain(actor) == null and absf(at.y - actor.global_position.y) > 0.1) or (check_range and cast_distance(actor, at) > float(DATA.MODULE_DEFINITIONS.eclipse.max_range) + 0.05):
		return false
	at = surface_destination(actor, at)
	# Use each arena's actual outer playable extent, with room for the body.
	var scene := actor.get_tree().current_scene
	var constants: Dictionary = scene.get_script().get_script_constant_map() if scene != null and scene.get_script() != null else {}
	var extent_x := float(constants.get("MAP_HALF_WIDTH", constants.get("ARENA_HALF_EXTENT", constants.get("ARENA_HALF", 23.0)))) - 1.0
	var extent_z := float(constants.get("MAP_HALF_DEPTH", extent_x + 1.0)) - 1.0
	if TERRAIN.terrain(actor) != null:
		extent_x = 13.4
		extent_z = 13.4
	elif scene != null and scene.has_meta("arena_half_size"):
		var half: Vector2 = scene.get_meta("arena_half_size")
		extent_x = half.x - 1.0
		extent_z = half.y - 1.0
	var outline: PackedVector2Array = scene.get_meta("arena_outline", PackedVector2Array()) if scene != null else PackedVector2Array()
	if outline.size() >= 3:
		if not _inside_arena_outline(actor, at, outline):
			return false
	elif absf(at.x) > extent_x or absf(at.z) > extent_z:
		return false
	for child in actor.get_children():
		if not child is CollisionShape3D or child.shape == null or child.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.transform.origin += at - actor.global_position
		# Floor contact is valid: leave a small clearance for the physics query.
		# The actor still arrives at ground height and solid cover stays blocking.
		query.transform.origin.y += 0.02
		query.collision_mask = 1 | 2 | 8
		query.margin = 0.0
		query.exclude = terrain_exclusions(actor)
		if not actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


static func resolve_destination(actor: CharacterBody3D, at: Vector3) -> Vector3:
	if not at.is_finite() or (TERRAIN.terrain(actor) == null and absf(at.y - actor.global_position.y) > 0.1):
		return Vector3.INF
	at = surface_destination(actor, at)
	if fits(actor, at, false):
		return at
	# Project onto all obstacle faces, then examine the nearest candidates first.
	# Repeating this for overlaps also handles adjoining cover and corners.
	var pending: Array[Vector3] = [at]
	var visited: Dictionary = {}
	var best := Vector3.INF
	var best_distance := INF
	for iteration in range(256):
		if pending.is_empty():
			break
		pending.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(at) < b.distance_squared_to(at))
		var candidate: Vector3 = surface_destination(actor, pending.pop_front())
		var key := candidate.snapped(Vector3.ONE * 0.001)
		if visited.has(key) or candidate.distance_squared_to(at) > best_distance:
			continue
		visited[key] = true
		if fits(actor, candidate, false):
			best = candidate
			best_distance = candidate.distance_squared_to(at)
			continue
		for child in actor.get_children():
			if not child is CollisionShape3D or child.shape == null or child.disabled:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = child.global_transform
			query.transform.origin += candidate - actor.global_position
			query.transform.origin.y += 0.02
			query.collision_mask = 1 | 2 | 8
			query.margin = 0.0
			query.exclude = terrain_exclusions(actor)
			for hit in actor.get_world_3d().direct_space_state.intersect_shape(query, 64):
				var body := hit.collider as CollisionObject3D
				if body == null:
					continue
				var owner := body.shape_find_owner(int(hit.shape))
				var collision := body.shape_owner_get_owner(owner) as CollisionShape3D
				if collision == null or collision.shape == null:
					continue
				_append_obstacle_exits(actor, candidate, collision, pending)
	if best.is_finite():
		return best
	# Non-box collision shapes use a physics-checked radial fallback.
	for index in range(96):
		var angle := TAU * float(index) / 96.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var distance := 0.1
		var blocked_distance := 0.0
		while distance <= 128.0:
			var candidate := surface_destination(actor, at + direction * distance)
			if fits(actor, candidate, false):
				for refinement in range(14):
					var middle := (blocked_distance + distance) * 0.5
					if fits(actor, at + direction * middle, false):
						distance = middle
					else:
						blocked_distance = middle
				candidate = surface_destination(actor, at + direction * distance)
				if candidate.distance_squared_to(at) < best_distance:
					best = candidate
					best_distance = candidate.distance_squared_to(at)
				break
			blocked_distance = distance
			distance *= 2.0
	return best


static func _append_obstacle_exits(actor: CharacterBody3D, at: Vector3, collision: CollisionShape3D, pending: Array[Vector3]) -> void:
	if collision.shape is CylinderShape3D or collision.shape is CapsuleShape3D or collision.shape is SphereShape3D:
		if absf(collision.global_basis.y.normalized().dot(Vector3.UP)) < 0.999 or absf(collision.global_basis.x.length() - collision.global_basis.z.length()) > 0.001:
			return
		var radius: float = collision.shape.radius * collision.global_basis.x.length()
		var offset := at - collision.global_position
		offset.y = 0.0
		var directions: Array[Vector3] = []
		if offset.length_squared() > 0.000001:
			directions.append(offset.normalized())
		for index in range(16):
			var angle := TAU * float(index) / 16.0
			directions.append(Vector3(cos(angle), 0.0, sin(angle)))
		for outward in directions:
			var candidate := collision.global_position + outward * (radius + _body_support(actor, outward) + 0.015)
			candidate.y = at.y
			pending.append(candidate)
		return
	var shape := collision.shape as BoxShape3D
	if shape == null or absf(collision.global_basis.y.normalized().dot(Vector3.UP)) < 0.999:
		return
	var half := shape.size * 0.5
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		var normal: Vector3 = (collision.global_basis * axis).normalized()
		for sign_value in [-1.0, 1.0]:
			var outward: Vector3 = normal * sign_value
			var face: Vector3 = collision.global_transform * (axis * half * sign_value)
			var clearance := outward.dot(face - at) + _body_support(actor, outward) + 0.015
			pending.append(at + outward * clearance)
	# Outside a box corner, the capsule can leave diagonally at a shorter distance.
	var local := collision.to_local(at)
	local.y = 0.0
	var closest := collision.to_global(local.clamp(-half, half))
	var offset := at - closest
	offset.y = 0.0
	if offset.length_squared() > 0.000001:
		var outward := offset.normalized()
		pending.append(at + outward * (_body_support(actor, outward) - offset.length() + 0.015))


static func _body_support(actor: CharacterBody3D, direction: Vector3) -> float:
	var support := 0.0
	for child in actor.get_children():
		if not child is CollisionShape3D or child.shape == null or child.disabled:
			continue
		var local: Vector3 = child.global_basis.transposed() * direction
		var shape_support: float
		if child.shape is CapsuleShape3D:
			shape_support = child.shape.radius * local.length() + maxf(0.0, child.shape.height * 0.5 - child.shape.radius) * absf(local.y)
		else:
			var bounds: AABB = child.shape.get_debug_mesh().get_aabb()
			shape_support = local.dot(bounds.get_center()) + local.abs().dot(bounds.size * 0.5)
		support = maxf(support, direction.dot(child.global_position - actor.global_position) + shape_support)
	return support


static func surface_destination(actor: CharacterBody3D, at: Vector3) -> Vector3:
	if at.is_finite() and TERRAIN.terrain(actor) != null:
		at.y = TERRAIN.height(actor, at)
	return at


static func cast_distance(actor: CharacterBody3D, at: Vector3) -> float:
	if TERRAIN.terrain(actor) != null:
		return Vector2(at.x - actor.global_position.x, at.z - actor.global_position.z).length()
	return at.distance_to(actor.global_position)


static func terrain_exclusions(actor: CharacterBody3D) -> Array[RID]:
	var excluded: Array[RID] = [actor.get_rid()]
	excluded.append_array(TERRAIN.exclusions(actor))
	var scene := actor.get_tree().current_scene
	if scene != null and scene.has_meta("arena_floor_rid"):
		excluded.append(scene.get_meta("arena_floor_rid"))
	return excluded


static func _inside_arena_outline(actor: CharacterBody3D, at: Vector3, outline: PackedVector2Array) -> bool:
	var point := Vector2(at.x, at.z)
	if not Geometry2D.is_point_in_polygon(point, outline):
		return false
	for index in range(outline.size()):
		var start := outline[index]
		var finish := outline[(index + 1) % outline.size()]
		var nearest := Geometry2D.get_closest_point_to_segment(point, start, finish)
		var normal := (finish - start).orthogonal().normalized()
		var clearance := _body_support(actor, Vector3(normal.x, 0, normal.y)) + 0.015
		if point.distance_to(nearest) < clearance:
			return false
	return true


static func pointer_destination(actor: CharacterBody3D, start: Vector3, ray: Vector3) -> Vector3:
	var at := start + ray * maxf(0.0, -start.y / ray.y)
	var surface := TERRAIN.terrain(actor)
	if surface != null:
		var excluded: Array[RID] = [actor.get_rid()]
		# Ignore cover tops: the selector addresses walkable decks and the floor.
		for body in actor.get_tree().current_scene.get("_arena_blockers"):
			if not body in surface.get("surfaces"):
				excluded.append(body.get_rid())
		var query := PhysicsRayQueryParameters3D.create(start, at + ray * 0.05, 1, excluded)
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			at = hit.position
	return surface_destination(actor, at)


func _update_surface_preview(actor: CharacterBody3D) -> void:
	if TERRAIN.terrain(actor) == null:
		return
	# Mesh vertices live in world coordinates and follow every traversed level.
	_range_ring.global_position = Vector3.ZERO
	_target_ring.global_position = Vector3.ZERO
	_target_disc.global_position = Vector3.ZERO
	if not _range_center.is_finite() or _range_center.distance_squared_to(actor.global_position) > 0.0004:
		_range_center = actor.global_position
		_range_ring.mesh = surface_circle(actor, _range_center, float(DATA.MODULE_DEFINITIONS.eclipse.max_range), false, 0.045)
	if not _target_center.is_finite() or _target_center.distance_squared_to(destination) > 0.0004:
		_target_center = destination
		var radius := float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius)
		_target_ring.mesh = surface_circle(actor, destination, radius, false, 0.08)
		_target_disc.mesh = surface_circle(actor, destination, radius, true, 0.06)


static func surface_circle(actor: CharacterBody3D, center: Vector3, radius: float, filled: bool, lift: float) -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := clampi(ceili(TAU * radius / 0.2), 64, 384)
	var bands := maxi(1, ceili(radius / 0.35)) if filled else 1
	for band in range(bands):
		var inner := radius * float(band) / bands if filled else radius - 0.035
		var outer := radius * float(band + 1) / bands if filled else radius + 0.035
		for index in range(segments):
			var angle_a := TAU * float(index) / segments
			var angle_b := TAU * float(index + 1) / segments
			var a := surface_destination(actor, center + Vector3(cos(angle_a) * inner, 0, sin(angle_a) * inner)) + Vector3.UP * lift
			var b := surface_destination(actor, center + Vector3(cos(angle_a) * outer, 0, sin(angle_a) * outer)) + Vector3.UP * lift
			var c := surface_destination(actor, center + Vector3(cos(angle_b) * outer, 0, sin(angle_b) * outer)) + Vector3.UP * lift
			var d := surface_destination(actor, center + Vector3(cos(angle_b) * inner, 0, sin(angle_b) * inner)) + Vector3.UP * lift
			for triangle in [[a, b, c], [a, c, d]]:
				# Leave a gap at vertical ledges instead of stretching a diagonal veil.
				if maxf(triangle[0].y, maxf(triangle[1].y, triangle[2].y)) - minf(triangle[0].y, minf(triangle[1].y, triangle[2].y)) > 0.25:
					continue
				for point in triangle:
					builder.set_normal(Vector3.UP)
					builder.add_vertex(point)
	return builder.commit()


func snapshot() -> Dictionary:
	return {"serial": serial, "remaining": remaining, "origin": origin, "destination": destination}


func receive_snapshot(actor: CharacterBody3D, value: Dictionary) -> void:
	var revision := int(value.get("serial", 0))
	var time_left := clampf(float(value.get("remaining", 0.0)), 0.0, float(DATA.MODULE_DEFINITIONS.eclipse.travel_duration))
	if revision < serial and time_left > 0.0:
		return
	if time_left <= 0.0:
		if travelling:
			if revision == serial:
				burst(actor.get_tree().current_scene, destination)
			cancel(actor)
		serial = revision
		_completed_serial = revision
		return
	if revision <= _completed_serial:
		return
	var at: Vector3 = value.get("destination", actor.global_position)
	var start: Vector3 = value.get("origin", actor.global_position)
	if not at.is_finite() or not start.is_finite():
		return
	if not travelling:
		# Replica-only restore; authority already checked collision and cooldown.
		cancel(actor)
		actor.global_position = start
		actor.set("_replaying", true)
		actor.get("_module_cooldowns").erase("eclipse")
		depart(actor, at, true)
		actor.set("_replaying", false)
	serial = revision
	remaining = time_left


static func material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func ring(parent: Node3D, radius: float, alpha: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - 0.035)
	mesh.outer_radius = radius + 0.035
	mesh.rings = 48
	mesh.ring_segments = 8
	visual.mesh = mesh
	visual.material_override = material(TINT, alpha)
	parent.add_child(visual)
	return visual


func _build_preview(actor: CharacterBody3D) -> void:
	_range_center = Vector3.INF
	_target_center = Vector3.INF
	_preview = Node3D.new()
	_preview.name = "EclipseDestinationPreview"
	actor.get_tree().current_scene.add_child(_preview)
	_range_ring = ring(_preview, float(DATA.MODULE_DEFINITIONS.eclipse.max_range), 0.28)
	_target_ring = ring(_preview, float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius), 0.95)
	_target_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius)
	disc.bottom_radius = disc.top_radius
	disc.height = 0.01
	_target_disc.mesh = disc
	_target_disc.material_override = material(TINT, 0.13)
	_preview.add_child(_target_disc)
	_caption = Label3D.new()
	_caption.font_size = 30
	_caption.pixel_size = 0.009
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_preview.add_child(_caption)


func _build_flight(actor: CharacterBody3D) -> void:
	_flight = Node3D.new()
	_flight.name = "EclipseParticleTransit"
	actor.get_tree().current_scene.add_child(_flight)
	var mesh := SphereMesh.new()
	mesh.radius = 0.065
	mesh.height = 0.13
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := material(Color("#9e64ff"), 0.95)
	for index in range(35):
		var particle := MeshInstance3D.new()
		particle.mesh = mesh
		particle.material_override = mat
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particle.scale = Vector3.ONE * (0.6 + float(index % 5) * 0.22)
		_flight.add_child(particle)
		particle.global_position = origin + Vector3.UP * 0.8
		_particles.append(particle)


static func burst(parent: Node, at: Vector3) -> void:
	var effect := Node3D.new()
	effect.name = "EclipseArrivalExplosion"
	parent.add_child(effect)
	effect.add_to_group("prototype0_fx_budget")
	effect.global_position = at + Vector3.UP * 0.1
	var wave := ring(effect, 1.0, 0.95)
	wave.scale = Vector3.ONE * 0.15
	var core := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	core.mesh = mesh
	core.material_override = material(Color("#f0e8ff"), 0.7)
	core.position.y = 0.8
	effect.add_child(core)
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(wave, "scale", Vector3.ONE * float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius), 0.3)
	tween.tween_property(wave.material_override, "albedo_color:a", 0.0, 0.3)
	tween.tween_property(core, "scale", Vector3(2.4, 1.8, 2.4), 0.22)
	tween.tween_property(core.material_override, "albedo_color:a", 0.0, 0.22)
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.09
	spark_mesh.height = 0.18
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	var sparks_material := material(Color("#9861f0"), 0.95)
	for index in range(18):
		var spark := MeshInstance3D.new()
		spark.mesh = spark_mesh
		spark.material_override = sparks_material
		spark.position = Vector3.UP * 0.65
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effect.add_child(spark)
		var angle := float(index) * TAU / 18.0
		var radius := float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius)
		var end := Vector3(cos(angle) * radius, 0.2 + float(index % 3) * 0.25, sin(angle) * radius)
		tween.tween_property(spark, "position", end, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.3)
	tween.tween_property(sparks_material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(effect.queue_free)
