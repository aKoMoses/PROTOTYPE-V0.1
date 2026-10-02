extends Node3D
## Local, bounded scenery responses. Only observes combat; never writes to actors.
const DETAIL_SHADER := preload("res://scripts/environment/organic_details.gdshader")
const MAX_BITS := 72
const MAX_STAMPS := 48
const MAX_MOTES := 18
const MAX_PROPS := 192
const MAX_ACTORS := 48
const GRAVITY := 9.8
const BREEZE := Vector3(0.94, 0.0, -0.34)
var manager: Node
var observer: Node3D
var _props: Array[Dictionary] = []
var _actors: Dictionary = {}
var _bits: Array[Dictionary] = []
var _stamps: Array[Dictionary] = []
var _motes: Array[Dictionary] = []
var _batches: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _scan_clock := 0.0
var _ambient_clock := 0.0
var _clock := 0.0
var _active := false
var _rejected := 0
var _ground_queries := 0
var _collision_queries := 0

static func install(scene: Node, vfx: Node) -> void:
	if not is_instance_valid(scene) or scene.has_node("OrganicWorldDetails") or not scene.has_node("CameraRig"):
		return
	var director := load("res://scripts/environment/organic_world_details.gd").new() as Node3D
	director.name = "OrganicWorldDetails"
	director.set("manager", vfx)
	scene.add_child(director)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 110 # Resolve the rendered material after the scenery directors.
	_rng.randomize()
	_make_batches()
	manager.connect("organic_contact", _contact)
	manager.connect("organic_shot", _shot)
	manager.connect("organic_motion", _motion)
	manager.connect("presentation_cleared", clear)
	get_tree().node_added.connect(_node_added)
	_scan()

func _resolve_observer() -> void:
	var rig := get_parent().get_node_or_null("CameraRig")
	observer = rig.get("_target") as Node3D if rig != null else null

func _scan() -> void:
	_resolve_observer()
	_props.clear()
	for mesh in get_parent().find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material == null or material.shader == null:
			continue
		var path := material.shader.resource_path
		if path in ["res://scripts/bush_foliage.gdshader", "res://scripts/environment/yard_cloth.gdshader"] and _props.size() < MAX_PROPS:
			# Store state on the mesh so discovery never resets a running response.
			if not mesh.has_meta("organic_state"):
				mesh.set_meta("organic_state", {"age": 3.0, "power": 0.0, "at": Vector3.ZERO, "direction": Vector2.ZERO, "influence": 0.0, "near": false, "cooldown": 0.0})
			_props.append({"mesh": weakref(mesh), "grass": path.ends_with("bush_foliage.gdshader")})
	for body in get_parent().find_children("*", "CollisionObject3D", true, false):
		if not body.has_method("get_health") or not "_visual_rig" in body:
			continue
		var id := body.get_instance_id()
		if not _actors.has(id) and _actors.size() < MAX_ACTORS:
			_actors[id] = {"actor": weakref(body), "previous": body.global_position, "velocity": Vector3.ZERO, "distance": 0.0, "side": 1.0, "admitted": false}
	for id in _actors.keys():
		if not is_instance_valid(_actors[id].actor.get_ref()):
			_actors.erase(id)

func _is_active() -> bool:
	return is_instance_valid(observer) and observer.is_visible_in_tree() and observer.has_method("is_gameplay_enabled") and bool(observer.call("is_gameplay_enabled"))

func _admitted(actor: Node3D) -> bool:
	if not _is_active() or not is_instance_valid(actor) or not actor.is_visible_in_tree():
		return false
	if actor.has_method("is_real_dead") and bool(actor.call("is_real_dead")):
		return false
	if actor != observer:
		# Without explicit observer visibility, a remote actor cannot leave clues.
		if not actor.has_method("is_visible_to") or not bool(actor.call("is_visible_to", observer)):
			return false
	return true

