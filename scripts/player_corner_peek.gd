extends Node

## Automatic upper-body opening at a real cover edge. No movement/input lock.
const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")
const MAX_OFFSET := 0.60
const COVER_DISTANCE := 1.15
const OPEN_DISTANCE := 1.65
const CLEARANCE_RADIUS := 0.10
const ENTER_SPEED := 3.5
const RETURN_SPEED := 4.5
const MAX_ROLL := 12.0

var player: PLAYER_STATE
var offset := Vector3.ZERO
var side := 0.0
var _last_position := Vector3.ZERO
var _last_weapon := ""
var _clearance := SphereShape3D.new()


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "CornerPeekComponent"
	_clearance.radius = CLEARANCE_RADIUS


func _eligible() -> bool:
	return player._weapon_id in ["blaster", "shotgun", "longshot"] and player._weapon_pose_uses_aim() and not player._action_incapacitated() and not player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE) and not player._shotgun_reloading and not player._dash_active and not player._round_warmup_active and player._get_actual_move_velocity().length() <= player.move_speed * 0.60 and player._visual_rig != null and player._visual_rig.skeleton != null


func reset() -> void:
	offset = Vector3.ZERO
	side = 0.0
	_last_position = player.global_position if player.is_inside_tree() else Vector3.ZERO
	_last_weapon = player._weapon_id
	_apply_pose()


func update(delta: float) -> void:
	if not _eligible() or player.global_position.distance_to(_last_position) > 0.9 or _last_weapon != player._weapon_id:
		reset()
		return
	_last_position = player.global_position
	var direction: Vector3 = player._normalized_aim_direction()
	var right := direction.cross(Vector3.UP).normalized()
	var origin := player.global_position + Vector3.UP * 0.9
	var muzzle: Node3D = player._visual_rig.get_weapon_muzzle(StringName(player._weapon_id))
	var barrel := muzzle.global_position - offset if muzzle != null else origin + direction * 0.7
	var radius := CLEARANCE_RADIUS
	if player._weapon_id == "longshot":
		radius = maxf(radius, float(player._longshot_definition.projectile_radius) * (float(player._longshot_definition.enhanced_size_multiplier) if player.is_longshot_enhanced_ready() else 1.0))
	var target := Vector3.ZERO
	# A nearby vertical face is required. A wide wall has no open candidate;
	# floors, distant walls and open ground cannot activate the pose.
	if _near_cover(origin, direction) or _near_cover(origin - right * 0.25, direction) or _near_cover(origin + right * 0.25, direction):
		var preferred := side if side != 0.0 else 1.0
		for candidate_side in [preferred, -preferred]:
			for distance in [0.25, 0.40, MAX_OFFSET]:
				var candidate: Vector3 = right * float(candidate_side) * float(distance)
				if _clear_segment(origin, origin + candidate, 1 | 8, radius) and _clear_segment(origin + candidate, barrel + candidate, 1 | 8, radius) and _clear_segment(barrel + candidate, barrel + candidate + direction * OPEN_DISTANCE, 1 | 8, radius):
					target = candidate
					break
			if not target.is_zero_approx():
				break
	var speed := RETURN_SPEED if target.is_zero_approx() else ENTER_SPEED
	offset = offset.move_toward(target, maxf(0.0, delta) * speed)
	# Moving cover or a turn must never carry the upper body through a wall.
	if not offset.is_zero_approx() and not _clear_segment(origin, origin + offset):
		offset = Vector3.ZERO
	side = signf(offset.dot(right)) if offset.length() > 0.01 else 0.0
	_apply_pose()


func _apply_pose() -> void:
	if player._visual_rig != null:
		player._visual_rig.set_corner_peek(offset, side * MAX_ROLL * offset.length() / MAX_OFFSET)


func _near_cover(origin: Vector3, direction: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * COVER_DISTANCE, 1 | 8, _exclusions())
	query.collide_with_areas = true
	query.hit_from_inside = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.4


func _exclusions() -> Array[RID]:
	return PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()])


func _clear_segment(start: Vector3, end: Vector3, mask: int = 1 | 8, radius: float = CLEARANCE_RADIUS) -> bool:
	_clearance.radius = maxf(CLEARANCE_RADIUS, radius)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = end - start
	query.collision_mask = mask
	query.collide_with_areas = true
	query.exclude = _exclusions()
	var space := player.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var travel := space.cast_motion(query)
	if travel[0] < 0.9999:
		return false
	query.transform.origin = end
	query.motion = Vector3.ZERO
	return space.intersect_shape(query, 1).is_empty()


func projectile_support_origin(radius: float = 0.0) -> Vector3:
	var origin := player.global_position + Vector3.UP * 0.9
	if offset.length() < 0.01 or not _eligible():
		return origin
	# First validate the lateral shoulder route, including actors and shields.
	# The weapon's existing muzzle guard validates the second leg to the barrel.
	return origin + offset if _clear_segment(origin, origin + offset, 1 | 2 | 4 | 8, radius) else origin


func snapshot() -> Dictionary:
	return {"offset": offset, "side": side, "active": offset.length() > 0.01}
