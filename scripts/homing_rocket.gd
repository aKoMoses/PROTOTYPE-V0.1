extends StaticBody3D

signal impacted(target: Node3D, rocket: Node3D)
const DATA := preload("res://scripts/combat_data.gd")
const GROUP := "prototype0_homing_rockets"
var caster: Node3D
var rocket_id := ""
var replica := false
var health := 40.0
var direction := Vector3.FORWARD
var _epoch := -1
var _finished := false
var _age := 0.0
var _damage_ids: Dictionary = {}
var _body: Node3D
var _bar: MeshInstance3D
var _trail: MeshInstance3D
var _points: Array[Vector3] = []
var _cast: ShapeCast3D
var _propulsion: AudioStreamPlayer3D


func configure(actor: Node3D, identifier: String, heading: Vector3, visual_only: bool = false) -> void:
	caster = actor
	rocket_id = identifier
	direction = heading.normalized()
	replica = visual_only
	_epoch = int(actor.call("get_visibility_epoch")) if actor.has_method("get_visibility_epoch") else -1
	health = float(DATA.MODULE_DEFINITIONS.rocket_basket.health)


func _ready() -> void:
	name = "HomingRocket"
	process_physics_priority = 21
	add_to_group(GROUP)
	add_to_group("prototype0_gameplay_projectiles")
	collision_layer = 0 if replica else 2 | 4
	collision_mask = 0
	set_meta("fulguro_non_solid", true)
	set_meta("ai_projectile_source", caster.get_instance_id())
	set_meta("ai_projectile_radius", float(DATA.MODULE_DEFINITIONS.rocket_basket.collision_radius))
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = float(DATA.MODULE_DEFINITIONS.rocket_basket.collision_radius)
	collision.shape = sphere
	add_child(collision)
	_cast = ShapeCast3D.new()
	_cast.shape = sphere
	_cast.enabled = false
	_cast.collision_mask = 1 | 2 | 4 | 8 | 16
	_cast.collide_with_areas = true
	add_child(_cast)
	_build_visual()
	_propulsion = AudioStreamPlayer3D.new()
	var loop := preload("res://art/audio/game-sfx/rocket-flight.wav").duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	_propulsion.stream = loop
	_propulsion.volume_db = -17.0 # Five quiet engines stay below their impacts.
	_propulsion.unit_size = 3.0
	_propulsion.max_distance = 22.0
	add_child(_propulsion)
	_propulsion.play()


static func owned_exclusions(context: Node, excluded: Array[RID]) -> Array[RID]:
	var result := excluded.duplicate()
	if not context.is_inside_tree() or excluded.is_empty():
		return result
	for rocket in context.get_tree().get_nodes_in_group(GROUP):
		if is_instance_valid(rocket.caster) and rocket.caster is CollisionObject3D and rocket.caster.get_rid() == excluded[0]:
			result.append(rocket.get_rid())
	return result


func _physics_process(delta: float) -> void:
	if _finished:
		return
	if not is_instance_valid(caster) or not caster.is_inside_tree() or (_epoch >= 0 and int(caster.call("get_visibility_epoch")) != _epoch):
		_destroy()
		return
	_age += delta
	if replica:
		_update_visual()
		return
	var definition: Dictionary = DATA.MODULE_DEFINITIONS.rocket_basket
	# Keep the launch cone visible before progressively engaging guidance/search.
	var guidance := smoothstep(float(definition.homing_delay), float(definition.homing_delay) + float(definition.homing_ramp), _age)
	var target := _nearest_target() if guidance > 0.0 else null
	var desired := direction
	if target != null:
		desired = (target.global_position + Vector3.UP * 0.9 - global_position).normalized()
	else:
		# Stay airborne and keep scanning even when the last enemy disappears.
		desired = direction.rotated(Vector3.UP, delta * 2.0 * guidance)
	var turn := float(definition.turn_rate) * guidance * delta
	var angle := direction.angle_to(desired)
	if angle > 0.0001:
		direction = direction.slerp(desired, minf(1.0, turn / angle)).normalized()
	var motion := direction * float(DATA.MODULE_DEFINITIONS.rocket_basket.speed) * delta
	_cast.clear_exceptions()
	_cast.add_exception_rid(get_rid())
	if caster is CollisionObject3D:
		_cast.add_exception_rid(caster.get_rid())
	# Rockets in one team never collide with each other. Walls always collide.
	for rocket in get_tree().get_nodes_in_group(GROUP):
		if rocket.caster == caster:
			_cast.add_exception_rid(rocket.get_rid())
	_cast.target_position = motion
	_cast.force_shapecast_update()
	if _cast.is_colliding():
		var collider := _cast.get_collider(0) as Node3D
		global_position += motion * _cast.get_closest_collision_safe_fraction()
		_finished = true
		collision_layer = 0
		_play_terminal_sound("rocket_impact")
		if is_instance_valid(collider) and collider != caster and collider.has_method("take_damage"):
			impacted.emit(collider, self)
		if is_instance_valid(collider) and collider.has_method("projectile_impact"):
			collider.call("projectile_impact", global_position)
		queue_free()
		return
	global_position += motion
	set_meta("ai_projectile_velocity", direction * float(DATA.MODULE_DEFINITIONS.rocket_basket.speed))
	set_meta("ai_projectile_endpoint", global_position + direction * 3.0)
	_update_visual()


