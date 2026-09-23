extends CharacterBody3D

const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")

@export var move_speed := 7.5
@export var fire_interval := 0.22

var aim_direction := Vector3(0.0, 0.0, -1.0)
var _last_shot_time := -10.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	_build_collision()
	_build_robot()


func _physics_process(_delta: float) -> void:
	_update_aim()
	_update_movement()
	_update_fire()


func _update_movement() -> void:
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1.0

	input_vector = input_vector.normalized()
	velocity = Vector3(input_vector.x, 0.0, input_vector.y) * move_speed
	move_and_slide()
	global_position.y = 0.0


func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	if absf(ray_direction.y) < 0.001:
		return
	var distance_to_ground := -ray_origin.y / ray_direction.y
	if distance_to_ground <= 0.0:
		return
	var aim_point := ray_origin + ray_direction * distance_to_ground
	var flat_direction := aim_point - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.04:
		aim_direction = flat_direction.normalized()
		look_at(global_position + aim_direction, Vector3.UP)


func _update_fire() -> void:
	var wants_to_fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	var now := Time.get_ticks_msec() / 1000.0
	if wants_to_fire and now - _last_shot_time >= fire_interval:
		_last_shot_time = now
		_fire_projectile()


func _fire_projectile() -> void:
	var projectile := CharacterBody3D.new()
	projectile.name = "Projectile"
	projectile.set_script(PROJECTILE_SCRIPT)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * 0.85 + aim_direction * 1.05
	projectile.call("setup", aim_direction, 19.0, 25.0)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)


func _build_robot() -> void:
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.25
	body.mesh = body_mesh
	body.position.y = 0.8
	body.material_override = _material(Color("#e4d0ae"), 0.72)
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.48
	head_mesh.height = 0.85
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.55, 0.0)
	head.material_override = _material(Color("#efe1c4"), 0.65)
	add_child(head)

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.18
	eye_mesh.height = 0.26
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 1.58, -0.42)
	eye.scale = Vector3(1.2, 0.75, 0.45)
	eye.material_override = _material(Color("#4ee8ff"), 0.25, Color("#21cfff"))
	add_child(eye)

	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.26, 0.24, 1.45)
	gun.mesh = gun_mesh
	gun.position = Vector3(0.5, 0.95, -0.82)
	gun.material_override = _material(Color("#5c5148"), 0.5)
	add_child(gun)

	var scarf := MeshInstance3D.new()
	var scarf_mesh := BoxMesh.new()
	scarf_mesh.size = Vector3(0.6, 0.08, 1.15)
	scarf.mesh = scarf_mesh
	scarf.position = Vector3(0.0, 1.2, 0.65)
	scarf.rotation_degrees.x = -18.0
	scarf.material_override = _material(Color("#a62f25"), 0.9)
	add_child(scarf)


func _material(color: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 3.0
	return material

