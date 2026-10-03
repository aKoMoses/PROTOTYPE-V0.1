extends Node3D

## One height field owns both the visible islands and player/bot traversal.
## The round controller drives the tide; countdowns and pauses do not advance it.
const CATALOG := preload("res://scripts/compact_arena_catalog.gd")
const HEIGHT := 1.35
const CYCLE := 24.0
const HIGH_WATER := 0.90
const SCALE := CATALOG.LAYOUT_SCALE
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled;
uniform float clock = 0.0;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world.xz;
    float wave = sin(p.x * 2.1 + p.y * 3.4 - clock * 2.0);
    float streak = pow(max(0.0, sin(p.x * 6.2 + sin(p.y * 1.7 - clock * 1.8))), 18.0);
    float ripple = pow(max(0.0, sin(p.y * 4.2 - clock * 3.2 + p.x * 1.2)), 12.0);
    ALBEDO = mix(vec3(0.025, 0.24, 0.29), vec3(0.075, 0.48, 0.49), wave * 0.2 + 0.45);
    ALBEDO += vec3(0.25, 0.38, 0.32) * streak * ripple;
    ROUGHNESS = 0.25;
    METALLIC = 0.15;
    NORMAL_MAP = vec3(0.5 + wave * 0.05, 0.5 + sin(p.y * 3.0 - clock) * 0.035, 1.0);
    NORMAL_MAP_DEPTH = 0.13;
    ALPHA = 0.74;
}
"""

var surfaces: Array[StaticBody3D] = []
var islands: Array[PackedVector2Array] = []
var ramps: Array[Dictionary] = []
var barges: Array[Dictionary] = []
var elapsed := 0.0
var water_level := -0.06
var phase := "basse"
var active := false
var _stage: Node3D
var _palette: Dictionary
var _island_tiles: ShaderMaterial
var _water: MeshInstance3D
var _water_material: ShaderMaterial
var _actors: Array[Node3D] = []
var _readouts: Dictionary = {}
var _tide_gauges: Array[MeshInstance3D] = []
var _arrows: Array[Node3D] = []
var _status: Label3D

func configure(stage: Node3D) -> void:
	_stage = stage
	_palette = stage.get("_materials")
	_island_tiles = _palette.floor.duplicate()
	_island_tiles.set_shader_parameter("stone_color", Color("#c3d2c2"))
	_island_tiles.set_shader_parameter("joint_color", Color("#60786e"))
	(_palette.floor as ShaderMaterial).set_shader_parameter("stone_color", Color("#48716e"))
	var left := PackedVector2Array([Vector2(-6.8, -9.7), Vector2(-1.9, -9.7), Vector2(-1.9, -4.2), Vector2(-4.5, -1.2), Vector2(-9.7, -1.2), Vector2(-9.7, -6.8)])
	var right := PackedVector2Array()
	for p in left:
		right.append(Vector2(-p.x, p.y))
	right.reverse()
	var lower := PackedVector2Array([Vector2(-2.5, 3.4), Vector2(2.5, 3.4), Vector2(5.3, 6.2), Vector2(5.3, 9.7), Vector2(-5.3, 9.7), Vector2(-5.3, 6.2)])
	for polygon in [left, right, lower]:
		var outline := _scaled(polygon)
		islands.append(outline)
		_platform(outline, "CombatIsland")
	# A short bridge connects both starting islands. The lower refuge is reached
	# through the basin via three broad ramps, at either water level.
	var bridge := _scaled(PackedVector2Array([Vector2(-2.0, -9.7), Vector2(2.0, -9.7), Vector2(2.0, -7.8), Vector2(-2.0, -7.8)]))
	islands.append(bridge)
	_platform(bridge, "UpperBridge", false)
	_add_ramp(Vector2(-6.4, -1.2) * SCALE, Vector2(-6.4, 2.0) * SCALE, 3.2 * SCALE)
	_add_ramp(Vector2(6.4, -1.2) * SCALE, Vector2(6.4, 2.0) * SCALE, 3.2 * SCALE)
	_add_ramp(Vector2(0, 3.4) * SCALE, Vector2(0, 0.0), 3.6 * SCALE)
	for side in [-1.0, 1.0]:
		_build_barge(side)
		_fixed_planter(Vector3(side * 8.3 * SCALE, HEIGHT + 0.5, -4.2 * SCALE), Vector3(1.4, 1, 2.7))
	_fixed_planter(Vector3(0, HEIGHT + 0.5, 7.7 * SCALE), Vector3(3.0, 1, 1.1))
	_build_water()
	_build_gauges()
	_status = Label3D.new()
	_status.text = "MARÉE BASSE"
	_status.font_size = 58
	_status.pixel_size = 0.012
	_status.outline_size = 10
	_status.modulate = Color("#b6ede2")
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.position = Vector3(0, 2.6, -12.8)
	add_child(_status)
	reset_round()

func configure_actors(actors: Array[Node3D]) -> void:
	_actors.assign(actors)
	for actor in _actors:
		if not is_instance_valid(actor):
			continue
		# A world-space marker for the opponent would reveal its position through
		# fog and cover. The water restriction readout belongs to the local player.
		if actor != get_tree().current_scene.get("player"):
			continue
		var label := Label3D.new()
		label.text = "EAU · ATTAQUE BLOQUÉE"
		label.font_size = 36
		label.pixel_size = 0.007
		label.outline_size = 8
		label.modulate = Color("#76e7e7")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visible = false
		add_child(label)
		_readouts[actor.get_instance_id()] = label

func height_at(point: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	for polygon in islands:
		if Geometry2D.is_point_in_polygon(p, polygon):
			return HEIGHT
	for ramp in ramps:
		var offset: Vector2 = p - ramp.start
		var along: float = offset.dot(ramp.direction)
		var lateral: float = absf(offset.cross(ramp.direction))
		if along >= -0.01 and along <= float(ramp.length) + 0.01 and lateral <= float(ramp.width) * 0.5:
			return HEIGHT * clampf(1.0 - along / float(ramp.length), 0.0, 1.0)
	return 0.0

func segment_walkable(origin: Vector3, destination: Vector3) -> bool:
	if not Geometry2D.is_point_in_polygon(Vector2(destination.x, destination.z), CATALOG.footprint("tideglass")):
		return false
	var steps := maxi(1, ceili(Vector2(destination.x - origin.x, destination.z - origin.z).length() / 0.08))
	var previous := height_at(origin)
	for index in range(1, steps + 1):
		var level := height_at(origin.lerp(destination, float(index) / steps))
		if absf(level - previous) > 0.12:
			return false
		previous = level
	return true

func navigation_extent() -> float:
	return 12.0

func is_submerged(point: Vector3) -> bool:
	return active and water_level > height_at(point) + 0.18

func reset_round() -> void:
	elapsed = 0.0
	water_level = -0.06
	phase = "basse"
	active = false
	_apply_visuals(0.0)

func advance(delta: float) -> void:
	active = true
	elapsed += maxf(0.0, delta)
	var time := fmod(elapsed, CYCLE)
	var amount := 0.0
	if time < 7.0:
		phase = "basse"
	elif time < 10.0:
		phase = "montante"
		amount = smoothstep(7.0, 10.0, time)
	elif time < 18.0:
		phase = "haute"
		amount = 1.0
	else:
		phase = "descendante"
		amount = 1.0 - smoothstep(18.0, 24.0, time)
	water_level = lerpf(-0.06, HIGH_WATER, amount)
	_apply_visuals(amount)
	for actor in _actors:
		if not is_instance_valid(actor):
			continue
		var label: Label3D = _readouts.get(actor.get_instance_id())
		var submerged := is_submerged(actor.global_position)
		if label != null:
			label.visible = submerged and not (actor.has_method("is_real_dead") and actor.call("is_real_dead"))
			label.global_position = actor.global_position + Vector3.UP * 2.6
		if not submerged or (actor.has_method("is_real_dead") and actor.call("is_real_dead")):
			continue
		var controls := actor.get_node_or_null("ControlsComponent")
		if controls != null:
			controls.call("_interrupt_water_attack")
		var controller := actor.get_node_or_null("TrainingBot")
		if controller != null and int(controller.get("_attack_action_token")) != 0:
			controller.call("cancel_action")
		# Currents are slow enough to steer against; walls and ramps stay solid.
		var current := Vector3(0, 0, 0.65 if phase != "descendante" else -0.65) * delta * amount
		var destination := actor.global_position + current
		if segment_walkable(actor.global_position, destination) and not _barge_overlaps(destination, 0.7):
			destination.y = height_at(destination)
			var motion := destination - actor.global_position
			actor.global_position += _swept_current(actor, motion)
			actor.global_position.y = height_at(actor.global_position)

func _swept_current(actor: Node3D, motion: Vector3) -> Vector3:
	for child in actor.get_children():
		if child is CollisionShape3D and child.shape != null and not child.disabled:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = child.global_transform
			query.motion = motion
			query.collision_mask = 1 | 8
			query.exclude = surfaces_rids()
			var excluded: Array[RID] = query.exclude
			if actor is CollisionObject3D:
				excluded.append(actor.get_rid())
			excluded.append(_stage.get_node("CompactFloor").get_rid())
			query.exclude = excluded
			var cast := get_world_3d().direct_space_state.cast_motion(query)
			return motion * maxf(0.0, float(cast[0]) - 0.02)
	return Vector3.ZERO

func surfaces_rids() -> Array[RID]:
	var result: Array[RID] = []
	for body in surfaces:
		result.append(body.get_rid())
	return result

func stop() -> void:
	for label in _readouts.values():
		label.visible = false

func get_snapshot() -> Dictionary:
	return {"phase": phase, "water_level": water_level, "clock": elapsed, "islands": 3,
		"ramps": ramps.size(), "barges": barges.size(), "active": active}

func _scaled(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point * SCALE)
	return result

func _platform(outline: PackedVector2Array, label: String, rim: bool = true) -> void:
	var points := PackedVector3Array()
	for p in outline:
		points.append(Vector3(p.x, 0, p.y))
		points.append(Vector3(p.x, HEIGHT, p.y))
	var body := _solid(label, points, true)
	_stage.call("_prism", body, "PorcelainWall", outline, HEIGHT, Vector3(0, HEIGHT * 0.5, 0), _palette.porcelain)
	_stage.call("_prism", body, "IslandTiles", outline, 0.03, Vector3(0, HEIGHT + 0.015, 0), _island_tiles)
	if rim:
		for index in range(outline.size()):
			var a := outline[index]
			var b := outline[(index + 1) % outline.size()]
			_stage.call("_beam", body, "BrassWaterline", Vector3(a.x, HEIGHT - 0.09, a.y), Vector3(b.x, HEIGHT - 0.09, b.y), 0.045, _palette.gold)

func _add_ramp(start: Vector2, end: Vector2, width: float) -> void:
	var direction := (end - start).normalized()
	var side := Vector2(-direction.y, direction.x) * width * 0.5
	var outline := PackedVector2Array([start - side, start + side, end + side, end - side])
	var points := PackedVector3Array()
	for index in range(4):
		var p := outline[index]
		points.append(Vector3(p.x, HEIGHT if index < 2 else 0.0, p.y))
		points.append(Vector3(p.x, -0.05, p.y))
	var body := _solid("BasinRamp", points, true)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 2, 4, 0, 4, 6]:
		builder.add_vertex(points[index])
	builder.generate_normals()
	var visual := MeshInstance3D.new()
	visual.mesh = builder.commit()
	visual.material_override = _palette.teal_metal
	body.add_child(visual)
	ramps.append({"start": start, "direction": direction, "length": start.distance_to(end), "width": width})
	for rib in range(12):
		var t := (float(rib) + 0.5) / 12.0
		var p := start.lerp(end, t)
		_stage.call("_beam", body, "RampGrip", Vector3(p.x - side.x * 0.93, HEIGHT * (1.0 - t) + 0.024, p.y - side.y * 0.93), Vector3(p.x + side.x * 0.93, HEIGHT * (1.0 - t) + 0.024, p.y + side.y * 0.93), 0.022, _palette.gold)

func _solid(label: String, points: PackedVector3Array, walkable: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("arena_solid")
	body.set_meta("blocks_navigation", not walkable)
	body.set_meta("blocks_projectiles", true)
	body.set_meta("blocks_line_of_sight", true)
	body.set_meta("vfx_surface", "metal")
	add_child(body)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	if walkable:
		surfaces.append(body)
	return body

func _fixed_planter(at: Vector3, size: Vector3) -> void:
	var points := PackedVector3Array()
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				points.append(Vector3(x, y, z) * size)
	var body := _solid("IslandPlanter", points, false)
	body.position = at
	_stage.call("_build_cover", body, size, 1)

func _build_barge(side: float) -> void:
	var size := Vector3(3.9, 1.8, 1.2)
	var points := PackedVector3Array()
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				points.append(Vector3(x, y, z) * size)
	var body := _solid("FloatingPlanter", points, false)
	_stage.call("_build_cover", body, size, int(2 + side))
	var low := Vector3(side * 8.0 * SCALE, 0.93, 4.2 * SCALE)
	var high := Vector3(side * 6.0 * SCALE, 0.93 + HIGH_WATER, 3.6 * SCALE)
	body.position = low
	for edge in [-1.0, 1.0]:
		_stage.call("_beam", self, "BargeGuideRail", Vector3(low.x + edge * 2.05, 0.04, low.z), Vector3(high.x + edge * 2.05, 0.04, high.z), 0.03, _palette.gold)
	barges.append({"body": body, "low": low, "high": high, "size": size})

func _barge_overlaps(point: Vector3, margin: float) -> bool:
	for entry in barges:
		var body: Node3D = entry.body
		var size: Vector3 = entry.size
		if absf(point.x - body.position.x) < size.x * 0.5 + margin and absf(point.z - body.position.z) < size.z * 0.5 + margin:
			return true
	return false

func _build_water() -> void:
	var shader := Shader.new()
	shader.code = WATER_SHADER
	_water_material = ShaderMaterial.new()
	_water_material.shader = shader
	var outline := CATALOG.footprint("tideglass")
	var indices := Geometry2D.triangulate_polygon(outline)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(0, indices.size(), 3):
		for offset in [0, 2, 1]:
			var point := outline[indices[index + offset]]
			builder.add_vertex(Vector3(point.x, 0, point.y))
	builder.generate_normals()
	_water = MeshInstance3D.new()
	_water.name = "TidalWater"
	_water.mesh = builder.commit()
	_water.material_override = _water_material
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	# A few low foam chevrons make the current readable without HUD arrows.
	for z in [-4.0, 0.0, 6.0]:
		for side in [-1.0, 1.0]:
			var arrow := Node3D.new()
			arrow.position = Vector3(side * (1.0 if z < 0 else 7.6), 0, z)
			add_child(arrow)
			for wing in [-1.0, 1.0]:
				_stage.call("_beam", arrow, "CurrentFoam", Vector3(wing * 0.22, 0, -0.30), Vector3(0, 0, 0.1), 0.022, _palette.aqua_glow)
			_arrows.append(arrow)

func _build_gauges() -> void:
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 2.45, 0, -7.0)
		_stage.call("_box", self, "TideGauge", Vector3(0.24, 1.8, 0.18), at + Vector3.UP * 0.9, _palette.teal_metal)
		for index in range(6):
			_stage.call("_box", self, "WaterLevelGraduation", Vector3(0.38, 0.04, 0.08), at + Vector3(0, 0.16 + index * 0.25, 0.12), _palette.porcelain)
		_tide_gauges.append(_stage.call("_box", self, "LevelFloat", Vector3(0.45, 0.13, 0.3), at, _palette.aqua_glow))

func _apply_visuals(amount: float) -> void:
	if _water == null:
		return
	_water.position.y = water_level
	_water.visible = water_level > 0.015
	_water_material.set_shader_parameter("clock", elapsed)
	for entry in barges:
		var body: Node3D = entry.body
		var destination: Vector3 = (entry.low as Vector3).lerp(entry.high, amount)
		var clear := true
		for actor in _actors:
			if is_instance_valid(actor) and absf(actor.global_position.x - destination.x) < float(entry.size.x) * 0.5 + 0.8 and absf(actor.global_position.z - destination.z) < float(entry.size.z) * 0.5 + 0.8:
				clear = false
		if clear:
			body.position = destination
		else:
			body.position.y = destination.y
	for gauge in _tide_gauges:
		gauge.position.y = maxf(0.08, water_level + 0.03)
	for arrow in _arrows:
		arrow.visible = water_level > 0.2
		arrow.position.y = water_level + 0.025
		arrow.rotation.y = PI if phase == "descendante" else 0.0
	if _status != null:
		_status.text = "MARÉE " + phase.to_upper()
		_status.modulate = Color("#ffd17c") if phase == "montante" else Color("#b6ede2")
	# Float only the collectible's presentation: its collection area stays on
	# the basin floor, where actors actually walk and receive healing.
	for child in _stage.get_children():
		if child is RepairKit:
			var visual: Node3D = child.get("_kit_visual")
			if visual != null:
				visual.position.y = maxf(0.0, water_level)
	if not active:
		stop()
