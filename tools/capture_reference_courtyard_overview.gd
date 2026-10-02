extends SceneTree
## Whole-map art review. The extra overview camera and extended shadow/culling
## distances exist only in this capture, never in the shipped gameplay scene.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(2)
		return
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	scene.call("set_bot_build_seed", 42)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	scene.set_process(false)
	scene.set("_menu_showcase_active", false)
	flow.set_process(false)
	for branch in ["Player", "TargetDummy", "CameraRig"]:
		_freeze(scene.get_node(branch))
	var player := scene.get_node("Player") as Node3D
	player.call("set_robot", "puissant")
	player.call("set_weapon", "mekatana")
	player.global_position = Vector3(0, 0, 2)
	player.set("aim_direction", Vector3.FORWARD)
	var target := scene.get_node("TargetDummy") as Node3D
	target.call("set_training_bot_enabled", false)
	target.global_position = Vector3(3.5, 0, -2)
	for canvas in scene.find_children("*", "CanvasLayer", true, false):
		(canvas as CanvasLayer).visible = false
	for label in scene.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	for readout in scene.find_children("*HealthReadout", "Node3D", true, false):
		(readout as Node3D).visible = false
	for frame in range(5):
		await process_frame
	# Cull ranges and shadow splits are measured from the camera. The production
	# camera is nearby; this temporary full-map camera needs a longer distance.
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 0.0
		mesh.visibility_range_end_margin = 0.0
	var sun := scene.get_node("ArenaKeyLight") as DirectionalLight3D
	sun.directional_shadow_max_distance = 150.0
	var camera := Camera3D.new()
	camera.name = "DiagnosticOverviewCamera"
	camera.position = Vector3(0, 76, 53)
	camera.fov = 38
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0, 5))
	camera.current = true
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(args[0])
	print("REFERENCE OVERVIEW: diagnostic camera only; file=", args[0])
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	current_scene = null
	await process_frame
	quit(0 if code == OK else 1)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)
