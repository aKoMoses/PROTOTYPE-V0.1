extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera_rig.gd")
const TARGET_SCRIPT := preload("res://scripts/target_dummy.gd")
const SAND_TEXTURE: Texture2D = preload("res://art/sand_dust.svg")
const METAL_CREAM_TEXTURE: Texture2D = preload("res://art/metal_cream.svg")
const METAL_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const STEEL_DARK_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const BANNER_TEXTURE: Texture2D = preload("res://art/banner_red.svg")

var player: CharacterBody3D
var _ambient_clock := 0.0
var _flicker_lights: Array[OmniLight3D] = []


func _process(delta: float) -> void:
	_ambient_clock += delta
	for index in range(_flicker_lights.size()):
		var light := _flicker_lights[index]
		if not is_instance_valid(light):
			continue
		var base_energy := float(light.get_meta("base_energy", 1.0))
		var phase := float(index) * 1.71
		light.light_energy = base_energy + sin(_ambient_clock * (5.0 + float(index % 3)) + phase) * 0.14 + sin(_ambient_clock * 11.0 + phase) * 0.06


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
	environment.background_color = Color("#20191b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9ca4b0")
	environment.ambient_light_energy = 0.52
	environment.fog_enabled = true
	environment.fog_light_color = Color("#6e7787")
	environment.fog_light_energy = 0.18
	environment.fog_density = 0.008
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffd2a1")
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "CoolFillLight"
	fill.light_color = Color("#8fa8c4")
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)
	var arena_fill := OmniLight3D.new()
	arena_fill.name = "ArenaNeutralFill"
	arena_fill.position = Vector3(0.0, 9.0, 0.0)
	arena_fill.light_color = Color("#b6c3d0")
	arena_fill.light_energy = 0.35
	arena_fill.omni_range = 32.0
	arena_fill.shadow_enabled = false
	add_child(arena_fill)


func _build_arena() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(54.0, 54.0)
	ground.mesh = ground_mesh
	ground.material_override = _textured_material(Color.WHITE, 0.98, Color.BLACK, SAND_TEXTURE, Vector3(7.0, 7.0, 7.0))
	add_child(ground)
	_create_ground_details()
	_create_ambient_dust()

	_build_scrap_perimeter()

	# Four future health-kit locations. They are landmarks only until their rules
	# are defined in the design document.
	_create_health_pad("HealthPadNorth", Vector3(0.0, 0.0, -20.8))
	_create_health_pad("HealthPadSouth", Vector3(0.0, 0.0, 20.8))
	_create_health_pad("HealthPadWest", Vector3(-21.0, 0.0, 0.0))
	_create_health_pad("HealthPadEast", Vector3(21.0, 0.0, 0.0))

	# Main readable lanes: two central columns, transverse covers and mirrored
	# side pockets inspired by the reference without copying it literally.
	_create_scrap_barrier("NorthCenterCover", Vector3(0.0, 0.95, -9.0), Vector3(10.8, 1.9, 1.55))
	_create_scrap_barrier("WestSpine", Vector3(-7.0, 1.10, 1.2), Vector3(2.15, 2.2, 9.6))
	_create_scrap_barrier("EastSpine", Vector3(7.0, 1.10, 1.2), Vector3(2.15, 2.2, 9.6))
	_create_scrap_barrier("SouthCenterCover", Vector3(0.0, 0.95, 11.0), Vector3(9.5, 1.9, 1.55))

	_create_scrap_barrier("NorthWestAngle", Vector3(-11.3, 1.0, -9.4), Vector3(6.2, 2.0, 1.4), -24.0)
	_create_scrap_barrier("SouthEastAngle", Vector3(11.3, 1.0, 10.8), Vector3(6.2, 2.0, 1.4), -24.0)
	_create_scrap_barrier("NorthEastAngle", Vector3(12.0, 0.95, -6.7), Vector3(5.0, 1.9, 1.3), 25.0)
	_create_scrap_barrier("SouthWestAngle", Vector3(-12.0, 0.95, 8.1), Vector3(5.0, 1.9, 1.3), 25.0)

	_create_scrap_barrier("WestPocketLong", Vector3(-18.5, 1.0, 8.0), Vector3(1.8, 2.0, 5.5))
	_create_scrap_barrier("WestPocketShort", Vector3(-16.0, 1.0, 10.0), Vector3(4.6, 2.0, 1.6))
	_create_scrap_barrier("EastPocketLong", Vector3(18.5, 1.0, -8.0), Vector3(1.8, 2.0, 5.5))
	_create_scrap_barrier("EastPocketShort", Vector3(16.0, 1.0, -10.0), Vector3(4.6, 2.0, 1.6))

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
	_create_bush_cluster("BushNorthWestCover", Vector3(-14.0, 0.0, -8.0), 1.35)
	_create_bush_cluster("BushNorthEastCover", Vector3(13.8, 0.0, -8.0), 1.35)
	_create_bush_cluster("BushSouthWestCover", Vector3(-13.8, 0.0, 10.0), 1.35)
	_create_bush_cluster("BushSouthEastCover", Vector3(14.0, 0.0, 10.0), 1.35)
	_create_bush_cluster("BushWestPocket", Vector3(-18.5, 0.0, 5.4), 1.25)
	_create_bush_cluster("BushEastPocket", Vector3(18.5, 0.0, -5.4), 1.25)
	_create_bush_cluster("BushNorthPad", Vector3(-2.8, 0.0, -20.5), 1.0)
	_create_bush_cluster("BushSouthPad", Vector3(2.8, 0.0, 20.5), 1.0)
	_create_pipe_clutter("PipeClutterWest", Vector3(-20.5, 0.0, -6.0), 22.0)
	_create_pipe_clutter("PipeClutterEast", Vector3(20.5, 0.0, 6.0), -22.0)

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
	_create_wrecked_vehicle("WreckNorthWest", Vector3(-20.0, 0.0, -21.0), 18.0, true)
	_create_wrecked_vehicle("WreckNorthEast", Vector3(20.0, 0.0, -21.0), -12.0, false)
	_create_wrecked_vehicle("WreckSouthWest", Vector3(-20.0, 0.0, 21.0), 164.0, false)
	_create_wrecked_vehicle("WreckSouthEast", Vector3(20.0, 0.0, 21.0), 192.0, true)
	_create_barrel_cluster("BarrelsNorth", Vector3(-14.0, 0.0, -23.1), 3)
	_create_barrel_cluster("BarrelsSouth", Vector3(14.0, 0.0, 23.1), 3)
	_create_barrel_cluster("BarrelsWest", Vector3(-23.1, 0.0, -13.0), 2)
	_create_barrel_cluster("BarrelsEast", Vector3(23.1, 0.0, 13.0), 2)
	_create_crate_stack("CratesNorth", Vector3(13.8, 0.0, -22.5), 3)
	_create_crate_stack("CratesSouth", Vector3(-13.8, 0.0, 22.5), 3)
	_create_crate_stack("CratesWest", Vector3(-22.5, 0.0, 13.5), 2)
	_create_crate_stack("CratesEast", Vector3(22.5, 0.0, -13.5), 2)
	_create_hanging_lamp("LampNorth", Vector3(-8.0, 3.1, -24.2))
	_create_hanging_lamp("LampSouth", Vector3(8.0, 3.1, 24.2))
	_create_hanging_lamp("LampWest", Vector3(-24.2, 3.1, 8.0), 90.0)
	_create_hanging_lamp("LampEast", Vector3(24.2, 3.1, -8.0), 90.0)
	_create_dead_grass_line(Vector3(-22.0, 0.0, -10.0), 5, 0.8)
	_create_dead_grass_line(Vector3(22.0, 0.0, 10.0), 5, 0.8)
	_create_dead_grass_line(Vector3(-10.0, 0.0, 22.0), 5, 0.7)
	_create_dead_grass_line(Vector3(10.0, 0.0, -22.0), 5, 0.7)
	_create_arena_skull("SkullNorthWest", Vector3(-22.8, 0.0, -14.0), 0.85)
	_create_arena_skull("SkullNorthEast", Vector3(22.8, 0.0, -14.0), 0.72)
	_create_arena_skull("SkullSouthWest", Vector3(-22.8, 0.0, 14.0), 0.72)
	_create_arena_skull("SkullSouthEast", Vector3(22.8, 0.0, 14.0), 0.85)
	_create_fight_story_marks()
	_create_spectator_stands()
	_create_arena_scoreboard()