func _visible(at: Vector3) -> bool:
	if not _is_active():
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(at) or observer.global_position.distance_squared_to(at) > 900.0:
		return false
	if not get_viewport().get_visible_rect().has_point(camera.unproject_position(at)):
		return false
	var ray := PhysicsRayQueryParameters3D.create(observer.global_position + Vector3.UP, at)
	ray.collision_mask = 1
	ray.hit_from_inside = false
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_resolve_observer()
	var enabled := _is_active()
	if enabled != _active:
		clear()
		_active = enabled
	if not enabled:
		return
	_ground_queries = 0
	_collision_queries = 0
	_clock += delta
	_scan_clock -= delta
	if _scan_clock <= 0.0:
		_scan_clock = 0.8
		_scan()
	_update_props(delta)
	_update_actors(delta)
	_update_bits(delta)
	_update_stamps(delta)
	_update_ambient(delta)
	_render()

func _update_props(delta: float) -> void:
	for prop in _props:
		var mesh := prop.mesh.get_ref() as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree():
			continue
		var material := mesh.material_override as ShaderMaterial
		if material == null:
			continue
		var state: Dictionary = mesh.get_meta("organic_state")
		state.age += delta
		state.cooldown = maxf(0.0, state.cooldown - delta)
		if prop.grass:
			var relative := mesh.to_local(observer.global_position)
			var radius := float(mesh.get_parent().get_meta("foliage_radius", 1.28))
			var near := Vector2(relative.x, relative.z).length() <= radius + 0.5 and absf(relative.y) < 1.8
			state.influence = move_toward(float(state.influence), 1.0 if near else 0.0, delta * (6.0 if near else 2.4))
			# Resolve the actual rendered override: another finish may duplicate it.
			if near:
				material.set_shader_parameter("local_actor_position", relative)
			material.set_shader_parameter("local_actor_influence", state.influence)
			if near and not state.near and state.cooldown <= 0.0:
				_disturb(mesh, observer.global_position, Vector3.ZERO, 0.45)
				_emit_leaves(mesh.global_position + Vector3.UP * 0.7, Vector3.UP, 3)
			state.near = near
		material.set_shader_parameter("organic_impulse_origin", state.at)
		material.set_shader_parameter("organic_impulse_direction", state.direction)
		material.set_shader_parameter("organic_impulse_strength", state.power if state.age < 2.5 else 0.0)
		material.set_shader_parameter("organic_impulse_age", state.age)

func _disturb(mesh: MeshInstance3D, at: Vector3, direction: Vector3, power: float) -> void:
	var state: Dictionary = mesh.get_meta("organic_state", {})
	if state.is_empty():
		return
	var remaining := float(state.power) * exp(-float(state.age) * 4.0)
	if power < remaining:
		return
	state.at = at
	state.direction = Vector2(direction.x, direction.z)
	state.power = clampf(power, 0.0, 1.6)
	state.age = 0.0
	state.cooldown = 0.25

func disturb_at(at: Vector3, direction: Vector3, power: float, radius: float = 3.6) -> void:
	for prop in _props:
		var mesh := prop.mesh.get_ref() as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree():
			continue
		var distance := mesh.global_position.distance_to(at)
		if distance > radius:
			continue
		if not _visible(mesh.global_position + Vector3.UP * (0.8 if prop.grass else 0.1)):
			continue
		var state: Dictionary = mesh.get_meta("organic_state")
		var outward := (mesh.global_position - at).normalized()
		var strength := power * (1.0 - distance / radius)
		if prop.grass and state.cooldown <= 0.0 and strength > 0.2:
			_emit_leaves(mesh.global_position + Vector3.UP * 0.8, outward + Vector3.UP * 0.8, 3 if _low() else 5)
		_disturb(mesh, at, outward if direction.length_squared() < 0.01 else direction, strength)

