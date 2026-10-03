extends SceneTree
## -- record BASELINE.json | verify BASELINE.json (default: reuse guards only).
const CATALOG := preload("res://scripts/compact_arena_catalog.gd")
const IDS := ["heliostat", "tideglass", "clockwork"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("COMPACT PRESENTATION: " + message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "guards"
	var baseline := {}
	if mode in ["record", "verify"] and args.size() != 2:
		quit(2)
		return
	if mode == "verify":
		baseline = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var script := load("res://scripts/main.gd") as Script
	if script == null or not script.can_instantiate():
		quit(2)
		return
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 8:
		await process_frame
	_freeze(scene)
	var sun := scene.get_node("ArenaKeyLight") as DirectionalLight3D
	var fill := scene.get_node("CoolFillLight") as DirectionalLight3D
	var classic_light := [sun.light_color, sun.light_energy, sun.shadow_bias, sun.shadow_normal_bias, sun.shadow_blur, sun.directional_shadow_max_distance, fill.light_energy]
	var snapshot := {}
	for id in CATALOG.IDS:
		scene.call("set_arena_variant", id)
		var light_direction: Vector3 = scene.get_node("ArenaKeyLight").rotation
		for frame in 5:
			await process_frame
		_freeze(scene)
		var stage := scene.get_node("CompactArenaStage") as Node3D
		var solids := {}
		_collect_solids(stage, scene, solids)
		_collect_solids(scene.get_node("ArenaHazards"), scene, solids)
		# Stored JSON and live Variants must use the same numeric representations.
		snapshot[id] = JSON.parse_string(JSON.stringify({"solids": solids, "definition": var_to_str(CATALOG.definition(id)), "fov": scene.get_node("CameraRig/Camera3D").fov}))
		if mode == "verify":
			_check(snapshot[id] == baseline[id], id + ": gameplay geometry or map definition changed")
		if mode != "record":
			_validate_presentation(stage, scene, id)
			_check(scene.get_node("ArenaKeyLight").rotation == light_direction, id + ": profile changed the map's sun direction")
	scene.call("set_arena_variant", "classic")
	await process_frame
	_check(not scene.has_node("CompactArenaStage"), "compact presentation survived the return to classic")
	_check([sun.light_color, sun.light_energy, sun.shadow_bias, sun.shadow_normal_bias, sun.shadow_blur, sun.directional_shadow_max_distance, fill.light_energy] == classic_light, "compact art settings leaked into classic lighting")
	if mode == "record":
		var file := FileAccess.open(args[1], FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshot, "\t") + "\n")
		print("COMPACT PRESENTATION: BASELINE RECORDED")
	else:
		await _test_reuse()
		print("COMPACT PRESENTATION: ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	root.get_node("GameSfx").call("clear")
	# Dummy audio does not retire an in-flight music fade before a short fixture
	# exits. Stop the fixture's players explicitly before releasing its scene.
	for audio in scene.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _collect_solids(node: Node, scene: Node, values: Dictionary) -> void:
	var key := str(scene.get_path_to(node))
	if node is CollisionObject3D:
		values[key] = [str(node.transform), node.collision_layer, node.collision_mask]
	if node is CollisionShape3D:
		var shape: Shape3D = node.shape
		var dimensions := ""
		if shape is BoxShape3D:
			dimensions = str(shape.size)
		elif shape is CylinderShape3D or shape is CapsuleShape3D:
			dimensions = str(shape.radius) + "/" + str(shape.height)
		elif shape is SphereShape3D:
			dimensions = str(shape.radius)
		elif shape is ConcavePolygonShape3D:
			dimensions = var_to_bytes(shape.get_faces()).hex_encode().sha256_text()
		elif shape is ConvexPolygonShape3D:
			dimensions = var_to_bytes(shape.points).hex_encode().sha256_text()
		values[key] = [str(node.transform), node.disabled, shape.get_class(), dimensions]
	for child in node.get_children():
		_collect_solids(child, scene, values)

func _validate_presentation(stage: Node3D, scene: Node3D, id: String) -> void:
	var presentation := stage.get_node_or_null("CompactArenaPresentation")
	if id not in IDS:
		_check(presentation == null, id + ": unrelated arena received this visual pass")
		return
	_check(presentation != null, id + ": presentation missing")
	if presentation == null:
		return
	var snapshot: Dictionary = presentation.call("get_snapshot")
	_check(bool(snapshot.initialized), id + ": deferred finish did not settle")
	_check(int(snapshot.finished_materials) > 0, id + ": shared finish was not applied")
	_check(int(snapshot.oriented_prisms) > 0, id + ": inward visual prisms were not corrected")
	_check(int(snapshot.detail_batches) > 0 and int(snapshot.detail_batches) <= 24, id + ": decorative batches exceed budget")
	_check(str(snapshot.get("recipe", "")).ends_with(id + ".tres"), id + ": complete art recipe missing")
	_check(int(snapshot.get("skinned_covers", 0)) == {"heliostat": 3, "tideglass": 5, "clockwork": 2}[id], id + ": object families did not replace the visible covers")
	_check(int(snapshot.get("kit_batches", 0)) > 0 and int(snapshot.get("kit_batches", 0)) <= 84, id + ": object-family batches missing or exceed budget")
	_check(int(snapshot.get("kit_triangles", 0)) > 0 and int(snapshot.get("kit_triangles", 0)) <= 100000, id + ": object-family geometry missing or exceeds budget")
	for mesh in stage.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name) not in ["ContinuousDeck", "IslandTiles"]:
			continue
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var top: float = mesh.mesh.get_aabb().end.y
		var cap_normal := 0.0
		var cap_vertices := 0
		for index in vertices.size():
			if absf(vertices[index].y - top) < 0.0001:
				cap_normal += normals[index].y
				cap_vertices += 1
		_check(cap_vertices > 0 and cap_normal > 0, id + ": visible floor points downwards: " + str(stage.get_path_to(mesh)))
		_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, id + ": walk surface casts a shadow on itself")
		var material := mesh.material_override as ShaderMaterial
		_check(material != null and material.get_shader_parameter("detail_albedo") is Texture2D and float(material.get_shader_parameter("detail_strength")) > 0.0, id + ": walk surface lost its real material texture")
	var visual_roots: Array[Node3D] = []
	_collect_kit_roots(stage, visual_roots)
	_collect_kit_roots(scene.get_node("ArenaHazards"), visual_roots)
	_check(not visual_roots.is_empty(), id + ": no attached object families")
	var foreground: Node3D = presentation.get_node("ForegroundAssemblies")
	var outside := true
	var footprint := CATALOG.footprint(id)
	for mesh in foreground.find_children("PrimarySilhouette*", "MeshInstance3D", true, false):
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			var point: Vector3 = stage.to_local(mesh.global_transform * vertex)
			outside = outside and not Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), footprint)
	_check(outside, id + ": bulky exterior scenery intrudes on the walking footprint")
	for visual in visual_roots:
		var solids := {}
		_collect_solids(visual, scene, solids)
		_check(solids.is_empty(), id + ": authored skin contains gameplay geometry")
		if visual.has_meta("cover_size"):
			var contact := visual.get_node_or_null("CoverContactOcclusion") as MultiMeshInstance3D
			_check(contact != null and contact.multimesh.instance_count == 1, id + ": moving cover lost its contact shading")
	for node in presentation.find_children("*", "Node", true, false):
		_check(not node is CollisionObject3D and not node is CollisionShape3D and not node is NavigationRegion3D and not node is Light3D, id + ": decorative component added gameplay geometry or lights")
	var sun := scene.get_node("ArenaKeyLight") as DirectionalLight3D
	var direction := sun.rotation
	scene.get_node("VFXManager").set("quality", 0)
	presentation.call("refresh_quality")
	_check(int(presentation.call("get_snapshot").quality) == 0, id + ": presentation ignores low quality")
	_check(not bool(presentation.call("get_snapshot").optional_visible), id + ": fine detail remains visible at low quality")
	_check(_fasteners_visible(visual_roots, false), id + ": attached fasteners ignore low quality")
	_check(sun.rotation == direction, id + ": finish changed the sun direction")
	scene.get_node("VFXManager").set("quality", 1)
	presentation.call("refresh_quality")
	_check(int(presentation.call("get_snapshot").quality) == 1, id + ": normal quality not restored")
	_check(bool(presentation.call("get_snapshot").optional_visible), id + ": fine detail was not restored")
	_check(_fasteners_visible(visual_roots, true), id + ": attached fasteners not restored")
	_validate_motion(scene, id, visual_roots)

