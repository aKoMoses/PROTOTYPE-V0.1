extends SceneTree

const BUSH_VISUAL_SCRIPT := preload("res://scripts/bush_visual.gd")

var _output_path := "res://captures/bush_visual_pass.png"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_output_path = arguments[0]
	var mode := arguments[1] if arguments.size() > 1 else "detail"
	call_deferred("_capture", mode)


func _capture(mode: String) -> void:
	if mode in ["arena", "same_bush"]:
		await _build_arena_stage(mode == "same_bush")
	else:
		_build_detail_stage()
	for _frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var error := capture.save_png(_output_path)
	print("BUSH CAPTURE: ", _output_path, " error=", error)
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	if current_scene != null:
		current_scene.queue_free()
	await create_timer(0.1).timeout
	quit(0 if error == OK else 1)


func _build_detail_stage() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#171b1e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#aab4b7")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	stage.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	light.light_color = Color("#f2d7b5")
	light.light_energy = 1.08
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var floor := PlaneMesh.new()
	floor.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = floor
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#9a8566")
	material.roughness = 1.0
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	for index in range(3):
		var bush := BUSH_VISUAL_SCRIPT.new()
		var bush_scale := 0.9 + float(index) * 0.225
		bush.setup(1.28 * bush_scale, 2.35 * bush_scale, index * 173 + 41)
		bush.position = Vector3(float(index - 1) * 4.4, 0.012, 0.0)
		stage.add_child(bush)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 13.0, 12.0)
	camera.fov = 38.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)


func _build_arena_stage(same_bush: bool) -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.set("_menu_showcase_active", false)
	scene.call("reset_round_camera")
	for node_name in ["Interface", "NetworkMatch", "TouchControls"]:
		var interface := scene.get_node_or_null(node_name)
		if interface != null and interface.has_method("hide"):
			interface.call("hide")
	var bush := scene.get_node("BushSouthCenter") as Node3D
	var centre: Vector3 = bush.get_meta("bush_center", bush.global_position)
	var player := scene.get_node("Player") as Node3D
	player.call("reset_combat_state")
	player.global_position = centre + Vector3(-0.25, 0.0, 0.25)
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	var target := scene.get_node("TargetDummy") as Node3D
	target.call("set_training_bot_enabled", false)
	target.call("reset_combat_state")
	if same_bush:
		target.global_position = centre + Vector3(0.65, 0.0, -0.25)
	else:
		var opponent_bush := scene.get_node("BushSouthWestCover") as Node3D
		target.global_position = opponent_bush.get_meta("bush_center", opponent_bush.global_position)
	target.set_physics_process(false)
	await physics_frame
	player.call("_update_world_ui_anchor")
	player.call("_update_bush_state", 0.0)
	target.call("_update_visibility_presentation")
	print("BUSH CAPTURE STATE: local=", player.get_node("WorldUIAnchor/BushStatus").get("text") if player.has_node("WorldUIAnchor/BushStatus") else player.call("get_current_bush_name"), " enemy_visible=", target.call("is_visible_to", player))
	var camera_rig := scene.get_node("CameraRig") as Node3D
	camera_rig.set_process(false)
	var camera := camera_rig.get_node("Camera3D") as Camera3D
	camera.global_position = centre + Vector3(0.0, 20.5, 17.5)
	camera.look_at(centre + Vector3(0.0, 0.45, 0.0), Vector3.UP)