func _nearest_target() -> Node3D:
	var candidates: Array = []
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_training_targets"):
		candidates.append_array(scene.call("get_training_targets"))
	elif scene != null:
		var dummy := scene.get_node_or_null("TargetDummy")
		if dummy != null:
			candidates.append(dummy)
	candidates.append_array(get_tree().get_nodes_in_group("prototype0_combat_bots"))
	if caster.has_method("_module_target"):
		candidates.append(caster.call("_module_target"))
	if caster.has_meta("rocket_enemy"):
		var enemy: Object = instance_from_id(int(caster.get_meta("rocket_enemy")))
		if is_instance_valid(enemy):
			candidates.append(enemy)
	var nearest: Node3D
	var distance := INF
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate is Node3D or candidate == caster or not candidate.has_method("get_health"):
			continue
		if candidate.is_in_group(GROUP) or float(candidate.call("get_health")) <= 0.0:
			continue
		if candidate.has_method("is_real_dead") and bool(candidate.call("is_real_dead")):
			continue
		# Bot-fired rockets only acquire their opposing player.
		if caster.has_meta("rocket_enemy") and candidate.get_instance_id() != int(caster.get_meta("rocket_enemy")):
			continue
		var next_distance: float = global_position.distance_squared_to(candidate.global_position + Vector3.UP * 0.9)
		if next_distance < distance:
			distance = next_distance
			nearest = candidate
	return nearest


func get_health() -> float:
	return health


func is_real_dead() -> bool:
	return _finished or health <= 0.0


func take_damage(amount: float, _source: String = "", _attack: String = "") -> float:
	if replica or _finished:
		return 0.0
	if _attack != "":
		if _damage_ids.has(_attack):
			return 0.0
		_damage_ids[_attack] = true
	var applied := minf(health, maxf(0.0, amount))
	health -= applied
	if health <= 0.0:
		_play_terminal_sound("rocket_destroyed")
		_destroy()
	else:
		_update_visual()
	return applied


func _destroy() -> void:
	_finished = true
	collision_layer = 0
	if _propulsion != null:
		_propulsion.stop()
	queue_free()


func _play_terminal_sound(event_id: String) -> void:
	_propulsion.stop()
	get_node("/root/GameSfx").play_module_event(event_id, global_position)
	if not replica and is_instance_valid(caster) and caster.has_method("_notify"):
		caster.call("_notify", "rocket_end", {"sound": event_id, "center": global_position})


func flash_impact(_critical: bool = false) -> void:
	pass


func apply_slow(_duration: float, _percent: float, _source: String = "") -> void:
	pass


func apply_burn(_duration: float, _damage: float, _source: String = "") -> void:
	pass


func start_fulguro_projection(_direction: Vector3, _distance: float, _duration: float, _damage: float, _stun: float, _source: String, _attack: String) -> void:
	pass


func get_fulguro_hit_radius() -> float:
	return float(DATA.MODULE_DEFINITIONS.rocket_basket.collision_radius)


func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.7
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material


func _mesh(parent: Node3D, mesh: Mesh, material: Material, position_value: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = position_value
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual


func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	var chassis := _material(Color("#536477"))
	var electric := _material(Color("#60ebff"), true)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.10
	cylinder.bottom_radius = 0.10
	cylinder.height = 0.40
	var body := _mesh(_body, cylinder, chassis, Vector3.ZERO)
	body.rotation.x = PI * 0.5
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.10
	cone.height = 0.20
	var nose := _mesh(_body, cone, electric, Vector3(0, 0, -0.29))
	nose.rotation.x = -PI * 0.5
	for index in range(4):
		var fin := BoxMesh.new()
		fin.size = Vector3(0.24, 0.026, 0.15)
		var visual := _mesh(_body, fin, chassis, Vector3(0, 0, 0.15))
		visual.rotation.z = float(index) * PI * 0.5
	var bar := QuadMesh.new()
	bar.size = Vector2(0.42, 0.045)
	var background := _mesh(self, bar, _material(Color("#15232f")), Vector3(0, 0.30, 0))
	(background.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	(background.material_override as StandardMaterial3D).billboard_keep_scale = true
	_bar = _mesh(self, bar, _material(Color("#8dffb4"), true), Vector3(0, 0.30, 0.002))
	(_bar.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	(_bar.material_override as StandardMaterial3D).billboard_keep_scale = true
	_trail = _mesh(self, ImmediateMesh.new(), electric, Vector3.ZERO)
	_trail.top_level = true
	_trail.global_transform = Transform3D.IDENTITY


func _update_visual() -> void:
	_body.look_at(global_position + direction, Vector3.UP)
	_bar.scale.x = maxf(0.01, health / float(DATA.MODULE_DEFINITIONS.rocket_basket.health))
	_points.push_front(global_position - direction * 0.24)
	if _points.size() > 9:
		_points.pop_back()
	var mesh := _trail.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(_points.size() - 1):
		var jitter := Vector3(0, sin(_age * 42.0 + index * 2.0) * 0.035, 0)
		mesh.surface_add_vertex(_points[index] + jitter)
		mesh.surface_add_vertex(_points[index + 1])
	mesh.surface_end()