func _collect_kit_roots(node: Node, roots: Array[Node3D]) -> void:
	if node is Node3D and node.get_meta("arena_visual_kit", false):
		roots.append(node)
	for child in node.get_children():
		_collect_kit_roots(child, roots)

func _fasteners_visible(roots: Array[Node3D], expected: bool) -> bool:
	for visual in roots:
		if visual.get_node("OptionalFasteners").visible != expected:
			return false
	return true

func _validate_motion(scene: Node3D, id: String, roots: Array[Node3D]) -> void:
	var poses := {}
	for visual in roots:
		poses[visual] = {"local": visual.transform, "global": visual.global_transform}
	var controller := scene.get_node("ArenaHazards")
	if id == "heliostat":
		controller.call("set_enabled", true)
		controller.call("start_round")
		controller.call("advance", 6.0)
		var mirror: Node = controller.find_children("SolarMirror*", "StaticBody3D", true, false)[0]
		var lamp: Material = mirror.get("lamp")
		_check(mirror.call("request_turn"), "heliostat: mirror command disabled by skin")
		controller.call("advance", 0.4)
		_check(mirror.get("lamp") == lamp and lamp.emission_energy_multiplier > 1.0, "heliostat: command lamp lost its live material")
	elif id == "tideglass":
		var tide: Node = scene.get_node("CompactArenaStage/TideglassArena")
		tide.call("advance", 12.0)
		_check(tide.get("phase") == "haute", "tideglass: tide did not reach high water")
	else:
		var clock: Node = controller.get_node("ClockworkMechanism")
		var lamp: Material = clock.get("cover_material")
		var visible_lamps := 0
		for body in clock.get("covers"):
			for mesh in body.find_children("*", "MeshInstance3D", true, false):
				if mesh.is_visible_in_tree() and mesh.material_override == lamp:
					visible_lamps += 1
		_check(visible_lamps == 2, "clockwork: segmented lamps lost their visible live warning material")
		clock.set("phase", "rotate")
		clock.set("remaining", 2.0)
		clock.call("advance", 0.3)
		_check(clock.get("cover_material") == lamp, "clockwork: warning material replaced")
	var moved := false
	var attached := true
	for visual in roots:
		attached = attached and visual.transform.is_equal_approx(poses[visual].local)
		moved = moved or not visual.global_transform.is_equal_approx(poses[visual].global)
	_check(attached and moved, id + ": skins do not follow their real pivot/body")

