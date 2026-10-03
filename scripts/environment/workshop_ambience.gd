extends Node3D
## Scenery circuits, moving pendants and bounded service equipment. No physics.
const NEON := preload("res://scripts/environment/workshop_neon_live.gdshader")
const HALO := preload("res://scripts/environment/workshop_glow_live.gdshader")
const FIXTURE := preload("res://scripts/environment/workshop_fixture.gd")
const VAPOUR := preload("res://scripts/environment/workshop_vapour.gdshader")
const SCENERY_LIFE := preload("res://scripts/environment/scenery_life.gd")
const MAX_CIRCUITS := 128
const MAX_FIXTURES := 16
const MAX_PENDANTS := 16
const ACTIVE_FIXTURES := 4
const ACTIVE_PENDANTS := 6
var _scene: Node3D
var _workshop: Node3D
var _circuits: Array[Dictionary] = []
var _pendants: Array[Dictionary] = []
var _fixtures: Array[Dictionary] = []
var _materials: Dictionary = {}
var _values := PackedVector4Array()
var _clock := 0.0
var _update_clock := 0.0
var _initialized := false
var _low := false
var _lamp_grid: Dictionary = {}
var _circuit_grid: Dictionary = {}
var _paused_hidden := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 120
	set_process(false)
	_prepare.call_deferred()

func _prepare() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	for frame in range(2):
		await tree.process_frame
		if not is_inside_tree() or is_queued_for_deletion():
			return
	_workshop = get_parent() as Node3D
	_scene = _workshop
	while _scene != null and not _scene.has_node("CameraRig"):
		_scene = _scene.get_parent() as Node3D
	if _scene == null:
		return
	_values.resize(MAX_CIRCUITS)
	_values.fill(Vector4(1.0, -100.0, 1.0, 0.0))
	_collect_circuits()
	_collect_pendants()
	_recover_sign_layouts()
	_bind_geometry()
	_build_fixtures()
	var manager := _scene.get_node_or_null("VFXManager")
	if manager != null:
		manager.connect("organic_contact", _contact)
		manager.connect("organic_motion", _motion)
		manager.connect("presentation_cleared", reset_transients)
	_initialized = true
	set_meta("visual_only", true)
	set_process(true)
	_process(0.0)
	SCENERY_LIFE.install(self)

func _collect_circuits() -> void:
	var neon_index := 0
	for light in _workshop.find_children("WorkshopLight*", "OmniLight3D", true, false):
		if _circuits.size() >= MAX_CIRCUITS:
			break
		var color: Color = light.light_color
		var neon := color.g > color.r * 1.1 or color.r > color.g * 1.8
		var seed_value := absi((str(light.name) + str(light.global_position) + str(_workshop.get_meta("reference_map", "classic"))).hash())
		var pool := _workshop.get_node_or_null("LightPool" + String(light.name).trim_prefix("WorkshopLight")) as MeshInstance3D
		if pool != null and pool.material_override is ShaderMaterial:
			pool.material_override = pool.material_override.duplicate()
		var circuit := {"id": _circuits.size(), "light": weakref(light), "pool": weakref(pool) if pool != null else null, "at": light.global_position, "pool_at": pool.global_position if pool != null else Vector3.ZERO, "energy": light.light_energy, "color": color, "neon": neon, "seed": seed_value, "phase": float(seed_value % 1009) * 0.043, "period": 33.0 + float(seed_value % 17), "mode": seed_value % 5, "axis": Vector3.RIGHT, "out": Vector3.BACK, "fault_until": -1.0, "power": 1.0, "average": 1.0, "arc": 0.0}
		if neon:
			# Distribute steady, faulty and weak circuits even among the four
			# central signs, while keeping their periods and phases independent.
			circuit.mode = [4, 3, 1, 2, 0][neon_index % 5]
			neon_index += 1
		_circuits.append(circuit)
		var tile := Vector2i(floori(circuit.at.x / 8.0), floori(circuit.at.z / 8.0))
		for x in range(-1, 2):
			for z in range(-1, 2):
				var key := tile + Vector2i(x, z)
				if not _circuit_grid.has(key):
					_circuit_grid[key] = []
				_circuit_grid[key].append(circuit.id)

