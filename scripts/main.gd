extends Node3D

const BOT_BUILDS := preload("res://scripts/duel_bot_builds.gd")
const ARENA_HAZARDS := preload("res://scripts/arena_hazards.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera_rig.gd")
const TARGET_SCRIPT := preload("res://scripts/target_dummy.gd")
const TOUCH_CONTROLS_SCRIPT := preload("res://scripts/touch_controls.gd")
const GAME_FLOW_SCRIPT := preload("res://scripts/game_flow.gd")
const NETWORK_MATCH_SCRIPT := preload("res://scripts/network_match.gd")
const VFX_MANAGER_SCRIPT := preload("res://scripts/vfx_manager.gd")
const BOT_BUILD_PRESETS := preload("res://scripts/bot_build_presets.gd")
const BUSH_VISUAL_SCRIPT := preload("res://scripts/bush_visual.gd")
const SIGHT_TRACKER_SCRIPT := preload("res://scripts/sight_tracker.gd")
const FOG_OF_WAR_SCRIPT := preload("res://scripts/fog_of_war.gd")
const REPAIR_KIT_SCENE := preload("res://scenes/repair_kit.tscn")
const SAND_TEXTURE: Texture2D = preload("res://art/sand_dust.svg")
const ARENA_FLOOR_TEXTURE: Texture2D = preload("res://art/arena_floor.svg")
const METAL_CREAM_TEXTURE: Texture2D = preload("res://art/metal_cream.svg")
const METAL_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const STEEL_DARK_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const BANNER_TEXTURE: Texture2D = preload("res://art/banner_red.svg")
const COVER_SKIN_A: ArrayMesh = preload("res://art/environment/families/cover_skin_mesh.tres")
const COVER_SKIN_B: ArrayMesh = preload("res://art/environment/families/cover_skin_b_mesh.tres")
const COVER_CONTACT: Material = preload("res://art/environment/cover_contact.tres")
const ARENA_PRESENTATION: PackedScene = preload("res://scenes/environment/arena_presentation.tscn")
const REPAIR_SOCKET: PackedScene = preload("res://scenes/environment/repair_socket.tscn")
const ARENA_HALF_EXTENT := 29.0
const EXTERIOR_SIZE := 128.0
const BUSH_PLACEMENT_ATTEMPTS := 12

@export_enum("easy", "normal", "hard") var bot_difficulty := "normal"

var player: CharacterBody3D
var game_flow: CanvasLayer
var network_match: CanvasLayer
var target: StaticBody3D
var touch_controls: Control
var sight_tracker: CanvasLayer
var fog_of_war: Node3D
var duel_active := false
var arena_variant := "classic"
var _arena_hazards: Node3D
var _bot_build: Dictionary = {}
var _ambient_clock := 0.0
var _flicker_lights: Array[OmniLight3D] = []
var _fx_serial := 0
var _fx_budget_clock := 0.0
var _menu_showcase_active := false
var _menu_showcase_elapsed := 0.0
var _menu_showcase_clip := -1
var _material_cache: Dictionary = {}
var _textured_material_cache: Dictionary = {}
var _arena_blockers: Array[StaticBody3D] = []
var _arena_exterior: Node3D
var _bot_build_presets := BOT_BUILD_PRESETS.new()
var _bot_build_round_key := ""
var _bot_build_current: Dictionary = {}
const FX_MAX_PARTICLES := 24
const FX_MAX_BURSTS := 42
const FX_MAX_PROJECTILES := 14
const MENU_SHOWCASE_CLIP_SECONDS := 3.0


func _process(delta: float) -> void:
	if fog_of_war != null:
		var active_player: Node = game_flow.get("player") if game_flow != null else player
		var active_target: Node = game_flow.get("target") if game_flow != null else target
		var live_round := is_instance_valid(active_player) and bool(active_player.call("is_gameplay_enabled")) and not bool(active_player.call("is_real_dead"))
		var local_or_network := duel_active or is_instance_valid(network_match)
		fog_of_war.call("set_enabled", live_round and local_or_network and is_instance_valid(active_target) and not bool(active_target.call("is_real_dead")))
	_ambient_clock += delta
	_fx_budget_clock += delta
	_update_menu_showcase(delta)
	if _fx_budget_clock >= 0.25:
		_fx_budget_clock = 0.0
		_trim_fx_budget()
	for index in range(_flicker_lights.size()):
		var light := _flicker_lights[index]
		if not is_instance_valid(light):
			continue
		var base_energy := float(light.get_meta("base_energy", 1.0))
		var phase := float(index) * 1.71
		light.light_energy = base_energy + sin(_ambient_clock * (5.0 + float(index % 3)) + phase) * 0.14 + sin(_ambient_clock * 11.0 + phase) * 0.06


func register_fx_node(node: Node, category: String = "burst") -> void:
	if node == null or not is_instance_valid(node):
		return
	# Projectile nodes own combat callbacks and may only be cleared at round reset.
	if category == "projectile":
		node.add_to_group("prototype0_gameplay_projectiles")
		return
	_fx_serial += 1
	node.add_to_group("prototype0_fx_budget")
	node.set_meta("prototype0_fx_category", category)
	node.set_meta("prototype0_fx_serial", _fx_serial)


func _trim_fx_budget() -> void:
	var counts := {"particle": 0, "burst": 0, "projectile": 0}
	var nodes_by_category := {"particle": [], "burst": [], "projectile": []}
	for node in get_tree().get_nodes_in_group("prototype0_fx_budget"):
		if node == null or not is_instance_valid(node):
			continue
		var category := str(node.get_meta("prototype0_fx_category", "burst"))
		if not nodes_by_category.has(category):
			category = "burst"
		counts[category] = int(counts[category]) + 1
		nodes_by_category[category].append(node)
	var limits := {"particle": FX_MAX_PARTICLES, "burst": FX_MAX_BURSTS, "projectile": FX_MAX_PROJECTILES}
	for category in limits.keys():
		var excess := int(counts[category]) - int(limits[category])
		if excess <= 0:
			continue
		var candidates: Array = nodes_by_category[category]
		candidates.sort_custom(func(a: Node, b: Node) -> bool:
			return int(a.get_meta("prototype0_fx_serial", 0)) < int(b.get_meta("prototype0_fx_serial", 0))
		)
		for index in range(mini(excess, candidates.size())):
			var node: Node = candidates[index]
			if is_instance_valid(node):
				node.queue_free()


