extends SceneTree

var output_path := ""


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 0:
		output_path = arguments[0]
	else:
		output_path = "user://prototype0_capture.png"
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	if arguments.size() >= 3:
		var capture_player := scene.get_node_or_null("Player") as Node3D
		if capture_player != null:
			capture_player.position = Vector3(float(arguments[1]), 0.0, float(arguments[2]))
	for _frame in range(30):
		await process_frame
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png(output_path)
	quit()
