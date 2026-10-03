extends SceneTree

var failures: Array[String] = []
var checks := 0
var output := ""

class PeerProbe:
	extends Node
	func get_client_id() -> int: return 11
	func get_host() -> int: return 11
	func is_host() -> bool: return true


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _capture(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(output)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var player: Node = scene.get_node("Player")
	var target: Node = scene.get_node("TargetDummy")
	var camera: Node = scene.get_node("CameraRig")
	var feedback: Node = flow.get("_round_end_feedback")
	for outcome in ["win", "loss", "draw", "final"]:
		# Exercise the real round lifecycle without writing loadout saves.
		flow.set("match_id", int(flow.get("match_id")) + 1)
		flow.set("player_round_score", 0)
		flow.set("bot_round_score", 0)
		flow.set("round_number", 1)
		flow.set("_round_resolved", false)
		flow.set("round_phase", flow.RoundPhase.COUNTDOWN)
		flow.call("_show_screen", flow.Screen.COMBAT)
		flow.call("_begin_round_countdown")
		flow.call("_begin_live_round")
		flow.call("_start_match_music")
		target.call("set_training_bot_enabled", false)
		# A random Baroud build legitimately survives its first lethal hit.
		target.call("get_passive_runtime").configure("")
		player.get("passive_state").configure("")
		player.position = Vector3(-2.0, 0.0, 17.0)
		target.position = Vector3(2.0, 0.0, 17.0)
		camera.call("set_target", player)
		# Let first-use model/shader loading settle before timing the death.
		for frame in range(4):
			await process_frame
		if outcome == "final":
			flow.set("player_round_score", 2)
		if outcome in ["win", "final", "draw"]:
			target.call("take_damage", 100000.0, "test", "end-" + outcome)
		if outcome in ["loss", "draw"]:
			player.call("take_damage", 100000.0, "test", "end-" + outcome)
		await process_frame
		await process_frame
		_check(int(flow.get("round_phase")) == flow.RoundPhase.WINNER_FOCUS, outcome + ": arena hold precedes result")
		_check(not flow.get("_result_panel").visible, outcome + ": no immediate panel")
		_check(Engine.time_scale == 1.0, outcome + ": simulation speed untouched")
		await create_timer(0.30).timeout
		_check(feedback.get("_title").modulate.a > 0.9, outcome + ": announcement readable during fall")
		_check(feedback.get("_audio").stream == feedback.WIN_SOUND if outcome in ["win", "final"] else feedback.get("_audio").stream == feedback.LOSS_SOUND if outcome == "loss" else feedback.get("_audio").stream == null, outcome + ": correct audio perspective")
		_check(camera.get("_focus_target") == null, outcome + ": camera waits for fall")
		await _capture(outcome + "-fall")
		await create_timer(0.42).timeout
		_check(feedback.get("_score").modulate.a > 0.5, outcome + ": score follows announcement")
		if outcome in ["win", "final", "draw"]:
			_check(target.call("is_real_dead") and target.get("_visual_rig").get("dead"), outcome + ": corpse does not reset on duel stop")
		if outcome in ["loss", "draw"]:
			_check(player.get("_visual_rig").get("_active_action") == &"fall", outcome + ": player fall preserved")
			var playback: AnimationNodeStateMachinePlayback = player.get("_visual_rig").get("_playback")
			_check(playback.get_current_node() == &"fall" and playback.get_current_play_position() > 0.1, outcome + ": actual fall playback advances after visual hold (%s, %.3f)" % [playback.get_current_node(), playback.get_current_play_position()])
		if outcome != "draw":
			_check(camera.get("_focus_target") == (target if outcome == "loss" else player), outcome + ": delayed winner focus")
		await _capture(outcome + "-focus")
		await create_timer(1.42).timeout
		_check(int(flow.get("round_phase")) == flow.RoundPhase.ROUND_RESULT, outcome + ": result appears after sequence")
		if outcome == "final":
			flow.call("_start_next_round")
			_check(int(flow.get("round_phase")) == flow.RoundPhase.MATCH_RESULT and flow.get("_result_audio").stream == flow.VICTORY_SOUND, "final: full match victory retained")
	# Cancellation during the visual pause must release actors and camera.
	var process_before := [player.is_processing(), target.is_processing(), camera.is_processing()]
	feedback.begin(1, 1, 0, [player, target], camera, flow.get("_match_music"))
	feedback.reset()
	_check([player.is_processing(), target.is_processing(), camera.is_processing()] == process_before, "cancel restores prior visual processing")
	_check(is_equal_approx(flow.get("_match_music").volume_db, -17.0), "cancel restores music level")
	flow.call("_show_screen", flow.Screen.MENU)
	# Real online actors exercise the same presentation without a cloud login.
	var session: Node = root.get_node("NetworkSession")
	var original_service: Node = session.get("_service")
	var peer_probe := PeerProbe.new()
	root.add_child(peer_probe)
	session.set("_service", peer_probe)
	var host_id: int = session.call("local_peer_id")
	var guest_id := host_id + 1
	scene.call("_on_network_match_started", host_id, guest_id)
	session.set("round_loadouts", {host_id: flow.get("loadout"), guest_id: flow.get("loadout")})
	var network: Node = scene.get("network_match")
	network.set_physics_process(false)
	for local_won in [true, false]:
		network.call("_on_round_prepared", 1, 0, 0)
		network.call("_on_round_live")
		var dead: Node = network.get("_target") if local_won else network.get("_player")
		# Also verify the result-before-snapshot order for a remote defeat.
		if not local_won:
			dead.call("take_damage", 100000.0, "test", "online-death")
		network.call("_on_round_finished", 1, 0, host_id if local_won else guest_id, false)
		await create_timer(0.72).timeout
		var online_feedback: Node = network.get("_round_end_feedback")
		_check(online_feedback.get("_title").text == ("MANCHE REMPORTÉE" if local_won else "MANCHE PERDUE"), "online: correct local result perspective")
		_check(online_feedback.get("_audio").stream == (online_feedback.WIN_SOUND if local_won else online_feedback.LOSS_SOUND), "online: correct local sound perspective")
		_check(dead.get("_visual_rig").get("_active_action") == &"fall", "online: loser fall never replaced by standing defeat")
		_check(Engine.time_scale == 1.0, "online: no global slowdown")
		await _capture("online-win" if local_won else "online-loss")
		network.call("_on_round_prepared", 2, 1, 0)
		_check(camera.get("_focus_target") == null and not network.get("_round_end_feedback").visible, "online: next round clears focus and banner")
	network.call("_on_round_finished", 3, 1, host_id, true)
	await create_timer(2.10).timeout
	_check(flow.get("_result_audio").stream == flow.VICTORY_SOUND, "online final: full victory follows short cue")
	network.call("_cleanup_actors")
	session.set("_service", original_service)
	peer_probe.queue_free()
	_check(not flow.get("_result_audio").playing and camera.is_processing(), "online exit: audio and holds cleaned")
	scene.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	for failure in failures:
		push_error(failure)
	print("ROUND END FEEDBACK: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
