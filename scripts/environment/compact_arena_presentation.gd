extends Node3D
## Map-specific recipes composed from independent, shared presentation components.
## Changes scenery only; the stage and mechanisms continue to own every collider.
const SURFACES := preload("res://scripts/environment/arena_surface_finish.gd")
const MATERIALS := preload("res://scripts/environment/arena_material_library.gd")
const LIGHTING := preload("res://scripts/environment/arena_lighting_profile.gd")
const CONTACTS := preload("res://scripts/environment/arena_contact_shadows.gd")
const FLOOR_FINISH := preload("res://scripts/environment/arena_floor_finish.gd")
const MESH_FINISH := preload("res://scripts/environment/arena_mesh_finish.gd")
const BATCH := preload("res://scripts/environment/arena_detail_batch.gd")
const FITTINGS := preload("res://scripts/environment/arena_architectural_props.gd")
const SCENERY := preload("res://scripts/environment/arena_scenery_materials.gd")
const KIT := preload("res://scripts/environment/arena_visual_kit.gd")
const DRESSING := preload("res://scripts/environment/arena_set_dressing.gd")
const RECIPES := {
	"heliostat": preload("res://art/environment/arena_recipes/heliostat.tres"),
	"tideglass": preload("res://art/environment/arena_recipes/tideglass.tres"),
	"clockwork": preload("res://art/environment/arena_recipes/clockwork.tres")}
const SOURCE_SURFACE := "res://shaders/compact_arena_floor.gdshader"
var _stage: Node3D
var _scene: Node3D
var _surfaces := SURFACES.new()
var _floor_finish := FLOOR_FINISH.new()
var _mesh_finish := MESH_FINISH.new()
var _materials := MATERIALS.new()
var _finished: Dictionary = {}
var _protected: Array[Material] = []
var _optional: Node3D
var _lights: Array[Dictionary] = []
var _light_defaults: Dictionary = {}
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _quality := -1
var _clock := 0.0
var _initialized := false
var _detail_batches := 0
var _triangles := 0
var _id := ""
var _recipe: Resource
var _scenery: RefCounted
var _kit_roots: Array[Node3D] = []
var _kit_optional: Array[Node3D] = []
var _kit_batches := 0
var _kit_triangles := 0
var _skinned_covers := 0

func _ready() -> void:
	set_process(false)
	_stage = get_parent() as Node3D
	_scene = _stage.get_parent() as Node3D
	_id = str(_stage.get("arena_id"))
	_recipe = RECIPES[_id]
	_scenery = SCENERY.new(_recipe)
	set_meta("visual_only", true)
	_configure.call_deferred()

func _configure() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var tree := get_tree()
	for frame in 2:
		await tree.process_frame
		if not is_inside_tree() or is_queued_for_deletion() or _stage.is_queued_for_deletion():
			return
	_floor_finish.configure(_recipe, _floor_wear_zones())
	var palette: Dictionary = _stage.get("_materials")
	for key in ["leaf", "leaf_light", "leaf_blue", "soil", "cloud", "glass", "mirror", "water"]:
		if palette.has(key):
			_protected.append(palette[key])
	_finish_branch(_stage)
	if _scene != null:
		var mechanisms := _scene.get_node_or_null("ArenaHazards")
		if mechanisms != null:
			_finish_branch(mechanisms)
	_apply_lighting()
	_build_details()
	_build_object_families()
	var dressing := _register_kit(DRESSING.build(_id, _stage, _palette()), self)
	dressing.name = "ForegroundAssemblies"
	_build_contacts()
	for light in _stage.find_children("*", "OmniLight3D", true, false):
		_lights.append({"node": light, "visible": light.visible})
	_initialized = true
	refresh_quality()
	set_process(true)