func _collect_pendants() -> void:
	for circuit in _circuits:
		if circuit.neon or float(circuit.at.y) < 2.55 or _pendants.size() >= MAX_PENDANTS:
			continue
		var pivot := Node3D.new()
		pivot.name = "LivePendant%02d" % circuit.id
		add_child(pivot)
		pivot.global_position = circuit.at + Vector3.UP * 0.30
		var shadow_mesh := PlaneMesh.new()
		shadow_mesh.size = Vector2(0.70, 0.46)
		var shadow := MeshInstance3D.new()
		shadow.name = "MovingPendantShadow%02d" % circuit.id
		shadow.mesh = shadow_mesh
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = VAPOUR
		material.set_shader_parameter("effect_kind", 2)
		material.set_shader_parameter("tint", Color("#34332c"))
		shadow.material_override = material
		add_child(shadow)
		var entry := {"id": _pendants.size(), "circuit": circuit.id, "pivot": pivot, "shadow": shadow, "at": circuit.at, "angle": 0.0, "velocity": 0.0, "pieces": 0}
		_pendants.append(entry)
		var tile := Vector2i(floori(circuit.at.x / 2.0), floori(circuit.at.z / 2.0))
		for x in range(-1, 2):
			for z in range(-1, 2):
				var key := tile + Vector2i(x, z)
				if not _lamp_grid.has(key):
					_lamp_grid[key] = []
				_lamp_grid[key].append(entry.id)

func circuit_state(circuit: Dictionary, clock: float) -> Vector4:
	var phase: float = fmod(clock + float(circuit.phase), float(circuit.period))
	var supply := 1.0
	var failure_letter := -100.0
	var letter_level := 1.0
	if circuit.neon:
		# Most signs stay steady. A minority have a clear off interval, two
		# deliberate ignition attempts, then a long stable illuminated interval.
		if int(circuit.mode) in [0, 3]:
			if phase < 1.75:
				supply = 0.0
			elif phase < 2.20:
				supply = 0.82 if phase < 1.86 or phase >= 2.03 and phase < 2.13 else 0.03
			elif phase < 2.85:
				supply = smoothstep(2.20, 2.85, phase)
		elif int(circuit.mode) == 1:
			supply = 0.86 + sin(clock * 1.25 + float(circuit.phase)) * 0.035
		if int(circuit.mode) in [1, 2, 3]:
			failure_letter = float(int(circuit.seed) % int(circuit.get("letters", 7)))
			var letter_phase := fmod(clock + float(circuit.phase) * 0.7, 12.0 + float(int(circuit.seed) % 5))
			if letter_phase < 1.3:
				letter_level = 0.0
			elif letter_phase < 1.65:
				letter_level = 0.75 if letter_phase < 1.40 or letter_phase > 1.53 else 0.02
	else:
		supply = 0.96 + sin(clock * 0.75 + float(circuit.phase)) * 0.025
	if clock < float(circuit.fault_until):
		supply *= 0.30
	return Vector4(supply, failure_letter, letter_level, float(circuit.arc))

func _nearest_circuit(point: Vector3, color: Color) -> int:
	var tile := Vector2i(floori(point.x / 8.0), floori(point.z / 8.0))
	var candidates: Array = _circuit_grid.get(tile, [])
	var best := -1
	var distance := INF
	for id in candidates:
		var circuit := _circuits[int(id)]
		var mismatch := 0.0
		if color.g > color.r * 1.1 and not circuit.neon:
			mismatch = 4.0
		elif color.r > color.g * 1.8 and not circuit.neon:
			mismatch = 4.0
		var score: float = point.distance_squared_to(circuit.at) + mismatch
		if score < distance:
			distance = score
			best = int(id)
	return best