func _test_reuse() -> void:
	var parent := Node3D.new()
	parent.position = Vector3(60, 2, 40)
	parent.rotation.y = 0.4
	root.add_child(parent)
	var batch: RefCounted = load("res://scripts/environment/arena_detail_batch.gd").new()
	var palette := {}
	for key in ["stone", "metal", "trim", "dark", "bright", "leaf", "leaf_light", "stem"]:
		palette[key] = StandardMaterial3D.new()
	var fittings: RefCounted = load("res://scripts/environment/arena_architectural_props.gd").new(batch, palette)
	fittings.pedestal(Vector3.ZERO, Vector3(1, 1, 1))
	fittings.planter(Vector3(3, 0, 0), Vector2(2, 1), 7)
	fittings.dial(Vector3(-3, 1, 0), 0.5)
	fittings.service_pipe(Vector3(0, 0, 3), Vector3(0, 2, 3), 0.1)
	var meshes: Array[MeshInstance3D] = batch.flush(parent, "StandaloneFittings")
	_check(not meshes.is_empty(), "fittings require a map stage to produce geometry")
	var valid := true
	for mesh in meshes:
		var arrays := mesh.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		valid = valid and normals.size() == vertices.size() and uvs.size() == vertices.size()
		for index in vertices.size():
			valid = valid and vertices[index].is_finite() and normals[index].is_finite() and normals[index].length_squared() > 0.99 and uvs[index].is_finite()
		_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "reusable fine details add a real shadow pass")
	_check(valid, "reusable fittings contain invalid vertices, degenerate normals or missing UVs")
	_check(parent.find_children("*", "CollisionObject3D", true, false).is_empty(), "reusable fittings add gameplay bodies")
	_test_object_family(parent)
	parent.queue_free()
	await process_frame

