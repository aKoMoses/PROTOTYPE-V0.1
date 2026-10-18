extends SceneTree

## Actual combat widgets and input ownership; optional native screenshots via -- DIR.
const LAYOUT := preload("res://scripts/hud_layout.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var checks := 0
var output := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	root.get_node("FramePacing").hide()
	var flow: Node = scene.get_node("Interface")
	flow.set("loadout", LOADOUT.sanitize({"weapon": "blaster", "offensive": "pelto_smash", "defensive": "static_shield", "mobility": "eclipse", "passive": "tracker"}))
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	var player: Node3D = scene.get_node("Player")
	var target: Node3D = scene.get_node("TargetDummy")
	player.position = Vector3(-2, 0, 2)
	target.position = Vector3(5, 0, 0)
	player.set_physics_process(false)
	player.set_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	player.get("combat_state").apply_damage(240, "hud-fixture", "initial")
	player.set("_blaster_charge_ratio", 0.65)
	player.set("_blaster_charge_active", true)
	player.set("_module_cooldowns", {"static_shield": 3.2})
	player.get_node("WorldUIAnchor/PlayerHealthReadout").call("clear_damage_numbers")
	var rig: Node = root.get_camera_3d().get_parent()
	rig.set_process(false)
	for step in 300: rig.call("_process", 1.0 / 60.0)
	var controller: Node = flow.get("_hud_controller")
	var touch: Control = flow.get_node("TouchControls")
	var vitals: Control = flow.get_node("FlowRoot/CombatHUD/PlayerVitals")
	var bar: Control = flow.get_node("FlowRoot/CombatHUD/SpellBar")
	var feedback: Control = flow.get("_combat_feedback")
	feedback.set("enabled", true)
	for mobile in [false, true]:
		touch.visible = mobile
		controller.call("set_layout", LAYOUT.standard("mobile" if mobile else "desktop"))
		for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 600)]:
			root.size = dimensions
			await process_frame
			controller.call("apply")
			player.set("_blaster_charge_active", true)
			player.set("_blaster_charge_ratio", 0.65)
			flow.call("_update_hud")
			vitals.call("_refresh")
			var safe := LAYOUT.safe_rect(root)
			for id in ["player_vitals", "match_summary", "pause", "offensive_slot", "defensive_slot", "mobility_slot", "passive_slot"]:
				_check(safe.grow(2).encloses(controller.call("widget_rect", id)), "Safe area: %s %s touch=%s" % [id, dimensions, mobile])
			_check(vitals.is_visible_in_tree(), "Persistent health and weapon")
			_check(not controller.call("widget_rect", "player_vitals").intersects(controller.call("widget_rect", "match_summary")), "Vitals and score do not overlap")
			_check(vitals.get("_health").text == "760 / 1000", "Actual life value")
			_check(vitals.get("_weapon").text == "CHARGE 65 %", "Actual blaster charge")
			for category in ["Offensive", "Defensive", "Mobility"]:
				_check(bar.get_node(category + "Slot").is_visible_in_tree() == not mobile, "Touch has one activation control per module")
			_check(bar.get_node("PassiveSlot").is_visible_in_tree(), "Passive remains visible on touch")
			if mobile:
				for id in ["offensive_button", "defensive_button", "mobility_button"]:
					var stick: Vector2 = touch.call("_widget_center", "move")
					var button: Vector2 = touch.call("_widget_center", id)
					var gap := float(touch.call("_hit_radius", "move")) + float(touch.call("_hit_radius", id))
					_check(stick.distance_to(button) >= gap, "Circular touch targets separated: %s distance=%.1f radii=%.1f" % [id, stick.distance_to(button), gap])
			if dimensions == Vector2i(1280, 720):
				await _capture("mobile" if mobile else "pc")
	# Health, weapon switching and effect data come from the live actor.
	touch.visible = false
	controller.call("set_layout", LAYOUT.standard("desktop"))
	root.size = Vector2i(1280, 720)
	await process_frame
	player.get("combat_state").apply_damage(540, "hud-fixture", "critical")
	player.call("apply_slow", 1.2, 30.0, "hud-fixture")
	player.set("_module_cooldowns", {"pelto_smash": 2.4})
	feedback.call("_process", 0.0)
	flow.call("_update_hud")
	vitals.call("_refresh")
	_check(vitals.get("_health").text == "220 / 1000" and "FAIBLES" in vitals.get("_warning").text, "Low life has a readable warning")
	_check(feedback.get_node("ContextState").visible and "RALENTI" in feedback.get_node("ContextState").text, "Timed slow beside actor")
	_check(flow.get("_hud_labels").offensive_status.text == "2,4 s", "French decimal cooldown")
	_check(flow.get("_hud_labels").defensive_status.text == "PRÊT", "Ready defense is explicit")
	target.call("apply_spotted", 10.0, "hud-fixture")
	target.call("_update_visibility_presentation", 1.0)
	player.call("take_damage", 1, "duel_bot", "hud-direction")
	player.get_node("WorldUIAnchor/PlayerHealthReadout").call("clear_damage_numbers")
	_check(float(feedback.get("_incoming_remaining")) > 0.0, "Actual visible opponent damage creates direction")
	var sampled: Vector3 = feedback.get("_incoming_direction")
	target.position += Vector3(-2, 0, 0)
	_check(feedback.get("_incoming_direction") == sampled, "Direction is an impact sample, never a live tracker")
	await _capture("critical")
	feedback.call("reset_round")
	_check(float(feedback.get("_incoming_remaining")) == 0.0 and not feedback.get_node("ContextState").visible, "Round reset clears transient cues")
	target.hide()
	feedback.call("_received", 10.0, "duel_bot", "hidden")
	_check(float(feedback.get("_incoming_remaining")) == 0.0, "Hidden source is not revealed by the HUD")
	target.show()
	feedback.set("enabled", false)
	feedback.call("_process", 0.0)
	_check(not feedback.get_node("ContextState").visible, "Comfort preference disables contextual alerts")
	feedback.set("enabled", true)
	feedback.call("_process", 0.0)
	paused = true
	_check(not feedback.get_node("ContextState").visible and float(feedback.get("_incoming_remaining")) == 0.0, "Pause clears transient cues")
	paused = false
	player.call("set_weapon", "shotgun")
	vitals.call("_refresh")
	_check("SHOTGUN" in vitals.get("_weapon").text, "Shotgun ammunition replaces blaster charge")
	player.call("set_weapon", "longshot")
	vitals.call("_refresh")
	_check("LONGSHOT" in vitals.get("_weapon").text, "Longshot cycle replaces ammunition")
	player.call("set_weapon", "mekatana")
	vitals.call("_refresh")
	_check("MEKATANA" in vitals.get("_weapon").text, "Mekatana retains combo status")
	var custom := LAYOUT.standard("desktop")
	custom.player_vitals.d = [0.1, -0.2]
	_check(LAYOUT._upgrade_standard(custom, "desktop") == custom, "Personal layout survives migration")
	controller.call("set_preview", true)
	touch.visible = true
	controller.call("apply")
	_check(bar.get_node("OffensiveSlot").visible, "HUD editor can still select desktop widgets on touch")
	controller.call("set_preview", false)
	flow.call("_stop_match_music")
	flow.get("_countdown_audio").stop()
	scene.call("clear_transient_fx")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	for message in failures: push_error("FAIL: " + message)
	print("COMBAT HUD TEST: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Native capture " + label)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
