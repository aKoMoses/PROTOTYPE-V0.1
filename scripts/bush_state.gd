class_name BushState
extends RefCounted

## A bush is a vision region, never a solid obstacle. Its world footprint is
## shared by actors, AI and foliage so the visible grass is the hiding place.
const GROUP := "bush_placeholder"
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")


static func center(bush: Node3D) -> Vector3:
	if bush == null or not is_instance_valid(bush):
		return Vector3.ZERO
	return bush.get_meta("bush_center", bush.get_meta("bush_visual_position", bush.global_position)) as Vector3


static func radius(bush: Node3D) -> float:
	return maxf(0.0, float(bush.get_meta("bush_radius", 0.0))) if bush != null and is_instance_valid(bush) else 0.0


static func contains(bush: Node3D, world_position: Vector3) -> bool:
	var footprint := radius(bush)
	if footprint <= 0.0:
		return false
	var offset := world_position - center(bush)
	var height := float(bush.get_meta("bush_height", 2.35))
	return offset.y >= -0.4 and offset.y <= height and Vector2(offset.x, offset.z).length_squared() <= footprint * footprint


static func find_bush(actor: Node3D) -> Node3D:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return null
	for node in actor.get_tree().get_nodes_in_group(GROUP):
		var bush := node as Node3D
		if contains(bush, actor.global_position):
			return bush
	return null


static func shares_bush(target: Node3D, observer: Node3D) -> bool:
	if target == null or observer == null or not is_instance_valid(target) or not is_instance_valid(observer) or not target.is_inside_tree():
		return false
	# Check a common region rather than first-match identity: overlapping patches
	# must not make two actors standing together invisible to each other.
	for node in target.get_tree().get_nodes_in_group(GROUP):
		var bush := node as Node3D
		if contains(bush, target.global_position) and contains(bush, observer.global_position):
			return true
	return false


static func visible_to(target: Node3D, observer: Node3D, revealed: bool, line_of_sight: bool) -> bool:
	if observer == null or not is_instance_valid(observer) or target == observer:
		return true
	if VISIBILITY_STATE.range_weight(target, observer) <= 0.0:
		return false
	# Reveal removes foliage concealment only while the observer has clear sight.
	var in_bush := find_bush(target) != null
	return VISIBILITY_STATE.visible_to_observer(revealed, in_bush, line_of_sight, in_bush and shares_bush(target, observer))
