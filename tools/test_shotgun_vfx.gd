extends SceneTree

const VFX := preload("res://scripts/vfx_manager.gd")
const SHOT := preload("res://scripts/live_projectile.gd")
var _manager: Node3D
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	_manager = VFX.new()
	stage.add_child(_manager)
	_manager.set_process(false)
	call_deferred("_run")


func _run() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0.0, 0.0, -0.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.1)
	shape.shape = box
	wall.add_child(shape)
	current_scene.add_child(wall)
	await physics_frame
	for quality in [VFX.Quality.LOW, VFX.Quality.NORMAL]:
		_manager.quality = quality
		_manager.clear()
		var shot := SHOT.new()
		current_scene.add_child(shot)
		shot.set_physics_process(false)
		shot.configure(Vector3.FORWARD, 22.0, 7.0, 1, [])
		_manager.projectile_visual(shot, "shotgun")
		var trail: Dictionary = _manager.get("_active").back()
		_check(trail.node.scale.z < 0.002, "trail starts at muzzle with no premature beam")
		shot._physics_process(0.01)
		_manager._process(0.01)
		_check(is_equal_approx(shot.global_position.z, -0.22) and is_equal_approx(trail.node.scale.z, 0.22), "trail follows real distance at 22 m/s")
		_check(trail.node.global_position.distance_to(shot.global_position) < 0.001, "trail leading edge follows projectile exactly")
		var contacts: Array[Dictionary] = []
		shot.finished.connect(func(hit: Dictionary, distance: float) -> void: contacts.append({"hit": hit, "distance": distance}))
		shot._physics_process(0.02)
		_check(contacts.size() == 1 and contacts[0].hit.get("collider") == wall and absf(contacts[0].distance - 0.45) < 0.001, "nearby wall remains the first and only contact")
		_check(trail.attachment == null and absf(trail.node.global_position.z + 0.45) < 0.001 and trail.node.global_basis.z.normalized().z > 0.99, "contact freezes trailing light behind wall surface")
		_manager._process(0.08)
		_check(_manager.get_debug_counts().active == 0, "contact trail fades within 80 ms")
		await process_frame
		var socket := Marker3D.new()
		current_scene.add_child(socket)
		_manager.muzzle(socket, "shotgun")
		socket.position = Vector3(0.4, 0.0, 0.2)
		socket.rotation.y = 0.7
		_manager._process(0.01)
		var follows := true
		var layers := 0
		for effect in _manager.get("_active"):
			if effect.kind == "shotgun_flame":
				layers += 1
				var expected: Vector3 = socket.global_position + socket.global_basis * effect.offset
				follows = follows and effect.node.global_position.distance_to(expected) < 0.001
		_check(layers == 3 and follows, "three flash layers follow animated weapon socket")
		socket.queue_free()
		await process_frame
		_manager._process(0.01)
		var dangling := false
		for effect in _manager.get("_active"):
			dangling = dangling or effect.attachment != null
		_check(not dangling, "switching or removing weapon releases attached flash")
		_manager.clear()
		for index in range(120):
			_manager.shotgun_impact(Vector3.ZERO, Vector3.BACK, "metal")
		var counts: Dictionary = _manager.get_debug_counts()
		var factor := 0.5 if quality == VFX.Quality.LOW else 1.0
		_check(counts.active <= int((_manager.max_effects + _manager.max_decals + _manager.max_particles) * factor), "repeated contacts respect quality budgets")
		var live := SHOT.new()
		current_scene.add_child(live)
		live.set_physics_process(false)
		_manager.projectile_visual(live, "shotgun")
		for index in range(120):
			_manager.shotgun_impact(Vector3.ZERO, Vector3.UP, "robot")
		_check(is_instance_valid(live) and not live.is_queued_for_deletion(), "visual budget never deletes gameplay projectile")
		live.queue_free()
		await process_frame
		_manager._process(10.0)
		_check(_manager.get_debug_counts().active == 0, "all shotgun effects expire after volley")
	_manager.clear()
	print("SHOTGUN VFX TEST: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("FAIL: " + label)
