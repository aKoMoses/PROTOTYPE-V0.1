extends Node

## The three seconds count actual work after reaching the selected accessory.
signal completed(identifier: String)
const WORK_TIME := 3.0
const APPROACH_LIMIT := 2.5
const RETURN_TIME := 0.55

# The existing scanner uses one fixed wrist orientation. Try other valid tool
# orientations to reach the ankle, keeping all its joint/collision limits.
class ModuleScanner extends "res://scripts/forge_manual_scanner.gd":
	func solve_pose(target: Vector3) -> Dictionary:
		var offset: Vector3 = target - _joints[1].global_position
		var yaw := atan2(offset.z, -offset.x)
		for degrees in [100.0, 120.0, 140.0, 80.0, 60.0]:
			var end_angle := deg_to_rad(degrees)
			var horizontal := Vector2(offset.x, offset.z).length() - _lengths.z * sin(end_angle)
			var vertical := offset.y - _lengths.z * cos(end_angle)
			var cosine := (horizontal * horizontal + vertical * vertical - _lengths.x * _lengths.x - _lengths.y * _lengths.y) / (2.0 * _lengths.x * _lengths.y)
			if cosine < -1.0 or cosine > 1.0:
				continue
			var elbow := acos(cosine)
			var shoulder := atan2(horizontal, vertical) - atan2(_lengths.y * sin(elbow), _lengths.x + _lengths.y * cos(elbow))
			var angles := Vector4(yaw, shoulder, elbow, end_angle - shoulder - elbow)
			var valid := true
			for index in 4:
				valid = valid and is_finite(angles[index]) and angles[index] >= deg_to_rad(LIMITS[index].x) and angles[index] <= deg_to_rad(LIMITS[index].y)
			if valid and pose_is_clear(angles):
				return {"angles": angles}
		return {}

var stage
var focus
var scanner: ModuleScanner
var active := false
var equipment_id := ""
var phase := ""
var worked_seconds := 0.0
var elapsed := 0.0
var reached_module := false
var _return_elapsed := 0.0


func configure(garage_stage: Node, equipment_focus: Node) -> void:
	stage = garage_stage
	focus = equipment_focus


func _ready() -> void:
	process_priority = 3
	scanner = ModuleScanner.new()
	scanner.name = "ModuleInstallationScanner"
	scanner.configure(stage)
	stage.world.add_child(scanner)
	set_process(false)


func begin(identifier: String) -> bool:
	if identifier not in ["pyro_boots", "bio_injector"] or not stage.is_visible_in_tree():
		return false
	cancel(false)
	equipment_id = identifier
	focus.show_equipment("mobility", identifier, false)
	scanner.set_enabled(true)
	scanner.set_process(false)
	scanner.motion_speed = 2.1
	if not scanner.enabled:
		focus.show_overview()
		return false
	active = true
	phase = "approach"
	worked_seconds = 0.0
	elapsed = 0.0
	_return_elapsed = 0.0
	reached_module = false
	set_process(true)
	return true


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	if not scanner.enabled or not stage.is_visible_in_tree():
		cancel()
		return
	elapsed += delta
	if phase == "return":
		scanner.advance(delta)
		_return_elapsed += delta
		if _return_elapsed >= RETURN_TIME:
			_finish()
		return
	var point: Vector3 = stage.module_visuals.service_point(equipment_id)
	# The subtle wrist sweep stays on the physical housing, rather than orbiting
	# a whole body zone. A standoff beam avoids intersecting the robot mesh.
	var rotation: Basis = stage.robot.global_basis.orthonormalized()
	point += rotation * Vector3(sin(worked_seconds * 4.0) * 0.012, sin(worked_seconds * 5.0) * 0.010, 0)
	scanner.point_at_surface(point, rotation * Vector3.BACK, "PYROBOOTS" if equipment_id == "pyro_boots" else "BIO INJECTOR")
	var step := minf(delta, WORK_TIME - worked_seconds)
	scanner.advance(step)
	if scanner.scanning:
		reached_module = true
		phase = "work"
		worked_seconds = minf(WORK_TIME, worked_seconds + step)
		stage.arm.manual_phase = "INSTALLATION · " + ("PYROBOOTS" if equipment_id == "pyro_boots" else "BIO INJECTOR")
	if worked_seconds >= WORK_TIME:
		phase = "return"
		scanner.retract()
	elif not reached_module and elapsed >= APPROACH_LIMIT:
		# A cancelled/invalid trajectory cannot hold the garage indefinitely.
		cancel()


func cancel(overview: bool = true) -> void:
	if not active:
		return
	active = false
	phase = ""
	scanner.set_enabled(false)
	scanner.set_process(false)
	if overview:
		focus.show_overview()
	set_process(false)


func _finish() -> void:
	active = false
	phase = ""
	scanner.set_enabled(false)
	scanner.set_process(false)
	focus.show_overview()
	set_process(false)
	completed.emit(equipment_id)


func _exit_tree() -> void:
	cancel(false)
	if is_instance_valid(scanner):
		scanner.queue_free()
