extends Node

## Five seconds of real articulated work, using the existing scanner and servo.
signal completed
signal cancelled
const SCANNER := preload("res://scripts/forge_manual_scanner.gd")
const DURATION := 5.0
var stage
var focus
var scanner: SCANNER
var active := false
var elapsed := 0.0
var visited_parts: Array[String] = []
var scanned_parts: Array[String] = []
var _camera: Transform3D
var _phase := -1
var _targets: Array[Dictionary] = []
var _first_process := false


func configure(garage_stage: Node, equipment_focus: Node) -> void:
	stage = garage_stage
	focus = equipment_focus


func _ready() -> void:
	process_priority = 4
	scanner = SCANNER.new()
	scanner.name = "InstallationScanner"
	scanner.configure(stage)
	stage.world.add_child(scanner)
	set_process(false)


func begin(equipment: Dictionary) -> bool:
	if active or not stage.is_visible_in_tree():
		return false
	focus.show_overview(false)
	focus.set_process(false)
	_camera = stage.camera.global_transform
	stage.camera.position = Vector3(0.7, 2.6, 8.1)
	stage.camera.look_at(Vector3(0.75, 1.65, 0))
	stage.set_equipment_focus(true)
	scanner.set_enabled(true)
	scanner.set_process(false)
	scanner.motion_speed = 1.8
	if not scanner.enabled:
		_restore()
		return false
	# Defense and passive share the core; weapon/offense share the arm.
	_targets = [
		{"part": "TORSE", "bone": "spine1", "offset": Vector3(0.15, 0.06, 0.29)},
		{"part": "BRAS", "bone": "leftarm", "offset": Vector3(0.04, -0.15, 0.26)},
		{"part": "JAMBES", "bone": "leftleg", "offset": Vector3(0.05, -0.03, 0.22)},
	]
	if str(equipment.mobility) == "bio_injector":
		_targets[2] = {"part": "RÉACTEUR", "bone": "spine", "offset": Vector3(0.12, -0.09, 0.29)}
	active = true
	_first_process = true
	elapsed = 0.0
	_phase = -1
	visited_parts.clear()
	scanned_parts.clear()
	set_process(true)
	return true


func _process(delta: float) -> void:
	# A click can start the installation late in a frame; that elapsed time
	# belongs to the menu. Start measuring on the following process tick.
	if _first_process:
		_first_process = false
		return
	advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	elapsed = minf(elapsed + delta, DURATION)
	var phase := mini(3, int(elapsed / 1.25))
	if phase != _phase:
		_phase = phase
		if phase < _targets.size():
			visited_parts.append(str(_targets[phase].part))
		else:
			scanner.retract()
	if phase < _targets.size():
		var target: Dictionary = _targets[phase]
		var point: Vector3 = focus.anchor(str(target.bone), target.offset)
		scanner.point_at_surface(point, Vector3.BACK, str(target.part))
	scanner.advance(delta)
	if scanner.scanning and not scanned_parts.has(scanner.target_zone):
		scanned_parts.append(scanner.target_zone)
	if elapsed >= DURATION:
		active = false
		_restore()
		completed.emit()


func cancel() -> void:
	if not active:
		return
	active = false
	_restore()
	cancelled.emit()


func _restore() -> void:
	scanner.set_enabled(false)
	scanner.set_process(false)
	stage.set_equipment_focus(false)
	stage.camera.global_transform = _camera
	stage.camera.fov = focus._base_fov
	focus.set_process(stage.is_visible_in_tree())
	set_process(false)


func _exit_tree() -> void:
	if active:
		_restore()
	if is_instance_valid(scanner):
		scanner.queue_free()
