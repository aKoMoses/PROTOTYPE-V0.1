extends Node3D

## A round-controlled clock: telegraph, non-damaging sweep, then cover rotation.
## The compact arena controller owns pause/lifecycle, sounds and collision casts.
const GRACE := 4.0
const WARNING := 1.8
const SWEEP := 2.2
const COVER_WARNING := 1.0
const ROTATE := 2.0
const REST := 2.0
const REACH := 6.8
const COVER_RADIUS := 4.4
const COVER_SIZE := Vector3(0.65, 2.0, 3.0)
const CONTACT_CLEARANCE := 0.70
const CONTACT_CORRECTION_SPEED := 8.0
const AMBER := Color("#ffbf54")

var controller: Node3D
var phase := "grace"
var remaining := GRACE
var cycles := 0
var pushes := 0
var cover_angle := 0.0
var arm_angle := -PI * 0.5
var sweep_start := -PI * 0.5
var hit: Dictionary = {}
var arm: Node3D
var covers: Array[StaticBody3D] = []
var warning_sector: MeshInstance3D
var rotation_marks: Node3D
var warning_material: StandardMaterial3D
var cover_material: StandardMaterial3D
var _minimap_angle := INF

func _ready() -> void:
	controller = get_parent()
	name = "ClockworkMechanism"
	var brass: StandardMaterial3D = controller.call("_material", Color("#a57b45"), 0.45)
	var dark: StandardMaterial3D = controller.call("_material", Color("#373343"), 0.65)
	warning_material = controller.call("_material", Color(1.0, 0.65, 0.2, 0.19), 0.5, AMBER, 0.35)
	warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cover_material = controller.call("_material", AMBER, 0.5, AMBER, 0.2)
	var hub := _body("ClockSpindle", CylinderShape3D.new())
	(hub.get_child(0).shape as CylinderShape3D).radius = 0.72
	(hub.get_child(0).shape as CylinderShape3D).height = 1.5
	hub.get_child(0).position.y = 0.75
	controller.call("_cylinder", hub, Vector3(0, 0.65, 0), 0.72, 1.3, brass)
	controller.call("_cylinder", hub, Vector3(0, 0.14, 0), 1.05, 0.18, dark)
	for index in range(16):
		var angle := index * TAU / 16.0
		var tooth: Node3D = controller.call("_box", self, Vector3(cos(angle), 0.18, sin(angle)), Vector3(0.32, 0.17, 0.24), brass)
		tooth.rotation.y = -angle
	arm = Node3D.new()
	arm.name = "SweepingPendulum"
	add_child(arm)
	controller.call("_cylinder", arm, Vector3(0, 1.5, 0), 0.17, 1.3, brass)
	controller.call("_box", arm, Vector3(REACH * 0.5, 1.1, 0), Vector3(REACH, 0.13, 0.13), brass)
	var bob := SphereMesh.new()
	bob.radius = 0.55
	bob.height = 1.1
	bob.radial_segments = 12
	bob.rings = 6
	controller.call("_mesh", arm, Vector3(REACH, 0.85, 0), bob, brass)
	for side in [-1.0, 1.0]:
		var shape := BoxShape3D.new()
		shape.size = COVER_SIZE
		var body := _body("PivotCover", shape)
		body.get_child(0).position.y = 1.0
		controller.call("_box", body, Vector3(0, 1, 0), COVER_SIZE, dark)
		for z in [-1.5, 1.5]:
			controller.call("_box", body, Vector3(0, 1, z), Vector3(0.76, 2.1, 0.12), brass)
		controller.call("_box", body, Vector3(0, 2.04, 0), Vector3(0.72, 0.08, 3.1), cover_material)
		covers.append(body)
		body.set_meta("side", side)
	var track: Node3D = controller.call("_torus", self, Vector3(0, 0.035, 0), COVER_RADIUS - 0.03, COVER_RADIUS + 0.03, brass)
	track.scale.y = 0.15
	rotation_marks = Node3D.new()
	rotation_marks.name = "CoverRotationWarning"
	add_child(rotation_marks)
	for index in range(32):
		var angle := index * TAU / 32.0
		var mark: Node3D = controller.call("_box", rotation_marks, Vector3(cos(angle) * COVER_RADIUS, 0.06, sin(angle) * COVER_RADIUS), Vector3(0.3, 0.025, 0.10), cover_material)
		mark.rotation.y = -angle - PI * 0.25
	warning_sector = MeshInstance3D.new()
	warning_sector.name = "PendulumTelegraph"
	warning_sector.mesh = _sector_mesh()
	warning_sector.material_override = warning_material
	warning_sector.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(warning_sector)
	reset_round()

