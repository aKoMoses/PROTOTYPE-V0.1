extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const LIB_PATH := "user://garage-verification-builds.cfg"
const OLD_PATH := "user://garage-verification-loadout.cfg"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	for path in [LIB_PATH, OLD_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var original := LOADOUT.defaults()
	LOADOUT.save_local(original, OLD_PATH)
	var garage := GARAGE.new()
	garage.library_path = LIB_PATH
	garage.legacy_save_path = OLD_PATH
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)
	var saves := [0]
	garage.build_saved.connect(func(_equipment: Dictionary) -> void: saves[0] += 1)
	check(garage.find_child("GarageScanner", true, false) == null, "aucun bouton Scanner")
	check(garage._hub_mode and garage._module_options == null and not garage._module_panel.visible, "le garage ouvre les rangements sans catalogue imposé")
	garage._open_modules("passive")
	check(garage._module_options.columns == 1 and garage._module_options.get_child_count() == 6, "six passifs visibles dans une liste compacte")
	check(garage._training_demo.get_global_rect().position.x > garage._module_panel.get_global_rect().end.x, "la video est dans la fiche a droite")
	for button in garage._choices.passive.values():
		var icon: Control = button.get_node("EquipmentIcon")
		check(Rect2(Vector2.ZERO, button.size).encloses(icon.get_rect()) and icon.get_rect().end.x <= 72, "icone contenue à gauche du nom")
	for category in ["robot", "weapon", "offensive", "defensive", "mobility", "passive"]:
		var options: Array = garage._options(category)
		var id: String = options.back()
		equip(garage, category, id)
		check(garage.loadout[category] == id and LOADOUT.load_local(OLD_PATH) == original, "le choix reste un brouillon : " + category)
		check(garage._detail_description.text == LOADOUT.category_description(id), "la fiche affiche le vrai effet : " + id)
	var expected: Dictionary = garage.loadout.duplicate(true)
	garage._rename_build()
	garage._name_input.text = "ÉCLAIREUR"
	garage._finish_rename()
	garage._save_build()
	garage.installation.set_process(false)
	check(garage.installation.active and not garage._ui.visible and garage._save_button.disabled, "Sauvegarder cache le menu et bloque les clics")
	garage._save_build()
	garage._select_equipment("weapon", "blaster")
	check(garage.loadout == expected and saves[0] == 0, "double clic et changement pendant intervention ignores")
	var rest: Vector3 = garage.stage.arm.contact.global_position
	var movement := 0.0
	for frame in 299:
		garage.installation.advance(1.0 / 60.0)
		movement = maxf(movement, rest.distance_to(garage.stage.arm.contact.global_position))
		if frame % 75 == 0:
			print("INSTALLATION part=", garage.installation.scanner.target_zone, " valid=", garage.installation.scanner.target_valid, " scan=", garage.installation.scanner.scanning, " tip=", garage.stage.arm.contact.global_position)
	check(saves[0] == 0 and LOADOUT.load_local(OLD_PATH) == original, "aucune sauvegarde avant cinq secondes")
	var scanned: Array[String] = garage.installation.scanned_parts.duplicate()
	garage.installation.advance(0.03)
	check(saves[0] == 1 and garage._ui.visible and not garage.installation.active, "une seule sauvegarde a la fin et retour du menu")
	check(LOADOUT.load_local(OLD_PATH) == expected, "les six selections sont conservees pour le combat")
	var reloaded := LIBRARY.load_local(LIB_PATH, OLD_PATH)
	check(reloaded.builds[0].name == "ÉCLAIREUR" and reloaded.builds[0].loadout == expected, "le build nomme survit au rechargement du fichier")
	check(movement > 0.5, "les vraies articulations deplacent l'outil")
	print("INSTALLATION scanned=", scanned, " movement=", movement)
	check(scanned.size() >= 3, "balayage reel de trois parties du robot")
	check(not garage.installation.scanner.enabled and not garage.installation.scanner._motor.playing and not garage.stage.arm.active, "bras, lumiere et son au repos apres sauvegarde")
	garage._duplicate_build()
	garage._name_input.text = "BASTION"
	garage._finish_rename()
	equip(garage, "weapon", "shotgun")
	garage._save_build()
	garage.installation.set_process(false)
	for frame in 301:
		garage.installation.advance(1.0 / 60.0)
	reloaded = LIBRARY.load_local(LIB_PATH, OLD_PATH)
	check(reloaded.builds.size() == 2 and reloaded.builds[0].name == "ÉCLAIREUR" and reloaded.builds[1].name == "BASTION", "une copie cree un deuxieme build sans ecraser le premier")
	var stale_counter := reloaded.duplicate(true)
	stale_counter.next_id = 2
	var extra := LIBRARY.with_build(stale_counter, "", "TROISIEME", expected)
	check(extra.builds.size() == 3 and extra.builds[1].name == "BASTION" and extra.active == "build_3", "un ancien compteur d'identifiants n'ecrase aucun build")
	garage._select_build(0)
	check(garage.loadout == expected and garage.build_name == "ÉCLAIREUR", "la liste recharge toutes les selections du build")
	garage._save_build()
	garage.installation.set_process(false)
	garage.installation.advance(1.0)
	garage.hide()
	check(not garage.installation.active and saves[0] == 2, "fermeture en cours ne sauvegarde pas un brouillon")
	garage.show()
	var failed_path := garage.library_path
	garage.library_path = "user://missing-garage-folder/builds.cfg"
	garage._save_build()
	garage.installation.set_process(false)
	for frame in 301:
		garage.installation.advance(1.0 / 60.0)
	check(saves[0] == 2 and garage._ui.visible and not garage._save_button.disabled, "echec disque signale sans faux succes ni blocage")
	garage.library_path = failed_path
	for chassis in LOADOUT.ROBOTS:
		garage._select_equipment("robot", chassis)
		equip(garage, "mobility", "bio_injector" if chassis == "polyvalent" else "pyro_boots")
		garage._save_build()
		garage.installation.set_process(false)
		for frame in 301:
			garage.installation.advance(1.0 / 60.0)
		print("INSTALLATION chassis=", chassis, " scanned=", garage.installation.scanned_parts)
		check(garage.installation.scanned_parts.size() >= 3, "trois parties atteintes sur le chassis " + chassis)
		if chassis == "polyvalent":
			check(garage.installation.scanned_parts.has("RÉACTEUR"), "Bio Injector dirige le bras sur le reacteur")
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1790, 925)]:
		root.size = dimensions
		await process_frame
		for category in ["robot", "weapon", "offensive", "defensive", "mobility", "passive"]:
			garage._navigate("ROBOT" if category == "robot" else ("ARMES" if category == "weapon" else "MODULES"))
			if not category in ["robot", "weapon"]:
				garage._open_modules(category)
			await process_frame
			for button in garage._choices[category].values():
				check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(button.get_global_rect()), "carte contenue : %s a %s" % [category, dimensions])
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(garage._save_button.get_global_rect()), "Sauvegarder accessible a " + str(dimensions))
	garage.build_name = "ABCDEFGHIJKLMNOPQRSTUVWXYZ12"
	garage._refresh_build_names()
	await process_frame
	check(garage._build_selector.get_rect().end.x < garage._build_menu.position.x and garage._build_selector.clip_text, "les noms longs restent contenus dans le selecteur unique")
	garage.queue_free()
	await process_frame
	for path in [LIB_PATH, OLD_PATH]:
		DirAccess.remove_absolute(path)
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE BUILD INSTALLATION TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " controles, ", failures.size(), " echecs)")
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func equip(garage: Control, category: String, identifier: String) -> void:
	if category == "robot":
		garage._select_equipment(category, identifier)
		return
	garage._open_station(category)
	var before: Dictionary = garage.loadout.duplicate(true)
	(garage._choices[category][identifier] as Button).pressed.emit()
	check(garage.loadout == before and not garage.module_installation.active, "la carte reste un aperçu : " + identifier)
	if str(before[category]) != identifier:
		garage._equip_preview()
		garage.module_installation.set_process(false)
		if category == "weapon" or identifier in garage.module_installation.REAL_MODULES:
			check(garage.module_installation.active and garage.loadout == before, "Équiper attend la fixation : " + identifier)
			garage.module_installation.finish_now()
		else:
			check(not garage.module_installation.active, "un équipement sans modèle s'équipe sans fausse pièce : " + identifier)
	check(str(garage.loadout[category]) == identifier and not garage.module_installation.active, "l'équipement rejoint le brouillon : " + identifier)
	garage.focus.set_process(false)
