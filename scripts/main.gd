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
	environment.fog_enabled = true
	environment.fog_light_color = Color("#c6805b")
	environment.fog_light_energy = 0.32
	environment.fog_density = 0.006
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
	_create_ground_details()

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
	_create_brazier("BrazierNorthWest", Vector3(-22.8, 0.0, -21.8))
	_create_brazier("BrazierNorthEast", Vector3(22.8, 0.0, -21.8))
	_create_brazier("BrazierSouthWest", Vector3(-22.8, 0.0, 21.8))
	_create_brazier("BrazierSouthEast", Vector3(22.8, 0.0, 21.8))
	_create_scrap_pile("ScrapPileNorth", Vector3(-19.0, 0.0, -21.2), 0.9)
	_create_scrap_pile("ScrapPileSouth", Vector3(19.0, 0.0, 21.2), 0.9)
	_create_scrap_pile("ScrapPileWest", Vector3(-21.2, 0.0, 18.0), 0.75)
	_create_scrap_pile("ScrapPileEast", Vector3(21.2, 0.0, -18.0), 0.75)


func _create_ground_details() -> void:
	# Broad, low-contrast stains give the sand a hand-painted variation without
	# needing external textures. They remain below the player and never collide.
	var stains := [
		[Vector3(-12.0, 0.012, -2.0), Vector2(7.5, 2.4), -18.0, Color("#995a3b")],
		[Vector3(11.0, 0.012, 4.0), Vector2(8.0, 2.2), 24.0, Color("#b57447")],
		[Vector3(-1.0, 0.012, 17.5), Vector2(10.0, 2.0), -8.0, Color("#8f553b")],
		[Vector3(1.0, 0.012, -17.0), Vector2(9.0, 2.5), 13.0, Color("#b97749")],
	]
	for stain_data in stains:
		var stain := MeshInstance3D.new()
		var stain_mesh := PlaneMesh.new()
		stain_mesh.size = stain_data[1]
		stain.mesh = stain_mesh
		stain.position = stain_data[0]
		stain.rotation_degrees.y = stain_data[2]
		stain.material_override = _material(stain_data[3], 1.0)
		add_child(stain)
	# Small low-poly rocks and metal fragments break up the open centre.
	var rocks := [
		Vector3(-13.5, 0.0, -2.7), Vector3(-10.4, 0.0, 5.7), Vector3(-3.2, 0.0, -16.0),
		Vector3(3.8, 0.0, -5.6), Vector3(11.8, 0.0, 2.3), Vector3(14.0, 0.0, 7.5),
		Vector3(-14.8, 0.0, 14.2), Vector3(4.4, 0.0, 14.7), Vector3(14.3, 0.0, -13.0),
		Vector3(-4.0, 0.0, 6.0), Vector3(2.4, 0.0, 4.4), Vector3(-2.0, 0.0, -3.5),
	]
	for index in range(rocks.size()):
		_create_ground_rock("GroundRock%d" % index, rocks[index], 0.16 + float(index % 3) * 0.08)
	# Old vehicle tracks are painted on the ground as broken, irregular lines.
	_create_ground_track(Vector3(-20.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0), 0.12)
	_create_ground_track(Vector3(0.0, 0.0, -19.0), Vector3(0.0, 0.0, 18.0), 0.10)


func _create_ground_rock(node_name: String, rock_position: Vector3, rock_scale: float) -> void:
	var rock := MeshInstance3D.new()
	rock.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 0.6
	mesh.radial_segments = 6
	mesh.rings = 3
	rock.mesh = mesh
	rock.position = rock_position + Vector3.UP * (rock_scale * 0.22)
	rock.scale = Vector3(1.4, 0.55, 0.9) * rock_scale
	rock.rotation_degrees = Vector3(0.0, fmod(rock_position.x * 17.0 + rock_position.z * 9.0, 360.0), 7.0)
	rock.material_override = _material(Color("#655047"), 0.96)
	add_child(rock)


func _create_ground_track(start: Vector3, end: Vector3, width: float) -> void:
	var track := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _material(Color("#875039"), 1.0)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var direction := (end - start).normalized()
	var side := Vector3(-direction.z, 0.0, direction.x)
	for index in range(10):
		var t0 := float(index) / 10.0
		var t1 := t0 + 0.065
		var centre0 := start.lerp(end, t0)
		var centre1 := start.lerp(end, minf(t1, 1.0))
		var offset := side * (0.38 if index % 2 == 0 else -0.38)
		mesh.surface_add_vertex(centre0 + offset - side * width + Vector3.UP * 0.02)
		mesh.surface_add_vertex(centre1 + offset + side * width + Vector3.UP * 0.02)
	mesh.surface_end()
	track.mesh = mesh
	add_child(track)


