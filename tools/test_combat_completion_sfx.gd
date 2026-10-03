extends SceneTree

const AUDIO := preload("res://scripts/combat_audio.gd")
const NETWORK_ACTOR := preload("res://scripts/network_player.gd")
var failures: Array[String] = []
var heard: Array[String] = []
var exercised: Dictionary = {}
var sfx: Node
var player: Node3D
var target: Node3D
var scene: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func cue(id: String) -> void:
	check(heard.has(id), "Actual action emitted " + id)
	if heard.has(id):
		exercised[id] = true

func prepare() -> void:
	player.call("reset_combat_state")
	target.call("reset_combat_state")
	player.call("set_training_options", false, false, true)
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0, 24)
	player.set("aim_direction", Vector3.FORWARD)
	target.global_position = Vector3(0, 0, 22)
	player.call("set_passive", "baroud")
	sfx.clear()
	heard.clear()

func _run() -> void:
	scene = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	player = scene.player
	for dummy in scene.get_training_targets():
		dummy.set_physics_process(false)
		dummy.set_process(false)
	target = scene.get_training_targets()[1]
	sfx = root.get_node("GameSfx")
	sfx.event_played.connect(func(id: String) -> void: heard.append(id))
	var record := AudioEffectRecord.new()
	var bus := AudioServer.get_bus_index("Effects")
	var capturing := "--record" in OS.get_cmdline_user_args()
	if capturing:
		AudioServer.add_bus_effect(bus, record)
		record.set_recording_active(true)
	check(AUDIO.STREAMS.size() == 27, "All 27 generated cues are loadable")
	for stream: AudioStream in AUDIO.STREAMS.values():
		check(stream.resource_path.begins_with("res://art/audio/combat-sfx/") and stream.get_length() > 0.0, "Generated stream imported")
	prepare()
	await physics_frame
	player.call("_begin_javelin_charge")
	cue("javelin_charge")
	var charge: AudioStreamPlayer3D = player.get_meta("combat_charge_javelin_charge").get_ref()
	player.call("_cancel_javelin_charge")
	check(not charge.playing and charge.is_queued_for_deletion(), "Cancelled charge stops immediately")
	player.call("_update_javelin_charge", 2.0)
	check(not heard.has("javelin_launch"), "Cancelled Javelin never launches")
	prepare()
	player.call("_perform_javelin")
	player.call("_update_javelin_charge", 1.0)
	await create_timer(0.35).timeout
	cue("javelin_launch")
	cue("javelin_impact")
	check(target.call("has_javelin_mark"), "Live training projectile hits and marks")
	target.call("clear_javelin_mark")
	player.call("_update_javelin_mark")
	cue("javelin_mark_end")
	prepare()
	await physics_frame
	player.call("_perform_fulguro_punch")
	cue("fulguro_charge")
	player.call("_update_fulguro_attack", 1.0)
	cue("fulguro_impact")
	# Wall contact presentation callback; projection physics is covered separately.
	target.call("_spawn_fulguro_wall_visual", target.global_position, Vector3.BACK)
	cue("fulguro_wall")
	prepare()
	await physics_frame
	player.call("_perform_pelto_smash")
	player.call("_update_pelto_attack", 1.0)
	await create_timer(1.7).timeout
	cue("pelto_outbound")
	cue("pelto_hit")
	cue("pelto_return")
	prepare()
	player.call("_perform_bio_injector")
	cue("bio_inject")
	cue("bio_boost")
	player.call("_update_module_cooldowns", 20.0)
	player.call("_update_module_cooldowns", 20.0)
	cue("bio_end")
	check(heard.count("bio_end") == 1, "Bio expiration plays once")
	prepare()
	player.call("_perform_static_shield")
	cue("static_on")
	check(player.call("take_damage", 50.0, "enemy", "shield-test") == 0.0, "Shield still blocks damage")
	cue("static_block")
	player.call("_perform_static_shield")
	cue("static_off")
	prepare()
	player.global_position = Vector3(0, 0, 18)
	await physics_frame
	player.call("_perform_magnetic_field")
	await create_timer(0.4).timeout
	var wall: Node3D = player.get("_magnetic_wall")
	check(is_instance_valid(wall), "Real magnetic cast deploys a wall")
	if is_instance_valid(wall):
		cue("magnetic_place")
		for voice: AudioStreamPlayer3D in sfx._module_voices:
			if voice.stream == AUDIO.STREAMS.magnetic_place:
				check(voice.global_position.is_equal_approx(wall.global_position), "Deployment audio uses wall position")
		wall.call("projectile_impact", wall.global_position)
		cue("magnetic_block")
		await create_timer(float(wall.get("duration")) + 0.1).timeout
		cue("magnetic_end")
		check(heard.count("magnetic_end") == 1, "Natural wall expiration plays once")
	prepare()
	player.call("apply_loadout", {"mobility": "eclipse"})
	player.set_physics_process(false)
	target.global_position = Vector3(4, 0, 23)
	await physics_frame
	check(player.call("_perform_eclipse", Vector3(4, 0, 24)), "Eclipse departs in actual training")
	cue("eclipse_depart")
	player.get("_eclipse").update(player, 0.3)
	cue("eclipse_arrival")
	cue("eclipse_shield")
	_test_passives()
	await _test_network_audio()
	check(exercised.size() == 27, "All 27 cues exercised through gameplay callbacks (%d/27)" % exercised.size())
	if capturing:
		record.set_recording_active(false)
		var wav := record.get_recording()
		check(wav != null and wav.data.size() > 44, "Training audio mixer recorded the new cues")
		if wav != null:
			wav.save_to_wav("res://audio-lab/combat-completion/reports/combat-completion-recorded.wav")
		AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	sfx.clear()
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("COMBAT COMPLETION SFX: PASS 27 gameplay cues, cancellation, throttling and network validation")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_passives() -> void:
	prepare()
	player.call("set_passive", "alternator")
	player.call("register_offensive_attack", "wave:audio")
	player.call("on_direct_offensive_hit", "wave:audio", 10.0, target)
	player.call("on_direct_offensive_hit", "wave:audio", 10.0, target)
	cue("alternator_ready")
	check(heard.count("alternator_ready") == 1, "Multiple wave contacts do not repeat readiness")
	prepare()
	player.call("set_passive", "tracker")
	var attack: Dictionary = player.call("emit_passive_weapon")
	player.call("passive_weapon_damage", target, 10.0, "player", "tracker1", attack)
	check(not heard.has("tracker_mark"), "First Tracker hit remains quiet")
	player.call("passive_weapon_damage", target, 10.0, "player", "tracker2", player.call("emit_passive_weapon"))
	cue("tracker_mark")
	check(player.passive_state.get_signal_connection_list("sound_requested").size() == 1, "Passive binding does not accumulate callbacks")
	prepare()
	player.call("set_passive", "inertia")
	player.passive_state.dash_finished(true)
	player.call("passive_weapon_damage", target, 10.0, "player", "inertia", player.call("emit_passive_weapon"))
	cue("inertia_trigger")
	prepare()
	player.call("set_passive", "auxiliary_reactor")
	player.set("training_instant_cooldowns", false)
	player._module_cooldowns[player._offensive_module_id] = 3.0
	player.call("passive_weapon_damage", target, 10.0, "player", "reactor", player.call("emit_passive_weapon"))
	cue("reactor_refresh")
	prepare()
	player.call("set_passive", "omnivamp")
	player.call("_on_damage_dealt", 100.0, target)
	check(not heard.has("omnivamp_heal"), "Full health does not emit healing audio")
	player.call("take_damage", 100.0, "enemy", "wound")
	for hit in 8:
		player.call("_on_damage_dealt", 10.0, target)
	cue("omnivamp_heal")
	check(heard.count("omnivamp_heal") == 1, "Rapid healing contacts are throttled")

func _test_network_audio() -> void:
	sfx.clear()
	heard.clear()
	var replica := CharacterBody3D.new()
	replica.set_script(NETWORK_ACTOR)
	replica.set("authoritative", false)
	replica.set("remote_controlled", true)
	scene.add_child(replica)
	replica.call("set_gameplay_enabled", true)
	replica.set_physics_process(false)
	var health: float = replica.call("get_health")
	var packet := {"cue": "javelin_impact", "center": Vector3.ZERO}
	replica.call("receive_action", "combat_sfx", packet, false)
	check(heard.is_empty(), "Client audio request cannot execute as a combat action")
	replica.call("receive_action", "combat_sfx", packet, true)
	check(heard.count("javelin_impact") == 1, "Host outcome plays on replica")
	replica.call("receive_action", "combat_sfx", {"cue": "unknown", "center": Vector3.ZERO}, true)
	replica.call("receive_action", "combat_sfx", {"cue": "fulguro_impact", "center": Vector3.INF}, true)
	check(heard.size() == 1 and replica.call("get_health") == health, "Invalid packets ignored and audio cannot alter health")
	replica.queue_free()
	await process_frame
