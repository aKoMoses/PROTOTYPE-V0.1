extends RefCounted
## Reusable courtyard objects. Parent, collider registry and lamp registry are explicit.
## Construction adds no controller node, keeping the original scene paths intact.
const MATERIALS = preload("res://scripts/environment/arena_material_library.gd")
const BUSH_VISUAL_SCRIPT := preload("res://scripts/bush_visual.gd")
const REPAIR_KIT_SCENE := preload("res://scenes/repair_kit.tscn")
const SAND_TEXTURE: Texture2D = preload("res://art/sand_dust.svg")
const METAL_CREAM_TEXTURE: Texture2D = preload("res://art/metal_cream.svg")
const METAL_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const STEEL_DARK_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const BANNER_TEXTURE: Texture2D = preload("res://art/banner_red.svg")
const COVER_SKIN_A: ArrayMesh = preload("res://art/environment/families/cover_skin_mesh.tres")
const COVER_SKIN_B: ArrayMesh = preload("res://art/environment/families/cover_skin_b_mesh.tres")
const COVER_CONTACT: Material = preload("res://art/environment/cover_contact.tres")
const REPAIR_SOCKET: PackedScene = preload("res://scenes/environment/repair_socket.tscn")

var _parent: Node3D
var materials := MATERIALS.new()
var blockers: Array[StaticBody3D]
var flicker_lights: Array[OmniLight3D]

func _init(parent: Node3D, blocker_registry: Array[StaticBody3D] = [], lamp_registry: Array[OmniLight3D] = []) -> void:
	_parent = parent
	blockers = blocker_registry
	flicker_lights = lamp_registry

func create_wrecked_vehicle(node_name: String, vehicle_position: Vector3, rotation_y: float, with_crates: bool) -> void:
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
	body.material_override = materials.textured(Color.WHITE, 0.88, Color.BLACK, METAL_RUST_TEXTURE, Vector3(1.2, 1.2, 1.2))
	root.add_child(body)
	var hood := MeshInstance3D.new()
	var hood_mesh := BoxMesh.new()
	hood_mesh.size = Vector3(1.35, 0.46, 2.25)
	hood.mesh = hood_mesh
	hood.position = Vector3(-1.48, 1.46, 0.0)
	hood.rotation_degrees.z = -4.0
	hood.material_override = materials.textured(Color.WHITE, 0.84, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.3, 1.3, 1.3))
	root.add_child(hood)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.95, 1.12, 2.28)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.65, 1.55, 0.0)
	cabin.rotation_degrees.z = 4.0
	cabin.material_override = materials.textured(Color.WHITE, 0.88, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.0, 1.0, 1.0))
	root.add_child(cabin)
	for side in [-1.0, 1.0]:
		var window := MeshInstance3D.new()
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3(1.1, 0.48, 0.05)
		window.mesh = window_mesh
		window.position = Vector3(0.65, 1.65, side * 1.17)
		window.material_override = materials.material(Color("#24383a"), 0.28, Color("#172a2f"))
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
		wheel.material_override = materials.material(Color("#272625"), 1.0)
		root.add_child(wheel)
	for index in range(3):
		var brace := MeshInstance3D.new()
		var brace_mesh := BoxMesh.new()
		brace_mesh.size = Vector3(0.13, 0.12, 2.58)
		brace.mesh = brace_mesh
		brace.position = Vector3(-1.0 + float(index) * 1.15, 1.45, 0.0)
		brace.material_override = materials.material(Color("#c38345"), 0.7)
		root.add_child(brace)
	if with_crates:
		create_vehicle_crate(root, Vector3(0.8, 2.45, -0.55), 0.75)
		create_vehicle_crate(root, Vector3(1.1, 2.45, 0.58), 0.62)
	_parent.add_child(root)


