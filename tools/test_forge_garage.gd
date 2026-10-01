extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const CHASSIS_PAINT := preload("res://scripts/robot_chassis_visuals.gd")
var failures: Array[String] = []
var saved_bytes := PackedByteArray()
var save_existed := false


func _initialize() -> void:
	save_existed = FileAccess.file_exists(LOADOUT.SAVE_PATH)
	if save_existed:
		saved_bytes = FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH)
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
	check(stage.robot_model.scene_file_path == "res://art/player_mecha_animated.glb", "vrai modele de combat au centre")
	check(stage.robot_animator.is_playing(), "robot anime dans le garage")
	check(stage.weapon_attachment != null and stage.weapon_socket != null, "arme attachee a la main du vrai squelette")
	for button in garage.get("_nav").values():
		check((button.get_child(0) as Control).size == Vector2(44, 44), "icone de navigation contenue dans son bouton")
	for button in garage.weapon_buttons.values():
		var icon := button.get_child(0) as Control
		check(icon.size.x <= button.size.x and icon.size.y < button.size.y - 24, "icone d'arme contenue dans sa carte")
		check(button.get_rect().end.x <= 1245 and button.get_rect().end.y < 615, "chaque arme reste visible au-dessus de JOUER")
	check((garage.get("_health_bar") as Control).size.y <= 6.0, "barres compactes dans le panneau de statistiques")
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
	var before: Dictionary = flow.get("loadout").duplicate(true)
	var shared_shader_code: String = CHASSIS_PAINT.PAINT_SHADER.code
	for identifier in LOADOUT.ROBOTS:
		(garage.robot_buttons[identifier] as Button).pressed.emit()
		check(str(flow.get("loadout").robot) == identifier and LOADOUT.load_local().robot == identifier, "choix chassis transmis et sauvegarde : " + identifier)
		check(stage.chassis_id == identifier, "apparence du robot central actualisee : " + identifier)
		if CHASSIS_PAINT.PROFILES.has(identifier):
			var armour := stage.robot_model.find_child("tripo_part_0", true, false) as MeshInstance3D
			var painted := armour.get_active_material(0) as ShaderMaterial
			check(painted != null and painted.shader != CHASSIS_PAINT.PAINT_SHADER, "shader du garage independant du combat")
			check(painted.get_shader_parameter("panel_color") == CHASSIS_PAINT.PROFILES[identifier].panel_color, "couleur du chassis conservee dans le garage")
		check(flow.get("loadout").offensive == before.offensive, "module preserve au changement de robot")
	check(not arm.active, "changement de chassis remet le bras en position sure")
	check(CHASSIS_PAINT.PAINT_SHADER.code == shared_shader_code, "shader de camouflage du combat preserve")
	for identifier in LOADOUT.WEAPONS:
		(garage.weapon_buttons[identifier] as Button).pressed.emit()
		check(stage.weapon_id == identifier and LOADOUT.load_local().weapon == identifier, "choix d'arme transmis et sauvegarde : " + identifier)
		var model := stage.weapon_socket.get_child(0).get_child(0) as Node3D
		check(model.scene_file_path == stage.WEAPON_MODELS[identifier].resource_path, "bon modele 3D dans la main : " + identifier)
		var box: AABB = stage.weapon_socket.global_transform * stage.call("_bounds", stage.weapon_socket)
		check(box.size.length() > 0.7 and box.size.length() < 2.1, "taille coherente de chaque arme : " + identifier)
	(garage.weapon_buttons["shotgun"] as Button).pressed.emit()
	check(stage.weapon_id == "shotgun" and LOADOUT.load_local().weapon == "shotgun", "vrai shotgun et selection sauvegardee")
	garage.call("_open_modules", "defensive")
	var picker: VBoxContainer = garage.get("_module_options")
	(picker.get_child(1) as Button).pressed.emit()
	check(flow.get("loadout").defensive == "static_shield" and LOADOUT.load_local().defensive == "static_shield", "module selectionne dans le nouveau garage")
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
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE GARAGE TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " echecs)")
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