func _create_wrecked_vehicle(node_name: String, vehicle_position: Vector3, rotation_y: float, with_crates: bool) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = vehicle_position
	root.rotation_degrees.y = rotation_y
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(4.4, 1.25, 2.55)
	body.mesh = body_mesh
	body.position.y = 0.78
	body.rotation_degrees.z = -3.0
	body.material_override = _textured_material(Color.WHITE, 0.88, Color.BLACK, METAL_RUST_TEXTURE, Vector3(1.2, 1.2, 1.2))
	root.add_child(body)
	var hood := MeshInstance3D.new()
	var hood_mesh := BoxMesh.new()
	hood_mesh.size = Vector3(1.35, 0.46, 2.25)
	hood.mesh = hood_mesh
	hood.position = Vector3(-1.48, 1.46, 0.0)
	hood.rotation_degrees.z = -4.0
	hood.material_override = _textured_material(Color.WHITE, 0.84, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.3, 1.3, 1.3))
	root.add_child(hood)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.95, 1.12, 2.28)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.65, 1.55, 0.0)
	cabin.rotation_degrees.z = 4.0
	cabin.material_override = _textured_material(Color.WHITE, 0.88, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.0, 1.0, 1.0))
	root.add_child(cabin)
	for side in [-1.0, 1.0]:
		var window := MeshInstance3D.new()
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3(1.1, 0.48, 0.05)
		window.mesh = window_mesh
		window.position = Vector3(0.65, 1.65, side * 1.17)
		window.material_override = _material(Color("#24383a"), 0.28, Color("#172a2f"))
		root.add_child(window)
	for wheel_position in [Vector3(-1.45, 0.32, -1.28), Vector3(-1.45, 0.32, 1.28), Vector3(1.45, 0.32, -1.28), Vector3(1.45, 0.32, 1.28)]:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := TorusMesh.new()
		wheel_mesh.inner_radius = 0.30
		wheel_mesh.outer_radius = 0.55
		wheel_mesh.rings = 8
		wheel_mesh.ring_segments = 12
		wheel.mesh = wheel_mesh
		wheel.position = wheel_position
		wheel.rotation_degrees.x = 90.0
		wheel.material_override = _material(Color("#272625"), 1.0)
		root.add_child(wheel)
	for index in range(3):
		var brace := MeshInstance3D.new()
		var brace_mesh := BoxMesh.new()
		brace_mesh.size = Vector3(0.13, 0.12, 2.58)
		brace.mesh = brace_mesh
		brace.position = Vector3(-1.0 + float(index) * 1.15, 1.45, 0.0)
		brace.material_override = _material(Color("#c38345"), 0.7)
		root.add_child(brace)
	if with_crates:
		_create_vehicle_crate(root, Vector3(0.8, 2.45, -0.55), 0.75)
		_create_vehicle_crate(root, Vector3(1.1, 2.45, 0.58), 0.62)
	add_child(root)


func _create_vehicle_crate(parent: Node3D, local_position: Vector3, crate_scale: float) -> void:
	var crate := MeshInstance3D.new()
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(1.05, 0.72, 0.88) * crate_scale
	crate.mesh = crate_mesh
	crate.position = local_position
	crate.rotation_degrees = Vector3(0.0, 18.0, -4.0)
	crate.material_override = _textured_material(Color.WHITE, 0.95, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.0, 1.0, 1.0))
	parent.add_child(crate)


func _create_barrel_cluster(node_name: String, cluster_position: Vector3, count: int) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = cluster_position
	for index in range(count):
		var barrel := MeshInstance3D.new()
		var barrel_mesh := CylinderMesh.new()
		barrel_mesh.top_radius = 0.42
		barrel_mesh.bottom_radius = 0.50
		barrel_mesh.height = 1.05
		barrel.mesh = barrel_mesh
		barrel.position = Vector3(float(index % 2) * 0.76, 0.54 + float(index / 2) * 0.82, float(index % 2) * 0.18)
		barrel.rotation_degrees = Vector3(0.0, float(index) * 17.0, float(index % 2) * 4.0)
		barrel.material_override = _textured_material(Color.WHITE, 0.84, Color.BLACK, METAL_RUST_TEXTURE if index % 2 == 0 else STEEL_DARK_TEXTURE, Vector3(0.8, 0.8, 0.8))
		root.add_child(barrel)
		for band_height in [0.24, 0.78]:
			var band := MeshInstance3D.new()
			var band_mesh := TorusMesh.new()
			band_mesh.inner_radius = 0.42
			band_mesh.outer_radius = 0.47
			band_mesh.rings = 8
			band_mesh.ring_segments = 12
			band.mesh = band_mesh
			band.position = barrel.position + Vector3.UP * (band_height - 0.54)
			band.material_override = _material(Color("#c18445"), 0.7)
			root.add_child(band)
	add_child(root)


func _create_crate_stack(node_name: String, stack_position: Vector3, count: int) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = stack_position
	for index in range(count):
		var crate := MeshInstance3D.new()
		var crate_mesh := BoxMesh.new()
		crate_mesh.size = Vector3(1.35, 1.0, 1.25) * (0.82 + float(index % 2) * 0.12)
		crate.mesh = crate_mesh
		crate.position = Vector3(float(index % 2) * 0.72, 0.5 + float(index / 2) * 0.94, float(index % 3) * 0.16)
		crate.rotation_degrees = Vector3(0.0, float(index) * 13.0, float(index % 2) * 3.0)
		crate.material_override = _textured_material(Color.WHITE, 0.94, Color.BLACK, STEEL_DARK_TEXTURE if index % 2 == 0 else METAL_RUST_TEXTURE, Vector3(1.0, 1.0, 1.0))
		root.add_child(crate)
		for axis in [-1.0, 1.0]:
			var strap := MeshInstance3D.new()
			var strap_mesh := BoxMesh.new()
			strap_mesh.size = Vector3(0.09, crate_mesh.size.y + 0.08, crate_mesh.size.z + 0.06) if absf(axis) > 0.0 else Vector3(0.09, 0.1, 0.1)
			strap.mesh = strap_mesh
			strap.position = crate.position + Vector3(axis * crate_mesh.size.x * 0.29, 0.0, 0.0)
			strap.material_override = _material(Color("#b57d46"), 0.78)
			root.add_child(strap)
	add_child(root)


