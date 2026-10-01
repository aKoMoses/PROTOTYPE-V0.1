extends SceneTree

const ROCKET := preload("res://scripts/homing_rocket.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var actor := StaticBody3D.new()
	scene.add_child(actor)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#111d2a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#adc6e2")
	environment.ambient_light_energy = 0.8
	world_environment.environment = environment
	scene.add_child(world_environment)
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(-50, -25, 0)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.8
	camera.global_position = Vector3(3.4, 4.2, 5.0)
	camera.look_at(Vector3(0, 0, -0.15))
	camera.current = true
	for index in range(5):
		var rocket := ROCKET.new()
		rocket.configure(actor, "preview:%d" % index, Vector3.FORWARD)
		scene.add_child(rocket)
		rocket.set_physics_process(false)
		rocket.global_position = Vector3(float(index - 2) * 0.55, float(index % 2) * 0.08, -float(index % 3) * 0.28)
		rocket.health = 40.0 if index != 3 else 20.0
		for step in range(9):
			rocket.global_position.z -= 0.08
			rocket._update_visual()
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var title := Label.new()
	layer.add_child(title)
	title.text = "PANIER ROQUETTES"
	title.position = Vector2(38, 30)
	title.add_theme_font_size_override("font_size", 30)
	title.modulate = Color("#92ecff")
	var subtitle := Label.new()
	layer.add_child(subtitle)
	subtitle.text = "5 missiles autoguidés  ·  PV individuels  ·  sillage électrique"
	subtitle.position = Vector2(38, 76)
	subtitle.add_theme_font_size_override("font_size", 18)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/rocket-basket"))
	var result := root.get_texture().get_image().save_png("res://captures/rocket-basket/preview.png")
	print("ROCKET CAPTURE: ", result)
	quit(result)
