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
	if not DisplayServer.is_touchscreen_available() and not OS.has_feature("mobile") and bool(controls.visible):
		push_error("FAIL: contrôles tactiles visibles sur desktop sans mode preview")
		quit(1)
		return
	var viewport_rect: Rect2 = controls.get_viewport().get_visible_rect()
	var safe_rect: Rect2 = controls.call("_safe_rect")
	if not viewport_rect.encloses(safe_rect):
		push_error("FAIL: safe area hors de la fenêtre")
		quit(1)
		return
	var centers: Dictionary = controls.call("_action_centers")
	for value in centers.values():
		var center: Vector2 = Vector2(value)
		if not safe_rect.has_point(center):
			push_error("FAIL: bouton hors de la safe area")
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
	print("P0-121/122 TOUCH LAYOUT TEST: PASS")
	quit(0)
