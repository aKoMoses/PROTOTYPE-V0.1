extends RefCounted
## Authored map-1 layout, separate from actors, rounds, networking and camera.
## Builds under the supplied root to preserve gameplay paths and visibility adapters.
const PROPS = preload("res://scripts/environment/arena_prop_factory.gd")
const SAND_TEXTURE: Texture2D = preload("res://art/sand_dust.svg")
const ARENA_FLOOR_TEXTURE: Texture2D = preload("res://art/arena_floor.svg")
const METAL_CREAM_TEXTURE: Texture2D = preload("res://art/metal_cream.svg")
const METAL_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const STEEL_DARK_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const ARENA_HALF_EXTENT := 29.0
const EXTERIOR_SIZE := 128.0
const BUSH_PLACEMENT_ATTEMPTS := 12

var _parent: Node3D
var _arena_blockers: Array[StaticBody3D]
var _arena_exterior: Node3D
var props: RefCounted

func _init(parent: Node3D, blockers: Array[StaticBody3D], lamps: Array[OmniLight3D]) -> void:
	_parent = parent
	_arena_blockers = blockers
	props = PROPS.new(parent, blockers, lamps)

func build_environment() -> void:
	_build_environment()

func build() -> void:
	_build_arena()

func _create_scrap_barrier(node_name: String, barrier_position: Vector3, size: Vector3, rotation_y: float = 0.0) -> StaticBody3D:
	var body: StaticBody3D = props.create_scrap_barrier(node_name, barrier_position, size, rotation_y)
	if node_name == "NorthCenterCover":
		props.create_cover_label(body, size, "NORTH // 07")
	elif node_name == "SouthCenterCover":
		props.create_cover_label(body, size, "SOUTH // 03")
	return body

func _create_bush_cluster(node_name: String, position: Vector3, scale: float) -> void:
	var visual_position := _resolve_bush_visual_position(node_name, position, 0.70 * scale)
	props.create_bush_cluster(node_name, position, scale, visual_position)

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
	_parent.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "ArenaKeyLight"
	sun.light_color = Color("#f2d7b5")
	sun.light_energy = 1.08
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.shadow_enabled = true
	_parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "CoolFillLight"
	fill.light_color = Color("#91a9b6")
	fill.light_energy = 0.28
	fill.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	fill.shadow_enabled = false
	_parent.add_child(fill)


func _build_arena() -> void:
	_build_arena_exterior()
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(60.0, 60.0)
	ground.mesh = ground_mesh
	ground.material_override = props.materials.textured(Color.WHITE, 0.94, Color.BLACK, ARENA_FLOOR_TEXTURE, Vector3(2.35, 2.35, 2.35))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent.add_child(ground)
	# The authored sand atlas includes flush repairs, traffic and cover-foot dust.

	_build_scrap_perimeter()

	# Four mirrored repair points keep the established arena contract and make
	# every spawn side travel a comparable distance for healing.
	props.create_health_pad("HealthPadNorth", Vector3(0.0, 0.0, -20.8))
	props.create_health_pad("HealthPadSouth", Vector3(0.0, 0.0, 20.8))
	props.create_health_pad("HealthPadWest", Vector3(-21.0, 0.0, 0.0))
	props.create_health_pad("HealthPadEast", Vector3(21.0, 0.0, 0.0))

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
	props.create_hanging_lamp("LampNorth", Vector3(-8.0, 2.48, -27.58))
	props.create_hanging_lamp("LampSouth", Vector3(8.0, 2.48, 27.58), 180.0)
	props.create_hanging_lamp("LampWest", Vector3(-27.58, 2.48, 8.0), 90.0)
	props.create_hanging_lamp("LampEast", Vector3(27.58, 2.48, -8.0), -90.0)
	_create_arena_scoreboard()
	_create_arena_identity_markers()


