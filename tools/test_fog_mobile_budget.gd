extends SceneTree
const FOG := preload("res://scripts/fog_of_war.gd")
var failures: Array[String] = []
var checks := 0

class Observer extends Node3D:
	var vision_radius := 22.0
	var epoch := 0
	func get_vision_radius() -> float: return vision_radius
	func get_vision_fade_width() -> float: return 0.0
	func get_visibility_epoch() -> int: return epoch

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var observer := Observer.new()
	world.add_child(observer)
	var camera := Camera3D.new()
	world.add_child(camera)
	var wall := StaticBody3D.new()
	wall.position = Vector3(8, 1, 0)
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 8)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	var fogs: Array[Node3D] = []
	for mobile in [false, true]:
		var fog: Node3D = FOG.new()
		world.add_child(fog)
		fog.call("configure", observer, camera)
		fog.call("_apply_device_budget", mobile)
		fog.set_process(false)
		fog.set_physics_process(false)
		fogs.append(fog)
	await physics_frame
	for fog in fogs:
		fog.call("_physics_process", 1.0)
		fog.call("_process", 1.0)
		check(float(fog.call("sample_world_visibility", Vector3(4, 0, 0))) > 0.95, "visible foreground stays clear")
		check(float(fog.call("sample_world_visibility", Vector3(15, 0, 0))) < 0.05, "wall still conceals the floor behind it")
		check(float(fog.call("sample_world_visibility", Vector3(10, 0, -12))) > 0.90, "open side of a cover stays visible")
		check(float(fog.call("sample_world_visibility", Vector3(-24, 0, 0))) == 0.0, "vision range remains unchanged")
	var mobile := fogs[1]
	check(int(mobile.get("ray_count")) == 192 and int(mobile.get("mask_resolution")) == 128, "mobile sampling is bounded")
	var before := int(mobile.get("_profile_updates"))
	for frame in 60:
		mobile.call("_physics_process", 1.0 / 60.0)
		mobile.call("_process", 1.0 / 60.0)
	check(int(mobile.get("_profile_updates")) - before == 10, "steady mobile vision rebuilds at 10 Hz instead of 20 Hz")
	observer.position = Vector3(14, 0, 0)
	mobile.call("_physics_process", 0.001)
	check(int(mobile.get("_profile_updates")) == before + 11, "teleport rebuilds immediately between scheduled updates")
	check(float(mobile.call("sample_world_visibility", Vector3(17, 0, 0))) > 0.95, "teleport discards concealment from the old position")
	observer.epoch += 1
	mobile.call("_physics_process", 0.001)
	check(int(mobile.get("_profile_updates")) == before + 12, "new round resets history without waiting for the mobile clock")
	observer.vision_radius = 5.0
	mobile.call("_physics_process", 0.001)
	check(float(mobile.call("sample_world_visibility", Vector3(21, 0, 0))) == 0.0, "changed vision radius applies immediately")
	wall.queue_free()
	await physics_frame
	observer.position = Vector3.ZERO
	mobile.call("_physics_process", 0.2)
	mobile.call("_process", 0.3)
	check(float(mobile.call("sample_world_visibility", Vector3(3, 0, 0))) > 0.95, "removed cover cannot leave stale world opacity")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("FOG MOBILE BUDGET: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
