extends SceneTree

var rig: Node3D
var camera: Camera3D
var target := Vector3(0, 0.92, -8)
var output_directory := "res://exports/enemy-droid-review"

func _initialize() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	call_deferred("capture")

func capture() -> void:
	var stage := current_scene as Node3D
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#252c38")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d9e4f5")
	environment.ambient_light_energy = 0.65
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	stage.add_child(light)
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30, 30)
	floor_visual.mesh = floor_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#424c5a")
	floor_visual.material_override = material
	stage.add_child(floor_visual)
	rig = load("res://scripts/enemy_droid_visual.gd").new()
	stage.add_child(rig)
	if not rig.setup():
		quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	if arguments.has("shotgun"):
		rig.set_weapon("shotgun")
		output_directory = "res://exports/enemy-droid-shotgun-review"
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	stage.add_child(camera)
	camera.position = Vector3(3, 2, -4)
	camera.look_at(Vector3(0, 0.95, -0.10))
	DirAccess.make_dir_recursive_absolute(output_directory)
	await frame("01_idle")
	tick(Vector3.ZERO, 60)
	await frame("02_aim")
	camera.position = Vector3(-4, 1.8, -0.8)
	camera.look_at(Vector3(0, 1.1, -0.3))
	await frame("03_aim_side")
	camera.position = Vector3(3, 2, -4)
	camera.look_at(Vector3(0, 0.95, -0.10))
	tick(Vector3(0, 0, -1.8), 45)
	await frame("04_walk")
	tick(Vector3(1.8, 0, 0), 45)
	await frame("05_strafe")
	tick(Vector3(0, 0, 1.8), 45)
	await frame("06_backstep")
	tick(Vector3(7.2, 0, 0), 45)
	await frame("07_dodge")
	tick(Vector3.ZERO, 30)
	rig.prepare_shot(target)
	tick(Vector3.ZERO, 3)
	await frame("08_fire")
	rig.play_death()
	tick(Vector3.ZERO, 75)
	camera.size = 3.7
	await frame("09_death")
	rig.reset_visual()
	tick(Vector3.ZERO, 20)
	await frame("10_reset")
	print("ENEMY_DROID_CAPTURE: ", output_directory)
	quit()

func tick(velocity: Vector3, frames: int) -> void:
	for index in frames:
		rig.update_visual(1.0 / 60.0, velocity, target, true, false, false)

func frame(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [output_directory, name])
	var muzzle: Transform3D = rig.get_muzzle_transform()
	print(name, " state=", rig.animation_state, " muzzle=", muzzle.origin, " forward=", -muzzle.basis.z, " grip_error=", rig.left_grip_error)
