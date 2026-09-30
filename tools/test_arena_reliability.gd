extends SceneTree

# Verifies the parts of the arena clean-up that are intentionally outside the
# frozen gameplay contract: visible/collision agreement, grounded vegetation,
# protected spawns/pads, and the replaceable exterior branch.

const EXPECTED_BLOCKERS := 48
const EXPECTED_BUSHES := 14
const MINIMUM_EXTERIOR_SIZE := 120.0
const MAXIMUM_EXTERIOR_MESHES := 160

var _failures: Array[String] = []


func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	var blockers: Array[Node] = get_nodes_in_group("arena_solid")
	_check(blockers.size() == EXPECTED_BLOCKERS, "expected %d arena blockers, found %d" % [EXPECTED_BLOCKERS, blockers.size()])
	for blocker_node in blockers:
		_validate_blocker(blocker_node as StaticBody3D)

	var bushes: Array[Node] = get_nodes_in_group("bush_placeholder")
	_check(bushes.size() == EXPECTED_BUSHES, "expected %d bushes, found %d" % [EXPECTED_BUSHES, bushes.size()])
	for bush_node in bushes:
		_validate_bush(bush_node as Node3D, blockers)

	_validate_access(scene, blockers)
	_validate_representative_impacts(scene)
	await _validate_navigation_volume(scene)
	_validate_exterior(scene)

	if not _failures.is_empty():
		for failure in _failures:
			push_error("ARENA RELIABILITY: %s" % failure)
		quit(1)
		return
	print("ARENA RELIABILITY: PASS (%d blockers, %d grounded bushes, exterior <= %d meshes)" % [
		blockers.size(),
		bushes.size(),
		MAXIMUM_EXTERIOR_MESHES,
	])
	quit(0)


func _validate_blocker(body: StaticBody3D) -> void:
	_check(body != null, "arena_solid contains a non-StaticBody3D node")
	if body == null:
		return
	_check(body.collision_layer == 1, "%s is not on environment collision layer 1" % body.name)
	_check(bool(body.get_meta("blocks_navigation", false)), "%s is not marked as a navigation blocker" % body.name)
	_check(bool(body.get_meta("blocks_projectiles", false)), "%s is not marked as a projectile blocker" % body.name)
	_check(bool(body.get_meta("blocks_line_of_sight", false)), "%s is not marked as a line-of-sight blocker" % body.name)
	var collision := body.get_node_or_null("Collision") as CollisionShape3D
	_check(collision != null and collision.shape is BoxShape3D, "%s has no simple box collision" % body.name)
	if collision == null or not collision.shape is BoxShape3D:
		return
	var shape := collision.shape as BoxShape3D
	var bottom := body.position.y + collision.position.y - shape.size.y * 0.5
	_check(bottom >= -0.20 and bottom <= 0.03, "%s is not grounded (bottom %.3f)" % [body.name, bottom])
	if bool(body.get_meta("invisible_safety_limit", false)):
		return
	var visual := body.get_node_or_null("CollisionMatchedVisual") as MeshInstance3D
	_check(visual != null and visual.mesh != null, "%s has no collision-matched visible shell" % body.name)
	if visual != null and visual.mesh != null:
		# Accept the reusable bevelled shell while comparing its real transformed
		# bounds with the collider. Mesh resource type cannot prove volume parity.
		var visible_bounds: AABB = visual.global_transform * visual.mesh.get_aabb()
		var collision_bounds: AABB = collision.global_transform * AABB(-shape.size * 0.5, shape.size)
		_check(visible_bounds.position.distance_to(collision_bounds.position) <= 0.035 and visible_bounds.size.distance_to(collision_bounds.size) <= 0.035, "%s visible shell and collision bounds differ" % body.name)


func _validate_bush(bush: Node3D, blockers: Array[Node]) -> void:
	_check(bush != null, "bush_placeholder contains a non-Node3D node")
	if bush == null:
		return
	var visual_root := bush.get_node_or_null("GroundedVegetation") as Node3D
	_check(visual_root != null, "%s has no grounded visual root" % bush.name)
	_check(not _has_collision_descendant(bush), "%s unexpectedly creates collision" % bush.name)
	var visual_position: Vector3 = bush.get_meta("bush_visual_position", bush.global_position)
	var base_radius := float(bush.get_meta("bush_base_radius", 0.0))
	_check(base_radius > 0.0, "%s has no base radius" % bush.name)
	_check(_base_is_clear(visual_position, base_radius, blockers), "%s base intersects a solid or protected pad" % bush.name)


func _validate_access(scene: Node, blockers: Array[Node]) -> void:
	var player := scene.get_node_or_null("Player") as Node3D
	var target := scene.get_node_or_null("TargetDummy") as Node3D
	_check(player != null and _point_is_clear(player.global_position, 0.60, blockers), "player spawn is obstructed")
	_check(target != null and _point_is_clear(target.global_position, 0.75, blockers), "bot spawn is obstructed")
	for pad_node in get_nodes_in_group("health_kit_placeholder"):
		var pad := pad_node as Node3D
		_check(pad != null and _point_is_clear(pad.global_position, 1.72, blockers), "%s is not accessible" % pad_node.name)


