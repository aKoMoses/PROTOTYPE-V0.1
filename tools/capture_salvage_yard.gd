extends SceneTree
## Isolated asset review under the real gameplay camera height, offset and FOV.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var arguments := OS.get_cmdline_user_args()
	var view := arguments[0] if not arguments.is_empty() else "north"
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#a6a294")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b6bec1")
	environment.ambient_light_energy = 0.50
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	stage.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color("#ffdfaa")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	stage.add_child(sun)
	var yard := load("res://scenes/environment/salvage_yard.tscn").instantiate() as Node3D
	stage.add_child(yard)
	var floor_node := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(128, 128)
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#b29368")
	material.roughness = 1.0
	floor_node.material_override = material
	stage.add_child(floor_node)
	var focus := Vector3(0, 0, -27)
	if view == "west":
		focus = Vector3(-30.5, 0, -11.5)
	elif view == "east":
		focus = Vector3(31.5, 0, -7)
	var camera := Camera3D.new()
	camera.position = focus + Vector3(0, 20.5, 17.5)
	camera.fov = 38.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(focus + Vector3(0, 0.45, 0), Vector3.UP)
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://captures/yard_" + view + ".png"
	var error := root.get_texture().get_image().save_png(output)
	print("YARD CAPTURE: ", output, " error=", error)
	stage.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
