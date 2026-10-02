extends Node3D

@export var follow_speed := 8.0
@export var aim_smoothing_speed := 4.0
@export var look_ahead_distance := 0.9
@export var max_aim_pan_speed := 1.8

var _target: Node3D
var _camera: Camera3D
var _follow_offset := Vector3.ZERO
var _smoothed_aim := Vector3.ZERO
var _follow_position := Vector3.ZERO
var _aim_offset := Vector3.ZERO
var _shake_time := 0.0
var _shake_strength := 0.0
var _focus_target: Node3D
var _focus_time := 0.0
var _focus_start_position := Vector3.ZERO
var _focus_start_camera_position := Vector3.ZERO
var _focus_start_fov := 38.0
const FOCUS_DURATION := 1.45


func _ready() -> void:
	_resolve_camera()


func set_target(target: Node3D) -> void:
	reset_focus()
	_target = target
	global_position = target.global_position + _follow_offset
	_follow_position = global_position
	_aim_offset = Vector3.ZERO
	if "aim_direction" in _target:
		_smoothed_aim = _target.aim_direction
	_resolve_camera()
	_aim_camera()


func set_follow_offset(offset: Vector3, snap: bool = false) -> void:
	_follow_offset = offset
	if not snap or _target == null:
		return
	var target_aim := Vector3.ZERO
	if "aim_direction" in _target:
		target_aim = _target.aim_direction
	_smoothed_aim = target_aim
	global_position = _target.global_position + target_aim * look_ahead_distance + _follow_offset
	global_position.y = 0.0
	_follow_position = _target.global_position + _follow_offset
	_follow_position.y = 0.0
	_aim_offset = target_aim * look_ahead_distance
	_aim_camera()


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	_resolve_camera()
	if _focus_target != null and is_instance_valid(_focus_target):
		_focus_time = minf(FOCUS_DURATION, _focus_time + delta)
		var progress := _focus_time / FOCUS_DURATION
		var eased := 1.0 - pow(1.0 - progress, 3.0)
		var focus_position := _focus_target.global_position
		focus_position.y = 0.0
		global_position = _focus_start_position.lerp(focus_position, eased)
		if _camera != null:
			_camera.position = _focus_start_camera_position.lerp(Vector3(0.0, 9.0, 8.0), eased)
			_camera.fov = lerpf(_focus_start_fov, 35.0, eased)
			_camera.look_at(_focus_target.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		return
	var target_aim := Vector3.ZERO
	if "aim_direction" in _target:
		target_aim = _target.aim_direction
	_smoothed_aim = _smoothed_aim.lerp(target_aim, 1.0 - exp(-aim_smoothing_speed * delta))
	var desired := _target.global_position + _follow_offset
	desired.y = 0.0
	_follow_position = _follow_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	# Aim panning has its own bounded speed; body follow never inherits shake.
	var desired_aim_offset := _smoothed_aim * look_ahead_distance
	_aim_offset = _aim_offset.move_toward(desired_aim_offset, max_aim_pan_speed * delta)
	global_position = _follow_position + _aim_offset
	if _shake_time > 0.0:
		_shake_time -= delta
		var shake_offset := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * _shake_strength
		global_position += shake_offset
		_shake_strength = lerpf(_shake_strength, 0.0, 1.0 - exp(-18.0 * delta))
	_aim_camera()


func shake(duration: float, strength: float = 0.12) -> void:
	if _focus_target != null:
		return
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_meta("camera_shake_enabled") and not bool(scene.get_meta("camera_shake_enabled")):
		return
	_shake_time = maxf(_shake_time, duration)
	_shake_strength = maxf(_shake_strength, strength)


func focus_on_winner(winner: Node3D) -> void:
	if winner == null:
		return
	_resolve_camera()
	_focus_target = winner
	_focus_time = 0.0
	_focus_start_position = global_position
	_shake_time = 0.0
	_shake_strength = 0.0
	if _camera != null:
		_focus_start_camera_position = _camera.position
		_focus_start_fov = _camera.fov


func reset_focus() -> void:
	_focus_target = null
	_focus_time = 0.0
	_follow_position = global_position - _aim_offset
	_resolve_camera()
	if _camera != null:
		_camera.position = Vector3(0.0, 20.5, 17.5)
		_camera.fov = 38.0


func _resolve_camera() -> void:
	if _camera == null:
		_camera = get_node_or_null("Camera3D") as Camera3D


func _aim_camera() -> void:
	if _camera != null:
		_camera.look_at(global_position + Vector3(0.0, 0.45, 0.0), Vector3.UP)