func create_vehicle_crate(parent: Node3D, local_position: Vector3, crate_scale: float) -> void:
	var crate := MeshInstance3D.new()
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(1.05, 0.72, 0.88) * crate_scale
	crate.mesh = crate_mesh
	crate.position = local_position
	crate.rotation_degrees = Vector3(0.0, 18.0, -4.0)
	crate.material_override = materials.textured(Color.WHITE, 0.95, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.0, 1.0, 1.0))
	parent.add_child(crate)


func create_barrel_cluster(node_name: String, cluster_position: Vector3, count: int) -> void:
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
		barrel.material_override = materials.textured(Color.WHITE, 0.84, Color.BLACK, METAL_RUST_TEXTURE if index % 2 == 0 else STEEL_DARK_TEXTURE, Vector3(0.8, 0.8, 0.8))
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
			band.material_override = materials.material(Color("#c18445"), 0.7)
			root.add_child(band)
	_parent.add_child(root)


func create_crate_stack(node_name: String, stack_position: Vector3, count: int) -> void:
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
		crate.material_override = materials.textured(Color.WHITE, 0.94, Color.BLACK, STEEL_DARK_TEXTURE if index % 2 == 0 else METAL_RUST_TEXTURE, Vector3(1.0, 1.0, 1.0))
		root.add_child(crate)
		for axis in [-1.0, 1.0]:
			var strap := MeshInstance3D.new()
			var strap_mesh := BoxMesh.new()
			strap_mesh.size = Vector3(0.09, crate_mesh.size.y + 0.08, crate_mesh.size.z + 0.06) if absf(axis) > 0.0 else Vector3(0.09, 0.1, 0.1)
			strap.mesh = strap_mesh
			strap.position = crate.position + Vector3(axis * crate_mesh.size.x * 0.29, 0.0, 0.0)
			strap.material_override = materials.material(Color("#b57d46"), 0.78)
			root.add_child(strap)
	_parent.add_child(root)


func create_hanging_lamp(node_name: String, lamp_position: Vector3, rotation_y: float = 0.0) -> void:
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
	mount.material_override = materials.material(Color("#34383a"), 0.88)
	root.add_child(mount)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.055
	arm_mesh.bottom_radius = 0.075
	arm_mesh.height = 1.02
	arm.mesh = arm_mesh
	arm.position = Vector3(0.0, 0.12, 0.50)
	arm.rotation_degrees.x = 90.0
	arm.material_override = materials.material(Color("#4a3730"), 0.90)
	root.add_child(arm)
	var chain := MeshInstance3D.new()
	var chain_mesh := CylinderMesh.new()
	chain_mesh.top_radius = 0.035
	chain_mesh.bottom_radius = 0.035
	chain_mesh.height = 0.72
	chain.mesh = chain_mesh
	chain.position = Vector3(0.0, -0.30, 0.98)
	chain.material_override = materials.material(Color("#3e3230"), 0.9)
	root.add_child(chain)
	var lantern := MeshInstance3D.new()
	var lantern_mesh := CylinderMesh.new()
	lantern_mesh.top_radius = 0.18
	lantern_mesh.bottom_radius = 0.25
	lantern_mesh.height = 0.46
	lantern.mesh = lantern_mesh
	lantern.position = Vector3(0.0, -0.82, 0.98)
	lantern.material_override = materials.material(Color("#7c4a2e"), 0.72)
	root.add_child(lantern)
	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.13
	glow_mesh.height = 0.24
	glow.mesh = glow_mesh
	glow.position = lantern.position
	glow.material_override = materials.material(Color("#c88f4f"), 0.34, Color("#9f5b2d"))
	root.add_child(glow)
	_parent.add_child(root)


func create_dead_grass_line(line_position: Vector3, count: int, grass_scale: float) -> void:
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
		blade.material_override = materials.material(Color("#766b35") if index % 2 == 0 else Color("#96743b"), 1.0)
		root.add_child(blade)
	_parent.add_child(root)