func _shot(socket: Node3D, weapon: String, charge: float) -> void:
	var actor: Node = socket
	while actor != null and not actor.has_method("get_health"):
		actor = actor.get_parent()
	if not _admitted(actor as Node3D):
		_rejected += 1
		return
	var direction := -socket.global_basis.z.normalized()
	var start := socket.global_position
	var end := start + direction * 18.0
	var ray := PhysicsRayQueryParameters3D.create(start, end)
	ray.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		end = hit.position
	for prop in _props:
		if not prop.grass:
			continue
		var mesh := prop.mesh.get_ref() as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree():
			continue
		var centre := mesh.global_position + Vector3.UP * 1.0
		var closest := Geometry3D.get_closest_point_to_segment(centre, start, end)
		var state: Dictionary = mesh.get_meta("organic_state")
		if centre.distance_to(closest) < 1.45 and _visible(closest) and state.cooldown <= 0.0:
			_disturb(mesh, closest, direction, 0.75 + charge * 0.5)
			_emit_leaves(closest, direction + Vector3.UP * 0.8, 3 if _low() else 6)
	disturb_at(start, direction, 0.75 if weapon == "shotgun" else 0.32, 2.2)
	if weapon == "shotgun":
		var ground := _ground(start, 3.0)
		if not ground.is_empty():
			_add_bit("shell", start - direction * 0.18, socket.global_basis.x * 1.6 + Vector3.UP * 1.5, ground.position, Color("#b69a66"), 0.09, 3.5)

func _contact(at: Vector3, normal: Vector3, surface: String, power: float) -> void:
	if not _visible(at):
		_rejected += 1
		return
	disturb_at(at, normal, clampf(power, 0.2, 1.6))
	if surface not in ["metal", "concrete", "sand", "environment"]:
		return
	var ground := _ground(at, 6.0)
	if ground.is_empty():
		return
	var color := Color("#76746b") if surface == "metal" else Color("#a99b82")
	for index in (2 if _low() else 5):
		var tangent := Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(0.8, 1.6), _rng.randf_range(-0.7, 0.7))
		_add_bit("chip", at, (normal * 1.6 + tangent) * clampf(power, 0.5, 1.5), ground.position, color.darkened(_rng.randf_range(0.0, 0.2)), _rng.randf_range(0.055, 0.10), 1.8)

func _motion(at: Vector3, direction: Vector3, power: float) -> void:
	if _visible(at + Vector3.UP * 0.25):
		disturb_at(at, -direction, power * 0.9, 2.8)

func _node_added(node: Node) -> void:
	if node is Node3D and String(node.name) in ["RocketImpact", "RocketIntercept"]:
		_blast.call_deferred(weakref(node))