func _create_fight_story_marks() -> void:
	# Scars are deliberately placed away from the player spawn so they read as
	# evidence of earlier matches instead of active gameplay indicators.
	props.create_blood_stain(Vector3(-7.8, 0.0, 3.8), 0.65, 0.23)
	props.create_blood_stain(Vector3(8.8, 0.0, -1.6), 0.55, 0.20)
	props.create_blood_stain(Vector3(1.8, 0.0, -2.0), 0.85, 0.24)
	props.create_blood_stain(Vector3(-4.0, 0.0, 12.8), 0.48, 0.22)
	props.create_scorch_mark(Vector3(-6.7, 0.0, 6.8), 0.72)
	props.create_scorch_mark(Vector3(6.6, 0.0, 6.4), 0.82)
	props.create_crater_story(Vector3(-10.0, 0.0, -11.8), 0.72)
	props.create_crater_story(Vector3(10.5, 0.0, 12.8), 0.56)
	props.create_shell_casings(Vector3(-4.6, 0.0, 15.5), 11)
	props.create_shell_casings(Vector3(4.8, 0.0, -14.5), 8)
	props.create_bullet_scar(Vector3(-21.9, 1.15, -4.0), 90.0)
	props.create_bullet_scar(Vector3(21.9, 1.0, 4.5), -90.0)
	props.create_broken_weapon(Vector3(-15.6, 0.0, 3.6), -22.0)
	props.create_broken_weapon(Vector3(15.5, 0.0, -4.0), 148.0)
	props.create_debris_field(Vector3(-3.8, 0.0, 7.0), 10, 2.2)
	props.create_debris_field(Vector3(4.4, 0.0, -6.5), 9, 1.9)
	props.create_debris_field(Vector3(-1.8, 0.0, -1.0), 7, 1.5)
	props.create_wall_graffiti(Vector3(-8.0, 1.15, -25.62), 0.0, Color("#d2b27d"))
	props.create_wall_graffiti(Vector3(8.5, 1.0, 25.62), 180.0, Color("#762e32"))
	props.create_wall_graffiti(Vector3(-25.62, 1.1, 7.0), 90.0, Color("#c5a06f"))
	props.create_wall_graffiti(Vector3(25.62, 1.1, -7.0), -90.0, Color("#762e32"))


func _build_arena_exterior() -> void:
	_arena_exterior = Node3D.new()
	_arena_exterior.name = "ArenaExterior"
	_arena_exterior.add_to_group("arena_exterior")
	_arena_exterior.set_meta("replaceable_environment", true)
	_parent.add_child(_arena_exterior)

	var terrain := MeshInstance3D.new()
	terrain.name = "ExteriorDustTerrain"
	var terrain_mesh := PlaneMesh.new()
	terrain_mesh.size = Vector2(EXTERIOR_SIZE, EXTERIOR_SIZE)
	terrain.mesh = terrain_mesh
	terrain.position.y = -0.06
	terrain.material_override = props.materials.textured(Color("#7a6d63"), 1.0, Color.BLACK, SAND_TEXTURE, Vector3(7.0, 7.0, 7.0))
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
		props.create_perimeter_tower(_arena_exterior, tower_data[0], tower_data[1], tower_data[2])

	var rock_clusters := [
		[Vector3(-38.0, 0.0, -34.0), 2.1, 12.0],
		[Vector3(39.0, 0.0, -31.0), 1.7, -18.0],
		[Vector3(-42.0, 0.0, 15.0), 1.8, 34.0],
		[Vector3(41.0, 0.0, 20.0), 2.2, -9.0],
		[Vector3(-13.0, 0.0, 43.0), 1.5, 22.0],
		[Vector3(17.0, 0.0, -44.0), 1.9, -27.0],
	]
	for cluster_data in rock_clusters:
		props.create_exterior_rock_cluster(_arena_exterior, cluster_data[0], cluster_data[1], cluster_data[2])
	for scrap_data in [
		[Vector3(-35.0, 0.0, -6.0), 18.0],
		[Vector3(35.5, 0.0, 7.0), -21.0],
		[Vector3(-7.0, 0.0, -37.0), -8.0],
		[Vector3(10.0, 0.0, 38.0), 14.0],
	]:
		props.create_exterior_scrap_cluster(_arena_exterior, scrap_data[0], scrap_data[1])
	for silhouette_data in [
		[Vector3(-48.0, 0.0, -18.0), 7.0, Color("#303638")],
		[Vector3(47.0, 0.0, -12.0), 5.5, Color("#493a35")],
		[Vector3(-34.0, 0.0, 47.0), 6.2, Color("#34393a")],
		[Vector3(36.0, 0.0, 45.0), 7.8, Color("#403733")],
	]:
		props.create_exterior_industrial_silhouette(_arena_exterior, silhouette_data[0], silhouette_data[1], silhouette_data[2])


func _create_spectator_stands(parent: Node3D) -> void:
	props.create_spectator_side(parent, "SpectatorsNorth", Vector3(0.0, 0.0, -30.5), 0.0, Color("#8d3732"))
	props.create_spectator_side(parent, "SpectatorsSouth", Vector3(0.0, 0.0, 30.5), 180.0, Color("#8d3732"))
	props.create_spectator_side(parent, "SpectatorsWest", Vector3(-30.5, 0.0, 0.0), 90.0, Color("#3b5a60"))
	props.create_spectator_side(parent, "SpectatorsEast", Vector3(30.5, 0.0, 0.0), -90.0, Color("#3b5a60"))


func _create_arena_scoreboard() -> void:
	var root := Node3D.new()
	root.name = "ArenaScoreboard"
	root.position = Vector3(0.0, 0.0, -27.62)
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(8.8, 2.10, 0.30)
	frame.mesh = frame_mesh
	frame.position.y = 1.30
	frame.material_override = props.materials.textured(Color("#b7b3aa"), 0.86, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.4, 1.4, 1.4))
	root.add_child(frame)
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(7.35, 1.25, 0.06)
	screen.mesh = screen_mesh
	screen.position = Vector3(0.0, 1.32, 0.19)
	screen.material_override = props.materials.material(Color("#183236"), 0.36, Color("#0e4e53"))
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
		status.material_override = props.materials.material(Color("#8d3f38") if side < 0.0 else Color("#496b70"), 0.62)
		root.add_child(status)
	_parent.add_child(root)