func _create_hanging_lamp(node_name: String, lamp_position: Vector3, rotation_y: float = 0.0) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = lamp_position
	root.rotation_degrees.y = rotation_y
	var chain := MeshInstance3D.new()
	var chain_mesh := CylinderMesh.new()
	chain_mesh.top_radius = 0.035
	chain_mesh.bottom_radius = 0.035
	chain_mesh.height = 1.1
	chain.mesh = chain_mesh
	chain.position.y = 0.55
	chain.material_override = _material(Color("#3e3230"), 0.9)
	root.add_child(chain)
	var lantern := MeshInstance3D.new()
	var lantern_mesh := CylinderMesh.new()
	lantern_mesh.top_radius = 0.18
	lantern_mesh.bottom_radius = 0.25
	lantern_mesh.height = 0.46
	lantern.mesh = lantern_mesh
	lantern.position.y = -0.05
	lantern.material_override = _material(Color("#7c4a2e"), 0.72)
	root.add_child(lantern)
	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.13
	glow_mesh.height = 0.24
	glow.mesh = glow_mesh
	glow.position.y = -0.05
	glow.material_override = _material(Color("#ffd275"), 0.25, Color("#ff9b35"))
	root.add_child(glow)
	var light := OmniLight3D.new()
	light.position.y = -0.05
	light.light_color = Color("#ffb55b")
	light.light_energy = 1.2
	light.omni_range = 4.5
	light.set_meta("base_energy", 1.2)
	_flicker_lights.append(light)
	root.add_child(light)
	add_child(root)


func _create_dead_grass_line(line_position: Vector3, count: int, grass_scale: float) -> void:
	var root := Node3D.new()
	root.name = "DryGrass"
	root.position = line_position
	for index in range(count):
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(0.08, 0.75 + float(index % 3) * 0.18, 0.18) * grass_scale
		blade.mesh = blade_mesh
		blade.position = Vector3(float(index) * 0.42 - float(count - 1) * 0.2, blade_mesh.size.y * 0.5, sin(float(index) * 1.7) * 0.3)
		blade.rotation_degrees = Vector3(0.0, float(index) * 19.0, -12.0 + float(index % 2) * 23.0)
		blade.material_override = _material(Color("#766b35") if index % 2 == 0 else Color("#96743b"), 1.0)
		root.add_child(blade)
	add_child(root)


func _create_arena_skull(node_name: String, skull_position: Vector3, skull_scale: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = skull_position
	root.scale = Vector3.ONE * skull_scale
	var stake := MeshInstance3D.new()
	var stake_mesh := CylinderMesh.new()
	stake_mesh.top_radius = 0.04
	stake_mesh.bottom_radius = 0.10
	stake_mesh.height = 1.35
	stake.mesh = stake_mesh
	stake.position.y = 0.68
	stake.material_override = _material(Color("#3b2e2b"), 0.94)
	root.add_child(stake)
	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.46
	skull_mesh.height = 0.72
	skull.mesh = skull_mesh
	skull.position.y = 1.25
	skull.scale = Vector3(1.0, 0.88, 0.76)
	skull.material_override = _material(Color("#c2ab85"), 0.92)
	root.add_child(skull)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.095
		eye_mesh.height = 0.14
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.18, 1.30, -0.36)
		eye.material_override = _material(Color("#e33c42"), 0.25, Color("#ff1f39"))
		root.add_child(eye)
	for side in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var horn_mesh := CylinderMesh.new()
		horn_mesh.top_radius = 0.01
		horn_mesh.bottom_radius = 0.12
		horn_mesh.height = 0.42
		horn.mesh = horn_mesh
		horn.position = Vector3(side * 0.34, 1.55, 0.0)
		horn.rotation_degrees = Vector3(0.0, 0.0, side * -28.0)
		horn.material_override = _material(Color("#554036"), 0.95)
		root.add_child(horn)
	add_child(root)


func _create_fight_story_marks() -> void:
	# Scars are deliberately placed away from the player spawn so they read as
	# evidence of earlier matches instead of active gameplay indicators.
	_create_blood_stain(Vector3(-7.8, 0.0, 3.8), 0.65, 0.23)
	_create_blood_stain(Vector3(8.8, 0.0, -1.6), 0.55, 0.20)
	_create_blood_stain(Vector3(1.8, 0.0, -2.0), 0.85, 0.24)
	_create_blood_stain(Vector3(-4.0, 0.0, 12.8), 0.48, 0.22)
	_create_scorch_mark(Vector3(-6.7, 0.0, 6.8), 0.72)
	_create_scorch_mark(Vector3(6.6, 0.0, 6.4), 0.82)
	_create_crater_story(Vector3(-10.0, 0.0, -11.8), 0.72)
	_create_crater_story(Vector3(10.5, 0.0, 12.8), 0.56)
	_create_shell_casings(Vector3(-4.6, 0.0, 15.5), 11)
	_create_shell_casings(Vector3(4.8, 0.0, -14.5), 8)
	_create_bullet_scar(Vector3(-21.9, 1.15, -4.0), 90.0)
	_create_bullet_scar(Vector3(21.9, 1.0, 4.5), -90.0)
	_create_broken_weapon(Vector3(-15.6, 0.0, 3.6), -22.0)
	_create_broken_weapon(Vector3(15.5, 0.0, -4.0), 148.0)
	_create_debris_field(Vector3(-3.8, 0.0, 7.0), 10, 2.2)
	_create_debris_field(Vector3(4.4, 0.0, -6.5), 9, 1.9)
	_create_debris_field(Vector3(-1.8, 0.0, -1.0), 7, 1.5)
	_create_wall_graffiti(Vector3(-8.0, 1.15, -25.62), 0.0, Color("#d2b27d"))
	_create_wall_graffiti(Vector3(8.5, 1.0, 25.62), 180.0, Color("#762e32"))
	_create_wall_graffiti(Vector3(-25.62, 1.1, 7.0), 90.0, Color("#c5a06f"))
	_create_wall_graffiti(Vector3(25.62, 1.1, -7.0), -90.0, Color("#762e32"))