func _finish_branch(branch: Node) -> void:
	# Gameplay feedback owns its source materials and their live updates.
	if branch.is_in_group("repair_kits"):
		return
	if branch is MeshInstance3D and branch.mesh != null:
		if branch.get_meta("arena_prism", false):
			branch.mesh = _mesh_finish.orient_prism(branch.mesh)
		if str(branch.name) in ["ContinuousDeck", "IslandTiles"]:
			# Continuous walk surfaces receive shadows, but casting on themselves
			# creates visible shadow acne in the Mobile renderer. Like map 1's ground,
			# only the surrounding structures and real cover silhouettes cast here.
			branch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if branch.material_override != null:
			branch.material_override = _finish_material(branch.material_override)
		else:
			for surface in branch.mesh.get_surface_count():
				var source: Material = branch.get_active_material(surface)
				var finished := _finish_material(source)
				if finished != source:
					branch.set_surface_override_material(surface, finished)
	elif branch is MultiMeshInstance3D and branch.material_override != null:
		branch.material_override = _finish_material(branch.material_override)
	for child in branch.get_children():
		_finish_branch(child)

func _finish_material(source: Material) -> Material:
	if source == null or source in _protected:
		return source
	if _finished.has(source):
		return _finished[source]
	var finish: Material = source
	if source is ShaderMaterial and source.shader != null and source.shader.resource_path == SOURCE_SURFACE:
		var style: Variant = source.get_shader_parameter("style")
		if style in [0, 1, 2]:
			finish = _floor_finish.finish(source)
		elif style in [8, 9]:
			var color: Color = source.get_shader_parameter("stone_color")
			var roughness := float(source.get_shader_parameter("surface_roughness"))
			var metal: Variant = source.get_shader_parameter("surface_metallic")
			var ceramic: bool = _id == "tideglass" and style == 8
			finish = _scenery.finish(source, color, 3 if ceramic else 0 if style == 8 else 1, roughness, float(metal) if metal != null else 0.0, 0.8 if ceramic else 0.0)
	elif source is StandardMaterial3D:
		# The same exclusions as map 1 preserve live glow, glass and foliage.
		if _materials.paint(source) != null:
			var kind := 1 if source.metallic > 0.3 else 2 if source.albedo_color.s > 0.25 else 0
			finish = _scenery.finish(source, source.albedo_color, kind, source.roughness, source.metallic)
	elif source is ShaderMaterial:
		finish = _surfaces.finish_material(source)
	if finish != source:
		_finished[source] = finish
		_finished[finish] = finish
	return finish

func _apply_lighting() -> void:
	if _scene == null:
		return
	var environment: Environment
	for child in _scene.get_children():
		if child is WorldEnvironment:
			environment = child.environment
	_sun = _scene.get_node_or_null("ArenaKeyLight") as DirectionalLight3D
	_fill = _scene.get_node_or_null("CoolFillLight") as DirectionalLight3D
	if _sun != null:
		for key in ["shadow_blur", "shadow_bias", "shadow_normal_bias", "directional_shadow_max_distance"]:
			_light_defaults[key] = _sun.get(key)
	if _fill != null:
		_light_defaults["fill_energy"] = _fill.light_energy
	var profile := LIGHTING.new()
	profile.sunlight_energy = _recipe.sun_energy
	profile.shadow_bias = _recipe.shadow_bias
	profile.shadow_normal_bias = _recipe.shadow_normal_bias
	profile.fill_energy = 0.11
	profile.ambient_energy = _recipe.ambient_energy
	profile.sunlight_color = _recipe.sun_color
	profile.ambient_color = _recipe.ambient_color
	profile.sky_top_color = _recipe.sky_top
	profile.sky_horizon_color = _recipe.sky_horizon
	profile.ground_bottom_color = _recipe.sky_ground
	profile.ground_horizon_color = _recipe.sky_ground_horizon
	profile.sky_energy = _recipe.sky_energy
	profile.ground_energy = _recipe.sky_energy
	profile.apply(environment, _sun, _fill)
	# Viewport/atlas ownership remains with the existing Android/VFX controls.
	# Main restores its saved environment and sun colour when changing arena.

func _build_contacts() -> void:
	# Parenting each contact to its real body makes it follow barges/pivot covers.
	# Body/collision names differ between the classic and procedural constructors.
	for visual in _kit_roots:
		if visual.has_meta("cover_size"):
			var size: Vector3 = visual.get_meta("cover_size")
			var pose := visual.global_transform
			pose.origin.y -= size.y * 0.5 - 0.012
			var footprints: Array[Dictionary] = [{"pose": pose, "size": Vector2(size.x, size.z)}]
			var contacts := CONTACTS.build_footprints(visual, footprints, 0.85)
			contacts.set_meta("visual_only", true)

