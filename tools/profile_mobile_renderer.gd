extends SceneTree
## Diagnostic only: inventories rendering resources and compares real GPU work.
var report: Dictionary = {}

func _initialize() -> void:
	seed(0)
	_run.call_deferred()

func _run() -> void:
	for label in ["arena", "garage", "training"]:
		var packed: PackedScene = load("res://scenes/training_ground.tscn" if label == "training" else "res://scenes/main.tscn")
		var scene := packed.instantiate() as Node3D
		root.add_child(scene)
		current_scene = scene
		var vfx := scene.get_node_or_null("VFXManager")
		if vfx != null:
			vfx.call("_apply_device_budget", true)
		root.scaling_3d_scale = 0.75
		var world: Node = scene
		var viewport: Viewport = root
		if label != "training":
			var flow: Node = scene.get_node("Interface")
			if label == "garage":
				flow.call("_open_equipment")
				var garage: Node = flow.get("_forge_garage")
				world = garage.get("stage").get("world")
				viewport = garage.get("stage").get("viewport")
			else:
				flow.call("_show_screen", flow.Screen.COMBAT)
		var target := scene.get_node_or_null("TargetDummy")
		if target != null:
			target.call("set_training_bot_enabled", false)
		await create_timer(1.0).timeout
		if OS.get_cmdline_user_args().has("surface-baseline"):
			var original := Shader.new()
			original.code = FileAccess.get_file_as_string("res://outputs/mobile-surface-original.gdshader")
			for mesh: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
				if mesh.mesh == null:
					continue
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as ShaderMaterial
					if material != null and material.shader.resource_path == "res://art/environment/reference_finish/surface.gdshader":
						material.shader = original
		report[label] = _inventory(world)
		report[label]["static_batch"] = world.get_meta("static_batch_stats", {})
		if DisplayServer.get_name() != "headless":
			RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
			await create_timer(1.0).timeout
			var sums := {"draw_calls": 0.0, "triangles": 0.0, "gpu_ms": 0.0, "render_cpu_ms": 0.0}
			for frame in 120:
				await process_frame
				sums.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				sums.triangles += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				sums.gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
				sums.render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
			for key in sums:
				sums[key] /= 120.0
			report[label]["rendered"] = sums
		print(label.to_upper() + " " + JSON.stringify(report[label]))
		if label == "arena" and DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("shader-compare"):
			await _compare_shader(world, viewport)
		if label == "garage" and DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("batch-compare"):
			await _compare_batches(world, viewport)
		if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("capture-static"):
			var frozen: Dictionary = {}
			var time_regex := RegEx.create_from_string("\\bTIME\\b")
			for mesh: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
				if mesh.mesh == null:
					continue
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as ShaderMaterial
					if material == null or material.shader == null or not material.shader.code.contains("TIME"):
						continue
					var original: Shader = material.shader
					if not frozen.has(original):
						var shader := Shader.new()
						shader.code = time_regex.sub(original.code, "0.0", true)
						frozen[original] = shader
					material.shader = frozen[original]
			for branch_name in ["Player", "TargetDummy", "HeroRobot", "ServiceMechanism"]:
				var branch := world.get_node_or_null(branch_name) as Node3D
				if branch != null:
					branch.hide()
			for particle: GPUParticles3D in world.find_children("*", "GPUParticles3D", true, false):
				particle.hide()
			root.get_node("FramePacing").hide()
			paused = true
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].get_basename() + "-" + label + ".png")
			paused = false
		current_scene = null
		scene.queue_free()
		await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var output := FileAccess.open(args[0], FileAccess.WRITE)
		output.store_string(JSON.stringify(report, "\t"))
	quit()

func _compare_shader(world: Node, viewport: Viewport) -> void:
	var original := Shader.new()
	original.code = FileAccess.get_file_as_string("res://outputs/mobile-surface-original.gdshader")
	var materials: Dictionary = {}
	for mesh: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null and material.shader.resource_path == "res://art/environment/reference_finish/surface.gdshader":
				materials[material] = material.shader
	paused = true
	var readings: Dictionary = {"original": [], "optimized": []}
	for mode in ["original", "optimized", "optimized", "original"]:
		for material in materials:
			material.shader = original if mode == "original" else materials[material]
		for frame in 20:
			await process_frame
		var total := 0.0
		for frame in 60:
			await process_frame
			total += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
		readings[mode].append(total / 60.0)
	for material in materials:
		material.shader = materials[material]
	paused = false
	print("SHADER_ABBA_GPU_MS ", JSON.stringify(readings))

func _compare_batches(world: Node, viewport: Viewport) -> void:
	var helper := world.get_node("StaticSceneBatcher")
	helper.set_process(false)
	paused = true
	var groups: Dictionary = helper.get("_groups")
	var readings: Dictionary = {"original": [], "optimized": []}
	for mode in ["original", "optimized", "optimized", "original"]:
		for group in groups.values():
			group.render.layers = group.properties[0] if mode == "optimized" else 0
			for entry in group.sources:
				entry.node.get_ref().layers = 0 if mode == "optimized" else entry.layers
		for frame in 20:
			await process_frame
		var total := {"gpu_ms": 0.0, "render_cpu_ms": 0.0, "draw_calls": 0.0, "primitives": 0.0}
		for frame in 60:
			await process_frame
			total.gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
			total.render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
			total.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			total.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		for key in total:
			total[key] /= 60.0
		readings[mode].append(total)
	for group in groups.values():
		group.render.layers = group.properties[0]
		for entry in group.sources:
			entry.node.get_ref().layers = 0
	helper.set_process(true)
	paused = false
	print("BATCH_ABBA_RENDER ", JSON.stringify(readings))

func _inventory(world: Node) -> Dictionary:
	var meshes: Array[Node] = world.find_children("*", "MeshInstance3D", true, false)
	var materials: Dictionary = {}
	var groups: Dictionary = {}
	var branches: Dictionary = {}
	var shaders: Dictionary = {}
	var visible := 0
	var surfaces := 0
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or mesh.layers == 0 or not mesh.is_visible_in_tree() or mesh.get_viewport() != world.get_viewport():
			continue
		visible += 1
		var branch: Node = mesh
		while branch.get_parent() != world and branch.get_parent() != null:
			branch = branch.get_parent()
		branches[str(branch.name)] = int(branches.get(str(branch.name), 0)) + mesh.mesh.get_surface_count()
		var group := str(mesh.mesh.get_instance_id())
		for surface in mesh.mesh.get_surface_count():
			surfaces += 1
			var material := mesh.get_active_material(surface)
			if material == null:
				continue
			var id := material.get_instance_id()
			if not materials.has(id):
				materials[id] = {"count": 0, "name": material.resource_name, "shader": (material.shader.resource_path if material is ShaderMaterial and material.shader != null else material.get_class())}
			materials[id].count += 1
			var shader: String = materials[id].shader
			shaders[shader] = int(shaders.get(shader, 0)) + 1
			group += ":" + str(id)
		groups[group] = int(groups.get(group, 0)) + 1
	var shared: Array = groups.values()
	shared.sort()
	var ranked: Array = materials.values()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count)
	return {"meshes": meshes.size(), "visible_meshes": visible, "visible_surfaces": surfaces, "unique_materials": materials.size(), "mesh_material_groups": groups.size(), "identical_instances_saved": visible - groups.size(), "largest_instance_group": shared[-1] if not shared.is_empty() else 0, "branches": branches, "shaders": shaders, "top_materials": ranked.slice(0, 12)}
