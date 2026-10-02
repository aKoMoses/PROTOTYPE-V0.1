extends SceneTree

const COUNTER := preload("res://scripts/counter.gd")
const DATA := preload("res://scripts/combat_data.gd")
const NETWORK_ACTOR := preload("res://scripts/network_player.gd")
const NETWORK_MATCH := preload("res://scripts/network_match.gd")
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var player: Node3D
var target: Node3D
var feedback: Control
var observed: Array[String] = []
var sounds: Array[String] = []
var capture := false
var network_completed := false

class ControllerProbe extends Node:
	var _phase := "live"
	var events: Array[Dictionary] = []
	func on_actor_action(_actor: Node3D, action: String, data: Dictionary) -> void:
		events.append({"action": action, "data": data})

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 720)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	player = scene.player
	target = scene.target
	feedback = scene.game_flow._combat_feedback
	scene.game_flow._solo_options.quick = true
	scene.game_flow._start_duel()
	scene.game_flow._begin_live_round()
	scene.game_flow.set_process(false)
	player.set_physics_process(false)
	target.set_training_bot_enabled(false)
	scene.get_node("CameraRig").set_process(false)
	var camera: Camera3D = scene.get_node("CameraRig/Camera3D")
	camera.global_position = Vector3(0, 20.5, 17.5)
	camera.look_at(Vector3(0, 0.45, -1.0))
	feedback.enabled = true
	feedback.action_observed.connect(func(kind: String) -> void: observed.append(kind))
	root.get_node("GameSfx").event_played.connect(func(id: String) -> void:
		if id.begins_with("signature_"):
			sounds.append(id)
	)
	await _prepare("shotgun")
	player._perform_shotgun_attack()
	await _wait_signature("shotgun")
	check(feedback._signature.kind == "shotgun", "six real pellets trigger Shotgun signature")
	check(observed.count("shotgun") == 1, "six pellets confirm the salvo once")
	check(target.get_health() < 850, "signature follows effective damage")
	check(sounds.count("signature_shotgun") == 1, "one short Shotgun accent")
	await shot("01-shotgun")
	var count := observed.size()
	var key: String = feedback._signature_seen.keys()[0] if not feedback._signature_seen.is_empty() else ""
	player.present_combat_signature("shotgun", target, key.trim_prefix("shotgun:"))
	check(observed.size() == count, "duplicate salvo confirmation is ignored")
	await _prepare("shotgun")
	var partial := {"id": 987, "source": "shotgun", "credited": {}, "hits_by_target": {}, "passive_attack": {}}
	for pellet in range(5):
		player._resolve_shotgun_projectile(partial, pellet, true, target, 2.0)
	check(not observed.has("shotgun"), "five damaging pellets do not claim a full impact")
	await _prepare("longshot")
	player._perform_longshot_attack()
	await create_timer(0.25).timeout
	check(not observed.has("longshot") and target.get_health() < 1000, "normal Longshot hit is not labelled execution")
	await _prepare("longshot")
	player._longshot_state.hits = 2
	player._perform_longshot_attack()
	await _wait_signature("longshot")
	check(feedback._signature.kind == "longshot" and observed.count("longshot") == 1, "real enhanced Longshot confirms execution")
	await shot("02-longshot")
	count = observed.size()
	key = feedback._signature_seen.keys()[0] if not feedback._signature_seen.is_empty() else ""
	player.present_combat_signature("longshot", target, key.trim_prefix("longshot:"))
	check(observed.size() == count, "piercing confirmation is bounded to one card per shot")
	await _prepare("longshot")
	target.set_meta("duel_static_shield", true)
	player._longshot_state.hits = 2
	player._perform_longshot_attack()
	await create_timer(0.25).timeout
	check(not observed.has("longshot") and is_equal_approx(target.get_health(), 1000.0), "blocked execution never claims success")
	await _prepare("blaster")
	player._perform_counter()
	var guard := COUNTER.component(player)
	guard.update(float(guard.definition.preparation))
	var attack := COUNTER.weapon_attack(target, "signature:counter", DATA.WEAPON_DEFINITIONS.blaster)
	COUNTER.impact(player, 100, "duel_bot", "signature:counter", attack, Vector3.UP)
	check(observed.count("counter") == 1 and feedback._signature.kind == "counter", "actual intercepted attack confirms Counter immediately")
	check(is_equal_approx(player.get_health(), 1000.0) and guard.surcharge_remaining > 0.0, "Counter protection and reward preserved")
	await shot("03-counter")
	await _prepare("blaster")
	target.position = Vector3(0, 0, -1.45)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0, 0.9, -3.25)
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.8, 0.3)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	scene.add_child(wall)
	await physics_frame
	player._perform_fulguro_punch()
	player._update_fulguro_attack(0.36)
	await _wait_signature("fulguro_punch")
	check(observed.count("fulguro_punch") == 1 and feedback._signature.kind == "fulguro_punch", "actual projection against wall confirms crushing")
	check(target.is_stunned() and is_equal_approx(target.get_health(), 650.0), "wall damage and stun preserved")
	await shot("04-fulguro")
	wall.queue_free()
	await process_frame
	await _test_lifecycle()
	await _test_network()
	check(network_completed, "network integration runs to completion")
	await _test_audio()
	await _test_stale_projectile()
	await _test_lethal_success()
	root.get_node("GameSfx").clear()
	scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.2).timeout
	print("COMBAT SIGNATURES: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _prepare(weapon: String) -> void:
	scene.clear_transient_fx()
	player.apply_loadout({"robot": "polyvalent", "weapon": weapon, "offensive": "fulguro_punch", "defensive": "counter", "mobility": "pyro_boots", "passive": "omnivamp"})
	player.reset_combat_state()
	player.set_gameplay_enabled(true)
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	target.reset_combat_state()
	target.set_training_bot_enabled(false)
	target.position = Vector3(0, 0, -2.0)
	target.set_meta("duel_static_shield", false)
	target.show()
	player.set_touch_aim_vector(Vector2.UP)
	player.aim_direction = Vector3.FORWARD
	feedback.reset_round()
	feedback.enabled = true
	observed.clear()
	sounds.clear()
	root.get_node("GameSfx").clear()
	await physics_frame
	await process_frame

func _wait_signature(kind: String) -> void:
	for frame in range(120):
		await physics_frame
		if feedback._signature.kind == kind:
			return

func _test_lifecycle() -> void:
	await _prepare("shotgun")
	feedback.enabled = false
	player.present_combat_signature("counter", player, "disabled")
	check(observed.has("counter") and feedback._signature.kind.is_empty() and sounds.is_empty(), "disabled feedback keeps challenge observation and suppresses accents")
	feedback.enabled = true
	target.hide()
	player.present_combat_signature("shotgun", target, "hidden")
	check(feedback._signature.kind.is_empty() and sounds.is_empty(), "concealed target does not reveal an impact")
	target.show()
	target.position = Vector3(80, 0, 80)
	player.present_combat_signature("longshot", target, "offscreen")
	check(feedback._signature.kind.is_empty(), "offscreen target does not reveal an impact")
	target.position = Vector3(0, 0, -2)
	scene.set_meta("camera_shake_enabled", false)
	var rig: Node = scene.get_node("CameraRig")
	rig._shake_time = 0.0
	player.present_combat_signature("longshot", target, "comfort")
	check(rig._shake_time == 0.0 and feedback._signature.kind == "longshot", "camera comfort setting is honored")
	var age: float = feedback._signature.age
	paused = true
	await create_timer(0.15, true).timeout
	check(is_equal_approx(age, feedback._signature.age), "pause freezes presentation")
	paused = false
	player.reset_combat_state()
	check(feedback._signature.kind.is_empty() and feedback._signature_seen.is_empty(), "actor reset clears all confirmation history")
	player.present_combat_signature("counter", player, "finish")
	feedback._signature._process(2.0)
	check(feedback._signature.kind.is_empty(), "card and marker expire")
	player.present_combat_signature("counter", player, "leave")
	player.set_gameplay_enabled(false)
	feedback._process(0.01)
	check(feedback._signature.kind.is_empty(), "menu and disabled gameplay clear presentation")
	player.set_gameplay_enabled(true)
	for index in range(150):
		player.present_combat_signature("unknown", player, str(index))
	check(feedback._signature_seen.size() < 128, "unknown events cannot allocate signature history")
	if capture:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(844, 390)
		await process_frame
		player.present_combat_signature("counter", player, "mobile")
		await shot("05-mobile")
		check(feedback._signature.card_rect.end.x <= feedback.size.x and feedback._signature.card_rect.end.y <= feedback.size.y, "small landscape card fits the viewport")
		root.size = Vector2i(1280, 720)
		await process_frame

func _test_network() -> void:
	var controller := ControllerProbe.new()
	scene.add_child(controller)
	var authority := CharacterBody3D.new()
	authority.set_script(NETWORK_ACTOR)
	authority.controller = controller
	scene.add_child(authority)
	authority.opponent = target
	authority.position = Vector3.ZERO
	authority.set_gameplay_enabled(true)
	authority.set_physics_process(false)
	feedback.bind_actor(authority)
	feedback.register_target(target)
	authority.present_combat_signature("longshot", target, "host-confirmed")
	check(controller.events.size() == 1 and controller.events[0].action == "combat_signature", "host publishes an explicit success event")
	check(feedback._signature.kind == "longshot", "host local player receives success")
	authority.authoritative = false
	feedback.reset_round()
	authority.present_combat_signature("longshot", target, "guest-fake")
	check(controller.events.size() == 1 and feedback._signature.kind.is_empty(), "guest projectile cannot invent a successful action")
	authority.receive_action("combat_signature", {"kind": "longshot", "event_id": "fake"})
	check(feedback._signature.kind.is_empty(), "guest input action is not treated as host confirmation")
	# Exercise production match routing for a host-confirmed guest success.
	var remote := CharacterBody3D.new()
	remote.set_script(NETWORK_ACTOR)
	remote.authoritative = false
	remote.remote_controlled = true
	scene.add_child(remote)
	remote.opponent = authority
	remote.position = Vector3(0, 0, -2)
	remote.set_physics_process(false)
	feedback.register_target(remote)
	var match_layer := CanvasLayer.new()
	match_layer.set_script(NETWORK_MATCH)
	match_layer._cleanup_done = true
	scene.add_child(match_layer)
	match_layer._main = scene
	match_layer._flow = scene.game_flow
	match_layer._session = root.get_node("NetworkSession")
	match_layer._host_id = match_layer._session.local_peer_id() + 1
	match_layer._player = authority
	match_layer._target = remote
	match_layer._phase = "live"
	var event := {"sequence": 1, "peer": match_layer._session.local_peer_id(), "action": "combat_signature", "data": {"kind": "longshot", "event_id": "confirmed"}, "position": Vector3.ZERO, "aim": Vector3.FORWARD}
	match_layer._on_action_received(event)
	check(feedback._signature.kind == "longshot", "guest presents host-confirmed signature through match routing")
	feedback.reset_round()
	match_layer._on_action_received(event)
	check(feedback._signature.kind.is_empty(), "duplicate network event is ignored")
	event.sequence = 2
	event.peer = match_layer._host_id
	match_layer._on_action_received(event)
	check(feedback._signature.kind.is_empty(), "opponent successes are not credited to local player")
	match_layer._phase = "countdown"
	event.sequence = 3
	event.peer = match_layer._session.local_peer_id()
	match_layer._on_action_received(event)
	check(feedback._signature.kind.is_empty(), "countdown ignores stale confirmations")
	match_layer.queue_free()
	feedback.bind_actor(player)
	feedback.register_target(target)
	check(feedback.actor == player and feedback._registered.size() == 1, "return from network rebinds feedback and target")
	authority.queue_free()
	remote.queue_free()
	controller.queue_free()
	await process_frame
	player.present_combat_signature("counter", player, "restored")
	check(feedback._signature.kind == "counter", "solo feedback still works after network actor removal")
	network_completed = true

func _test_audio() -> void:
	var sfx: Node = root.get_node("GameSfx")
	sfx.clear()
	for kind in sfx._signature_streams:
		var stream: AudioStreamWAV = sfx._signature_streams[kind]
		check(stream.get_length() <= 0.25 and stream.data.size() > 1000, "short accent: " + kind)
		if capture:
			stream.save_to_wav("res://outputs/combat-signatures/%s.wav" % kind)
	sfx.set_paused(true)
	check(not sfx.play_signature("shotgun"), "audio pause suppresses new accents")
	sfx.clear()
	check(sfx.play_signature("shotgun") and not sfx.play_signature("shotgun"), "audio limits same-frame repeated accents")
	sfx.clear()
	check(sfx._signature_voices.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing), "round cleanup stops accent voices")

