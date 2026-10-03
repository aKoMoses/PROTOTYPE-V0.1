extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const CHASSIS_PAINT := preload("res://scripts/robot_chassis_visuals.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
var failures: Array[String] = []
var saved_bytes := PackedByteArray()
var save_existed := false
var library_bytes := PackedByteArray()
var library_existed := false


func _initialize() -> void:
	save_existed = FileAccess.file_exists(LOADOUT.SAVE_PATH)
	if save_existed:
		saved_bytes = FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH)
	library_existed = FileAccess.file_exists(LIBRARY.SAVE_PATH)
	if library_existed:
		library_bytes = FileAccess.get_file_as_bytes(LIBRARY.SAVE_PATH)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var flow: Node = main.get_node("Interface")
	flow.call("_open_equipment")
	await process_frame
	var garage = flow.get("_forge_garage")
	var stage = garage.get("stage")
	var arm = stage.get("arm")
	check(garage.visible and not (flow.get("_equipment_panel") as Control).visible, "le garage est la forge officielle sans ecran intermediaire")
	check(main.find_child("OpenForgeGarage", true, false) == null, "aucun bouton de garage secondaire")
	if main.has_method("set_arena_variant"):
		(garage.arena_buttons["hazards"] as Button).pressed.emit()
		check(str(main.get("arena_variant")) == "hazards", "choix d'arene conserve dans le garage officiel")
	else:
		check(not (garage.arena_buttons["hazards"] as Button).visible, "options d'arene cachees si le mode n'est pas disponible")
	check(stage.viewport.own_world_3d, "monde de rendu isole du combat")
	check(stage.robot_model.scene_file_path == stage.PAINT.model_path(stage.chassis_id), "vrai modele du chassis choisi au centre")
	check(stage.robot_animator.is_playing(), "robot anime dans le garage")
	check(stage.weapon_attachment != null and stage.weapon_socket != null, "arme attachee a la main du vrai squelette")
	for button in garage.get("_nav").values():
		check(button.size == Vector2(133, 36), "onglet compact dans l'entête du garage")
	for button in garage.weapon_buttons.values():
		var icon := button.get_child(0) as Control
		check(Rect2(Vector2.ZERO, button.size).encloses(icon.get_rect()), "icone d'arme contenue dans sa ligne")
		check(button.get_rect().end.x <= 1245 and button.get_rect().end.y < 615, "chaque arme reste visible au-dessus de JOUER")
	check((garage.get("_health") as Label).text.ends_with("PV"), "PV dans le bandeau compact sous le robot")
	check(not stage.automatic_service_enabled, "le bras attend Sauvegarder")
	var weapon_bounds: AABB = stage.call("_bounds", stage.weapon_socket)
	weapon_bounds = stage.weapon_socket.global_transform * weapon_bounds
	check(weapon_bounds.size.length() > 0.7 and weapon_bounds.size.length() < 1.7, "arme normalisee a une taille coherente avec le robot")
	check(arm.animator != null and arm.clip != &"", "animation Blender du bras importee")
	check(arm.animator.get_animation(arm.clip).length >= 9.9, "cycle complet du bras importe")
	check(arm.animator.get_animation(arm.clip).get_track_count() >= 4, "plusieurs articulations animees")
	stage.set_process(false)
	arm.seek_service(0.0)
	var rest: Vector3 = arm.contact.global_position
	arm.seek_service(4.5)
	var contact: Vector3 = arm.contact.global_position
	check(rest.distance_to(contact) > 0.5, "l'outil se deplace reellement vers le chassis")
	check(contact.is_finite() and contact.x > 0.4 and contact.y > 0.8, "contact a l'exterieur du centre du robot")
	arm.seek_service(9.98)
	check((arm.contact.global_position as Vector3).distance_to(rest) < 0.02, "retour reel du mecanisme au repos")
	arm.cancel_service()
	check(stage.inspect_robot(), "inspection manuelle declenchee")
	check(not stage.inspect_robot(), "une deuxieme inspection ne coupe pas la trajectoire")
	arm.advance_service(4.2)
	check(arm.active and arm.particles.emitting, "etincelles synchronisees a l'intervention")
	await check_robot_rotation(garage, stage)
	await check_robot_gestures(garage, stage)
	var before: Dictionary = flow.get("loadout").duplicate(true)
	var saved_before: Dictionary = LOADOUT.load_local()
	var shared_shader_code: String = CHASSIS_PAINT.PAINT_SHADER.code
	for identifier in LOADOUT.ROBOTS:
		(garage.robot_buttons[identifier] as Button).pressed.emit()
		check(str(garage.loadout.robot) == identifier and flow.get("loadout") == before and LOADOUT.load_local() == saved_before, "choix chassis en brouillon : " + identifier)
		check(stage.chassis_id == identifier, "apparence du robot central actualisee : " + identifier)
		if CHASSIS_PAINT.PROFILES.has(identifier):
			var armour := stage.robot_model.find_child("tripo_part_0", true, false) as MeshInstance3D
			var painted := armour.get_active_material(0) as ShaderMaterial
			check(painted != null and painted.shader != CHASSIS_PAINT.PAINT_SHADER, "shader du garage independant du combat")
			check(painted.get_shader_parameter("panel_color") == CHASSIS_PAINT.PROFILES[identifier].panel_color, "couleur du chassis conservee dans le garage")
		check(flow.get("loadout").offensive == before.offensive, "module preserve au changement de robot")
	check(not arm.active, "changement de chassis remet le bras en position sure")
	check(CHASSIS_PAINT.PAINT_SHADER.code == shared_shader_code, "shader de camouflage du combat preserve")
	garage._navigate("ARMES")
	check(garage.focus.station_category == "weapon" and stage.weapon_rack.items.size() == LOADOUT.WEAPONS.size(), "ARMES ouvre le ratelier distinct avec les quatre vrais modeles")
	for identifier in LOADOUT.WEAPONS:
		var weapon_before: Dictionary = garage.loadout.duplicate(true)
		var stage_weapon_before: String = stage.weapon_id
		(garage.weapon_buttons[identifier] as Button).pressed.emit()
		check(garage._preview_id == identifier and garage.loadout == weapon_before and stage.weapon_id == stage_weapon_before and not garage.module_installation.active, "la ligne montre l'arme sans changer le brouillon : " + identifier)
		garage.equip_button.pressed.emit()
		if str(weapon_before.weapon) == identifier:
			check(not garage.module_installation.active and garage.loadout == weapon_before, "arme deja installee ne relance pas le bras : " + identifier)
		else:
			check(garage.module_installation.active and garage.loadout == weapon_before, "Equiper attend la fixation de l'arme avant le brouillon : " + identifier)
			garage.module_installation.finish_now()
		check(stage.weapon_id == identifier and garage.loadout.weapon == identifier and LOADOUT.load_local() == saved_before, "choix d'arme en brouillon apres le transport : " + identifier)
		var model := stage.weapon_socket.get_child(0).get_child(0) as Node3D
		check(model.scene_file_path == stage.WEAPON_MODELS[identifier].resource_path, "bon modele 3D dans la main : " + identifier)
		var box: AABB = stage.weapon_socket.global_transform * stage.call("_bounds", stage.weapon_socket)
		check(box.size.length() > 0.7 and box.size.length() < 2.1, "taille coherente de chaque arme : " + identifier)
	(garage.weapon_buttons["shotgun"] as Button).pressed.emit()
	garage.equip_button.pressed.emit()
	if garage.module_installation.active:
		garage.module_installation.finish_now()
	check(stage.weapon_id == "shotgun" and garage.loadout.weapon == "shotgun", "vrai shotgun et selection en brouillon")
	var module_baseline: Dictionary = garage.loadout.duplicate(true)
	module_baseline.defensive = "counter"
	module_baseline.passive = "auxiliary_reactor"
	garage.restore_draft({"loadout": module_baseline, "name": garage.build_name, "id": garage.build_id})
	garage.call("_open_modules", "passive")
	var picker: GridContainer = garage.get("_module_options")
	check(picker.columns == 1, "modules presentes en liste lisible")
	var passive_before: Dictionary = garage.loadout.duplicate(true)
	(garage._choices.passive["omnivamp"] as Button).pressed.emit()
	check(garage.loadout == passive_before and not garage.module_installation.active, "aperçu d'Omnivamp conserve le brouillon")
	garage.equip_button.pressed.emit()
	check(garage.module_installation.active and garage.loadout == passive_before, "le passif réel est transporté avant de modifier le brouillon")
	garage.module_installation.finish_now()
	check(garage.loadout.passive == "omnivamp" and not garage.module_installation.active and flow.get("loadout") == before and LOADOUT.load_local() == saved_before, "passif fixé sans écraser le build actif ni sa sauvegarde")
	garage.call("_open_modules", "defensive")
	var defense := "magnetic_field"
	var draft_before: Dictionary = garage.loadout.duplicate(true)
	(garage._choices.defensive[defense] as Button).pressed.emit()
	check(garage.loadout == draft_before and not garage.module_installation.active, "la carte affiche le module sans l'équiper")
	garage.equip_button.pressed.emit()
	check(garage.module_installation.active and garage.loadout == draft_before, "Équiper lance le bras avant de modifier le brouillon")
	garage.module_installation.finish_now()
	check(garage.loadout.defensive == defense and flow.get("loadout") == before and LOADOUT.load_local() == saved_before, "module fixé sans écraser le build actif")
	garage.call("_save_build")
	check(not garage.get("_ui").visible, "l'interface disparait pour l'installation")
	garage.installation.set_process(false)
	for step in 301:
		garage.installation.advance(1.0 / 60.0)
	check(flow.get("loadout") == garage.loadout and LOADOUT.load_local() == garage.loadout, "le loadout complet arrive au combat apres l'installation")
	garage.emit_signal("back_requested")
	await process_frame
	check(not garage.visible and int(flow.get("current_screen")) == 0, "retour du garage vers le menu principal")
	check(stage.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not stage.is_processing(), "rendu et animations suspendus hors du garage")
	flow.call("_open_equipment")
	await process_frame
	check(garage.visible and garage.loadout.weapon == "shotgun", "reouverture conserve l'equipement")
	garage.emit_signal("start_requested")
	await process_frame
	check(not garage.visible, "entree en duel ferme le garage")
	check(main.get_node("Player").call("get_robot_id") == "puissant", "chassis du garage transmis au combat")
	flow.set_process(false)
	for audio_node in main.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	await create_timer(0.1).timeout
	main.queue_free()
	await process_frame
	if save_existed:
		var file := FileAccess.open(LOADOUT.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved_bytes)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOADOUT.SAVE_PATH))
	if library_existed:
		var file := FileAccess.open(LIBRARY.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(library_bytes)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LIBRARY.SAVE_PATH))
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE GARAGE TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " echecs)")
	quit(0 if failures.is_empty() else 1)


