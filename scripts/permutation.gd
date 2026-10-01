extends Node3D

## A locked mark, not a damaging projectile: no collisions, distance cap or
## lifetime. Only the authoritative instance may exchange the live positions.
signal arrived(origin: Vector3, destination: Vector3)
signal failed

const DATA := preload("res://scripts/combat_data.gd")
const TINT := Color("#a797ff")
var caster: Node3D
var target: Node3D
var resolves_swap := true
var _caster_epoch := -1
var _target_epoch := -1
var _elapsed := 0.0
var _trail: Array[MeshInstance3D] = []
var _trail_positions: Array[Vector3] = []
var _arcs: MeshInstance3D
var _arc_clock := 0.0
var _settled := false
var _flight_audio: AudioStreamPlayer3D


static func actor_available(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion():
		return false
	if actor.has_method("is_real_dead") and bool(actor.call("is_real_dead")):
		return false
	if actor.has_method("is_gameplay_enabled") and not bool(actor.call("is_gameplay_enabled")):
		return false
	return actor.global_position.is_finite()


static func epoch(actor: Node3D) -> int:
	return int(actor.call("get_visibility_epoch")) if is_instance_valid(actor) and actor.has_method("get_visibility_epoch") else -1


static func can_activate(source: Node3D, victim: Node3D) -> bool:
	return source != victim and actor_available(source) and actor_available(victim) and source.global_position.distance_to(victim.global_position) <= float(DATA.MODULE_DEFINITIONS.permutation.activation_range)


func configure(source: Node3D, victim: Node3D, authority: bool = true) -> void:
	caster = source
	target = victim
	resolves_swap = authority
	_caster_epoch = epoch(caster)
	_target_epoch = epoch(target)


func _ready() -> void:
	name = "PermutationMark"
	add_to_group("prototype0_gameplay_projectiles")
	process_physics_priority = 20
	_build_shadow()
	if is_instance_valid(caster):
		global_position = caster.global_position + Vector3.UP * 0.95
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.call("play_module_event", "permutation_send", global_position)
	_flight_audio = AudioStreamPlayer3D.new()
	var loop := preload("res://art/audio/game-sfx/permutation-flight.wav").duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	_flight_audio.stream = loop
	_flight_audio.volume_db = -10.0
	_flight_audio.unit_size = 3.0
	_flight_audio.max_distance = 24.0
	add_child(_flight_audio)
	_flight_audio.play()
	for ghost in _trail:
		ghost.global_position = global_position
		_trail_positions.append(global_position)


func _physics_process(delta: float) -> void:
	if _settled:
		return
	if not is_instance_valid(caster) or not is_instance_valid(target) or not actor_available(caster) or not actor_available(target) or epoch(caster) != _caster_epoch or epoch(target) != _target_epoch:
		_settled = true
		stop_audio()
		failed.emit()
		queue_free()
		return
	_elapsed += delta
	var destination := target.global_position + Vector3.UP * 0.95
	var old_position := global_position
	var travel := float(DATA.MODULE_DEFINITIONS.permutation.mark_speed) * delta
	global_position = global_position.move_toward(destination, travel)
	var direction := destination - old_position
	if direction.length_squared() > 0.001:
		rotation.y = atan2(direction.x, direction.z)
	var previous := old_position
	for index in range(_trail.size()):
		var ghost := _trail[index]
		var stored := _trail_positions[index]
		_trail_positions[index] = previous
		var segment := previous - stored
		ghost.visible = segment.length_squared() > 0.0001
		if ghost.visible:
			ghost.global_position = (previous + stored) * 0.5
			var up := Vector3.FORWARD if absf(segment.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
			ghost.global_basis = Basis.looking_at(segment.normalized(), up)
			ghost.scale = Vector3(0.85 - index * 0.07, 0.65 - index * 0.055, segment.length() / 0.4 + 0.35)
		previous = stored
	_arc_clock -= delta
	if _arc_clock <= 0.0:
		_arc_clock = 0.04
		_update_arcs()
	if global_position.distance_squared_to(destination) > 0.0001 or _elapsed < float(DATA.MODULE_DEFINITIONS.permutation.minimum_travel_time):
		return
	_settled = true
	stop_audio()
	if resolves_swap:
		var origin := caster.global_position
		var arrival := target.global_position
		if exchange(caster, target):
			pulse(caster.get_tree().current_scene, origin)
			pulse(caster.get_tree().current_scene, arrival)
			play_exchange_sound(caster.get_tree().current_scene, arrival)
			arrived.emit(origin, arrival)
		else:
			failed.emit()
	queue_free()


func stop_audio() -> void:
	if is_instance_valid(_flight_audio):
		_flight_audio.stop()


static func play_exchange_sound(scene: Node, destination: Vector3) -> void:
	var sfx := scene.get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.call("play_module_event", "permutation_swap", destination)


static func exchange(source: Node3D, victim: Node3D) -> bool:
	if source == victim or not actor_available(source) or not actor_available(victim):
		return false
	var origin := source.global_position
	var destination := victim.global_position
	# Only endpoints matter. Different chassis must both fit before either moves.
	if not _fits(source, destination, victim) or not _fits(victim, origin, source):
		return false
	source.global_position = destination
	victim.global_position = origin
	for actor in [source, victim]:
		if actor.has_method("on_permutation_relocated"):
			actor.call("on_permutation_relocated")
	refresh_sweeps(source.get_tree())
	return true


static func refresh_sweeps(tree: SceneTree) -> void:
	for observer in tree.get_nodes_in_group("permutation_relocation_observers"):
		observer.call("refresh_permutation_sweeps")


static func _fits(actor: Node3D, destination: Vector3, other: Node3D) -> bool:
	if not actor is CollisionObject3D:
		return true
	for child in actor.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.transform.origin += destination - actor.global_position
		query.collision_mask = 1 # World geometry; the two fighters are exchanged.
		query.margin = 0.0
		query.exclude = [actor.get_rid()]
		if other is CollisionObject3D:
			query.exclude.append(other.get_rid())
		if not actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


static func _material(tint: Color, alpha: float, glow: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(tint, alpha)
	mat.emission_enabled = glow > 0.0
	mat.emission = tint
	mat.emission_energy_multiplier = glow
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _build_shadow() -> void:
	var silhouette := CapsuleMesh.new()
	silhouette.radius = 0.28
	silhouette.height = 1.30
	var core := MeshInstance3D.new()
	core.mesh = silhouette
	core.material_override = _material(Color("#171124"), 0.92)
	core.scale = Vector3(1.25, 1.0, 0.7)
	add_child(core)
	var cloak := MeshInstance3D.new()
	var cloak_mesh := CylinderMesh.new()
	cloak_mesh.top_radius = 0.15
	cloak_mesh.bottom_radius = 0.38
	cloak_mesh.height = 0.85
	cloak.mesh = cloak_mesh
	cloak.position.y = -0.30
	cloak.material_override = core.material_override
	add_child(cloak)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var limb := CapsuleMesh.new()
		limb.radius = 0.10
		limb.height = 0.69
		arm.mesh = limb
		arm.position = Vector3(side * 0.33, 0.08, -0.02)
		arm.rotation.z = side * 0.30
		arm.material_override = core.material_override
		add_child(arm)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.23
	head_mesh.height = 0.46
	head.mesh = head_mesh
	head.position.y = 0.69
	head.material_override = _material(Color("#302443"), 0.95)
	add_child(head)
	for index in range(7):
		var ghost := MeshInstance3D.new()
		var smoke := SphereMesh.new()
		smoke.radius = 0.20
		smoke.height = 0.40
		ghost.mesh = smoke
		ghost.material_override = _material(Color("#21142f"), 0.72 * (1.0 - float(index) / 8.0))
		add_child(ghost)
		ghost.top_level = true
		_trail.append(ghost)
	_arcs = MeshInstance3D.new()
	_arcs.material_override = _material(TINT, 0.95, 2.5)
	add_child(_arcs)
	_update_arcs()


func _update_arcs() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for strand in range(4):
		var angle := float(strand) * TAU / 4.0 + _elapsed * 9.0
		var previous := Vector3(cos(angle) * 0.32, -0.68, sin(angle) * 0.32)
		for segment in range(1, 9):
			var next := Vector3(cos(angle + segment * 0.6) * randf_range(0.26, 0.48), -0.68 + float(segment) * 0.19, sin(angle + segment * 0.6) * randf_range(0.26, 0.48))
			var side := Vector3(0.025, 0.0, 0.025)
			for vertex in [previous - side, next - side, next + side, previous - side, next + side, previous + side]:
				mesh.surface_add_vertex(vertex)
			previous = next
	# A thin discharge follows the continuous shadow wake as well as its body.
	var wake := Vector3.ZERO
	for at in _trail_positions:
		var next := to_local(at) + Vector3.UP * randf_range(-0.10, 0.10)
		if wake.distance_squared_to(next) > 0.001:
			var side := Vector3.UP * 0.015
			for vertex in [wake - side, next - side, next + side, wake - side, next + side, wake + side]:
				mesh.surface_add_vertex(vertex)
		wake = next
	mesh.surface_end()
	_arcs.mesh = mesh


static func pulse(parent: Node, at: Vector3) -> void:
	if not is_instance_valid(parent):
		return
	var effect := Node3D.new()
	effect.name = "PermutationArrival"
	parent.add_child(effect)
	effect.add_to_group("prototype0_fx_budget")
	effect.global_position = at + Vector3.UP * 0.09
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.47
	ring.mesh = torus
	ring.material_override = _material(TINT, 0.9, 1.8)
	effect.add_child(ring)
	var burst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.44
	sphere.height = 0.88
	burst.mesh = sphere
	burst.position.y = 0.78
	burst.scale = Vector3(1.0, 2.0, 1.0)
	burst.material_override = _material(Color("#d4caff"), 0.36, 1.4)
	effect.add_child(burst)
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 3.6, 0.30)
	tween.tween_property(ring.material_override, "albedo_color:a", 0.0, 0.30)
	tween.tween_property(burst, "scale", Vector3(0.1, 2.6, 0.1), 0.22)
	tween.tween_property(burst.material_override, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_callback(effect.queue_free)
