extends StaticBody3D

## An arena receiver, not a combatant. Physical shots and melee can turn it;
## all time and eligibility are owned by the round's solar controller.
const TURN_SECONDS := 0.8
const LOCK_SECONDS := 2.0
var controller: Node3D
var mirror_index := 0
var preset := 0
var pending := -1
var turn_remaining := 0.0
var locked_remaining := 0.0
var rotations := 0
var illuminated := false
var pivot: Node3D
var lamp: StandardMaterial3D
var _start_angle := 0.0
var _credited: Dictionary = {}

func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	name = "SolarMirror%d" % (mirror_index + 1)
	add_to_group("solar_mirrors")
	var target_shape := BoxShape3D.new()
	target_shape.size = Vector3(1.65, 1.85, 1.65)
	var target_collision := CollisionShape3D.new()
	target_collision.position.y = 1.12
	target_collision.shape = target_shape
	add_child(target_collision)
	var brass: StandardMaterial3D = controller.call("_material", Color("#a77b46"), 0.43)
	var dark: StandardMaterial3D = controller.call("_material", Color("#304b50"), 0.55)
	var glass: StandardMaterial3D = controller.call("_material", Color("#55c5cb"), 0.24, Color("#55c5cb"), 0.18)
	lamp = controller.call("_material", Color("#ffc85f"), 0.4, Color("#ffc85f"), 0.6)
	var pedestal := StaticBody3D.new()
	pedestal.name = "MirrorPedestal"
	pedestal.collision_layer = 1
	pedestal.collision_mask = 0
	pedestal.add_to_group("arena_solid")
	var base_shape := CylinderShape3D.new()
	base_shape.radius = 0.70
	base_shape.height = 0.8
	var base_collision := CollisionShape3D.new()
	base_collision.shape = base_shape
	base_collision.position.y = 0.4
	pedestal.add_child(base_collision)
	add_child(pedestal)
	controller.call("_cylinder", self, Vector3(0, 0.14, 0), 0.88, 0.28, brass)
	controller.call("_cylinder", self, Vector3(0, 0.56, 0), 0.22, 0.75, dark)
	pivot = Node3D.new()
	pivot.name = "PivotingReflector"
	pivot.position.y = 1.45
	add_child(pivot)
	controller.call("_box", pivot, Vector3.ZERO, Vector3(1.7, 1.8, 0.16), brass)
	controller.call("_box", pivot, Vector3(0, 0, 0.10), Vector3(1.45, 1.55, 0.05), glass)
	controller.call("_box", pivot, Vector3(0, 0, -0.10), Vector3(1.45, 1.55, 0.05), glass)
	# A bright command hub is visible and hittable from both sides of the panel.
	for side in [-1.0, 1.0]:
		var button: MeshInstance3D = controller.call("_box", pivot, Vector3(0, -0.38, side * 0.15), Vector3(0.38, 0.38, 0.10), lamp)
		button.rotation.z = PI * 0.25
	for index in range(3):
		controller.call("_box", self, Vector3((index - 1) * 0.30, 0.30, 0.68), Vector3(0.10, 0.07, 0.19), lamp)
	reset_round()

func direction_for(index: int) -> Vector2:
	var toward_center := -Vector2(position.x, position.z).normalized()
	return toward_center.rotated(deg_to_rad([-28.0, 0.0, 28.0][index]))

func get_direction() -> Vector2:
	return direction_for(preset)

func next_direction() -> Vector2:
	return direction_for((preset + 1) % 3)

func can_turn() -> bool:
	return pending < 0 and locked_remaining <= 0.0 and is_instance_valid(controller) and bool(controller.call("solar_controls_live"))

func projectile_impact(_at: Vector3) -> void:
	request_turn()

func take_damage(_amount: float, _source: String = "", attack_id: String = "") -> float:
	if attack_id != "" and _credited.has(attack_id):
		return 0.0
	if request_turn() and attack_id != "":
		_credited[attack_id] = true
	return 0.0

func get_training_hit_radius() -> float:
	return 0.82

func request_turn() -> bool:
	if not can_turn():
		return false
	pending = (preset + 1) % 3
	turn_remaining = TURN_SECONDS
	locked_remaining = TURN_SECONDS + LOCK_SECONDS
	_start_angle = pivot.rotation.y
	controller.call("mirror_turn_announced", self)
	return true

func advance(delta: float) -> void:
	locked_remaining = maxf(0.0, locked_remaining - delta)
	if pending >= 0:
		turn_remaining = maxf(0.0, turn_remaining - delta)
		var dir := direction_for(pending)
		pivot.rotation.y = lerp_angle(_start_angle, atan2(dir.x, dir.y), 1.0 - turn_remaining / TURN_SECONDS)
		if turn_remaining <= 0.0:
			preset = pending
			pending = -1
			rotations += 1
			controller.call("mirror_turn_completed", self)
	lamp.emission_energy_multiplier = 1.8 if pending >= 0 else (1.0 if can_turn() else 0.12)

func reset_round() -> void:
	preset = 1
	pending = -1
	turn_remaining = 0.0
	locked_remaining = 0.0
	rotations = 0
	illuminated = false
	_credited.clear()
	if is_instance_valid(pivot):
		var dir := get_direction()
		pivot.rotation.y = atan2(dir.x, dir.y)