func _create_crater_story(crater_position: Vector3, radius: float) -> void:
	var root := Node3D.new()
	root.name = "OldFightCrater"
	root.position = crater_position
	var crater := MeshInstance3D.new()
	var crater_mesh := CylinderMesh.new()
	crater_mesh.top_radius = radius * 0.65
	crater_mesh.bottom_radius = radius
	crater_mesh.height = 0.08
	crater.mesh = crater_mesh
	crater.position.y = 0.05
	crater.material_override = _create_transparent_material(Color("#30272a"), 0.58)
	root.add_child(crater)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.72
	ring_mesh.outer_radius = radius * 0.78
	ring_mesh.rings = 10
	ring_mesh.ring_segments = 18
	ring.mesh = ring_mesh
	ring.position.y = 0.11
	ring.material_override = _material(Color("#713f39"), 0.94, Color("#2b2227"))
	root.add_child(ring)
	for index in range(5):
		var rock := MeshInstance3D.new()
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = 0.13 + float(index % 2) * 0.08
		rock_mesh.height = 0.22 + float(index % 2) * 0.12
		rock.mesh = rock_mesh
		var angle := TAU * float(index) / 5.0
		rock.position = Vector3(cos(angle), 0.16, sin(angle)) * radius * 0.85
		rock.scale = Vector3(1.2, 0.65, 0.9)
		rock.material_override = _material(Color("#554645"), 0.96)
		root.add_child(rock)
	add_child(root)


func _create_shell_casings(origin: Vector3, count: int) -> void:
	var root := Node3D.new()
	root.name = "SpentCasings"
	root.position = origin
	for index in range(count):
		var casing := MeshInstance3D.new()
		var casing_mesh := CylinderMesh.new()
		casing_mesh.top_radius = 0.035
		casing_mesh.bottom_radius = 0.055
		casing_mesh.height = 0.18
		casing.mesh = casing_mesh
		var angle := float(index) * 2.37
		casing.position = Vector3(cos(angle) * (0.5 + float(index % 4) * 0.22), 0.08, sin(angle) * (0.4 + float(index % 3) * 0.24))
		casing.rotation_degrees = Vector3(70.0 + float(index % 3) * 15.0, float(index) * 37.0, 12.0)
		casing.material_override = _material(Color("#d28a36"), 0.56, Color("#7a321f"))
		root.add_child(casing)
	add_child(root)


