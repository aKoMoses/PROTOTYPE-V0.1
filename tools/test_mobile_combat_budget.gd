extends SceneTree
const BUDGET := preload("res://scripts/mobile_combat_budget.gd")
const ORGANIC := preload("res://scripts/environment/organic_world_details.gd")
var failures: Array[String] = []
var checks := 0

class Observer extends Node3D:
	func is_gameplay_enabled() -> bool: return true
class Rig extends Node3D:
	var _target: Node3D
class Manager extends Node:
	signal organic_contact(at: Vector3, normal: Vector3, surface: String, power: float)
	signal organic_shot(socket: Node3D, weapon: String, charge: float)
	signal organic_motion(at: Vector3, direction: Vector3, power: float)
	signal presentation_cleared
	var quality := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var observer := Observer.new()
	world.add_child(observer)
	var rig := Rig.new()
	rig.name = "CameraRig"
	rig._target = observer
	world.add_child(rig)
	var manager := Manager.new()
	world.add_child(manager)
	var scenery: Node3D = ORGANIC.new()
	scenery.set("manager", manager)
	world.add_child(scenery)
	var budget: Node = BUDGET.new()
	world.add_child(budget)
	budget.set_process(false)
	budget.call("register_node", scenery)
	check(not scenery.is_processing(), "cosmetic controller has one scheduled owner")
	var unrelated := Node.new()
	world.add_child(unrelated)
	unrelated.set_process(true)
	budget.call("register_node", unrelated)
	check(unrelated.is_processing(), "unlisted gameplay node keeps its own processing")
	for frame in 60: budget.call("_process", 1.0 / 60.0)
	var snapshot: Dictionary = budget.call("get_debug_snapshot")
	check(int(snapshot.updates) == 15, "one second of full-rate frames makes 15 cosmetic updates")
	check(is_equal_approx(float(scenery.get("_clock")), 1.0), "cosmetic time advances by elapsed simulation time")
	var clock := float(scenery.get("_clock"))
	paused = true
	budget.call("_process", 0.5)
	check(float(scenery.get("_clock")) == clock, "pause does not advance scenery")
	paused = false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	budget.call("_process", 0.5)
	check(float(scenery.get("_clock")) == clock, "disabled scene is not revived by the scheduler")
	world.process_mode = Node.PROCESS_MODE_INHERIT
	for frame in 4: budget.call("_process", 1.0 / 60.0)
	check(absf(float(scenery.get("_clock")) - clock - 1.0 / 15.0) < 0.0001, "resume has no hidden-time catch-up")
	scenery.hide()
	clock = float(scenery.get("_clock"))
	budget.call("_process", 0.5)
	check(float(scenery.get("_clock")) == clock, "hidden branch stops cosmetic work")
	scenery.show()
	world.remove_child(scenery)
	budget.call("_process", 0.1)
	check(scenery.is_processing(), "detached reusable branch recovers its original callback")
	world.add_child(scenery)
	budget.call("register_node", scenery)
	check(not scenery.is_processing(), "reattached branch can be scheduled again")
	scenery.free()
	budget.call("_process", 0.1)
	check(int(budget.call("get_debug_snapshot").controllers) == 0, "freed scene controller leaves no stale scheduled work")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("MOBILE COMBAT BUDGET: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
