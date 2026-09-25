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
	current_scene = scene
	# Main builds the arena and its runtime children during _ready(). Wait one
	# frame before looking up the player/target so capture options are reliable.
	await process_frame
	if arguments.size() >= 3:
		var capture_player := scene.get_node_or_null("Player") as Node3D
		if capture_player != null:
			capture_player.position = Vector3(float(arguments[1]), 0.0, float(arguments[2]))
	if arguments.size() >= 4 and arguments[3] == "effects":
		var capture_target := scene.get_node_or_null("TargetDummy")
		if capture_target != null:
			capture_target.call("apply_burn", 3.5, 20.0, "capture")
			capture_target.call("apply_slow", 1.5, 30.0, "capture")
			capture_target.call("apply_stun", 1.5, "capture")
			capture_target.call("apply_spotted", 5.0, "capture")
			print("CAPTURE EFFECTS: ", capture_target.call("get_active_effect_types"))
	if arguments.size() >= 4 and arguments[3] == "axe":
		var axe_player := scene.get_node_or_null("Player")
		var axe_target := scene.get_node_or_null("TargetDummy")
		if axe_player != null and axe_target != null:
			axe_player.position = Vector3(0.0, 0.0, 0.0)
			axe_target.position = Vector3(0.0, 0.0, -2.0)
			axe_player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
			axe_player.call("reset_axe_state")
			axe_player.set("_combo_step", 2)
			axe_player.call("_perform_axe_attack")
			print("CAPTURE AXE: third strike started")
	var settle_frames := 50 if arguments.size() >= 4 and arguments[3] == "axe" else 30
	for _frame in range(settle_frames):
		await process_frame
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png(output_path)
	quit()