func _blast(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node3D
	if node == null or not get_parent().is_ancestor_of(node) or not _visible(node.global_position):
		return
	var at := node.global_position
	disturb_at(at, Vector3.ZERO, 1.6, 6.0)
	var ground := _ground(at, 6.0)
	if ground.is_empty() or String(node.name) == "RocketIntercept":
		return
	# Low, dusty tongues follow the floor instead of an extra glowing explosion.
	for index in (3 if _low() else 6):
		var angle := TAU * float(index) / 6.0 + _rng.randf_range(-0.2, 0.2)
		var direction := Vector3(cos(angle), 0.25, sin(angle))
		manager.call("burst", ground.position + Vector3.UP * 0.06, direction, Color(0.55, 0.46, 0.33, 0.18), 3, 2.6, 0.45, 0.20, 24.0, "dust")
		_add_bit("chip", ground.position + Vector3.UP * 0.12, direction * 3.0 + Vector3.UP * 1.6, ground.position, Color("#9c8b6a"), 0.09, 2.0)

func _update_actors(delta: float) -> void:
	for state in _actors.values():
		var actor := state.actor.get_ref() as Node3D
		if actor == null:
			continue
		if not _admitted(actor):
			state.admitted = false
			state.distance = 0.0
			state.velocity = Vector3.ZERO
			continue
		if not state.admitted:
			state.previous = actor.global_position
			state.admitted = true
			continue
		var motion: Vector3 = actor.global_position - state.previous
		state.previous = actor.global_position
		if motion.length() > maxf(1.2, delta * 25.0) or absf(motion.y) > 0.3:
			state.distance = 0.0
			state.velocity = Vector3.ZERO
			continue
		motion.y = 0.0
		var velocity := motion / maxf(delta, 0.008)
		var speed := velocity.length()
		state.distance += motion.length()
		var previous: Vector3 = state.velocity
		var braking := previous.length() > 3.0 and speed < 0.7
		var turning := previous.length() > 2.0 and speed > 2.0 and previous.normalized().dot(velocity.normalized()) < 0.35
		if float(state.distance) > (1.6 if _low() else 0.92) or braking or turning:
			state.distance = 0.0
			var direction := velocity.normalized() if speed > 0.2 else previous.normalized()
			var ground := _ground(actor.global_position + Vector3.UP * 0.2, 0.8)
			if not ground.is_empty() and ground.normal.y > 0.65 and absf(actor.global_position.y - ground.position.y) < 0.28:
				state.side = -float(state.side)
				var lateral := Vector3(-direction.z, 0, direction.x) * float(state.side) * 0.16
				_add_stamp(ground.position + lateral, direction, ground.normal, braking or turning)
				if actor == observer:
					disturb_at(actor.global_position, direction, 0.25 + minf(speed / 12.0, 0.4), 1.8)
				if not _low():
					manager.call("burst", ground.position + lateral + Vector3.UP * 0.035, -direction + Vector3.UP * 0.3, Color(0.51, 0.45, 0.34, 0.13), 2, 0.65, 0.24, 0.09, 30.0, "dust")
		state.velocity = velocity

func _ground(at: Vector3, depth: float) -> Dictionary:
	if _ground_queries >= (4 if _low() else 12):
		return {}
	_ground_queries += 1
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.12, at - Vector3.UP * depth)
	ray.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		return hit
	# The classic yard deliberately has a visual PlaneMesh and no floor body.
	# Match its authored floor (and the test arena height field), without adding
	# physics geometry or assuming an endless y=0 plane outside the actual map.
	var scene := get_parent()
	var ground := scene.get_node_or_null("Ground") as MeshInstance3D
	var terrain := scene.get_node_or_null("TestArena")
	if terrain != null and "arena_variant" in scene and str(scene.get("arena_variant")) == "test":
		ground = terrain.get_node_or_null("Ground") as MeshInstance3D
	if ground == null or ground.mesh == null or not ground.is_visible_in_tree():
		return {}
	var local := ground.to_local(at)
	var bounds := ground.mesh.get_aabb()
	if local.x < bounds.position.x or local.x > bounds.end.x or local.z < bounds.position.z or local.z > bounds.end.z:
		return {}
	var level := ground.global_position.y
	var normal := Vector3.UP
	if terrain != null and terrain.has_method("height_at") and "arena_variant" in scene and str(scene.get("arena_variant")) == "test":
		level = float(terrain.call("height_at", at))
		var x := float(terrain.call("height_at", at + Vector3.RIGHT * 0.05)) - level
		var z := float(terrain.call("height_at", at + Vector3.BACK * 0.05)) - level
		normal = Vector3(-x / 0.05, 1.0, -z / 0.05).normalized()
	if level > at.y + 0.12 or level < at.y - depth:
		return {}
	return {"position": Vector3(at.x, level, at.z), "normal": normal}

func _emit_leaves(at: Vector3, direction: Vector3, amount: int) -> void:
	var ground := _ground(at, 5.0)
	if ground.is_empty():
		return
	for index in amount:
		var flutter := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.4, 1.3), _rng.randf_range(-1.0, 1.0))
		var color := Color("#959559").lerp(Color("#b6a165"), _rng.randf())
		_add_bit("leaf", at, direction * 1.2 + flutter, ground.position, color, _rng.randf_range(0.08, 0.14), 2.4)

func _add_bit(kind: String, at: Vector3, velocity: Vector3, floor_at: Vector3, color: Color, size: float, life: float) -> void:
	var limit := 28 if _low() else MAX_BITS
	if _bits.size() >= limit:
		_bits.pop_front()
	_bits.append({"kind": kind, "at": at, "velocity": velocity, "floor": floor_at.y + size * 0.3, "age": 0.0, "life": life, "color": color, "size": size, "spin": _rng.randf_range(-5.0, 5.0), "angle": _rng.randf_range(0.0, TAU), "bounces": 0, "resting": false})

