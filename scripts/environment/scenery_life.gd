extends Node3D
## Fixed visual batches for the workshop's loose, hanging and atmospheric details.
const PAPER := preload("res://scripts/environment/scenery_paper.gdshader")
const AIR := preload("res://scripts/environment/scenery_atmosphere.gdshader")
const OIL := preload("res://scripts/environment/scenery_oil.gdshader")
const MAX_STATIONS := 16
const MAX_LOOSE := 24
const MAX_OIL := 8
const MAX_SHAFTS := 3
const MAX_MOTES := 24
var _ambience: Node3D
var _workshop: Node3D
var _scene: Node3D
var _organic: Node
var _loose: Array[Dictionary] = []
var _hanging: Array[Dictionary] = []
var _oil: Array[Dictionary] = []
var _batches: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _low := false
var _hidden := false
var _previous := Vector3.ZERO
var _has_previous := false
var _wake_clock := 0.0
var _queries := 0
var _rejected := 0
var _bird_period := 41.0
var _bird_phase := 6.0
var _bird_active := false
var _bird_origin := Vector3.ZERO

static func install(ambience: Node3D) -> void:
	if ambience.has_node("SceneryLife"):
		return
	var life := load("res://scripts/environment/scenery_life.gd").new() as Node3D
	life.name = "SceneryLife"
	ambience.add_child(life)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 125
	top_level = true
	global_transform = Transform3D.IDENTITY
	_ambience = get_parent() as Node3D
	_workshop = _ambience.get_parent() as Node3D
	_scene = _workshop
	while _scene != null and not _scene.has_node("CameraRig"):
		_scene = _scene.get_parent() as Node3D
	if _scene == null:
		set_process(false)
		return
	_rng.seed = absi(("Workshop life / " + str(_workshop.get_meta("reference_map", "classic"))).hash())
	_organic = _scene.get_node_or_null("OrganicWorldDetails")
	_make_batches()
	_make_stations()
	var manager := _scene.get_node_or_null("VFXManager")
	if manager != null:
		manager.connect("organic_contact", _contact)
		manager.connect("presentation_cleared", reset_transients)
	get_tree().node_added.connect(_node_added)
	_bird_phase = _rng.randf_range(9.0, 25.0)
	set_meta("visual_only", true)
	_process(0.0)

func _make_batches() -> void:
	var paper := PlaneMesh.new()
	paper.size = Vector2(0.34, 0.23)
	paper.subdivide_width = 4
	paper.subdivide_depth = 2
	_batch("papers", paper, _shader(PAPER), MAX_LOOSE)
	var metal := StandardMaterial3D.new()
	metal.vertex_color_use_as_albedo = true
	metal.metallic = 0.38
	metal.roughness = 0.66
	_batch("cans", _can_mesh(), metal, MAX_LOOSE)
	_batch("hanging", _hanging_mesh(), metal, MAX_STATIONS)
	var oil := PlaneMesh.new()
	oil.size = Vector2(0.65, 0.42)
	_batch("oil", oil, _shader(OIL), MAX_OIL)
	var shaft := QuadMesh.new()
	shaft.size = Vector2.ONE
	_batch("shafts", shaft, _shader(AIR, 0), MAX_SHAFTS)
	var mote := QuadMesh.new()
	mote.size = Vector2(0.03, 0.03)
	_batch("motes", mote, _shader(AIR, 1), MAX_MOTES)
	var bird := PlaneMesh.new()
	bird.size = Vector2(1.25, 0.72)
	_batch("bird", bird, _shader(AIR, 2), 1)

func _shader(shader: Shader, kind: int = -1) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	if kind >= 0:
		material.set_shader_parameter("kind", kind)
	_materials.append(material)
	return material

func _batch(key: String, mesh: Mesh, material: Material, capacity: int) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = key.capitalize().replace(" ", "")
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_batches[key] = multimesh