func create_arena_skull(node_name: String, skull_position: Vector3, skull_scale: float) -> void:
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
	stake.material_override = materials.material(Color("#3b2e2b"), 0.94)
	root.add_child(stake)
	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.46
	skull_mesh.height = 0.72
	skull.mesh = skull_mesh
	skull.position.y = 1.25
	skull.scale = Vector3(1.0, 0.88, 0.76)
	skull.material_override = materials.material(Color("#c2ab85"), 0.92)
	root.add_child(skull)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.095
		eye_mesh.height = 0.14
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.18, 1.30, -0.36)
		eye.material_override = materials.material(Color("#e33c42"), 0.25, Color("#ff1f39"))
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
		horn.material_override = materials.material(Color("#554036"), 0.95)
		root.add_child(horn)
	_parent.add_child(root)


func create_crater_story(crater_position: Vector3, radius: float) -> void:
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
	crater.material_override = create_transparent_material(Color("#30272a"), 0.58)
	root.add_child(crater)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.72
	ring_mesh.outer_radius = radius * 0.78
	ring_mesh.rings = 10
	ring_mesh.ring_segments = 18
	ring.mesh = ring_mesh
	ring.position.y = 0.11
	ring.material_override = materials.material(Color("#713f39"), 0.94, Color("#2b2227"))
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
		rock.material_override = materials.material(Color("#554645"), 0.96)
		root.add_child(rock)
	_parent.add_child(root)


func create_shell_casings(origin: Vector3, count: int) -> void:
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
		casing.material_override = materials.material(Color("#d28a36"), 0.56, Color("#7a321f"))
		root.add_child(casing)
	_parent.add_child(root)


func create_bullet_scar(scar_position: Vector3, rotation_y: float) -> void:
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
		mark.material_override = create_transparent_material(Color("#251f22"), 0.65)
		root.add_child(mark)
	_parent.add_child(root)


func create_broken_weapon(weapon_position: Vector3, rotation_y: float) -> void:
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
	shaft.material_override = materials.material(Color("#51382f"), 0.9)
	root.add_child(shaft)
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.45, 0.08, 0.22)
	blade.mesh = blade_mesh
	blade.position = Vector3(0.67, 0.0, 0.0)
	blade.material_override = materials.material(Color("#9e4d36"), 0.82)
	root.add_child(blade)
	_parent.add_child(root)


func create_wall_graffiti(graffiti_position: Vector3, rotation_y: float, color: Color) -> void:
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
	circle.material_override = materials.material(color, 0.94)
	root.add_child(circle)
	var slash := MeshInstance3D.new()
	var slash_mesh := BoxMesh.new()
	slash_mesh.size = Vector3(0.12, 0.95, 0.07)
	slash.mesh = slash_mesh
	slash.position = Vector3(0.0, 0.0, 0.14)
	slash.rotation_degrees.z = 28.0
	slash.material_override = materials.material(color, 0.94)
	root.add_child(slash)
	for index in range(3):
		var drip := MeshInstance3D.new()
		var drip_mesh := BoxMesh.new()
		drip_mesh.size = Vector3(0.06, 0.24 + float(index % 2) * 0.18, 0.05)
		drip.mesh = drip_mesh
		drip.position = Vector3(-0.5 + float(index) * 0.45, -0.30 - float(index % 2) * 0.10, 0.12)
		drip.material_override = materials.material(color, 0.98)
		root.add_child(drip)
	_parent.add_child(root)


func create_debris_field(field_position: Vector3, count: int, radius: float) -> void:
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
		piece.material_override = materials.material(colors[index % colors.size()], 0.95)
		root.add_child(piece)
	_parent.add_child(root)