func _floor_wear_zones() -> PackedVector4Array:
	var zones := PackedVector4Array()
	var definition: Dictionary = _stage.get("_definition")
	for cover in definition.get("covers", []):
		var at: Vector3 = cover.position
		var size: Vector3 = cover.size
		zones.append(Vector4(at.x, at.z, Vector2(size.x, size.z).length() * 0.48, 0.9))
	for at in definition.get("mirrors", []):
		zones.append(Vector4(at.x, at.z, 0.95, 0.85))
	if _id == "tideglass":
		for body in _stage.find_children("IslandPlanter*", "StaticBody3D", true, false):
			zones.append(Vector4(body.position.x, body.position.z, 1.2, 0.8))
	elif _id == "clockwork":
		zones.append(Vector4(0, 0, 1.15, 0.8))
	return zones

func _body_bounds(body: Node3D) -> Dictionary:
	for collision in body.get_children():
		if not collision is CollisionShape3D:
			continue
		if collision.shape is BoxShape3D:
			return {"size": collision.shape.size, "center": collision.position}
		if collision.shape is ConvexPolygonShape3D and not collision.shape.points.is_empty():
			var bounds := AABB(collision.shape.points[0], Vector3.ZERO)
			for point in collision.shape.points:
				bounds = bounds.expand(point)
			return {"size": bounds.size, "center": collision.transform * bounds.get_center()}
	return {}