func _make_stations() -> void:
	for circuit in _ambience.get("_circuits"):
		if not circuit.neon or _hanging.size() >= MAX_STATIONS:
			continue
		var side: Vector3 = circuit.axis
		var out: Vector3 = circuit.out
		var anchor: Vector3 = circuit.at + side * 0.94 + Vector3.DOWN * 0.67 + out * 0.08
		anchor = _accessible_face(anchor, out, 0.045)
		_hanging.append({"circuit": circuit.id, "anchor": anchor, "basis": Basis(side, Vector3.UP, out), "phase": _rng.randf_range(0, TAU), "angle": 0.0, "velocity": 0.0})
		for index in 2:
			if _loose.size() >= MAX_LOOSE:
				break
			var at: Vector3 = circuit.at + out * (0.72 + index * 0.18) + side * (-0.72 if index == 0 else 0.73)
			at.y = _floor_y(at)
			at = _accessible_face(at + Vector3.UP * 0.16, out, 0.22 + index * 0.18)
			at.y = _floor_y(at)
			_loose.append({"circuit": circuit.id, "kind": "paper" if index == 0 else "can", "origin": at, "at": at, "velocity": Vector3.ZERO, "yaw": _rng.randf_range(0, TAU), "roll": 0.0, "lift": 0.0, "phase": _rng.randf_range(0, TAU), "tint": Color("#b8a989") if index == 0 else Color("#bca987"), "cooldown": 0.0})
		if _oil.size() < MAX_OIL:
			var at: Vector3 = circuit.at + side * 0.60 + out * 0.22
			at.y = _floor_y(at) + 0.018
			at = _accessible_face(at + Vector3.UP * 0.06, out, 0.34)
			at.y = _floor_y(at) + 0.018
			_oil.append({"circuit": circuit.id, "at": at, "phase": _rng.randf_range(0, TAU), "pulse": -100.0, "power": 0.0, "yaw": _rng.randf_range(0, TAU)})

func _accessible_face(at: Vector3, outward: Vector3, margin: float) -> Vector3:
	# Some transplanted workshops sit behind the arena boundary. Author the
	# accessory on the accessible face without changing any gameplay collider.
	var ray := PhysicsRayQueryParameters3D.create(at + outward * 3.0, at, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and (hit.normal as Vector3).dot(outward) > 0.5:
		return (hit.position as Vector3) + outward * margin
	return at

func _process(delta: float) -> void:
	if _scene == null:
		return
	if not _workshop.is_visible_in_tree():
		if not _hidden:
			reset_transients()
			_hidden = true
		return
	_hidden = false
	_clock += maxf(0.0, delta)
	_low = bool(_ambience.get("_low")) or int(_workshop.get("_quality")) == 0
	_queries = 0
	var focus := (_scene.get_node("CameraRig") as Node3D).global_position
	_sample_wake(delta)
	_draw_loose(minf(delta, 0.05), focus)
	_draw_hanging(minf(delta, 0.05), focus)
	_draw_oil(focus)
	_draw_air(focus)
	_draw_bird(focus)
	for material in _materials:
		material.set_shader_parameter("clock", _clock)

func _sample_wake(delta: float) -> void:
	if _organic == null or not bool(_organic.call("_is_active")):
		_has_previous = false
		return
	var observer: Node3D = _organic.get("observer")
	if observer == null:
		return
	var at := observer.global_position
	if not _has_previous:
		_previous = at
		_has_previous = true
		return
	var displacement := at - _previous
	_previous = at
	_wake_clock -= delta
	# The local actor alone creates a wake. Teleports do not produce a blast.
	if displacement.length_squared() > 9.0 or _wake_clock > 0.0 or delta <= 0.0:
		return
	var speed := displacement.length() / delta
	if speed < 0.65:
		return
	_wake_clock = 0.14
	_impulse(at + Vector3.UP * 0.12, displacement.normalized(), clampf(speed / 9.0, 0.12, 1.1), 1.6)

func _contact(at: Vector3, direction: Vector3, _surface: String, power: float) -> void:
	_impulse(at, direction, clampf(power, 0.0, 1.6), 3.0)

func _node_added(node: Node) -> void:
	if node is Node3D and String(node.name) in ["RocketImpact", "RocketIntercept"]:
		_blast.call_deferred(weakref(node))

func _blast(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node3D
	if node != null and _scene.is_ancestor_of(node):
		_impulse(node.global_position, Vector3.ZERO, 1.6, 5.0)

func _impulse(at: Vector3, direction: Vector3, power: float, radius: float) -> void:
	if not _workshop.is_visible_in_tree() or _organic == null or not bool(_organic.call("_visible", at)):
		_rejected += 1
		return
	for entry in _loose:
		var distance: float = (entry.at as Vector3).distance_to(at)
		if distance >= radius or entry.cooldown > 0.0 or not bool(_organic.call("_visible", entry.at + Vector3.UP * 0.16)):
			continue
		var outward: Vector3 = entry.at - at
		outward.y = 0.0
		var push := (outward.normalized() + Vector3(direction.x, 0, direction.z) * 0.45).normalized()
		if push.length_squared() < 0.001:
			push = Vector3(sin(float(entry.phase)), 0, cos(float(entry.phase)))
		var strength := power * (1.0 - distance / radius)
		entry.velocity += push * strength * (1.5 if entry.kind == "paper" else 1.1)
		entry.lift = maxf(entry.lift, strength)
		entry.cooldown = 0.18
	for entry in _hanging:
		var distance: float = (entry.anchor as Vector3).distance_to(at)
		if distance < radius and bool(_organic.call("_visible", entry.anchor)):
			entry.velocity = clampf(float(entry.velocity) + power * (1.0 - distance / radius) * 1.6, -3.0, 3.0)
	for entry in _oil:
		if (entry.at as Vector3).distance_to(at) < radius and bool(_organic.call("_visible", entry.at + Vector3.UP * 0.04)):
			entry.pulse = _clock
			entry.power = minf(1.0, power)

func _near(entries: Array[Dictionary], focus: Vector3, field: String, budget: int) -> Array[Dictionary]:
	var ordered := entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a[field] as Vector3).distance_squared_to(focus) < (b[field] as Vector3).distance_squared_to(focus))
	var visible_entries: Array[Dictionary] = []
	for entry in ordered:
		if visible_entries.size() < budget and (entry[field] as Vector3).distance_squared_to(focus) < 180.0:
			visible_entries.append(entry)
	return visible_entries

