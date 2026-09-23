extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera_rig.gd")
const TARGET_SCRIPT := preload("res://scripts/target_dummy.gd")

var player: CharacterBody3D


func _ready() -> void:
	_build_environment()
	_build_arena()
	_build_player()
	_build_camera()
	_build_target()
	_build_interface()


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#2b201d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#f2c08d")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffd0a1")
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_arena() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(52.0, 52.0)
	ground.mesh = ground_mesh
	ground.material_override = _material(Color("#a9653f"), 0.95)
	add_child(ground)

	_create_box("NorthWall", Vector3(0.0, 1.25, -26.0), Vector3(52.0, 2.5, 1.0), Color("#4b3932"))
	_create_box("SouthWall", Vector3(0.0, 1.25, 26.0), Vector3(52.0, 2.5, 1.0), Color("#4b3932"))
	_create_box("WestWall", Vector3(-26.0, 1.25, 0.0), Vector3(1.0, 2.5, 52.0), Color("#4b3932"))
	_create_box("EastWall", Vector3(26.0, 1.25, 0.0), Vector3(1.0, 2.5, 52.0), Color("#4b3932"))

	_create_box("WreckA", Vector3(-7.0, 1.4, -5.0), Vector3(5.5, 2.8, 2.5), Color("#76442f"))
	_create_box("WreckB", Vector3(7.5, 1.0, 5.5), Vector3(3.0, 2.0, 6.0), Color("#5b4540"))
	_create_box("BarrierA", Vector3(-12.0, 0.75, 8.0), Vector3(7.0, 1.5, 1.2), Color("#7c5c47"))
	_create_box("BarrierB", Vector3(12.0, 0.75, -8.0), Vector3(7.0, 1.5, 1.2), Color("#7c5c47"))
	_create_box("CratesA", Vector3(-16.0, 1.0, -13.0), Vector3(3.0, 2.0, 3.0), Color("#455346"))
	_create_box("CratesB", Vector3(16.0, 1.0, 13.0), Vector3(3.0, 2.0, 3.0), Color("#455346"))


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(-10.0, 0.0, 10.0)
	add_child(player)


func _build_camera() -> void:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CAMERA_RIG_SCRIPT)
	add_child(rig)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 15.5, 13.5)
	camera.fov = 42.0
	camera.current = true
	rig.add_child(camera)
	rig.call("set_target", player)


func _build_target() -> void:
	var target := StaticBody3D.new()
	target.name = "TargetDummy"
	target.set_script(TARGET_SCRIPT)
	target.position = Vector3(7.0, 0.0, -7.0)
	add_child(target)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.position = Vector2(24.0, 18.0)
	title.text = "PROTOTYPE 0 — ESSAI 2,5D"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#f6d5a6"))
	layer.add_child(title)

	var help := Label.new()
	help.position = Vector2(24.0, 54.0)
	help.text = "ZQSD / WASD / flèches : déplacement\nSouris : viser   •   Clic gauche ou Espace : tirer\nLes obstacles bloquent le robot et les projectiles."
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(help)

	var status := Label.new()
	status.name = "Status"
	status.position = Vector2(24.0, 650.0)
	status.text = "Objectif : détruire la cible rouge. Elle se réinitialise automatiquement."
	status.add_theme_font_size_override("font_size", 17)
	status.add_theme_color_override("font_color", Color("#7de8ff"))
	layer.add_child(status)


func _create_box(node_name: String, box_position: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box_position
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _material(color, 0.85)
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body


func _material(color: Color, roughness: float = 0.8, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 2.5
	return material

