extends StaticBody3D

## The visible spindle is also the receiver. It has no health or combat reward.
var mechanism: Node3D
var _lamp: StandardMaterial3D
var _cap: Node3D
var _label: Label3D
var _ticks: Node3D
var _credited: Dictionary = {}

func _ready() -> void:
	name = "ClockSpindle"
	collision_layer = 1 | 8
	collision_mask = 0
	add_to_group("arena_solid")
	var shape := CylinderShape3D.new()
	shape.radius = 1.0
	shape.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	var controller: Node3D = mechanism.get("controller")
	_lamp = controller.call("_material", Color("#65e8d1"), 0.3, Color("#65e8d1"), 1.0)
	var brass: StandardMaterial3D = controller.call("_material", Color("#c99c52"), 0.35)
	_cap = Node3D.new()
	_cap.name = "StrikeCommand"
	add_child(_cap)
	controller.call("_cylinder", _cap, Vector3(0, 1.54, 0), 1.0, 0.22, brass)
	controller.call("_cylinder", _cap, Vector3(0, 1.68, 0), 0.82, 0.10, _lamp)
	var gem: MeshInstance3D = controller.call("_box", _cap, Vector3(0, 1.84, 0), Vector3(0.44, 0.20, 0.44), brass)
	gem.rotation.y = PI * 0.25
	_ticks = Node3D.new()
	_ticks.name = "CommandDial"
	add_child(_ticks)
	for index in range(12):
		var angle := float(index) * TAU / 12.0
		var tick: Node3D = controller.call("_box", _ticks, Vector3(cos(angle) * 1.14, 1.63, sin(angle) * 1.14), Vector3(0.07, 0.07, 0.24), _lamp)
		tick.rotation.y = PI * 0.5 - angle
	_label = Label3D.new()
	_label.name = "ClockCommandReadout"
	_label.position.y = 5.0
	_label.font_size = 40
	_label.pixel_size = 0.010
	_label.outline_size = 7
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)
	var main := controller.get_parent()
	if main != null and "_arena_blockers" in main:
		main.get("_arena_blockers").append(self)

func projectile_impact(_at: Vector3) -> void:
	mechanism.call("request_sweep")

func take_damage(_amount: float, _source: String = "", attack_id: String = "") -> float:
	if attack_id != "" and _credited.has(attack_id):
		return 0.0
	if bool(mechanism.call("request_sweep")) and attack_id != "":
		_credited[attack_id] = true
	return 0.0

func get_training_hit_radius() -> float:
	return 1.0

func reset_round() -> void:
	_credited.clear()

func update_state(phase: String, remaining: float, clock: float) -> void:
	var ready := phase == "ready"
	var tint := Color("#65e8d1") if ready else (Color("#ffbe50") if phase == "warning" else Color("#776a64"))
	_lamp.albedo_color = tint
	_lamp.emission = tint
	_lamp.emission_energy_multiplier = 0.8 + sin(clock * 4.0) * 0.25 if ready else (1.2 + sin(clock * 14.0) * 0.45 if phase == "warning" else 0.10)
	_cap.position.y = -0.15 * sin(clampf((1.8 - remaining) / 0.3, 0.0, 1.0) * PI) if phase == "warning" else 0.0
	_ticks.rotation.y = clock * 0.55 if phase == "warning" else 0.0
	_label.modulate = tint
	match phase:
		"ready": _label.text = "BALANCIER PRÊT\nFRAPPE LE CŒUR"
		"warning": _label.text = "BALAYAGE DANS %.1f s" % remaining
		"sweep": _label.text = "BALAYAGE"
		"cover_warning", "rotate": _label.text = "ROTATION DES ABRIS"
		_: _label.text = "ARMEMENT · %.0f s" % ceilf(remaining)
