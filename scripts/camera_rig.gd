extends Node3D

@export var follow_speed := 3.2
@export var aim_smoothing_speed := 4.0
@export var look_ahead_distance := 1.6

var _target: Node3D
var _camera: Camera3D
var _smoothed_aim := Vector3.ZERO


func _ready() -> void:
	_resolve_camera()


func set_target(target: Node3D) -> void:
	_target = target
	global_position = target.global_position
	if "aim_direction" in _target:
		_smoothed_aim = _target.aim_direction
	_resolve_camera()
	_aim_camera()


func _process(delta: float) -> void:
	if _target == null:
		return
	_resolve_camera()
	var target_aim := Vector3.ZERO
	if "aim_direction" in _target:
		target_aim = _target.aim_direction
	_smoothed_aim = _smoothed_aim.lerp(target_aim, 1.0 - exp(-aim_smoothing_speed * delta))
	var desired := _target.global_position + _smoothed_aim * look_ahead_distance
	desired.y = 0.0
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	_aim_camera()


func _resolve_camera() -> void:
	if _camera == null:
		_camera = get_node_or_null("Camera3D") as Camera3D


func _aim_camera() -> void:
	if _camera != null:
		_camera.look_at(global_position + Vector3(0.0, 0.45, 0.0), Vector3.UP)