func _create_brazier(node_name: String, brazier_position: Vector3) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = brazier_position
	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.30
	bowl_mesh.bottom_radius = 0.42
	bowl_mesh.height = 0.42
	bowl.mesh = bowl_mesh
	bowl.position.y = 0.21
	bowl.material_override = _material(Color("#4b3a32"), 0.78)
	root.add_child(bowl)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.24
	flame_mesh.height = 0.62
	flame.mesh = flame_mesh
	flame.position.y = 0.65
	flame.scale = Vector3(0.75, 1.3, 0.75)
	flame.material_override = _material(Color("#ff9e35"), 0.25, Color("#ff6b21"))
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.position.y = 1.1
	light.light_color = Color("#ff9d4c")
	light.light_energy = 1.3
	light.omni_range = 5.0
	root.add_child(light)
	add_child(root)


func _create_scrap_pile(node_name: String, pile_position: Vector3, pile_scale: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = pile_position
	root.scale = Vector3.ONE * pile_scale
	for index in range(5):
		var piece := MeshInstance3D.new()
		var piece_mesh := BoxMesh.new()
		piece_mesh.size = Vector3(0.65 + float(index % 2) * 0.25, 0.18 + float(index % 3) * 0.12, 0.42)
		piece.mesh = piece_mesh
		piece.position = Vector3(-0.6 + float(index % 3) * 0.5, 0.12 + float(index / 3) * 0.25, -0.25 + float(index % 2) * 0.45)
		piece.rotation_degrees = Vector3(float(index * 9), float(index * 31), float(index * 17))
		piece.material_override = _material(Color("#704334") if index % 2 == 0 else Color("#6f6653"), 0.9)
		root.add_child(piece)
	add_child(root)


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
	# Repeated beams, bolts and a raised cap sell the object as assembled scrap
	# instead of a clean primitive while keeping one simple collision shape.
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(size.x + 0.24, 0.16, size.z + 0.24)
	cap.mesh = cap_mesh
	cap.position.y = size.y * 0.53
	cap.material_override = _material(Color("#4b3a34"), 0.8)
	body.add_child(cap)
	var post_count := 2 if size.x >= size.z else 3
	for index in range(post_count):
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.14, size.y + 0.30, 0.18) if size.x >= size.z else Vector3(0.18, size.y + 0.30, 0.14)
		post.mesh = post_mesh
		if size.x >= size.z:
			post.position = Vector3(lerpf(-size.x * 0.34, size.x * 0.34, float(index) / float(maxi(1, post_count - 1))), 0.0, size.z * 0.48)
		else:
			post.position = Vector3(size.x * 0.48, 0.0, lerpf(-size.z * 0.34, size.z * 0.34, float(index) / float(maxi(1, post_count - 1))))
		post.material_override = _material(Color("#453832"), 0.82)
		body.add_child(post)
	for corner in [Vector3(-size.x * 0.40, size.y * 0.22, -size.z * 0.47), Vector3(size.x * 0.40, size.y * 0.22, -size.z * 0.47), Vector3(-size.x * 0.40, size.y * 0.22, size.z * 0.47), Vector3(size.x * 0.40, size.y * 0.22, size.z * 0.47)]:
		var bolt := MeshInstance3D.new()
		var bolt_mesh := SphereMesh.new()
		bolt_mesh.radius = 0.11
		bolt_mesh.height = 0.16
		bolt.mesh = bolt_mesh
		bolt.position = corner
		bolt.scale = Vector3(1.0, 0.45, 1.0)
		bolt.material_override = _material(Color("#d69a5e"), 0.45, Color("#9f5731"))
		body.add_child(bolt)
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
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.035
		stem_mesh.bottom_radius = 0.08
		stem_mesh.height = 0.55
		stem.mesh = stem_mesh
		stem.position = offsets[index] - Vector3.UP * 0.28
		stem.material_override = _material(Color("#51402c"), 1.0)
		root.add_child(stem)
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
	var root := Node3D.new()
	root.name = "ScrapBanner"
	root.position = banner_position
	root.rotation_degrees.y = rotation_y
	var banner := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.0, 1.8, 0.08)
	banner.mesh = mesh
	banner.material_override = _material(Color("#9f3028"), 0.92)
	root.add_child(banner)
	var emblem_vertical := MeshInstance3D.new()
	var vertical_mesh := BoxMesh.new()
	vertical_mesh.size = Vector3(0.20, 0.96, 0.05)
	emblem_vertical.mesh = vertical_mesh
	emblem_vertical.position = Vector3(0.0, 0.0, -0.06)
	emblem_vertical.material_override = _material(Color("#e3c28e"), 0.8)
	root.add_child(emblem_vertical)
	var emblem_horizontal := MeshInstance3D.new()
	var horizontal_mesh := BoxMesh.new()
	horizontal_mesh.size = Vector3(0.92, 0.20, 0.05)
	emblem_horizontal.mesh = horizontal_mesh
	emblem_horizontal.position = Vector3(0.0, 0.0, -0.065)
	emblem_horizontal.material_override = emblem_vertical.material_override
	root.add_child(emblem_horizontal)
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.035
	pole_mesh.bottom_radius = 0.055
	pole_mesh.height = 2.2
	pole.mesh = pole_mesh
	pole.position = Vector3(-1.62, 0.0, 0.0)
	pole.material_override = _material(Color("#453831"), 0.85)
	root.add_child(pole)
	add_child(root)


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
