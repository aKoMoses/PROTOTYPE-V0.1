extends SceneTree

# Runs the production main scene with the active renderer and reports a compact,
# repeatable environment budget. Use a graphics backend (not --headless) so the
# draw-call and primitive monitors reflect the gameplay camera.

const SAMPLE_FRAMES := 120


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node_or_null("Interface")
	if flow != null:
		flow.call("_start_duel")
		flow.call("_begin_live_round")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if target != null:
		target.call("set_training_bot_enabled", false)
	var totals := {
		"fps": 0.0,
		"process_ms": 0.0,
		"physics_ms": 0.0,
		"draw_calls": 0.0,
		"primitives": 0.0,
	}
	for _frame in range(30):
		await process_frame
	for _frame in range(SAMPLE_FRAMES):
		await process_frame
		totals.fps += Performance.get_monitor(Performance.TIME_FPS)
		totals.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		totals.physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		totals.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		totals.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var counts := _count_scene(scene)
	print("ARENA AUDIT: version=%s renderer=%s display=%s viewport=%s" % [
		Engine.get_version_info().string,
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		DisplayServer.get_name(),
		root.size,
	])
	print("ARENA AUDIT: nodes=%d node3d=%d meshes=%d materials=%d lights=%d shadow_lights=%d particles=%d static_bodies=%d collisions=%d" % [
		counts.nodes,
		counts.node3d,
		counts.meshes,
		counts.materials,
		counts.lights,
		counts.shadow_lights,
		counts.particles,
		counts.static_bodies,
		counts.collisions,
	])
	print("ARENA AUDIT: avg_fps=%.1f avg_process_ms=%.3f avg_physics_ms=%.3f avg_draw_calls=%.1f avg_primitives=%.1f" % [
		totals.fps / SAMPLE_FRAMES,
		totals.process_ms / SAMPLE_FRAMES,
		totals.physics_ms / SAMPLE_FRAMES,
		totals.draw_calls / SAMPLE_FRAMES,
		totals.primitives / SAMPLE_FRAMES,
	])
	quit(0)


func _count_scene(scene: Node) -> Dictionary:
	var counts := {
		"nodes": 0,
		"node3d": 0,
		"meshes": 0,
		"materials": 0,
		"lights": 0,
		"shadow_lights": 0,
		"particles": 0,
		"static_bodies": 0,
		"collisions": 0,
	}
	var material_ids := {}
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		counts.nodes += 1
		if node is Node3D:
			counts.node3d += 1
		if node is MeshInstance3D:
			counts.meshes += 1
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.material_override != null:
				material_ids[mesh_instance.material_override.get_instance_id()] = true
			if mesh_instance.mesh != null:
				for surface in range(mesh_instance.mesh.get_surface_count()):
					var surface_material := mesh_instance.mesh.surface_get_material(surface)
					if surface_material != null:
						material_ids[surface_material.get_instance_id()] = true
		if node is Light3D:
			counts.lights += 1
			if (node as Light3D).shadow_enabled:
				counts.shadow_lights += 1
		if node is GPUParticles3D:
			counts.particles += 1
		if node is StaticBody3D:
			counts.static_bodies += 1
		if node is CollisionShape3D:
			counts.collisions += 1
		for child in node.get_children():
			pending.append(child)
	counts.materials = material_ids.size()
	return counts
