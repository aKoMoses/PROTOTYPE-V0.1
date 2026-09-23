extends StaticBody3D

const MAX_HEALTH := 100.0

var _health := MAX_HEALTH
var _resetting := false
var _health_label: Label3D
var _body_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_build_collision()
	_build_visuals()
	_update_label()


func take_damage(amount: float) -> void:
	if _resetting:
		return
	_health = maxf(0.0, _health - amount)
	_update_label()
	if _health <= 0.0:
		_reset_target()


func _reset_target() -> void:
	_resetting = true
	_health_label.text = "CIBLE DÉTRUITE"
	_body_material.albedo_color = Color("#3b302e")
	await get_tree().create_timer(1.25).timeout
	_health = MAX_HEALTH
	_resetting = false
	_body_material.albedo_color = Color("#8f302b")
	_update_label()


func _update_label() -> void:
	if _health_label != null:
		_health_label.text = "CIBLE  %d / %d" % [int(_health), int(MAX_HEALTH)]


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.7
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)


func _build_visuals() -> void:
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.72
	body_mesh.height = 1.45
	body.mesh = body_mesh
	body.position.y = 0.9
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#8f302b")
	_body_material.metallic = 0.35
	_body_material.roughness = 0.62
	body.material_override = _body_material
	add_child(body)

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.2
	eye_mesh.height = 0.3
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 1.2, 0.66)
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color("#ff503f")
	eye_material.emission_enabled = true
	eye_material.emission = Color("#ff241d")
	eye_material.emission_energy_multiplier = 3.5
	eye.material_override = eye_material
	add_child(eye)

	_health_label = Label3D.new()
	_health_label.position = Vector3(0.0, 2.25, 0.0)
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.font_size = 38
	_health_label.outline_size = 8
	_health_label.modulate = Color("#ff8b78")
	add_child(_health_label)

