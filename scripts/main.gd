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
	ground_mesh.size = Vector2(54.0, 54.0)
	ground.mesh = ground_mesh
	ground.material_override = _material(Color("#a9663f"), 0.98)
	add_child(ground)

	_build_scrap_perimeter()

	# Four future health-kit locations. They are landmarks only until their rules
	# are defined in the design document.
	_create_health_pad("HealthPadNorth", Vector3(0.0, 0.0, -20.8))
	_create_health_pad("HealthPadSouth", Vector3(0.0, 0.0, 20.8))
	_create_health_pad("HealthPadWest", Vector3(-21.0, 0.0, 0.0))
	_create_health_pad("HealthPadEast", Vector3(21.0, 0.0, 0.0))

	# Main readable lanes: two central columns, transverse covers and mirrored
	# side pockets inspired by the reference without copying it literally.
	_create_scrap_barrier("NorthCenterCover", Vector3(0.0, 1.15, -9.0), Vector3(11.5, 2.3, 2.0))
	_create_scrap_barrier("WestSpine", Vector3(-7.0, 1.35, 1.2), Vector3(2.8, 2.7, 10.5))
	_create_scrap_barrier("EastSpine", Vector3(7.0, 1.35, 1.2), Vector3(2.8, 2.7, 10.5))
	_create_scrap_barrier("SouthCenterCover", Vector3(0.0, 1.15, 11.0), Vector3(10.0, 2.3, 2.0))

	_create_scrap_barrier("NorthWestAngle", Vector3(-11.3, 1.0, -9.4), Vector3(6.2, 2.0, 1.4), -24.0)
	_create_scrap_barrier("SouthEastAngle", Vector3(11.3, 1.0, 10.8), Vector3(6.2, 2.0, 1.4), -24.0)
	_create_scrap_barrier("NorthEastAngle", Vector3(12.0, 0.95, -6.7), Vector3(5.0, 1.9, 1.3), 25.0)
	_create_scrap_barrier("SouthWestAngle", Vector3(-12.0, 0.95, 8.1), Vector3(5.0, 1.9, 1.3), 25.0)

	_create_scrap_barrier("WestPocketLong", Vector3(-18.5, 1.15, 8.0), Vector3(2.2, 2.3, 6.0))
	_create_scrap_barrier("WestPocketShort", Vector3(-16.0, 1.15, 10.0), Vector3(5.0, 2.3, 2.0))
	_create_scrap_barrier("EastPocketLong", Vector3(18.5, 1.15, -8.0), Vector3(2.2, 2.3, 6.0))
	_create_scrap_barrier("EastPocketShort", Vector3(16.0, 1.15, -10.0), Vector3(5.0, 2.3, 2.0))

	_create_scrap_barrier("NorthWestBlock", Vector3(-17.5, 1.15, -15.0), Vector3(4.0, 2.3, 3.5))
	_create_scrap_barrier("SouthEastBlock", Vector3(17.5, 1.15, 15.0), Vector3(4.0, 2.3, 3.5))
	_create_scrap_barrier("NorthEastBlock", Vector3(17.8, 1.15, -16.0), Vector3(3.2, 2.3, 3.2))
	_create_scrap_barrier("SouthWestBlock", Vector3(-17.8, 1.15, 16.0), Vector3(3.2, 2.3, 3.2))

	# Bush placeholders are deliberately non-colliding for now.
	_create_bush_cluster("BushNorthCenter", Vector3(0.0, 0.0, -7.5), 1.2)
	_create_bush_cluster("BushSouthCenter", Vector3(0.0, 0.0, 9.5), 1.2)
	_create_bush_cluster("BushWestSpine", Vector3(-8.8, 0.0, 1.0), 0.9)
	_create_bush_cluster("BushEastSpine", Vector3(8.8, 0.0, 1.0), 0.9)
	_create_bush_cluster("BushNorthWest", Vector3(-19.5, 0.0, -12.6), 0.8)
	_create_bush_cluster("BushSouthEast", Vector3(19.5, 0.0, 12.6), 0.8)

	_create_tire_stack("TiresNorthWest", Vector3(-22.2, 0.0, -17.0), 3)
	_create_tire_stack("TiresSouthEast", Vector3(22.2, 0.0, 17.0), 3)
	_create_tire_stack("TiresWest", Vector3(-23.0, 0.0, 7.0), 2)
	_create_tire_stack("TiresEast", Vector3(23.0, 0.0, -7.0), 2)