func _update_bits(delta: float) -> void:
	var step := minf(delta, 0.05)
	while _bits.size() > (28 if _low() else MAX_BITS):
		_bits.pop_front()
	for index in range(_bits.size() - 1, -1, -1):
		var bit := _bits[index]
		bit.age += delta
		if bit.age >= bit.life:
			_bits.remove_at(index)
			continue
		var leaf: bool = bit.kind == "leaf"
		if bool(bit.resting):
			continue
		var velocity: Vector3 = bit.velocity
		velocity.y -= (1.5 if leaf else GRAVITY) * step
		if leaf:
			velocity += (BREEZE * 0.6 + Vector3(sin(_clock * 5.0 + bit.angle), 0.0, cos(_clock * 4.0 + bit.angle)) * 0.5) * step
		var next: Vector3 = bit.at + velocity * step
		# A bounded sweep keeps chips on the outside of the actual cover face.
		if not leaf and velocity.length_squared() > 0.2 and _collision_queries < (4 if _low() else 16):
			_collision_queries += 1
			var ray := PhysicsRayQueryParameters3D.create(bit.at, next)
			ray.collision_mask = 1
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				next = hit.position + hit.normal * 0.025
				velocity = velocity.bounce(hit.normal) * 0.35
				bit.bounces += 1
		if next.y <= float(bit.floor):
			next.y = bit.floor
			velocity.y = absf(velocity.y) * (0.12 if leaf else 0.33)
			velocity.x *= 0.55
			velocity.z *= 0.55
			bit.spin *= 0.5
			bit.bounces += 1
			if int(bit.bounces) >= 3 or velocity.length_squared() < 0.08:
				bit.resting = true
		bit.at = next
		bit.velocity = velocity
		bit.angle += float(bit.spin) * step

func _add_stamp(at: Vector3, direction: Vector3, normal: Vector3, skid: bool) -> void:
	if _stamps.size() >= (20 if _low() else MAX_STAMPS):
		_stamps.pop_front()
	var forward := direction.slide(normal).normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	var basis := Basis(normal.cross(forward).normalized(), normal, forward)
	_stamps.append({"at": at + normal * 0.014, "basis": basis, "age": 0.0, "life": 5.0 if _low() else 8.0, "size": Vector3(0.24, 1.0, 0.70 if skid else 0.34), "alpha": 0.26 if skid else 0.15})

func _update_stamps(delta: float) -> void:
	while _stamps.size() > (20 if _low() else MAX_STAMPS):
		_stamps.pop_front()
	for index in range(_stamps.size() - 1, -1, -1):
		_stamps[index].age += delta
		if _stamps[index].age >= _stamps[index].life:
			_stamps.remove_at(index)

func _update_ambient(delta: float) -> void:
	if _low():
		_motes.clear()
		return
	_ambient_clock -= delta
	if _ambient_clock <= 0.0:
		_ambient_clock = 0.65
		var at := observer.global_position + Vector3(_rng.randf_range(-7.0, 7.0), 1.2, _rng.randf_range(-6.0, 6.0))
		if _visible(at) and _motes.size() < MAX_MOTES:
			_motes.append({"at": at, "age": 0.0, "life": _rng.randf_range(3.0, 5.0), "phase": _rng.randf_range(0.0, TAU), "size": _rng.randf_range(0.018, 0.038)})
	for index in range(_motes.size() - 1, -1, -1):
		var mote := _motes[index]
		mote.age += delta
		if mote.age >= mote.life:
			_motes.remove_at(index)
			continue
		mote.at += (BREEZE * 0.34 + Vector3(0.0, sin(_clock + mote.phase) * 0.08, 0.0)) * delta

func _low() -> bool:
	return int(manager.get("quality")) == 0

