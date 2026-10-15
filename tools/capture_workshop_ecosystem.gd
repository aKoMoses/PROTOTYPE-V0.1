extends SceneTree
const WIND := preload("res://scripts/environment/scenery_wind.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(2)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for index in 10:
		await process_frame
	scene.call("set_menu_showcase_enabled", false)
	var flow: Node = scene.get("game_flow")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	scene.set_meta("camera_shake_enabled", false)
	var ambience := scene.find_child("WorkshopAmbience", true, false)
	var life := ambience.get_node("SceneryLife")
	var eco := ambience.get_node("WorkshopEcosystem")
	var organic := scene.get_node("OrganicWorldDetails")
	var stations: Array = eco.get("_stations")
	stations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.vent as Vector3).length_squared() < (b.vent as Vector3).length_squared())
	var station: Dictionary = stations[0]
	var sign: Dictionary = ambience.get("_circuits")[int(station.circuit)]
	var player := scene.get("player") as Node3D
	player.set_physics_process(false)
	player.call("set_gameplay_enabled", true)
	player.global_position = station.vent + station.out * 1.55 - station.axis * 0.80
	player.global_position.y = float(life.call("_floor_y", player.global_position))
	player.get_node("WorldUIAnchor").hide()
	var target := scene.get("target") as Node3D
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.hide()
	var rig := scene.get_node("CameraRig") as Node3D
	rig.set_process(false)
	rig.global_position = station.vent + station.out * 0.80
	var camera := scene.get_viewport().get_camera_3d()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	camera.global_position = sign.at + station.out * 7.0 + Vector3.UP * 4.6 + station.axis * 1.6
	camera.look_at(sign.at + Vector3.DOWN * 0.85 + station.out * 0.40)
	for index in 12:
		await process_frame
	# Seek clocks into a real working cycle and travelling gust; keep periods intact.
	var fixture := station.fixture.get_ref() as Node3D
	ambience.set("_clock", -float(fixture.get("phase")) * 2.0 + 2.0 + 4.0 * (18.0 + fposmod(float(fixture.get("phase")), 7.0)))
	organic.set("_clock", (station.vent as Vector3).dot(WIND.DIRECTION) / WIND.SPEED + 0.30 + WIND.PERIOD * 2.0)
	var manager := scene.get_node("VFXManager")
	var peak := {"dust": 0, "heat": 0, "insects": 0, "scorches": 0, "sheen": 0}
	for index in 240:
		if index < 44:
			player.global_position += station.axis * 0.020 - station.out * 0.010
		elif index > 165 and index < 202:
			player.global_position += station.out * 0.015
		if index == 65:
			manager.call("impact", station.panel + station.out * 0.06, station.out, "metal", 1.2)
		if index == 110:
			_energy_hit(scene, player, station, manager)
		if index == 165:
			load("res://scripts/rocket_visual.gd").spawn_burst(scene, station.vent + station.out * 0.75 + Vector3.UP * 0.10, Vector3.UP)
		player.call("_update_world_ui_anchor")
		flow.call("_update_hud")
		await process_frame
		await RenderingServer.frame_post_draw
		var counts: Dictionary = eco.call("get_debug_counts")
		for key in peak:
			peak[key] = maxi(int(peak[key]), int(counts[key + "_visible"]))
		var error := root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % index))
		if error != OK:
			quit(2)
			return
	var cable_batch: MultiMesh = eco.get("_batches").cables
	var cable_lengths_valid := true
	for index in cable_batch.visible_instance_count:
		var length := cable_batch.get_instance_transform(index).basis.y.length()
		cable_lengths_valid = cable_lengths_valid and length > 0.05 and length < 0.30
	print("WORKSHOP ECOSYSTEM CAPTURE: ", JSON.stringify({"frames": 240, "renderer": RenderingServer.get_current_rendering_driver_name(), "cable_lengths_valid": cable_lengths_valid, "peaks": peak, "counts": eco.call("get_debug_counts")}))
	manager.call("clear")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	quit(0 if int(peak.scorches) > 0 and int(peak.heat) > 0 and cable_lengths_valid else 1)

func _energy_hit(scene: Node3D, player: Node3D, station: Dictionary, manager: Node) -> void:
	var socket := Marker3D.new()
	player.add_child(socket)
	socket.global_position = player.global_position + Vector3.UP * 0.95
	var aim: Vector3 = station.vent - station.out * 0.5
	aim.y = socket.global_position.y
	socket.look_at(aim)
	var ray := PhysicsRayQueryParameters3D.create(socket.global_position, socket.global_position - socket.global_basis.z * 8.0, 1)
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		var bodies := scene.find_children("*", "StaticBody3D", true, false)
		bodies.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(station.vent) < b.global_position.distance_squared_to(station.vent))
		for body in bodies:
			if (body as StaticBody3D).collision_layer & 1 == 0 or (body as Node3D).global_position.distance_squared_to(station.vent) > 36.0:
				continue
			aim = (body as Node3D).global_position
			aim.y = socket.global_position.y
			socket.look_at(aim)
			ray.to = socket.global_position - socket.global_basis.z * 8.0
			hit = scene.get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				break
	if not hit.is_empty():
		manager.call("muzzle", socket, "blaster", 0.0)
		manager.call("impact", hit.position, hit.normal, "metal", 1.1)
		print("CAPTURE ENERGY CONTACT: ", hit.position, " / ", hit.collider)
	socket.queue_free()