func _ready() -> void:
	set_meta("camera_shake_enabled", true)
	var vfx := VFX_MANAGER_SCRIPT.new()
	vfx.name = "VFXManager"
	add_child(vfx)
	_build_environment()
	_build_arena()
	_build_player()
	_build_camera()
	_build_target()
	_arena_hazards = ARENA_HAZARDS.new()
	_arena_hazards.name = "ArenaHazards"
	add_child(_arena_hazards)
	_arena_hazards.call("configure", player, target)
	_build_interface()
	add_child(ARENA_PRESENTATION.instantiate())
	fog_of_war = FOG_OF_WAR_SCRIPT.new()
	fog_of_war.name = "FogOfWar"
	add_child(fog_of_war)
	fog_of_war.call("configure", player, get_node("CameraRig/Camera3D"))
	fog_of_war.call("set_enabled", false)
	get_node("/root/NetworkSession").match_started.connect(_on_network_match_started)


func _on_network_match_started(host_id: int, guest_id: int) -> void:
	if _arena_hazards != null:
		_arena_hazards.call("set_enabled", false)
	if network_match != null and is_instance_valid(network_match):
		network_match.call("_cleanup_actors")
		network_match.queue_free()
	network_match = CanvasLayer.new()
	network_match.name = "NetworkMatch"
	network_match.set_script(NETWORK_MATCH_SCRIPT)
	add_child(network_match)
	network_match.call("configure", self, host_id, guest_id)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#171b1e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#aab4b7")
	environment.ambient_light_energy = 0.62
	# The Mobile renderer gets its depth from controlled key/fill contrast. A
	# global fog veil made the fighters and projectiles lose contrast on phones.
	environment.fog_enabled = false
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "ArenaKeyLight"
	sun.light_color = Color("#f2d7b5")
	sun.light_energy = 1.08
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "CoolFillLight"
	fill.light_color = Color("#91a9b6")
	fill.light_energy = 0.28
	fill.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)


func _build_arena() -> void:
	_build_arena_exterior()
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(60.0, 60.0)
	ground.mesh = ground_mesh
	ground.material_override = _textured_material(Color.WHITE, 0.94, Color.BLACK, ARENA_FLOOR_TEXTURE, Vector3(2.35, 2.35, 2.35))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# The authored sand atlas includes flush repairs, traffic and cover-foot dust.

	_build_scrap_perimeter()

	# Four mirrored repair points keep the established arena contract and make
	# every spawn side travel a comparable distance for healing.
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

	# Existing visibility volumes stay at their exact gameplay positions. Their
	# new sparse silhouette reads as flexible brush instead of solid cover.
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
	# All remaining non-colliding props are suspended from, or mounted directly
	# onto, the blocking perimeter. The former loose crates, vehicles and scrap
	# piles looked like traversable obstacles and have deliberately been removed.
	_create_hanging_lamp("LampNorth", Vector3(-8.0, 2.48, -27.58))
	_create_hanging_lamp("LampSouth", Vector3(8.0, 2.48, 27.58), 180.0)
	_create_hanging_lamp("LampWest", Vector3(-27.58, 2.48, 8.0), 90.0)
	_create_hanging_lamp("LampEast", Vector3(27.58, 2.48, -8.0), -90.0)
	_create_arena_scoreboard()
	_create_arena_identity_markers()


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
	# The mount and arm make the support unambiguous from the gameplay camera.
	# Local +Z always points from the perimeter wall toward the arena.
	var mount := MeshInstance3D.new()
	var mount_mesh := BoxMesh.new()
	mount_mesh.size = Vector3(0.42, 0.52, 0.14)
	mount.mesh = mount_mesh
	mount.material_override = _material(Color("#34383a"), 0.88)
	root.add_child(mount)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.055
	arm_mesh.bottom_radius = 0.075
	arm_mesh.height = 1.02
	arm.mesh = arm_mesh
	arm.position = Vector3(0.0, 0.12, 0.50)
	arm.rotation_degrees.x = 90.0
	arm.material_override = _material(Color("#4a3730"), 0.90)
	root.add_child(arm)
	var chain := MeshInstance3D.new()
	var chain_mesh := CylinderMesh.new()
	chain_mesh.top_radius = 0.035
	chain_mesh.bottom_radius = 0.035
	chain_mesh.height = 0.72
	chain.mesh = chain_mesh
	chain.position = Vector3(0.0, -0.30, 0.98)
	chain.material_override = _material(Color("#3e3230"), 0.9)
	root.add_child(chain)
	var lantern := MeshInstance3D.new()
	var lantern_mesh := CylinderMesh.new()
	lantern_mesh.top_radius = 0.18
	lantern_mesh.bottom_radius = 0.25
	lantern_mesh.height = 0.46
	lantern.mesh = lantern_mesh
	lantern.position = Vector3(0.0, -0.82, 0.98)
	lantern.material_override = _material(Color("#7c4a2e"), 0.72)
	root.add_child(lantern)
	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.13
	glow_mesh.height = 0.24
	glow.mesh = glow_mesh
	glow.position = lantern.position
	glow.material_override = _material(Color("#c88f4f"), 0.34, Color("#9f5b2d"))
	root.add_child(glow)
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