func _draw_loose(delta: float, focus: Vector3) -> void:
	var counts := {"paper": 0, "can": 0}
	var selected := _near(_loose, focus, "at", 6 if not _low else 3)
	for entry in _loose:
		entry.cooldown = maxf(0.0, float(entry.cooldown) - delta)
		if entry not in selected:
			entry.velocity = Vector3.ZERO
			entry.lift = 0.0
			continue
		_advance_loose(entry, delta)
		var key := "papers" if entry.kind == "paper" else "cans"
		var batch: MultiMesh = _batches[key]
		var index: int = counts[entry.kind]
		var at: Vector3 = entry.at
		var basis := _floor_basis(at) * Basis(Vector3.UP, float(entry.yaw))
		if entry.kind == "can":
			basis *= Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, float(entry.roll))
			at.y += 0.078
		else:
			at.y += 0.017 + float(entry.lift) * 0.08
		batch.set_instance_transform(index, Transform3D(basis, at))
		batch.set_instance_color(index, entry.tint)
		batch.set_instance_custom_data(index, Color(float(entry.phase), float(entry.lift) + (0.2 if not _low else 0.0), 0, 0))
		counts[entry.kind] += 1
	(_batches.papers as MultiMesh).visible_instance_count = counts.paper
	(_batches.cans as MultiMesh).visible_instance_count = counts.can

func _advance_loose(entry: Dictionary, delta: float) -> void:
	entry.lift = maxf(0.0, float(entry.lift) - delta * 0.70)
	var velocity: Vector3 = entry.velocity
	if velocity.length_squared() < 0.00001 or delta <= 0.0:
		return
	var step := velocity * delta
	var next: Vector3 = entry.at + step
	var floor_y := _floor_y(next)
	var blocked := absf(floor_y - float(entry.at.y)) > 0.22 or next.distance_to(entry.origin) > 1.1
	if not blocked:
		if _queries >= (2 if _low else 4):
			return
		_queries += 1
		var ray := PhysicsRayQueryParameters3D.create(entry.at + Vector3.UP * 0.08, next + Vector3.UP * 0.08)
		ray.collision_mask = 1
		blocked = not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	if blocked:
		entry.velocity = -velocity * 0.24
		return
	next.y = floor_y
	entry.at = next
	entry.roll += step.length() / 0.072
	if entry.kind == "can":
		entry.yaw = atan2(-velocity.z, velocity.x) + PI * 0.5
	entry.velocity = velocity.move_toward(Vector3.ZERO, delta * (0.85 if entry.kind == "can" else 1.25))