func create_spectator_side(parent: Node3D, node_name: String, side_position: Vector3, rotation_y: float, banner_color: Color) -> void:
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
		stand.material_override = materials.material(Color("#292e30") if tier == 0 else Color("#35383a"), 0.96)
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
		body.material_override = materials.material(Color("#24282a") if index % 2 == 0 else Color("#3a3738"), 1.0)
		audience.add_child(body)
		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.17
		head_mesh.height = 0.30
		head_mesh.radial_segments = 8
		head_mesh.rings = 4
		head.mesh = head_mesh
		head.position.y = 0.78
		head.material_override = materials.material(Color("#67544a"), 0.95)
		audience.add_child(head)
		root.add_child(audience)
	for flag_index in range(2):
		var flag := MeshInstance3D.new()
		var flag_mesh := BoxMesh.new()
		flag_mesh.size = Vector3(3.1, 0.82, 0.05)
		flag.mesh = flag_mesh
		flag.position = Vector3(-12.0 + float(flag_index) * 24.0, 2.18, -1.05)
		flag.material_override = materials.material(banner_color, 0.96)
		root.add_child(flag)
	parent.add_child(root)


func create_exterior_rock_cluster(parent: Node3D, cluster_position: Vector3, cluster_scale: float, rotation_y: float) -> void:
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
		rock.material_override = materials.material(Color("#5e4b43") if index != 1 else Color("#6f5948"), 1.0)
		root.add_child(rock)
	parent.add_child(root)


func create_exterior_scrap_cluster(parent: Node3D, cluster_position: Vector3, rotation_y: float) -> void:
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
		piece.position.y = grounded_box_center_y(piece, mesh.size) - 0.035
		piece.material_override = materials.material(piece_data[3], 0.96)
		root.add_child(piece)
	parent.add_child(root)


func grounded_box_center_y(box: Node3D, size: Vector3) -> float:
	var half := size * 0.5
	return absf(box.basis.x.y) * half.x + absf(box.basis.y.y) * half.y + absf(box.basis.z.y) * half.z


func create_exterior_industrial_silhouette(parent: Node3D, silhouette_position: Vector3, height: float, color: Color) -> void:
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
	tank.material_override = materials.material(color, 0.98)
	root.add_child(tank)
	var chimney := MeshInstance3D.new()
	var chimney_mesh := CylinderMesh.new()
	chimney_mesh.top_radius = 0.25
	chimney_mesh.bottom_radius = 0.38
	chimney_mesh.height = height * 0.72
	chimney_mesh.radial_segments = 8
	chimney.mesh = chimney_mesh
	chimney.position = Vector3(1.65, chimney_mesh.height * 0.5, 0.55)
	chimney.material_override = materials.material(Color("#272d2f"), 1.0)
	root.add_child(chimney)
	var accent := MeshInstance3D.new()
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = Vector3(2.5, 0.22, 0.12)
	accent.mesh = accent_mesh
	accent.position = Vector3(0.0, height * 0.64, -1.15)
	accent.material_override = materials.material(Color("#78352f"), 0.96)
	root.add_child(accent)
	parent.add_child(root)


func create_wall_identity_marker(node_name: String, marker_position: Vector3, rotation_y: float, marker_text: String, accent: Color) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = marker_position
	root.rotation_degrees.y = rotation_y
	var backing := MeshInstance3D.new()
	var backing_mesh := BoxMesh.new()
	backing_mesh.size = Vector3(5.8, 1.35, 0.10)
	backing.mesh = backing_mesh
	backing.material_override = materials.textured(Color("#d0c6b4"), 0.94, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.8, 1.0, 1.0))
	root.add_child(backing)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.42, 1.14, 0.05)
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(-2.35, 0.0, 0.08)
	stripe.rotation_degrees.z = -12.0
	stripe.material_override = materials.material(accent, 0.90)
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
	_parent.add_child(root)


func create_floor_plate(parent: Node3D, plate_position: Vector2, plate_size: Vector2, rotation_y: float, material: Material, height: float) -> void:
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(plate_size.x, height, plate_size.y)
	plate.mesh = mesh
	plate.position = Vector3(plate_position.x, height * 0.5 + 0.002, plate_position.y)
	plate.rotation_degrees.y = rotation_y
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plate)