func _pendant_for(a: Vector3, b: Vector3, c: Vector3) -> int:
	var centre := (a + b + c) / 3.0
	var tile := Vector2i(floori(centre.x / 2.0), floori(centre.z / 2.0))
	for id in _lamp_grid.get(tile, []):
		var at: Vector3 = _pendants[int(id)].at
		var accepted := true
		for point in [a, b, c]:
			var relative: Vector3 = point - at
			if absf(relative.x) > 0.26 or absf(relative.z) > 0.26 or relative.y < -0.20 or relative.y > 0.23:
				accepted = false
				break
		if accepted:
			return int(id)
	return -1

func _recover_sign_layouts() -> void:
	# Recover the actual bent-glass plane and disconnected glyph intervals.
	# This works for rotated/scaled map instances and letters of different widths.
	var clouds: Dictionary = {}
	for node in _workshop.find_children("Workshop_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh is ArrayMesh:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null or not material.emission_enabled:
				continue
			var color := material.albedo_color
			if not (color.g > color.r * 1.1 or color.r > color.g * 1.8):
				continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index in range(0, count, 3):
				var triangle: Array[Vector3] = []
				for offset in 3:
					triangle.append(mesh.global_transform * vertices[indices[index + offset] if not indices.is_empty() else index + offset])
				var centre := (triangle[0] + triangle[1] + triangle[2]) / 3.0
				var id := _nearest_circuit(centre, color)
				if id < 0 or not _circuits[id].neon:
					continue
				var relative: Vector3 = centre - _circuits[id].at
				if relative.y < 0.0 or relative.y > 0.52 or relative.length_squared() > 8.0:
					continue
				if not clouds.has(id):
					clouds[id] = PackedVector3Array()
				clouds[id].append_array(PackedVector3Array(triangle))
	for id in clouds:
		var points: PackedVector3Array = clouds[id]
		var mean := Vector3.ZERO
		for point in points:
			mean += point
		mean /= float(points.size())
		var xx := 0.0
		var zz := 0.0
		var xz := 0.0
		for point in points:
			var relative := point - mean
			xx += relative.x * relative.x
			zz += relative.z * relative.z
			xz += relative.x * relative.z
		var angle := atan2(2.0 * xz, xx - zz) * 0.5
		var right := Vector3(cos(angle), 0, sin(angle))
		var outward := right.cross(Vector3.UP)
		var circuit := _circuits[int(id)]
		if outward.dot(circuit.at - mean) < 0.0:
			right = -right
			outward = -outward
		circuit.axis = right
		circuit.out = outward
		circuit.axis_bound = true
		var intervals: Array[Vector2] = []
		for index in range(0, points.size(), 3):
			var a: float = (points[index] - circuit.at).dot(right)
			var b: float = (points[index + 1] - circuit.at).dot(right)
			var c: float = (points[index + 2] - circuit.at).dot(right)
			intervals.append(Vector2(minf(a, minf(b, c)), maxf(a, maxf(b, c))))
		intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var glyphs: Array[Vector2] = []
		for interval in intervals:
			if glyphs.is_empty() or interval.x > glyphs[-1].y + 0.018:
				glyphs.append(interval)
			else:
				glyphs[-1].y = maxf(glyphs[-1].y, interval.y)
		circuit.letter_bounds = glyphs
		circuit.letters = maxi(1, glyphs.size())

func _bind_geometry() -> void:
	# Baked meshes remain the source of truth. Only instance meshes are copied;
	# original resources, triangle counts, collision bodies and footprints stay intact.
	var meshes := _workshop.find_children("Workshop_*", "MeshInstance3D", true, false)
	for node in meshes:
		var mesh := node as MeshInstance3D
		if not mesh.mesh is ArrayMesh:
			continue
		var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		var near_pendant := false
		for entry in _pendants:
			var lamp_bounds := AABB((entry.at as Vector3) - Vector3(0.27, 0.21, 0.27), Vector3(0.54, 0.45, 0.54))
			if bounds.intersects(lamp_bounds):
				near_pendant = true
				break
		var copy := ArrayMesh.new()
		var changed := false
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var source := mesh.get_active_material(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var element_count := indices.size() if not indices.is_empty() else vertices.size()
			if element_count % 3 != 0:
				copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				copy.surface_set_material(copy.get_surface_count() - 1, source)
				continue
			var opaque := source is StandardMaterial3D and (source as StandardMaterial3D).emission_enabled and "Workshop_" in source.resource_name
			var glow := source is ShaderMaterial and (source as ShaderMaterial).shader.resource_path == "res://shaders/workshop_neon_halo.gdshader"
			if not near_pendant and not opaque and not glow:
				copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				copy.surface_set_material(copy.get_surface_count() - 1, source)
				continue
			var color := Color.WHITE
			if opaque:
				color = (source as StandardMaterial3D).albedo_color
			elif glow:
				color = (source as ShaderMaterial).get_shader_parameter("neon_color")
			if not near_pendant:
				var tagged := arrays.duplicate()
				var tags := PackedVector2Array()
				tags.resize(vertices.size())
				for index in vertices.size():
					tags[index] = _tag(mesh.global_transform * vertices[index], color, true)
				tagged[Mesh.ARRAY_TEX_UV2] = tags
				copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tagged)
				copy.surface_set_material(copy.get_surface_count() - 1, _live_material(source, color, glow))
				changed = true
				continue
			var data := _empty_geometry()
			var pieces: Dictionary = {}
			for triangle in range(0, element_count, 3):
				var ia := indices[triangle] if not indices.is_empty() else triangle
				var ib := indices[triangle + 1] if not indices.is_empty() else triangle + 1
				var ic := indices[triangle + 2] if not indices.is_empty() else triangle + 2
				var a := mesh.global_transform * vertices[ia]
				var b := mesh.global_transform * vertices[ib]
				var c := mesh.global_transform * vertices[ic]
				var lamp := _pendant_for(a, b, c)
				if lamp >= 0:
					if not pieces.has(lamp):
						pieces[lamp] = _empty_geometry()
					for index in [ia, ib, ic]:
						var at := mesh.global_transform * vertices[index]
						if _append_geometry(pieces[lamp], index, at - _pendants[lamp].pivot.global_position, mesh.global_basis * normals[index], uvs[index], _tag(at, color, opaque or glow)):
							_append_tangent(pieces[lamp], tangents, index, mesh.global_basis)
					changed = true
				else:
					for index in [ia, ib, ic]:
						if _append_geometry(data, index, vertices[index], normals[index], uvs[index], _tag(mesh.global_transform * vertices[index], color, opaque or glow)):
							_append_tangent(data, tangents, index, Basis.IDENTITY)
			var finish := _live_material(source, color, glow) if opaque or glow else source
			if pieces.is_empty() and not opaque and not glow:
				copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				copy.surface_set_material(copy.get_surface_count() - 1, source)
				continue
			if not data.v.is_empty():
				copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _geometry_arrays(data))
				copy.surface_set_material(copy.get_surface_count() - 1, finish)
			for lamp in pieces:
				var moving := MeshInstance3D.new()
				moving.name = "Workshop_LiveLamp%02d_%s" % [lamp, mesh.name]
				var piece_mesh := ArrayMesh.new()
				piece_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _geometry_arrays(pieces[lamp]))
				piece_mesh.surface_set_material(0, finish)
				moving.mesh = piece_mesh
				moving.cast_shadow = mesh.cast_shadow
				_pendants[int(lamp)].pivot.add_child(moving)
				_pendants[int(lamp)].pieces += 1
			changed = changed or opaque or glow
		if changed:
			if copy.get_surface_count() == 0:
				mesh.queue_free()
				continue
			mesh.mesh = copy
			mesh.material_override = null
			for surface in mesh.get_surface_override_material_count():
				mesh.set_surface_override_material(surface, null)