func _build_arena_exterior() -> void:
	_arena_exterior = Node3D.new()
	_arena_exterior.name = "ArenaExterior"
	_arena_exterior.add_to_group("arena_exterior")
	_arena_exterior.set_meta("replaceable_environment", true)
	add_child(_arena_exterior)

	var terrain := MeshInstance3D.new()
	terrain.name = "ExteriorDustTerrain"
	var terrain_mesh := PlaneMesh.new()
	terrain_mesh.size = Vector2(EXTERIOR_SIZE, EXTERIOR_SIZE)
	terrain.mesh = terrain_mesh
	terrain.position.y = -0.06
	terrain.material_override = _textured_material(Color("#7a6d63"), 1.0, Color.BLACK, SAND_TEXTURE, Vector3(7.0, 7.0, 7.0))
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.set_meta("exterior_ground_size", EXTERIOR_SIZE)
	_arena_exterior.add_child(terrain)

	# The former stands projected into the playable arena. They now step away
	# from the outside face of every wall and live in this replaceable branch.
	_create_spectator_stands(_arena_exterior)
	for tower_data in [
		["TowerNorthWest", Vector3(-30.0, 0.0, -30.0), 0.0],
		["TowerNorthEast", Vector3(30.0, 0.0, -30.0), 90.0],
		["TowerSouthWest", Vector3(-30.0, 0.0, 30.0), -90.0],
		["TowerSouthEast", Vector3(30.0, 0.0, 30.0), 180.0],
	]:
		_create_perimeter_tower(_arena_exterior, tower_data[0], tower_data[1], tower_data[2])

	var rock_clusters := [
		[Vector3(-38.0, 0.0, -34.0), 2.1, 12.0],
		[Vector3(39.0, 0.0, -31.0), 1.7, -18.0],
		[Vector3(-42.0, 0.0, 15.0), 1.8, 34.0],
		[Vector3(41.0, 0.0, 20.0), 2.2, -9.0],
		[Vector3(-13.0, 0.0, 43.0), 1.5, 22.0],
		[Vector3(17.0, 0.0, -44.0), 1.9, -27.0],
	]
	for cluster_data in rock_clusters:
		_create_exterior_rock_cluster(_arena_exterior, cluster_data[0], cluster_data[1], cluster_data[2])
	for scrap_data in [
		[Vector3(-35.0, 0.0, -6.0), 18.0],
		[Vector3(35.5, 0.0, 7.0), -21.0],
		[Vector3(-7.0, 0.0, -37.0), -8.0],
		[Vector3(10.0, 0.0, 38.0), 14.0],
	]:
		_create_exterior_scrap_cluster(_arena_exterior, scrap_data[0], scrap_data[1])
	for silhouette_data in [
		[Vector3(-48.0, 0.0, -18.0), 7.0, Color("#303638")],
		[Vector3(47.0, 0.0, -12.0), 5.5, Color("#493a35")],
		[Vector3(-34.0, 0.0, 47.0), 6.2, Color("#34393a")],
		[Vector3(36.0, 0.0, 45.0), 7.8, Color("#403733")],
	]:
		_create_exterior_industrial_silhouette(_arena_exterior, silhouette_data[0], silhouette_data[1], silhouette_data[2])


func _create_spectator_stands(parent: Node3D) -> void:
	_create_spectator_side(parent, "SpectatorsNorth", Vector3(0.0, 0.0, -30.5), 0.0, Color("#8d3732"))
	_create_spectator_side(parent, "SpectatorsSouth", Vector3(0.0, 0.0, 30.5), 180.0, Color("#8d3732"))
	_create_spectator_side(parent, "SpectatorsWest", Vector3(-30.5, 0.0, 0.0), 90.0, Color("#3b5a60"))
	_create_spectator_side(parent, "SpectatorsEast", Vector3(30.5, 0.0, 0.0), -90.0, Color("#3b5a60"))


func _create_spectator_side(parent: Node3D, node_name: String, side_position: Vector3, rotation_y: float, banner_color: Color) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = side_position
	root.rotation_degrees.y = rotation_y
	root.set_meta("decorative_exterior", true)
	for tier in range(3):
		var stand := MeshInstance3D.new()
		var stand_mesh := BoxMesh.new()
		stand_mesh.size = Vector3(43.0, 0.58, 1.10)
		stand.mesh = stand_mesh
		stand.position = Vector3(0.0, 0.30 + float(tier) * 0.62, -0.72 - float(tier) * 0.82)
		stand.material_override = _material(Color("#292e30") if tier == 0 else Color("#35383a"), 0.96)
		root.add_child(stand)
	# A few broad silhouettes provide scale beyond the wall without becoming a
	# screen of tiny animated pieces in the Mobile renderer.
	for index in range(4):
		var local_x := -15.0 + float(index) * 10.0
		var audience := Node3D.new()
		audience.position = Vector3(local_x, 1.08 + float(index % 2) * 0.48, -0.85 - float(index % 3) * 0.60)
		var body := MeshInstance3D.new()
		var body_mesh := CylinderMesh.new()
		body_mesh.top_radius = 0.18
		body_mesh.bottom_radius = 0.24
		body_mesh.height = 0.62
		body_mesh.radial_segments = 6
		body.mesh = body_mesh
		body.position.y = 0.31
		body.material_override = _material(Color("#24282a") if index % 2 == 0 else Color("#3a3738"), 1.0)
		audience.add_child(body)
		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.17
		head_mesh.height = 0.30
		head_mesh.radial_segments = 8
		head_mesh.rings = 4
		head.mesh = head_mesh
		head.position.y = 0.78
		head.material_override = _material(Color("#67544a"), 0.95)
		audience.add_child(head)
		root.add_child(audience)
	for flag_index in range(2):
		var flag := MeshInstance3D.new()
		var flag_mesh := BoxMesh.new()
		flag_mesh.size = Vector3(3.1, 0.82, 0.05)
		flag.mesh = flag_mesh
		flag.position = Vector3(-12.0 + float(flag_index) * 24.0, 2.18, -1.05)
		flag.material_override = _material(banner_color, 0.96)
		root.add_child(flag)
	parent.add_child(root)


