extends SceneTree
## Exercise production maps, actual materials, light coupling and lifecycle.
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var ambience: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count: int = 6) -> void:
	for index in count:
		await process_frame

func _run() -> void:
	for mode in ["main", "training_ground", "survival"]:
		await _map(mode)
	root.get_node("GameSfx").call("clear")
	await create_timer(0.25).timeout
	check(checks >= 90, "all production map checks ran to completion")
	print("WORKSHOP AMBIENCE: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _map(mode: String) -> void:
	scene = load("res://scenes/" + mode + ".tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(8)
	ambience = scene.find_child("WorkshopAmbience", true, false)
	check(ambience != null and bool(ambience.get("_initialized")), mode + " initializes ambient circuits")
	if ambience == null or not bool(ambience.get("_initialized")):
		scene.queue_free()
		await frames()
		return
	ambience.set_process(false)
	var counts: Dictionary = ambience.call("get_debug_counts")
	check(int(counts.circuits) > 0 and int(counts.circuits) <= 128 and int(counts.materials) > 0, mode + " binds actual authored neon glass and halos")
	check(int(counts.fixtures) > 0 and int(counts.fixtures) <= 16 and int(counts.pendants) <= 16, mode + " bounds service hardware and moving lamps")
	var workshop := ambience.get_parent()
	var total := 0
	var moving := 0
	for mesh in workshop.find_children("Workshop_*", "MeshInstance3D", true, false):
		if "LiveLamp" in String(mesh.name):
			moving += 1
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	check(total == int(workshop.get_meta("baked_triangles", 0)), mode + " preserves authored decoration triangle count after extracting pendants")
	check(counts.pendants == 0 or moving > 0, mode + " moves actual lamp geometry")
	var physics_added := false
	for node in ambience.find_children("*", "", true, false):
		physics_added = physics_added or node is CollisionObject3D or node is CollisionShape3D or node is NavigationRegion3D or node is NavigationObstacle3D
	check(not physics_added, mode + " ambience adds no collision or navigation")
	var circuits: Array = ambience.get("_circuits")
	var neon: Dictionary = circuits.filter(func(entry: Dictionary) -> bool: return entry.neon)[0]
	var layouts_valid := true
	for entry in circuits:
		if entry.neon:
			layouts_valid = layouts_valid and entry.get("letters", 0) >= 4 and entry.get("letters", 100) <= 14 and entry.axis.dot(entry.out) < 0.001
	check(layouts_valid, mode + " recovers real separate glyphs and sign orientation")
	var test_circuit := neon.duplicate()
	test_circuit.mode = 0
	test_circuit.phase = 0.0
	test_circuit.fault_until = -1.0
	test_circuit.arc = 0.0
	check(ambience.call("circuit_state", test_circuit, 1.0).x == 0.0, "faulty sign has a real off interval")
	check(ambience.call("circuit_state", test_circuit, 1.80).x > 0.7 and ambience.call("circuit_state", test_circuit, 1.95).x < 0.1 and ambience.call("circuit_state", test_circuit, 2.08).x > 0.7 and ambience.call("circuit_state", test_circuit, 2.16).x < 0.1, "neon makes two separate ignition flashes")
	check(ambience.call("circuit_state", test_circuit, 2.55).x > 0.1 and ambience.call("circuit_state", test_circuit, 2.55).x < 0.9 and ambience.call("circuit_state", test_circuit, 3.0).x == 1.0, "neon settles progressively and stays illuminated")
	test_circuit.mode = 2
	check(ambience.call("circuit_state", test_circuit, 0.4).z == 0.0 and ambience.call("circuit_state", test_circuit, 3.0).z == 1.0, "faulty letter recovers independently from sign supply")
	var phases: Dictionary = {}
	var modes: Dictionary = {}
	for circuit in circuits:
		phases[circuit.phase] = true
		if circuit.neon:
			modes[circuit.mode] = true
	check(phases.size() > 3 and modes.size() > 1, mode + " gives workshops independent rhythms")
	var old_mode: int = neon.mode
	var old_phase: float = neon.phase
	neon.mode = 0
	neon.phase = 0.0
	ambience.set("_clock", 1.0)
	ambience.call("_update_circuits")
	var light := neon.light.get_ref() as OmniLight3D
	var pool := neon.pool.get_ref() as MeshInstance3D
	check(light.light_energy == 0.0 and float(pool.material_override.get_shader_parameter("live_intensity")) == 0.0, mode + " off tube removes its local illumination and ground glow")
	var values: PackedVector4Array = ambience.get("_values")
	var synced := true
	var colors_preserved := true
	for material in ambience.get("_materials").values():
		var bound: PackedVector4Array = material.get_shader_parameter("circuit_values")
		synced = synced and bound.size() == 128 and bound[int(neon.id)] == values[int(neon.id)]
		var tint: Color = material.get_shader_parameter("tube_color")
		colors_preserved = colors_preserved and tint != Color.WHITE and tint != Color.BLACK
	check(synced, mode + " glass and halo use the same circuit values")
	check(colors_preserved, mode + " live shaders retain authored cyan, red and amber colors")
	ambience.set("_clock", 3.0)
	ambience.call("_update_circuits")
	check(is_equal_approx(light.light_energy, neon.energy) and float(pool.material_override.get_shader_parameter("live_intensity")) == 1.0, mode + " ignition restores illumination")
	neon.mode = old_mode
	neon.phase = old_phase
	seed(7219)
	var expected := randf()
	seed(7219)
	ambience.call("_update_circuits")
	check(is_equal_approx(randf(), expected), mode + " ambience does not consume combat random state")
	var fixtures: Array = ambience.get("_fixtures")
	var fixture: Node3D = fixtures[0].node
	var phase: float = fixture.get("phase")
	var period := 18.0 + fmod(phase, 7.0)
	var start := period * 5.0 - phase * 2.0 + 1.0
	fixture.set("fan_speed", 0.0)
	fixture.call("animate", start, 0.1, 1.0, false, 0.0, Vector3.RIGHT)
	var speed: float = fixture.get("fan_speed")
	check(speed > 0.0 and speed < 5.0, mode + " fan accelerates progressively")
	fixture.call("animate", start + 12.0, 0.1, 1.0, false, 0.0, Vector3.RIGHT)
	check(float(fixture.get("fan_speed")) > 0.0 and float(fixture.get("fan_speed")) < speed, mode + " fan coasts after machine stops")
	var steam_clock := 8.5 * 5.0 - phase + 0.8
	fixture.call("animate", steam_clock, 0.1, 1.0, false, 0.0, Vector3.RIGHT)
	check(fixture.get_node("IntermittentSteam0").visible, mode + " pipe emits an intermittent steam plume")
	var drip_clock := 4.2 * 10.0 - phase + 0.1
	fixture.call("animate", drip_clock, 0.1, 1.0, false, 0.0, Vector3.ZERO)
	check(fixture.get_node("CondensationDrop").visible and fixture.get_node("CondensationDrop").global_position.y < fixture.global_position.y, mode + " condensation falls from pipe")
	var fall_duration := sqrt(maxf(0.0, fixture.global_position.y - 0.24) * 2.0 / 9.8)
	fixture.call("animate", drip_clock - 0.1 + fall_duration + 0.2, 0.1, 1.0, false, 0.0, Vector3.ZERO)
	check(fixture.get_node("CondensationRipple").visible and absf(fixture.get_node("CondensationRipple").global_position.y - 0.024) < 0.001, mode + " drip ends with a ground ripple")
	var arc_clock := (19.0 + fmod(phase, 5.0)) * 8.0 - phase * 3.0 + 0.04
	fixture.call("animate", arc_clock, 0.1, 1.0, false, 0.0, Vector3.ZERO)
	check(fixture.get_node("RareCableArc").visible, mode + " faulty cable produces a rare electric arc")
	ambience.set("_clock", arc_clock)
	ambience.set("_low", false)
	var fixture_circuit: Dictionary = circuits[int(fixtures[0].circuit)]
	fixture_circuit.power = 1.0
	ambience.call("_update_fixtures", 0.1, fixture.global_position)
	ambience.call("_update_circuits")
	check(fixture_circuit.arc > 0.0 and (fixture_circuit.light.get_ref() as OmniLight3D).light_color != fixture_circuit.color, mode + " arc briefly colors existing local light without adding a lamp")
	fixture.call("animate", arc_clock + 0.2, 0.1, 1.0, false, 0.0, Vector3.ZERO)
	check(not fixture.get_node("RareCableArc").visible, mode + " cable flash immediately subsides")
	var focus := fixture.global_position
	ambience.set("_low", false)
	ambience.call("_update_fixtures", 0.1, focus)
	ambience.call("_update_pendants", 0.1, focus)
	counts = ambience.call("get_debug_counts")
	check(counts.active_fixtures > 0 and counts.active_fixtures <= 4 and counts.active_pendants <= 6, mode + " normal quality respects animation budgets")
	var pendants: Array = ambience.get("_pendants")
	if not pendants.is_empty():
		var pendant: Dictionary = pendants[0]
		var lamp_circuit: Dictionary = circuits[int(pendant.circuit)]
		pendant.velocity = 0.3
		ambience.call("_update_pendants", 0.1, pendant.at)
		var lamp := lamp_circuit.light.get_ref() as OmniLight3D
		var glow := lamp_circuit.pool.get_ref() as MeshInstance3D
		check(pendant.angle != 0.0 and lamp.global_position.distance_to(pendant.at) > 0.0001 and glow.global_position.distance_to(lamp_circuit.pool_at) > 0.0001 and pendant.shadow.visible, mode + " actual lamp, light, ground glow and projected shadow move together")
	ambience.set("_low", true)
	ambience.call("_update_fixtures", 0.1, focus)
	ambience.call("_update_pendants", 0.1, focus)
	counts = ambience.call("get_debug_counts")
	check(counts.active_fixtures <= 2 and counts.active_pendants == 0, mode + " low quality reduces hardware and disables pendant shadows")
	var small_fx_hidden := true
	for entry in fixtures:
		for label in ["IntermittentSteam0", "IntermittentSteam1", "CondensationDrop", "CondensationRipple", "RareCableArc"]:
			small_fx_hidden = small_fx_hidden and not entry.node.get_node(label).visible
	check(small_fx_hidden, mode + " low quality suppresses small transient effects")
	ambience.set_process(true)
	await frames(2)
	var clock: float = ambience.get("_clock")
	var rotation: Vector3 = fixture.get_node("InertialFanRotor").rotation
	paused = true
	await frames(6)
	check(is_equal_approx(float(ambience.get("_clock")), clock) and fixture.get_node("InertialFanRotor").rotation == rotation, mode + " pause freezes clock, fans and screen animation")
	paused = false
	workshop.hide()
	await frames(2)
	clock = ambience.get("_clock")
	await frames(4)
	check(is_equal_approx(float(ambience.get("_clock")), clock), mode + " hidden map stops ambience simulation")
	workshop.show()
	await frames(2)
	check(float(ambience.get("_clock")) > clock, mode + " returning to map resumes ambience")
	if mode == "main":
		scene.call("set_arena_variant", "test")
		await frames(8)
		var directors := scene.find_children("WorkshopAmbience", "", true, false)
		check(directors.size() >= 2, "test arena installs its own workshop ambience")
		check(not workshop.is_visible_in_tree(), "switching arena hides original workshop ambience")
		var test_ambience: Node = directors.filter(func(node: Node) -> bool: return node != ambience)[0]
		check(absf(float(test_ambience.call("_floor_y", Vector3(3.5, 2.5, 0.6))) - 2.4) < 0.02, "ambient floor effects follow test arena platform heights")
		scene.call("set_arena_variant", "classic")
		await frames(4)
		check(workshop.is_visible_in_tree(), "classic return restores its authored workshops")
	scene.get_node("VFXManager").call("clear")
	var clean := true
	for circuit in circuits:
		clean = clean and circuit.arc == 0.0 and circuit.fault_until < 0.0
		clean = clean and ambience.get("_values")[int(circuit.id)].w == 0.0
	check(clean, mode + " round cleanup clears temporary electrical disturbances")
	scene.queue_free()
	current_scene = null
	await frames(4)
