extends Node3D
## Bounded workshop reactions driven by the existing scenery and combat signals.
const WIND := preload("res://scripts/environment/scenery_wind.gd")
const AIR := preload("res://scripts/environment/ecosystem_air.gdshader")
const HEAT := preload("res://scripts/environment/ecosystem_heat.gdshader")
const SCORCH := preload("res://scripts/environment/ecosystem_scorch.gdshader")
const MAX_STATIONS := 16
const MAX_DUST := 48
const MAX_SCORCHES := 16
const CABLE_SEGMENTS := 12
var _ambience: Node3D
var _workshop: Node3D
var _scene: Node3D
var _life: Node3D
var _organic: Node
var _stations: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _scorches: Array[Dictionary] = []
var _shots: Array[Dictionary] = []
var _scatter: Dictionary = {}
var _batches: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _low := false
var _hidden := false
var _rejected := 0
var _max_cable_extent := 0.0

static func install(ambience: Node3D) -> void:
	if ambience.has_node("WorkshopEcosystem"):
		return
	var node := load("res://scripts/environment/workshop_ecosystem.gd").new() as Node3D
	node.name = "WorkshopEcosystem"
	ambience.add_child(node)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 123
	top_level = true
	global_transform = Transform3D.IDENTITY
	_ambience = get_parent() as Node3D
	_workshop = _ambience.get_parent() as Node3D
	_life = _ambience.get_node_or_null("SceneryLife") as Node3D
	_scene = _workshop
	while _scene != null and not _scene.has_node("CameraRig"):
		_scene = _scene.get_parent() as Node3D
	if _scene == null or _life == null:
		set_process(false)
		return
	_organic = _scene.get_node_or_null("OrganicWorldDetails")
	_rng.seed = absi(("Workshop ecosystem / " + str(_workshop.get_meta("reference_map", "classic"))).hash())
	_make_batches()
	_make_stations()
	var manager := _scene.get_node_or_null("VFXManager")
	if manager != null:
		manager.connect("organic_contact", _contact)
		manager.connect("organic_shot", _shot)
		manager.connect("presentation_cleared", reset_transients)
	get_tree().node_added.connect(_node_added)
	set_meta("visual_only", true)
	_process(0.0)

func _make_batches() -> void:
	var metal := StandardMaterial3D.new()
	metal.vertex_color_use_as_albedo = true
	metal.metallic = 0.55
	metal.roughness = 0.48
	_batch("panels", _panel_mesh(), metal, MAX_STATIONS)
	var cable := CylinderMesh.new()
	cable.top_radius = 0.012
	cable.bottom_radius = 0.012
	cable.height = 1.0
	cable.radial_segments = 6
	cable.rings = 1
	var cable_material := StandardMaterial3D.new()
	cable_material.albedo_color = Color("#383d37")
	cable_material.roughness = 0.65
	_batch("cables", cable, cable_material, MAX_STATIONS * CABLE_SEGMENTS)
	_batch("housings", _vent_mesh(), metal, MAX_STATIONS)
	var slat := BoxMesh.new()
	slat.size = Vector3(0.30, 0.013, 0.063)
	_batch("louvers", slat, metal, MAX_STATIONS * 3)
	var dust := QuadMesh.new()
	dust.size = Vector2.ONE
	_batch("dust", dust, _shader(AIR, 0), MAX_DUST + 24)
	var insect := QuadMesh.new()
	insect.size = Vector2(0.040, 0.026)
	_batch("insects", insect, _shader(AIR, 1), 12)
	var heat := QuadMesh.new()
	heat.size = Vector2(0.35, 0.62)
	_batch("heat", heat, _shader(HEAT), 2)
	var scorch := QuadMesh.new()
	scorch.size = Vector2.ONE
	_batch("scorches", scorch, _shader(SCORCH), MAX_SCORCHES)
	var sheen := QuadMesh.new()
	sheen.size = Vector2.ONE
	_batch("sheen", sheen, _shader(AIR, 2), 8)

func _shader(shader: Shader, kind: int = -1) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	if kind >= 0:
		material.set_shader_parameter("kind", kind)
	_materials.append(material)
	return material

