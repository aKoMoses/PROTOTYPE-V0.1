extends SceneTree

var output_path := "user://repair_kit_states.png"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		output_path = arguments[0]
	call_deferred("_capture")


func _capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#121716")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d5e0da")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.72
	environment.glow_strength = 0.58
	environment.glow_bloom = 0.06
	environment_node.environment = environment
	stage.add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	light.light_color = Color("#fff0d2")
	light.light_energy = 1.1
	light.shadow_enabled = true
	stage.add_child(light)

	var floor_mesh := MeshInstance3D.new()
	var floor := PlaneMesh.new()
	floor.size = Vector2(18.0, 16.0)
	floor_mesh.mesh = floor
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#343a37")
	floor_material.roughness = 0.96
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)

	var kit_scene := load("res://scenes/repair_kit.tscn") as PackedScene
	var available := kit_scene.instantiate() as Area3D
	available.name = "AvailableKit"
	available.position = Vector3(-2.2, 0.0, 0.0)
	stage.add_child(available)
	available.call("set_collection_active", false)
	var recharging := kit_scene.instantiate() as Area3D
	recharging.name = "RechargingKit"
	recharging.position = Vector3(2.2, 0.0, 0.0)
	stage.add_child(recharging)
	recharging.call("set_collection_active", false)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 20.5, 17.5)
	camera.fov = 38.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.45, 0.0), Vector3.UP)

	await process_frame
	recharging.set("_respawn_remaining", 10.0)
	recharging.call("_set_state", 2, false)
	recharging.call("_update_recharge_bar")
	for _frame in range(24):
		await process_frame
	var image := get_root().get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	print("REPAIR KIT CAPTURE: ", output_path, " error=", error)
	quit(0 if error == OK else 1)