func _make_batches() -> void:
	var chip := BoxMesh.new()
	chip.size = Vector3(1.0, 0.55, 0.7)
	var leaf := PrismMesh.new()
	leaf.size = Vector3(0.6, 0.10, 1.2)
	var shell := CylinderMesh.new()
	shell.top_radius = 0.27
	shell.bottom_radius = 0.3
	shell.height = 1.2
	shell.radial_segments = 6
	var stamp := PlaneMesh.new()
	stamp.size = Vector2.ONE
	for kind in ["chip", "leaf", "shell", "stamp", "mote"]:
		var mesh: Mesh = {"chip": chip, "leaf": leaf, "shell": shell, "stamp": stamp, "mote": chip}[kind]
		var batch := MultiMeshInstance3D.new()
		batch.name = "Organic" + String(kind).capitalize()
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = mesh
		instances.instance_count = MAX_STAMPS if kind == "stamp" else MAX_MOTES if kind == "mote" else MAX_BITS
		instances.visible_instance_count = 0
		batch.multimesh = instances
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.custom_aabb = AABB(Vector3.ONE * -100.0, Vector3.ONE * 200.0)
		var material := ShaderMaterial.new()
		material.shader = DETAIL_SHADER
		material.set_shader_parameter("ground_stamp", kind == "stamp")
		batch.material_override = material
		add_child(batch)
		_batches[kind] = instances

func _render() -> void:
	var counts := {"chip": 0, "leaf": 0, "shell": 0}
	for bit in _bits:
		var color: Color = bit.color
		color.a = 1.0 - smoothstep(float(bit.life) - 0.65, float(bit.life), float(bit.age))
		var rotation := Vector3(bit.angle * 0.7, bit.angle, sin(bit.angle) * 0.6)
		var basis := Basis.from_euler(rotation).scaled(Vector3.ONE * float(bit.size))
		var batch := _batches[bit.kind] as MultiMesh
		batch.set_instance_transform(counts[bit.kind], global_transform.affine_inverse() * Transform3D(basis, bit.at))
		batch.set_instance_color(counts[bit.kind], color)
		counts[bit.kind] += 1
	for kind in counts:
		(_batches[kind] as MultiMesh).visible_instance_count = counts[kind]
	for index in _stamps.size():
		var stamp := _stamps[index]
		var fade := 1.0 - smoothstep(float(stamp.life) * 0.55, float(stamp.life), float(stamp.age))
		var batch := _batches.stamp as MultiMesh
		batch.set_instance_transform(index, global_transform.affine_inverse() * Transform3D((stamp.basis as Basis).scaled_local(stamp.size), stamp.at))
		batch.set_instance_color(index, Color(0.27, 0.23, 0.17, float(stamp.alpha) * fade))
	(_batches.stamp as MultiMesh).visible_instance_count = _stamps.size()
	for index in _motes.size():
		var mote := _motes[index]
		var alpha := sin(PI * float(mote.age) / float(mote.life)) * 0.22
		var batch := _batches.mote as MultiMesh
		batch.set_instance_transform(index, global_transform.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(mote.size)), mote.at))
		batch.set_instance_color(index, Color(0.77, 0.69, 0.48, alpha))
	(_batches.mote as MultiMesh).visible_instance_count = _motes.size()

func clear() -> void:
	_bits.clear()
	_stamps.clear()
	_motes.clear()
	for prop in _props:
		var mesh := prop.mesh.get_ref() as MeshInstance3D
		if mesh == null:
			continue
		var state: Dictionary = mesh.get_meta("organic_state")
		state.age = 3.0
		state.power = 0.0
		state.near = false
		state.influence = 0.0
		state.cooldown = 0.0
		var material := mesh.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("organic_impulse_strength", 0.0)
			if prop.grass:
				material.set_shader_parameter("local_actor_influence", 0.0)
	for state in _actors.values():
		state.admitted = false
		state.distance = 0.0
		state.velocity = Vector3.ZERO
	for batch in _batches.values():
		(batch as MultiMesh).visible_instance_count = 0

func get_debug_counts() -> Dictionary:
	return {"bits": _bits.size(), "stamps": _stamps.size(), "motes": _motes.size(), "props": _props.size(), "actors": _actors.size(), "draw_calls": _batches.size(), "rejected": _rejected, "ground_queries": _ground_queries, "collision_queries": _collision_queries}
