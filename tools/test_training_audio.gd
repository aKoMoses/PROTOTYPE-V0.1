extends SceneTree

var failures: Array[String] = []
var heard: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _run() -> void:
	var build := preload("res://scripts/loadout_state.gd").defaults()
	build.offensive = "rocket_basket"
	build.weapon = "mekatana"
	set_meta("garage_test_loadout", build)
	var scene := load("res://scenes/training_ground.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player: Node3D = scene.player
	var listener := player.get_node_or_null("TrainingAudioListener") as AudioListener3D
	check(listener != null and listener.is_current(), "Training listens from the controlled robot")
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	var camera_distance := camera.global_position.distance_to(player.global_position)
	print("Training overhead listener distance: %.2f m" % camera_distance)
	check(camera_distance > 15.0, "Fixture preserves substantial camera-distance attenuation")
	var sfx := root.get_node("GameSfx")
	sfx.event_played.connect(func(id: String) -> void: heard.append(id))
	player.set_physics_process(false)
	player.set("training_invulnerable", true)
	player.set("training_instant_cooldowns", true)
	var targets: Array = scene.get_training_targets()
	player.global_position = targets[1].global_position + Vector3(0, 0, 5)
	player.set("aim_direction", Vector3.FORWARD)
	var moved: Vector3 = listener.global_position if listener != null else Vector3.ZERO
	check(moved.distance_to(player.global_position + Vector3.UP * 1.2) < 0.01, "Listener follows a robot crossing the training map")
	var record := AudioEffectRecord.new()
	var bus := AudioServer.get_bus_index("Effects")
	var capturing := "--record" in OS.get_cmdline_user_args()
	if capturing:
		AudioServer.add_bus_effect(bus, record)
		record.set_recording_active(true)
	player.call("_perform_rocket_basket")
	check(heard.count("rocket_arm") == 1, "Real training cast emits arm cue")
	await create_timer(0.36).timeout
	check(heard.count("rocket_launch") == 1, "Real training cast emits one volley cue")
	var rockets := get_nodes_in_group("prototype0_homing_rockets")
	check(rockets.size() == 5, "Real training cast creates five rockets")
	for rocket in rockets:
		var engine: AudioStreamPlayer3D = rocket._propulsion
		check(engine.playing and engine.bus == &"Effects", "Rocket propulsion is routed and playing")
		check(engine.global_position.distance_to(moved) < engine.max_distance, "Propulsion is within the actual listener radius")
	for voice: AudioStreamPlayer3D in sfx._module_voices:
		check(voice.global_position.distance_to(moved) < voice.max_distance, "Arm and launch voices reach the listener")
	for frame in range(100):
		await physics_frame
	check(heard.has("rocket_impact"), "Training target contact emits impact")
	if capturing:
		record.set_recording_active(false)
		var wav := record.get_recording()
		check(wav != null and wav.data.size() > 44, "Real audio mixer produced a recording")
		if wav != null:
			wav.save_to_wav("res://audio-lab/combat-completion/reports/training-rockets-recorded.wav")
		AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	var rig: Node = player.get("_visual_rig")
	var blade := rig.get("_mekatana_weapon") as Node if rig != null else null
	if blade != null:
		blade.call("set_phase", 0, "active", 0.0)
		var voice := blade.get_node("MekatanaSound") as AudioStreamPlayer
		check(voice.stream.resource_path.ends_with("weapon-sfx/mekatana-slash-1.wav"), "Mekatana plays selected Stable blade audio")
		check(voice.pitch_scale == 1.0 and voice.volume_db >= -4.0, "Selected blade grain keeps its timbre and audible level")
	else:
		check(false, "Training Mekatana visual exists")
	var shot: AudioStreamPlayer = player.get("_longshot_shot_audio")
	check(shot != null and shot.stream.resource_path.ends_with("weapon-sfx/longshot-shot.wav"), "Longshot uses selected precision rifle audio")
	check(player.get_node_or_null("LongshotReadyAudio") != null, "Longshot ready cue is installed")
	sfx.clear()
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("TRAINING AUDIO TEST: PASS")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)