func _batch(key: String, mesh: Mesh, material: Material, capacity: int) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.use_custom_data = true
	batch.mesh = mesh
	batch.instance_count = capacity
	batch.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = key.capitalize()
	node.multimesh = batch
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_batches[key] = batch

func _make_stations() -> void:
	var circuits: Array = _ambience.get("_circuits")
	for anchor in _life.get("_hanging"):
		if _stations.size() >= MAX_STATIONS:
			break
		var circuit: Dictionary = circuits[int(anchor.circuit)]
		var out: Vector3 = circuit.out
		var axis: Vector3 = circuit.axis
		var panel: Vector3 = _life.call("_accessible_face", circuit.at - axis * 0.87 + Vector3.DOWN * 0.96 + out * 0.04, out, 0.055)
		var cable: Vector3 = _life.call("_accessible_face", circuit.at + axis * 0.32 + Vector3.DOWN * 0.29 + out * 0.04, out, 0.060)
		var vent: Vector3 = circuit.at + out * 0.03
		vent.y = float(_life.call("_floor_y", vent)) + 0.37
		vent = _life.call("_accessible_face", vent, out, 0.065)
		var fixtures: Array = _ambience.get("_fixtures")
		var matching := fixtures.filter(func(entry: Dictionary) -> bool: return entry.circuit == circuit.id)
		var fixture: Node3D = matching[0].node if not matching.is_empty() else null
		var heat_at := fixture.to_global(Vector3(0.57, 0.54, 0.14)) if fixture != null else panel + Vector3.UP * 0.4
		heat_at = _life.call("_accessible_face", heat_at, out, 0.16)
		_stations.append({"circuit": circuit.id, "out": out, "axis": axis, "basis": Basis(axis, Vector3.UP, out), "panel": panel, "cable": cable, "vent": vent, "heat_at": heat_at, "fixture": weakref(fixture) if fixture != null else null, "phase": _rng.randf_range(0, TAU), "angle": 0.0, "velocity": 0.0, "wave": 0.0, "vent_open": 0.0, "heat": 0.0, "flash": -100.0, "flash_power": 0.0, "last_power": circuit.average, "cooldown": 0.0})

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
	var focus := (_scene.get_node("CameraRig") as Node3D).global_position
	var camera := get_viewport().get_camera_3d()
	var step := minf(delta, 0.05)
	_update_dust(step, delta)
	_update_scorches(delta)
	for index in range(_shots.size() - 1, -1, -1):
		if _clock - float(_shots[index].clock) > 2.5:
			_shots.remove_at(index)
	for id in _scatter.keys():
		if _clock > float(_scatter[id]):
			_scatter.erase(id)
	_draw_stations(step, focus, camera)
	_draw_insects(focus, camera)
	_draw_scorches(focus)
	for material in _materials:
		material.set_shader_parameter("clock", _clock)

