extends SceneTree

const NETWORK := preload("res://scripts/network_player.gd")
var heard: Array[String] = []
var failures: Array[String] = []
var scene: Node
var player: Node3D
var target: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func prepare() -> void:
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.call("set_training_options", false, false, false)
	player.set("_defensive_module_id", "projector")
	player.set("_mobility_module_id", "permutation")
	player.global_position = Vector3(0, 0, 60)
	player.set("aim_direction", Vector3.RIGHT)
	target.call("reset_combat_state")
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.global_position = Vector3(4, 0, 60)
	root.get_node("GameSfx").clear()
	heard.clear()

func await_mark() -> Node3D:
	for frame in range(60):
		await process_frame
		var mark: Node3D = player.get("_permutation_mark")
		if is_instance_valid(mark):
			mark.set_physics_process(false)
			return mark
	return null

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	var sfx := root.get_node("GameSfx")
	sfx.event_played.connect(func(id: String) -> void: heard.append(id))
	prepare()
	check(player.call("_perform_projector"), "Manual cast accepted")
	var cast: Node3D = player.get("_projector_cast_visual")
	var voice: AudioStreamPlayer3D = cast.get_meta("charge_voice")
	check(heard.count("projector_charge") == 1 and voice.bus == &"Effects", "Manual compression starts once on effects bus")
	player.call("apply_stun", 0.2, "audio-test")
	check(not voice.playing and not heard.has("projector_wave"), "Interrupted cast stops compression and emits no wave")
	prepare()
	player.call("_perform_projector")
	player.call("_update_projector_cast", 0.18)
	check(heard.count("projector_wave") == 1 and heard.count("projector_push") == 1, "Successful cast emits wave and outward breath")
	check(not heard.has("projector_passive"), "Manual activation has no emergency cue")
	prepare()
	var maximum: float = player.call("get_max_health")
	player.call("take_damage", maximum * 0.76, "audio-test", "threshold1")
	player.call("take_damage", 1.0, "audio-test", "threshold2")
	check(heard.count("projector_passive") == 1 and heard.count("projector_push") == 1, "Threshold crossing emits emergency cue once")
	check(not heard.has("projector_charge") and not heard.has("projector_wave"), "Emergency bypasses manual preparation and signature")
	prepare()
	player.call("_perform_permutation")
	check(not heard.has("permutation_send"), "No shadow audio before mark emission")
	var mark := await await_mark()
	check(is_instance_valid(mark), "Real cast produces a mark")
	if is_instance_valid(mark):
		check(heard.count("permutation_send") == 1 and mark._flight_audio.playing, "Shadow launch and moving loop begin once")
		check(mark._flight_audio.bus == &"Effects" and mark._flight_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Flight is a routed loop")
		mark._physics_process(0.5)
		check(not mark._flight_audio.playing, "Exchange stops flight before retirement")
		check(heard.count("permutation_swap") == 1 and heard.count("permutation_shield") == 1, "Successful exchange announces relocation and shield")
		check(not heard.has("javelin_teleport"), "Permutation uses its dedicated sound")
	await process_frame
	prepare()
	player.call("_perform_permutation")
	mark = await await_mark()
	if is_instance_valid(mark):
		target.set("_visibility_epoch", int(target.call("get_visibility_epoch")) + 1)
		mark._physics_process(0.01)
		check(not mark._flight_audio.playing, "Invalid target stops flight immediately")
		check(not heard.has("permutation_swap") and not heard.has("permutation_shield"), "Failed exchange has no success cues")
	await process_frame
	prepare()
	var replica := NETWORK.new()
	replica.authoritative = false
	scene.add_child(replica)
	replica.set_gameplay_enabled(true)
	replica.set_physics_process(false)
	replica.receive_action("projector_pulse", {"origin":Vector3.ZERO, "emergency":true}, true)
	check(heard.count("projector_passive") == 1 and not heard.has("projector_wave"), "Client retains host emergency signature")
	for item in sfx._module_voices: check(item.bus == &"Effects", "Module voices obey effects volume")
	sfx.clear()
	check(sfx._module_voices.is_empty(), "Round cleanup retires module voices")
	player.call("set_gameplay_enabled", false)
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null: vfx.call("clear")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PROJECTOR PERMUTATION SFX TEST: PASS")
		quit(0)
	else:
		for message in failures: push_error(message)
		quit(1)