func _validate_representative_impacts(scene: Node) -> void:
	var world: World3D = scene.get_world_3d()
	_check(world != null, "arena has no World3D")
	if world == null:
		return
	for blocker_name in ["NorthCenterCover", "WestSpine", "NorthWestAngle", "EastPocketLong", "SouthEastBlock"]:
		var body := scene.get_node_or_null(blocker_name) as StaticBody3D
		_check(body != null, "%s is missing" % blocker_name)
		if body == null:
			continue
		var collision := body.get_node_or_null("Collision") as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var size := (collision.shape as BoxShape3D).size
		var local_normal := Vector3.BACK if size.x >= size.z else Vector3.RIGHT
		var normal := (body.global_basis * local_normal).normalized()
		var half_depth := (size.z if size.x >= size.z else size.x) * 0.5
		var centre := body.global_position + Vector3.UP * 0.72
		var query := PhysicsRayQueryParameters3D.create(centre + normal * (half_depth + 0.8), centre - normal * (half_depth + 0.8))
		query.collision_mask = 1
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		_check(not hit.is_empty() and hit.get("collider") == body, "%s does not receive shots on its visible face" % blocker_name)


func _validate_navigation_volume(scene: Node) -> void:
	var bot_body := scene.get_node_or_null("TargetDummy") as Node3D
	var controller := scene.get_node_or_null("TargetDummy/TrainingBot")
	_check(bot_body != null and controller != null, "bot navigation controller is missing")
	if bot_body == null or controller == null:
		return
	var previous_position := bot_body.global_position
	bot_body.global_position = Vector3(0.0, 0.0, -7.42)
	await physics_frame
	var into_cover := bool(controller.call("_navigation_motion_is_clear", bot_body, Vector3(0.0, 0.0, -0.40)))
	var along_cover := bool(controller.call("_navigation_motion_is_clear", bot_body, Vector3(0.40, 0.0, 0.0)))
	_check(not into_cover, "bot navigation volume can enter NorthCenterCover")
	_check(along_cover, "bot navigation volume cannot follow a valid cover edge")
	bot_body.global_position = previous_position
	await physics_frame


func _validate_exterior(scene: Node) -> void:
	var exterior := scene.get_node_or_null("ArenaExterior") as Node3D
	_check(exterior != null, "ArenaExterior branch is missing")
	if exterior == null:
		return
	_check(bool(exterior.get_meta("replaceable_environment", false)), "ArenaExterior is not marked replaceable")
	var terrain := exterior.get_node_or_null("ExteriorDustTerrain") as MeshInstance3D
	_check(terrain != null and float(terrain.get_meta("exterior_ground_size", 0.0)) >= MINIMUM_EXTERIOR_SIZE, "exterior terrain does not cover the camera field")
	_check(not _has_collision_descendant(exterior), "decorative exterior contains reachable collision")
	var mesh_count := _count_meshes(exterior)
	_check(mesh_count <= MAXIMUM_EXTERIOR_MESHES, "exterior mesh budget exceeded: %d" % mesh_count)
	for child in exterior.get_children():
		if not bool(child.get_meta("decorative_exterior", false)):
			continue
		var child_3d := child as Node3D
		_check(child_3d != null and maxf(absf(child_3d.position.x), absf(child_3d.position.z)) >= 29.5, "%s intrudes into the playable arena" % child.name)


func _base_is_clear(position: Vector3, radius: float, blockers: Array[Node]) -> bool:
	if not _point_is_clear(position, radius + 0.08, blockers):
		return false
	for zone in [Vector2(0.0, -20.8), Vector2(0.0, 20.8), Vector2(-21.0, 0.0), Vector2(21.0, 0.0)]:
		var zone_position: Vector2 = zone
		var delta: Vector2 = Vector2(position.x, position.z) - zone_position
		if absf(delta.x) <= 1.72 + radius and absf(delta.y) <= 1.72 + radius:
			return false
	return true


func _point_is_clear(position: Vector3, radius: float, blockers: Array[Node]) -> bool:
	for blocker_node in blockers:
		var body := blocker_node as StaticBody3D
		if body == null:
			continue
		var collision := body.get_node_or_null("Collision") as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var size := (collision.shape as BoxShape3D).size
		var relative := Vector2(position.x - body.position.x, position.z - body.position.z)
		relative = relative.rotated(deg_to_rad(-body.rotation_degrees.y))
		if absf(relative.x) <= size.x * 0.5 + radius and absf(relative.y) <= size.z * 0.5 + radius:
			return false
	return true


func _has_collision_descendant(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			return true
		if _has_collision_descendant(child):
			return true
	return false


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
