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
var _axe_pivot: Node3D
var _axe_pivot_home := Vector3(0.5, 1.0, -0.55)
var _axe_pivot_home_rotation := Vector3.ZERO


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
	_play_axe_animation(step)
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
		target.call("flash_impact", true)
	else:
		target.call("apply_slow", AXE_SLOW_DURATION if step < 2 else AXE_SHOCKWAVE_DURATION, AXE_SLOW_PERCENT)
		target.call("flash_impact", false)
	target.call("take_damage", damage)


func _play_axe_animation(step: int) -> void:
	if _axe_pivot == null:
		return
	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(_axe_pivot, "position", _axe_pivot_home, 0.01)
	tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.01)
	if step == 0:
		# A readable thrust: the weapon lunges toward the target and snaps back.
		tween.tween_property(_axe_pivot, "position", Vector3(0.5, 1.0, -1.65), 0.09)
		tween.tween_property(_axe_pivot, "position", _axe_pivot_home, 0.16)
	elif step == 1:
		# A lateral sweep, with a brief anticipation in the opposite direction.
		tween.tween_property(_axe_pivot, "rotation", Vector3(0.0, deg_to_rad(-65.0), deg_to_rad(-12.0)), 0.07)
		tween.tween_property(_axe_pivot, "rotation", Vector3(0.0, deg_to_rad(78.0), deg_to_rad(14.0)), 0.12)
		tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.16)
	else:
		# Overhead slam: weapon rises, pauses, then drives down into the floor.
		tween.tween_property(_axe_pivot, "rotation", Vector3(deg_to_rad(-72.0), 0.0, 0.0), 0.12)
		tween.tween_interval(0.05)
		tween.tween_property(_axe_pivot, "rotation", Vector3(deg_to_rad(78.0), 0.0, 0.0), 0.10)
		tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.22)


func _create_fx_material(color: Color, alpha: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 5.0
	return material


func _play_impact_fx(step: int) -> void:
	if step == 0:
		var thrust := MeshInstance3D.new()
		var thrust_mesh := BoxMesh.new()
		thrust_mesh.size = Vector3(0.18, 0.18, AXE_RANGE[0])
		thrust.mesh = thrust_mesh
		thrust.material_override = _create_fx_material(Color("#8cefff"), 0.85)
		get_tree().current_scene.add_child(thrust)
		thrust.global_position = global_position + Vector3.UP * 0.95 + aim_direction * (AXE_RANGE[0] * 0.5)
		thrust.look_at(thrust.global_position + aim_direction, Vector3.UP)
		var tween := create_tween()
		tween.tween_property(thrust, "scale", Vector3(1.8, 1.8, 0.2), 0.12)
		tween.tween_callback(thrust.queue_free)
	elif step == 1:
		var slash := _create_slash_fan(AXE_RANGE[1], deg_to_rad(58.0))
		get_tree().current_scene.add_child(slash)
		slash.global_position = global_position + Vector3.UP * 0.9
		slash.look_at(slash.global_position + aim_direction, Vector3.UP)
		var tween := create_tween()
		tween.tween_property(slash, "scale", Vector3(1.25, 1.0, 1.25), 0.16)
		tween.tween_callback(slash.queue_free)
	else:
		_create_shockwave_fx()


func _create_slash_fan(radius: float, half_angle: float) -> MeshInstance3D:
	var slash := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(Color("#56dcff"), 0.72)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var segments := 10
	for index in range(segments):
		var a0 := -half_angle + (2.0 * half_angle) * float(index) / float(segments)
		var a1 := -half_angle + (2.0 * half_angle) * float(index + 1) / float(segments)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(sin(a0) * radius, 0.0, -cos(a0) * radius))
		mesh.surface_add_vertex(Vector3(sin(a1) * radius, 0.0, -cos(a1) * radius))
	mesh.surface_end()
	slash.mesh = mesh
	return slash


func _create_shockwave_fx() -> void:
	var impact_point := global_position + aim_direction * 1.15
	var crater := MeshInstance3D.new()
	var crater_mesh := CylinderMesh.new()
	crater_mesh.top_radius = 0.72
	crater_mesh.bottom_radius = 0.9
	crater_mesh.height = 0.10
	crater.mesh = crater_mesh
	crater.material_override = _create_fx_material(Color("#263e50"), 0.94)
	get_tree().current_scene.add_child(crater)
	crater.global_position = impact_point + Vector3.UP * 0.05
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.35
	ring_mesh.outer_radius = 0.52
	ring.mesh = ring_mesh
	ring.material_override = _create_fx_material(Color("#42e7ff"), 0.95)
	get_tree().current_scene.add_child(ring)
	ring.global_position = impact_point + Vector3.UP * 0.12
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(crater, "scale", Vector3(1.9, 1.0, 1.9), 0.65)
	tween.tween_property(ring, "scale", Vector3(3.2, 1.0, 3.2), 0.48)
	tween.set_parallel(false)
	tween.tween_interval(0.45)
	tween.tween_callback(crater.queue_free)
	tween.tween_callback(ring.queue_free)
	for index in range(8):
		_create_lightning_spark(impact_point, index)


func _create_lightning_spark(origin: Vector3, index: int) -> void:
	var spark := MeshInstance3D.new()
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.055, 0.08, 1.2 + float(index % 3) * 0.35)
	spark.mesh = spark_mesh
	spark.material_override = _create_fx_material(Color("#b7f8ff"), 0.95)
	get_tree().current_scene.add_child(spark)
	var angle := (TAU / 8.0) * float(index)
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	spark.global_position = origin + direction * 0.45 + Vector3.UP * (0.10 + float(index % 2) * 0.08)
	spark.look_at(spark.global_position + direction, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(spark, "scale", Vector3(1.0, 1.0, 0.1), 0.38)
	tween.tween_callback(spark.queue_free)


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
	_play_impact_fx(step)


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

	_axe_pivot = Node3D.new()
	_axe_pivot.name = "ElectroAxePivot"
	_axe_pivot.position = _axe_pivot_home
	visuals.add_child(_axe_pivot)
	var axe_handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.09
	handle_mesh.bottom_radius = 0.12
	handle_mesh.height = 1.5
	axe_handle.mesh = handle_mesh
	axe_handle.rotation_degrees.x = -90.0
	axe_handle.position = Vector3(0.0, 0.0, -0.55)
	axe_handle.material_override = _material(Color("#4b342b"), 0.72)
	_axe_pivot.add_child(axe_handle)
	var axe_blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.78, 0.18, 0.52)
	axe_blade.mesh = blade_mesh
	axe_blade.position = Vector3(0.0, 0.0, -1.25)
	axe_blade.material_override = _material(Color("#bfefff"), 0.22, Color("#28dfff"))
	_axe_pivot.add_child(axe_blade)
	var axe_edge := MeshInstance3D.new()
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.9, 0.06, 0.08)
	axe_edge.mesh = edge_mesh
	axe_edge.position = Vector3(0.0, -0.11, -1.25)
	axe_edge.material_override = _material(Color("#eaffff"), 0.1, Color("#9cf6ff"))
	_axe_pivot.add_child(axe_edge)

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