func _draw_stations(delta: float, focus: Vector3, camera: Camera3D) -> void:
	var chosen: Array = _life.call("_near", _stations, focus, "vent", 2 if _low else 4)
	var wind_clock := float(_life.call("wind_clock"))
	var circuits: Array = _ambience.get("_circuits")
	var panels: MultiMesh = _batches.panels
	var cables: MultiMesh = _batches.cables
	var housings: MultiMesh = _batches.housings
	var louvers: MultiMesh = _batches.louvers
	var heat: MultiMesh = _batches.heat
	var sheen: MultiMesh = _batches.sheen
	var segments := 6 if _low else CABLE_SEGMENTS
	var heat_count := 0
	var sheen_count := 0
	var cable_count := 0
	_max_cable_extent = 0.0
	var dust_count := _draw_dust(focus, camera)
	for station in _stations:
		var enabled := station in chosen
		var circuit: Dictionary = circuits[int(station.circuit)]
		if enabled and float(circuit.average) - float(station.last_power) > 0.25:
			_flash(station, 0.75)
		station.last_power = circuit.average
		station.cooldown = maxf(0.0, float(station.cooldown) - delta)
		station.wave = float(station.wave) * exp(-delta * 2.5)
		if not enabled:
			station.velocity = 0.0
			station.angle = 0.0
			station.heat = 0.0
			station.vent_open = 0.0
			continue
		var index := chosen.find(station)
		var gust := WIND.strength(wind_clock, station.panel) if not _low else 0.0
		var target := sin(_clock * 0.7 + float(station.phase)) * 0.012 + gust * 0.12
		station.velocity += (target - float(station.angle)) * delta * 18.0
		station.velocity *= exp(-delta * 3.0)
		station.angle = clampf(float(station.angle) + float(station.velocity) * delta, -0.38, 0.38)
		var panel_basis: Basis = station.basis * Basis(Vector3.RIGHT, float(station.angle))
		panels.set_instance_transform(index, Transform3D(panel_basis, station.panel))
		panels.set_instance_color(index, Color.WHITE)
		for segment in segments:
			var a := cable_point(station, float(segment) / segments, wind_clock)
			var b := cable_point(station, float(segment + 1) / segments, wind_clock)
			var direction := b - a
			var basis := Basis(Quaternion(Vector3.UP, direction.normalized())) * Basis.from_scale(Vector3(1, direction.length() + 0.012, 1))
			_max_cable_extent = maxf(_max_cable_extent, basis.y.length())
			cables.set_instance_transform(cable_count, Transform3D(basis, (a + b) * 0.5))
			cable_count += 1
		var fixture := station.fixture.get_ref() as Node3D if station.fixture != null else null
		var flow := clampf(float(fixture.get("fan_speed")) / 9.0, 0.0, 1.0) if fixture != null and fixture.is_visible_in_tree() else 0.0
		station.vent_open = lerpf(float(station.vent_open), flow, 1.0 - exp(-delta * 3.2))
		station.heat = lerpf(float(station.heat), flow, 1.0 - exp(-delta * (0.75 if flow > float(station.heat) else 0.28)))
		housings.set_instance_transform(index, Transform3D(station.basis, station.vent))
		housings.set_instance_color(index, Color.WHITE)
		for slat in 3:
			var at: Vector3 = station.vent + Vector3.UP * (0.068 - slat * 0.068) + station.out * 0.032
			var basis: Basis = station.basis * Basis(Vector3.RIGHT, -0.12 - float(station.vent_open) * 0.90)
			louvers.set_instance_transform(index * 3 + slat, Transform3D(basis, at))
			louvers.set_instance_color(index * 3 + slat, Color("#9b9c8a"))
		_life.call("apply_airflow", station.vent + station.out * 0.04, station.out, flow, delta)
		if not _low and camera != null:
			dust_count = _vent_dust(station, flow, camera, dust_count)
			if heat_count < 2 and float(station.heat) > 0.05:
				var source: Vector3 = station.heat_at
				heat.set_instance_transform(heat_count, Transform3D(camera.global_basis.orthonormalized(), source))
				heat.set_instance_custom_data(heat_count, Color(float(station.phase), float(station.heat), 0, 0))
				heat_count += 1
		var age := _clock - float(station.flash)
		if age < 0.42 and sheen_count < (2 if _low else 8):
			var tint: Color = (circuit.color as Color).lerp(Color("#e2dbbb"), 0.72)
			var at: Vector3 = station.panel + panel_basis * Vector3(0, -0.145, 0.020)
			sheen.set_instance_transform(sheen_count, Transform3D(panel_basis * Basis.from_scale(Vector3(0.38, 0.28, 1)), at))
			sheen.set_instance_color(sheen_count, Color(tint, 0.38 * float(station.flash_power)))
			sheen.set_instance_custom_data(sheen_count, Color(0, age, 0, 0))
			sheen_count += 1
			if not _low and fixture != null and fixture.is_visible_in_tree() and sheen_count < 8:
				var hardware: Transform3D = fixture.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.082))
				hardware.basis *= Basis.from_scale(Vector3(0.77, 0.40, 1))
				sheen.set_instance_transform(sheen_count, hardware)
				sheen.set_instance_color(sheen_count, Color(tint, 0.30 * float(station.flash_power)))
				sheen.set_instance_custom_data(sheen_count, Color(0, age, 0, 0))
				sheen_count += 1
	panels.visible_instance_count = chosen.size()
	housings.visible_instance_count = chosen.size()
	louvers.visible_instance_count = chosen.size() * 3
	cables.visible_instance_count = cable_count
	heat.visible_instance_count = heat_count
	sheen.visible_instance_count = sheen_count
	(_batches.dust as MultiMesh).visible_instance_count = dust_count

