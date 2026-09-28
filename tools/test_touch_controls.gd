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
	if centers.has("attack"):
		push_error("FAIL: ancien bouton ATK encore présent")
		quit(1)
		return
	for value in centers.values():
		var center: Vector2 = Vector2(value)
		if not safe_rect.has_point(center):
			push_error("FAIL: bouton hors de la safe area")
			quit(1)
			return
	for test_rect in [Rect2(0, 0, 1280, 720), Rect2(0, 0, 1920, 1080), Rect2(80, 0, 2180, 1080), Rect2(0, 0, 1024, 600)]:
		var layout: Dictionary = controls.call("_layout_for_safe_rect", test_rect)
		var move: Vector2 = layout.move
		var aim: Vector2 = layout.aim
		var move_radius := float(layout.move_radius)
		var aim_radius := float(layout.aim_radius)
		if not test_rect.has_point(move - Vector2(move_radius, move_radius)) or not test_rect.has_point(move + Vector2(move_radius, move_radius)):
			push_error("FAIL: joystick gauche hors zone sur %s" % test_rect)
			quit(1)
			return
		if not test_rect.has_point(aim - Vector2(aim_radius, aim_radius)) or not test_rect.has_point(aim + Vector2(aim_radius, aim_radius)):
			push_error("FAIL: joystick droit hors zone sur %s" % test_rect)
			quit(1)
			return
		if test_rect.end.x - (aim.x + aim_radius) > 55.0 * float(layout.scale):
			push_error("FAIL: joystick droit pas assez proche du bord")
			quit(1)
			return
		for action in ["offensive", "defensive", "mobility"]:
			var module_center: Vector2 = layout.actions[action]
			if module_center.distance_to(move) >= module_center.distance_to(aim):
				push_error("FAIL: module %s groupé du mauvais côté" % action)
				quit(1)
				return
	# Multitouch : relâcher un module ou le déplacement ne doit pas réinitialiser
	# la visée tenue par un autre doigt.
	var move_center: Vector2 = controls.call("_joystick_center")
	var aim_center: Vector2 = controls.call("_aim_center")
	controls.call("_begin_touch", 11, move_center + Vector2(22, -18))
	controls.call("_begin_touch", 12, aim_center + Vector2(0, -40))
	controls.call("_begin_touch", 13, centers.offensive)
	controls.call("_end_touch", 13)
	if int(controls.get("_joystick_touch")) != 11 or int(controls.get("_aim_touch")) != 12:
		push_error("FAIL: relâchement module a réinitialisé un joystick")
		quit(1)
		return
	controls.call("_end_touch", 11)
	if int(controls.get("_aim_touch")) != 12 or not bool(player.get("_touch_fire_active")):
		push_error("FAIL: relâchement déplacement a interrompu la visée/tir")
		quit(1)
		return
	controls.call("reset_inputs")
	if bool(player.get("_touch_fire_active")) or bool(player.call("is_blaster_charging")):
		push_error("FAIL: reset tactile n'annule pas le contact/charge")
		quit(1)
		return
	if not bool(controls.visible) and DisplayServer.is_touchscreen_available():
		push_error("FAIL: panneau tactile masqué sur une cible tactile")
		quit(1)
		return
	print("P0 MOBILE TOUCH LAYOUT/MULTITOUCH TEST: PASS")
	quit(0)
