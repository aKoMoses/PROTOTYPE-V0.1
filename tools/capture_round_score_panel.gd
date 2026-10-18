extends SceneTree

## Real solo round transitions, local network actors and native HUD captures.
## No cloud connection and no changes to the player's saved HUD layout.
const LAYOUT := preload("res://scripts/hud_layout.gd")
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var flow: Node
var controller: Node
var output := "res://outputs/round-score-forge"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	root.get_node("FramePacing").hide()
	flow = scene.get_node("Interface")
	controller = flow.get("_hud_controller")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	_freeze_combat()
	var labels: Dictionary = flow.get("_hud_labels")
	_check(labels.match.text == "0 — 0" and labels.match_round.text == "MANCHE 1", "solo starts with the actual round and score")
	var touch: Control = flow.get_node("TouchControls")
	for mobile in [false, true]:
		touch.visible = mobile
		controller.call("set_layout", LAYOUT.standard("mobile" if mobile else "desktop"))
		for dimensions in [Vector2i(1280, 720), Vector2i(960, 600)]:
			root.size = dimensions
			await process_frame
			controller.call("apply")
			var panel: Rect2 = controller.call("widget_rect", "match_summary")
			var artwork: Control = flow.get_node("FlowRoot/CombatHUD/MatchSummary/ForgeFrame")
			_check(panel.grow(1).encloses(artwork.get_global_rect()), "rendered art stays inside its registered HUD bounds")
			_check(LAYOUT.safe_rect(root).grow(1).encloses(panel), "complete illustrated panel stays inside the safe area at %s touch=%s" % [dimensions, mobile])
			_check(not panel.intersects(controller.call("widget_rect", "pause")), "panel keeps pause accessible at %s touch=%s" % [dimensions, mobile])
			_check(not panel.intersects(controller.call("widget_rect", "player_vitals")), "panel keeps health readable at %s touch=%s" % [dimensions, mobile])
			await _capture("solo-%dx%d-%s" % [dimensions.x, dimensions.y, "touch" if mobile else "pc"])
	touch.visible = false
	root.size = Vector2i(1280, 720)
	controller.call("set_layout", LAYOUT.standard("desktop"))
	flow.call("resolve_round", false, true)
	flow.call("_update_hud")
	_check(labels.match.text == "1 — 0", "solo victory updates the rendered score")
	flow.call("_process", float(flow.WINNER_FOCUS_SECONDS))
	flow.set("_round_result_remaining", 0.0)
	flow.call("_start_next_round")
	flow.call("_begin_live_round")
	_freeze_combat()
	flow.call("_update_hud")
	_check(labels.match.text == "1 — 0" and labels.match_round.text == "MANCHE 2", "next round keeps the score and changes the round label")
	await _capture("solo-round-2-score-1-0")
	flow.call("resolve_round", true, false)
	flow.call("_update_hud")
	_check(labels.match.text == "1 — 1", "solo defeat updates the opponent score")
	flow.call("_return_menu")
	var session: Node = root.get_node("NetworkSession")
	var local_id := int(session.call("local_peer_id"))
	scene.call("_on_network_match_started", local_id, local_id + 1)
	session.set("round_loadouts", {local_id: flow.get("loadout"), local_id + 1: flow.get("loadout")})
	var network: Node = scene.get("network_match")
	network.call("_on_round_prepared", 4, 2, 1)
	network.call("_on_round_live")
	network.set_process(false)
	network.set_physics_process(false)
	network.call("_process", 0.0)
	_check(labels.match.text == "2 — 1" and labels.match_round.text == "MANCHE 4", "network host uses the same live labels")
	await _capture("network-host-score-2-1")
	network.set("_host_id", local_id + 1)
	network.call("_process", 0.0)
	_check(labels.match.text == "1 — 2", "network guest score uses the local player's perspective")
	network.call("_cleanup_actors")
	flow.call("_stop_match_music")
	flow.get("_countdown_audio").stop()
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	for failure in failures:
		push_error(failure)
	print("ROUND SCORE PANEL: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _freeze_combat() -> void:
	var player: Node3D = scene.get_node("Player")
	var target: Node3D = scene.get_node("TargetDummy")
	player.position = Vector3(-2, 0, 2)
	target.position = Vector3(5, 0, 0)
	player.set_process(false)
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	var rig: Node = scene.get_node("CameraRig")
	rig.set_process(false)
	for step in 180:
		rig.call("_process", 1.0 / 60.0)
	flow.call("_update_hud")

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "native capture " + label)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