func _tag(at: Vector3, color: Color, live: bool) -> Vector2:
	if not live:
		return Vector2.ZERO
	var id := _nearest_circuit(at, color)
	if id < 0:
		return Vector2.ZERO
	var circuit := _circuits[id]
	if circuit.neon:
		# The signs are built on the nearest cover face. Recover its horizontal
		# axis so the same letter tag is used by both glass and its wider halo.
		var axis: Vector3 = _sign_axis(circuit)
		if circuit.has("letter_bounds"):
			var horizontal := (at - (circuit.at as Vector3)).dot(axis)
			var letter := -2
			var distance := 0.085
			for index in circuit.letter_bounds.size():
				var bound: Vector2 = circuit.letter_bounds[index]
				var gap := absf(horizontal - clampf(horizontal, bound.x, bound.y))
				if gap < distance:
					distance = gap
					letter = index
			return Vector2(float(id), float(letter))
		return Vector2(float(id), floorf((at - circuit.at).dot(axis) / 0.34 + 3.5))
	return Vector2(float(id), -1.0 if color.r > 0.9 and color.g > 0.6 else -2.0)

func _sign_axis(circuit: Dictionary) -> Vector3:
	if circuit.has("axis_bound"):
		return circuit.axis
	var nearest: Node3D
	var distance := INF
	for body in _scene.find_children("*", "StaticBody3D", true, false):
		if not body.is_visible_in_tree():
			continue
		var score: float = body.global_position.distance_squared_to(circuit.at)
		if score < distance:
			distance = score
			nearest = body as Node3D
	var right := Vector3.RIGHT
	if nearest != null:
		right = nearest.global_basis.x.normalized()
		var shapes := nearest.find_children("*", "CollisionShape3D", true, false)
		var collision := shapes[0] as CollisionShape3D if not shapes.is_empty() else null
		if collision != null and collision.shape is BoxShape3D:
			var size := (collision.shape as BoxShape3D).size
			if size.z > size.x:
				right = -nearest.global_basis.z.normalized()
	var outward := right.cross(Vector3.UP).normalized()
	if nearest != null and outward.dot(circuit.at - nearest.global_position) < 0.0:
		outward = -outward
		right = -right
	circuit.axis = right
	circuit.out = outward
	circuit["axis_bound"] = true
	return right