func _body(label: String, shape: Shape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("arena_solid")
	add_child(body)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var main := controller.get_parent()
	if main != null and "_arena_blockers" in main:
		main.get("_arena_blockers").append(body)
	return body

func _sector_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	for index in range(48):
		var a := PI * index / 48.0
		var b := PI * (index + 1) / 48.0
		vertices.append_array(PackedVector3Array([Vector3(0, 0.065, 0), Vector3(cos(b) * (REACH + 0.65), 0.065, sin(b) * (REACH + 0.65)), Vector3(cos(a) * (REACH + 0.65), 0.065, sin(a) * (REACH + 0.65))]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func reset_round() -> void:
	phase = "grace"
	remaining = GRACE
	cycles = 0
	pushes = 0
	cover_angle = 0.0
	arm_angle = -PI * 0.5
	sweep_start = arm_angle
	hit.clear()
	_apply_covers(cover_angle)
	_update_visuals()

func advance(delta: float) -> void:
	# Substeps prevent a fast arm or a long test frame from skipping a robot.
	var pending := delta
	while pending > 0.000001:
		var step := minf(pending, 1.0 / 60.0)
		pending -= step
		if phase == "rotate":
			var next_angle := cover_angle + PI * 0.5 / ROTATE * step
			if _covers_clear(next_angle):
				cover_angle = next_angle
				_apply_covers(cover_angle)
			else:
				# Never put a solid inside a combatant. Wait until the route clears.
				continue
		remaining = maxf(0.0, remaining - step)
		if phase == "sweep":
			arm_angle = sweep_start + PI * (1.0 - remaining / SWEEP)
			_push_actors(step)
		if remaining <= 0.000001:
			_next_phase()
	_update_visuals()

func _next_phase() -> void:
	match phase:
		"grace", "rest":
			phase = "warning"
			remaining = WARNING
			sweep_start = arm_angle
			hit.clear()
			controller.call("_request_sound", "trap_tile_warning", global_position)
		"warning":
			phase = "sweep"
			remaining = SWEEP
			controller.call("_request_sound", "trap_tile_discharge", global_position)
		"sweep":
			phase = "cover_warning"
			remaining = COVER_WARNING
			controller.call("_request_sound", "trap_tile_warning", global_position)
		"cover_warning":
			phase = "rotate"
			remaining = ROTATE
		"rotate":
			cycles += 1
			cover_angle = cycles * PI * 0.5
			_apply_covers(cover_angle)
			phase = "rest"
			remaining = REST

func _apply_covers(angle: float) -> void:
	for body in covers:
		var a := angle + (PI if float(body.get_meta("side")) < 0.0 else 0.0)
		body.position = Vector3(cos(a) * COVER_RADIUS, 0, sin(a) * COVER_RADIUS)
		body.rotation.y = -a

func _covers_clear(angle: float) -> bool:
	for body in covers:
		var a := angle + (PI if float(body.get_meta("side")) < 0.0 else 0.0)
		var at := global_position + Vector3(cos(a) * COVER_RADIUS, 0, sin(a) * COVER_RADIUS)
		# Query the proposed real shape against all actor layers (not the floor).
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body.get_child(0).shape
		query.transform = Transform3D(Basis(Vector3.UP, -a), at + Vector3.UP)
		query.collision_mask = 2 | 4 | 8
		query.margin = 0.18
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true

func _push_actors(delta: float) -> void:
	var direction := Vector3(cos(arm_angle), 0, sin(arm_angle))
	for actor in controller.get("_actors"):
		if not controller.call("_live_actor", actor):
			continue
		var offset: Vector3 = actor.global_position - global_position
		if absf(offset.y) > 1.8:
			continue
		offset.y = 0.0
		var along := offset.dot(direction)
		if along < 1.05 or along > REACH + 0.6:
			continue
		if (offset - direction * clampf(along, 1.05, REACH)).length() > 0.85:
			continue
		var tangent := Vector3(-direction.z, 0, direction.x)
		# Carry the robot with the arm's angular movement at its own radius.
		# A bounded correction keeps it just ahead of the arm, without a burst
		# that would eject it from contact after the first frame.
		var motion := offset.rotated(Vector3.UP, -PI / SWEEP * delta) - offset
		motion += tangent * minf(maxf(0.0, CONTACT_CLEARANCE - offset.dot(tangent)), CONTACT_CORRECTION_SPEED * delta)
		var travel: Vector3 = controller.call("_safe_motion", actor, motion)
		if travel.length_squared() < 0.000001:
			continue
		actor.global_position += travel
		controller.call("_clear_actor_velocity", actor)
		if not hit.has(actor.get_instance_id()):
			hit[actor.get_instance_id()] = true
			pushes += 1
			if actor.has_method("on_permutation_relocated"):
				actor.call("on_permutation_relocated")
		if actor.has_method("refresh_permutation_sweeps"):
			actor.call("refresh_permutation_sweeps")

func _update_visuals() -> void:
	arm.rotation.y = -arm_angle
	warning_sector.rotation.y = -sweep_start
	warning_sector.visible = phase in ["warning", "sweep"]
	rotation_marks.visible = phase in ["cover_warning", "rotate"]
	var pulse := 0.3 + 0.3 * sin(float(controller.get("elapsed")) * 9.0)
	cover_material.emission_energy_multiplier = pulse if rotation_marks.visible else 0.1
	warning_material.albedo_color.a = 0.17 if phase == "warning" else 0.08
	if not is_finite(_minimap_angle) or absf(cover_angle - _minimap_angle) > 0.04:
		_minimap_angle = cover_angle
		var main := controller.get_parent()
		var tracker := main.get_node_or_null("SightTracker") if main != null else null
		if tracker != null and tracker.has_method("_cache_obstacles"):
			tracker.call("_cache_obstacles")

func get_snapshot() -> Dictionary:
	return {"phase": phase, "remaining": remaining, "busy": 1 if phase != "grace" and phase != "rest" else 0,
		"events": cycles, "pushes": pushes, "arm_angle": arm_angle, "cover_angle": cover_angle,
		"phases": [phase], "cover_positions": [covers[0].position, covers[1].position]}

func get_threats() -> Array[Dictionary]:
	var threats: Array[Dictionary] = []
	if phase not in ["warning", "sweep"]:
		return threats
	# Small tile samples reuse the existing bot's avoidance contract.
	for index in range(12):
		var a := sweep_start + (index + 0.5) * PI / 12.0
		for radius in [2.0, 4.0, 6.0]:
			threats.append({"id": cycles * 100 + index, "kind": "tile", "position": global_position + Vector3(cos(a), 0, sin(a)) * radius,
				"size": Vector2(1.6, 1.6), "direction": Vector3.ZERO, "length": 0.0, "half_width": 0.8,
				"remaining": remaining, "phase": "warning" if phase == "warning" else "active"})
	return threats
