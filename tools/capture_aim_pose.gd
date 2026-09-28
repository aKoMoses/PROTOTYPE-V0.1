extends SceneTree

## Render the actual player rig from both sides, then a charged kick and recovery.
## Run with a graphics backend (not --headless), followed by -- OUTPUT_DIRECTORY.
var _output_directory := "res://exports/aim-pose-review"
var _player: CharacterBody3D
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_directory))
	var stage := Node3D.new()
	stage.name = "AimPoseReview"
	root.add_child(stage)
	current_scene = stage
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#303a49")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e4eaf5")
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	light.light_energy = 1.6
	stage.add_child(light)
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30.0, 30.0)
	floor_visual.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#495260")
	floor_material.roughness = 1.0
	floor_visual.material_override = floor_material
	stage.add_child(floor_visual)
	_player = load("res://scripts/player.gd").new() as CharacterBody3D
	_player.name = "Player"
	stage.add_child(_player)
	_player.set_physics_process(false)
	_player.call("set_gameplay_enabled", true)
	(_player.get_node("WorldUIAnchor") as Node3D).hide()
	var rig: PlayerVisualRig = _player.get("_visual_rig")
	rig.update_visual_state(Vector3.ZERO, Vector3.FORWARD, 0.0, 5.0, 1.0, true)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.7
	stage.add_child(_camera)
	_camera.make_current()
	_set_camera(Vector3(-3.0, 1.9, -4.0))
	await create_timer(0.45).timeout
	await _save_frame("aim_front_left.png")
	_set_camera(Vector3(3.0, 1.9, -4.0))
	await _save_frame("aim_front_right.png")
	_set_camera(Vector3(-4.0, 1.45, -0.5))
	await _save_frame("aim_side.png")
	_player.call("_play_blaster_recoil", 1.0)
	await create_timer(0.05).timeout
	await _save_frame("kick_50ms.png")
	await create_timer(0.30).timeout
	await _save_frame("recovery_350ms.png")
	_player.set("_direction_debug_enabled", true)
	(_player.get_node("PlayerDirectionDebug") as Node3D).show()
	(_player.get_node("MuzzleAimAngleDebug") as Node3D).show()
	_player.call("_update_player_debug_vectors")
	_set_camera(Vector3(-4.0, 2.2, -1.5))
	_camera.look_at(Vector3(0.0, 1.45, -0.25), Vector3.UP)
	_camera.size = 4.2
	await _save_frame("aim_debug.png")
	(_player.get_node("PlayerDirectionDebug") as Node3D).hide()
	(_player.get_node("MuzzleAimAngleDebug") as Node3D).hide()
	for marker_info in [
		["mixamorig_RightHand", "RightHand", Color.RED, Vector3(0.0, 0.14, 0.0)],
		["mixamorig_LeftHand", "LeftHand", Color.GREEN, Vector3(0.0, -0.14, 0.0)],
		["mixamorig_RightShoulder", "RShoulder", Color.YELLOW, Vector3(0.0, 0.26, 0.0)],
	]:
		var bone_index := rig.skeleton.find_bone(marker_info[0])
		if bone_index >= 0:
			var bone_world := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(bone_index)
			if marker_info[1] == "RightHand":
				bone_world = rig.aim_modifier.last_right_hand_world
			elif marker_info[1] == "LeftHand":
				bone_world = rig.aim_modifier.last_left_hand_world
			_create_marker(stage, marker_info[1], bone_world.origin, marker_info[2], marker_info[3])
	var grip := _player.find_child("LeftHandGrip", true, false) as Node3D
	if grip != null:
		_create_marker(stage, "Grip", grip.global_position, Color.CYAN, Vector3(0.0, 0.07, -0.2))
	_set_camera(Vector3(-3.0, 1.9, -4.0))
	_camera.size = 2.7
	await _save_frame("aim_markers_front_left.png")
	_set_camera(Vector3(-4.0, 1.45, -0.5))
	await _save_frame("aim_markers_side.png")
	_set_camera(Vector3(3.0, 1.9, -4.0))
	await _save_frame("aim_markers_front_right.png")
	print("AIM_POSE_CAPTURE: ", ProjectSettings.globalize_path(_output_directory))
	quit()


func _set_camera(position: Vector3) -> void:
	_camera.global_position = position
	_camera.look_at(Vector3(0.0, 1.05, -0.25), Vector3.UP)


func _create_marker(parent: Node3D, title: String, position: Vector3, color: Color, label_offset: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.028
	sphere.height = 0.056
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	marker.material_override = material
	parent.add_child(marker)
	marker.global_position = position
	var label := Label3D.new()
	label.text = title
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	label.outline_size = 5
	label.no_depth_test = true
	label.position = label_offset
	marker.add_child(label)
	print("AIM_MARKER ", title, " = ", position)


func _save_frame(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var result := capture.save_png(_output_directory.path_join(filename))
	if result != OK:
		push_error("Could not save aim capture: %s (%s)" % [filename, error_string(result)])