func cable_point(station: Dictionary, t: float, wind_clock: float) -> Vector3:
	var free := sin(t * PI)
	var wave := sin(t * 10.0 - _clock * 13.0) * float(station.wave)
	var gust := WIND.strength(wind_clock, station.cable) * 0.05 if not _low else 0.0
	return station.cable + station.axis * ((t - 0.5) * 1.18) + Vector3.DOWN * free * 0.15 + station.out * free * (wave + gust)

func _vent_dust(station: Dictionary, flow: float, camera: Camera3D, offset: int) -> int:
	if flow < 0.05:
		return offset
	var batch: MultiMesh = _batches.dust
	for index in 6:
		var t := fposmod(_clock * (0.35 + flow * 0.6) + index * 0.618 + float(station.phase), 1.0)
		var exhaust := index >= 3
		var point: Vector3 = station.vent + station.out * ((0.10 + t * 0.85) if exhaust else (0.10 + (1.0 - t) * 0.55))
		point += station.axis * sin(float(index) * 2.4 + t * 4.0) * 0.08 + Vector3.UP * ((-0.10 - t * 0.18) if exhaust else (0.15 + (1.0 - t) * 0.15))
		var size := 0.025 + t * 0.030
		batch.set_instance_transform(offset, Transform3D(camera.global_basis.orthonormalized().scaled(Vector3.ONE * size), point))
		batch.set_instance_color(offset, Color(0.58, 0.49, 0.34, sin(t * PI) * flow * 0.32))
		offset += 1
	return offset

func _draw_insects(focus: Vector3, camera: Camera3D) -> void:
	var batch: MultiMesh = _batches.insects
	batch.visible_instance_count = 0
	if _low or camera == null:
		return
	var lamps: Array[Dictionary] = []
	for circuit in _ambience.get("_circuits"):
		var light := circuit.light.get_ref() as OmniLight3D
		if not circuit.neon and light != null and light.is_visible_in_tree() and float(circuit.average) > 0.05 and light.global_position.distance_squared_to(focus) < 150.0:
			lamps.append(circuit)
	lamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.light.get_ref() as OmniLight3D).global_position.distance_squared_to(focus) < (b.light.get_ref() as OmniLight3D).global_position.distance_squared_to(focus))
	var count := 0
	var observer := _organic.get("observer") as Node3D if _organic != null else null
	for circuit in lamps.slice(0, 3):
		var light := circuit.light.get_ref() as OmniLight3D
		if observer != null and bool(_organic.call("_is_active")):
			var offset := light.global_position - observer.global_position
			if Vector2(offset.x, offset.z).length() < 1.4 and absf(offset.y) < 3.5:
				_scatter[int(circuit.id)] = _clock + 0.85
		var fleeing := clampf((float(_scatter.get(int(circuit.id), -1.0)) - _clock) / 0.85, 0.0, 1.0)
		for index in 4:
			var phase: float = float(circuit.phase) + index * 2.399
			var radius := 0.13 + index * 0.022 + fleeing * 0.40
			var point := light.global_position + Vector3(sin(_clock * 2.0 + phase) * radius, -0.09 + cos(_clock * 2.6 + phase) * radius * 0.5, cos(_clock * 1.7 + phase) * radius)
			batch.set_instance_transform(count, Transform3D(camera.global_basis.orthonormalized(), point))
			batch.set_instance_color(count, Color(0.22, 0.20, 0.12, 0.74 * (1.0 - fleeing * 0.30)))
			batch.set_instance_custom_data(count, Color(phase, fleeing, 0, 0))
			count += 1
	batch.visible_instance_count = count

