extends Node3D
## Decorative stages and the exact shared collision contract. Combat mechanisms
## are deliberately separate, so every online peer uses the same arena solids.

const CATALOG = preload("res://scripts/compact_arena_catalog.gd")
const FLOOR_SHADER = preload("res://shaders/compact_arena_floor.gdshader")
const WATER_SHADER = preload("res://shaders/compact_arena_water.gdshader")
const REPAIR_SCENE = preload("res://scenes/repair_kit.tscn")
const LEGACY_ART = preload("res://scripts/compact_arena_legacy_art.gd")
const OPEN_ART = preload("res://scripts/compact_arena_open_art.gd")
const PRESENTATION = preload("res://scripts/environment/compact_arena_presentation.gd")

var arena_id: String = "heliostat"
var running: bool = false
var _definition: Dictionary = {}
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _rotors: Array[Dictionary] = []
var _pendulums: Array[Dictionary] = []
var _waters: Array[ShaderMaterial] = []
var _clock: float = 0.0
var _mesh_count: int = 0
var _solid_count: int = 0
var _orbit_rings: Array[Node3D] = []
var _batched_draws_saved: int = 0


func _ready() -> void:
	_definition = CATALOG.definition(arena_id)
	if _definition.is_empty():
		arena_id = "heliostat"
		_definition = CATALOG.definition(arena_id)
	name = "CompactArenaStage"
	_build_materials()
	_build_collision_contract()
	var geometry := get_children()
	var gameplay_definition := _definition
	_definition = CATALOG.DEFINITIONS[arena_id].duplicate(true)
	match arena_id:
		"heliostat": _build_heliostat()
		"tideglass": _build_tideglass()
		"clockwork": _build_clockwork()
		"gyre": _build_gyre()
		"resonance": _build_resonance()
	if arena_id in ["heliostat", "tideglass", "clockwork"]:
		LEGACY_ART.build(self, arena_id)
	else:
		OPEN_ART.build(self, arena_id)
	# Enlarge decorative architecture without scaling physics bodies or heights.
	var art_layout := Node3D.new()
	art_layout.name = "ExpandedArchitecture"
	add_child(art_layout)
	for child in get_children():
		if child != art_layout and child not in geometry and child is Node3D:
			child.reparent(art_layout, false)
	art_layout.scale = Vector3(CATALOG.LAYOUT_SCALE, 1, CATALOG.LAYOUT_SCALE)
	_definition = gameplay_definition
	if arena_id == "gyre":
		var platform := preload("res://scripts/gyre_platform.gd").new()
		platform.name = "GyrePlatform"
		add_child(platform)
		platform.configure(self)
	if arena_id == "tideglass":
		var basin := preload("res://scripts/tideglass_arena.gd").new()
		basin.name = "TideglassArena"
		add_child(basin)
		basin.configure(self)
	_build_landmarks()
	_batch_static_details(self)
	set_meta("arena_id", arena_id)
	set_meta("mesh_count", _mesh_count)
	if arena_id in ["heliostat", "tideglass", "clockwork"] and not OS.get_cmdline_user_args().has("compact-art-baseline"):
		var presentation := PRESENTATION.new()
		presentation.name = "CompactArenaPresentation"
		add_child(presentation)


func _process(delta: float) -> void:
	if not running:
		return
	_clock += maxf(delta, 0.0)
	for entry in _rotors:
		var rotor := entry["node"] as Node3D
		rotor.rotate(entry["axis"], float(entry["speed"]) * delta)
	for entry in _pendulums:
		var pendulum := entry["node"] as Node3D
		pendulum.rotation.z = sin(_clock * float(entry["speed"]) + float(entry["phase"])) * float(entry["arc"])
	for water in _waters:
		water.set_shader_parameter("motion_clock", _clock)


func get_snapshot() -> Dictionary:
	return {"id": arena_id, "mesh_count": _mesh_count, "solid_count": _solid_count,
		"half_size": _definition.get("half_size", Vector2.ZERO), "floor_top": 0.0,
		"covers": (_definition.get("covers", []) as Array).duplicate(true),
		"repair_count": (_definition.get("repairs", []) as Array).size(),
		"footprint": CATALOG.footprint(arena_id), "clock": _clock, "running": running,
		"orbit_angles": [_orbit_rings[0].rotation.y, _orbit_rings[1].rotation.y] if _orbit_rings.size() == 2 else [],
		"batched_draws_saved": _batched_draws_saved}


func set_orbit_angles(inner: float, outer: float) -> void:
	# Runtime owns floor movement and supplies the same angles used for actors.
	if _orbit_rings.size() == 2:
		_orbit_rings[0].rotation.y = inner
		_orbit_rings[1].rotation.y = outer