func _create_bullet_scar(scar_position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = "BulletScar"
	root.position = scar_position
	root.rotation_degrees.y = rotation_y
	for index in range(5):
		var mark := MeshInstance3D.new()
		var mark_mesh := CylinderMesh.new()
		mark_mesh.top_radius = 0.10 + float(index % 2) * 0.04
		mark_mesh.bottom_radius = 0.12 + float(index % 2) * 0.05
		mark_mesh.height = 0.025
		mark.mesh = mark_mesh
		mark.position = Vector3(-0.65 + float(index) * 0.30, 0.0, 0.0)
		mark.rotation_degrees = Vector3(90.0, 0.0, float(index) * 13.0)
		mark.material_override = _create_transparent_material(Color("#251f22"), 0.65)
		root.add_child(mark)
	add_child(root)


func _create_broken_weapon(weapon_position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = "BrokenWeapon"
	root.position = weapon_position
	root.rotation_degrees.y = rotation_y
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.055
	shaft_mesh.bottom_radius = 0.08
	shaft_mesh.height = 1.35
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees.z = 90.0
	shaft.material_override = _material(Color("#51382f"), 0.9)
	root.add_child(shaft)
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.45, 0.08, 0.22)
	blade.mesh = blade_mesh
	blade.position = Vector3(0.67, 0.0, 0.0)
	blade.material_override = _material(Color("#9e4d36"), 0.82)
	root.add_child(blade)
	add_child(root)


func _create_wall_graffiti(graffiti_position: Vector3, rotation_y: float, color: Color) -> void:
	var root := Node3D.new()
	root.name = "OldArenaGraffiti"
	root.position = graffiti_position
	root.rotation_degrees.y = rotation_y
	var circle := MeshInstance3D.new()
	var circle_mesh := TorusMesh.new()
	circle_mesh.inner_radius = 0.35
	circle_mesh.outer_radius = 0.44
	circle_mesh.rings = 8
	circle_mesh.ring_segments = 14
	circle.mesh = circle_mesh
	circle.position = Vector3(0.0, 0.0, 0.10)
	circle.rotation_degrees.x = 90.0
	circle.material_override = _material(color, 0.94)
	root.add_child(circle)
	var slash := MeshInstance3D.new()
	var slash_mesh := BoxMesh.new()
	slash_mesh.size = Vector3(0.12, 0.95, 0.07)
	slash.mesh = slash_mesh
	slash.position = Vector3(0.0, 0.0, 0.14)
	slash.rotation_degrees.z = 28.0
	slash.material_override = _material(color, 0.94)
	root.add_child(slash)
	for index in range(3):
		var drip := MeshInstance3D.new()
		var drip_mesh := BoxMesh.new()
		drip_mesh.size = Vector3(0.06, 0.24 + float(index % 2) * 0.18, 0.05)
		drip.mesh = drip_mesh
		drip.position = Vector3(-0.5 + float(index) * 0.45, -0.30 - float(index % 2) * 0.10, 0.12)
		drip.material_override = _material(color, 0.98)
		root.add_child(drip)
	add_child(root)


func _create_debris_field(field_position: Vector3, count: int, radius: float) -> void:
	var root := Node3D.new()
	root.name = "LooseDebrisField"
	root.position = field_position
	var colors := [Color("#5b4942"), Color("#8c5535"), Color("#6d725f"), Color("#9a6b43")]
	for index in range(count):
		var piece := MeshInstance3D.new()
		var piece_mesh := BoxMesh.new()
		piece_mesh.size = Vector3(0.18 + float(index % 3) * 0.14, 0.10 + float(index % 2) * 0.11, 0.16 + float(index % 4) * 0.08)
		piece.mesh = piece_mesh
		var angle := float(index) * 2.11
		var distance := radius * (0.25 + float((index * 3) % 7) / 7.0)
		piece.position = Vector3(cos(angle) * distance, 0.10 + float(index % 2) * 0.08, sin(angle) * distance)
		piece.rotation_degrees = Vector3(float(index) * 22.0, float(index) * 41.0, float(index) * 13.0)
		piece.material_override = _material(colors[index % colors.size()], 0.95)
		root.add_child(piece)
	add_child(root)


func _create_spectator_stands() -> void:
	_create_spectator_side("SpectatorsNorth", Vector3(0.0, 0.0, -29.0), 0.0, Color("#a43832"))
	_create_spectator_side("SpectatorsSouth", Vector3(0.0, 0.0, 29.0), 180.0, Color("#a43832"))
	_create_spectator_side("SpectatorsWest", Vector3(-29.0, 0.0, 0.0), 90.0, Color("#3e6670"))
	_create_spectator_side("SpectatorsEast", Vector3(29.0, 0.0, 0.0), -90.0, Color("#3e6670"))


func _create_spectator_side(node_name: String, side_position: Vector3, rotation_y: float, banner_color: Color) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = side_position
	root.rotation_degrees.y = rotation_y
	for tier in range(3):
		var stand := MeshInstance3D.new()
		var stand_mesh := BoxMesh.new()
		stand_mesh.size = Vector3(45.0, 0.75, 1.05)
		stand.mesh = stand_mesh
		stand.position = Vector3(0.0, 0.40 + float(tier) * 0.78, 0.42 + float(tier) * 0.85)
		stand.material_override = _material(Color("#332c30") if tier == 0 else Color("#47363a"), 0.98)
		root.add_child(stand)
	for index in range(8):
		var local_x := -19.0 + float(index) * 5.45
		var audience := Node3D.new()
		audience.position = Vector3(local_x, 1.25 + float(index % 2) * 0.72, 0.10 + float(index % 3) * 0.82)
		var body := MeshInstance3D.new()
		var body_mesh := CapsuleMesh.new()
		body_mesh.radius = 0.20
		body_mesh.height = 0.58
		body.mesh = body_mesh
		body.position.y = 0.35
		body.material_override = _material(Color("#241f24") if index % 2 == 0 else Color("#3d3540"), 1.0)
		audience.add_child(body)
		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.22
		head_mesh.height = 0.36
		head.mesh = head_mesh
		head.position.y = 0.83
		head.material_override = _material(Color("#8c6450"), 0.95)
		audience.add_child(head)
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.045
		eye_mesh.height = 0.07
		eye.mesh = eye_mesh
		eye.position = Vector3(0.10, 0.86, -0.18)
		eye.material_override = _material(banner_color, 0.3, banner_color)
		audience.add_child(eye)
		root.add_child(audience)
		var wave := create_tween().set_loops()
		wave.tween_property(audience, "rotation_degrees", Vector3(0.0, 0.0, 4.0 if index % 2 == 0 else -4.0), 0.9 + float(index % 3) * 0.15).set_trans(Tween.TRANS_SINE)
		wave.tween_property(audience, "rotation_degrees", Vector3.ZERO, 0.9 + float(index % 2) * 0.20).set_trans(Tween.TRANS_SINE)
	for flag_index in range(4):
		var flag := MeshInstance3D.new()
		var flag_mesh := BoxMesh.new()
		flag_mesh.size = Vector3(2.6, 1.0, 0.06)
		flag.mesh = flag_mesh
		flag.position = Vector3(-15.0 + float(flag_index) * 10.0, 2.65, 0.12)
		flag.material_override = _material(banner_color, 0.96)
		root.add_child(flag)
		var flag_tween := create_tween().set_loops()
		flag_tween.tween_property(flag, "rotation_degrees", Vector3(0.0, 0.0, 3.0), 1.2).set_trans(Tween.TRANS_SINE)
		flag_tween.tween_property(flag, "rotation_degrees", Vector3(0.0, 0.0, -3.0), 1.0).set_trans(Tween.TRANS_SINE)
	var spot := OmniLight3D.new()
	spot.position = Vector3(0.0, 3.2, -0.15)
	spot.light_color = banner_color
	spot.light_energy = 0.75
	spot.omni_range = 9.0
	spot.set_meta("base_energy", 0.75)
	_flicker_lights.append(spot)
	root.add_child(spot)
	add_child(root)


func _create_arena_scoreboard() -> void:
	var root := Node3D.new()
	root.name = "ArenaScoreboard"
	root.position = Vector3(0.0, 0.0, -28.1)
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(8.8, 3.1, 0.55)
	frame.mesh = frame_mesh
	frame.position.y = 2.8
	frame.material_override = _material(Color("#29252b"), 0.88)
	root.add_child(frame)
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(7.1, 1.75, 0.08)
	screen.mesh = screen_mesh
	screen.position = Vector3(0.0, 2.82, 0.32)
	screen.material_override = _material(Color("#2c8790"), 0.22, Color("#28dce5"))
	root.add_child(screen)
	for index in range(4):
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.30 + float(index % 2) * 0.22, 0.16, 0.09)
		bar.mesh = bar_mesh
		bar.position = Vector3(-2.6 + float(index) * 1.72, 2.85 + float(index % 2) * 0.35, 0.40)
		bar.material_override = _material(Color("#e2a34c") if index % 2 == 0 else Color("#e34e4c"), 0.28, Color("#ff6d4e"))
		root.add_child(bar)
	for side in [-1.0, 1.0]:
		var cable := MeshInstance3D.new()
		var cable_mesh := CylinderMesh.new()
		cable_mesh.top_radius = 0.04
		cable_mesh.bottom_radius = 0.04
		cable_mesh.height = 2.6
		cable.mesh = cable_mesh
		cable.position = Vector3(side * 4.0, 1.4, 0.0)
		cable.rotation_degrees.z = side * -8.0
		cable.material_override = _material(Color("#211d22"), 0.96)
		root.add_child(cable)
	add_child(root)


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
	_create_blood_stain(Vector3(-15.0, 0.0, 2.8), 1.2, 0.34)
	_create_blood_stain(Vector3(14.5, 0.0, -2.0), 0.9, 0.27)
	_create_blood_stain(Vector3(-2.8, 0.0, -13.0), 0.72, 0.22)
	_create_blood_stain(Vector3(4.5, 0.0, 14.2), 1.0, 0.29)
	_create_scorch_mark(Vector3(10.0, 0.0, 8.0), 1.5)
	_create_scorch_mark(Vector3(-10.0, 0.0, -5.0), 1.1)


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


func _create_ambient_dust() -> void:
	var dust := GPUParticles3D.new()
	dust.name = "ArenaDust"
	dust.amount = 72
	dust.lifetime = 8.0
	dust.preprocess = 4.0
	dust.visibility_aabb = AABB(Vector3(-28.0, 0.0, -28.0), Vector3(56.0, 8.0, 56.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.25, 0.18, -0.1)
	process_material.spread = 75.0
	process_material.initial_velocity_min = 0.03
	process_material.initial_velocity_max = 0.16
	process_material.gravity = Vector3(0.0, 0.02, 0.0)
	process_material.scale_min = 0.035
	process_material.scale_max = 0.09
	dust.process_material = process_material
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.18
	dust_mesh.height = 0.30
	dust_mesh.material = _create_dust_material()
	dust.draw_pass_1 = dust_mesh
	dust.position = Vector3(0.0, 0.45, 0.0)
	dust.emitting = true
	add_child(dust)


func _create_dust_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.35, 0.25, 0.16)
	return material


func _create_blood_stain(stain_position: Vector3, radius: float, alpha: float) -> void:
	var stain := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_transparent_material(Color("#431f29"), alpha)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var points: Array[Vector3] = []
	for index in range(11):
		var angle := TAU * float(index) / 10.0
		var irregular := radius * (0.55 + float((index * 7) % 5) * 0.10)
		points.append(Vector3(cos(angle) * irregular, 0.025, sin(angle) * irregular * 0.72))
	for index in range(1, points.size() - 1):
		mesh.surface_add_vertex(points[0])
		mesh.surface_add_vertex(points[index])
		mesh.surface_add_vertex(points[index + 1])
	mesh.surface_end()
	stain.mesh = mesh
	stain.position = stain_position
	stain.rotation_degrees.y = fmod(stain_position.x * 13.0 + stain_position.z * 4.0, 360.0)
	add_child(stain)


