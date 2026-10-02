extends SceneTree

## Exercise the official menu, natural process loop and real training round trip.
const LOADOUT := preload("res://scripts/loadout_state.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const EXPERIENCE := preload("res://scripts/review_preferences.gd")
var failures: Array[String] = []
var backups: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 120
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	for path in [LOADOUT.SAVE_PATH, LIBRARY.SAVE_PATH, EXPERIENCE.PATH]:
		backups[path] = {"existed": FileAccess.file_exists(path), "bytes": _bytes(path)}
	# This test exercises the complete arm animation regardless of a saved
	# quick-mode preference, then restores the user's original preference.
	var experience := EXPERIENCE.read()
	experience.quick = false
	check(EXPERIENCE.write(experience) == OK, "installation complete configuree pour la fixture")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	# Complete the deferred courtyard work before measuring an installation's
	# wall time, rather than including the cost of loading the main scene.
	for frame in 6:
		await process_frame
	var flow: Node = main.get_node("Interface")
	var garage_button: Button
	for button in main.find_children("*", "Button", true, false):
		if (button as Button).text == "GARAGE":
			garage_button = button
			break
	check(garage_button != null and garage_button.is_visible_in_tree(), "Garage accessible depuis le menu principal")
	if garage_button != null:
		garage_button.pressed.emit()
	else:
		flow.call("_open_equipment")
	await process_frame
	var garage = flow.get("_forge_garage")
	var stage = garage.stage
	var scanner = garage.installation.scanner
	var before: Dictionary = flow.get("loadout").duplicate(true)
	var draft := {"robot": "agile", "weapon": "shotgun", "offensive": "pelto_smash", "defensive": "counter", "mobility": "permutation", "passive": "alternator"}
	for category in draft:
		garage.call("_select_equipment", category, draft[category])
		# The new rack equips through its own cinematic before saving the build.
		if garage.module_installation.active:
			garage.module_installation.finish_now()
	garage.build_name = "TEST INSTALLATION"
	check(flow.get("loadout") == before and _bytes(LOADOUT.SAVE_PATH) == backups[LOADOUT.SAVE_PATH].bytes, "six choix en brouillon sans sauvegarde immediate")
	for frame in 3:
		await process_frame
	garage.get("_save_button").pressed.emit()
	var started := Time.get_ticks_msec()
	var rest: Vector3 = stage.arm.contact.global_position
	var movement := 0.0
	var scanned: Array[String] = []
	check(garage.installation.active and not garage.get("_ui").visible, "Sauvegarder masque tout le menu")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	escape.pressed = false
	root.push_input(escape, true)
	check(garage.visible and int(flow.get("current_screen")) == 1, "Echap ne quitte pas pendant l'installation")
	var unchanged_until_completion := true
	while garage.installation.active and Time.get_ticks_msec() - started < 9000:
		await process_frame
		movement = maxf(movement, stage.arm.contact.global_position.distance_to(rest))
		if scanner.scanning and not scanned.has(scanner.target_zone):
			scanned.append(scanner.target_zone)
		if garage.installation.active:
			unchanged_until_completion = unchanged_until_completion and _bytes(LOADOUT.SAVE_PATH) == backups[LOADOUT.SAVE_PATH].bytes and _bytes(LIBRARY.SAVE_PATH) == backups[LIBRARY.SAVE_PATH].bytes
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	print("ARM RUNTIME elapsed=", elapsed, " movement=", movement, " scanned=", scanned)
	check(not garage.installation.active and elapsed >= 4.8 and elapsed < 8.0, "installation d'environ cinq secondes par les vraies frames")
	check(unchanged_until_completion, "aucun fichier modifie avant la fin du bras")
	check(movement > 0.5 and scanned.size() == 3, "bras et scanner travaillent reellement sur trois parties")
	check(not scanner.enabled and not stage.arm.particles.emitting and garage.get("_ui").visible, "retour au menu avec bras au repos")
	check(flow.get("loadout") == draft and LOADOUT.load_local() == draft, "loadout complet actif dans le combat apres installation")
	var library := LIBRARY.load_local()
	check(library.builds.any(func(entry: Dictionary) -> bool: return entry.id == library.active and entry.name == "TEST INSTALLATION" and entry.loadout == draft), "build nomme relu depuis le disque")
	var installed_bytes := _bytes(LOADOUT.SAVE_PATH)
	var installed_library := _bytes(LIBRARY.SAVE_PATH)
	garage.call("_select_equipment", "passive", "inertia")
	garage.build_name = "BROUILLON A TESTER"
	var trial: Dictionary = garage.call("draft_state")
	garage.call("_test_build")
	await scene_changed
	await process_frame
	var training: Node = current_scene
	check(training.scene_file_path == "res://scenes/training_ground.tscn", "Tester ouvre le vrai terrain d'entrainement")
	check(training.get("_garage_test_session") and training.get("_loadout") == trial.loadout and training.get("player").call("get_passive_id") == "inertia", "le combat de test utilise le brouillon")
	var fighter: Node3D = training.get("player")
	var target: Node3D = training.call("get_training_targets")[1]
	target.position = Vector3(0, 0, 5)
	fighter.position = Vector3(0, 0, 11)
	fighter.call("_set_aim_direction", Vector3.FORWARD)
	fighter.call("_perform_mobility_module")
	await create_timer(1.0).timeout
	check(fighter.position.distance_to(Vector3(0, 0, 5)) < 0.1 and float(fighter.call("get_shield_health")) > 0.0, "Permutation fonctionne sur le sol du terrain de test")
	training.get("_loadout").weapon = "longshot"
	training.call("_apply_loadout")
	check(_bytes(LOADOUT.SAVE_PATH) == installed_bytes and _bytes(LIBRARY.SAVE_PATH) == installed_library, "modifier le terrain de test ne sauvegarde pas le build")
	training.call("_return_to_main_menu")
	await scene_changed
	await process_frame
	var returned_flow: Node = current_scene.get_node("Interface")
	var returned_garage = returned_flow.get("_forge_garage")
	check(returned_garage.visible and int(returned_flow.get("current_screen")) == 1, "retour direct au Garage apres le test")
	trial.loadout.weapon = "longshot"
	check(returned_garage.call("draft_state") == trial, "nom et loadout du brouillon conserves au retour")
	check(returned_flow.get("loadout") == draft and _bytes(LOADOUT.SAVE_PATH) == installed_bytes, "le build sauvegarde reste actif tant que le brouillon n'est pas valide")
	current_scene.queue_free()
	for frame in 8:
		await process_frame
	_restore_files()
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE ARM RUNTIME TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " echecs)")
	quit(0 if failures.is_empty() else 1)


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


func _restore_files() -> void:
	for path in backups:
		if backups[path].existed:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backups[path].bytes)
			file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)