func _create_exterior_rock_cluster(parent: Node3D, cluster_position: Vector3, cluster_scale: float, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = "ExteriorRockCluster"
	root.position = cluster_position
	root.rotation_degrees.y = rotation_y
	root.set_meta("decorative_exterior", true)
	var offsets := [Vector3(-1.1, 0.0, 0.2), Vector3(0.7, 0.0, -0.5), Vector3(1.45, 0.0, 0.8)]
	for index in range(offsets.size()):
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.72 + float(index) * 0.12
		mesh.height = 1.0 + float(index % 2) * 0.35
		mesh.radial_segments = 7
		mesh.rings = 4
		rock.mesh = mesh
		var rock_scale := Vector3(1.25 + float(index % 2) * 0.25, 0.62 + float(index) * 0.08, 0.9 + float((index + 1) % 2) * 0.20) * cluster_scale
		rock.scale = rock_scale
		rock.position = offsets[index] * cluster_scale
		rock.position.y = mesh.height * rock_scale.y * 0.46
		rock.rotation_degrees.y = float(index) * 47.0
		rock.material_override = _material(Color("#5e4b43") if index != 1 else Color("#6f5948"), 1.0)
		root.add_child(rock)
	parent.add_child(root)


func _create_exterior_scrap_cluster(parent: Node3D, cluster_position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = "ExteriorScrapCluster"
	root.position = cluster_position
	root.rotation_degrees.y = rotation_y
	root.set_meta("decorative_exterior", true)
	var pieces := [
		[Vector3(-1.35, 0.0, 0.15), Vector3(2.9, 0.34, 1.15), Vector3(7.0, 12.0, -5.0), Color("#5a4a43")],
		[Vector3(0.75, 0.0, -0.45), Vector3(2.25, 0.48, 1.45), Vector3(-8.0, -17.0, 9.0), Color("#81472f")],
		[Vector3(1.55, 0.0, 0.65), Vector3(1.55, 0.30, 2.20), Vector3(5.0, 28.0, 12.0), Color("#3f4545")],
	]
	for piece_data in pieces:
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = piece_data[1]
		piece.mesh = mesh
		piece.position = piece_data[0]
		piece.rotation_degrees = piece_data[2]
		piece.position.y = _grounded_box_center_y(piece, mesh.size) - 0.035
		piece.material_override = _material(piece_data[3], 0.96)
		root.add_child(piece)
	parent.add_child(root)


func _grounded_box_center_y(box: Node3D, size: Vector3) -> float:
	var half := size * 0.5
	return absf(box.basis.x.y) * half.x + absf(box.basis.y.y) * half.y + absf(box.basis.z.y) * half.z


func _create_exterior_industrial_silhouette(parent: Node3D, silhouette_position: Vector3, height: float, color: Color) -> void:
	var root := Node3D.new()
	root.name = "ExteriorIndustrialSilhouette"
	root.position = silhouette_position
	root.set_meta("decorative_exterior", true)
	var tank := MeshInstance3D.new()
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 1.15
	tank_mesh.bottom_radius = 1.45
	tank_mesh.height = height
	tank_mesh.radial_segments = 10
	tank.mesh = tank_mesh
	tank.position.y = height * 0.5
	tank.material_override = _material(color, 0.98)
	root.add_child(tank)
	var chimney := MeshInstance3D.new()
	var chimney_mesh := CylinderMesh.new()
	chimney_mesh.top_radius = 0.25
	chimney_mesh.bottom_radius = 0.38
	chimney_mesh.height = height * 0.72
	chimney_mesh.radial_segments = 8
	chimney.mesh = chimney_mesh
	chimney.position = Vector3(1.65, chimney_mesh.height * 0.5, 0.55)
	chimney.material_override = _material(Color("#272d2f"), 1.0)
	root.add_child(chimney)
	var accent := MeshInstance3D.new()
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = Vector3(2.5, 0.22, 0.12)
	accent.mesh = accent_mesh
	accent.position = Vector3(0.0, height * 0.64, -1.15)
	accent.material_override = _material(Color("#78352f"), 0.96)
	root.add_child(accent)
	parent.add_child(root)


func _create_arena_scoreboard() -> void:
	var root := Node3D.new()
	root.name = "ArenaScoreboard"
	root.position = Vector3(0.0, 0.0, -27.62)
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(8.8, 2.10, 0.30)
	frame.mesh = frame_mesh
	frame.position.y = 1.30
	frame.material_override = _textured_material(Color("#b7b3aa"), 0.86, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.4, 1.4, 1.4))
	root.add_child(frame)
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(7.35, 1.25, 0.06)
	screen.mesh = screen_mesh
	screen.position = Vector3(0.0, 1.32, 0.19)
	screen.material_override = _material(Color("#183236"), 0.36, Color("#0e4e53"))
	root.add_child(screen)
	var title := Label3D.new()
	title.name = "YardNumber"
	title.text = "YARD 07"
	title.font_size = 96
	title.pixel_size = 0.009
	title.modulate = Color("#d9c8a8")
	title.outline_modulate = Color("#111719")
	title.outline_size = 12
	title.position = Vector3(0.0, 1.37, 0.24)
	root.add_child(title)
	for side in [-1.0, 1.0]:
		var status := MeshInstance3D.new()
		var status_mesh := BoxMesh.new()
		status_mesh.size = Vector3(0.20, 0.72, 0.08)
		status.mesh = status_mesh
		status.position = Vector3(side * 3.28, 1.32, 0.25)
		status.material_override = _material(Color("#8d3f38") if side < 0.0 else Color("#496b70"), 0.62)
		root.add_child(status)
	add_child(root)


func _create_arena_identity_markers() -> void:
	_create_wall_identity_marker("WestBayMarker", Vector3(-27.62, 1.35, -5.6), 90.0, "WEST // 03", Color("#9a4438"))
	_create_wall_identity_marker("EastBayMarker", Vector3(27.62, 1.35, 6.4), -90.0, "EAST // 07", Color("#596c69"))


func _create_wall_identity_marker(node_name: String, marker_position: Vector3, rotation_y: float, marker_text: String, accent: Color) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = marker_position
	root.rotation_degrees.y = rotation_y
	var backing := MeshInstance3D.new()
	var backing_mesh := BoxMesh.new()
	backing_mesh.size = Vector3(5.8, 1.35, 0.10)
	backing.mesh = backing_mesh
	backing.material_override = _textured_material(Color("#d0c6b4"), 0.94, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.8, 1.0, 1.0))
	root.add_child(backing)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.42, 1.14, 0.05)
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(-2.35, 0.0, 0.08)
	stripe.rotation_degrees.z = -12.0
	stripe.material_override = _material(accent, 0.90)
	root.add_child(stripe)
	var label := Label3D.new()
	label.text = marker_text
	label.font_size = 72
	label.pixel_size = 0.008
	label.modulate = Color("#2a2d2d")
	label.outline_modulate = Color("#d3c5aa")
	label.outline_size = 5
	label.position = Vector3(0.35, 0.02, 0.09)
	root.add_child(label)
	add_child(root)