func _live_material(source: Material, color: Color, glow: bool) -> Material:
	var key := str(source.get_instance_id()) + ("halo" if glow else "glass")
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = HALO if glow else NEON
	material.set_shader_parameter("tube_color", color)
	if not glow:
		material.set_shader_parameter("emission_strength", (source as StandardMaterial3D).emission_energy_multiplier)
	material.set_shader_parameter("circuit_values", _values)
	_materials[key] = material
	return material

func _build_fixtures() -> void:
	for circuit in _circuits:
		if not circuit.neon or _fixtures.size() >= MAX_FIXTURES:
			continue
		var right := _sign_axis(circuit)
		var fixture := FIXTURE.new()
		fixture.name = "WorkshopService%02d" % circuit.id
		add_child(fixture)
		fixture.global_transform = Transform3D(Basis(right, Vector3.UP, circuit.out), circuit.at + Vector3.DOWN * 0.85 + circuit.out * 0.035)
		fixture.call("setup", circuit.seed, circuit.color)
		fixture.hide()
		_fixtures.append({"node": fixture, "circuit": circuit.id, "gust": Vector3.ZERO})

func _empty_geometry() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "tag": PackedVector2Array(), "t": PackedFloat32Array(), "i": PackedInt32Array(), "map": {}}

func _append_geometry(data: Dictionary, source_index: int, vertex: Vector3, normal: Vector3, uv: Vector2, tag: Vector2) -> bool:
	if data.map.has(source_index):
		data.i.append(data.map[source_index])
		return false
	data.map[source_index] = data.v.size()
	data.i.append(data.v.size())
	data.v.append(vertex)
	data.n.append(normal)
	data.uv.append(uv)
	data.tag.append(tag)
	return true