func _contact(at: Vector3, normal: Vector3, surface: String, power: float) -> void:
	if not _admitted(at) or surface not in ["metal", "concrete", "environment", "sand"]:
		_rejected += 1
		return
	for station in _stations:
		var distance: float = (station.panel as Vector3).distance_to(at)
		if distance < 3.4 and bool(_organic.call("_visible", station.panel + station.out * 0.02)):
			station.velocity = clampf(float(station.velocity) + power * (1.0 - distance / 3.4) * 1.7, -3.0, 3.0)
			station.wave = maxf(float(station.wave), power * (1.0 - distance / 3.4) * 0.13)
			_flash(station, clampf(power, 0.0, 1.0))
			if station.cooldown <= 0.0:
				station.cooldown = 0.35
				_shed_dust(station, power)
	for circuit in _ambience.get("_circuits"):
		if not circuit.neon and (circuit.at as Vector3).distance_to(at) < 3.5:
			_scatter[int(circuit.id)] = _clock + 0.85
	# Only a matching, locally admitted energy shot heats a real solid contact.
	for index in range(_shots.size() - 1, -1, -1):
		var shot := _shots[index]
		if (shot.at as Vector3).distance_to(at) < 0.55:
			_add_scorch(at, normal, power, shot.owner)
			_shots.remove_at(index)
			break

