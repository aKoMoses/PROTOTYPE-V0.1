extends RefCounted
## Batched visual contact shading, independent of map layout and collision ownership.
const CONTACT := preload("res://art/environment/reference_finish/contact.gdshader")

static func build(parent: Node3D, entries: Array[Node3D], ground_height: float = 0.012, spread: float = 1.6) -> MultiMeshInstance3D:
	var footprints: Array[Dictionary] = []
	for body in entries:
		var collision := box_collision(body)
		if collision == null:
			continue
		var shape := collision.shape as BoxShape3D
		var pose := body.global_transform * collision.transform
		pose.origin.y = ground_height
		footprints.append({"pose": pose, "size": Vector2(shape.size.x, shape.size.z)})
	return build_footprints(parent, footprints, spread)

static func build_footprints(parent: Node3D, footprints: Array[Dictionary], spread: float = 1.6) -> MultiMeshInstance3D:
	# Explicit render footprints also support convex planters without fake bodies.
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = PlaneMesh.new()
	(instances.mesh as PlaneMesh).size = Vector2.ONE
	instances.instance_count = footprints.size()
	for index in footprints.size():
		var footprint: Dictionary = footprints[index]
		var size: Vector2 = footprint.size
		var extent := size + Vector2.ONE * spread
		var pose: Transform3D = footprint.pose
		pose.basis = pose.basis * Basis.from_scale(Vector3(extent.x, 1.0, extent.y))
		instances.set_instance_transform(index, parent.global_transform.affine_inverse() * pose)
		instances.set_instance_custom_data(index, Color(size.x, size.y, extent.x, extent.y))
	var contacts := MultiMeshInstance3D.new()
	contacts.name = "CoverContactOcclusion"
	contacts.multimesh = instances
	var material := ShaderMaterial.new()
	material.shader = CONTACT
	contacts.material_override = material
	contacts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(contacts)
	parent.set_meta("contact_instances", footprints.size())
	return contacts

static func box_collision(body: Node3D) -> CollisionShape3D:
	var named := body.get_node_or_null("Collision") as CollisionShape3D
	if named != null and named.shape is BoxShape3D:
		return named
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return child
	return null