func check_robot_rotation(garage: Control, stage) -> void:
	var original_angle: float = stage.robot.rotation.y
	var original_camera: Transform3D = stage.camera.global_transform
	var original_position: Vector3 = stage.robot.global_position
	var original_loadout: Dictionary = garage.loadout.duplicate(true)
	stage.set_weapon(stage.weapon_id)
	var point: Vector2 = stage.camera.unproject_position(original_position + Vector3(0, 1.5, 0)) * stage.size / Vector2(stage.viewport.size)
	check(stage.is_robot_at_position(point), "le clic vise le vrai robot projete par la camera")
	await mouse_button(point, true)
	await mouse_motion(point + Vector2(160, 0), Vector2(160, 0), true)
	check(absf(angle_difference(original_angle, stage.robot.rotation.y)) > 0.5, "le clic maintenu et le deplacement tournent le robot via les entrees GUI")
	check(not stage.arm.active and not stage.arm.particles.emitting, "la manipulation met le bras et ses etincelles au repos")
	check(stage.camera.global_transform.is_equal_approx(original_camera) and stage.robot.global_position.is_equal_approx(original_position), "le robot tourne sur place avec une camera fixe")
	var socket_before: Transform3D = stage.weapon_socket.transform
	stage.set_weapon(stage.weapon_id)
	check(stage.weapon_socket.transform.is_equal_approx(socket_before), "changer l'arme apres rotation conserve sa pose dans la main")
	var rotated_angle: float = stage.robot.rotation.y
	await mouse_button(point + Vector2(160, 0), false)
	await mouse_motion(point, Vector2(-160, 0), false)
	stage.call("_process", 20.0)
	check(is_equal_approx(stage.robot.rotation.y, rotated_angle) and not stage.arm.active, "relachement conserve l'angle sans redemarrer le bras sur le robot tourne")
	await mouse_button(Vector2(350, 60), true)
	await mouse_motion(Vector2(510, 60), Vector2(160, 0), true)
	await mouse_button(Vector2(510, 60), false)
	check(is_equal_approx(stage.robot.rotation.y, rotated_angle), "cliquer le decor ne fait pas tourner le robot")
	var button: Button = garage._nav["MODULES"]
	var button_point: Vector2 = button.get_global_rect().get_center()
	await mouse_button(button_point, true)
	await mouse_motion(button_point + Vector2(12, 0), Vector2(12, 0), true)
	await mouse_button(button_point + Vector2(12, 0), false)
	check(is_equal_approx(stage.robot.rotation.y, rotated_angle), "les boutons restent utilisables sans declencher la rotation")
	garage._show_garage(false)
	garage.get("_module_panel").hide()
	point = stage.camera.unproject_position(original_position + Vector3(0, 1.5, 0)) * stage.size / Vector2(stage.viewport.size)
	await mouse_button(point, true)
	await mouse_motion(point - Vector2(160, 0), Vector2(-160, 0), true)
	check(is_equal_approx(stage.robot.rotation.y, original_angle), "le mouvement inverse ramene le robot a son angle initial")
	garage.notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	var stopped_angle: float = stage.robot.rotation.y
	await mouse_motion(point, Vector2(160, 0), true)
	await mouse_button(point, false)
	check(is_equal_approx(stage.robot.rotation.y, stopped_angle), "perdre le focus arrete la manipulation")
	await mouse_button(point, true)
	garage.hide()
	garage.show()
	await mouse_motion(point, Vector2(160, 0), true)
	await mouse_button(point, false)
	check(is_equal_approx(stage.robot.rotation.y, stopped_angle), "fermer et rouvrir la forge ne conserve pas un clic bloque")
	check(garage.loadout == original_loadout, "la rotation ne modifie pas l'equipement")
	stage.set_process(false)
	if "--capture-rotation" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/forge-garage/rotation-front.png")
		await mouse_button(point, true)
		await mouse_motion(point + Vector2(garage.size.x * 0.25, 0), Vector2(garage.size.x * 0.25, 0), true)
		await mouse_button(point + Vector2(garage.size.x * 0.25, 0), false)
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/forge-garage/rotation-back.png")
	check(stage.inspect_robot() and is_equal_approx(stage.robot.rotation.y, original_angle), "une inspection manuelle remet le robot face au bras")
	stage.arm.cancel_service()