func _create_scorch_mark(mark_position: Vector3, radius: float) -> void:
	var scorch := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.2
	mesh.height = 0.025
	scorch.mesh = mesh
	scorch.position = mark_position + Vector3.UP * 0.03
	scorch.material_override = _create_transparent_material(Color("#292025"), 0.34)
	add_child(scorch)


func _create_transparent_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	return material


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
	# A restrained squash/stretch loop gives the braziers a living silhouette
	# without adding physics or noisy screen-space effects during combat.
	var flame_tween := create_tween().set_loops()
	flame_tween.tween_property(flame, "scale", Vector3(0.62, 1.52, 0.62), 0.32).set_trans(Tween.TRANS_SINE)
	flame_tween.tween_property(flame, "scale", Vector3(0.84, 1.08, 0.84), 0.44).set_trans(Tween.TRANS_SINE)
	var light := OmniLight3D.new()
	light.position.y = 1.1
	light.light_color = Color("#ff9d4c")
	light.light_energy = 1.3
	light.omni_range = 5.0
	light.set_meta("base_energy", 1.3)
	_flicker_lights.append(light)
	root.add_child(light)
	var smoke := GPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 2.6
	smoke.preprocess = 1.3
	smoke.visibility_aabb = AABB(Vector3(-2.0, 0.0, -2.0), Vector3(4.0, 5.0, 4.0))
	var smoke_process := ParticleProcessMaterial.new()
	smoke_process.direction = Vector3.UP
	smoke_process.spread = 18.0
	smoke_process.initial_velocity_min = 0.35
	smoke_process.initial_velocity_max = 0.8
	smoke_process.gravity = Vector3(0.0, 0.4, 0.0)
	smoke_process.scale_min = 0.16
	smoke_process.scale_max = 0.28
	smoke.process_material = smoke_process
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.20
	smoke_mesh.height = 0.35
	smoke_mesh.material = _create_smoke_material()
	smoke.draw_pass_1 = smoke_mesh
	smoke.position.y = 0.85
	smoke.emitting = true
	root.add_child(smoke)
	add_child(root)


func _create_smoke_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.24, 0.22, 0.20, 0.22)
	return material


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
		_create_scrap_barrier("NorthPanel%d" % index, Vector3(offset, 1.05, -25.1), Vector3(6.6, 2.1 + float(index % 2) * 0.35, 0.86))
		_create_scrap_barrier("SouthPanel%d" % index, Vector3(-offset, 1.05, 25.1), Vector3(6.6, 2.1 + float((index + 1) % 2) * 0.35, 0.86))
		_create_scrap_barrier("WestPanel%d" % index, Vector3(-25.1, 1.05, -offset), Vector3(0.86, 2.1 + float(index % 2) * 0.35, 6.6))
		_create_scrap_barrier("EastPanel%d" % index, Vector3(25.1, 1.05, offset), Vector3(0.86, 2.1 + float((index + 1) % 2) * 0.35, 6.6))
	for banner_data in [
		[Vector3(-15.0, 2.0, -24.45), 0.0], [Vector3(15.0, 2.0, -24.45), 0.0],
		[Vector3(-15.0, 2.0, 24.45), 0.0], [Vector3(15.0, 2.0, 24.45), 0.0],
		[Vector3(-24.45, 2.0, -15.0), 90.0], [Vector3(-24.45, 2.0, 15.0), 90.0],
		[Vector3(24.45, 2.0, -15.0), 90.0], [Vector3(24.45, 2.0, 15.0), 90.0],
	]:
		_create_banner(banner_data[0], banner_data[1])
	_create_perimeter_tower("TowerNorthWest", Vector3(-23.4, 0.0, -23.4), 0.0)
	_create_perimeter_tower("TowerNorthEast", Vector3(23.4, 0.0, -23.4), 90.0)
	_create_perimeter_tower("TowerSouthWest", Vector3(-23.4, 0.0, 23.4), -90.0)
	_create_perimeter_tower("TowerSouthEast", Vector3(23.4, 0.0, 23.4), 180.0)


func _create_scrap_barrier(node_name: String, barrier_position: Vector3, size: Vector3, rotation_y: float = 0.0) -> StaticBody3D:
	var body := _create_box(node_name, barrier_position, size, Color.WHITE, METAL_RUST_TEXTURE)
	body.rotation_degrees.y = rotation_y
	# The collision body is intentionally kept as one simple shape, but its
	# visible counterpart is assembled from offset scrap modules below.
	var collision_visual := body.get_child(0) as MeshInstance3D
	if collision_visual != null:
		collision_visual.visible = false
	_create_barrier_segments(body, size)
	var pale_panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(maxf(0.18, size.x * 0.70), maxf(0.25, size.y * 0.42), maxf(0.18, size.z * 0.70))
	pale_panel.mesh = panel_mesh
	pale_panel.position.y = size.y * 0.16
	pale_panel.material_override = _textured_material(Color.WHITE, 0.94, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.5, 1.5, 1.5))
	body.add_child(pale_panel)
	_create_debris_face(body, size)
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
	cap.material_override = _textured_material(Color.WHITE, 0.82, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.2, 1.2, 1.2))
	body.add_child(cap)
	# Break the perfectly straight silhouette with loose scrap jutting above the
	# cover. These pieces are decorative; the single collision remains unchanged.
	var top_debris_colors := [Color("#6b4538"), Color("#9b5d35"), Color("#5c6558"), Color("#3f3737")]
	for index in range(5):
		var chunk := MeshInstance3D.new()
		var chunk_mesh := BoxMesh.new()
		var chunk_width := clampf(maxf(size.x, size.z) * (0.10 + float(index % 3) * 0.04), 0.20, 1.0)
		var chunk_height := 0.22 + float(index % 3) * 0.16
		if size.x >= size.z:
			chunk_mesh.size = Vector3(chunk_width, chunk_height, clampf(size.z * 0.70, 0.18, 0.65))
			chunk.position = Vector3(-size.x * 0.42 + float(index) * size.x * 0.21, size.y * 0.58 + chunk_height * 0.35, 0.0)
		else:
			chunk_mesh.size = Vector3(clampf(size.x * 0.70, 0.18, 0.65), chunk_height, chunk_width)
			chunk.position = Vector3(0.0, size.y * 0.58 + chunk_height * 0.35, -size.z * 0.42 + float(index) * size.z * 0.21)
		chunk.mesh = chunk_mesh
		chunk.rotation_degrees = Vector3(-4.0 + float(index) * 9.0, float(index) * 23.0, -11.0 + float(index % 2) * 19.0)
		chunk.material_override = _material(top_debris_colors[index % top_debris_colors.size()], 0.9)
		body.add_child(chunk)
	if int(node_name.length()) % 3 != 0:
		var torn_cloth := MeshInstance3D.new()
		var cloth_mesh := BoxMesh.new()
		cloth_mesh.size = Vector3(0.44, 1.15, 0.05)
		torn_cloth.mesh = cloth_mesh
		torn_cloth.position = Vector3(-size.x * 0.23, -0.20, size.z * 0.54)
		torn_cloth.rotation_degrees.z = -8.0
		torn_cloth.material_override = _material(Color("#762d2e"), 0.97)
		body.add_child(torn_cloth)
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
	var facing_z := size.z * 0.5 + 0.035
	for index in range(3):
		var plate := MeshInstance3D.new()
		var plate_mesh := BoxMesh.new()
		var plate_width := clampf(size.x * (0.24 + float(index % 2) * 0.08), 0.30, 2.4)
		var plate_height := clampf(size.y * (0.26 + float(index % 2) * 0.12), 0.25, 0.85)
		plate_mesh.size = Vector3(plate_width, plate_height, 0.07)
		plate.mesh = plate_mesh
		plate.position = Vector3(-size.x * 0.30 + float(index) * size.x * 0.30, size.y * (-0.14 + float(index % 2) * 0.28), facing_z)
		plate.rotation_degrees.z = -8.0 + float(index) * 11.0
		plate.material_override = _material(Color("#b06b42") if index % 2 == 0 else Color("#69715c"), 0.9)
		body.add_child(plate)
	var brace := MeshInstance3D.new()
	var brace_mesh := BoxMesh.new()
	brace_mesh.size = Vector3(clampf(size.x * 0.8, 0.65, 3.8), 0.09, 0.09)
	brace.mesh = brace_mesh
	brace.position = Vector3(0.0, 0.18, facing_z + 0.06)
	brace.rotation_degrees.z = -17.0 if size.x >= size.z else 17.0
	brace.material_override = _material(Color("#403531"), 0.78)
	body.add_child(brace)
	var pipe := MeshInstance3D.new()
	var pipe_mesh := CylinderMesh.new()
	pipe_mesh.top_radius = 0.07
	pipe_mesh.bottom_radius = 0.10
	pipe_mesh.height = size.y + 0.6
	pipe.mesh = pipe_mesh
	pipe.position = Vector3(size.x * 0.42, 0.0, facing_z + 0.08)
	pipe.material_override = _material(Color("#50382f"), 0.86)
	body.add_child(pipe)
	_create_barrier_cable(body, size, facing_z)
	_create_barrier_rubble(body, size)
	return body


