extends SceneTree
const WIND := preload("res://scripts/environment/scenery_wind.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count: int = 4) -> void:
	for index in count:
		await physics_frame
		await process_frame

func _run() -> void:
	check(is_equal_approx(WIND.strength(2.4, Vector3.ZERO), 1.0), "travelling gust has a smooth crest")
	var downwind := WIND.DIRECTION * WIND.SPEED * 2.0
	check(WIND.strength(2.4, downwind) < 0.1 and WIND.strength(4.4, downwind) > 0.999, "same gust reaches a downwind point two seconds later")
	check(WIND.strength(9.0, Vector3.ZERO) == 0.0, "gust leaves a quiet interval")
	for mode in ["main", "training_ground", "survival"]:
		await _map(mode)
	root.get_node("GameSfx").call("clear")
	await create_timer(0.3).timeout
	check(checks >= 130, "all production map checks completed")
	print("WORKSHOP ECOSYSTEM: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _map(mode: String) -> void:
	var scene := load("res://scenes/" + mode + ".tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await frames(10)
	var eco := scene.find_child("WorkshopEcosystem", true, false) as Node3D
	check(eco != null, mode + " installs workshop ecosystem")
	if eco == null:
		scene.queue_free()
		await frames()
		return
	var ambience := eco.get_parent() as Node3D
	var life := ambience.get_node("SceneryLife")
	var organic := scene.get_node("OrganicWorldDetails")
	var manager := scene.get_node("VFXManager")
	var player := scene.get("player") as Node3D
	if mode == "main":
		scene.call("set_menu_showcase_enabled", false)
		var flow: Node = scene.get("game_flow")
		flow.call("_start_duel")
		flow.call("_begin_live_round")
		flow.set_process(false)
		var target: Node3D = scene.get("target")
		target.call("set_training_bot_enabled", false)
		target.set_physics_process(false)
	elif mode == "survival":
		scene.call("_choose_weapon", "blaster")
		scene.call("_begin_wave_combat")
	else:
		if bool(scene.get("_menu").get("visible")):
			scene.call("_toggle_menu")
	scene.set_process(false)
	player.set_physics_process(false)
	player.call("set_gameplay_enabled", true)
	var rig := scene.get_node("CameraRig") as Node3D
	rig.call("set_target", player)
	rig.call("set_follow_offset", Vector3.ZERO, true)
	var stations: Array = eco.get("_stations")
	var station: Dictionary = stations[0]
	var reachable := false
	var diagnostic: Array[Dictionary] = []
	for candidate in stations:
		player.global_position = candidate.vent + candidate.out * 1.3
		player.global_position.y = float(life.call("_floor_y", player.global_position))
		rig.call("set_target", player)
		await frames(8)
		var nearby: Array = life.call("_near", stations, rig.global_position, "vent", 4)
		var has_paper: bool = (life.get("_loose") as Array).any(func(entry: Dictionary) -> bool: return entry.kind == "paper" and entry.circuit == candidate.circuit)
		var shown := bool(organic.call("_visible", candidate.panel + candidate.out * 0.02))
		diagnostic.append({"station": candidate.circuit, "vent": candidate.vent, "panel": candidate.panel, "focus": rig.global_position, "player": player.global_position, "near": candidate in nearby, "shown": shown, "paper": has_paper})
		if has_paper and candidate in nearby and shown:
			station = candidate
			reachable = true
			break
	check(reachable, mode + " has accessible physical reactions")
	if not reachable:
		print("UNREACHABLE ECOSYSTEM FIXTURE ", mode, " ", diagnostic)
		scene.queue_free()
		await frames()
		return
	check(eco.get_child_count() == 9, mode + " uses nine fixed batches")
	check(stations.size() > 0 and stations.size() <= 16, mode + " station pool is bounded")
	check(eco.find_children("*", "CollisionObject3D", true, false).is_empty() and eco.find_children("*", "CollisionShape3D", true, false).is_empty() and eco.find_children("*", "NavigationRegion3D", true, false).is_empty() and eco.find_children("*", "Light3D", true, false).is_empty(), mode + " adds no collision navigation or lights")
	eco.set_process(false)
	life.set_process(false)
	ambience.set_process(false)
	var camera := scene.get_viewport().get_camera_3d()
	var loose: Array = life.get("_loose")
	var paper: Dictionary = loose.filter(func(entry: Dictionary) -> bool: return entry.kind == "paper" and entry.circuit == station.circuit)[0]
	var clock: float = organic.get("_clock")
	organic.set("_clock", 2.4 + (paper.at as Vector3).dot(WIND.DIRECTION) / WIND.SPEED)
	life.call("reset_transients")
	life.set("_low", false)
	life.call("_draw_loose", 0.05, paper.at)
	check(paper.lift > 0.25 and (paper.velocity as Vector3).length() > 0.0, mode + " coherent gust lifts and moves real loose paper")
	var props: Array = organic.get("_props")
	if props.is_empty():
		organic.call("_scan")
		props = organic.get("_props")
	check(not props.is_empty(), mode + " discovers rendered foliage and cloth after deferred map setup")
	if props.is_empty():
		scene.queue_free()
		await frames()
		return
	var mesh := props[0].mesh.get_ref() as MeshInstance3D
	organic.set("_clock", 2.4 + mesh.global_position.dot(WIND.DIRECTION) / WIND.SPEED)
	organic.call("_update_props", 0.01)
	check(bool(mesh.material_override.get_shader_parameter("scenery_driven")) and float(mesh.material_override.get_shader_parameter("scenery_gust")) > 0.999, mode + " actual foliage or cloth receives the shared gust")
	organic.set("_clock", clock)
	life.call("reset_transients")
	eco.call("reset_transients")
	var health := float(player.call("get_health"))
	var at := player.global_position
	var endpoint: Vector3 = eco.call("cable_point", station, 0.0, clock)
	manager.call("impact", station.panel + station.out * 0.04, station.out, "metal", 1.2)
	check(absf(station.velocity) > 0.1, mode + " actual contact shakes the hinged plate")
	check(station.wave > 0.0, mode + " actual contact sends an impulse through the cable")
	check((eco.call("cable_point", station, 0.0, clock) as Vector3).distance_to(endpoint) < 0.00001 and (eco.call("cable_point", station, 1.0, clock) as Vector3).distance_to(station.cable + station.axis * 0.59) < 0.00001, mode + " both cable attachments stay pinned")
	check(eco.call("get_debug_counts").dust_pool > 0, mode + " beam sheds a small dust shower")
	check(station.flash_power > 0.0, mode + " impact lights a brief metal reflection")
	check(player.global_position == at and float(player.call("get_health")) == health, mode + " scenery leaves actor health and position unchanged")
	var initial_wave: float = station.wave
	eco.call("_process", 0.05)
	check(absf(station.angle) > 0.0 and absf(station.angle) <= 0.38 and station.wave < initial_wave, mode + " panel integrates and cable impulse decays")
	var cable_batch: MultiMesh = eco.get("_batches").cables
	check(cable_batch.visible_instance_count > 0 and float(eco.call("get_debug_counts").cable_section_max) < 0.3, mode + " cable sections preserve their short physical length after rotation")
	var dust: Array = eco.get("_dust")
	var initial_height: float = dust[0].at.y
	eco.call("_process", 0.05)
	check(float(dust[0].at.y) < initial_height, mode + " released dust falls under gravity")
	# Drive the existing fan through its real working cycle.
	var fixture := station.fixture.get_ref() as Node3D
	check(absf(float(station.heat_at.y) - fixture.to_global(Vector3(0.57, 0.54, 0.14)).y) < 0.001, mode + " heat volume sits above the actual service pipe")
	fixture.show()
	for index in 80:
		fixture.call("animate", -float(fixture.get("phase")) * 2.0, 0.05, 1.0, false, 0.0, WIND.DIRECTION)
		eco.call("_process", 0.05)
	check(float(fixture.get("fan_speed")) > 7.0 and station.vent_open > 0.75, mode + " working machine opens its ventilation louvers")
	check(station.heat > 0.5 and eco.call("get_debug_counts").heat_visible > 0, mode + " working machine produces bounded heat shimmer")
	check((paper.velocity as Vector3).length() > 0.0 and paper.lift > 0.0, mode + " exhaust pushes nearby loose debris")
	var temperature: float = station.heat
	fixture.set("fan_speed", 0.0)
	for index in 60:
		eco.call("_process", 0.05)
	check(station.vent_open < 0.02 and station.heat < temperature and station.heat > 0.05, mode + " vents close while heat cools with inertia")
	var circuits: Array = ambience.get("_circuits")
	for circuit in circuits:
		(circuit.light.get_ref() as OmniLight3D).hide()
	var lamp: Dictionary = circuits.filter(func(entry: Dictionary) -> bool: return not entry.neon)[0]
	var light := lamp.light.get_ref() as OmniLight3D
	light.show()
	lamp.average = 1.0
	player.global_position = light.global_position
	player.global_position.y = float(life.call("_floor_y", player.global_position))
	eco.call("_draw_insects", light.global_position, camera)
	check(eco.call("get_debug_counts").insects_visible == 4, mode + " lit lamp attracts a bounded insect cluster")
	check(eco.call("get_debug_counts").scattered_lamps > 0, mode + " local mech disperses nearby insects")
	lamp.average = 0.0
	eco.call("_draw_insects", light.global_position, camera)
	check(eco.call("get_debug_counts").insects_visible == 0, mode + " unlit lamps have no insect cloud")
	player.global_position = at
	await frames(4)
	var neon: Dictionary = circuits[int(station.circuit)]
	station.last_power = 0.0
	neon.average = 0.9
	eco.call("_process", 0.05)
	check(eco.call("get_debug_counts").sheen_visible > 0, mode + " neon return sweeps a reflection across the metal")
	# A real solid surface and the production muzzle/contact callbacks.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.2, 0.12)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_transform = Transform3D(station.basis, station.vent + station.out * 0.65 + Vector3.UP * 0.5)
	var socket := Marker3D.new()
	player.add_child(socket)
	socket.global_position = player.global_position + Vector3.UP * 0.85
	socket.look_at(wall.global_position)
	await frames(4)
	eco.call("reset_transients")
	var ray := PhysicsRayQueryParameters3D.create(socket.global_position, socket.global_position - socket.global_basis.z * 4.0, 1)
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == wall, mode + " energy fixture hits the intended physical wall")
	if not hit.is_empty():
		manager.call("muzzle", socket, "blaster", 0.0)
		check(eco.call("get_debug_counts").energy_shots == 1, mode + " actual energy muzzle tracks its first solid hit")
		manager.call("impact", hit.position, hit.normal, "metal", 1.2)
		check(eco.call("get_debug_counts").scorch_pool == 1, mode + " energy contact leaves a hot scorch on a real surface")
		eco.call("_process", 0.05)
		check(eco.call("get_debug_counts").scorches_visible == 1, mode + " hot scorch is submitted to its fixed batch")
		var scorch: Dictionary = eco.get("_scorches")[0]
		check(scorch.age > 0.0 and scorch.life <= 6.0, mode + " scorch cools and has a finite lifetime")
		eco.call("reset_transients")
		manager.call("muzzle", socket, "shotgun", 0.0)
		manager.call("impact", hit.position, hit.normal, "metal", 1.2)
		check(eco.call("get_debug_counts").scorch_pool == 0, mode + " ballistic contact does not create an energy scorch")
	eco.call("reset_transients")
	var rejected: int = eco.get("_rejected")
	manager.call("impact", station.panel + station.out * 0.04, station.out, "metal", 1.2)
	check(int(eco.get("_rejected")) > rejected and eco.call("get_debug_counts").dust_pool == 0 and station.velocity == 0.0, mode + " occluded structural impact produces no visible clue")
	wall.queue_free()
	socket.queue_free()
	await frames(4)
	for quality in [1, 0]:
		ambience.set("_low", quality == 0)
		life.set("_low", quality == 0)
		manager.set("quality", quality)
		eco.call("_process", 0.05)
		for index in 8:
			manager.call("impact", station.panel + station.out * 0.04, station.out, "metal", 1.2)
			eco.call("_process", 0.4)
		var counts: Dictionary = eco.call("get_debug_counts")
		check(counts.panels_visible <= (4 if quality == 1 else 2) and counts.louvers_visible <= (12 if quality == 1 else 6) and counts.cables_visible <= (48 if quality == 1 else 12), mode + " mechanical batch budget at quality %d" % quality)
		check(counts.dust_pool <= (48 if quality == 1 else 16) and counts.dust_visible <= (72 if quality == 1 else 16), mode + " dust budget at quality %d" % quality)
		check(counts.insects_visible <= (12 if quality == 1 else 0) and counts.heat_visible <= (2 if quality == 1 else 0), mode + " air budget at quality %d" % quality)
		check(counts.sheen_visible <= (8 if quality == 1 else 2) and counts.scorch_pool <= (16 if quality == 1 else 6), mode + " reflection and scorch budget at quality %d" % quality)
	seed(71291)
	var expected := randf()
	seed(71291)
	eco.call("_process", 0.05)
	check(is_equal_approx(randf(), expected), mode + " ecosystem preserves the combat random stream")
	eco.set_process(true)
	await frames(2)
	var eco_clock: float = eco.get("_clock")
	paused = true
	for index in 5:
		await process_frame
	check(float(eco.get("_clock")) == eco_clock, mode + " pause freezes CPU and shader clocks")
	paused = false
	var workshop := ambience.get_parent() as Node3D
	workshop.hide()
	await frames(2)
	eco_clock = eco.get("_clock")
	manager.call("impact", station.panel, station.out, "metal", 1.2)
	await frames(2)
	check(float(eco.get("_clock")) == eco_clock and eco.call("get_debug_counts").dust_pool == 0, mode + " hidden workshop freezes and rejects effects")
	check((eco.get("_batches") as Dictionary).values().all(func(batch: MultiMesh) -> bool: return batch.visible_instance_count == 0), mode + " hidden branch clears all nine batches")
	workshop.show()
	await frames(2)
	check(float(eco.get("_clock")) > eco_clock, mode + " returning workshop resumes")
	manager.call("clear")
	check((eco.get("_batches") as Dictionary).values().all(func(batch: MultiMesh) -> bool: return batch.visible_instance_count == 0) and eco.call("get_debug_counts").scorch_pool == 0 and eco.call("get_debug_counts").energy_shots == 0, mode + " round clear resets all visual state immediately")
	scene.queue_free()
	current_scene = null
	await frames(4)
