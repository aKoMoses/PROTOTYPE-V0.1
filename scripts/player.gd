extends CharacterBody3D

@export var move_speed := 7.5
@export var attack_interval := 0.34

# Electro Axe V0.1 — first playable combat lot. Damage values are deliberately
# centralized so balancing after the human test does not touch hitbox code.
const AXE_DAMAGE := [120.0, 145.0, 80.0]
const AXE_RANGE := [4.4, 3.2, 2.8]
const AXE_COMBO_WINDOW := 1.05
const AXE_SLOW_DURATION := 0.25
const AXE_SLOW_PERCENT := 30.0
const AXE_SHOCKWAVE_DURATION := 0.50
const AXE_STUN_DURATION := 0.50
const CRIT_MULTIPLIER := 1.5

var aim_direction := Vector3(0.0, 0.0, -1.0)
var _last_attack_time := -10.0
var _combo_step := 0
var _combo_expires_at := -1.0
var _attack_label: Label3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	_build_collision()
	_build_robot()


func _physics_process(_delta: float) -> void:
	_update_aim()
	_update_movement()
	_update_attack()


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


func _update_attack() -> void:
	var wants_to_attack := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	var now := Time.get_ticks_msec() / 1000.0
	if now > _combo_expires_at:
		_combo_step = 0
	if wants_to_attack and now - _last_attack_time >= attack_interval:
		_last_attack_time = now
		_perform_axe_attack()


func _perform_axe_attack() -> void:
	var step := _combo_step
	_combo_step = (_combo_step + 1) % 3
	_combo_expires_at = Time.get_ticks_msec() / 1000.0 + AXE_COMBO_WINDOW
	_attack_label.text = "ELECTRO AXE  •  COUP %d/3" % (step + 1)
	_show_attack_hitbox(step)
	var target := get_tree().current_scene.get_node_or_null("TargetDummy")
	if target == null:
		return
	var offset: Vector3 = target.global_position - global_position
	var flat_offset := Vector3(offset.x, 0.0, offset.z)
	var distance := flat_offset.length()
	if distance > AXE_RANGE[step] or distance < 0.01:
		return
	var facing_dot := aim_direction.dot(flat_offset.normalized())
	var cone_limit := 0.88 if step == 0 else (0.35 if step == 1 else -0.25)
	if facing_dot < cone_limit:
		return
	var damage: float = float(AXE_DAMAGE[step])
	if step == 2 and distance <= 0.9:
		damage *= CRIT_MULTIPLIER
		target.call("apply_stun", AXE_STUN_DURATION)
	else:
		target.call("apply_slow", AXE_SLOW_DURATION if step < 2 else AXE_SHOCKWAVE_DURATION, AXE_SLOW_PERCENT)
	target.call("take_damage", damage)


func _show_attack_hitbox(step: int) -> void:
	var hitbox := MeshInstance3D.new()
	hitbox.name = "AxeHitbox"
	var mesh := CylinderMesh.new()
	mesh.top_radius = AXE_RANGE[step] * (0.10 if step == 0 else 0.55)
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.06
	hitbox.mesh = mesh
	hitbox.position = global_position + aim_direction * (AXE_RANGE[step] * 0.5)
	hitbox.position.y = 0.04
	hitbox.rotation_degrees = Vector3.ZERO
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.25, 0.85, 1.0, 0.42)
	material.emission_enabled = true
	material.emission = Color("#2ad9ff")
	material.emission_energy_multiplier = 2.0
	hitbox.material_override = material
	get_tree().current_scene.add_child(hitbox)
	var tween := create_tween()
	tween.tween_property(hitbox, "scale", Vector3(1.0, 1.0, 1.8), 0.12)
	tween.tween_callback(hitbox.queue_free)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)


func _build_robot() -> void:
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	visuals.scale = Vector3.ONE * 0.88
	add_child(visuals)

	_attack_label = Label3D.new()
	_attack_label.position = Vector3(0.0, 2.55, 0.0)
	_attack_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_attack_label.font_size = 26
	_attack_label.outline_size = 6
	_attack_label.modulate = Color("#8beaff")
	add_child(_attack_label)

	var selection_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.78
	ring_mesh.outer_radius = 0.93
	selection_ring.mesh = ring_mesh
	selection_ring.position.y = 0.045
	selection_ring.material_override = _material(Color("#bdefff"), 0.3, Color("#56dfff"))
	visuals.add_child(selection_ring)

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.25
	body.mesh = body_mesh
	body.position.y = 0.8
	body.material_override = _material(Color("#e4d0ae"), 0.72)
	visuals.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.48
	head_mesh.height = 0.85
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.55, 0.0)
	head.material_override = _material(Color("#efe1c4"), 0.65)
	visuals.add_child(head)

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.18
	eye_mesh.height = 0.26
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 1.58, -0.42)
	eye.scale = Vector3(1.2, 0.75, 0.45)
	eye.material_override = _material(Color("#4ee8ff"), 0.25, Color("#21cfff"))
	visuals.add_child(eye)

	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.26, 0.24, 1.45)
	gun.mesh = gun_mesh
	gun.position = Vector3(0.5, 0.95, -0.82)
	gun.material_override = _material(Color("#5c5148"), 0.5)
	visuals.add_child(gun)

	var scarf := MeshInstance3D.new()
	var scarf_mesh := BoxMesh.new()
	scarf_mesh.size = Vector3(0.6, 0.08, 1.15)
	scarf.mesh = scarf_mesh
	scarf.position = Vector3(0.0, 1.2, 0.65)
	scarf.rotation_degrees.x = -18.0
	scarf.material_override = _material(Color("#a62f25"), 0.9)
	visuals.add_child(scarf)


func _material(color: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 3.0
	return material
