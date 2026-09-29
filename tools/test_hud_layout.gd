extends SceneTree

const LAYOUT := preload("res://scripts/hud_layout.gd")

func _initialize() -> void:
	var defaults: Dictionary = LAYOUT.standard()
	for identifier in ["move", "aim", "offensive_button", "defensive_button", "mobility_button", "weapon_button", "player_vitals", "match_summary", "pause", "spell_bar", "offensive_slot", "defensive_slot", "mobility_slot"]:
		if not defaults.has(identifier):
			_fail("Identifiant manquant : " + identifier)
			return
	var bad := {"move": {"s": 200.0, "o": -4.0, "v": false, "d": [99.0, -99.0]}, "pause": {"v": false}}
	var clean: Dictionary = LAYOUT.sanitize(bad)
	if float(clean.move.s) > 1.65 or float(clean.move.o) < 0.35 or bool(clean.pause.v) == false:
		_fail("Validation des données hors limites")
		return
	var safe := Rect2(20, 20, 1240, 680)
	var left: Dictionary = LAYOUT.left_handed()
	if LAYOUT.center(left.move, safe).x <= safe.get_center().x or LAYOUT.center(left.aim, safe).x >= safe.get_center().x:
		_fail("Disposition gaucher")
		return
	var item: Dictionary = defaults.move.duplicate(true)
	var desired := Vector2(432, 512)
	LAYOUT.set_center(item, desired, safe, Vector2(150, 150))
	if LAYOUT.center(item, safe).distance_to(desired) > 0.01:
		_fail("Conversion position / ancrage")
		return
	var wide := Rect2(20, 20, 2100, 680)
	if absf((LAYOUT.center(defaults.aim, safe).x - safe.end.x) - (LAYOUT.center(defaults.aim, wide).x - wide.end.x)) > 0.01:
		_fail("Ancrage sur écran allongé")
		return
	var partial: Dictionary = LAYOUT.sanitize({"move": {"s": 1.2}, "future_widget": {"s": 1.3}})
	if not partial.has("future_widget") or float(partial.aim.s) != 1.0:
		_fail("Migration partielle / widget futur")
		return
	var primary := "res://captures/_hud_layout_test.json"
	var backup := "res://captures/_hud_layout_test.backup.json"
	var temporary := "res://captures/_hud_layout_test.tmp.json"
	var first := {"version": LAYOUT.VERSION, "families": {"mobile": {"saved": defaults}}}
	var second := {"version": LAYOUT.VERSION, "families": {"mobile": {"saved": left}}}
	if not LAYOUT.save_document(first, primary, backup, temporary) or not LAYOUT.save_document(second, primary, backup, temporary):
		_fail("Écriture résistante aux interruptions")
		return
	var corrupt := FileAccess.open(primary, FileAccess.WRITE)
	corrupt.store_string("{")
	corrupt.close()
	var recovered: Dictionary = LAYOUT.load_from_paths(primary, backup)
	if LAYOUT.center(recovered.families.mobile.saved.move, safe).x != LAYOUT.center(defaults.move, safe).x:
		_fail("Repli sur la dernière configuration valide")
		return
	if not LAYOUT.save_document(second, primary, backup, temporary) or not LAYOUT.save_document(first, primary, backup, temporary):
		_fail("Écrasement de la copie de secours")
		return
	corrupt = FileAccess.open(primary, FileAccess.WRITE)
	corrupt.store_string("{")
	corrupt.close()
	recovered = LAYOUT.load_from_paths(primary, backup)
	if LAYOUT.center(recovered.families.mobile.saved.move, safe).x != LAYOUT.center(left.move, safe).x:
		_fail("Sauvegardes successives et copie de secours")
		return
	var malformed := FileAccess.open(primary, FileAccess.WRITE)
	malformed.store_string('{"version":1,"families":{"mobile":"invalid","desktop":{"saved":{"move":{"s":"huge"}},"active_slot":false}}}')
	malformed.close()
	var repaired: Dictionary = LAYOUT.load_from_paths(primary, backup)
	if repaired.families.has("mobile") or float(repaired.families.desktop.saved.move.s) != 1.0 or repaired.families.desktop.active_slot != "standard":
		_fail("Enregistrement partiel ou de mauvais type")
		return
	malformed = FileAccess.open(primary, FileAccess.WRITE)
	malformed.store_string('{"version":"invalid","families":{}}')
	malformed.close()
	recovered = LAYOUT.load_from_paths(primary, backup)
	if LAYOUT.center(recovered.families.mobile.saved.move, safe).x != LAYOUT.center(left.move, safe).x:
		_fail("Version de mauvais type et copie de secours")
		return
	for path in [primary, backup, temporary]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var controller: Node = flow.get_node("HudLayoutController")
	var editor: Control = flow.get_node("HudEditor")
	var touch: Control = flow.get_node("TouchControls")
	for identifier in ["move", "aim", "player_vitals", "match_summary", "pause", "spell_bar", "offensive_slot", "defensive_slot", "mobility_slot"]:
		if not controller.ids().has(identifier):
			_fail("Widget absent du registre : " + identifier)
			return
	flow.call("_open_settings")
	flow.call("_open_hud_editor")
	if not editor.visible or not bool(touch.get("_editor_editing")):
		_fail("Ouverture de l'éditeur")
		return
	editor.call("select", "move")
	var old_scale := float(editor.get("draft")["move"].s)
	editor.call("_on_size_changed", old_scale + 0.1)
	if float(editor.get("draft")["move"].s) <= old_scale:
		_fail("Modification de taille")
		return
	editor.call("_undo")
	if absf(float(editor.get("draft")["move"].s) - old_scale) > 0.001:
		_fail("Historique annuler")
		return
	editor.call("_redo")
	if float(editor.get("draft")["move"].s) <= old_scale:
		_fail("Historique rétablir")
		return
	editor.call("_undo")
	var before_center: Vector2 = controller.widget_rect("move").get_center()
	var press := InputEventScreenTouch.new()
	press.index = 17
	press.pressed = true
	press.position = before_center + Vector2(10, 0)
	editor.call("_input", press)
	var drag := InputEventScreenDrag.new()
	drag.index = 17
	drag.position = press.position + Vector2(100, -40)
	editor.call("_input", drag)
	var release := InputEventScreenTouch.new()
	release.index = 17
	release.pressed = false
	release.position = drag.position
	editor.call("_input", release)
	var after_center: Vector2 = controller.widget_rect("move").get_center()
	if after_center.distance_to(before_center) < 40 or editor.get("undo_stack").size() != 1:
		_fail("Glissement et action d'historique unique")
		return
	editor.call("_undo")
	if controller.widget_rect("move").get_center().distance_to(before_center) > 0.01:
		_fail("Annuler le glissement")
		return
	var group_before: Rect2 = controller.widget_rect("offensive_slot")
	controller.set_widget_center("spell_bar", controller.widget_rect("spell_bar").get_center() + Vector2(30, -30))
	if controller.widget_rect("offensive_slot").get_center().distance_to(group_before.get_center()) < 20:
		_fail("Déplacement collectif des modules")
		return
	controller.set_layout(editor.get("draft"))
	editor.call("select", "offensive_slot")
	editor.call("_on_visible_toggled", false)
	if bool(editor.get("draft")["offensive_slot"].v) or editor.get("selection") != "offensive_slot":
		_fail("Récupération d'un emplacement masqué")
		return
	editor.call("_undo")
	var original_player: Node = flow.get("player")
	var original_health := float(original_player.call("get_health"))
	editor.call("_start_test")
	if flow.get("player") == original_player or not editor.get("test_mode"):
		_fail("Joueur temporaire du mode test")
		return
	var trial_player: Node = flow.get("player")
	var trial_start: Vector3 = trial_player.global_position
	touch.call("_begin_touch", 41, touch.call("_joystick_center") + Vector2(40, -20))
	touch.call("_begin_touch", 42, touch.call("_aim_center") + Vector2(30, -30))
	for _frame in range(10):
		await process_frame
	if trial_player.global_position.distance_to(trial_start) < 0.01:
		_fail("Déplacement dans l'essai")
		return
	touch.call("_end_touch", 42)
	editor.call("_finish_test")
	if flow.get("player") != original_player or absf(float(original_player.call("get_health")) - original_health) > 0.001 or int(touch.get("_aim_touch")) != -1:
		_fail("Restauration du joueur après test")
		return
	editor.call("_discard_and_close")
	if editor.visible or bool(touch.get("_editor_editing")):
		_fail("Annulation de l'édition")
		return
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1024, 600)]:
		root.size = dimensions
		await process_frame
		controller.apply()
		var current_safe: Rect2 = LAYOUT.safe_rect(root)
		for identifier in controller.ids():
			var widget: Rect2 = controller.widget_rect(identifier)
			if not current_safe.grow(2).encloses(widget):
				_fail("Widget hors zone sûre (%s, %s)" % [identifier, dimensions])
				return
	scene.queue_free()
	await process_frame
	var survival: Node = load("res://scenes/survival.tscn").instantiate()
	root.add_child(survival)
	current_scene = survival
	await process_frame
	survival.set("_state", "pause")
	survival.call("_open_hud_editor")
	var survival_editor: Control = survival.get_node("SurvivalUI/HudEditor")
	if not survival_editor.visible or not survival.get_node("HudLayoutController").ids().has("wave"):
		_fail("Intégration Survie")
		return
	survival_editor.call("_start_test")
	survival_editor.call("_finish_test")
	survival_editor.call("_discard_and_close")
	paused = false
	survival.queue_free()
	await process_frame
	var training: Node = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(training)
	current_scene = training
	await process_frame
	training.call("_toggle_menu")
	training.call("_open_hud_editor")
	var training_editor: Control = training.get_node("TrainingUI/HudEditor")
	if not training_editor.visible or not training.get_node("HudLayoutController").ids().has("training_menu"):
		_fail("Intégration Entraînement")
		return
	training_editor.call("_start_test")
	training_editor.call("_finish_test")
	training_editor.call("_discard_and_close")
	paused = false
	print("P0 HUD LAYOUT/EDITOR TEST: PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	quit(1)