func create_ground_rock(node_name: String, rock_position: Vector3, rock_scale: float) -> void:
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
	rock.material_override = materials.material(Color("#655047"), 0.96)
	_parent.add_child(rock)


func create_ground_track(start: Vector3, end: Vector3, width: float) -> void:
	var track := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := materials.material(Color("#875039"), 1.0)
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
	_parent.add_child(track)


func create_ambient_dust() -> void:
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
	dust_mesh.material = create_dust_material()
	dust.draw_pass_1 = dust_mesh
	dust.position = Vector3(0.0, 0.45, 0.0)
	dust.emitting = true
	_parent.add_child(dust)


func create_dust_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.35, 0.25, 0.16)
	return material


func create_blood_stain(stain_position: Vector3, radius: float, alpha: float) -> void:
	var stain := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := create_transparent_material(Color("#431f29"), alpha)
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
	_parent.add_child(stain)


func create_scorch_mark(mark_position: Vector3, radius: float) -> void:
	var scorch := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.2
	mesh.height = 0.025
	scorch.mesh = mesh
	scorch.position = mark_position + Vector3.UP * 0.03
	scorch.material_override = create_transparent_material(Color("#292025"), 0.34)
	_parent.add_child(scorch)


func create_transparent_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	return material


func create_brazier(node_name: String, brazier_position: Vector3) -> void:
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
	bowl.material_override = materials.material(Color("#4b3a32"), 0.78)
	root.add_child(bowl)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.24
	flame_mesh.height = 0.62
	flame.mesh = flame_mesh
	flame.position.y = 0.65
	flame.scale = Vector3(0.75, 1.3, 0.75)
	flame.material_override = materials.material(Color("#ff9e35"), 0.25, Color("#ff6b21"))
	root.add_child(flame)
	# A restrained squash/stretch loop gives the braziers a living silhouette
	# without adding physics or noisy screen-space effects during combat.
	var flame_tween := _parent.create_tween().set_loops()
	flame_tween.tween_property(flame, "scale", Vector3(0.62, 1.52, 0.62), 0.32).set_trans(Tween.TRANS_SINE)
	flame_tween.tween_property(flame, "scale", Vector3(0.84, 1.08, 0.84), 0.44).set_trans(Tween.TRANS_SINE)
	var light := OmniLight3D.new()
	light.position.y = 1.1
	light.light_color = Color("#ff9d4c")
	light.light_energy = 1.3
	light.omni_range = 5.0
	light.set_meta("base_energy", 1.3)
	flicker_lights.append(light)
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
	smoke_mesh.material = create_smoke_material()
	smoke.draw_pass_1 = smoke_mesh
	smoke.position.y = 0.85
	smoke.emitting = true
	root.add_child(smoke)
	_parent.add_child(root)


func create_smoke_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.24, 0.22, 0.20, 0.22)
	return material


func create_scrap_pile(node_name: String, pile_position: Vector3, pile_scale: float) -> void:
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
		piece.material_override = materials.material(Color("#704334") if index % 2 == 0 else Color("#6f6653"), 0.9)
		root.add_child(piece)
	_parent.add_child(root)


func create_scrap_barrier(node_name: String, barrier_position: Vector3, size: Vector3, rotation_y: float = 0.0) -> StaticBody3D:
	# Physics and blocker metadata remain owned by the original factory.
	var body := create_box(node_name, barrier_position, size, Color("#d7d2c8"), STEEL_DARK_TEXTURE)
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
	create_barrier_contact(body, size)
	return body


func create_cover_label(parent: Node3D, size: Vector3, label_text: String) -> void:
	var label := Label3D.new()
	label.text = label_text
	label.font_size = 64
	label.pixel_size = 0.008
	label.modulate = Color("#d7c6a6")
	label.outline_modulate = Color("#242a2b")
	label.outline_size = 8
	label.position = Vector3(0.0, 0.02, size.z * 0.5 + 0.11)
	parent.add_child(label)


