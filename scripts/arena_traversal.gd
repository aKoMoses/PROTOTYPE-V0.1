extends RefCounted

## Optional height field used only by the solo test arena. Other maps stay flat.
static func terrain(actor: Node) -> Node3D:
	if not actor.is_inside_tree():
		return null
	var scene := actor.get_tree().current_scene
	if scene == null or scene.get("arena_variant") != "test":
		return null
	return scene.get_node_or_null("TestArena") as Node3D


static func height(actor: Node, point: Vector3) -> float:
	var surface := terrain(actor)
	return float(surface.call("height_at", point)) if surface != null else 0.0


static func snap(actor: Node3D) -> void:
	actor.global_position.y = height(actor, actor.global_position)


static func motion(actor: Node3D, requested: Vector3) -> Vector3:
	var surface := terrain(actor)
	if surface == null:
		return requested
	var origin := actor.global_position
	var result := requested
	result.y = 0.0
	if not bool(surface.call("segment_walkable", origin, origin + result)):
		# Slide along a ledge rather than climbing its vertical face.
		result = Vector3(requested.x, 0, 0)
		if not bool(surface.call("segment_walkable", origin, origin + result)):
			result = Vector3(0, 0, requested.z)
			if not bool(surface.call("segment_walkable", origin, origin + result)):
				return Vector3.ZERO
	result.y = height(actor, origin + result) - origin.y
	return result


static func exclusions(actor: Node) -> Array[RID]:
	var surface := terrain(actor)
	var result: Array[RID] = []
	if surface != null:
		for body in surface.get("surfaces"):
			result.append(body.get_rid())
	return result


static func shot_direction(actor: Node3D, start: Vector3, direction: Vector3) -> Vector3:
	if terrain(actor) == null:
		return direction
	var scene := actor.get_tree().current_scene
	var opponent: Node3D = scene.get("target") if actor == scene.get("player") else scene.get("player")
	if not is_instance_valid(opponent) or absf(opponent.global_position.y - actor.global_position.y) < 0.1:
		return direction
	if opponent.has_method("is_visible_to") and not bool(opponent.call("is_visible_to", actor)):
		return direction
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	var offset := opponent.global_position - start
	var distance := Vector2(offset.x, offset.z).dot(Vector2(flat.x, flat.z))
	var side := absf(offset.x * flat.z - offset.z * flat.x)
	if distance <= 0.1 or side > 0.65:
		return direction
	# Keep horizontal aim/spread; only pitch toward an aligned visible torso.
	return (flat * distance + Vector3.UP * (opponent.global_position.y + 0.9 - start.y)).normalized()
