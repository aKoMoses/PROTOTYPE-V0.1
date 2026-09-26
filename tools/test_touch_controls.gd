extends SceneTree


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var controls := scene.get_node_or_null("Interface/TouchControls")
	var player := scene.get_node_or_null("Player")
	if controls == null or player == null:
		push_error("FAIL: contrôles tactiles ou joueur introuvable")
		quit(1)
		return
	player.call("set_touch_move_vector", Vector2(0.5, -0.4))
	player.call("set_touch_aim_vector", Vector2(0.0, -1.0))
	player.call("set_touch_attack_held", true)
	player.call("set_touch_attack_held", false)
	player.call("trigger_touch_action", "weapon")
	if not bool(controls.visible) and DisplayServer.is_touchscreen_available():
		push_error("FAIL: panneau tactile masqué sur une cible tactile")
		quit(1)
		return
	print("P0-120 TOUCH CONTROLS TEST: PASS")
	quit(0)
