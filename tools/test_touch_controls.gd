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
	controls.visible = true
	controls.call("_begin_touch", 21, aim_center)
	var canceled := InputEventScreenTouch.new()
	canceled.index = 21
	canceled.pressed = false
	canceled.canceled = true
	controls.call("_input", canceled)
	if int(controls.get("_aim_touch")) != -1 or bool(player.get("_touch_fire_active")):
		push_error("FAIL: interruption tactile interprétée comme un tir")
		quit(1)
		return
	# A second finger rejected during FULGURO must not release the cast owned by
	# the first finger when that rejected contact is lifted.
	player.call("apply_loadout", {"weapon": "blaster", "offensive": "fulguro_punch", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	player.call("reset_combat_state")
	controls.call("_begin_touch", 40, centers.offensive)
	controls.call("_begin_touch", 41, centers.offensive)
	var action_touches: Dictionary = controls.get("_action_touches")
	if str(action_touches.get(40, "")) != "offensive" or str(action_touches.get(41, "accepted")) != "":
		push_error("FAIL: seconde activation FULGURO non marquée comme rejetée")
		quit(1)
		return
	controls.call("_end_touch", 41)
	if bool(player.get("_fulguro_release_requested")):
		push_error("FAIL: relâchement rejeté a déclenché FULGURO")
		quit(1)
		return
	controls.call("_end_touch", 40)
	if not bool(player.get("_fulguro_release_requested")):
		push_error("FAIL: relâchement propriétaire n'a pas déclenché FULGURO")
		quit(1)
		return
	player.call("_cancel_fulguro_attack", "test")
	var profile: Dictionary = load("res://scripts/hud_layout.gd").standard()
	profile.offensive_button.a = profile.move.a.duplicate()
	profile.offensive_button.d = profile.move.d.duplicate()
	profile.offensive_button.z = 5
	controls.call("set_hud_layout", profile)
	var shared_center: Vector2 = controls.call("_joystick_center")
	controls.call("_begin_touch", 30, shared_center)
	if not (controls.get("_action_touches") as Dictionary).has(30):
		push_error("FAIL: priorité Devant ignorée")
		quit(1)
		return
	controls.call("reset_inputs")
	profile.move.z = 6
	controls.call("set_hud_layout", profile)
	controls.call("_begin_touch", 31, shared_center)
	if int(controls.get("_joystick_touch")) != 31:
		push_error("FAIL: priorité du joystick ignorée")
		quit(1)
		return
	controls.call("reset_inputs")
	controls.call("set_reserved_rects", [Rect2(shared_center - Vector2(40, 40), Vector2(80, 80))])
	if controls.call("_begin_touch", 32, shared_center) or int(controls.get("_joystick_touch")) != -1:
		push_error("FAIL: accès Pause/Menu capturé par un joystick")
		quit(1)
		return
	controls.call("set_reserved_rects", [])
	if not bool(controls.visible) and DisplayServer.is_touchscreen_available():
		push_error("FAIL: panneau tactile masqué sur une cible tactile")
		quit(1)
		return
	print("P0 MOBILE TOUCH LAYOUT/MULTITOUCH TEST: PASS")
	quit(0)
