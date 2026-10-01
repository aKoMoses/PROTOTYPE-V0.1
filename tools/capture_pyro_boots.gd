extends SceneTree


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#172128")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#fff1de")
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.3
	scene.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#465257")
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(6, 6, 9)
	camera.look_at(Vector3(1.0, 0.5, 0.0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.5
	camera.current = true
	var player: CharacterBody3D = load("res://scripts/player.gd").new()
	player.name = "Player"
	scene.add_child(player)
	player.call("apply_loadout", {"robot": "polyvalent", "weapon": "blaster", "mobility": "pyro_boots"})
	player.set_physics_process(false)
	player.call("_set_aim_direction", Vector3.RIGHT)
	for frame in range(15):
		await process_frame
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	var effect := scene.get_node("PyroBootsIgnition")
	effect.set_process(false)
	effect.call("_process", 0.055)
	await process_frame
	await RenderingServer.frame_post_draw
	save("ignition")
	player.call("_update_dash", 0.07)
	effect.call("_process", 0.04)
	await process_frame
	await RenderingServer.frame_post_draw
	save("burning-boots")
	scene.queue_free()
	await process_frame
	quit()


func save(phase: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://captures/pyro-boots")
	var error := root.get_texture().get_image().save_png("res://captures/pyro-boots/" + phase + ".png")
	print("PYRO BOOTS CAPTURE ", phase, ": ", error)
