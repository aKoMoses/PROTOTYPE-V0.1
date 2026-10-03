extends SceneTree
## Compare the live, finished courtyard with a snapshot taken before extraction.
## -- reuse (default) | record OUTPUT.json | verify OUTPUT.json
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("CLASSIC COMPONENTS: " + message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "reuse"
	if (mode == "reuse" and args.size() > 1) or (mode != "reuse" and (args.size() != 2 or mode not in ["record", "verify"])):
		push_error("Use -- reuse | record|verify baseline.json")
		quit(2)
		return
	var main_script := load("res://scripts/main.gd") as Script
	if main_script == null or not main_script.can_instantiate():
		push_error("CLASSIC COMPONENTS: main scripts must compile first")
		quit(2)
		return
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	_freeze(scene)
	for frame in range(8):
		await process_frame
		_freeze(scene)
	var snapshot := _snapshot(scene)
	# JSON canonicalizes typed null Object values and numeric Variant types.
	snapshot = JSON.parse_string(JSON.stringify(snapshot))
	if mode == "record":
		var file := FileAccess.open(args[1], FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshot, "\t") + "\n")
		print("CLASSIC COMPONENTS: RECORDED ", snapshot.nodes.size(), " scenery nodes")
	elif mode == "verify":
		var actual := FileAccess.open(args[1] + ".actual.json", FileAccess.WRITE)
		actual.store_string(JSON.stringify(snapshot, "\t") + "\n")
		actual.close()
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		_check(_same(snapshot.environment, expected.environment), "lighting or reflections changed")
		_check(_same(snapshot.spawns, expected.spawns), "spawn or camera changed")
		_check(snapshot.nodes.size() == expected.nodes.size(), "scenery node count changed")
		for path in expected.nodes:
			_check(snapshot.nodes.has(path), "missing scenery: " + path)
			if snapshot.nodes.has(path):
				_check(_same(_stable_node(snapshot.nodes[path], path), _stable_node(expected.nodes[path], path)), "scenery changed: " + path)
	if mode != "record":
		await _test_reuse(scene)
		print("CLASSIC COMPONENTS: ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _snapshot(scene: Node3D) -> Dictionary:
	var nodes := {}
	for branch in scene.get("_classic_arena_roots"):
		_collect(branch, scene, nodes)
	var environment: Environment
	for child in scene.get_children():
		if child is WorldEnvironment:
			environment = child.environment
	var sky_values := {}
	if environment.sky != null and environment.sky.sky_material != null:
		for key in ["sky_top_color", "sky_horizon_color", "ground_bottom_color", "ground_horizon_color", "sky_energy_multiplier", "ground_energy_multiplier", "sun_angle_max"]:
			sky_values[key] = _value(environment.sky.sky_material.get(key))
	var lighting := {"sky": sky_values}
	for key in ["background_mode", "background_color", "ambient_light_source", "ambient_light_color", "ambient_light_energy", "reflected_light_source", "tonemap_mode", "fog_enabled"]:
		lighting[key] = _value(environment.get(key))
	for name in ["ArenaKeyLight", "CoolFillLight"]:
		var light := scene.get_node(name) as DirectionalLight3D
		lighting[name] = _properties(light, ["transform", "light_color", "light_energy", "shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur", "directional_shadow_max_distance"])
	var spawns := {}
	for name in ["Player", "TargetDummy", "CameraRig/Camera3D"]:
		spawns[name] = _properties(scene.get_node(name), ["transform"])
	spawns["fov"] = scene.get_node("CameraRig/Camera3D").fov
	return {"nodes": nodes, "environment": lighting, "spawns": spawns}

func _collect(node: Node, scene: Node3D, nodes: Dictionary) -> void:
	var data := {"class": node.get_class()}
	if node is Node3D:
		data.merge(_properties(node, ["transform", "visible"]))
	if node is CollisionObject3D:
		data.merge(_properties(node, ["collision_layer", "collision_mask"]))
	if node is CollisionShape3D:
		data.shape = _properties(node.shape, ["size", "radius", "height"])
		data.disabled = node.disabled
	if node is MeshInstance3D and node.mesh != null:
		data.cast_shadow = node.cast_shadow
		data.mesh = node.mesh.resource_path
		data.surfaces = []
		for surface in node.mesh.get_surface_count():
			data.surfaces.append({"arrays": var_to_bytes(node.mesh.surface_get_arrays(surface)).hex_encode().sha256_text(), "material": _material(node.get_active_material(surface))})
	if node is MultiMeshInstance3D and node.multimesh != null:
		data.instances = []
		for index in node.multimesh.instance_count:
			data.instances.append(_value(node.multimesh.get_instance_transform(index)))
		data.material = _material(node.material_override)
	for key in ["blocks_navigation", "blocks_projectiles", "blocks_line_of_sight", "invisible_safety_limit", "bush_radius", "bush_height", "bush_center", "vfx_surface"]:
		if node.has_meta(key):
			data[key] = _value(node.get_meta(key))
	nodes[str(scene.get_path_to(node))] = data
	for child in node.get_children():
		_collect(child, scene, nodes)

func _material(material: Material) -> Dictionary:
	if material == null:
		return {}
	var result := {"class": material.get_class()}
	if material is ShaderMaterial:
		result.shader = material.shader.resource_path
		for uniform in material.shader.get_shader_uniform_list():
			result[uniform.name] = _value(material.get_shader_parameter(uniform.name))
	elif material is StandardMaterial3D:
		result.merge(_properties(material, ["albedo_color", "albedo_texture", "roughness", "metallic", "emission_enabled", "emission", "emission_energy_multiplier", "uv1_scale", "transparency", "shading_mode", "cull_mode"]))
	return result

func _properties(object: Object, keys: Array) -> Dictionary:
	var values := {}
	for key in keys:
		values[key] = _value(object.get(key))
	return values

func _value(value: Variant) -> Variant:
	if value is Resource:
		return value.resource_path
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return str(value)

func _stable_node(data: Dictionary, path: String) -> Dictionary:
	var stable := data.duplicate(true)
	# These pre-existing ambience animations depend on wall-clock delta. Keep
	# their geometry/recipes in the comparison, but exclude their live phase.
	if path.begins_with("ArenaPresentation/WorkshopDressing/WorkshopAmbience/") or path.begins_with("ArenaPresentation/WorkshopDressing/WorkshopLight") or path.begins_with("ArenaPresentation/WorkshopDressing/LightPool"):
		stable.erase("transform")
	for surface in stable.get("surfaces", []):
		for key in ["ambient_time", "circuit_values", "clock", "live_intensity", "opacity", "progress"]:
			surface.material.erase(key)
	for key in ["ambient_time", "circuit_values", "clock", "live_intensity", "opacity", "progress"]:
		stable.get("material", {}).erase(key)
	return stable

func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) <= 0.000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for index in a.size():
			if not _same(a[index], b[index]):
				return false
		return true
	return a == b