func _append_tangent(data: Dictionary, tangents: PackedFloat32Array, index: int, basis: Basis) -> void:
	if tangents.is_empty():
		return
	var offset := index * 4
	var tangent := basis * Vector3(tangents[offset], tangents[offset + 1], tangents[offset + 2])
	data.t.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, tangents[offset + 3]]))

func _geometry_arrays(data: Dictionary) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.v
	arrays[Mesh.ARRAY_NORMAL] = data.n
	if not data.t.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = data.t
	arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_TEX_UV2] = data.tag
	arrays[Mesh.ARRAY_INDEX] = data.i
	return arrays

func _process(delta: float) -> void:
	if not _initialized:
		return
	if not _workshop.is_inside_tree() or not _workshop.is_visible_in_tree():
		if not _paused_hidden:
			reset_transients()
			_paused_hidden = true
		return
	_paused_hidden = false
	_clock += maxf(0.0, delta)
	var manager := _scene.get_node_or_null("VFXManager")
	_low = int(manager.get("quality")) == 0 if manager != null else int(_workshop.get("_quality")) == 0
	var rig := _scene.get_node("CameraRig") as Node3D
	var focus := rig.global_position
	_update_fixtures(delta, focus)
	_update_pendants(delta, focus)
	_update_clock -= delta
	if _update_clock <= 0.0:
		_update_clock = 1.0 / (15.0 if _low else 30.0)
		_update_circuits()

func _update_circuits() -> void:
	for circuit in _circuits:
		var state := circuit_state(circuit, _clock)
		_values[int(circuit.id)] = state
		circuit.power = state.x
		circuit.average = state.x * (1.0 - (1.0 - state.z) / float(circuit.get("letters", 7))) + state.w
		var light := circuit.light.get_ref() as OmniLight3D
		if light != null:
			light.light_energy = float(circuit.energy) * float(circuit.average)
			light.light_color = (circuit.color as Color).lerp(Color("#b8ecff"), clampf(float(circuit.arc), 0.0, 0.45))
		if circuit.pool != null:
			var pool := circuit.pool.get_ref() as MeshInstance3D
			if pool != null:
				(pool.material_override as ShaderMaterial).set_shader_parameter("live_intensity", circuit.average)
	for material in _materials.values():
		(material as ShaderMaterial).set_shader_parameter("circuit_values", _values)
		(material as ShaderMaterial).set_shader_parameter("ambient_time", _clock)

func _update_fixtures(delta: float, focus: Vector3) -> void:
	var ordered := _fixtures.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.node.global_position.distance_squared_to(focus) < b.node.global_position.distance_squared_to(focus))
	var admitted := 0
	for entry in ordered:
		var fixture: Node3D = entry.node
		var enabled := admitted < (2 if _low else ACTIVE_FIXTURES) and fixture.global_position.distance_squared_to(focus) < 230.0
		fixture.visible = enabled
		entry.gust = (entry.gust as Vector3).move_toward(Vector3.ZERO, delta * 2.0)
		var circuit := _circuits[int(entry.circuit)]
		circuit.arc = 0.0
		if not enabled:
			fixture.call("reset_transients")
			continue
		admitted += 1
		var floor_y := _floor_y(fixture.to_global(Vector3(0.62, 0, 0.02)))
		fixture.call("animate", _clock, delta, circuit.power, _low, floor_y, Vector3(0.94, 0, -0.34) + entry.gust)
		if bool(fixture.get("arc_active")):
			circuit.arc = 0.42
	set_meta("active_service_fixtures", admitted)

