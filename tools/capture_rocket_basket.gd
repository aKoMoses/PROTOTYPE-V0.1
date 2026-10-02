extends SceneTree

const ROCKET := preload("res://scripts/homing_rocket.gd")
const VISUAL := preload("res://scripts/rocket_visual.gd")
const BASKET := preload("res://scripts/rocket_basket.gd")
var _rockets: Array[Node3D] = []
var _elapsed := 0.0
var _moving := false


func _initialize() -> void:
	_run.call_deferred()


func _process(delta: float) -> bool:
	if _moving:
		_elapsed += minf(delta, 1.0 / 30.0)
		for index in range(_rockets.size()):
			var rocket := _rockets[index]
			if not is_instance_valid(rocket):
				continue
			var t := _elapsed + float(index) * 0.08
			rocket.position = Vector3(float(index - 2) * 0.62 + sin(t * 3.0) * 0.12, 0.9 + float(index % 2) * 0.11, 1.2 - t * 3.0)
			rocket.direction = Vector3(cos(t * 3.0) * 0.36, 0, -3.0).normalized()
			rocket._update_visual()
	return false


func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/rocket-basket/" + label + ".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/rocket-basket"))
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var actor := StaticBody3D.new()
	scene.add_child(actor)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#182329")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c6d5db")
	environment.ambient_light_energy = 0.65
	world.environment = environment
	scene.add_child(world)
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.4
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(14, 14)
	floor_visual.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#405050")
	floor_material.roughness = 0.95
	floor_visual.material_override = floor_material
	scene.add_child(floor_visual)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position = Vector3(3.0, 4.4, 4.3)
	camera.look_at(Vector3(0, 0.65, -0.20))
	camera.current = true
	for index in range(5):
		var rocket := ROCKET.new()
		rocket.configure(actor, "preview:%d" % index, Vector3.FORWARD)
		scene.add_child(rocket)
		rocket.set_physics_process(false)
		rocket.health = 20.0 if index == 3 else 40.0
		_rockets.append(rocket)
	_moving = true
	await create_timer(0.36).timeout
	await _capture("flight-detail")
	for index in range(24):
		camera.position = Vector3(3.0, 4.4, 4.3 - _elapsed * 3.0)
		camera.look_at(Vector3(0, 0.65, 0.7 - _elapsed * 3.0))
		await _capture("animation-%02d" % index)
		await create_timer(0.018).timeout
	_moving = false
	var center: Vector3 = _rockets[2].global_position
	camera.position = center + Vector3(3, 3.5, 4)
	camera.look_at(center)
	_rockets[2].get("_visual").finish(Vector3.UP)
	_rockets[2].queue_free()
	await create_timer(0.025).timeout
	await _capture("impact-detail")
	for effect in get_nodes_in_group("prototype0_fx_budget"):
		effect.queue_free()
	scene.queue_free()
	await process_frame
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player: Node3D = scene.get_node("Player")
	var target: Node3D = scene.get_node("TargetDummy")
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	player.position = Vector3(-3, 0, 17)
	target.position = Vector3(3, 0, 17)
	player.call("_set_aim_direction", Vector3.RIGHT)
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	camera = scene.get_node("CameraRig/Camera3D")
	camera.global_position = Vector3(0, 13, 27)
	camera.look_at(Vector3(0, 0.7, 17))
	await create_timer(0.3).timeout
	var launched := BASKET.launch(player, Vector3.RIGHT, "capture", "capture-volley", {"rocket_basket": 10.0})
	await create_timer(0.26).timeout
	for rocket in launched:
		if is_instance_valid(rocket):
			rocket.set_physics_process(false)
	await _capture("flight-gameplay")
	for rocket in launched:
		if is_instance_valid(rocket):
			rocket.set_physics_process(true)
	for frame in range(28):
		await _capture("combat-%02d" % frame)
		await create_timer(0.018).timeout
	BASKET.clear(player)
	VISUAL.spawn_burst(scene, target.global_position + Vector3.UP * 0.9, Vector3.RIGHT, Vector3.LEFT)
	await create_timer(0.025).timeout
	await _capture("impact-gameplay")
	await create_timer(0.10).timeout
	await _capture("impact-smoke")
	print("ROCKET CAPTURE: PASS")
	quit(0)
