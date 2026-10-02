extends Area3D

## Projectile surface stays on layer 8; the solid body uses a separate layer
## so sight and weapon queries still see the energy surface, not its chassis.
const FIELD_SHADER := preload("res://shaders/magnetic_wall.gdshader")
const SOLID_LAYER := 16
const GROUP := "prototype0_magnetic_walls"

var owner_rid := RID()
var width := 4.0
var height := 2.4
var duration := 2.5
var _age := 0.0
var _impact_age := 10.0
var _field: ShaderMaterial
var _assembly: Node3D
var _solid: StaticBody3D
var _edge: StandardMaterial3D


func configure(actor: CollisionObject3D, next_width: float, next_height: float, lifetime: float) -> void:
	owner_rid = actor.get_rid()
	width = next_width
	height = next_height
	duration = lifetime


static func owned_exclusions(context: Node, excluded: Array) -> Array[RID]:
	var result: Array[RID] = []
	result.assign(excluded)
	if not context.is_inside_tree() or excluded.is_empty():
		return result
	for wall in context.get_tree().get_nodes_in_group(GROUP):
		# The first exclusion is the shooter; later ones can include its target.
		if is_instance_valid(wall) and excluded[0] == wall.owner_rid:
			result.append(wall.get_rid())
			if is_instance_valid(wall._solid):
				result.append(wall._solid.get_rid())
	return result


static func find_placement(actor: CollisionObject3D, direction: Vector3, distance: float, field_width: float, field_height: float, arena_center: Vector3 = Vector3.ZERO) -> Vector3:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return Vector3.INF
	direction = direction.normalized()
	var side := direction.cross(Vector3.UP)
	var excluded := owned_exclusions(actor, [actor.get_rid()])
	for forward in [distance, distance * 0.8, distance * 0.6]:
		for lateral in [0.0, 0.35, -0.35]:
			var center := actor.global_position + direction * float(forward) + side * float(lateral)
			if absf(center.x - arena_center.x) > 23.0 or absf(center.z - arena_center.z) > 23.0:
				continue
			var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 0.72, center + Vector3.UP * 0.72)
			ray.collision_mask = 1 | 8
			ray.collide_with_areas = true
			ray.exclude = excluded
			if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			var shape := BoxShape3D.new()
			shape.size = Vector3(field_width, maxf(0.1, field_height - 0.12), 0.18)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(Basis(Vector3.UP, atan2(direction.x, direction.z)), center + Vector3.UP * (field_height * 0.5 + 0.04))
			query.collision_mask = 1 | 8
			query.collide_with_areas = true
			query.exclude = excluded
			if actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				return center
	return Vector3.INF


func _ready() -> void:
	name = "MagneticField"
	add_to_group(GROUP)
	set_meta("vfx_surface", "shield")
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.14)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position.y = height * 0.5
	add_child(collision)
	_solid = StaticBody3D.new()
	_solid.name = "OpponentBlocker"
	_solid.collision_layer = SOLID_LAYER
	_solid.collision_mask = 0
	var solid_shape := CollisionShape3D.new()
	solid_shape.shape = shape
	solid_shape.position = collision.position
	_solid.add_child(solid_shape)
	add_child(_solid)
	_register_actors(get_tree().current_scene)
	get_tree().node_added.connect(_actor_added)
	_build_visual()


func _register_actors(node: Node) -> void:
	_register_actor(node)
	for child in node.get_children():
		_register_actors(child)


func _actor_added(node: Node) -> void:
	# Actor scripts set their masks in _ready; apply the additional bit afterwards.
	_register_actor.call_deferred(node)


func _register_actor(node: Node) -> void:
	if not is_instance_valid(node) or not node is PhysicsBody3D or node == _solid:
		return
	var actor := node as PhysicsBody3D
	if actor.collision_layer & (2 | 4) == 0 or actor.is_in_group("prototype0_homing_rockets"):
		return
	actor.collision_mask |= SOLID_LAYER
	if actor.get_rid() == owner_rid:
		_solid.add_collision_exception_with(actor)
		actor.add_collision_exception_with(_solid)


func _build_visual() -> void:
	_assembly = Node3D.new()
	_assembly.name = "WallVisual"
	add_child(_assembly)
	var chassis := StandardMaterial3D.new()
	chassis.albedo_color = Color("#24383e")
	chassis.metallic = 0.75
	chassis.roughness = 0.32
	_edge = StandardMaterial3D.new()
	_edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge.albedo_color = Color("#68e4ed")
	_edge.emission_enabled = true
	_edge.emission = Color("#37dce8")
	_edge.emission_energy_multiplier = 1.1
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 - 0.06)
		_box(Vector3(x, 0.12, 0), Vector3(0.42, 0.24, 0.52), chassis)
		_box(Vector3(x, height * 0.5, 0), Vector3(0.18, height, 0.22), chassis)
		_box(Vector3(x, height * 0.5, -0.13), Vector3(0.045, height * 0.88, 0.035), _edge)
		_box(Vector3(x, height * 0.5, 0.13), Vector3(0.045, height * 0.88, 0.035), _edge)
		for y in [0.22, height - 0.16]:
			_box(Vector3(x, y, 0), Vector3(0.28, 0.12, 0.30), _edge)
	for y in [0.09, height - 0.05]:
		_box(Vector3(0, y, 0), Vector3(width, 0.07, 0.10), _edge)
	_field = ShaderMaterial.new()
	_field.shader = FIELD_SHADER
	_field.set_shader_parameter("field_size", Vector2(width, height))
	var plane := MeshInstance3D.new()
	plane.name = "EnergyMembrane"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, height)
	plane.mesh = mesh
	plane.position.y = height * 0.5
	plane.material_override = _field
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_assembly.add_child(plane)
	_assembly.scale.y = 0.02


func _box(position_value: Vector3, size_value: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_value
	mesh.mesh = box
	mesh.position = position_value
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_assembly.add_child(mesh)


func projectile_impact(point: Vector3) -> void:
	if _field == null:
		return
	var local := to_local(point)
	_field.set_shader_parameter("impact_uv", Vector2(local.x / width + 0.5, 1.0 - local.y / height))
	_impact_age = 0.0


func _process(delta: float) -> void:
	_age += delta
	_impact_age += delta
	var deployment := smoothstep(0.0, 0.18, _age)
	var remaining := clampf((duration - _age) / 0.22, 0.0, 1.0)
	_assembly.scale.y = maxf(0.02, deployment * remaining)
	_field.set_shader_parameter("strength", deployment * remaining)
	_field.set_shader_parameter("impact_age", _impact_age)
	_edge.emission_energy_multiplier = (1.1 + sin(_age * 7.0) * 0.15 + maxf(0.0, 1.0 - _impact_age * 5.0) * 1.5) * remaining
