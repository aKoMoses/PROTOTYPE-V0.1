extends Node3D

@export var follow_speed := 3.2
@export var aim_smoothing_speed := 4.0
@export var look_ahead_distance := 1.6

var _target: Node3D
var _camera: Camera3D
var _smoothed_aim := Vector3.ZERO
var _shake_time := 0.0
var _shake_strength := 0.0


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
	if _shake_time > 0.0:
		_shake_time -= delta
		var shake_offset := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * _shake_strength
		global_position += shake_offset
		_shake_strength = lerpf(_shake_strength, 0.0, 1.0 - exp(-18.0 * delta))
	_aim_camera()


func shake(duration: float, strength: float = 0.12) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_meta("camera_shake_enabled") and not bool(scene.get_meta("camera_shake_enabled")):
		return
	_shake_time = maxf(_shake_time, duration)
	_shake_strength = maxf(_shake_strength, strength)


func _resolve_camera() -> void:
	if _camera == null:
		_camera = get_node_or_null("Camera3D") as Camera3D


func _aim_camera() -> void:
	if _camera != null:
		_camera.look_at(global_position + Vector3(0.0, 0.45, 0.0), Vector3.UP)