func _update_pendants(delta: float, focus: Vector3) -> void:
	var ordered := _pendants.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at.distance_squared_to(focus) < b.at.distance_squared_to(focus))
	var admitted := 0
	for entry in ordered:
		var circuit := _circuits[int(entry.circuit)]
		var enabled: bool = not _low and admitted < ACTIVE_PENDANTS and entry.at.distance_squared_to(focus) < 230.0
		entry.shadow.visible = enabled
		# A culled pendant retains its authored geometry, but stops secondary motion.
		var target := sin(_clock * 0.82 + float(circuit.phase)) * 0.035 if enabled else 0.0
		var step := minf(delta, 0.05)
		entry.velocity += (target - float(entry.angle)) * 12.0 * step
		entry.velocity *= exp(-step * 2.6)
		entry.angle = clampf(float(entry.angle) + float(entry.velocity) * step, -0.15, 0.15)
		entry.pivot.rotation.z = entry.angle
		var offset: Vector3 = entry.pivot.global_basis * Vector3(0, -0.30, 0) + entry.pivot.global_position - entry.at
		var light := circuit.light.get_ref() as OmniLight3D
		if light != null:
			light.global_position = entry.at + offset
		if circuit.pool != null:
			var pool := circuit.pool.get_ref() as MeshInstance3D
			if pool != null:
				pool.global_position = circuit.pool_at + Vector3(offset.x, 0, offset.z) * 5.0
		var shadow_at: Vector3 = entry.at + Vector3(offset.x, 0, offset.z) * 6.0
		shadow_at.y = _floor_y(shadow_at) + 0.026
		entry.shadow.global_transform = Transform3D(Basis.IDENTITY, shadow_at)
		(entry.shadow.material_override as ShaderMaterial).set_shader_parameter("opacity", 0.15 * float(circuit.average) if enabled else 0.0)
		if enabled:
			admitted += 1
	set_meta("active_moving_pendants", admitted)

func _floor_y(at: Vector3) -> float:
	var terrain := _scene.get_node_or_null("TestArena")
	if terrain != null and "arena_variant" in _scene and str(_scene.get("arena_variant")) == "test":
		return float(terrain.call("height_at", at))
	return 0.0

func _contact(at: Vector3, direction: Vector3, _surface: String, power: float) -> void:
	if not _initialized or not _workshop.is_inside_tree() or not _workshop.is_visible_in_tree():
		return
	var director := _scene.get_node_or_null("OrganicWorldDetails")
	if director == null or not bool(director.call("_visible", at)):
		return
	for entry in _pendants:
		var distance: float = entry.at.distance_to(at)
		if distance < 5.0:
			entry.velocity += clampf(power, 0.0, 1.5) * (1.0 - distance / 5.0) * 0.45
	for entry in _fixtures:
		var distance: float = entry.node.global_position.distance_to(at)
		if distance < 3.5:
			entry.gust = direction * power * (1.0 - distance / 3.5)
			var circuit := _circuits[int(entry.circuit)]
			if int(circuit.mode) in [0, 1]:
				circuit.fault_until = _clock + 0.16

func _motion(at: Vector3, direction: Vector3, power: float) -> void:
	_contact(at + Vector3.UP * 0.25, direction, "motion", power * 0.45)

func reset_transients() -> void:
	for entry in _fixtures:
		entry.node.call("reset_transients")
		entry.gust = Vector3.ZERO
	for entry in _pendants:
		entry.velocity = 0.0
		entry.angle = 0.0
		entry.pivot.rotation = Vector3.ZERO
		entry.shadow.hide()
		var circuit := _circuits[int(entry.circuit)]
		var light := circuit.light.get_ref() as OmniLight3D
		if light != null and light.is_inside_tree():
			light.global_position = entry.at
		if circuit.pool != null:
			var pool := circuit.pool.get_ref() as MeshInstance3D
			if pool != null and pool.is_inside_tree():
				pool.global_position = circuit.pool_at
	for circuit in _circuits:
		circuit.arc = 0.0
		circuit.fault_until = -1.0
	set_meta("active_service_fixtures", 0)
	set_meta("active_moving_pendants", 0)
	if _initialized:
		_update_circuits()

func get_debug_counts() -> Dictionary:
	return {"circuits": _circuits.size(), "materials": _materials.size(), "fixtures": _fixtures.size(), "pendants": _pendants.size(), "active_fixtures": int(get_meta("active_service_fixtures", 0)), "active_pendants": int(get_meta("active_moving_pendants", 0)), "clock": _clock, "initialized": _initialized}