func _draw_hanging(delta: float, focus: Vector3) -> void:
	var batch: MultiMesh = _batches.hanging
	var selected := _near(_hanging, focus, "anchor", 4 if not _low else 2)
	var count := 0
	for entry in _hanging:
		var enabled := entry in selected
		var wind := sin(_clock * 0.8 + float(entry.phase)) * 0.035 + sin(_clock * 0.27) * 0.015
		var target := wind if enabled and not _low else 0.0
		entry.velocity += (target - float(entry.angle)) * delta * 15.0
		entry.velocity *= exp(-delta * 2.5)
		entry.angle = clampf(float(entry.angle) + float(entry.velocity) * delta, -0.40, 0.40)
		if not enabled:
			continue
		var basis: Basis = entry.basis * Basis(Vector3.BACK, float(entry.angle))
		batch.set_instance_transform(count, Transform3D(basis, entry.anchor))
		batch.set_instance_color(count, Color.WHITE)
		count += 1
	batch.visible_instance_count = count

func _draw_oil(focus: Vector3) -> void:
	var batch: MultiMesh = _batches.oil
	var selected := _near(_oil, focus, "at", 4 if not _low else 2)
	for index in selected.size():
		var entry := selected[index]
		var basis := _floor_basis(entry.at) * Basis(Vector3.UP, float(entry.yaw))
		batch.set_instance_transform(index, Transform3D(basis, entry.at))
		batch.set_instance_color(index, Color(0.14, 0.13, 0.105, 0.70))
		batch.set_instance_custom_data(index, Color(float(entry.phase), float(entry.pulse), float(entry.power), 0))
	batch.visible_instance_count = selected.size()

func _draw_air(focus: Vector3) -> void:
	var shafts: MultiMesh = _batches.shafts
	var motes: MultiMesh = _batches.motes
	shafts.visible_instance_count = 0
	motes.visible_instance_count = 0
	var camera := get_viewport().get_camera_3d()
	if _low or camera == null:
		return
	var lamps: Array[Dictionary] = []
	for circuit in _ambience.get("_circuits"):
		var light := circuit.light.get_ref() as OmniLight3D
		if not circuit.neon and light != null and light.is_visible_in_tree() and float(circuit.average) > 0.05 and light.global_position.distance_squared_to(focus) < 150.0:
			lamps.append(circuit)
	lamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.light.get_ref() as OmniLight3D).global_position.distance_squared_to(focus) < (b.light.get_ref() as OmniLight3D).global_position.distance_squared_to(focus))
	var right := camera.global_basis.x.normalized()
	var facing := Basis(right, Vector3.UP, right.cross(Vector3.UP)).orthonormalized()
	var count := 0
	for circuit in lamps.slice(0, MAX_SHAFTS):
		var light := circuit.light.get_ref() as OmniLight3D
		var at := light.global_position
		var floor_y := _floor_y(at)
		var height := clampf(at.y - floor_y, 0.3, 3.0)
		var strength: float = circuit.average
		shafts.set_instance_transform(count, Transform3D(facing.scaled(Vector3(0.58, height, 1)), Vector3(at.x, floor_y + height * 0.5, at.z)))
		shafts.set_instance_color(count, Color(0.93, 0.74, 0.44, 0.038 * strength))
		for index in 8:
			var phase: float = float(circuit.phase) + index * 2.399
			var point := Vector3(at.x + sin(_clock * 0.33 + phase) * 0.23, floor_y + 0.20 + fposmod(_clock * 0.12 + phase * 0.16, maxf(0.20, height - 0.28)), at.z + cos(_clock * 0.26 + phase) * 0.22)
			motes.set_instance_transform(count * 8 + index, Transform3D(camera.global_basis.orthonormalized(), point))
			motes.set_instance_color(count * 8 + index, Color(0.93, 0.78, 0.52, strength * 0.52))
		count += 1
	shafts.visible_instance_count = count
	motes.visible_instance_count = count * 8