func _create_arena_identity_markers() -> void:
	props.create_wall_identity_marker("WestBayMarker", Vector3(-27.62, 1.35, -5.6), 90.0, "WEST // 03", Color("#9a4438"))
	props.create_wall_identity_marker("EastBayMarker", Vector3(27.62, 1.35, 6.4), -90.0, "EAST // 07", Color("#596c69"))


func _create_ground_details() -> void:
	var floor_art := Node3D.new()
	floor_art.name = "FloorArt"
	_parent.add_child(floor_art)
	# Broad repairs are placed outside the central reaction space. Their scale is
	# readable from the gameplay camera; no small loose props sit in movement lanes.
	var repairs := [
		[Vector2(-17.5, -14.5), Vector2(6.4, 4.2), 7.0, props.materials.textured(Color("#8a8780"), 0.88, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.2, 1.2, 1.2))],
		[Vector2(16.0, -13.5), Vector2(5.2, 3.6), -11.0, props.materials.textured(Color("#77736a"), 0.94, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.25, 1.25, 1.25))],
		[Vector2(-15.2, 14.8), Vector2(4.8, 3.4), -8.0, props.materials.textured(Color("#777067"), 0.96, Color.BLACK, METAL_CREAM_TEXTURE, Vector3(1.15, 1.15, 1.15))],
		[Vector2(16.4, 15.2), Vector2(6.8, 3.5), 12.0, props.materials.textured(Color("#85817a"), 0.91, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.3, 1.3, 1.3))],
		[Vector2(-22.8, 1.2), Vector2(3.2, 7.8), 2.0, props.materials.textured(Color("#8a6c58"), 0.95, Color.BLACK, METAL_RUST_TEXTURE, Vector3(1.0, 1.0, 1.0))],
		[Vector2(22.6, -1.0), Vector2(3.0, 7.2), -3.0, props.materials.textured(Color("#7c7870"), 0.94, Color.BLACK, STEEL_DARK_TEXTURE, Vector3(1.0, 1.0, 1.0))],
	]
	for repair in repairs:
		props.create_floor_plate(floor_art, repair[0], repair[1], repair[2], repair[3], 0.018)
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
		props.create_floor_plate(floor_art, seam[0], seam[1], seam[2], props.materials.material(Color("#2f3435"), 1.0), 0.021)
	# Faded workshop paint provides orientation at a glance while remaining much
	# darker than projectiles, status effects and the four recovery pads.
	var markings := [
		[Vector2(0.0, -12.4), Vector2(7.6, 0.34), 0.0],
		[Vector2(0.0, 14.3), Vector2(7.0, 0.34), 0.0],
		[Vector2(-19.8, -3.8), Vector2(3.4, 0.28), 90.0],
		[Vector2(19.8, 4.0), Vector2(3.4, 0.28), 90.0],
	]
	for marking in markings:
		props.create_floor_plate(floor_art, marking[0], marking[1], marking[2], props.materials.material(Color("#75433d"), 0.98), 0.024)


func _build_scrap_perimeter() -> void:
	# Invisible continuous limits keep the original containment contract. Visible
	# panels sit on the same footprint and now read as one assembled industrial wall.
	props.create_invisible_limit("NorthLimit", Vector3(0.0, 1.5, -29.0), Vector3(58.0, 3.0, 0.8))
	props.create_invisible_limit("SouthLimit", Vector3(0.0, 1.5, 29.0), Vector3(58.0, 3.0, 0.8))
	props.create_invisible_limit("WestLimit", Vector3(-29.0, 1.5, 0.0), Vector3(0.8, 3.0, 58.0))
	props.create_invisible_limit("EastLimit", Vector3(29.0, 1.5, 0.0), Vector3(0.8, 3.0, 58.0))
	for index in range(7):
		var offset := -24.8 + float(index) * 8.27
		_create_scrap_barrier("NorthPanel%d" % index, Vector3(offset, 1.05, -28.1), Vector3(7.5, 2.1 + float(index % 2) * 0.35, 0.86))
		_create_scrap_barrier("SouthPanel%d" % index, Vector3(-offset, 1.05, 28.1), Vector3(7.5, 2.1 + float((index + 1) % 2) * 0.35, 0.86))
		_create_scrap_barrier("WestPanel%d" % index, Vector3(-28.1, 1.05, -offset), Vector3(0.86, 2.1 + float(index % 2) * 0.35, 7.5))
		_create_scrap_barrier("EastPanel%d" % index, Vector3(28.1, 1.05, offset), Vector3(0.86, 2.1 + float((index + 1) % 2) * 0.35, 7.5))


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