func _build_scrap_perimeter() -> void:
	# Invisible continuous limits guarantee containment while the visible wall is
	# split into battered panels, leaving a more organic scrapyard silhouette.
	_create_invisible_limit("NorthLimit", Vector3(0.0, 1.5, -26.0), Vector3(52.0, 3.0, 0.8))
	_create_invisible_limit("SouthLimit", Vector3(0.0, 1.5, 26.0), Vector3(52.0, 3.0, 0.8))
	_create_invisible_limit("WestLimit", Vector3(-26.0, 1.5, 0.0), Vector3(0.8, 3.0, 52.0))
	_create_invisible_limit("EastLimit", Vector3(26.0, 1.5, 0.0), Vector3(0.8, 3.0, 52.0))
	for index in range(7):
		var offset := -22.0 + float(index) * 7.3
		_create_scrap_barrier("NorthPanel%d" % index, Vector3(offset, 1.25, -25.1), Vector3(6.6, 2.5 + float(index % 2) * 0.5, 1.0))
		_create_scrap_barrier("SouthPanel%d" % index, Vector3(-offset, 1.25, 25.1), Vector3(6.6, 2.5 + float((index + 1) % 2) * 0.5, 1.0))
		_create_scrap_barrier("WestPanel%d" % index, Vector3(-25.1, 1.25, -offset), Vector3(1.0, 2.5 + float(index % 2) * 0.5, 6.6))
		_create_scrap_barrier("EastPanel%d" % index, Vector3(25.1, 1.25, offset), Vector3(1.0, 2.5 + float((index + 1) % 2) * 0.5, 6.6))
	for banner_data in [
		[Vector3(-15.0, 2.0, -24.45), 0.0], [Vector3(15.0, 2.0, -24.45), 0.0],
		[Vector3(-15.0, 2.0, 24.45), 0.0], [Vector3(15.0, 2.0, 24.45), 0.0],
		[Vector3(-24.45, 2.0, -15.0), 90.0], [Vector3(-24.45, 2.0, 15.0), 90.0],
		[Vector3(24.45, 2.0, -15.0), 90.0], [Vector3(24.45, 2.0, 15.0), 90.0],
	]:
		_create_banner(banner_data[0], banner_data[1])


func _create_scrap_barrier(node_name: String, barrier_position: Vector3, size: Vector3, rotation_y: float = 0.0) -> StaticBody3D:
	var body := _create_box(node_name, barrier_position, size, Color("#8a5b42"))
	body.rotation_degrees.y = rotation_y
	var pale_panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(maxf(0.18, size.x - 0.25), maxf(0.25, size.y * 0.62), maxf(0.18, size.z - 0.25))
	pale_panel.mesh = panel_mesh
	pale_panel.position.y = size.y * 0.16
	pale_panel.material_override = _material(Color("#c7a17b"), 0.92)
	body.add_child(pale_panel)
	var rust_strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	if size.x >= size.z:
		strip_mesh.size = Vector3(size.x + 0.08, 0.18, size.z + 0.08)
	else:
		strip_mesh.size = Vector3(size.x + 0.08, 0.18, size.z + 0.08)
	rust_strip.mesh = strip_mesh
	rust_strip.position.y = size.y * 0.34
	rust_strip.material_override = _material(Color("#9b3f28"), 0.95)
	body.add_child(rust_strip)
	return body


