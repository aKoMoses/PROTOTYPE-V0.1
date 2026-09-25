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
	if arguments.size() >= 4 and arguments[3] == "shotgun":
		var shotgun_player := scene.get_node_or_null("Player")
		var shotgun_target := scene.get_node_or_null("TargetDummy")
		if shotgun_player != null and shotgun_target != null:
			shotgun_player.position = Vector3(-1.7, 0.0, 0.8)
			shotgun_target.position = Vector3(1.0, 0.0, -1.8)
			shotgun_player.set("aim_direction", Vector3(2.7, 0.0, -2.6).normalized())
			shotgun_player.call("set_weapon", "shotgun")
			shotgun_player.call("reset_combat_state")
			shotgun_target.call("reset_combat_state")
			shotgun_player.call("_perform_shotgun_attack")
			print("CAPTURE SHOTGUN: salvo started")
	if arguments.size() >= 4 and (arguments[3] == "drone" or arguments[3] == "javelin"):
		var module_player := scene.get_node_or_null("Player")
		var module_target := scene.get_node_or_null("TargetDummy")
		if module_player != null and module_target != null:
			module_player.position = Vector3(-1.7, 0.0, 0.8)
			module_target.position = Vector3(1.0, 0.0, -1.8)
			module_player.set("aim_direction", Vector3(2.7, 0.0, -2.6).normalized())
			module_player.call("reset_combat_state")
			module_target.call("reset_combat_state")
			if arguments[3] == "drone":
				module_player.call("_perform_modulo_drone")
			else:
				module_player.call("_perform_javelin")
			print("CAPTURE MODULE: ", arguments[3])
	if arguments.size() >= 4 and (arguments[3] == "magnetic" or arguments[3] == "stasis"):
		var defensive_player := scene.get_node_or_null("Player")
		var defensive_target := scene.get_node_or_null("TargetDummy")
		if defensive_player != null and defensive_target != null:
			defensive_player.position = Vector3(0.0, 0.0, 0.0)
			defensive_target.position = Vector3(0.0, 0.0, -3.0)
			defensive_player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
			defensive_player.call("reset_combat_state")
			defensive_target.call("reset_combat_state")
			defensive_player.set("_defensive_module_id", "static_shield" if arguments[3] == "stasis" else "magnetic_field")
			defensive_player.call("_perform_defensive_module")
			print("CAPTURE DEFENSIVE: ", arguments[3])
	if arguments.size() >= 4 and arguments[3] == "baroud":
		var passive_player := scene.get_node_or_null("Player")
		if passive_player != null:
			passive_player.position = Vector3(0.0, 0.0, 0.0)
			passive_player.call("reset_combat_state")
			passive_player.call("set_passive", "baroud")
			passive_player.call("take_damage", 1000.0, "capture", "baroud_capture")
			print("CAPTURE PASSIVE: baroud")
	var settle_frames := 50 if arguments.size() >= 4 and arguments[3] == "axe" else (22 if arguments.size() >= 4 and arguments[3] == "shotgun" else (32 if arguments.size() >= 4 and (arguments[3] == "drone" or arguments[3] == "javelin") else (18 if arguments.size() >= 4 and arguments[3] == "magnetic" else (12 if arguments.size() >= 4 and (arguments[3] == "stasis" or arguments[3] == "baroud") else 30))))
	for _frame in range(settle_frames):
		await process_frame
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png(output_path)
	quit()