func _draw_bird(focus: Vector3) -> void:
	var batch: MultiMesh = _batches.bird
	var phase := fposmod(_clock + _bird_phase, _bird_period)
	var passing := not _low and phase < 6.0
	if not passing:
		_bird_active = false
		batch.visible_instance_count = 0
		return
	if not _bird_active:
		_bird_origin = focus
		_bird_active = true
	var direction := Vector3(0.94, 0, -0.34)
	var at := _bird_origin + direction * (phase * 3.8 - 11.4)
	at.y = _floor_y(at) + 0.029
	var basis := _floor_basis(at) * Basis(Vector3.UP, 1.18)
	batch.set_instance_transform(0, Transform3D(basis, at))
	batch.set_instance_color(0, Color(0.21, 0.20, 0.17, sin(phase / 6.0 * PI) * 0.17))
	batch.set_instance_custom_data(0, Color(_bird_phase, 0, 0, 0))
	batch.visible_instance_count = 1

func _floor_y(at: Vector3) -> float:
	return float(_ambience.call("_floor_y", at))

func _floor_basis(at: Vector3) -> Basis:
	var y := _floor_y(at)
	var normal := Vector3(-(_floor_y(at + Vector3.RIGHT * 0.1) - y) / 0.1, 1, -(_floor_y(at + Vector3.BACK * 0.1) - y) / 0.1).normalized()
	return Basis(Quaternion(Vector3.UP, normal))

func reset_transients() -> void:
	_has_previous = false
	_wake_clock = 0.0
	_bird_active = false
	for entry in _loose:
		entry.at = entry.origin
		entry.velocity = Vector3.ZERO
		entry.roll = 0.0
		entry.lift = 0.0
		entry.cooldown = 0.0
	for entry in _hanging:
		entry.angle = 0.0
		entry.velocity = 0.0
	for entry in _oil:
		entry.pulse = -100.0
		entry.power = 0.0
	for batch in _batches.values():
		(batch as MultiMesh).visible_instance_count = 0

func _colored_part(tool: SurfaceTool, mesh: Mesh, pose: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for element in count:
		var index := indices[element] if not indices.is_empty() else element
		tool.set_color(color)
		tool.set_normal(pose.basis * normals[index])
		tool.add_vertex(pose * vertices[index])

func _can_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var can := CylinderMesh.new()
	can.top_radius = 0.072
	can.bottom_radius = 0.070
	can.height = 0.18
	can.radial_segments = 10
	can.rings = 1
	_colored_part(tool, can, Transform3D.IDENTITY, Color("#7e8b88"))
	var label := BoxMesh.new()
	label.size = Vector3(0.087, 0.10, 0.006)
	_colored_part(tool, label, Transform3D(Basis.IDENTITY, Vector3(0, -0.005, 0.068)), Color("#c5bfa5"))
	tool.index()
	return tool.commit()

func _hanging_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.034
	ring.outer_radius = 0.047
	ring.rings = 12
	ring.ring_segments = 5
	_colored_part(tool, ring, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -0.047, 0)), Color("#9ca9a2"))
	for part in [[Vector3(-0.029, -0.15, 0.01), Vector3(0.016, 0.15, 0.018)], [Vector3(-0.011, -0.217, 0.01), Vector3(0.040, 0.020, 0.018)], [Vector3(0.015, -0.21, 0.024), Vector3(0.075, 0.14, 0.012)]]:
		var box := BoxMesh.new()
		box.size = part[1]
		_colored_part(tool, box, Transform3D(Basis.IDENTITY, part[0]), Color("#af9b6d"))
	tool.index()
	return tool.commit()

func get_debug_counts() -> Dictionary:
	var counts := {"stations": _hanging.size(), "loose": _loose.size(), "oil": _oil.size(), "clock": _clock, "queries": _queries, "rejected": _rejected}
	for key in _batches:
		counts[key + "_visible"] = (_batches[key] as MultiMesh).visible_instance_count
	return counts