func _hide_old_skin(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D:
			var material: Material = child.material_override
			# Preserve source material references for animated warning/command lamps.
			if material is StandardMaterial3D and material.emission_enabled:
				continue
			child.visible = false
		else:
			_hide_old_skin(child)

func _register_kit(kit: RefCounted, parent: Node3D, center: Vector3 = Vector3.ZERO) -> Node3D:
	var result: Dictionary = kit.flush(parent)
	result.root.position = center
	_kit_roots.append(result.root)
	_kit_optional.append(result.optional)
	_kit_batches += int(result.batches)
	_kit_triangles += int(result.triangles)
	return result.root

func _build_object_families() -> void:
	var palette := _palette()
	var index := 0
	for original in _stage.find_children("CoverSculpture", "Node3D", true, false):
		var body := original.get_parent() as Node3D
		var bounds := _body_bounds(body)
		if bounds.is_empty():
			continue
		index += 1
		var kit := KIT.new(palette)
		kit.cover(bounds.size, _recipe.cover_style, index)
		var visual := _register_kit(kit, body, bounds.center)
		visual.set_meta("cover_size", bounds.size)
		_hide_old_skin(original)
		var shoulders := body.get_node_or_null("SolarBatteryCopperShoulders") as Node3D
		if shoulders != null:
			shoulders.visible = false
		_skinned_covers += 1
	var mechanisms := _scene.get_node_or_null("ArenaHazards")
	if mechanisms == null:
		return
	for mirror in mechanisms.find_children("SolarMirror*", "StaticBody3D", true, false):
		var pivot := mirror.get_node_or_null("PivotingReflector") as Node3D
		if pivot == null:
			continue
		var kit := KIT.new(palette)
		kit.mirror_frame(Vector2(1.7, 1.8), 11 + int(mirror.get("mirror_index")))
		_register_kit(kit, pivot)
		kit = KIT.new(palette)
		kit.mirror_base()
		_register_kit(kit, mirror)
	var clock := mechanisms.get_node_or_null("ClockworkMechanism")
	if clock != null:
		for body in clock.get("covers"):
			index += 1
			var bounds := _body_bounds(body)
			var kit := KIT.new(palette)
			kit.cover(bounds.size, "clock", index)
			_hide_old_skin(body)
			# Preserve the warning's live material, on segmented lamps instead of
			# a solid yellow roof. The mechanism still owns the pulse and timing.
			for mesh in body.find_children("*", "MeshInstance3D", true, false):
				if mesh.material_override == clock.get("cover_material"):
					mesh.visible = false
			kit.warning_rail(bounds.size, clock.get("cover_material"))
			var visual := _register_kit(kit, body, bounds.center)
			visual.set_meta("cover_size", bounds.size)
			_skinned_covers += 1
		var kit := KIT.new(palette)
		for mesh in clock.get("arm").find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh is SphereMesh:
				mesh.visible = false
		kit.pendulum(float(clock.get_script().get_script_constant_map()["REACH"]))
		_register_kit(kit, clock.get("arm"))
		kit = KIT.new(palette)
		kit.gear(Vector3(0, 0.35, 0), 1.06, Basis.IDENTITY, 24)
		for y in [0.20, 0.65, 1.12]:
			kit.details.ring(palette.metal, Vector3(0, y, 0), 0.73, 0.05, 0.15, Basis.IDENTITY, 32)
		for i in range(12):
			var angle := TAU * float(i) / 12.0
			var at := Vector3(cos(angle), 0.73, sin(angle)) * Vector3(0.72, 1, 0.72)
			kit.details.beveled_box(palette.paint, at, Vector3(0.17, 0.75, 0.045), 0.016, Basis(Vector3.UP, PI * 0.5 - angle))
		_register_kit(kit, clock.get_node("ClockSpindle"))

func _palette() -> Dictionary:
	return _scenery.palette()

func _build_details() -> void:
	var root := Node3D.new()
	root.name = "ArchitecturalFittings"
	root.scale = Vector3(1.25, 1, 1.25)
	add_child(root)
	_optional = Node3D.new()
	_optional.name = "FineOrnaments"
	root.add_child(_optional)
	var primary := BATCH.new()
	var fine := BATCH.new()
	var palette := _palette()
	var props := FITTINGS.new(primary, palette)
	var ornaments := FITTINGS.new(fine, palette)
	match _id:
		"heliostat": _dress_solar(props, ornaments, primary, fine, palette)
		"tideglass": _dress_greenhouse(props, ornaments, primary, fine, palette)
		"clockwork": _dress_clock(props, ornaments, primary, fine, palette)
	var primary_meshes: Array[MeshInstance3D] = primary.flush(root, "StructuralDetail")
	var fine_meshes: Array[MeshInstance3D] = fine.flush(_optional, "FineDetail")
	_detail_batches = primary_meshes.size() + fine_meshes.size()
	_triangles = primary.triangles + fine.triangles

func _dress_solar(props: RefCounted, ornaments: RefCounted, primary: RefCounted, fine: RefCounted, palette: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		for z in [-9.75, 9.75]:
			props.pedestal(Vector3(side * 11.75, -0.06, z), Vector3(0.78, 0.64, 0.75))
			props.column_collar(Vector3(side * 11.75, 1.35, z), 0.27)
		for z in [-5.9, 0.0, 5.9]:
			props.louvred_panel(Vector3(side * 12.04, -0.35, z), Vector2(1.25, 0.50), side * PI * 0.5)
		for z in [-7.1, 7.1]:
			props.planter(Vector3(side * 13.5, 0.24, z), Vector2(1.35, 1.8), int(z + 10), false)
		for i in range(13):
			var z := -9.0 + float(i) * 1.5
			fine.box(palette.dark, Vector3(side * 11.35, 0.20, z), Vector3(0.12, 0.08, 0.62))
			fine.box(palette.bright, Vector3(side * 11.43, 0.26, z), Vector3(0.05, 0.035, 0.08))
		for z in [-12.8, -15.9]:
			ornaments.column_collar(Vector3(side * 13.4, 0.95, z), 0.54)
	props.dial(Vector3(0, 1.1, -12.01), 0.48)
	for i in range(16):
		var x := -11.2 + float(i) * 1.5
		primary.box(palette.trim, Vector3(x, -0.74, 9.85), Vector3(0.32, 0.19, 0.16))
		fine.box(palette.dark, Vector3(x, -0.30, 9.98), Vector3(0.055, 0.21, 0.018))

func _dress_greenhouse(props: RefCounted, ornaments: RefCounted, primary: RefCounted, fine: RefCounted, palette: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		for i in range(4):
			var z := -6.8 + float(i) * 4.2
			props.planter(Vector3(side * 14.6, 0.18, z), Vector2(1.65, 2.4), i + 23)
			ornaments.louvred_panel(Vector3(side * 14.14, 0.43, z), Vector2(1.3, 0.58), side * PI * 0.5)
		props.service_pipe(Vector3(side * 14.0, 0.24, -9.4), Vector3(side * 14.0, 0.24, 9.4), 0.10)
		for z in [-12.2, -15.7, -19.2]:
			props.pedestal(Vector3(side * 12.4, -0.04, z), Vector3(1.08, 0.74, 1.12))
			ornaments.column_collar(Vector3(side * 12.4, 0.88, z), 0.31)
		# Mineral deposits sit on the exterior casing, below the playable islands.
		for i in range(18):
			var z := -9.0 + float(i)
			fine.box(palette.trim, Vector3(side * 10.52, -0.71, z), Vector3(0.03, 0.14 + float(i % 4) * 0.06, 0.11))
	for i in range(7):
		var x := -9.4 + float(i) * 3.1
		props.foliage(Vector3(x, 0.64, -17.4), 1.3, i + 31)
		primary.box(palette.trim, Vector3(x, 0.57, -12.05), Vector3(0.16, 0.22, 0.13))
	ornaments.dial(Vector3(-11.8, 1.45, -12.0), 0.28)

func _dress_clock(props: RefCounted, ornaments: RefCounted, primary: RefCounted, fine: RefCounted, palette: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		props.pedestal(Vector3(side * 10.8, -0.43, -10.8), Vector3(2.6, 0.64, 2.35))
		for y in [0.8, 3.0, 6.9]:
			props.column_collar(Vector3(side * 10.8, y, -10.8), 0.44)
		props.louvred_panel(Vector3(side * 10.8, 0.21, -9.60), Vector2(1.45, 0.78))
		ornaments.dial(Vector3(side * 10.8, 2.0, -10.27), 0.4)
	props.column_collar(Vector3(0, 0.62, -15.4), 0.77)
	for i in range(48):
		var angle := TAU * float(i) / 48.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		var basis := Basis(Vector3.UP, -angle)
		primary.box(palette.dark, radial * 13.56 + Vector3.DOWN * 0.36, Vector3(0.24, 0.44, 0.07), basis)
		fine.box(palette.bright, radial * 13.0 + Vector3.UP * 0.095, Vector3.ONE * 0.065, basis)
		if i % 4 == 0:
			fine.box(palette.trim, radial * 12.45 + Vector3.UP * 0.01, Vector3(0.12, 0.012, 0.42), basis)
	for i in range(12):
		var x := -10.0 + float(i) * 1.8
		fine.box(palette.dark, Vector3(x, -0.5, -10.4), Vector3(0.05, 0.32, 0.04))

func refresh_quality() -> void:
	var manager := _scene.get_node_or_null("VFXManager") if _scene != null else null
	var level := int(manager.get("quality")) if manager != null else 1
	if level == _quality:
		return
	_quality = level
	if _optional != null:
		_optional.visible = level > 0
	for optional in _kit_optional:
		if is_instance_valid(optional):
			optional.visible = level > 0
	for entry in _lights:
		if is_instance_valid(entry.node):
			entry.node.visible = bool(entry.visible) and level > 0
	set_meta("active_quality", level)

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 0.4:
		_clock = 0.0
		refresh_quality()

func get_snapshot() -> Dictionary:
	return {"id": _id, "initialized": _initialized, "recipe": _recipe.resource_path, "finished_materials": _finished.size() / 2, "oriented_prisms": _mesh_finish.corrected, "detail_batches": _detail_batches, "detail_triangles": _triangles, "kit_batches": _kit_batches, "kit_triangles": _kit_triangles, "skinned_covers": _skinned_covers, "quality": _quality, "optional_visible": _optional.visible if _optional != null else false}

func _exit_tree() -> void:
	if is_instance_valid(_sun):
		for key in _light_defaults:
			if key != "fill_energy":
				_sun.set(key, _light_defaults[key])
	if is_instance_valid(_fill) and _light_defaults.has("fill_energy"):
		_fill.light_energy = _light_defaults.fill_energy