func _test_object_family(parent: Node3D) -> void:
	var recipe: Resource = load("res://art/environment/arena_recipes/heliostat.tres")
	var materials: RefCounted = load("res://scripts/environment/arena_scenery_materials.gd").new(recipe)
	for key in ["stone", "metal", "paint"]:
		var surface: ShaderMaterial = materials.palette()[key]
		_check(surface.get_shader_parameter("surface_texture") is Texture2D and surface.get_shader_parameter("surface_normal") is Texture2D, "reusable " + key + " lost its owned color/normal textures")
	var kit: RefCounted = load("res://scripts/environment/arena_visual_kit.gd").new(materials.palette())
	var size := Vector3(3.0, 2.0, 0.65)
	kit.cover(size, "clock", 21)
	var result: Dictionary = kit.flush(parent)
	_check(result.triangles > 0 and result.batches > 0, "new object families require the current map stage")
	var valid := true
	for mesh in result.root.find_children("PrimarySilhouette*", "MeshInstance3D", true, false):
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in vertices.size():
			var v := vertices[index]
			valid = valid and v.is_finite() and absf(v.x) <= size.x * 0.5 and absf(v.y) <= size.y * 0.5 and absf(v.z) <= size.z * 0.5 and normals[index].dot(v) > 0.0
		_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "cover lost its primary silhouette shadow")
	_check(valid, "beveled cover is inward-facing or extends outside its collider")
	_check(result.root.find_children("*", "CollisionObject3D", true, false).is_empty(), "object family creates new physics bodies")
	var source := ShaderMaterial.new()
	source.shader = load("res://shaders/compact_arena_floor.gdshader")
	source.set_shader_parameter("style", 0)
	source.set_shader_parameter("stone_color", Color.WHITE)
	var original := var_to_str(source.get_shader_parameter("authored_wear"))
	var finish: RefCounted = load("res://scripts/environment/arena_floor_finish.gd").new()
	finish.configure(recipe, PackedVector4Array([Vector4(0, 0, 1, 0.8)]))
	var material: ShaderMaterial = finish.finish(source)
	_check(material != source and var_to_str(source.get_shader_parameter("authored_wear")) == original, "floor finish mutated shared source material")
	_check(material.get_shader_parameter("wear_zone_count") == 1 and material.get_shader_parameter("wear_zones").size() == 12, "floor lost its located wear recipe")
	kit = load("res://scripts/environment/arena_visual_kit.gd").new(materials.palette())
	kit.palm(Vector3.ZERO, 1.5, 3)
	kit.fern(Vector3(2, 0, 0), 0.8, 5)
	var plants: Dictionary = kit.flush(parent, "StandaloneFoliage")
	var valid_leaves := true
	var leaf_vertices := 0
	for mesh in plants.root.find_children("ObjectDetail*", "MeshInstance3D", true, false):
		if mesh.material_override not in [materials.palette().leaf, materials.palette().leaf_light]:
			continue
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		leaf_vertices += vertices.size()
		for index in vertices.size():
			valid_leaves = valid_leaves and vertices[index].is_finite() and normals[index].is_finite() and normals[index].length_squared() > 0.99 and uvs[index].is_finite() and uvs[index].x >= 0.0 and uvs[index].x <= 1.0 and uvs[index].y >= 0.0 and uvs[index].y <= 1.0
	_check(leaf_vertices > 0 and valid_leaves, "reusable foliage contains broken normals or non-leaf UVs")
