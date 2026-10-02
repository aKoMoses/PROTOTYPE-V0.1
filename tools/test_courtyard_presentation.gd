extends SceneTree

class RepairProbe extends Node3D:
	var health := 500.0
	func get_health() -> float: return health
	func get_max_health() -> float: return 1000.0
	func heal(amount: float, _source: String = "") -> float:
		var applied := minf(amount, 1000.0 - health)
		health += applied
		return applied

var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var kit := scene.get_node("HealthPadNorth")
	var socket := kit.get_node("RepairSocket")
	var cross := kit.get_node("ConsumableKit/FloatingCross") as Node3D
	_check(cross.position.y > .05 and cross.position.y < .075, "medical cross must sit on the plate")
	_check(cross.scale.x < .71, "medical cross must fit its inset")
	_check(not (kit.get_node("PermanentBase") as MeshInstance3D).visible, "old circular base must not overlap the square plate")
	var actor := RepairProbe.new()
	scene.add_child(actor)
	actor.global_position = kit.global_position
	kit.call("set_collection_active", true)
	_check(is_equal_approx(float(kit.call("try_collect", actor)),300.0), "presentation must retain 30 percent healing")
	await process_frame
	_check(kit.call("get_visual_state_name") == "recharging", "consumed plate must retain recharge state")
	_check((kit.get_node("ConsumableKit/RechargeBar") as Node3D).visible, "recharge bar must remain visible")
	kit.call("set_point_enabled", false)
	await process_frame
	_check(not socket.visible, "disabled plate must hide")
	kit.call("set_point_enabled", true)
	await process_frame
	_check(socket.visible and kit.call("get_visual_state_name") == "available", "reenabled plate must return")
	var director := scene.get_node("ArenaPresentation")
	director.call("set_quality", 0)
	for bush in get_nodes_in_group("bush_placeholder"):
		var grass := bush.get_node("GroundedVegetation/LayeredHighGrass") as MeshInstance3D
		_check(grass.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "low quality must disable grass shadows")
	for particles in director.find_children("*", "GPUParticles3D", true, false):
		_check(not particles.visible, "low quality must disable peripheral particles")
	director.call("set_quality", 1)
	for bush in get_nodes_in_group("bush_placeholder"):
		var grass := bush.get_node("GroundedVegetation/LayeredHighGrass") as MeshInstance3D
		_check(grass.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "normal quality must restore grass shadows")
	print("COURTYARD PRESENTATION: ", "PASS" if failures.is_empty() else "FAIL", " (medical availability, collection, recharge, disable/enable; quality switch)")
	for failure in failures:
		push_error(failure)
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