func _create_ground_details() -> void:
	var floor_art := Node3D.new()
	floor_art.name = "FloorArt"
	add_child(floor_art)
	# Broad repairs are placed outside the central reaction space. Their scale is
	# readable from the gameplay camera; no small loose props sit in movement lanes.
	var repairs := [
		[Vector2(-17.5, -14.5), Vector2(6.4, 4.2), 7.0, _textured_material(Color("#8a8780"), 0.88, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.2, 1.2, 1.2))],
		[Vector2(16.0, -13.5), Vector2(5.2, 3.6), -11.0, _textured_material(Color("#77736a"), 0.94, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.25, 1.25, 1.25))],
		[Vector2(-15.2, 14.8), Vector2(4.8, 3.4), -8.0, _textured_material(Color("#777067"), 0.96, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.15, 1.15, 1.15))],
		[Vector2(16.4, 15.2), Vector2(6.8, 3.5), 12.0, _textured_material(Color("#85817a"), 0.91, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.3, 1.3, 1.3))],
		[Vector2(-22.8, 1.2), Vector2(3.2, 7.8), 2.0, _textured_material(Color("#8a6c58"), 0.95, Color.BLACK, METAL_RUST_TEXTURE, Vector3(1.0, 1.0, 1.0))],
		[Vector2(22.6, -1.0), Vector2(3.0, 7.2), -3.0, _textured_material(Color("#7c7870"), 0.94, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.0, 1.0, 1.0))],
	]
	for repair in repairs:
		_create_floor_plate(floor_art, repair[0], repair[1], repair[2], repair[3], 0.018)
	# Irregular plate joins avoid an all-over grid and quietly organize the four
	# existing combat lanes without implying damage or bonus zones.
	var seams := [
		[Vector2(-8.8, -11.0), Vector2(0.10, 19.0), 0.0],
		[Vector2(9.6, 8.0), Vector2(0.10, 23.0), 0.0],
		[Vector2(-8.0, -14.0), Vector2(21.0, 0.10), 0.0],
		[Vector2(9.0, 14.0), Vector2(19.0, 0.10), 0.0],
		[Vector2(0.0, 1.4), Vector2(11.0, 0.08), -7.0],
	]
	for seam in seams:
		_create_floor_plate(floor_art, seam[0], seam[1], seam[2], _material(Color("#2f3435"), 1.0), 0.021)
	# Faded workshop paint provides orientation at a glance while remaining much
	# darker than projectiles, status effects and the four recovery pads.
	var markings := [
		[Vector2(0.0, -12.4), Vector2(7.6, 0.34), 0.0],
		[Vector2(0.0, 14.3), Vector2(7.0, 0.34), 0.0],
		[Vector2(-19.8, -3.8), Vector2(3.4, 0.28), 90.0],
		[Vector2(19.8, 4.0), Vector2(3.4, 0.28), 90.0],
	]
	for marking in markings:
		_create_floor_plate(floor_art, marking[0], marking[1], marking[2], _material(Color("#75433d"), 0.98), 0.024)


func _create_floor_plate(parent: Node3D, plate_position: Vector2, plate_size: Vector2, rotation_y: float, material: Material, height: float) -> void:
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(plate_size.x, height, plate_size.y)
	plate.mesh = mesh
	plate.position = Vector3(plate_position.x, height * 0.5 + 0.002, plate_position.y)
	plate.rotation_degrees.y = rotation_y
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plate)


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
	# Invisible continuous limits keep the original containment contract. Visible
	# panels sit on the same footprint and now read as one assembled industrial wall.
	_create_invisible_limit("NorthLimit", Vector3(0.0, 1.5, -29.0), Vector3(58.0, 3.0, 0.8))
	_create_invisible_limit("SouthLimit", Vector3(0.0, 1.5, 29.0), Vector3(58.0, 3.0, 0.8))
	_create_invisible_limit("WestLimit", Vector3(-29.0, 1.5, 0.0), Vector3(0.8, 3.0, 58.0))
	_create_invisible_limit("EastLimit", Vector3(29.0, 1.5, 0.0), Vector3(0.8, 3.0, 58.0))
	for index in range(7):
		var offset := -24.8 + float(index) * 8.27
		_create_scrap_barrier("NorthPanel%d" % index, Vector3(offset, 1.05, -28.1), Vector3(7.5, 2.1 + float(index % 2) * 0.35, 0.86))
		_create_scrap_barrier("SouthPanel%d" % index, Vector3(-offset, 1.05, 28.1), Vector3(7.5, 2.1 + float((index + 1) % 2) * 0.35, 0.86))
		_create_scrap_barrier("WestPanel%d" % index, Vector3(-28.1, 1.05, -offset), Vector3(0.86, 2.1 + float(index % 2) * 0.35, 7.5))
		_create_scrap_barrier("EastPanel%d" % index, Vector3(28.1, 1.05, offset), Vector3(0.86, 2.1 + float((index + 1) % 2) * 0.35, 7.5))


func _create_scrap_barrier(node_name: String, barrier_position: Vector3, size: Vector3, rotation_y: float = 0.0) -> StaticBody3D:
	# Physics and blocker metadata remain owned by the original factory.
	var body := _create_box(node_name, barrier_position, size, Color("#d7d2c8"), STEEL_DARK_TEXTURE)
	body.rotation_degrees.y = rotation_y
	body.set_meta("arena_art_family", "salvage_beveled_armor")
	var visual := body.get_node("CollisionMatchedVisual") as MeshInstance3D
	visual.mesh = COVER_SKIN_A if absi(node_name.hash()) % 2 == 0 else COVER_SKIN_B
	visual.material_override = null
	# Shared unit meshes have a long X axis. Orient them for the existing spines.
	if size.x >= size.z:
		visual.scale = size
	else:
		visual.scale = Vector3(size.z, size.y, size.x)
		visual.rotation.y = PI * 0.5
	_create_barrier_contact(body, size)
	if node_name == "NorthCenterCover":
		_create_cover_label(body, size, "NORTH // 07")
	elif node_name == "SouthCenterCover":
		_create_cover_label(body, size, "SOUTH // 03")
	return body


func _create_cover_label(parent: Node3D, size: Vector3, label_text: String) -> void:
	var label := Label3D.new()
	label.text = label_text
	label.font_size = 64
	label.pixel_size = 0.008
	label.modulate = Color("#d7c6a6")
	label.outline_modulate = Color("#242a2b")
	label.outline_size = 8
	label.position = Vector3(0.0, 0.02, size.z * 0.5 + 0.11)
	parent.add_child(label)


func _create_barrier_contact(parent: Node3D, size: Vector3) -> void:
	var contact := MeshInstance3D.new()
	contact.name = "SettledDustFootprint"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size.x + 1.1, size.z + 1.1)
	contact.mesh = mesh
	# Flat, feathered dust follows the original floor; no raised visual obstacle.
	contact.position.y = -parent.position.y + 0.008
	contact.material_override = COVER_CONTACT
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(contact)


func _perimeter_face_sign(node_name: String) -> float:
	if node_name.begins_with("North") or node_name.begins_with("West"):
		return 1.0
	return -1.0


func _barrier_panel_material(variant: int, panel_index: int) -> StandardMaterial3D:
	if variant == 0 and panel_index == 0:
		return _textured_material(Color("#c6bdab"), 0.93, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.25, 1.25, 1.25))
	if variant == 1 and panel_index % 2 == 0:
		return _textured_material(Color("#ad9682"), 0.94, Color.BLACK, METAL_RUST_TEXTURE, Vector3(1.10, 1.10, 1.10))
	if variant == 2 and panel_index == 1:
		return _textured_material(Color("#b9b3a7"), 0.91, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.35, 1.35, 1.35))
	return _textured_material(Color("#a6a39d"), 0.88, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.15, 1.15, 1.15))


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


