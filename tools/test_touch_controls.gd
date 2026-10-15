extends SceneTree

var _cancel_failures: Array[String] = []


func _initialize() -> void:
	_run_touch_fixture.call_deferred()


func _run_touch_fixture() -> void:
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
	# Use a queued defensive command: starting the default Javelin charge now
	# deliberately interrupts weapon fire, independently of finger ownership.
	controls.call("_begin_touch", 13, centers.defensive)
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
	_test_spell_cancel(controls, player)
	# Let queued preview deletion and Pelto's two-frame weapon restore settle.
	await process_frame
	await process_frame
	await process_frame
	if not _cancel_failures.is_empty():
		for failure in _cancel_failures:
			push_error("FAIL: " + failure)
		quit(1)
		return
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


func _check_cancel(ok: bool, message: String) -> void:
	if not ok:
		_cancel_failures.append(message)


func _is_preparing(player: Node, module_id: String) -> bool:
	var method: String = {"eclipse": "is_eclipse_aiming", "javelin": "is_javelin_charging", "fulguro_punch": "is_fulguro_charging", "pelto_smash": "is_pelto_preparing"}[module_id]
	return bool(player.call(method))


func _test_spell_cancel(controls: Control, player: Node) -> void:
	controls.call("reset_inputs")
	controls.call("set_hud_layout", load("res://scripts/hud_layout.gd").standard())
	player.set_physics_process(false)
	player.set("training_instant_cooldowns", false)
	player.call("set_gameplay_enabled", true)
	for safe in [Rect2(0, 0, 1280, 720), Rect2(0, 0, 1920, 1080), Rect2(80, 20, 2100, 1040), Rect2(0, 0, 800, 480)]:
		var zone: Rect2 = controls.call("_cancel_zone_for_safe_rect", safe)
		_check_cancel(safe.encloses(zone), "zone d'annulation hors safe area sur %s" % safe)
		_check_cancel(zone.get_center().x > safe.position.x + safe.size.x * 0.75 and zone.get_center().y < safe.position.y + safe.size.y * 0.5, "zone d'annulation hors du haut à droite")
	for module_id in ["eclipse", "javelin", "fulguro_punch", "pelto_smash"]:
		controls.call("reset_inputs")
		player.call("apply_loadout", {"weapon": "blaster", "offensive": "javelin" if module_id == "eclipse" else module_id, "defensive": "magnetic_field", "mobility": "eclipse" if module_id == "eclipse" else "pyro_boots", "passive": "omnivamp"})
		player.call("reset_combat_state")
		var action := "mobility" if module_id == "eclipse" else "offensive"
		var centers: Dictionary = controls.call("_action_centers")
		var move_center: Vector2 = controls.call("_joystick_center")
		var start: Vector2 = centers[action]
		controls.call("_begin_touch", 60, move_center + Vector2(20, -20))
		controls.call("_begin_touch", 61, start)
		_check_cancel(_is_preparing(player, module_id) and bool(controls.call("_has_cancellable_action")), "%s : maintien sans visée/zone d'annulation" % module_id)
		var zone: Rect2 = controls.call("_cancel_zone_rect")
		controls.call("_begin_touch", 62, start)
		controls.call("_update_touch", 62, zone.get_center())
		controls.call("_end_touch", 62)
		_check_cancel(_is_preparing(player, module_id), "%s : un doigt rejeté a annulé le sort" % module_id)
		controls.call("_update_touch", 60, zone.get_center())
		_check_cancel(_is_preparing(player, module_id), "%s : le doigt du déplacement a annulé le sort" % module_id)
		controls.call("_update_touch", 61, start + Vector2(20, -20))
		_check_cancel(_is_preparing(player, module_id), "%s : la visée normale annule le sort" % module_id)
		# Square corners outside the visible circle must remain ordinary aiming.
		controls.call("_update_touch", 61, zone.position)
		_check_cancel(_is_preparing(player, module_id), "%s : annulation hors du cercle visible" % module_id)
		var move_before: Vector2 = player.get("_touch_move_vector")
		var drag := InputEventScreenDrag.new()
		drag.index = 61
		drag.position = zone.get_center()
		controls.call("_input", drag)
		_check_cancel(not _is_preparing(player, module_id) and str(player.call("get_action_owner")).is_empty(), "%s : sort/action encore actif après annulation" % module_id)
		_check_cancel(float(player.call("get_module_cooldown", module_id)) == 0.0, "%s : annulation volontaire consomme la recharge" % module_id)
		_check_cancel(str(player.get("_attack_label").text).is_empty(), "%s : texte de charge encore visible après annulation" % module_id)
		_check_cancel(not bool(controls.call("_has_cancellable_action")) and float(controls.get("_cancel_feedback_remaining")) > 0.0, "%s : retour d'annulation absent" % module_id)
		_check_cancel(int(controls.get("_joystick_touch")) == 60 and player.get("_touch_move_vector") == move_before, "%s : annulation a interrompu le déplacement" % module_id)
		var preview: Node = player.get("_eclipse").get("_preview") if module_id == "eclipse" else player.get({"javelin": "_javelin_charge_visual", "fulguro_punch": "_fulguro_indicator", "pelto_smash": "_pelto_indicator"}[module_id])
		_check_cancel(preview == null or preview.is_queued_for_deletion(), "%s : tooltip de visée conservé" % module_id)
		controls.call("_update_touch", 61, start)
		controls.call("_end_touch", 61)
		player.call("_update_javelin_charge", 3.0)
		player.call("_update_fulguro_attack", 3.0)
		player.call("_update_pelto_attack", 3.0)
		_check_cancel(not _is_preparing(player, module_id) and not bool(player.call("is_eclipse_travelling")) and not bool(player.get("_fulguro_release_requested")) and not bool(player.get("_pelto_release_requested")) and not bool(player.get("_module_busy")), "%s : retour/relâchement a lancé le sort annulé" % module_id)
		controls.call("_end_touch", 60)
		player.call("reset_combat_state")
		player.get("_controls_component").call("request_module_command", action, false)
		_check_cancel(_is_preparing(player, module_id) and not bool(player.call("can_cancel_aimed_action", action)), "%s : visée clavier exposée comme un maintien tactile" % module_id)
		player.call("cancel_aimed_action", action)
		_check_cancel(_is_preparing(player, module_id), "%s : annulation tactile a interrompu la visée clavier" % module_id)
		controls.hide()
		_check_cancel(str(controls.call("_desktop_cancel_action")) == action, "%s : zone PC absente avec les joysticks masqués" % module_id)
		var motion := InputEventMouseMotion.new()
		motion.position = (controls.call("_cancel_zone_rect") as Rect2).get_center()
		controls.call("_input", motion)
		_check_cancel(not _is_preparing(player, module_id) and float(player.call("get_module_cooldown", module_id)) == 0.0, "%s : annulation souris absente ou recharge consommée" % module_id)
		player.get("_controls_component").call("end_touch_action", action, false)
		_check_cancel(str(player.call("get_action_owner")).is_empty(), "%s : relâchement clavier a relancé le sort annulé" % module_id)
		controls.show()
	# A touch-up can carry the final position without a preceding drag event.
	controls.call("reset_inputs")
	player.call("reset_combat_state")
	controls.hide()
	_check_cancel(not bool(controls.get("_cancel_canvas").visible), "zone d'annulation encore visible avec les contrôles masqués")
	controls.show()
	var centers: Dictionary = controls.call("_action_centers")
	controls.call("_begin_touch", 70, centers.offensive)
	var release := InputEventScreenTouch.new()
	release.index = 70
	release.position = (controls.call("_cancel_zone_rect") as Rect2).get_center()
	release.pressed = false
	controls.call("_input", release)
	_check_cancel(not bool(player.call("is_pelto_preparing")) and not bool(player.get("_pelto_release_requested")), "relâchement directement dans la zone a lancé Pelto")
	# Cancel a buffered hold without interrupting the unrelated active action.
	player.call("reset_combat_state")
	var token := int(player.call("_try_begin_module_action", "projector"))
	controls.call("_begin_touch", 80, centers.offensive)
	_check_cancel(bool(controls.call("_has_cancellable_action")) and not bool(player.call("is_pelto_preparing")), "maintien anticipé sans zone d'annulation")
	controls.call("_update_touch", 80, (controls.call("_cancel_zone_rect") as Rect2).get_center())
	controls.call("_end_touch", 80)
	_check_cancel(str(player.call("get_action_owner")) == "projector", "annulation du maintien anticipé a interrompu un autre sort")
	player.call("_end_module_action", token, "projector")
	player.get("_controls_component").call("execute_buffered_command")
	_check_cancel(not bool(player.call("is_pelto_preparing")), "sort anticipé annulé encore lancé après libération")
	controls.call("reset_inputs")
	player.call("reset_combat_state")
	# A hold queued during an existing cooldown cannot refund that cooldown.
	player.set("_module_cooldowns", {"pelto_smash": 5.0})
	controls.call("_begin_touch", 90, centers.offensive)
	controls.call("_update_touch", 90, (controls.call("_cancel_zone_rect") as Rect2).get_center())
	controls.call("_end_touch", 90)
	_check_cancel(float(player.call("get_module_cooldown", "pelto_smash")) == 5.0, "maintien anticipé annulé a remboursé une recharge antérieure")
	player.call("reset_combat_state")
	controls.call("_begin_touch", 91, centers.offensive)
	var spent := float(player.call("get_module_cooldown", "pelto_smash"))
	controls.call("reset_inputs")
	_check_cancel(spent > 0.0 and float(player.call("get_module_cooldown", "pelto_smash")) == spent, "interruption tactile remboursée comme une annulation volontaire")
	player.call("reset_combat_state")
	controls.call("_begin_touch", 92, centers.offensive)
	controls.call("_end_touch", 92)
	player.call("cancel_aimed_action", "offensive")
	_check_cancel(bool(player.get("_pelto_release_requested")) and float(player.call("get_module_cooldown", "pelto_smash")) > 0.0, "annulation volontaire autorisée après validation du sort")
	player.call("reset_combat_state")