func create_barrier_contact(parent: Node3D, size: Vector3) -> void:
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


func perimeter_face_sign(node_name: String) -> float:
	if node_name.begins_with("North") or node_name.begins_with("West"):
		return 1.0
	return -1.0


func barrier_panel_material(variant: int, panel_index: int) -> StandardMaterial3D:
	if variant == 0 and panel_index == 0:
		return materials.textured(Color("#c6bdab"), 0.93, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.25, 1.25, 1.25))
	if variant == 1 and panel_index % 2 == 0:
		return materials.textured(Color("#ad9682"), 0.94, Color.BLACK, METAL_RUST_TEXTURE, Vector3(1.10, 1.10, 1.10))
	if variant == 2 and panel_index == 1:
		return materials.textured(Color("#b9b3a7"), 0.91, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.35, 1.35, 1.35))
	return materials.textured(Color("#a6a39d"), 0.88, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.15, 1.15, 1.15))


func create_barrier_segments(parent: Node3D, size: Vector3) -> void:
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
		segment.material_override = materials.textured(Color.WHITE if index == 1 else Color(colors[index]), 0.90, Color.BLACK, METAL_CREAM_TEXTURE if index == 1 else METAL_RUST_TEXTURE, Vector3(0.9, 0.9, 0.9))
		parent.add_child(segment)


func create_barrier_cable(parent: Node3D, size: Vector3, facing_z: float) -> void:
	var cable := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := materials.material(Color("#292b29"), 1.0)
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


func create_debris_face(parent: Node3D, size: Vector3) -> void:
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
		plate.material_override = materials.material(debris_colors[index % debris_colors.size()], 0.88)
		parent.add_child(plate)
		if index % 2 == 0:
			var bolt := MeshInstance3D.new()
			var bolt_mesh := SphereMesh.new()
			bolt_mesh.radius = 0.08
			bolt_mesh.height = 0.11
			bolt.mesh = bolt_mesh
			bolt.position = plate.position + Vector3(width * 0.28, height * 0.25, 0.09)
			bolt.scale = Vector3(1.0, 0.5, 1.0)
			bolt.material_override = materials.material(Color("#d3a15d"), 0.55, Color("#8a4f2e"))
			parent.add_child(bolt)


func create_barrier_rubble(parent: Node3D, size: Vector3) -> void:
	for index in range(4):
		var rubble := MeshInstance3D.new()
		var rubble_mesh := BoxMesh.new()
		rubble_mesh.size = Vector3(0.16 + float(index % 2) * 0.14, 0.12 + float(index % 3) * 0.06, 0.18 + float(index % 2) * 0.12)
		rubble.mesh = rubble_mesh
		var x := -size.x * 0.42 + float(index) * size.x * 0.28
		var z := size.z * 0.56 if index % 2 == 0 else -size.z * 0.56
		rubble.position = Vector3(x, 0.10 + float(index % 2) * 0.08, z)
		rubble.rotation_degrees = Vector3(float(index) * 17.0, float(index) * 33.0, float(index) * 11.0)
		rubble.material_override = materials.material(Color("#655047") if index % 2 == 0 else Color("#9b683d"), 0.96)
		parent.add_child(rubble)


func create_pipe_clutter(node_name: String, clutter_position: Vector3, rotation_y: float) -> void:
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
		pipe.material_override = materials.material(Color("#5e493d") if index % 2 == 0 else Color("#8d4d30"), 0.86)
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
			ring.material_override = materials.material(Color("#bd7740"), 0.75)
			root.add_child(ring)
	_parent.add_child(root)