func _create_perimeter_tower(parent: Node3D, node_name: String, tower_position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = tower_position
	root.rotation_degrees.y = rotation_y
	root.set_meta("decorative_exterior", true)
	for x_offset in [-0.85, 0.85]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.30, 2.75, 0.30)
		post.mesh = post_mesh
		post.position = Vector3(x_offset, 1.375, 0.0)
		post.material_override = _material(Color("#2c3234"), 0.84)
		root.add_child(post)
	for y_offset in [0.42, 1.42, 2.48]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(2.05, 0.18, 0.26)
		beam.mesh = beam_mesh
		beam.position.y = y_offset
		beam.material_override = _material(Color("#6f4434") if y_offset < 1.0 else Color("#3e4242"), 0.88)
		root.add_child(beam)
	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(1.25, 0.58, 0.07)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.0, 1.62, -0.16)
	flag.material_override = _material(Color("#874038"), 0.94)
	root.add_child(flag)
	parent.add_child(root)


func _create_invisible_limit(node_name: String, limit_position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = limit_position
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("arena_solid")
	body.set_meta("invisible_safety_limit", true)
	body.set_meta("blocks_navigation", true)
	body.set_meta("blocks_projectiles", true)
	body.set_meta("blocks_line_of_sight", true)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_arena_blockers.append(body)


func _create_health_pad(node_name: String, pad_position: Vector3) -> void:
	var repair_kit := REPAIR_KIT_SCENE.instantiate() as Area3D
	repair_kit.name = node_name
	repair_kit.add_child(REPAIR_SOCKET.instantiate())
	repair_kit.position = pad_position
	add_child(repair_kit)
	repair_kit.call("set_collection_active", false)


func _create_bush_cluster(node_name: String, bush_position: Vector3, bush_scale: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = bush_position
	# Preserve authored arena roots while the visible clump and hiding footprint
	# share one validated centre. Vegetation remains completely passable.
	root.scale = Vector3(bush_scale * 1.60, bush_scale * 1.12, bush_scale * 1.50)
	root.add_to_group("bush_placeholder")
	root.add_to_group("arena_passable_decor")
	root.set_meta("bush_radius", 1.28 * bush_scale)
	root.set_meta("bush_height", 2.35 * bush_scale)
	var base_radius := 0.70 * bush_scale
	var visual_world_position := _resolve_bush_visual_position(node_name, bush_position, base_radius)
	root.set_meta("bush_base_radius", base_radius)
	root.set_meta("bush_visual_position", visual_world_position)
	root.set_meta("bush_center", visual_world_position)
	var visual_root := BUSH_VISUAL_SCRIPT.new()
	visual_root.name = "GroundedVegetation"
	visual_root.position = Vector3(
		(visual_world_position.x - bush_position.x) / root.scale.x,
		0.012 / root.scale.y,
		(visual_world_position.z - bush_position.z) / root.scale.z
	)
	# Meshes use world metres, so a circular gameplay radius cannot become an
	# ellipse through the old decorative root scale.
	visual_root.scale = Vector3.ONE / root.scale
	visual_root.setup(1.28 * bush_scale, 2.35 * bush_scale, node_name.hash())
	root.add_child(visual_root)
	add_child(root)


func _resolve_bush_visual_position(node_name: String, preferred: Vector3, base_radius: float) -> Vector3:
	var manual_fallbacks := {
		"BushNorthCenter": Vector3(0.0, 0.0, -6.9),
		"BushSouthCenter": Vector3(0.0, 0.0, 8.9),
		"BushWestSpine": Vector3(-9.2, 0.0, 1.0),
		"BushEastSpine": Vector3(9.2, 0.0, 1.0),
		"BushNorthWestCover": Vector3(-14.8, 0.0, -6.3),
		"BushNorthEastCover": Vector3(15.0, 0.0, -5.0),
		"BushSouthWestCover": Vector3(-13.0, 0.0, 12.2),
		"BushSouthEastCover": Vector3(14.9, 0.0, 12.3),
		"BushWestPocket": Vector3(-16.3, 0.0, 4.9),
		"BushEastPocket": Vector3(16.3, 0.0, -4.9),
	}
	var candidates: Array[Vector3] = [preferred]
	if manual_fallbacks.has(node_name):
		candidates.append(manual_fallbacks[node_name])
	var phase := deg_to_rad(float(absi(node_name.hash()) % 360))
	while candidates.size() < BUSH_PLACEMENT_ATTEMPTS:
		var attempt := candidates.size() - 1
		var ring := 0.55 + float(attempt / 4) * 0.60
		var angle := phase + float(attempt % 4) * PI * 0.5
		candidates.append(preferred + Vector3(cos(angle) * ring, 0.0, sin(angle) * ring))
	for candidate in candidates:
		if _bush_base_is_clear(candidate, base_radius):
			return candidate
	push_warning("Bush placement fallback exhausted for %s; keeping its authored position" % node_name)
	return preferred


func _bush_base_is_clear(candidate: Vector3, base_radius: float) -> bool:
	if absf(candidate.x) > ARENA_HALF_EXTENT - 1.1 or absf(candidate.z) > ARENA_HALF_EXTENT - 1.1:
		return false
	for body in _arena_blockers:
		if body == null or not is_instance_valid(body):
			continue
		for child in body.get_children():
			if not child is CollisionShape3D:
				continue
			var collision := child as CollisionShape3D
			if not collision.shape is BoxShape3D:
				continue
			var shape := collision.shape as BoxShape3D
			var relative := Vector2(candidate.x - body.position.x, candidate.z - body.position.z)
			relative = relative.rotated(deg_to_rad(-body.rotation_degrees.y))
			if absf(relative.x) <= shape.size.x * 0.5 + base_radius + 0.08 and absf(relative.y) <= shape.size.z * 0.5 + base_radius + 0.08:
				return false
	var reserved_zones := [
		[Vector2(0.0, -20.8), Vector2(1.72, 1.72)],
		[Vector2(0.0, 20.8), Vector2(1.72, 1.72)],
		[Vector2(-21.0, 0.0), Vector2(1.72, 1.72)],
		[Vector2(21.0, 0.0), Vector2(1.72, 1.72)],
	]
	for zone in reserved_zones:
		var zone_position: Vector2 = zone[0]
		var zone_half_size: Vector2 = zone[1]
		var delta: Vector2 = Vector2(candidate.x, candidate.z) - zone_position
		if absf(delta.x) <= zone_half_size.x + base_radius and absf(delta.y) <= zone_half_size.y + base_radius:
			return false
	return true


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
	if DisplayServer.get_name() != "headless":
		player.call("set_gameplay_enabled", false)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)


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
	target = StaticBody3D.new()
	target.name = "TargetDummy"
	target.set_script(TARGET_SCRIPT)
	target.position = Vector3(3.5, 0.0, 15.5)
	add_child(target)
	# Match start is always clean. This is intentionally explicit even though
	# TargetDummy creates a fresh CombatState in _ready(): it protects the
	# gameplay scene from any editor/capture reuse and keeps diagnostic effects
	# (F1-F4) opt-in instead of leaking into a new round.
	target.call("reset_combat_state")
	target.call("set_duel_mode", false)
	if target.has_signal("died"):
		target.died.connect(_on_target_died)


func _build_interface() -> void:
	game_flow = CanvasLayer.new()
	# Keep the historical Interface path so existing tools and captures remain valid.
	game_flow.name = "Interface"
	game_flow.set_script(GAME_FLOW_SCRIPT)
	add_child(game_flow)
	touch_controls = Control.new()
	touch_controls.name = "TouchControls"
	touch_controls.set_script(TOUCH_CONTROLS_SCRIPT)
	touch_controls.call("set_player", player)
	game_flow.add_child(touch_controls)
	game_flow.call("configure", self, player, target, touch_controls)
	sight_tracker = SIGHT_TRACKER_SCRIPT.new()
	sight_tracker.name = "SightTracker"
	add_child(sight_tracker)
	sight_tracker.call("configure", self, player, target)


func set_menu_mode(menu_mode: bool) -> void:
	# Headless integration scripts exercise the combat actors directly without
	# navigating the visual menu. Keep their physics active for those tests.
	if DisplayServer.get_name() == "headless":
		return
	if menu_mode:
		if player != null and player.has_method("set_gameplay_enabled"):
			player.call("set_gameplay_enabled", false)
		if target != null:
			target.call("set_training_bot_enabled", false)


func set_menu_showcase_enabled(value: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _menu_showcase_active == value:
		return
	_menu_showcase_active = value
	_menu_showcase_elapsed = 0.0
	_menu_showcase_clip = -1
	if value:
		_set_menu_showcase_clip(0)
		return
	if player != null:
		player.call("clear_touch_inputs")
		player.call("set_gameplay_enabled", false)
	if target != null:
		target.call("set_training_bot_enabled", false)
		target.call("set_duel_mode", false)
	reset_round_camera()


func _update_menu_showcase(delta: float) -> void:
	if not _menu_showcase_active or player == null or target == null:
		return
	_menu_showcase_elapsed += delta
	var clip_index := int(floor(_menu_showcase_elapsed / MENU_SHOWCASE_CLIP_SECONDS)) % 3
	if clip_index != _menu_showcase_clip:
		_set_menu_showcase_clip(clip_index)
	var clip_time := fmod(_menu_showcase_elapsed, MENU_SHOWCASE_CLIP_SECONDS)
	var aim: Vector3 = target.global_position - player.global_position
	aim.y = 0.0
	if aim.length_squared() > 0.001:
		player.call("set_touch_aim_vector", Vector2(aim.x, aim.z).normalized())
	var firing := (clip_time >= 0.62 and clip_time < 1.22) or (clip_time >= 2.04 and clip_time < 2.43)
	player.call("set_touch_attack_held", firing)


func _set_menu_showcase_clip(clip_index: int) -> void:
	_menu_showcase_clip = clip_index
	var player_positions: Array[Vector3] = [
		Vector3(-2.4, 0.0, 3.5),
		Vector3(2.2, 0.0, 4.0),
		Vector3(-1.5, 0.0, 5.3),
	]
	var target_positions: Array[Vector3] = [
		Vector3(2.1, 0.0, 0.5),
		Vector3(-0.5, 0.0, 2.0),
		Vector3(1.5, 0.0, 4.0),
	]
	var camera_positions: Array[Vector3] = [
		Vector3(-4.5, 13.0, 11.0),
		Vector3(-5.2, 13.0, 11.0),
		Vector3(-4.0, 14.0, 12.0),
	]
	var camera_fovs: Array[float] = [34.0, 36.0, 36.0]
	clear_transient_fx()
	player.global_position = player_positions[clip_index]
	target.global_position = target_positions[clip_index]
	player.call("clear_touch_inputs")
	player.call("reset_combat_state")
	player.call("set_weapon", "shotgun" if clip_index == 1 else "blaster")
	player.call("set_gameplay_enabled", true)
	target.call("set_duel_mode", false)
	target.call("reset_combat_state")
	target.call("set_training_bot_spawn_position", target_positions[clip_index])
	target.call("set_training_bot_enabled", true)
	var player_world_ui := player.get_node_or_null("WorldUIAnchor") as Node3D
	if player_world_ui != null:
		player_world_ui.visible = false
	var target_readout := target.get_node_or_null("TargetHealthReadout")
	if target_readout != null:
		target_readout.visible = false
		target_readout.call("set_cinematic_mode", true)
	var rig := get_node_or_null("CameraRig")
	if rig != null:
		rig.call("reset_focus")
		rig.call("set_target", player)
		rig.call("set_follow_offset", Vector3(-5.5 if clip_index == 1 else -6.0, 0.0, -3.0), true)
		var camera := rig.get_node_or_null("Camera3D") as Camera3D
		if camera != null:
			camera.position = camera_positions[clip_index]
			camera.fov = camera_fovs[clip_index]


func start_duel(loadout: Dictionary) -> void:
	_bot_build_round_key = ""
	prepare_round(loadout)


func prepare_round(loadout: Dictionary) -> void:
	duel_active = true
	if _arena_hazards != null:
		_arena_hazards.call("set_enabled", arena_variant == "hazards" and not is_instance_valid(network_match))
	if player == null or target == null:
		return
	reset_round_camera()
	clear_transient_fx()
	player.position = Vector3(-3.5, 0.0, 17.0)
	target.position = Vector3(3.5, 0.0, 15.5)
	target.call("set_duel_mode", true)
	var round_key := "%d:%d" % [game_flow.match_id if game_flow != null else 0, maxi(1, game_flow.round_number if game_flow != null else 1)]
	# start_duel and its countdown both prepare the initial round. Draw once.
	if _bot_build_current.is_empty() or round_key != _bot_build_round_key:
		_bot_build_current = _bot_build_presets.next_preset()
		_bot_build_round_key = round_key
	target.set_meta("bot_build_preset", _bot_build_current.duplicate(true))
	target.set_meta("bot_build_id", str(_bot_build_current.id))
	target.set_meta("bot_build_name", str(_bot_build_current.name))
	target.set_meta("bot_personality", _bot_build_current.personality.duplicate(true))
	_bot_build = _bot_build_current.loadout.duplicate(true)
	_bot_build["title"] = str(_bot_build_current.name)
	target.call("set_duel_loadout", _bot_build)
	target.call("set_bot_difficulty", bot_difficulty)
	target.call("set_training_bot_enabled", false)
	target.call("reset_combat_state")
	player.call("apply_loadout", loadout)
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", false)
	player.call("clear_touch_inputs")
	_reset_repair_kits(false)


func get_bot_build() -> Dictionary:
	return {} if is_instance_valid(network_match) or (target != null and bool(target.get("network_proxy"))) else _bot_build.duplicate(true)


func set_bot_build_seed(value: int) -> void:
	_bot_build_presets.set_seed(value)
	_bot_build_round_key = ""
	_bot_build_current.clear()
	_bot_build.clear()


func get_current_bot_build() -> Dictionary:
	return _bot_build_current.duplicate(true)


func activate_round() -> void:
	if not duel_active or player == null or target == null:
		return
	player.call("set_gameplay_enabled", true)
	target.call("set_training_bot_enabled", true)
	_set_repair_kits_active(true)
	if _arena_hazards != null:
		_arena_hazards.call("start_round")


func restart_duel(loadout: Dictionary) -> void:
	start_duel(loadout)


func stop_duel() -> void:
	duel_active = false
	if _arena_hazards != null:
		_arena_hazards.call("stop_round")
	clear_transient_fx()
	_set_repair_kits_active(false)
	if player != null:
		player.call("set_gameplay_enabled", false)
		player.call("clear_touch_inputs")
	if target != null:
		target.call("set_training_bot_enabled", false)
		target.call("set_duel_mode", false)


func set_arena_variant(value: String) -> void:
	arena_variant = "hazards" if value == "hazards" else "classic"
	if _arena_hazards != null:
		_arena_hazards.call("set_enabled", arena_variant == "hazards" and not is_instance_valid(network_match))


func focus_round_winner(player_won: bool) -> void:
	var rig := get_node_or_null("CameraRig")
	var winner: Node3D = player if player_won else target
	if rig != null:
		rig.call("focus_on_winner", winner)
	var readout := winner.get_node_or_null("WorldUIAnchor/PlayerHealthReadout") if player_won else winner.get_node_or_null("TargetHealthReadout")
	if readout != null:
		readout.call("set_cinematic_mode", true)


func reset_round_camera() -> void:
	var rig := get_node_or_null("CameraRig")
	if rig != null and player != null:
		rig.call("set_target", player)
		rig.call("set_follow_offset", Vector3.ZERO, true)
	if player != null:
		var player_world_ui := player.get_node_or_null("WorldUIAnchor") as Node3D
		if player_world_ui != null:
			player_world_ui.visible = true
		var player_readout := player.get_node_or_null("WorldUIAnchor/PlayerHealthReadout")
		if player_readout != null:
			player_readout.call("set_cinematic_mode", false)
	if target != null:
		var target_readout := target.get_node_or_null("TargetHealthReadout")
		if target_readout != null:
			target_readout.visible = true
			target_readout.call("set_cinematic_mode", false)


func resolve_round() -> void:
	if game_flow == null or not duel_active:
		return
	var player_dead := bool(player.call("is_real_dead"))
	var target_dead := bool(target.call("is_real_dead"))
	if not player_dead and player.has_method("get_health"):
		player_dead = float(player.call("get_health")) <= 0.0
	if not target_dead:
		target_dead = float(target.call("get_health")) <= 0.0
	if player_dead or target_dead:
		_set_repair_kits_active(false)
		game_flow.call("resolve_round", player_dead, target_dead)


func _reset_repair_kits(collection_active: bool) -> void:
	for repair_kit in get_tree().get_nodes_in_group("repair_kits"):
		if repair_kit.has_method("reset_for_round"):
			repair_kit.call("reset_for_round", collection_active)


func _set_repair_kits_active(value: bool) -> void:
	for repair_kit in get_tree().get_nodes_in_group("repair_kits"):
		if repair_kit.has_method("set_collection_active"):
			repair_kit.call("set_collection_active", value)


func shift_pause_timers(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if player != null and player.has_method("shift_pause_timers"):
		player.call("shift_pause_timers", seconds)
	if target != null and target.has_method("shift_pause_timers"):
		target.call("shift_pause_timers", seconds)


func clear_transient_fx() -> void:
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	var vfx := get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("clear")
	for node in get_tree().get_nodes_in_group("prototype0_fx_budget"):
		if is_instance_valid(node):
			node.queue_free()
	for node in get_tree().get_nodes_in_group("prototype0_gameplay_projectiles"):
		if is_instance_valid(node):
			node.queue_free()


func _on_player_died() -> void:
	if game_flow != null:
		game_flow.call("on_actor_died", player)


func _on_target_died() -> void:
	if game_flow != null:
		game_flow.call("on_actor_died", target)


func _create_box(node_name: String, box_position: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box_position
	body.set_meta("vfx_surface", "environment" if texture == SAND_TEXTURE or "Wall" in node_name or "Ground" in node_name else "metal")
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("arena_solid")
	body.set_meta("blocks_navigation", true)
	body.set_meta("blocks_projectiles", true)
	body.set_meta("blocks_line_of_sight", true)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "CollisionMatchedVisual"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _textured_material(color, 0.85, Color.BLACK, texture, Vector3(1.2, 1.2, 1.2))
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_arena_blockers.append(body)
	return body


func _material(color: Color, roughness: float = 0.8, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var key := "%s|%.3f|%s" % [color.to_html(), roughness, emission.to_html()]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.35
	_material_cache[key] = material
	return material


func _textured_material(color: Color, roughness: float, emission: Color, texture: Texture2D, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var texture_path := texture.resource_path if texture != null else ""
	var key := "%s|%.3f|%s|%s|%.3f,%.3f,%.3f" % [color.to_html(), roughness, emission.to_html(), texture_path, uv_scale.x, uv_scale.y, uv_scale.z]
	if _textured_material_cache.has(key):
		return _textured_material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.35
	if texture != null:
		material.albedo_texture = texture
		material.uv1_scale = uv_scale
		if texture == STEEL_DARK_TEXTURE:
			material.metallic = 0.42
		elif texture == METAL_RUST_TEXTURE:
			material.metallic = 0.18
		else:
			material.metallic = 0.04
	_textured_material_cache[key] = material
	return material