func _create_barrier_segments(parent: Node3D, size: Vector3) -> void:
	var colors := [Color("#9d5c3b"), Color("#c5a47d"), Color("#5e514a"), Color("#7e4433")]
	for index in range(3):
		var segment := MeshInstance3D.new()
		var segment_mesh := BoxMesh.new()
		var segment_length := maxf(0.30, maxf(size.x, size.z) * (0.28 + float(index % 2) * 0.05))
		var segment_height := maxf(0.42, size.y * (0.45 + float(index % 2) * 0.14))
		if size.x >= size.z:
			segment_mesh.size = Vector3(segment_length, segment_height, maxf(0.22, size.z * 0.72))
			segment.position = Vector3(-size.x * 0.35 + float(index) * size.x * 0.34, -size.y * 0.04 + float(index % 2) * 0.08, 0.0)
		else:
			segment_mesh.size = Vector3(maxf(0.22, size.x * 0.72), segment_height, segment_length)
			segment.position = Vector3(0.0, -size.y * 0.04 + float(index % 2) * 0.08, -size.z * 0.35 + float(index) * size.z * 0.34)
		segment.mesh = segment_mesh
		segment.rotation_degrees = Vector3(0.0, float(index) * 7.0, -4.0 + float(index) * 8.0)
		segment.material_override = _textured_material(Color.WHITE if index == 1 else Color(colors[index]), 0.90, Color.BLACK, METAL_CREAM_TEXTURE if index == 1 else METAL_RUST_TEXTURE, Vector3(0.9, 0.9, 0.9))
		parent.add_child(segment)


func _create_barrier_cable(parent: Node3D, size: Vector3, facing_z: float) -> void:
	var cable := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _material(Color("#292b29"), 1.0)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var cable_width := clampf(size.x * 0.75, 0.6, 4.0)
	for index in range(9):
		var t := float(index) / 8.0
		var x := lerpf(-cable_width * 0.5, cable_width * 0.5, t)
		var sag := -0.10 - sin(t * PI) * 0.18
		mesh.surface_add_vertex(Vector3(x, size.y * 0.48 + sag, facing_z + 0.12))
	mesh.surface_end()
	cable.mesh = mesh
	parent.add_child(cable)


func _create_debris_face(parent: Node3D, size: Vector3) -> void:
	var debris_colors := [Color("#67453a"), Color("#8c4b31"), Color("#5b6257"), Color("#a06c44"), Color("#3f3837")]
	for index in range(7):
		var plate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var width := clampf(size.x * (0.18 + float(index % 3) * 0.08), 0.25, 1.8)
		var height := clampf(size.y * (0.17 + float(index % 2) * 0.13), 0.20, 0.70)
		mesh.size = Vector3(width, height, 0.10)
		plate.mesh = mesh
		plate.position = Vector3(-size.x * 0.40 + float(index % 4) * size.x * 0.26, -size.y * 0.16 + float(index % 3) * size.y * 0.23, size.z * 0.51 + 0.07)
		plate.rotation_degrees = Vector3(0.0, float(index) * 9.0, -14.0 + float(index % 4) * 8.0)
		plate.material_override = _material(debris_colors[index % debris_colors.size()], 0.88)
		parent.add_child(plate)
		if index % 2 == 0:
			var bolt := MeshInstance3D.new()
			var bolt_mesh := SphereMesh.new()
			bolt_mesh.radius = 0.08
			bolt_mesh.height = 0.11
			bolt.mesh = bolt_mesh
			bolt.position = plate.position + Vector3(width * 0.28, height * 0.25, 0.09)
			bolt.scale = Vector3(1.0, 0.5, 1.0)
			bolt.material_override = _material(Color("#d3a15d"), 0.55, Color("#8a4f2e"))
			parent.add_child(bolt)


func _create_barrier_rubble(parent: Node3D, size: Vector3) -> void:
	for index in range(4):
		var rubble := MeshInstance3D.new()
		var rubble_mesh := BoxMesh.new()
		rubble_mesh.size = Vector3(0.16 + float(index % 2) * 0.14, 0.12 + float(index % 3) * 0.06, 0.18 + float(index % 2) * 0.12)
		rubble.mesh = rubble_mesh
		var x := -size.x * 0.42 + float(index) * size.x * 0.28
		var z := size.z * 0.56 if index % 2 == 0 else -size.z * 0.56
		rubble.position = Vector3(x, 0.10 + float(index % 2) * 0.08, z)
		rubble.rotation_degrees = Vector3(float(index) * 17.0, float(index) * 33.0, float(index) * 11.0)
		rubble.material_override = _material(Color("#655047") if index % 2 == 0 else Color("#9b683d"), 0.96)
		parent.add_child(rubble)