func _test_reuse(scene: Node3D) -> void:
	var parent := Node3D.new()
	parent.name = "IndependentArena"
	parent.position = Vector3(80, 5, 20)
	parent.rotation.y = 0.35
	root.add_child(parent)
	var colliders: Array[StaticBody3D] = []
	var lamps: Array[OmniLight3D] = []
	var props: RefCounted = load("res://scripts/environment/arena_prop_factory.gd").new(parent, colliders, lamps)
	var cover: StaticBody3D = props.create_scrap_barrier("ReusableCover", Vector3(2, 1, 1), Vector3(4, 2, 1), 25)
	_check(colliders.size() == 1 and colliders[0] == cover, "reusable cover did not register its collider")
	_check(cover.get_node("Collision").shape.size == Vector3(4, 2, 1), "reusable cover changed its collision footprint")
	_check(cover.get_meta("blocks_projectiles") and cover.get_meta("blocks_navigation"), "reusable cover lost its gameplay metadata")
	props.create_hanging_lamp("ReusableLamp", Vector3(0, 3, -4))
	props.create_tire_stack("ReusableTires", Vector3(0, 0, 4), 3)
	props.create_bush_cluster("ReusableBush", Vector3(-5, 0, 1), 1.0, Vector3(-4, 0, 1))
	_check(colliders.size() == 1, "decorative objects registered additional colliders")
	_check(parent.has_node("ReusableLamp") and parent.has_node("ReusableTires"), "objects require the Main scene to be constructed")
	var bush := parent.get_node("ReusableBush") as Node3D
	var visual_center := bush.get_node("GroundedVegetation").global_position as Vector3
	var hiding_center := bush.get_meta("bush_center") as Vector3
	_check(Vector2(visual_center.x, visual_center.z).is_equal_approx(Vector2(hiding_center.x, hiding_center.z)), "reusable vegetation concealment ignores the arena root transform")
	var entries: Array[Node3D] = [cover]
	var contacts: MultiMeshInstance3D = load("res://scripts/environment/arena_contact_shadows.gd").build(parent, entries, 5.012)
	var contact_world := contacts.to_global(contacts.multimesh.get_instance_transform(0).origin)
	_check(contacts.multimesh.instance_count == 1 and contacts.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "contact builder added unexpected instances or shadow casters")
	# The headless dummy renderer does not retain MultiMesh instance transforms.
	if DisplayServer.get_name() != "headless":
		_check(contact_world.is_equal_approx(Vector3(cover.global_position.x, 5.012, cover.global_position.z)), "contacts ignore the supplied parent transform or floor height")
	var original_material := ShaderMaterial.new()
	original_material.shader = load("res://shaders/stylized_salvage.gdshader")
	original_material.set_shader_parameter("source_tint", Color("#c6bdab"))
	var original_shader := original_material.shader
	var finish: RefCounted = load("res://scripts/environment/arena_surface_finish.gd").new()
	var finished: Material = finish.finish_material(original_material)
	_check(finished != original_material and original_material.shader == original_shader, "surface finish mutated a source resource")
	_check(finish.finish_material(original_material) == finished and finish.finish_material(finished) == finished, "surface finish duplicates already-finished materials")
	var raw_material: Material = props.materials.textured(Color.WHITE, 0.8, Color.BLACK, load("res://art/steel_dark.svg"))
	var raw_shader: ShaderMaterial = finish.finish_material(raw_material)
	_check(raw_shader != null and raw_shader.shader.resource_path.ends_with("reference_finish/surface.gdshader") and raw_shader.get_shader_parameter("steel_finish") == 1.0, "raw reusable objects require the scene autoload to receive their finish")
	_check(finish.finish_material(raw_material) == raw_shader, "raw material finish is not cached")
	var marker_material: Material = props.materials.material(Color.RED, 0.8, Color.RED)
	_check(finish.finish_material(marker_material) == marker_material, "finish rewrote a special material")
	_check(props.materials.material(Color.RED, 0.8, Color.RED) == marker_material, "material recipes are not shared within one factory")
	var other_props: RefCounted = load("res://scripts/environment/arena_prop_factory.gd").new(parent)
	_check(other_props.materials.material(Color.RED, 0.8, Color.RED) != marker_material, "material mutations can leak to another map instance")
	var profile: Resource = load("res://scripts/environment/arena_lighting_profile.gd").new()
	var other_profile: Resource = profile.duplicate()
	other_profile.sunlight_energy = 0.7
	var sun := DirectionalLight3D.new()
	var fill := DirectionalLight3D.new()
	parent.add_child(sun)
	parent.add_child(fill)
	sun.rotation = Vector3(-0.6, 0.4, 0)
	var direction := sun.rotation
	var environment := Environment.new()
	other_profile.apply(environment, sun, fill)
	_check(is_equal_approx(sun.light_energy, 0.7) and is_equal_approx(profile.sunlight_energy, 1.3), "per-map lighting overrides alter the common profile")
	_check(sun.rotation == direction, "lighting finish overrides a map-owned sun direction")
	_check(environment.sky != null and environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY, "lighting profile did not supply sky reflections")
	var expected_count: int = scene.get("_classic_arena_blockers").size()
	parent.queue_free()
	await process_frame
	_check(scene.get("_classic_arena_blockers").size() == expected_count, "independent components modified classic registries")
