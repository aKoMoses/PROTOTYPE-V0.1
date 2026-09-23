extends Node3D

@export var follow_speed := 7.0
@export var look_ahead_distance := 1.8

var _target: Node3D
var _camera: Camera3D


func _ready() -> void:
	_resolve_camera()


func set_target(target: Node3D) -> void:
	_target = target
	global_position = target.global_position
	_resolve_camera()
	_aim_camera()


func _process(delta: float) -> void:
	if _target == null:
		return
	_resolve_camera()
	var aim := Vector3.ZERO
	if "aim_direction" in _target:
		aim = _target.aim_direction * look_ahead_distance
	var desired := _target.global_position + aim
	desired.y = 0.0
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	_aim_camera()


func _resolve_camera() -> void:
	if _camera == null:
		_camera = get_node_or_null("Camera3D") as Camera3D


func _aim_camera() -> void:
	if _camera != null:
		_camera.look_at(global_position + Vector3(0.0, 0.45, 0.0), Vector3.UP)