func _create_pipe_clutter(node_name: String, clutter_position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = clutter_position
	root.rotation_degrees.y = rotation_y
	for index in range(4):
		var pipe := MeshInstance3D.new()
		var pipe_mesh := CylinderMesh.new()
		pipe_mesh.top_radius = 0.12 + float(index % 2) * 0.04
		pipe_mesh.bottom_radius = 0.15 + float(index % 2) * 0.05
		pipe_mesh.height = 2.8 + float(index % 3) * 0.7
		pipe.mesh = pipe_mesh
		pipe.position = Vector3(-0.7 + float(index % 2) * 1.0, pipe_mesh.height * 0.5, -0.7 + float(index / 2) * 0.85)
		pipe.rotation_degrees = Vector3(-10.0 + float(index) * 9.0, float(index) * 24.0, 6.0 - float(index) * 3.0)
		pipe.material_override = _material(Color("#5e493d") if index % 2 == 0 else Color("#8d4d30"), 0.86)
		root.add_child(pipe)
		for ring_height in [0.55, 1.55]:
			var ring := MeshInstance3D.new()
			var ring_mesh := TorusMesh.new()
			ring_mesh.inner_radius = pipe_mesh.bottom_radius * 0.92
			ring_mesh.outer_radius = pipe_mesh.bottom_radius * 1.16
			ring_mesh.rings = 7
			ring_mesh.ring_segments = 10
			ring.mesh = ring_mesh
			ring.position = pipe.position + Vector3.UP * (ring_height - pipe_mesh.height * 0.5)
			ring.material_override = _material(Color("#bd7740"), 0.75)
			root.add_child(ring)
	add_child(root)


func _create_perimeter_tower(node_name: String, tower_position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = tower_position
	root.rotation_degrees.y = rotation_y
	for x_offset in [-0.85, 0.85]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.26, 4.2, 0.26)
		post.mesh = post_mesh
		post.position = Vector3(x_offset, 2.1, 0.0)
		post.material_override = _material(Color("#4b3830"), 0.86)
		root.add_child(post)
	for y_offset in [1.3, 3.2]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(2.1, 0.20, 0.22)
		beam.mesh = beam_mesh
		beam.position.y = y_offset
		beam.material_override = _material(Color("#815039"), 0.88)
		root.add_child(beam)
	var top_light := OmniLight3D.new()
	top_light.position = Vector3(0.0, 3.55, 0.0)
	top_light.light_color = Color("#ff9c4b")
	top_light.light_energy = 0.7
	top_light.omni_range = 3.5
	root.add_child(top_light)
	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(1.25, 0.72, 0.06)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.18, 2.8, 0.0)
	flag.material_override = _material(Color("#9c2e27"), 0.94)
	root.add_child(flag)
	add_child(root)


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
	base.material_override = _textured_material(Color.WHITE, 0.75, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.0, 1.0, 1.0))
	root.add_child(base)
	for corner_position in [Vector3(-1.42, 0.22, -1.42), Vector3(1.42, 0.22, -1.42), Vector3(-1.42, 0.22, 1.42), Vector3(1.42, 0.22, 1.42)]:
		var bolt := MeshInstance3D.new()
		var bolt_mesh := CylinderMesh.new()
		bolt_mesh.top_radius = 0.15
		bolt_mesh.bottom_radius = 0.18
		bolt_mesh.height = 0.22
		bolt.mesh = bolt_mesh
		bolt.position = corner_position
		bolt.material_override = _material(Color("#bc7841"), 0.62, Color("#6e3d29"))
		root.add_child(bolt)
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
	# These are tall-grass gameplay landmarks, not round bushes: dense blades
	# create the readable League-like silhouette while staying fully non-colliding.
	root.scale = Vector3.ONE * bush_scale * 1.35
	root.add_to_group("bush_placeholder")
	var colors := [Color("#3d4e2f"), Color("#53613b"), Color("#73703d"), Color("#9a7539")]
	var blade_meshes: Array[Mesh] = []
	for color in colors:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.012
		mesh.bottom_radius = 0.075
		mesh.height = 1.0
		mesh.radial_segments = 5
		mesh.material = _material(color, 1.0)
		blade_meshes.append(mesh)
	for index in range(18):
		var blade := MeshInstance3D.new()
		blade.mesh = blade_meshes[index % blade_meshes.size()]
		var angle := TAU * float(index) / 18.0
		var radius := 0.18 + float(index % 5) * 0.16
		var blade_height := 0.85 + float(index % 4) * 0.28
		blade.position = Vector3(cos(angle) * radius, blade_height * 0.5, sin(angle) * radius)
		blade.scale = Vector3(0.72 + float(index % 3) * 0.18, blade_height, 0.72 + float(index % 2) * 0.20)
		blade.rotation_degrees = Vector3(float(index % 4) * 8.0, rad_to_deg(angle), -22.0 + float(index % 5) * 11.0)
		root.add_child(blade)
	# A dark, broken base makes the grass read as one dense clump from the camera.
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.48
	base_mesh.bottom_radius = 0.70
	base_mesh.height = 0.12
	base.mesh = base_mesh
	base.material_override = _material(Color("#4a3b2d"), 1.0)
	base.position.y = 0.06
	root.add_child(base)
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
	banner.material_override = _textured_material(Color.WHITE, 0.92, Color.BLACK, BANNER_TEXTURE, Vector3(1.0, 1.0, 1.0))
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
	var sway := create_tween().set_loops()
	sway.tween_property(banner, "rotation_degrees", Vector3(0.0, 0.0, 3.0), 0.9).set_trans(Tween.TRANS_SINE)
	sway.tween_property(banner, "rotation_degrees", Vector3(0.0, 0.0, -3.0), 1.1).set_trans(Tween.TRANS_SINE)


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
	help.text = "ZQSD / WASD / flèches : déplacement\nSouris : orienter l'attaque   •   Espace : auto-attaque\nA : offensif   •   E : défensif   •   R : mobilité   •   G : changer d'arme\nT : recharger le Shotgun   •   F1–F6 : diagnostic du mannequin uniquement\nCombo en 3 coups : estoc → slash → onde de choc. Les obstacles bloquent le mouvement.\nLab mannequin : F1 BURN • F2 SLOW • F3 STUN • F4 SPOTTED • F5 RESET • F6 HITBOX"
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(help)

	var status := Label.new()
	status.name = "Status"
	status.position = Vector2(24.0, 650.0)
	status.text = "ARÈNE DE FER — mannequin : PV, dégâts, reset et quatre effets testables."
	status.add_theme_font_size_override("font_size", 17)
	status.add_theme_color_override("font_color", Color("#7de8ff"))
	layer.add_child(status)


func _create_box(node_name: String, box_position: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box_position
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _textured_material(color, 0.85, Color.BLACK, texture, Vector3(1.2, 1.2, 1.2))
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


func _textured_material(color: Color, roughness: float, emission: Color, texture: Texture2D, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var material := _material(color, roughness, emission)
	if texture != null:
		material.albedo_texture = texture
		material.uv1_scale = uv_scale
		if texture == STEEL_DARK_TEXTURE:
			material.metallic = 0.42
		elif texture == METAL_RUST_TEXTURE:
			material.metallic = 0.18
		else:
			material.metallic = 0.04
	return material
