extends SceneTree
## Deterministic footprint, grounding and quality check for the visual scene.


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var yard := load("res://scenes/environment/salvage_yard.tscn").instantiate() as Node3D
	root.add_child(yard)
	await process_frame
	var failures: Array[String] = []
	var triangle_count := 0
	var surface_count := 0
	var materials: Dictionary = {}
	for node in yard.find_children("*", "MeshInstance3D", true, false):
		var mesh := node.mesh as Mesh
		surface_count += mesh.get_surface_count()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangle_count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			var material := mesh.surface_get_material(surface)
			if material != null:
				materials[material.get_instance_id()] = material.resource_path
			for vertex in vertices:
				var point: Vector3 = node.global_transform * vertex
				if absf(point.x) < 29.4 and absf(point.z) < 29.4:
					failures.append("Playable footprint overlap: " + str(node.get_path()) + " " + str(point))
					break
				if point.y < -0.07:
					failures.append("Below exterior terrain: " + str(node.get_path()) + " " + str(point))
					break
	yard.set_quality(0, Vector2(0.94, -0.34), 0.65)
	await process_frame
	for particles in yard.find_children("*", "GPUParticles3D", true, false):
		if particles.emitting:
			failures.append("Low quality still emitting particles")
	if yard.is_processing():
		failures.append("Low quality still rotating fan")
	yard.set_quality(1, Vector2(0.94, -0.34), 0.65)
	print("YARD VALIDATION: ", triangle_count, " triangles; ", surface_count, " mesh surfaces; ", materials.size(), " unique static materials; low-quality emitters disabled; failure count=", failures.size())
	for failure in failures:
		push_error(failure)
	yard.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