func create_perimeter_tower(parent: Node3D, node_name: String, tower_position: Vector3, rotation_y: float) -> void:
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
		post.material_override = materials.material(Color("#2c3234"), 0.84)
		root.add_child(post)
	for y_offset in [0.42, 1.42, 2.48]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(2.05, 0.18, 0.26)
		beam.mesh = beam_mesh
		beam.position.y = y_offset
		beam.material_override = materials.material(Color("#6f4434") if y_offset < 1.0 else Color("#3e4242"), 0.88)
		root.add_child(beam)
	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(1.25, 0.58, 0.07)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.0, 1.62, -0.16)
	flag.material_override = materials.material(Color("#874038"), 0.94)
	root.add_child(flag)
	parent.add_child(root)


func create_invisible_limit(node_name: String, limit_position: Vector3, size: Vector3) -> void:
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
	_parent.add_child(body)
	blockers.append(body)


func create_health_pad(node_name: String, pad_position: Vector3) -> void:
	var repair_kit := REPAIR_KIT_SCENE.instantiate() as Area3D
	repair_kit.name = node_name
	repair_kit.add_child(REPAIR_SOCKET.instantiate())
	repair_kit.position = pad_position
	_parent.add_child(repair_kit)
	repair_kit.call("set_collection_active", false)


func create_bush_cluster(node_name: String, bush_position: Vector3, bush_scale: float, visual_position: Vector3) -> void:
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
	root.set_meta("bush_base_radius", base_radius)
	# Construction positions are local to the supplied arena root; concealment
	# consumers use world coordinates, including translated/rotated map roots.
	var world_center := _parent.to_global(visual_position)
	root.set_meta("bush_visual_position", world_center)
	root.set_meta("bush_center", world_center)
	var visual_root := BUSH_VISUAL_SCRIPT.new()
	visual_root.name = "GroundedVegetation"
	visual_root.position = Vector3(
		(visual_position.x - bush_position.x) / root.scale.x,
		0.012 / root.scale.y,
		(visual_position.z - bush_position.z) / root.scale.z
	)
	# Meshes use world metres, so a circular gameplay radius cannot become an
	# ellipse through the old decorative root scale.
	visual_root.scale = Vector3.ONE / root.scale
	visual_root.setup(1.28 * bush_scale, 2.35 * bush_scale, node_name.hash())
	root.add_child(visual_root)
	_parent.add_child(root)


func create_tire_stack(node_name: String, tire_position: Vector3, count: int) -> void:
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
		tire.material_override = materials.material(Color("#272725"), 1.0)
		root.add_child(tire)
	_parent.add_child(root)


func create_banner(banner_position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = "ScrapBanner"
	root.position = banner_position
	root.rotation_degrees.y = rotation_y
	var banner := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.0, 1.8, 0.08)
	banner.mesh = mesh
	banner.material_override = materials.textured(Color.WHITE, 0.92, Color.BLACK, BANNER_TEXTURE, Vector3(1.0, 1.0, 1.0))
	root.add_child(banner)
	var emblem_vertical := MeshInstance3D.new()
	var vertical_mesh := BoxMesh.new()
	vertical_mesh.size = Vector3(0.20, 0.96, 0.05)
	emblem_vertical.mesh = vertical_mesh
	emblem_vertical.position = Vector3(0.0, 0.0, -0.06)
	emblem_vertical.material_override = materials.material(Color("#e3c28e"), 0.8)
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
	pole.material_override = materials.material(Color("#453831"), 0.85)
	root.add_child(pole)
	_parent.add_child(root)
	var sway := _parent.create_tween().set_loops()
	sway.tween_property(banner, "rotation_degrees", Vector3(0.0, 0.0, 3.0), 0.9).set_trans(Tween.TRANS_SINE)
	sway.tween_property(banner, "rotation_degrees", Vector3(0.0, 0.0, -3.0), 1.1).set_trans(Tween.TRANS_SINE)


func create_box(node_name: String, box_position: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
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
	mesh_instance.material_override = materials.textured(color, 0.85, Color.BLACK, texture, Vector3(1.2, 1.2, 1.2))
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_parent.add_child(body)
	blockers.append(body)
	return body