func _shot(socket: Node3D, weapon: String, _charge: float) -> void:
	if not _workshop.is_visible_in_tree() or _organic == null or weapon not in ["blaster", "longshot", "enemy"]:
		return
	var actor: Node = socket
	while actor != null and not actor.has_method("get_health"):
		actor = actor.get_parent()
	if not bool(_organic.call("_admitted", actor as Node3D)):
		return
	var start := socket.global_position
	var finish := start - socket.global_basis.z * 48.0
	var ray := PhysicsRayQueryParameters3D.create(start, finish, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		finish = hit.position
		while _shots.size() >= (4 if _low else 8):
			_shots.pop_front()
		_shots.append({"at": finish, "clock": _clock, "owner": weakref(hit.collider)})
	for station in _stations:
		var closest := Geometry3D.get_closest_point_to_segment(station.panel, start, finish)
		if closest.distance_to(station.panel) < 1.8 and _admitted(closest):
			_flash(station, 0.65)

func _node_added(node: Node) -> void:
	if node is Node3D and String(node.name) in ["RocketImpact", "RocketIntercept"]:
		_blast.call_deferred(weakref(node))

func _blast(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node3D
	if node != null and _scene.is_ancestor_of(node):
		_contact(node.global_position, Vector3.UP, "environment", 1.6)

func _admitted(at: Vector3) -> bool:
	return _workshop.is_visible_in_tree() and _organic != null and bool(_organic.call("_visible", at))

func _flash(station: Dictionary, power: float) -> void:
	station.flash = _clock
	station.flash_power = power

func _shed_dust(station: Dictionary, power: float) -> void:
	var limit := 16 if _low else MAX_DUST
	for index in (3 if _low else 8):
		while _dust.size() >= limit:
			_dust.pop_front()
		var at: Vector3 = station.panel + Vector3.UP * 0.45 + station.axis * _rng.randf_range(-0.32, 0.32) + station.out * 0.16
		_dust.append({"at": at, "velocity": station.out * _rng.randf_range(0.04, 0.18) + Vector3.DOWN * 0.12, "age": 0.0, "life": _rng.randf_range(1.3, 1.9), "size": _rng.randf_range(0.035, 0.080) * clampf(power, 0.6, 1.2)})

func _update_dust(step: float, delta: float) -> void:
	while _dust.size() > (16 if _low else MAX_DUST):
		_dust.pop_front()
	for index in range(_dust.size() - 1, -1, -1):
		var entry := _dust[index]
		entry.age += delta
		if entry.age >= entry.life:
			_dust.remove_at(index)
			continue
		entry.velocity += Vector3.DOWN * 1.8 * step
		entry.at += (entry.velocity + WIND.velocity(float(_life.call("wind_clock")), entry.at) * 0.16) * step
		entry.at.y = maxf(float(entry.at.y), float(_life.call("_floor_y", entry.at)) + 0.02)

func _draw_dust(focus: Vector3, camera: Camera3D) -> int:
	if camera == null:
		return 0
	var batch: MultiMesh = _batches.dust
	var count := 0
	for entry in _dust:
		if (entry.at as Vector3).distance_squared_to(focus) > 180.0:
			continue
		var size: float = float(entry.size) * (1.0 + float(entry.age) * 0.45)
		batch.set_instance_transform(count, Transform3D(camera.global_basis.orthonormalized().scaled(Vector3.ONE * size), entry.at))
		batch.set_instance_color(count, Color(0.58, 0.49, 0.34, sin(float(entry.age) / float(entry.life) * PI) * 0.42))
		count += 1
	return count

func _add_scorch(at: Vector3, normal: Vector3, power: float, owner: WeakRef) -> void:
	var limit := 6 if _low else MAX_SCORCHES
	while _scorches.size() >= limit:
		_scorches.pop_front()
	var axis := Vector3.UP.cross(normal).normalized()
	if axis.length_squared() < 0.01:
		axis = Vector3.RIGHT
	var basis := Basis(axis, normal.cross(axis).normalized(), normal)
	_scorches.append({"at": at + normal * 0.008, "basis": basis, "age": 0.0, "life": 3.0 if _low else 6.0, "size": clampf(power * 0.20, 0.14, 0.30), "phase": _rng.randf_range(0, TAU), "owner": owner})

func _update_scorches(delta: float) -> void:
	while _scorches.size() > (6 if _low else MAX_SCORCHES):
		_scorches.pop_front()
	for index in range(_scorches.size() - 1, -1, -1):
		var entry := _scorches[index]
		entry.age += delta
		if entry.age >= entry.life or entry.owner.get_ref() == null:
			_scorches.remove_at(index)

func _draw_scorches(focus: Vector3) -> void:
	var batch: MultiMesh = _batches.scorches
	var count := 0
	for entry in _scorches:
		if (entry.at as Vector3).distance_squared_to(focus) > 180.0:
			continue
		batch.set_instance_transform(count, Transform3D((entry.basis as Basis).scaled(Vector3.ONE * float(entry.size)), entry.at))
		batch.set_instance_custom_data(count, Color(float(entry.phase), float(entry.age), 1.0 - smoothstep(float(entry.life) * 0.5, float(entry.life), float(entry.age)), 0))
		count += 1
	batch.visible_instance_count = count

func reset_transients() -> void:
	_dust.clear()
	_scorches.clear()
	_shots.clear()
	_scatter.clear()
	for station in _stations:
		station.angle = 0.0
		station.velocity = 0.0
		station.wave = 0.0
		station.vent_open = 0.0
		station.heat = 0.0
		station.flash = -100.0
		station.flash_power = 0.0
		station.cooldown = 0.0
	for batch in _batches.values():
		(batch as MultiMesh).visible_instance_count = 0

func _panel_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3(0, -0.14, 0), Vector3(0.38, 0.28, 0.025), Color("#7b857b")], [Vector3(0, 0.008, 0), Vector3(0.40, 0.024, 0.032), Color("#ada68d")], [Vector3(-0.10, -0.15, 0.018), Vector3(0.022, 0.11, 0.012), Color("#4c5755")], [Vector3(0.02, -0.15, 0.018), Vector3(0.022, 0.11, 0.012), Color("#4c5755")], [Vector3(0.13, -0.18, 0.014), Vector3(0.065, 0.065, 0.002), Color("#9d6444")]]:
		var box := BoxMesh.new()
		box.size = part[1]
		_life.call("_colored_part", tool, box, Transform3D(Basis.IDENTITY, part[0]), part[2])
	tool.index()
	return tool.commit()

func _vent_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3.ZERO, Vector3(0.35, 0.25, 0.025), Color("#343a35")], [Vector3(-0.186, 0, 0.012), Vector3(0.024, 0.29, 0.035), Color("#8b907e")], [Vector3(0.186, 0, 0.012), Vector3(0.024, 0.29, 0.035), Color("#8b907e")], [Vector3(0, 0.137, 0.012), Vector3(0.40, 0.024, 0.035), Color("#8b907e")], [Vector3(0, -0.137, 0.012), Vector3(0.40, 0.024, 0.035), Color("#8b907e")]]:
		var box := BoxMesh.new()
		box.size = part[1]
		_life.call("_colored_part", tool, box, Transform3D(Basis.IDENTITY, part[0]), part[2])
	tool.index()
	return tool.commit()

func get_debug_counts() -> Dictionary:
	var counts := {"stations": _stations.size(), "dust_pool": _dust.size(), "scorch_pool": _scorches.size(), "energy_shots": _shots.size(), "scattered_lamps": _scatter.size(), "clock": _clock, "rejected": _rejected, "cable_section_max": _max_cable_extent}
	for key in _batches:
		counts[key + "_visible"] = (_batches[key] as MultiMesh).visible_instance_count
	return counts
