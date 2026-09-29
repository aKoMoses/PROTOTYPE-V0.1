extends Node3D

## Advances a shot through world space and reports the first surface it actually crosses.
signal finished(hit: Dictionary, distance: float)

var _direction := Vector3.FORWARD
var _speed := 1.0
var _range := 1.0
var _distance := 0.0
var _collision_mask := 0
var _excluded: Array[RID] = []


func _ready() -> void:
	# Read collisions after actors have advanced for this physics tick.
	process_physics_priority = 20


func configure(direction: Vector3, speed: float, max_range: float, collision_mask: int, excluded: Array[RID]) -> void:
	_direction = direction.normalized()
	_speed = maxf(speed, 0.01)
	_range = maxf(max_range, 0.01)
	_collision_mask = collision_mask
	_excluded = excluded.duplicate()


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var step := minf(_speed * delta, _range - _distance)
	if step <= 0.0:
		_finish({})
		return
	var next_position := global_position + _direction * step
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position)
	query.collision_mask = _collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_distance += global_position.distance_to(hit["position"])
		global_position = hit["position"]
		_finish(hit)
		return
	global_position = next_position
	_distance += step
	if _distance >= _range - 0.0001:
		_finish({})


func _finish(hit: Dictionary) -> void:
	set_physics_process(false)
	finished.emit(hit, _distance)
	queue_free()
