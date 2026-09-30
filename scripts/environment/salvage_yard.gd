extends Node3D
## Visual-only authored salvage yard. No collision, navigation or combat state.
## Static geometry is baked in five spatial meshes, with shared materials.

@export_range(0.0, 3.0, 0.05) var fan_speed := 1.15

var _fans: Array[Node3D] = []
var _cloth: Array[ShaderMaterial] = []
var _particles: Array[GPUParticles3D] = []
var _quality := 1


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		if node.material_override is ShaderMaterial:
			# Parameters belong to this yard instance, while opaque static
			# materials stay shared across all baked meshes.
			node.material_override = node.material_override.duplicate()
			_cloth.append(node.material_override as ShaderMaterial)
	for node in find_children("*", "Node3D", true, false):
		if node.has_meta("yard_fan"):
			_fans.append(node as Node3D)
	for node in find_children("*", "GPUParticles3D", true, false):
		node.process_material = node.process_material.duplicate()
		_particles.append(node as GPUParticles3D)
	set_quality(1, Vector2(0.94, -0.34), 0.65)


func set_quality(level: int, wind: Vector2, strength: float) -> void:
	_quality = clampi(level, 0, 1)
	var direction := wind.normalized() if wind.length_squared() > 0.001 else Vector2(1.0, 0.0)
	for cloth in _cloth:
		cloth.set_shader_parameter("wind_direction", direction)
		cloth.set_shader_parameter("wind_strength", clampf(strength, 0.0, 1.0))
		cloth.set_shader_parameter("motion_scale", 0.38 if _quality == 0 else 1.0)
	for particles in _particles:
		var process_material := particles.process_material as ParticleProcessMaterial
		if particles.name == "PeripheralDust":
			process_material.direction = Vector3(direction.x, 0.10, direction.y)
		else:
			process_material.direction = Vector3(direction.x * 0.16, 1.0, direction.y * 0.16)
			process_material.gravity = Vector3(direction.x * 0.02, 0.04, direction.y * 0.02)
		particles.emitting = _quality > 0
		particles.visible = _quality > 0
	set_process(_quality > 0 and not _fans.is_empty())


func _process(delta: float) -> void:
	# One controller for two peripheral rotor meshes; cloth uses shader TIME.
	for index in _fans.size():
		_fans[index].rotate_z(delta * fan_speed * (1.0 + index * 0.11))
