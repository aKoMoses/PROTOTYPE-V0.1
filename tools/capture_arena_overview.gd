extends SceneTree
## Diagnostic composition view only; production gameplay camera is untouched.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	# The distant diagnostic camera deliberately sees beyond gameplay culling.
	for mesh in scene.get_node("ArenaPresentation/SalvageYard").find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 0.0
		mesh.visibility_range_end_margin = 0.0
	var camera := Camera3D.new()
	print("Diagnostic overview: additional camera only, not the shipped gameplay view")
	camera.position = Vector3(0, 92, 76)
	camera.fov = 38
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0, -2))
	camera.current = true
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	var code := root.get_texture().get_image().save_png(args[0]) if not args.is_empty() else ERR_INVALID_PARAMETER
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null:
		sfx.call("clear")
	scene.queue_free()
	await process_frame
	quit(0 if code == OK else 1)
