extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const TARGET := preload("res://scripts/target_dummy.gd")
const VFX := preload("res://scripts/vfx_manager.gd")
const HUD := preload("res://scripts/hud_vitals.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var vfx := VFX.new()
	vfx.name = "VFXManager"
	stage.add_child(vfx)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#17212b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -26, 0)
	stage.add_child(light)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(32, 20)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#243543")
	floor.material_override = material
	stage.add_child(floor)
	var player := PLAYER.new()
	player.name = "Player"
	stage.add_child(player)
	player.apply_loadout({"weapon": "longshot", "passive": ""})
	player.set_gameplay_enabled(true)
	player.set_physics_process(false)
	player.position = Vector3(-10, 0, 0)
	player._update_world_ui_anchor()
	player._set_aim_direction(Vector3.RIGHT)
	var targets: Array[Node3D] = []
	for x in [-3.0, 4.0]:
		var target := TARGET.new()
		stage.add_child(target)
		target.position = Vector3(x, 0, 0)
		target.set_training_bot_enabled(false)
		target.set_process(false)
		target.set_duel_mode(true)
		targets.append(target)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22.0
	stage.add_child(camera)
	camera.position = Vector3(0, 18, 16)
	camera.look_at(Vector3(-1, 0.7, 0))
	camera.make_current()
	var canvas := CanvasLayer.new()
	stage.add_child(canvas)
	var hud := HUD.new()
	hud.position = Vector2(20, 20)
	canvas.add_child(hud)
	hud.set_player(player)
	var title := Label.new()
	title.position = Vector2(20, 630)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#ffd477"))
	title.text = "LONGSHOT / EXÉCUTION"
	canvas.add_child(title)
	var subtitle := Label.new()
	subtitle.position = Vector2(20, 668)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.text = "Deux impacts préparent le tir traversant · +20 % de vitesse après une touche"
	canvas.add_child(subtitle)
	for frame in range(20):
		player._update_robot_motion(1.0 / 60.0)
		player._update_weapon_pose_state(1.0 / 60.0)
		await physics_frame
	player._visual_rig.set_aim_enabled(true, true)
	player._longshot_state.hits = 2
	player._sync_weapon_readout()
	hud._refresh()
	await _save("ready")
	player._perform_longshot_attack()
	while player.get_longshot_shots_fired() == 0:
		player._update_robot_motion(1.0 / 60.0)
		await physics_frame
	await create_timer(0.09).timeout
	hud._refresh()
	await _save("execution")
	await create_timer(0.2).timeout
	assert(float(targets[0].get_health()) < 1000.0 and float(targets[1].get_health()) < 1000.0)
	print("LONGSHOT EXECUTION CAPTURE: PASS")
	quit(0)

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/longshot-execution"))
	root.get_texture().get_image().save_png("res://captures/longshot-execution/" + label + ".png")