func _test_lethal_success() -> void:
	await _prepare("shotgun")
	# A randomized Baroud build can postpone death despite a winning salvo.
	target.get_passive_runtime().configure("omnivamp")
	var flow: Node = scene.game_flow
	flow._round_resolved = false
	flow.round_phase = flow.RoundPhase.LIVE
	target.combat_state.health = 200.0
	player._perform_shotgun_attack()
	await _wait_signature("shotgun")
	# Round resolution already resets the training actor; the result keeps its death.
	check(flow._round_result_bot_dead and feedback._signature.kind == "shotgun", "lethal full impact is still confirmed")
	feedback._process(0.01)
	check(feedback._signature.kind == "shotgun" and flow.round_phase == flow.RoundPhase.WINNER_FOCUS, "winning hit remains visible during winner focus")

func _test_stale_projectile() -> void:
	await _prepare("longshot")
	var payload: Dictionary = player.emit_passive_weapon()
	payload.longshot_generation = player._longshot_state.generation
	player.reset_combat_state()
	player._on_longshot_projectile_finished({"collider": target, "position": target.global_position + Vector3.UP, "normal": Vector3.BACK}, 2.0, player._longshot_definition, true, "stale-signature-shot", false, payload)
	check(not observed.has("longshot") and feedback._signature.kind.is_empty(), "old weapon generation cannot confirm a new-round execution")

func shot(id: String) -> void:
	if not capture:
		return
	scene.game_flow._update_hud()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/combat-signatures"))
	feedback._signature.set_process(false)
	feedback._signature.age = 0.08
	feedback._signature._layout()
	feedback._signature.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/combat-signatures/%s.png" % id)
	feedback._signature.set_process(true)
