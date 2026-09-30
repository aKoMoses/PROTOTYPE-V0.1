extends SceneTree

## Actual forge cards, imported weapon meshes and camera framing, with isolated
## user data supplied by the runner. No combat scene or imported GLB is edited.
const LOADOUT := preload("res://scripts/loadout_state.gd")
const EQUIPMENT_FORGE_PREVIEW := preload("res://scripts/equipment_forge_preview.gd")
const MODEL_PATHS := {
	"blaster": "res://art/player_heavy_blaster.glb",
	"shotgun": "res://art/player_shotgun.glb",
	"mekatana": "res://art/weapons/mekatana.glb",
}
var _failures: Array[String] = []
var _checks := 0
var _save_existed := false
var _saved_bytes := PackedByteArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "preview_only" in OS.get_cmdline_user_args():
		await _run_preview_only()
		return
	_save_existed = FileAccess.file_exists(LOADOUT.SAVE_PATH)
	if _save_existed:
		_saved_bytes = FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH)
	LOADOUT.save_local(LOADOUT.defaults())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	flow.call("_open_equipment")
	flow.call("_open_equipment_category", "weapon")
	await process_frame
	await process_frame
	var choices: Dictionary = flow.get("_selection_buttons")["weapon"]
	_check(choices.size() == LOADOUT.WEAPONS.size(), "la forge affiche toutes les armes jouables")
	for identifier in MODEL_PATHS:
		_check(LOADOUT.WEAPONS.has(identifier) and choices.has(identifier), "les trois armes avec GLB connu restent disponibles : " + identifier)
	var previews: Array[Node] = []
	var worlds: Array[World3D] = []
	var angles: Array[float] = []
	for identifier in LOADOUT.WEAPONS:
		_check(choices.has(identifier), "carte disponible pour l'arme jouable : " + identifier)
		var button := choices.get(identifier) as Button
		var view := button.find_child("WeaponPreview", true, false) if button != null else null
		var expected_path: String = MODEL_PATHS.get(identifier, "res://art/weapons/%s.glb" % identifier)
		var expects_preview := MODEL_PATHS.has(identifier) or ResourceLoader.exists(expected_path, "PackedScene")
		if not expects_preview:
			_check(button != null and view == null and not button.find_children("*", "TextureRect", true, false).is_empty(), "l'arme sans GLB disponible conserve son icône 2D : " + identifier)
			continue
		_check(view != null, "aperçu 3D présent : " + identifier)
		if view == null:
			continue
		previews.append(view)
		var model := view.get("_model") as Node3D
		var viewport := view.get("_viewport") as SubViewport
		var turntable := view.get("_turntable") as Node3D
		_check(model != null and model.scene_file_path == expected_path, "vrai GLB de combat : " + identifier)
		_check(viewport != null and viewport.own_world_3d and viewport.find_world_3d() not in worlds, "monde 3D indépendant : " + identifier)
		if viewport != null:
			worlds.append(viewport.find_world_3d())
		_check(view.mouse_filter == Control.MOUSE_FILTER_IGNORE and viewport.gui_disable_input, "l'aperçu laisse les clics à la carte : " + identifier)
		_check(turntable != null and turntable.scale.is_finite(), "transformation finie de l'arme : " + identifier)
		if turntable != null:
			angles.append(turntable.rotation.y)
	await create_timer(0.25).timeout
	for index in previews.size():
		_check(not is_equal_approx((previews[index].get("_turntable") as Node3D).rotation.y, angles[index]), "rotation réelle de " + str(previews[index].get("equipment_id")))
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 600), Vector2i(2340, 1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		await process_frame
		for view in previews:
			_test_full_turn_framing(view, dimensions)
	for identifier in LOADOUT.WEAPONS:
		if not choices.has(identifier):
			continue
		(choices[identifier] as Button).pressed.emit()
		_check(str(flow.get("loadout").weapon) == identifier and LOADOUT.load_local().weapon == identifier, "sélection et sauvegarde immédiate : " + identifier)
		var markers: Dictionary = flow.get("_selection_markers")["weapon"]
		for other in markers:
			_check((markers[other] as Label).text.contains("ÉQUIPÉ") == (other == identifier), "marqueur équipé exclusif : " + identifier)
	var equipped := str(flow.get("loadout").weapon)
	for identifier in LOADOUT.WEAPONS:
		if not choices.has(identifier):
			continue
		var info := (choices[identifier] as Button).find_child("Info", true, false) as Button
		_check(info != null, "bouton info disponible : " + identifier)
		if info == null:
			continue
		info.pressed.emit()
		_check(flow.get("_equipment_info_panel").visible and flow.get("_equipment_info_id") == identifier, "le bouton info affiche la fiche : " + identifier)
		_check(flow.get("_equipment_info_description").text == LOADOUT.category_description(identifier) and flow.get("_equipment_info_stats").text == LOADOUT.stat_line(identifier), "description et statistiques conservées : " + identifier)
		_check(str(flow.get("loadout").weapon) == equipped and LOADOUT.load_local().weapon == equipped, "ouvrir une fiche n'équipe pas l'arme : " + identifier)
		info.pressed.emit()
		_check(not flow.get("_equipment_info_panel").visible, "le bouton info referme sa fiche : " + identifier)
	flow.call("_open_menu")
	await process_frame
	angles.clear()
	for view in previews:
		angles.append((view.get("_turntable") as Node3D).rotation.y)
	await create_timer(0.15).timeout
	for index in previews.size():
		var view := previews[index]
		_check((view.get("_viewport") as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED and not view.is_processing(), "rendu et processus coupés hors de la forge")
		_check(is_equal_approx((view.get("_turntable") as Node3D).rotation.y, angles[index]), "rotation suspendue hors de la forge")
	flow.call("_open_equipment")
	await process_frame
	angles.clear()
	for view in previews:
		angles.append((view.get("_turntable") as Node3D).rotation.y)
	await create_timer(0.15).timeout
	for index in previews.size():
		var view := previews[index]
		_check((view.get("_viewport") as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED and not is_equal_approx((view.get("_turntable") as Node3D).rotation.y, angles[index]), "rendu et rotation reprennent au retour dans la forge")
	flow.call("_open_equipment_category", "offensive")
	for view in previews:
		_check(not is_instance_valid(view), "aperçu libéré au changement de catégorie")
	_check(scene.get("player").call("get_weapon_id") == "blaster", "la présentation de forge ne modifie pas le contrôleur de combat")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	if _save_existed:
		var file := FileAccess.open(LOADOUT.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_saved_bytes)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOADOUT.SAVE_PATH))
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("WEAPON FORGE TEST: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _run_preview_only() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var paths: Dictionary = MODEL_PATHS.duplicate()
	var longshot_path := "res://art/weapons/longshot.glb"
	if ResourceLoader.exists(longshot_path, "PackedScene"):
		paths["longshot"] = longshot_path
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	root.add_child(cards)
	cards.position = Vector2(20, 20)
	cards.size = Vector2(root.size.x - 40, 292)
	var previews: Array[Node] = []
	var worlds: Array[World3D] = []
	var angles: Array[float] = []
	for identifier in paths:
		var card := Button.new()
		card.custom_minimum_size.y = 292
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		var view := EQUIPMENT_FORGE_PREVIEW.new()
		view.equipment_id = identifier
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view.offset_left = 18
		view.offset_right = -18
		view.offset_top = 18
		view.offset_bottom = -18
		card.add_child(view)
		previews.append(view)
		var model := view.get("_model") as Node3D
		var viewport := view.get("_viewport") as SubViewport
		_check(model != null and model.scene_file_path == paths[identifier], "GLB réel dans l'aperçu isolé : " + identifier)
		_check(viewport != null and viewport.own_world_3d and viewport.find_world_3d() not in worlds, "monde 3D indépendant dans l'aperçu isolé : " + identifier)
		if viewport != null:
			worlds.append(viewport.find_world_3d())
		_check(view.mouse_filter == Control.MOUSE_FILTER_IGNORE and viewport != null and viewport.gui_disable_input, "aperçu isolé transparent aux clics : " + identifier)
		angles.append((view.get("_turntable") as Node3D).rotation.y)
	await create_timer(0.25).timeout
	for index in previews.size():
		_check(not is_equal_approx((previews[index].get("_turntable") as Node3D).rotation.y, angles[index]), "rotation réelle de l'aperçu isolé : " + str(previews[index].get("equipment_id")))
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 600), Vector2i(2340, 1080)]:
		root.size = dimensions
		cards.size = Vector2(dimensions.x - 40, 292)
		await process_frame
		await process_frame
		await process_frame
		for view in previews:
			_test_full_turn_framing(view, dimensions)
	cards.hide()
	await process_frame
	angles.clear()
	for view in previews:
		angles.append((view.get("_turntable") as Node3D).rotation.y)
	await create_timer(0.15).timeout
	for index in previews.size():
		var view := previews[index]
		_check((view.get("_viewport") as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED and not view.is_processing(), "aperçu isolé masqué sans rendu ni processus")
		_check(is_equal_approx((view.get("_turntable") as Node3D).rotation.y, angles[index]), "rotation isolée suspendue après masquage")
	cards.show()
	await create_timer(0.15).timeout
	for index in previews.size():
		var view := previews[index]
		_check((view.get("_viewport") as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED and not is_equal_approx((view.get("_turntable") as Node3D).rotation.y, angles[index]), "rendu et rotation isolés reprennent")
	cards.queue_free()
	await process_frame
	for view in previews:
		_check(not is_instance_valid(view), "aperçu isolé libéré avec sa carte")
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("WEAPON FORGE PREVIEW TEST: %s (%d checks, %d failures, %d GLBs)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size(), paths.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_full_turn_framing(view: Node, dimensions: Vector2i) -> void:
	var model := view.get("_model") as Node3D
	var turntable := view.get("_turntable") as Node3D
	var viewport := view.get("_viewport") as SubViewport
	var camera := viewport.get_camera_3d()
	_check(camera != null and viewport.size.x > 0 and viewport.size.y > 0, "caméra et dimensions valides : " + str(dimensions))
	if camera == null or model == null or turntable == null:
		return
	var initial_angle := turntable.rotation.y
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty(), "le modèle contient des maillages 3D")
	var plinth := viewport.find_child("Plinth", true, false) as MeshInstance3D
	_check(plinth != null, "le socle est présent dans l'aperçu")
	var fitted := true
	var visible_extent := 0.0
	for sample in 12:
		turntable.rotation.y = TAU * float(sample) / 12.0
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for mesh: MeshInstance3D in meshes:
			for corner in 8:
				var point := mesh.global_transform * mesh.get_aabb().get_endpoint(corner)
				var screen := camera.unproject_position(point)
				minimum = minimum.min(screen)
				maximum = maximum.max(screen)
				fitted = fitted and camera.is_position_in_frustum(point) and screen.x >= -1.0 and screen.y >= -1.0 and screen.x <= viewport.size.x + 1.0 and screen.y <= viewport.size.y + 1.0
		if plinth != null:
			for corner in 8:
				var point := plinth.global_transform * plinth.get_aabb().get_endpoint(corner)
				var screen := camera.unproject_position(point)
				fitted = fitted and camera.is_position_in_frustum(point) and screen.x >= -1.0 and screen.y >= -1.0 and screen.x <= viewport.size.x + 1.0 and screen.y <= viewport.size.y + 1.0
		var extent := maximum - minimum
		visible_extent = maxf(visible_extent, maxf(extent.x / viewport.size.x, extent.y / viewport.size.y))
	turntable.rotation.y = initial_angle
	_check(fitted, "tous les coins de l'arme et du socle restent dans le cadre pendant un tour complet : %s / %s" % [view.get("equipment_id"), dimensions])
	_check(visible_extent >= 0.30, "l'arme occupe une taille lisible dans la carte : %s / %s" % [view.get("equipment_id"), dimensions])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
