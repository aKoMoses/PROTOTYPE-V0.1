extends SceneTree

## Real HUD and network actors, without a cloud connection or saved-data writes.
const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var layout_controller: Node = flow.get("_hud_controller")
	var hidden_layout: Dictionary = layout_controller.get("layout").duplicate(true)
	for identifier in ["spell_bar", "offensive_slot", "defensive_slot", "mobility_slot"]:
		hidden_layout[identifier].v = false
	layout_controller.call("set_layout", hidden_layout)
	var build := LOADOUT.sanitize({"offensive": "fulguro_punch", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "inertia"})
	flow.set("loadout", build)
	var session: Node = root.get_node("NetworkSession")
	var host_id := int(session.call("local_peer_id"))
	var guest_id := host_id + 1
	scene.call("_on_network_match_started", host_id, guest_id)
	session.set("round_loadouts", {host_id: build, guest_id: LOADOUT.defaults()})
	var match_controller: Node = scene.get("network_match")
	var fighter: Node = match_controller.get("_player")
	match_controller.call("_on_round_prepared", 1, 0, 0)
	match_controller.call("_on_round_live")
	await process_frame
	var bar: Control = flow.get_node("FlowRoot/CombatHUD/SpellBar")
	var passive: Control = bar.get_node("PassiveSlot")
	var vitals: Control = flow.get_node("FlowRoot/CombatHUD/PlayerVitals")
	_check(passive.get("player") == fighter and vitals.get("player") == fighter, "le passif et les PV suivent le combattant réseau")
	_check(str(passive.get("player").call("get_passive_id")) == "inertia", "le HUD montre le passif du vrai équipement réseau")
	var touch: Control = flow.get_node("TouchControls")
	var expected_touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or "touch_preview" in OS.get_cmdline_user_args()
	_check(touch.visible == expected_touch and touch.get("player") == fighter, "les boutons tactiles restent liés au joueur réseau et au mode aperçu")
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(800, 600)]:
		root.size = dimensions
		for _frame in range(4):
			await process_frame
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(bar.is_visible_in_tree(), "la barre reste visible en combat à %s" % dimensions)
		for category in ["Offensive", "Defensive", "Mobility"]:
			var slot: Control = bar.get_node(category + "Slot")
			var id: String = category.to_lower() + "_slot"
			_check(slot.is_visible_in_tree() and viewport.grow(1).encloses(layout_controller.call("widget_rect", id)), "le module %s reste dans l'écran à %s" % [category, dimensions])
		_check(not flow.get_node("FlowRoot/CombatHUD/PauseButton").visible, "redimensionner ne réactive pas la pause en ligne")
		if expected_touch:
			var leave: Control = match_controller.get("_leave_button")
			_check(not leave.get_global_rect().intersects(touch.call("get_widget_rect", "weapon_button")), "quitter ne recouvre pas le bouton tactile d'arme")
	root.size = Vector2i(1280, 720)
	for _frame in range(4):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "res://captures/multi-spell-bar-touch.png" if expected_touch else "res://captures/multi-spell-bar-pc.png"
		get_root().get_texture().get_image().save_png(path)
	match_controller.call("_on_round_finished", 3, 1, host_id, true)
	layout_controller.call("apply")
	await process_frame
	_check(not bar.visible and match_controller.get("_rematch_button").is_visible_in_tree(), "les actions de fin de match remplacent la barre même après un redimensionnement")
	match_controller.call("_on_round_prepared", 1, 0, 0)
	match_controller.call("_on_round_live")
	await process_frame
	_check(bar.is_visible_in_tree(), "la barre revient au lancement de la revanche")
	match_controller.call("_cleanup_actors")
	_check(layout_controller.get("layout") == hidden_layout and not bar.visible, "quitter restaure la disposition personnelle sans modifier sa sauvegarde")
	_check(passive.get("player") == scene.get_node("Player") and vitals.get("player") == scene.get_node("Player"), "quitter restaure les liens des panneaux vers le joueur local")
	flow.call("_stop_match_music")
	flow.get("_countdown_audio").stop()
	scene.queue_free()
	await process_frame
	# Audio and render resources are released asynchronously after node deletion.
	await create_timer(0.25).timeout
	for failure in failures:
		push_error(failure)
	print("NETWORK HUD TEST: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
