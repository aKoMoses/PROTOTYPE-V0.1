extends Node3D

## One readable number for any closely spaced damage on the same actor.

const MERGE_GAP := 0.22
const MAX_GROUP_AGE := 0.75

var total_damage := 0.0
var total_healing := 0.0
var hit_count := 0
var side := 1.0
var healing_mode := false
var is_critical := false
var _age := 0.0
var _idle := 0.0
var _punch := 0.0
var _label: Label3D
var _ghost: Label3D


func _ready() -> void:
	position = Vector3(side * 2.55, 2.35, 0.0)
	var main_color := Color("#72f0a5") if healing_mode else (Color("#ffe059") if is_critical else Color("#ff9a3e"))
	var ghost_color := Color(0.32, 1.0, 0.55, 0.34) if healing_mode else (Color(1.0, 0.88, 0.25, 0.45) if is_critical else Color(1.0, 0.34, 0.12, 0.38))
	_label = _make_label(main_color, 24 if is_critical else 19)
	add_child(_label)
	_ghost = _make_label(ghost_color, 28 if is_critical else 23)
	_ghost.position = Vector3(0.11, -0.10, 0.02)
	add_child(_ghost)


func can_merge() -> bool:
	return is_inside_tree() and _idle <= MERGE_GAP and _age <= MAX_GROUP_AGE


func add_damage(amount: float, critical: bool = false) -> void:
	total_damage += amount
	hit_count += 1
	_idle = 0.0
	if critical:
		is_critical = true
	_punch = 1.4 if is_critical else 1.0
	if is_critical and _label != null:
		_label.modulate = Color("#ffe059")
		if _ghost != null:
			_ghost.modulate = Color(1.0, 0.88, 0.25, 0.45)
	var value := "-%d%s" % [roundi(total_damage), "!" if is_critical else ""]
	_label.text = value
	_ghost.text = value


func add_healing(amount: float) -> void:
	total_healing += amount
	hit_count += 1
	_idle = 0.0
	_punch = 1.0
	var value := "+%d" % roundi(total_healing)
	_label.text = value
	_ghost.text = value


func _process(delta: float) -> void:
	_age += delta
	_idle += delta
	_punch = maxf(0.0, _punch - delta * 5.0)
	position.y = 2.35 + minf(_age, 0.8) * 0.72
	position.x = side * (2.55 + minf(_age, 0.8) * 0.18)
	var opacity := 1.0 - clampf((_idle - 0.30) / 0.48, 0.0, 1.0)
	_label.modulate.a = opacity
	_ghost.modulate.a = opacity * 0.38
	var size := 1.0 + 0.28 * _punch
	_label.scale = Vector3.ONE * size
	_ghost.scale = Vector3.ONE * (size + 0.05)
	if _idle >= 0.8:
		queue_free()


func _make_label(color: Color, outline: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 88
	label.pixel_size = 0.008
	label.outline_size = outline
	label.modulate = color
	return label