func _create_invisible_limit(node_name: String, limit_position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = limit_position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _create_health_pad(node_name: String, pad_position: Vector3) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = pad_position
	root.add_to_group("health_kit_placeholder")
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(3.3, 0.24, 3.3)
	base.mesh = base_mesh
	base.position.y = 0.12
	base.material_override = _material(Color("#594b40"), 0.75)
	root.add_child(base)
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(2.45, 0.10, 2.45)
	screen.mesh = screen_mesh
	screen.position.y = 0.29
	screen.material_override = _material(Color("#47dff1"), 0.22, Color("#17cce9"))
	root.add_child(screen)
	var cross_x := MeshInstance3D.new()
	var cross_x_mesh := BoxMesh.new()
	cross_x_mesh.size = Vector3(1.35, 0.08, 0.25)
	cross_x.mesh = cross_x_mesh
	cross_x.position.y = 0.36
	cross_x.material_override = _material(Color("#d8ffff"), 0.15, Color("#a5f9ff"))
	root.add_child(cross_x)
	var cross_z := MeshInstance3D.new()
	var cross_z_mesh := BoxMesh.new()
	cross_z_mesh.size = Vector3(0.25, 0.08, 1.35)
	cross_z.mesh = cross_z_mesh
	cross_z.position.y = 0.36
	cross_z.material_override = cross_x.material_override
	root.add_child(cross_z)
	var glow := OmniLight3D.new()
	glow.position.y = 0.8
	glow.light_color = Color("#50e9ff")
	glow.light_energy = 1.4
	glow.omni_range = 4.0
	root.add_child(glow)
	add_child(root)


func _create_bush_cluster(node_name: String, bush_position: Vector3, bush_scale: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = bush_position
	root.scale = Vector3.ONE * bush_scale
	root.add_to_group("bush_placeholder")
	var colors := [Color("#53613b"), Color("#6c7041"), Color("#7d6539")]
	var offsets := [Vector3(-0.65, 0.45, 0.1), Vector3(0.0, 0.58, -0.2), Vector3(0.62, 0.42, 0.15), Vector3(0.15, 0.38, 0.55)]
	for index in range(offsets.size()):
		var tuft := MeshInstance3D.new()
		var tuft_mesh := SphereMesh.new()
		tuft_mesh.radius = 0.62
		tuft_mesh.height = 0.9
		tuft_mesh.radial_segments = 7
		tuft_mesh.rings = 4
		tuft.mesh = tuft_mesh
		tuft.position = offsets[index]
		tuft.scale = Vector3(1.0, 0.8 + float(index % 2) * 0.25, 0.8)
		tuft.material_override = _material(colors[index % colors.size()], 1.0)
		root.add_child(tuft)
	add_child(root)


func _create_tire_stack(node_name: String, tire_position: Vector3, count: int) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = tire_position
	for index in range(count):
		var tire := MeshInstance3D.new()
		var tire_mesh := TorusMesh.new()
		tire_mesh.inner_radius = 0.38
		tire_mesh.outer_radius = 0.72
		tire_mesh.rings = 8
		tire_mesh.ring_segments = 12
		tire.mesh = tire_mesh
		tire.position = Vector3(float(index % 2) * 0.28, 0.18 + float(index) * 0.28, float(index % 2) * -0.18)
		tire.rotation_degrees = Vector3(0.0, float(index) * 23.0, 0.0)
		tire.material_override = _material(Color("#272725"), 1.0)
		root.add_child(tire)
	add_child(root)


func _create_banner(banner_position: Vector3, rotation_y: float) -> void:
	var banner := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.0, 1.8, 0.08)
	banner.mesh = mesh
	banner.position = banner_position
	banner.rotation_degrees.y = rotation_y
	banner.material_override = _material(Color("#9f3028"), 0.92)
	add_child(banner)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(-3.5, 0.0, 17.0)
	add_child(player)


func _build_camera() -> void:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CAMERA_RIG_SCRIPT)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	# A high, slightly perspective view keeps the arena readable while preserving
	# the visible height and depth found in the visual references.
	camera.position = Vector3(0.0, 20.5, 17.5)
	camera.fov = 38.0
	camera.current = true
	rig.add_child(camera)
	# Add the complete rig only after its Camera3D child exists. Otherwise the
	# rig's _ready() runs too early and the camera never gets aimed at the player.
	add_child(rig)
	rig.call("set_target", player)


func _build_target() -> void:
	var target := StaticBody3D.new()
	target.name = "TargetDummy"
	target.set_script(TARGET_SCRIPT)
	target.position = Vector3(3.5, 0.0, 15.5)
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
	help.text = "ZQSD / WASD / flèches : déplacement\nSouris : orienter l'attaque   •   Clic gauche ou Espace : Electro Axe\nCombo en 3 coups : estoc → slash → onde de choc. Les obstacles bloquent le mouvement."
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(help)

	var status := Label.new()
	status.name = "Status"
	status.position = Vector2(24.0, 650.0)
	status.text = "BLOCKOUT ARÈNE — murs et couverts actifs • plateformes bleues et bushs encore purement visuels."
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