func check_robot_gestures(garage: Control, stage) -> void:
	var position: Vector3 = stage.robot.position
	var angle: float = stage.robot.rotation.y
	var equipment: Dictionary = garage.loadout.duplicate(true)
	var clips: Array = stage.get("_gesture_clips")
	check(clips.size() == 5, "cinq gestes ambiants disponibles dans le garage")
	if clips.is_empty():
		return
	stage.arm.cancel_service()
	stage.set("_pending_reaction", &"")
	stage.call("_return_to_idle", 0.0)
	stage.set("_next_service", 1000.0)
	stage.set("_next_gesture", 0.02)
	stage.call("_process", 0.01)
	check(stage.robot_animator.current_animation == stage.idle_clip, "le robot attend avant son premier geste")
	stage.call("_process", 0.02)
	var first: StringName = stage.get("_gesture_clip")
	check(first in clips and stage.robot_animator.current_animation == first, "un geste commence automatiquement apres le delai")
	for cycle in range(2):
		var selected: StringName = stage.get("_gesture_clip")
		var clip: Animation = stage.robot_animator.get_animation(selected)
		check(clip.loop_mode == Animation.LOOP_NONE, "chaque geste ne joue qu'une fois")
		var bank_clip := String(selected).get_slice("/", 1)
		check(clip != stage.CONTEXT_BANK.LIBRARY.get_animation(bank_clip), "les clips du garage sont independants de la bibliotheque partagee")
		stage.call("_process", 1.5)
		stage.skeleton.force_update_all_bone_transforms()
		var hand_before: Transform3D = stage.skeleton.get_bone_global_pose(stage.weapon_attachment.bone_idx)
		stage.call("_process", 0.5)
		stage.skeleton.force_update_all_bone_transforms()
		check(not stage.skeleton.get_bone_global_pose(stage.weapon_attachment.bone_idx).is_equal_approx(hand_before), "la main du squelette portant l'arme bouge reellement pendant le geste")
		if "--capture-gestures" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			for frame in range(8):
				await process_frame
			await RenderingServer.frame_post_draw
			var label := String(selected).get_slice("/", String(selected).get_slice_count("/") - 1)
			root.get_texture().get_image().save_png("res://captures/forge-garage/gesture-" + label + ".png")
			for fraction in [0.5, 0.8]:
				stage.robot_animator.seek(clip.length * fraction, true)
				stage.robot_animator.advance(0.0)
				for frame in range(8):
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://captures/forge-garage/gesture-%s-%d.png" % [label, int(fraction * 100)])
		stage.call("_process", clip.length / stage.GESTURE_SPEED + 0.1)
		check(stage.get("_gesture_clip") == &"" and stage.robot_animator.current_animation == stage.idle_clip, "retour automatique a l'attente apres le geste")
		var delay: float = stage.get("_next_gesture")
		check(delay >= 8.0 and delay <= 14.0, "repos de huit a quatorze secondes entre les gestes")
		check(stage.robot.position.is_equal_approx(position) and is_equal_approx(stage.robot.rotation.y, angle), "les gestes conservent la plateforme et l'angle choisi")
		stage.set("_next_gesture", 0.0)
		stage.call("_process", 0.01)
		if cycle == 0:
			check(stage.get("_gesture_clip") != first, "pas de repetition immediate du meme geste")
	stage.begin_robot_rotation()
	var delay_during_drag: float = stage.get("_next_gesture")
	stage.call("_process", 2.0)
	check(stage.get("_gesture_clip") == &"" and is_equal_approx(stage.get("_next_gesture"), delay_during_drag), "le clic maintenu interrompt les gestes et suspend leur delai")
	stage.end_robot_rotation()
	stage.set("_next_gesture", 0.0)
	stage.call("_process", 0.01)
	check(stage.inspect_robot() and stage.get("_gesture_clip") == &"", "l'inspection interrompt un geste et rend le robot au bras")
	var delay_during_service: float = stage.get("_next_gesture")
	stage.call("_process", 2.0)
	check(stage.get("_gesture_clip") == &"" and is_equal_approx(stage.get("_next_gesture"), delay_during_service), "aucun geste pendant l'intervention du bras")
	stage.arm.cancel_service()
	stage.set("_next_gesture", 0.1)
	garage.hide()
	stage.call("_process", 20.0)
	check(is_equal_approx(stage.get("_next_gesture"), 0.1), "le temps cache ne declenche pas de geste")
	garage.show()
	stage.set("_pending_reaction", &"")
	stage.set_process(false)
	stage.set("_next_gesture", 0.0)
	stage.call("_process", 0.01)
	stage.set_weapon(stage.weapon_id)
	check(stage.get("_gesture_clip") == &"", "changer l'arme pendant un geste remet le robot en attente")
	check(garage.loadout == equipment, "les gestes ne modifient pas l'equipement")
	stage.set_equipment_focus(true)
	stage.set("_approval_index", 0)
	stage.react_to_installation(true)
	stage.call("_process", 0.5)
	check(stage.get("_gesture_clip") == &"" and stage.get("_pending_reaction") == &"context/agree", "l'approbation attend la fin de l'inspection")
	stage.set_equipment_focus(false)
	stage.call("_process", 0.01)
	check(stage.get("_gesture_clip") == &"context/agree", "une sauvegarde reussie recoit l'approbation")
	stage.robot_animator.advance(0.35)
	stage.robot_animator.advance(0.01)
	var right_arm: int = stage.skeleton.find_bone("mixamorig_RightArm")
	var carried_rotation: Quaternion = stage.skeleton.get_bone_pose_rotation(right_arm)
	stage.robot_animator.seek(2.6, true)
	stage.robot_animator.advance(0.0)
	check(stage.skeleton.get_bone_pose_rotation(right_arm).is_equal_approx(carried_rotation), "l'approbation conserve le bras portant l'arme")
	stage.set("_failure_index", 0)
	stage.react_to_installation(false)
	stage.call("_process", 0.01)
	check(stage.get("_gesture_clip") == &"context/frustrated_01", "l'echec de sauvegarde recoit une reaction distincte")
	garage.hide()
	stage.set("_welcome_index", 0)
	garage.show()
	stage.set_process(false)
	stage.call("_process", 0.01)
	check(stage.get("_gesture_clip") == &"context/greet_02", "le robot salue a l'ouverture du Garage")
	stage.robot_animator.advance(0.35)
	stage.robot_animator.advance(0.01)
	carried_rotation = stage.skeleton.get_bone_pose_rotation(right_arm)
	stage.robot_animator.seek(3.6, true)
	stage.robot_animator.advance(0.0)
	stage.skeleton.force_update_all_bone_transforms()
	var free_hand: int = stage.skeleton.find_bone("mixamorig_LeftHand")
	var shoulder: int = stage.skeleton.find_bone("mixamorig_LeftShoulder")
	var hand_position: Vector3 = stage.skeleton.global_transform * stage.skeleton.get_bone_global_pose(free_hand).origin
	var shoulder_position: Vector3 = stage.skeleton.global_transform * stage.skeleton.get_bone_global_pose(shoulder).origin
	check(hand_position.y > shoulder_position.y, "le salut leve la main libre au-dessus de l'epaule")
	check(stage.skeleton.get_bone_pose_rotation(right_arm).is_equal_approx(carried_rotation), "le salut garde l'arme dans le bras droit")
	var greetings: Array[StringName] = []
	for _cycle in range(4):
		garage.hide()
		garage.show()
		stage.set_process(false)
		stage.call("_process", 0.01)
		greetings.append(stage.get("_gesture_clip"))
	check(greetings.size() == 4 and greetings[0] != greetings[1] and greetings[1] != greetings[2] and greetings[2] != greetings[3], "quatre salutations alternent entre les ouvertures")
	var approvals: Array[StringName] = []
	for _cycle in range(3):
		stage.react_to_installation(true)
		stage.call("_process", 0.01)
		approvals.append(stage.get("_gesture_clip"))
	check(approvals[0] != approvals[1] and approvals[1] != approvals[2] and approvals[0] != approvals[2], "trois approbations alternent entre les installations")
	stage.call("_return_to_idle", 0.0)
	stage.set("_next_service", 15.0)
	stage.call("_schedule_gesture")


func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func mouse_motion(point: Vector2, relative: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await process_frame


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
