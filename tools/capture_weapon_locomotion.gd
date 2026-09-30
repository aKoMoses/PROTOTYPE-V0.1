extends SceneTree

## Visual QA for ready-low -> aim/fire -> hold -> locomotion and both weapons.
## Run with a rendering backend, followed by -- OUTPUT_DIRECTORY.
const STEP := 1.0 / 60.0
var _output_directory := "res://exports/weapon-locomotion-review"
var _player: CharacterBody3D
var _rig: PlayerVisualRig
var _camera: Camera3D


func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	call_deferred("_capture")


func _capture() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_directory))
	var stage := Node3D.new()
	stage.name = "WeaponLocomotionReview"
	root.add_child(stage)
	current_scene = stage
	_configure_stage(stage)
	_player = load("res://scripts/player.gd").new() as CharacterBody3D
	_player.name = "Player"
	stage.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_gameplay_enabled(true)
	(_player.get_node("WorldUIAnchor") as Node3D).hide()
	_rig = _player.get_node("VisualRoot") as PlayerVisualRig
	_rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL

	await _settle(Vector3.ZERO, Vector3.FORWARD, 24)
	await _save_frame("01_ready_idle.png")
	await _settle(Vector3.RIGHT, Vector3.FORWARD, 36)
	await _save_frame("02_locomotion_ready_low.png")

	_player._begin_weapon_aim()
	await _settle(Vector3.RIGHT, Vector3.LEFT, 12)
	await _save_frame("03_run_right_aim_left.png")
	_player._begin_weapon_fire()
	_player._play_blaster_recoil(1.0)
	await _settle(Vector3.RIGHT, Vector3.LEFT, 3)
	await _save_frame("04_blaster_recoil.png")
	await _settle(Vector3.RIGHT, Vector3.LEFT, 18)
	_player._begin_aim_hold()
	await _save_frame("05_blaster_aim_hold.png")

	_player.set_weapon("shotgun")
	_player._begin_weapon_aim()
	await _settle(Vector3.FORWARD, Vector3.BACK, 12)
	await _save_frame("06_shotgun_move_up_aim_down.png")

	_player._begin_aim_hold()
	_player._update_weapon_pose_state(_player.aim_hold_time + 0.01)
	await _settle(Vector3.RIGHT, Vector3.LEFT, 18)
	await _save_frame("07_return_to_locomotion.png")
	print("WEAPON_LOCOMOTION_CAPTURE: ", ProjectSettings.globalize_path(_output_directory))
	quit()


func _configure_stage(stage: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#27313d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e8eef7")
	environment.ambient_light_energy = 0.85
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-46.0, -34.0, 0.0)
	key.light_energy = 1.7
	stage.add_child(key)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(18.0, 18.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#4a5563")
	floor_material.roughness = 1.0
	floor.material_override = floor_material
	stage.add_child(floor)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.2
	stage.add_child(_camera)
	_camera.global_position = Vector3(3.8, 2.25, 4.4)
	_camera.look_at(Vector3(0.0, 1.15, 0.0), Vector3.UP)
	_camera.make_current()


func _settle(move: Vector3, aim: Vector3, frames: int) -> void:
	for _frame in range(frames):
		_rig.update_visual_state(move, aim, 0.0 if move.is_zero_approx() else _player.move_speed, _player.move_speed, STEP)
		_rig.animation_tree.advance(STEP)
		_rig.skeleton.advance(STEP)
		await process_frame


func _save_frame(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var muzzle := _rig.get_weapon_muzzle(_player._weapon_id)
	var muzzle_forward := -muzzle.global_basis.z.normalized() if muzzle != null else Vector3.ZERO
	print("[WeaponLocomotionFrame] %s state=%s aim_blend=%.3f muzzle_forward=%s" % [filename, _player.get_weapon_pose_state_name(), _rig._aim_blend_amount, muzzle_forward])
	var result := root.get_texture().get_image().save_png(_output_directory.path_join(filename))
	if result != OK:
		push_error("Could not save weapon/locomotion capture: %s (%s)" % [filename, error_string(result)])