func _build_materials() -> void:
	_materials["bronze"] = _surface_material(Color("#9b7044"), 9, 0.43, 0.68)
	_materials["gold"] = _surface_material(Color("#ddb369"), 9, 0.34, 0.72)
	_materials["dark_metal"] = _material(Color("#30343c"), 0.42, 0.64)
	_materials["stone"] = _surface_material(Color("#d0c0a1"), 8, 0.9)
	_materials["stone_light"] = _surface_material(Color("#e4d4b4"), 8, 0.82)
	_materials["ochre"] = _material(Color("#927154"), 0.9)
	_materials["teal_metal"] = _material(Color("#326a69"), 0.42, 0.64)
	_materials["porcelain"] = _surface_material(Color("#c3d6c8"), 8, 0.54, 0.08)
	_materials["navy"] = _material(Color("#223d47"), 0.62, 0.2)
	_materials["lavender"] = _surface_material(Color("#6b617f"), 8, 0.54, 0.18)
	_materials["dark_lavender"] = _material(Color("#37364a"), 0.65, 0.3)
	_materials["leaf"] = _material(Color("#3e8b68"), 0.82)
	_materials["leaf_light"] = _material(Color("#8eb66d"), 0.75)
	_materials["leaf_blue"] = _material(Color("#387d79"), 0.8)
	_materials["soil"] = _material(Color("#283b32"), 1.0)
	_materials["coral"] = _material(Color("#e18b74"), 0.63)
	_materials["cloud"] = _material(Color(0.85, 0.92, 0.92, 0.075), 1.0)
	var cloud_material := _materials["cloud"] as StandardMaterial3D
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_materials["mirror"] = _material(Color("#70b7b8"), 0.23, 0.72)
	_materials["glass"] = _material(Color(0.39, 0.77, 0.78, 0.21), 0.12, 0.26)
	var glass := _materials["glass"] as StandardMaterial3D
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_materials["aqua_glow"] = _material(Color("#73d6d1"), 0.42, 0.28, Color("#54c6c8"), 0.8)
	_materials["amber_glow"] = _material(Color("#f2c47d"), 0.4, 0.2, Color("#ffb653"), 0.8)
	_materials["violet_glow"] = _material(Color("#c5b5f0"), 0.4, 0.3, Color("#bba5e6"), 0.85)
	var floor_material := ShaderMaterial.new()
	floor_material.shader = FLOOR_SHADER
	floor_material.set_shader_parameter("stone_color", _definition["floor"])
	floor_material.set_shader_parameter("joint_color", Color("#424844") if arena_id != "clockwork" else Color("#34303f"))
	floor_material.set_shader_parameter("metal_color", Color("#b89a63") if arena_id != "tideglass" else Color("#356967"))
	floor_material.set_shader_parameter("style", CATALOG.IDS.find(arena_id))
	floor_material.set_shader_parameter("surface_roughness", 0.80)
	if arena_id == "gyre":
		floor_material.set_shader_parameter("metal_color", Color("#676963"))
		floor_material.set_shader_parameter("joint_color", Color("#151d22"))
	elif arena_id == "resonance":
		floor_material.set_shader_parameter("metal_color", Color("#bca779"))
	_materials["floor"] = floor_material
	var water := ShaderMaterial.new()
	water.shader = WATER_SHADER
	_materials["water"] = water
	_waters.append(water)
	if arena_id == "gyre":
		_materials["foundry_steel"] = load("res://art/environment/workshops/steel.tres")
		_materials["foundry_paint"] = load("res://art/environment/workshops/paint.tres")
		_materials["foundry_ochre"] = load("res://art/environment/workshops/ochre.tres")
		_materials["cast_iron"] = _surface_material(Color("#333a3d"), 9, 0.68, 0.42)
		_materials["molten_trim"] = _material(Color("#c56439"), 0.5, 0.15, Color("#ff5d16"), 0.55)
		water.set_shader_parameter("fluid_style", 1)
		water.set_shader_parameter("deep_color", Color("#341a16"))
		water.set_shader_parameter("shallow_color", Color("#d36429"))
	elif arena_id == "resonance":
		_materials["alabaster"] = _surface_material(Color("#c9d9da"), 8, 0.44, 0.12)
		_materials["midnight"] = _material(Color("#162534"), 0.4, 0.38)
		_materials["nacre"] = _material(Color("#b8cccf"), 0.29, 0.35)
		_materials["rose_crystal"] = _material(Color("#ba91b6"), 0.27, 0.48)
		_materials["blue_crystal"] = _material(Color("#7aafb7"), 0.27, 0.45)
		for key in ["nacre", "rose_crystal", "blue_crystal"]:
			(_materials[key] as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		water.set_shader_parameter("fluid_style", 2)
		water.set_shader_parameter("deep_color", Color("#101e2d"))
		water.set_shader_parameter("shallow_color", Color("#28444d"))


func _build_collision_contract() -> void:
	var half: Vector2 = _definition["half_size"]
	var footprint := CATALOG.footprint(arena_id) if float(_definition.get("corner_cut", 0.0)) > 0.0 else PackedVector2Array()
	if footprint.size() >= 3:
		_polygon_floor(footprint)
		_polygon_boundaries(footprint)
		_prism(self, "ContinuousDeck", footprint, 0.24, Vector3(0, -0.12, 0), _materials["floor"])
	else:
		_solid("CompactFloor", Vector3(half.x * 2.0, 0.6, half.y * 2.0), Vector3(0, -0.3, 0))
		for sign_value in [-1.0, 1.0]:
			_solid("BoundaryX", Vector3(0.4, 6, half.y * 2.0 + 0.8), Vector3(sign_value * (half.x + 0.2), 3, 0))
			_solid("BoundaryZ", Vector3(half.x * 2.0, 6, 0.4), Vector3(0, 3, sign_value * (half.y + 0.2)))
		_box(self, "ContinuousDeck", Vector3(half.x * 2.0, 0.24, half.y * 2.0), Vector3(0, -0.12, 0), _materials["floor"])
	var index := 0
	for entry in _definition["covers"]:
		index += 1
		var body := _solid("CompactCover%d" % index, entry["size"], entry["position"], deg_to_rad(float(entry["yaw"])))
		_build_cover(body, entry["size"], index)


func _build_landmarks() -> void:
	var metal: Material = _materials["teal_metal"] if arena_id == "tideglass" else _materials["bronze"]
	var light: Material = _materials["violet_glow"] if arena_id == "clockwork" else _materials["aqua_glow"]
	for point in _definition["portals"]:
		_cylinder(self, "PortalSocket", 1.18, 0.06, point + Vector3(0, 0.025, 0), metal)
		_ring(self, "PortalOuterInlay", 1.20, 0.025, point + Vector3(0, 0.045, 0), _materials["gold"])
		for i in range(8):
			var angle := TAU * float(i) / 8.0
			var mark := _box(self, "PortalLocator", Vector3(0.055, 0.018, 0.13), point + Vector3(cos(angle) * 1.34, 0.02, sin(angle) * 1.34), light)
			mark.rotation.y = -angle + PI * 0.5
	for point in _definition["boosts"]:
		var pad := Node3D.new()
		pad.name = "VectorPad"
		pad.position = point
		add_child(pad)
		_cylinder(pad, "VectorSocket", 1.08, 0.024, Vector3(0, 0.012, 0), _materials["dark_metal"])
		_ring(pad, "VectorRim", 1.06, 0.025, Vector3(0, 0.028, 0), metal)
	for point in _definition["repairs"]:
		var kit := REPAIR_SCENE.instantiate() as Node3D
		kit.name = "CompactRepairKit"
		kit.position = point
		kit.set("visual_scale", 1.35)
		add_child(kit)


func _build_cover(body: StaticBody3D, size: Vector3, index: int) -> void:
	var visual := Node3D.new()
	visual.name = "CoverSculpture"
	body.add_child(visual)
	match arena_id:
		"gyre", "resonance":
			var wall_material: Material = _materials["foundry_steel"] if arena_id == "gyre" else _materials["lavender"]
			_box(visual, "CoverWall", size, Vector3.ZERO, wall_material)
			_box(visual, "WallCap", Vector3(size.x + 0.12, 0.12, size.z + 0.12), Vector3(0, size.y * 0.5 - 0.06, 0), _materials["gold"])
		"heliostat":
			var outline := _clipped_rectangle(Vector2(size.x, size.z) * 0.98, 0.16)
			_prism(visual, "BeveledSandstoneBattery", outline, size.y * 0.96, Vector3.ZERO, _materials["stone"])
			for sign_value in [-1.0, 1.0]:
				_prism(visual, "ClippedBronzeCornice", _clipped_rectangle(Vector2(size.x, size.z), 0.14), 0.1, Vector3(0, sign_value * (size.y * 0.5 - 0.05), 0), _materials["bronze"])
				_box(visual, "ReflectorInset", Vector3(size.x * 0.74, size.y * 0.54, 0.025), Vector3(0, 0.07, sign_value * (size.z * 0.5 + 0.006)), _materials["mirror"])
				for grille in range(4):
					_box(visual, "ReflectorLouvre", Vector3(size.x * 0.76, 0.035, 0.05), Vector3(0, size.y * (-0.18 + float(grille) * 0.16), sign_value * size.z * 0.5), _materials["gold"])
			for x_sign in [-1.0, 1.0]:
				_box(visual, "BatteryBinding", Vector3(0.07, size.y, size.z), Vector3(x_sign * size.x * 0.41, 0, 0), _materials["bronze"])
			_box(visual, "SolarChargeLine", Vector3(size.x * 0.7, 0.02, 0.075), Vector3(0, size.y * 0.5 + 0.008, 0), _materials["amber_glow"])
			_cover_bolts(visual, size)
		"tideglass":
			_box(visual, "ReservoirWall", size * Vector3(0.98, 0.94, 0.98), Vector3.ZERO, _materials["porcelain"])
			for sign_value in [-1.0, 1.0]:
				_box(visual, "ReservoirLip", Vector3(size.x, 0.13, size.z), Vector3(0, sign_value * (size.y * 0.5 - 0.065), 0), _materials["teal_metal"])
				_box(visual, "WaterLevelWindow", Vector3(size.x * 0.72, size.y * 0.58, 0.025), Vector3(0, 0.05, sign_value * size.z * 0.5), _materials["navy"])
				for bar in range(3):
					_box(visual, "GlassMullion", Vector3(0.045, size.y * 0.62, 0.04), Vector3(size.x * (float(bar) - 1.0) * 0.25, 0.05, sign_value * size.z * 0.5), _materials["teal_metal"])
			_box(visual, "GrowingBed", Vector3(size.x * 0.86, 0.03, size.z * 0.75), Vector3(0, size.y * 0.5, 0), _materials["soil"])
			for plant_index in range(3):
				_plant(visual, Vector3((float(plant_index) - 1.0) * size.x * 0.24, size.y * 0.5, 0), 0.37, plant_index + index)
		"clockwork":
			_box(visual, "ClockCase", size * Vector3(0.98, 0.97, 0.98), Vector3.ZERO, _materials["dark_lavender"])
			for sign_value in [-1.0, 1.0]:
				_box(visual, "CaseCornice", Vector3(size.x, 0.105, size.z), Vector3(0, sign_value * (size.y * 0.5 - 0.05), 0), _materials["gold"])
				_box(visual, "DialInset", Vector3(size.x * 0.8, size.y * 0.7, 0.025), Vector3(0, 0.04, sign_value * size.z * 0.5), _materials["lavender"])
				var dial := _ring(visual, "EscapementDial", minf(size.x * 0.32, 0.47), 0.025, Vector3(0, 0.04, sign_value * (size.z * 0.5 + 0.02)), _materials["gold"])
				dial.rotation.x = PI * 0.5
				_box(visual, "DialHand", Vector3(0.045, size.y * 0.35, 0.025), Vector3(0, 0.11, sign_value * (size.z * 0.5 + 0.024)), _materials["violet_glow"])
			for side in [-1.0, 1.0]:
				_box(visual, "CaseCorner", Vector3(0.08, size.y, size.z), Vector3(side * (size.x * 0.5 - 0.05), 0, 0), _materials["bronze"])
			_cover_bolts(visual, size)
			for i in range(5):
				_box(visual, "ClockCaseTopVent", Vector3(0.045, 0.012, size.z * 0.3), Vector3(size.x * (float(i) - 2.0) * 0.12, size.y * 0.5 + 0.01, 0), _materials["dark_metal"])


func _build_heliostat() -> void:
	_box(self, "SandstoneRaft", Vector3(23.8, 0.72, 19.8), Vector3(0, -0.59, 0), _materials["stone"])
	_box(self, "BronzeShadowCourse", Vector3(23.4, 0.18, 19.4), Vector3(0, -1.03, 0), _materials["bronze"])
	_box(self, "HangingKeel", Vector3(20.8, 0.85, 16.8), Vector3(0, -1.54, 0), _materials["ochre"])
	_build_perimeter(_materials["stone_light"], _materials["bronze"], 0.34)
	for side in [-1.0, 1.0]:
		for z in [-9.75, 9.75]:
			var pillar := Vector3(side * 11.75, 1.4, z)
			_cylinder(self, "SolarObelisk", 0.25, 3.0, pillar, _materials["stone_light"], 0.17, 6)
			_ring(self, "ObeliskCollar", 0.28, 0.06, pillar + Vector3(0, 0.95, 0), _materials["gold"])
			_sphere(self, "ObeliskSun", 0.34, pillar + Vector3(0, 1.76, 0), _materials["amber_glow"])
			_cylinder(self, "RaftUndersidePylon", 0.6, 3.5, Vector3(side * 8.6, -3.35, z * 0.74), _materials["stone"], 0.95, 6)
		for z in [-11.1, 10.8]:
			var flower_point := Vector3(side * 14.3, -0.5, z)
			_solar_flower(flower_point, side * 0.3)
			var attachment := Vector3(side * 10.5, -0.75, signf(z) * 8.0)
			_beam(self, "HeliostatGantryArm", attachment, flower_point, 0.18, _materials["bronze"])
			_beam(self, "GantrySuspensionWire", attachment + Vector3(0, 2.1, 0), flower_point + Vector3(0, 0.1, 0), 0.025, _materials["gold"])
			_beam(self, "GantryBrace", attachment + Vector3(0, -1.1, 0), flower_point, 0.085, _materials["bronze"])
		for z in [-5.9, 0.0, 5.9]:
			var pedestal := Vector3(side * 11.8, 0.18, z)
			_box(self, "SmallSolarPedestal", Vector3(0.75, 0.6, 1.6), pedestal, _materials["stone"])
			var mirror := _box(self, "TerraceReflector", Vector3(1.05, 0.09, 1.9), pedestal + Vector3(0, 0.65, 0), _materials["mirror"])
			mirror.rotation.z = side * 0.48
			_box(self, "ReflectorBackRail", Vector3(0.09, 0.85, 1.65), pedestal + Vector3(side * 0.35, 0.48, 0), _materials["bronze"])
	# A luminous armillary sculpture lives beyond the far edge; it never blocks
	# the playable roof. Its moving arcs give the solar deck a clear silhouette.
	var armillary := Node3D.new()
	armillary.name = "SolarArmillary"
	armillary.position = Vector3(0, 4.1, -13.2)
	add_child(armillary)
	_cylinder(self, "SolarArmillaryPlinth", 1.15, 2.4, Vector3(0, 0.45, -13.2), _materials["stone"], 0.74, 8)
	_sphere(armillary, "CagedSun", 1.38, Vector3.ZERO, _materials["amber_glow"])
	for i in range(3):
		var hoop := _ring(armillary, "SolarOrbit", 2.0 + float(i) * 0.24, 0.065, Vector3.ZERO, _materials["gold"], 64)
		hoop.rotation = Vector3(PI * (0.28 + float(i) * 0.18), float(i) * 0.8, 0.3)
		_rotors.append({"node": hoop, "axis": Vector3.UP, "speed": 0.07 * (-1.0 if i % 2 == 0 else 1.0)})
	_add_light(Vector3(0, 3.3, -11.4), Color("#ffd195"), 2.0, 7.0)
	# Distant towers form a sky city in staggered depth rather than a wall.
	for i in range(7):
		var x := -42.0 + float(i) * 14.5
		var z := -44.0 - float(i % 3) * 7.0
		_floating_tower(Vector3(x, -8.0 - float(i % 2) * 3.0, z), 0.85 + float(i % 3) * 0.21, i)
	for side in [-1.0, 1.0]:
		_floating_tower(Vector3(side * 42, -10, 8), 0.8, 8)
		_cloud_bank(Vector3(side * 26, -11.0, -22.0), 0.85)
		_cloud_bank(Vector3(side * 34, -14.0, 13.0), 0.9)
	_cloud_bank(Vector3(-9, -13, -37), 1.0)
	_cloud_bank(Vector3(21, -17, -43), 0.85)
	for side in [-1.0, 1.0]:
		for i in range(8):
			var z := -7.4 + float(i) * 2.1
			_box(self, "CarvedTerraceDentil", Vector3(0.2, 0.22, 0.32), Vector3(side * 11.92, -0.66, z), _materials["stone_light"])


func _solar_flower(origin: Vector3, phase: float) -> void:
	var flower := Node3D.new()
	flower.name = "HeliostatPetals"
	flower.position = origin
	add_child(flower)
	_cylinder(flower, "FlowerColumn", 0.43, 2.3, Vector3(0, 0.75, 0), _materials["bronze"], 0.27, 12)
	_cylinder(flower, "FlowerCrown", 0.72, 0.25, Vector3(0, 2.0, 0), _materials["gold"], 0.85, 12)
	var crown := Node3D.new()
	crown.position.y = 2.0
	crown.rotation.y = phase
	flower.add_child(crown)
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var petal := Node3D.new()
		crown.add_child(petal)
		petal.rotation.y = angle
		petal.rotation.x = -0.37
		var outline := PackedVector2Array([Vector2(-0.34, 0.6), Vector2(-0.91, 1.5), Vector2(-0.57, 3.05), Vector2(0.57, 3.05), Vector2(0.91, 1.5), Vector2(0.34, 0.6)])
		_prism(petal, "PetalBronzeFrame", outline, 0.09, Vector3.ZERO, _materials["gold"])
		var panel := PackedVector2Array([Vector2(-0.26, 0.75), Vector2(-0.79, 1.52), Vector2(-0.48, 2.88), Vector2(0.48, 2.88), Vector2(0.79, 1.52), Vector2(0.26, 0.75)])
		_prism(petal, "PetalMirror", panel, 0.025, Vector3(0, 0.064, 0), _materials["mirror"])
		_box(petal, "PetalSpine", Vector3(0.035, 0.04, 2.21), Vector3(0, 0.079, 1.79), _materials["bronze"])
	_rotors.append({"node": crown, "axis": Vector3.UP, "speed": 0.012})


func _floating_tower(origin: Vector3, tower_scale: float, index: int) -> void:
	var tower := Node3D.new()
	tower.name = "DistantFloatingPavilion"
	tower.position = origin
	tower.scale = Vector3.ONE * tower_scale
	add_child(tower)
	_cylinder(tower, "FloatingIsland", 4.2, 2.0, Vector3(0, -1, 0), _materials["ochre"], 5.0, 6)
	_cylinder(tower, "HangingIslandTip", 0.3, 6.0, Vector3(0, -5, 0), _materials["stone"], 4.2, 6)
	_box(tower, "PavilionTerrace", Vector3(8, 0.5, 6), Vector3(0, 0.15, 0), _materials["stone_light"])
	for x in [-2.7, 2.7]:
		for z in [-1.8, 1.8]:
			_cylinder(tower, "PavilionColumn", 0.35, 6 + index % 3, Vector3(x, 3.3, z), _materials["stone"], 0.24, 6)
	_box(tower, "PavilionRoof", Vector3(7.4, 0.55, 5.7), Vector3(0, 6.7, 0), _materials["stone_light"])
	_cylinder(tower, "PavilionCrown", 0.4, 2.6, Vector3(0, 8.2, 0), _materials["bronze"], 1.8, 6)
	_sphere(tower, "PavilionBeacon", 0.3, Vector3(0, 9.6, 0), _materials["aqua_glow"])


func _build_tideglass() -> void:
	var outline := _scaled_polygon(CATALOG.footprint(arena_id), 1.0 / CATALOG.LAYOUT_SCALE)
	_prism(self, "GreenhousePontoon", _scaled_polygon(outline, 1.10), 0.8, Vector3(0, -0.64, 0), _materials["porcelain"])
	_prism(self, "PontoonWaterline", _scaled_polygon(outline, 1.12), 0.2, Vector3(0, -1.07, 0), _materials["teal_metal"])
	_box(self, "Ocean", Vector3(220, 0.06, 220), Vector3(0, -1.35, 0), _materials["water"])
	_build_perimeter(_materials["porcelain"], _materials["teal_metal"], 0.3)
	# Recessed water flanks the combat terrace. Ribbed bridges, pools and plants
	# stay outside its boundary and frame the field without hiding the actors.
	for side in [-1.0, 1.0]:
		_box(self, "BotanicalPoolCasing", Vector3(3.3, 0.18, 19.0), Vector3(side * 12.5, -0.2, 0), _materials["teal_metal"])
		_box(self, "BotanicalPool", Vector3(2.95, 0.035, 18.6), Vector3(side * 12.5, 0.08, 0), _materials["water"])
		for pool_side in [-1.0, 1.0]:
			_box(self, "PoolRetainingRim", Vector3(0.14, 0.3, 19.0), Vector3(side * 12.5 + pool_side * 1.59, 0.12, 0), _materials["teal_metal"])
			_box(self, "PoolEndCap", Vector3(3.3, 0.3, 0.14), Vector3(side * 12.5, 0.12, pool_side * 9.43), _materials["teal_metal"])
		for z in [-8.0, -3.8, 3.8, 8.0]:
			_box(self, "PoolBridge", Vector3(3.6, 0.15, 0.65), Vector3(side * 12.5, 0.25, z), _materials["porcelain"])
			for plank in range(4):
				_box(self, "BridgeSeam", Vector3(0.028, 0.015, 0.64), Vector3(side * 12.5 + (float(plank) - 1.5) * 0.68, 0.334, z), _materials["teal_metal"])
		for i in range(5):
			var z := -8.0 + float(i) * 4.0
			var root := Vector3(side * 11.0, 0.1, z)
			var peak := Vector3(side * 15.7, 6.8 - absf(z) * 0.08, z)
			_beam(self, "GlassFlyingButtress", root, peak, 0.085, _materials["teal_metal"])
			_beam(self, "ButtressOuterFoot", Vector3(side * 15.0, -0.8, z), peak, 0.14, _materials["teal_metal"])
			_box(self, "ButtressStoneFoot", Vector3(0.85, 0.7, 1.0), Vector3(side * 15, -0.45, z), _materials["porcelain"])
			_glass_triangle(self, root, peak, Vector3(side * 15, 0.2, z), _materials["glass"])
			if i % 2 == 0:
				_planter(Vector3(side * 14.7, 0.14, z + 1.4), Vector2(1.8, 2.0), i)
		for i in range(5):
			var z := -7.4 + float(i) * 3.7
			_lily(Vector3(side * 12.5 + sin(float(i) * 2.0) * 0.5, 0.12, z), 0.34 + float(i % 2) * 0.13, i)
	# Three arched bays on the far side reveal the ocean through blue glass.
	for i in range(3):
		var z := -12.2 - float(i) * 3.5
		_arch(self, "GreenhouseVaultRib", 12.4, 8.0, 0.15, 0.23, Vector3(0, 0, z), _materials["teal_metal"])
		_arch(self, "VaultBrassSeam", 12.7, 8.12, 0.04, 0.06, Vector3(0, 0, z), _materials["gold"])
		for side in [-1.0, 1.0]:
			_box(self, "VaultFoot", Vector3(0.85, 1.35, 1.0), Vector3(side * 12.4, 0.6, z), _materials["porcelain"])
	for i in range(7):
		var a := PI * float(i + 1) / 8.0
		var p := Vector3(cos(a) * 12.4, sin(a) * 8.0, -15.7)
		_beam(self, "VaultLongitudinalRail", p + Vector3(0, 0, -3.5), p + Vector3(0, 0, 3.5), 0.047, _materials["teal_metal"])
	for i in range(10):
		var a1 := PI * float(i) / 10.0
		var a2 := PI * float(i + 1) / 10.0
		_glass_quad(self, Vector3(cos(a1) * 12.4, sin(a1) * 8.0, -12.2), Vector3(cos(a2) * 12.4, sin(a2) * 8.0, -12.2), Vector3(cos(a2) * 12.4, sin(a2) * 8.0, -19.2), Vector3(cos(a1) * 12.4, sin(a1) * 8.0, -19.2), _materials["glass"])
	_box(self, "ConservatoryWalkway", Vector3(23, 0.6, 8), Vector3(0, -0.26, -15.7), _materials["porcelain"])
	for i in range(5):
		_planter(Vector3(-8.3 + float(i) * 4.15, 0.04, -14.1), Vector2(2.3, 2.6), i + 10)
		_cylinder(self, "HydroponicCylinder", 0.44, 1.8, Vector3(-8.3 + float(i) * 4.15, 0.96, -17.6), _materials["glass"])
		_ring(self, "HydroponicCollar", 0.44, 0.07, Vector3(-8.3 + float(i) * 4.15, 1.86, -17.6), _materials["teal_metal"])
	for side in [-1.0, 1.0]:
		_cylinder(self, "TideObservationTower", 1.0, 7.0, Vector3(side * 26, 1.5, -24), _materials["porcelain"], 0.72, 12)
		_ring(self, "TowerObservationDeck", 1.9, 0.12, Vector3(side * 26, 5, -24), _materials["teal_metal"])
		_sphere(self, "TowerGlassDome", 1.25, Vector3(side * 26, 5.6, -24), _materials["glass"])
	_add_light(Vector3(-11.3, 1.2, -6), Color("#81e3cb"), 1.1, 6.0)
	_add_light(Vector3(11.3, 1.2, 6), Color("#81e3cb"), 1.1, 6.0)


func _build_clockwork() -> void:
	_cylinder(self, "MainClockPlate", 13.65, 0.65, Vector3(0, -0.52, 0), _materials["dark_lavender"], 13.65, 96)
	_ring(self, "GrandClockBezel", 13.32, 0.17, Vector3(0, -0.1, 0), _materials["gold"], 96)
	_ring(self, "LowerClockCourse", 13.1, 0.24, Vector3(0, -0.84, 0), _materials["bronze"], 96)
	_build_perimeter(_materials["lavender"], _materials["gold"], 0.26)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var p := Vector3(x_side * 9.15, -0.02, z_side * 9.15)
			for i in range(3):
				var reach := 1.4 - float(i) * 0.38
				_beam(self, "ClockCornerFiligree", p + Vector3(-x_side * reach, 0, z_side * 0.12), p + Vector3(x_side * 0.12, 0, -z_side * reach), 0.025, _materials["gold"])
	for i in range(48):
		var a := TAU * float(i) / 48.0
		var tooth := _box(self, "GrandBezelTooth", Vector3(0.62, 0.7, 0.83), Vector3(cos(a) * 13.65, -0.42, sin(a) * 13.65), _materials["bronze"])
		tooth.rotation.y = -a
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a) * 11.9, -0.16, sin(a) * 11.9)
		var tick := _box(self, "OuterHourIndex", Vector3(0.08, 0.035, 0.7), p, _materials["gold"])
		tick.rotation.y = -a + PI * 0.5
		var label := Label3D.new()
		label.text = ["III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "I", "II"][i]
		label.position = Vector3(cos(a) * 10.75, -0.155, sin(a) * 10.75)
		label.rotation = Vector3(-PI * 0.5, 0, -a - PI * 0.5)
		label.font_size = 60
		label.pixel_size = 0.009
		label.modulate = Color("#d6b782")
		label.outline_size = 0
		label.no_depth_test = false
		add_child(label)
	# Large gears rotate outside the collision square. They establish an actual
	# machine suspended in space instead of a recolored industrial courtyard.
	_gear(Vector3(-16.3, -1.5, -8.3), 4.9, 20, -0.07, Vector3.ZERO)
	_gear(Vector3(16.0, -1.1, 5.1), 4.6, 18, 0.08, Vector3.ZERO)
	_gear(Vector3(0, -2.1, -18.1), 7.0, 28, 0.046, Vector3.ZERO)
	_gear(Vector3(-21, -5, 4), 6.0, 24, 0.056, Vector3(0.3, 0.0, 0.3))
	_gear(Vector3(19.0, 1.1, -17.0), 5.8, 22, -0.038, Vector3(1.18, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		_beam(self, "ClockSupportingTruss", Vector3(side * 8, -1.6, -5), Vector3(side * 16, -1.6, -9 if side < 0 else 5), 0.21, _materials["dark_metal"])
	for side in [-1.0, 1.0]:
		var z := -10.8
		_box(self, "PendulumTowerFoot", Vector3(2.5, 0.8, 2.2), Vector3(side * 10.8, -0.1, z), _materials["dark_lavender"])
		_cylinder(self, "PendulumTowerColumn", 0.42, 8.0, Vector3(side * 10.8, 4.0, z), _materials["bronze"], 0.3, 8)
		_ring(self, "TowerCapital", 0.66, 0.1, Vector3(side * 10.8, 7.8, z), _materials["gold"])
		var pendulum := Node3D.new()
		pendulum.name = "GrandPendulum"
		pendulum.position = Vector3(side * 10.8, 7.5, z - 0.2)
		add_child(pendulum)
		_beam(pendulum, "PendulumStem", Vector3.ZERO, Vector3(0, -5.3, 0), 0.065, _materials["gold"])
		var bob := _cylinder(pendulum, "PendulumLens", 0.8, 0.2, Vector3(0, -5.3, 0), _materials["gold"], 0.8, 32)
		bob.rotation.x = PI * 0.5
		var core := _cylinder(pendulum, "PendulumEye", 0.54, 0.225, Vector3(0, -5.3, 0), _materials["violet_glow"], 0.54, 32)
		core.rotation.x = PI * 0.5
		_pendulums.append({"node": pendulum, "speed": 0.84, "phase": 0.0 if side < 0 else PI, "arc": 0.37})
	# The distant central orrery makes a crown above the clock's back edge.
	var orrery := Node3D.new()
	orrery.name = "GrandOrrery"
	orrery.position = Vector3(0, 4.4, -15.4)
	add_child(orrery)
	_cylinder(self, "OrreryColumn", 0.65, 5.0, Vector3(0, 0.9, -15.4), _materials["dark_lavender"], 1.2, 12)
	_sphere(orrery, "OrreryHeart", 0.7, Vector3.ZERO, _materials["violet_glow"])
	for i in range(4):
		var orbit := Node3D.new()
		orbit.rotation = Vector3(0.4 + float(i) * 0.38, float(i) * 0.65, 0.28)
		orrery.add_child(orbit)
		var radius := 2.0 + float(i) * 0.47
		_ring(orbit, "PlanetOrbit", radius, 0.045, Vector3.ZERO, _materials["gold"], 64)
		_sphere(orbit, "OrreryPlanet", 0.23 + float(i) * 0.05, Vector3(radius, 0, 0), _materials["lavender"] if i % 2 == 0 else _materials["gold"])
		_rotors.append({"node": orbit, "axis": Vector3.UP, "speed": 0.065 + float(i) * 0.023})
	_add_light(Vector3(0, 3.1, -10.8), Color("#c6b0e9"), 1.1, 8.0)
	# Deep silhouettes have no collision and consume only a few draw calls.
	for i in range(5):
		var x := -42 + i * 20
		var z := -46.0 - float(i % 2) * 10.0
		_gear(Vector3(x, -5.5 + float(i % 2) * 5, z), 7.5 + float(i % 3), 20, 0.012 * (-1.0 if i % 2 == 0 else 1.0), Vector3(1.1, 0.2, 0.0))


func _build_gyre() -> void:
	var footprint := _scaled_polygon(CATALOG.footprint(arena_id), 1.0 / CATALOG.LAYOUT_SCALE)
	var steel: Material = _materials["foundry_steel"]
	var iron: Material = _materials["cast_iron"]
	_prism(self, "CastOctagonalFoundry", _scaled_polygon(footprint, 1.055), 0.92, Vector3(0, -0.60, 0), iron)
	_prism(self, "FoundryLowerArmor", _scaled_polygon(footprint, 1.025), 0.22, Vector3(0, -1.16, 0), steel)
	_box(self, "MoltenExteriorReservoir", Vector3(190, 0.05, 190), Vector3(0, -2.15, 0), _materials["water"])
	_polygon_trim(footprint, iron, _materials["foundry_ochre"], 0.2)
	_cylinder(self, "FlushAxleMedallion", 0.88, 0.026, Vector3(0, 0.013, 0), iron, 0.88, 32)
	_ring(self, "AxleGuideInlay", 0.85, 0.015, Vector3(0, 0.029, 0), _materials["aqua_glow"])
	for index in range(2):
		var ring_root := Node3D.new()
		ring_root.name = "InnerCastRotor" if index == 0 else "OuterCastRotor"
		add_child(ring_root)
		_orbit_rings.append(ring_root)
		var inner := 0.90 if index == 0 else 4.0
		var outer := 4.0 if index == 0 else 7.60
		var floor_material := (_materials["floor"] as ShaderMaterial).duplicate() as ShaderMaterial
		floor_material.set_shader_parameter("stone_color", Color("#5a4d47") if index == 0 else Color("#35434e"))
		_annulus(ring_root, "SegmentedCastRotorDeck", inner, outer, 0.018, Vector3(0, 0.009, 0), floor_material)
		_ring(ring_root, "RotorOuterTrack", outer - 0.05, 0.018, Vector3(0, 0.025, 0), steel, 96)
		_ring(ring_root, "RotorInnerTrack", inner + 0.05, 0.018, Vector3(0, 0.025, 0), steel, 64)
		var radius := (inner + outer) * 0.5
		for i in range(12 if index == 0 else 20):
			var a := TAU * float(i) / (12.0 if index == 0 else 20.0)
			var tick := _box(ring_root, "RotorDirectionInlay", Vector3(0.10, 0.012, 0.24), Vector3(cos(a) * radius, 0.028, sin(a) * radius), _materials["amber_glow"] if index == 0 else _materials["aqua_glow"])
			tick.rotation.y = -a + 0.40 * (-1.0 if index == 0 else 1.0)
			var joint := _box(ring_root, "RotorFastener", Vector3(0.065, 0.012, 0.065), Vector3(cos(a) * (outer - 0.22), 0.026, sin(a) * (outer - 0.22)), iron)
			joint.rotation.y = -a
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var mounting := Vector3(x_side * 7.4, -1.3, z_side * 6.9)
			_beam(self, "SuspendedFoundryBrace", mounting, mounting * Vector3(0.78, 0, 0.80) + Vector3(0, -4.3, 0), 0.31, steel)
			_box(self, "FoundryBraceAnchor", Vector3(1.3, 0.26, 1.3), mounting, _materials["foundry_paint"])
	for side in [-1.0, 1.0]:
		_foundry_tongs(Vector3(side * 13.5, -0.6, -4.6), side)
		for z in [-4.0, 3.5]:
			_beam(self, "ExteriorMachineBridge", Vector3(side * 9.6, -0.85, z), Vector3(side * 14, -0.85, z), 0.22, steel)
			_beam(self, "MachineBridgeDiagonal", Vector3(side * 8.6, -1.5, z), Vector3(side * 14, -0.85, z), 0.11, steel)
	# The crown is a physically mounted induction magnet with alternating cast
	# housings, service gaps, insulators and visible cables rather than a torus.
	var crown := Node3D.new()
	crown.name = "SegmentedInductionCrown"
	crown.position = Vector3(0, 4.9, -13.2)
	crown.rotation.x = PI * 0.5
	add_child(crown)
	_annulus(crown, "InductionCrownBackbone", 3.3, 3.72, 0.22, Vector3.ZERO, steel)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a) * 3.61, 0, sin(a) * 3.61)
		var casing := _box(crown, "InductionCoilHousing", Vector3(0.7, 0.62, 1.45), p, _materials["foundry_paint"] if i % 3 == 0 else iron)
		casing.rotation.y = -a
		var coil := _box(crown, "InductionCoilWindow", Vector3(0.35, 0.05, 1.15), p + Vector3(0, -0.335, 0), _materials["aqua_glow"])
		coil.rotation.y = -a
		for band in [-1.0, 1.0]:
			var strap := _box(crown, "CoilRetainingStrap", Vector3(0.86, 0.7, 0.07), p + Vector3(-sin(a) * band * 0.42, 0, cos(a) * band * 0.42), steel)
			strap.rotation.y = -a
	for side in [-1.0, 1.0]:
		_box(self, "CrownSupportFoot", Vector3(2.0, 0.55, 2.5), Vector3(side * 4.5, -0.42, -13.2), iron)
		_beam(self, "CrownSupportTower", Vector3(side * 4.5, -0.15, -13.2), Vector3(side * 3.3, 4.3, -13.2), 0.22, steel)
		_beam(self, "CrownSupplyConduit", Vector3(side * 4.8, 0, -13.6), Vector3(side * 3.75, 3.0, -13.6), 0.09, _materials["dark_metal"])
	_add_light(Vector3(-10.8, 0.3, 1), Color("#df6b35"), 1.2, 6.0)
	_add_light(Vector3(10.8, 0.3, -1), Color("#df6b35"), 1.2, 6.0)
	for i in range(5):
		var x := -35.0 + float(i) * 17.5
		var z := -36.0 - float(i % 2) * 8.0
		_box(self, "DistantCastingFactory", Vector3(8, 8 + i % 3, 10), Vector3(x, -2, z), iron)
		for chimney in range(2):
			_cylinder(self, "FoundryChimney", 0.55, 12.0 + float(chimney) * 3.0, Vector3(x + (float(chimney) - 0.5) * 4.5, 5.0, z), steel, 0.42, 8)
		_box(self, "CastingFurnaceWindow", Vector3(4, 0.7, 0.06), Vector3(x, -0.8, z + 5.05), _materials["molten_trim"])


func _foundry_tongs(point: Vector3, side: float) -> void:
	var steel: Material = _materials["foundry_steel"]
	var paint: Material = _materials["foundry_ochre"]
	var root := Node3D.new()
	root.name = "ArticulatedFoundryTongs"
	root.position = point
	add_child(root)
	_prism(root, "TongsConcreteMount", _clipped_rectangle(Vector2(3.8, 3.3), 0.45), 0.6, Vector3(0, 0, 0), _materials["cast_iron"])
	_cylinder(root, "TongsTurntable", 1.27, 0.32, Vector3(0, 0.46, 0), steel, 1.27, 32)
	_box(root, "TongsPedestal", Vector3(1.7, 1.35, 1.75), Vector3(0, 1.2, 0), paint)
	var shoulder := Vector3(0, 2.15, 0)
	var elbow := Vector3(side * 0.65, 5.9, -1.5)
	var wrist := Vector3(-side * 1.9, 6.9, -4.8)
	_beam(root, "TongsUpperArm", shoulder, elbow, 0.46, paint)
	_beam(root, "TongsForeArm", elbow, wrist, 0.37, paint)
	_beam(root, "UpperArmHydraulicPiston", shoulder + Vector3(-side * 0.58, 0.1, -0.2), elbow + Vector3(-side * 0.45, -0.7, 0.1), 0.12, steel)
	_beam(root, "ForeArmHydraulicPiston", elbow + Vector3(0, -0.45, 0.4), wrist + Vector3(0, -0.3, 0.4), 0.105, steel)
	for pivot in [shoulder, elbow, wrist]:
		var bearing := _cylinder(root, "TongsArticulationBearing", 0.57, 1.13, pivot, steel, 0.57, 16)
		bearing.rotation.z = PI * 0.5
		var cap := _cylinder(root, "TongsBearingCap", 0.30, 1.17, pivot, _materials["dark_metal"], 0.30, 12)
		cap.rotation.z = PI * 0.5
	for claw_side in [-1.0, 1.0]:
		var knuckle := wrist + Vector3(claw_side * 0.87, -1.12, 0)
		var tip := wrist + Vector3(claw_side * 0.43, -2.42, 0)
		_beam(root, "TongsClawLink", wrist, knuckle, 0.20, steel)
		_beam(root, "TongsClawJaw", knuckle, tip, 0.18, _materials["dark_metal"])
		_box(root, "TongsCeramicJawPad", Vector3(0.26, 0.62, 0.45), tip, _materials["foundry_paint"])
	_beam(root, "TongsExternalCable", shoulder + Vector3(0, 0, 0.6), elbow + Vector3(0, 0, 0.6), 0.045, _materials["dark_metal"])
	_beam(root, "TongsCableContinuation", elbow + Vector3(0, 0, 0.6), wrist + Vector3(0, 0, 0.6), 0.045, _materials["dark_metal"])


func _build_resonance() -> void:
	var footprint := _scaled_polygon(CATALOG.footprint(arena_id), 1.0 / CATALOG.LAYOUT_SCALE)
	_prism(self, "AlabasterResonancePlinth", _scaled_polygon(footprint, 1.055), 0.65, Vector3(0, -0.49, 0), _materials["alabaster"])
	_prism(self, "MidnightPlinthUndercut", _scaled_polygon(footprint, 1.02), 0.2, Vector3(0, -0.93, 0), _materials["midnight"])
	_box(self, "MidnightReflectingBasin", Vector3(190, 0.05, 190), Vector3(0, -1.60, 0), _materials["water"])
	_polygon_trim(footprint, _materials["alabaster"], _materials["nacre"], 0.16)
	# Floor engravings and scalloped relief stay flush; the interior has no prop
	# that blocks bullets, movement or a clear view of the other fighter.
	for side in [-1.0, 1.0]:
		for i in range(5):
			var x := -6.0 + float(i) * 3.0
			var inset := _box(self, "PearlEdgeInlay", Vector3(0.8, 0.010, 0.055), Vector3(x, 0.012, side * 7.15), _materials["blue_crystal"])
			inset.rotation.y = 0.4 * side
		for z in [-4.8, 4.8]:
			_acoustic_fan(Vector3(side * 13.6, 0.1, z), side, int(z > 0))
			_beam(self, "AcousticFanMountBridge", Vector3(side * 9.9, -0.12, z), Vector3(side * 13.6, -0.12, z), 0.11, _materials["nacre"])
		var arch_root := Node3D.new()
		arch_root.position = Vector3(side * 13.5, 0, 0)
		arch_root.rotation.y = PI * 0.5
		add_child(arch_root)
		_arch(arch_root, "PeripheralTensionArch", 8.1, 6.0, 0.06, 0.09, Vector3.ZERO, _materials["nacre"])
		for z in [-8.1, 8.1]:
			_box(self, "TensionArchStoneAnchor", Vector3(1.4, 0.42, 1.6), Vector3(side * 13.5, 0.08, z), _materials["alabaster"])
			_beam(self, "BasinSupportTie", Vector3(side * 9.8, -0.50, signf(z) * 4.9), Vector3(side * 13.5, -0.50, z), 0.095, _materials["nacre"])
	# The far shell hangs its faceted organ pipes from two real supporting ribs.
	for z in [-11.2, -12.0]:
		_arch(self, "AcousticShellRibbon", 10.7, 7.0, 0.15, 0.28, Vector3(0, 0.1, z), _materials["alabaster"])
	for i in range(9):
		var x := -8.0 + float(i) * 2.0
		var peak := 0.1 + sqrt(maxf(0.0, 1.0 - pow(x / 10.7, 2.0))) * 7.0
		var length := 2.0 + sin(float(i) * 0.72) * 0.65 + (2.0 if i == 4 else 0.0)
		_beam(self, "OrganSuspensionCable", Vector3(x, peak, -11.6), Vector3(x, peak - 0.5, -11.6), 0.018, _materials["nacre"])
		_cylinder(self, "FacetedAcousticOrganPipe", 0.21 + float(i % 3) * 0.08, length, Vector3(x, peak - 0.5 - length * 0.5, -11.6), _materials["blue_crystal"] if i % 2 == 0 else _materials["rose_crystal"], 0.16, 6)
		_ring(self, "OrganSuspensionCollar", 0.24, 0.035, Vector3(x, peak - 0.48, -11.6), _materials["nacre"], 16)
		_beam(self, "ShellRibbonConnector", Vector3(x, peak, -11.2), Vector3(x, peak, -12.0), 0.027, _materials["nacre"])
	for side in [-1.0, 1.0]:
		_box(self, "AcousticShellPedestal", Vector3(1.6, 0.6, 2.4), Vector3(side * 10.7, -0.1, -11.6), _materials["alabaster"])
		_beam(self, "ShellFoundationBridge", Vector3(side * 7.6, -0.8, -7.6), Vector3(side * 10.7, -0.8, -11.6), 0.13, _materials["nacre"])
	_add_light(Vector3(-11, 1.3, -2), Color("#95c8d8"), 0.7, 6.0)
	_add_light(Vector3(11, 1.3, 2), Color("#c5aacb"), 0.7, 6.0)
	for i in range(7):
		var x := -40.0 + float(i) * 13.2
		var p := Vector3(x, -1.7, -37 - i % 2 * 8)
		_cylinder(self, "DistantEchoPedestal", 2.2, 1.1, p, _materials["midnight"], 2.2, 8)
		_cylinder(self, "DistantEchoMonolith", 0.75, 7.0 + float(i % 3) * 2, p + Vector3(0, 3.8, 0), _materials["blue_crystal"] if i % 2 == 0 else _materials["rose_crystal"], 0.18, 5)


func _acoustic_fan(point: Vector3, side: float, seed: int) -> void:
	var fan := Node3D.new()
	fan.name = "FacetedAcousticFan"
	fan.position = point
	fan.rotation.y = side * PI * 0.25
	add_child(fan)
	_prism(fan, "AcousticFanGroundAnchor", _clipped_rectangle(Vector2(1.9, 1.6), 0.28), 0.4, Vector3(0, 0.02, 0), _materials["alabaster"])
	_beam(fan, "FanCentralSpindle", Vector3(0, 0.2, 0), Vector3(0, 1.1, 0), 0.08, _materials["nacre"])
	var pivot := Vector3(0, 0.8, 0)
	for i in range(7):
		var a := 0.34 + float(i) * (PI - 0.68) / 6.0
		var direction := Vector3(cos(a), sin(a), 0)
		var perpendicular := Vector3(-sin(a), cos(a), 0)
		var tip := pivot + direction * (3.65 + sin(float(i + seed) * 0.9) * 0.48)
		var shoulder := pivot + direction * 2.0
		var left := shoulder - perpendicular * 0.36
		var right := shoulder + perpendicular * 0.36
		var ridge := shoulder + Vector3(0, 0, 0.22)
		var material: Material = _materials["blue_crystal"] if (i + seed) % 2 == 0 else _materials["rose_crystal"]
		_glass_triangle(fan, pivot, left, ridge, material)
		_glass_triangle(fan, left, tip, ridge, material)
		_glass_triangle(fan, pivot, ridge, right, _materials["nacre"])
		_glass_triangle(fan, right, ridge, tip, _materials["nacre"])
		_beam(fan, "FanCrystalSpine", pivot, tip, 0.021, _materials["nacre"])
		_beam(fan, "FanOuterBinding", left, tip, 0.014, _materials["nacre"])
		_beam(fan, "FanInnerBinding", tip, right, 0.014, _materials["nacre"])


func _build_perimeter(coping: Material, binding: Material, rail_height: float) -> void:
	if float(_definition.get("corner_cut", 0.0)) > 0.0:
		var outline := _scaled_polygon(CATALOG.footprint(arena_id), 1.0 / CATALOG.LAYOUT_SCALE)
		_polygon_trim(outline, coping, binding, rail_height)
		return
	var half: Vector2 = _definition["half_size"]
	var rail_width := 0.065 if arena_id == "clockwork" else 0.12
	for side in [-1.0, 1.0]:
		_box(self, "SideCoping", Vector3(0.68, 0.19, half.y * 2.0 + 1.2), Vector3(side * (half.x + 0.34), -0.055, 0), coping)
		_box(self, "EndCoping", Vector3(half.x * 2.0, 0.19, 0.68), Vector3(0, -0.055, side * (half.y + 0.34)), coping)
		_box(self, "SideBoundaryRail", Vector3(rail_width, 0.055, half.y * 2.0), Vector3(side * (half.x + 0.28), rail_height, 0), binding)
		_box(self, "EndBoundaryRail", Vector3(half.x * 2.0, 0.055, rail_width), Vector3(0, rail_height, side * (half.y + 0.28)), binding)
		for i in range(7):
			var z := -half.y + float(i) * half.y / 3.0
			_box(self, "SideRailPier", Vector3(0.17, rail_height + 0.1, 0.17), Vector3(side * (half.x + 0.28), (rail_height + 0.1) * 0.5 - 0.02, z), binding)
		for i in range(5):
			var x := -half.x + float(i) * half.x * 0.5
			_box(self, "EndRailPier", Vector3(0.17, rail_height + 0.1, 0.17), Vector3(x, (rail_height + 0.1) * 0.5 - 0.02, side * (half.y + 0.28)), binding)


func _gear(origin: Vector3, radius: float, tooth_count: int, speed: float, angles: Vector3) -> void:
	var gear := Node3D.new()
	gear.name = "OrbitingGear"
	gear.position = origin
	gear.rotation = angles
	add_child(gear)
	_annulus(gear, "CastGearRim", radius * 0.8, radius * 0.975, 0.32, Vector3.ZERO, _materials["bronze"])
	_ring(gear, "GearPolishedRim", radius * 0.94, 0.045, Vector3(0, 0.17, 0), _materials["gold"], 64)
	_cylinder(gear, "GearAxle", radius * 0.21, 0.8, Vector3.ZERO, _materials["dark_metal"], radius * 0.21, 16)
	_ring(gear, "AxleCollar", radius * 0.23, 0.075, Vector3(0, 0.42, 0), _materials["gold"])
	_cylinder(gear, "GearAxleCap", radius * 0.18, 0.055, Vector3(0, 0.44, 0), _materials["bronze"], radius * 0.18, 12)
	var bolts := SurfaceTool.new()
	bolts.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		_append_box(bolts, Vector3(cos(a) * radius * 0.865, 0.18, sin(a) * radius * 0.865), Vector3(0.075, 0.08, 0.075) * radius * 0.4, Basis(Vector3.UP, a))
	bolts.generate_normals()
	_instance(gear, "GearRimBolting", bolts.commit(), Vector3.ZERO, _materials["dark_metal"])
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var spoke := _box(gear, "CastGearSpoke", Vector3(radius * 0.7, 0.24, radius * 0.12), Vector3(cos(a) * radius * 0.51, 0, sin(a) * radius * 0.51), _materials["bronze"])
		spoke.rotation.y = -a
	# All gear teeth are batched into one mesh; large silhouettes stay affordable.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(tooth_count):
		var a := TAU * float(i) / float(tooth_count)
		_append_box(st, Vector3(cos(a) * radius, 0, sin(a) * radius), Vector3(radius * 0.19, 0.4, radius * 0.12), Basis(Vector3.UP, -a))
	st.generate_normals()
	_instance(gear, "BatchedGearTeeth", st.commit(), Vector3.ZERO, _materials["gold"])
	_rotors.append({"node": gear, "axis": Vector3.UP, "speed": speed})


func _cover_bolts(parent: Node3D, size: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			_append_box(st, Vector3(x_side * size.x * 0.39, size.y * 0.5 + 0.016, z_side * size.z * 0.34), Vector3(0.065, 0.042, 0.065), Basis.IDENTITY)
	st.generate_normals()
	_instance(parent, "BatchedCoverBolts", st.commit(), Vector3.ZERO, _materials["dark_metal"])


func _clipped_rectangle(size: Vector2, clip: float) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([Vector2(-half.x + clip, -half.y), Vector2(half.x - clip, -half.y), Vector2(half.x, -half.y + clip), Vector2(half.x, half.y - clip), Vector2(half.x - clip, half.y), Vector2(-half.x + clip, half.y), Vector2(-half.x, half.y - clip), Vector2(-half.x, -half.y + clip)])


func _cloud_bank(point: Vector3, cloud_scale: float) -> void:
	for i in range(3):
		var cloud := _sphere(self, "CloudBelowSolarTerrace", 1.0, point + Vector3((float(i) - 1.0) * 3.6, float(i % 2) * 0.5, float(i % 2) * 1.9), _materials["cloud"])
		cloud.scale = Vector3(4.7 + float(i % 2) * 0.9, 1.7 + float(i % 2) * 0.8, 3.4) * cloud_scale
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _annulus(parent: Node3D, label: String, inner: float, outer: float, height: float, point: Vector3, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		var a1 := TAU * float(i) / 64.0
		var a2 := TAU * float(i + 1) / 64.0
		var i1 := Vector3(cos(a1) * inner, height * 0.5, sin(a1) * inner)
		var i2 := Vector3(cos(a2) * inner, height * 0.5, sin(a2) * inner)
		var o1 := Vector3(cos(a1) * outer, height * 0.5, sin(a1) * outer)
		var o2 := Vector3(cos(a2) * outer, height * 0.5, sin(a2) * outer)
		var down := Vector3(0, -height, 0)
		_quad(st, i1, i2, o2, o1)
		_quad(st, i1 + down, o1 + down, o2 + down, i2 + down)
		_quad(st, o1, o2, o2 + down, o1 + down)
		_quad(st, i2, i1, i1 + down, i2 + down)
	st.generate_normals()
	_instance(parent, label, st.commit(), point, material)


func _planter(point: Vector3, size: Vector2, seed: int) -> void:
	_box(self, "BotanicalPlanter", Vector3(size.x, 0.48, size.y), point + Vector3(0, 0.24, 0), _materials["porcelain"])
	_box(self, "PlanterLip", Vector3(size.x + 0.08, 0.075, size.y + 0.08), point + Vector3(0, 0.5, 0), _materials["teal_metal"])
	_box(self, "PlanterSoil", Vector3(size.x * 0.85, 0.025, size.y * 0.86), point + Vector3(0, 0.545, 0), _materials["soil"])
	for i in range(3):
		_plant(self, point + Vector3((float(i) - 1.0) * size.x * 0.26, 0.55, sin(float(i + seed)) * size.y * 0.14), 0.95 + float((seed + i) % 3) * 0.19, seed + i)


func _plant(parent: Node3D, point: Vector3, length: float, seed: int) -> void:
	# A single mesh holds five gently bowed, tapered fronds with a raised rib.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in range(5):
		var angle := float(frond) * TAU / 5.0 + float(seed) * 0.81
		var leaf_length := length * (0.8 + float((seed + frond) % 3) * 0.1)
		var forward := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(-sin(angle), 0, cos(angle))
		for segment in range(6):
			var t1 := float(segment) / 6.0
			var t2 := float(segment + 1) / 6.0
			var c1 := forward * t1 * leaf_length * 0.75 + Vector3.UP * (sin(t1 * PI * 0.68) * leaf_length * 0.88)
			var c2 := forward * t2 * leaf_length * 0.75 + Vector3.UP * (sin(t2 * PI * 0.68) * leaf_length * 0.88)
			var w1 := sin(t1 * PI) * leaf_length * 0.18
			var w2 := sin(t2 * PI) * leaf_length * 0.18
			_tri(st, c1 - across * w1, c2 - across * w2, c1 + Vector3.UP * w1 * 0.25)
			_tri(st, c1 + Vector3.UP * w1 * 0.25, c2 - across * w2, c2 + Vector3.UP * w2 * 0.25)
			_tri(st, c1 + across * w1, c1 + Vector3.UP * w1 * 0.25, c2 + across * w2)
			_tri(st, c2 + across * w2, c1 + Vector3.UP * w1 * 0.25, c2 + Vector3.UP * w2 * 0.25)
	st.generate_normals()
	var material: Material = _materials[["leaf", "leaf_light", "leaf_blue"][seed % 3]]
	_instance(parent, "LayeredTropicalFronds", st.commit(), point, material)


func _lily(point: Vector3, radius: float, seed: int) -> void:
	_cylinder(self, "LilyPad", radius, 0.015, point, _materials["leaf"], radius, 20)
	var bloom := Node3D.new()
	bloom.position = point + Vector3(0, 0.025, 0)
	add_child(bloom)
	for i in range(5):
		var a := TAU * float(i) / 5.0
		var petal := _sphere(bloom, "LotusPetal", radius * 0.29, Vector3(cos(a) * radius * 0.26, 0.04, sin(a) * radius * 0.26), _materials["coral"] if seed % 2 == 0 else _materials["porcelain"])
		petal.scale = Vector3(1.0, 0.5, 0.7)
	_sphere(bloom, "LotusHeart", radius * 0.12, Vector3(0, 0.09, 0), _materials["amber_glow"])


func _arch(parent: Node3D, label: String, radius: float, height: float, thickness: float, depth: float, origin: Vector3, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(40):
		var a1 := PI * float(i) / 40.0
		var a2 := PI * float(i + 1) / 40.0
		var vertices: Array[Vector3] = []
		for a in [a1, a2]:
			var p := Vector3(cos(a) * radius, sin(a) * height, 0)
			var normal := Vector3(cos(a) * height, sin(a) * radius, 0).normalized() * thickness * 0.5
			vertices.append(p - normal + Vector3(0, 0, -depth * 0.5))
			vertices.append(p + normal + Vector3(0, 0, -depth * 0.5))
			vertices.append(p + normal + Vector3(0, 0, depth * 0.5))
			vertices.append(p - normal + Vector3(0, 0, depth * 0.5))
		for face in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
			_quad(st, vertices[face[0]], vertices[face[1]], vertices[face[2]], vertices[face[3]])
	st.generate_normals()
	_instance(parent, label, st.commit(), origin, material)


func _glass_triangle(parent: Node3D, a: Vector3, b: Vector3, c: Vector3, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, a, b, c)
	st.generate_normals()
	var instance := _instance(parent, "ButtressGlazing", st.commit(), Vector3.ZERO, material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _glass_quad(parent: Node3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, a, b, c, d)
	st.generate_normals()
	var instance := _instance(parent, "VaultGlazing", st.commit(), Vector3.ZERO, material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _prism(parent: Node3D, label: String, outline: PackedVector2Array, thickness: float, point: Vector3, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		var a := outline[indices[i]]
		var b := outline[indices[i + 1]]
		var c := outline[indices[i + 2]]
		_tri(st, Vector3(a.x, thickness * 0.5, a.y), Vector3(c.x, thickness * 0.5, c.y), Vector3(b.x, thickness * 0.5, b.y))
		_tri(st, Vector3(a.x, -thickness * 0.5, a.y), Vector3(b.x, -thickness * 0.5, b.y), Vector3(c.x, -thickness * 0.5, c.y))
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_quad(st, Vector3(a.x, -thickness * 0.5, a.y), Vector3(a.x, thickness * 0.5, a.y), Vector3(b.x, thickness * 0.5, b.y), Vector3(b.x, -thickness * 0.5, b.y))
	st.generate_normals()
	var instance := _instance(parent, label, st.commit(), point, material)
	instance.set_meta("arena_prism", true)


func _solid(label: String, size: Vector3, point: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = point
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 2 | 4
	body.add_to_group("arena_solid")
	if label == "CompactFloor" or label.begins_with("Boundary"):
		body.set_meta("invisible_safety_limit", true)
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_solid_count += 1
	return body


func _polygon_floor(footprint: PackedVector2Array) -> void:
	var body := StaticBody3D.new()
	body.name = "CompactFloor"
	body.collision_layer = 1
	body.collision_mask = 2 | 4
	body.add_to_group("arena_solid")
	body.set_meta("invisible_safety_limit", true)
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for p in footprint:
		points.append(Vector3(p.x, 0.0, p.y))
		points.append(Vector3(p.x, -0.6, p.y))
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	_solid_count += 1


func _polygon_boundaries(footprint: PackedVector2Array) -> void:
	for i in range(footprint.size()):
		var a := footprint[i]
		var b := footprint[(i + 1) % footprint.size()]
		var direction := (b - a).normalized()
		var outward := _polygon_outward(footprint, direction)
		var center := (a + b) * 0.5 + outward * 0.2
		_solid("BoundaryPolygon%d" % i, Vector3(a.distance_to(b) + 0.12, 6, 0.4), Vector3(center.x, 3, center.y), atan2(-direction.y, direction.x))


func _polygon_trim(footprint: PackedVector2Array, coping: Material, binding: Material, height: float) -> void:
	for i in range(footprint.size()):
		var a := footprint[i]
		var b := footprint[(i + 1) % footprint.size()]
		var direction := (b - a).normalized()
		var outward := _polygon_outward(footprint, direction)
		var center := (a + b) * 0.5 + outward * 0.14
		var yaw := atan2(-direction.y, direction.x)
		var cap := _box(self, "OctagonalDeckBinding", Vector3(a.distance_to(b) + 0.1, 0.14, 0.28), Vector3(center.x, -0.03, center.y), coping)
		cap.rotation.y = yaw
		var rail := _box(self, "OctagonalSafetyRim", Vector3(a.distance_to(b), 0.05, 0.045), Vector3(center.x, height, center.y), binding)
		rail.rotation.y = yaw
		for j in range(4):
			var p := a.lerp(b, float(j) / 3.0) + outward * 0.15
			_box(self, "SafetyRimTie", Vector3(0.06, height + 0.05, 0.06), Vector3(p.x, height * 0.5, p.y), binding)


func _polygon_outward(footprint: PackedVector2Array, direction: Vector2) -> Vector2:
	var area := 0.0
	for i in range(footprint.size()):
		var a := footprint[i]
		var b := footprint[(i + 1) % footprint.size()]
		area += a.x * b.y - b.x * a.y
	return Vector2(direction.y, -direction.x) if area > 0.0 else Vector2(-direction.y, direction.x)


func _scaled_polygon(footprint: PackedVector2Array, factor: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in footprint:
		result.append(point * factor)
	return result


func _box(parent: Node3D, label: String, size: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var key := "box:%s" % size
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return _instance(parent, label, _meshes[key], point, material)


func _cylinder(parent: Node3D, label: String, radius: float, height: float, point: Vector3, material: Material, top_radius: float = -1.0, segments: int = 32) -> MeshInstance3D:
	var top := radius if top_radius < 0.0 else top_radius
	var key := "cylinder:%s:%s:%s:%s" % [radius, top, height, segments]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = radius
		mesh.top_radius = top
		mesh.height = height
		mesh.radial_segments = segments
		_meshes[key] = mesh
	return _instance(parent, label, _meshes[key], point, material)


func _ring(parent: Node3D, label: String, radius: float, tube: float, point: Vector3, material: Material, segments: int = 32) -> MeshInstance3D:
	var key := "torus:%s:%s:%s" % [radius, tube, segments]
	if not _meshes.has(key):
		var mesh := TorusMesh.new()
		mesh.inner_radius = radius - tube
		mesh.outer_radius = radius + tube
		mesh.rings = segments
		mesh.ring_segments = 8
		_meshes[key] = mesh
	return _instance(parent, label, _meshes[key], point, material)


func _sphere(parent: Node3D, label: String, radius: float, point: Vector3, material: Material) -> MeshInstance3D:
	var key := "sphere:%s" % radius
	if not _meshes.has(key):
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 16
		mesh.rings = 8
		_meshes[key] = mesh
	return _instance(parent, label, _meshes[key], point, material)


func _beam(parent: Node3D, label: String, from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var beam := _cylinder(parent, label, radius, from.distance_to(to), (from + to) * 0.5, material, radius, 8)
	beam.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	return beam


func _batch_static_details(parent: Node3D) -> void:
	# Repeated bolts, teeth and plinth details share one instanced draw. Each
	# rotating branch keeps its own batch and exactly the same local transforms.
	# Collectibles own mesh references and material swaps; preserve their subtree.
	if parent != self and parent.get_script() != null:
		return
	var groups: Dictionary = {}
	for child in parent.get_children():
		if child is Node3D:
			_batch_static_details(child)
		if not child is MeshInstance3D or child.get_child_count() > 0:
			continue
		var candidate := child as MeshInstance3D
		var animated := false
		for entry in _rotors:
			if entry["node"] == candidate:
				animated = true
		for entry in _pendulums:
			if entry["node"] == candidate:
				animated = true
		if animated or candidate.mesh == null or candidate.material_override == null:
			continue
		if candidate.material_override is StandardMaterial3D and candidate.material_override.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var key := "%d:%d:%d" % [candidate.mesh.get_instance_id(), candidate.material_override.get_instance_id(), candidate.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(candidate)
	for key in groups:
		var instances: Array = groups[key]
		if instances.size() < 4:
			continue
		var first := instances[0] as MeshInstance3D
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = first.mesh
		multi.instance_count = instances.size()
		for index in range(instances.size()):
			multi.set_instance_transform(index, instances[index].transform)
		var batch := MultiMeshInstance3D.new()
		batch.name = first.name + "Batch"
		batch.multimesh = multi
		batch.material_override = first.material_override
		batch.cast_shadow = first.cast_shadow
		parent.add_child(batch)
		_batched_draws_saved += instances.size() - 1
		for instance in instances:
			parent.remove_child(instance)
			instance.free()


func _instance(parent: Node3D, label: String, mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position = point
	instance.material_override = material
	parent.add_child(instance)
	_mesh_count += 1
	return instance


func _add_light(point: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = "ArchitecturalFill"
	light.position = point
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)


func _material(color: Color, roughness: float, metallic: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	return material


func _surface_material(color: Color, style: int, roughness: float, metallic: float = 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLOOR_SHADER
	material.set_shader_parameter("stone_color", color)
	material.set_shader_parameter("style", style)
	material.set_shader_parameter("surface_roughness", roughness)
	material.set_shader_parameter("surface_metallic", metallic)
	return material


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


func _append_box(st: SurfaceTool, center: Vector3, size: Vector3, basis: Basis) -> void:
	var points: Array[Vector3] = []
	for p in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		points.append(center + basis * (p * size * 0.5))
	for face in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		_quad(st, points[face[0]], points[face[1]], points[face[2]], points[face[3]])
