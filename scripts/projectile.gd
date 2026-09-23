extends CharacterBody3D

var _direction := Vector3.FORWARD
var _speed := 18.0
var _damage := 25.0
var _life_time := 0.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 3

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.16
	collision.shape = shape
	add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffb13b")
	material.emission_enabled = true
	material.emission = Color("#ff7b20")
	material.emission_energy_multiplier = 5.0
	mesh_instance.material_override = material
	add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.light_color = Color("#ff8d32")
	light.light_energy = 1.5
	light.omni_range = 2.0
	add_child(light)


func setup(direction: Vector3, speed: float, damage: float) -> void:
	_direction = direction.normalized()
	_speed = speed
	_damage = damage


func _physics_process(delta: float) -> void:
	_life_time += delta
	if _life_time > 3.0:
		queue_free()
		return

	var collision := move_and_collide(_direction * _speed * delta)
	if collision != null:
		var collider := collision.get_collider()
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", _damage)
		queue_free()

