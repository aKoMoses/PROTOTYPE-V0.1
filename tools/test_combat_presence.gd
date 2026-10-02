extends SceneTree

const SURFACES := preload("res://scripts/surface_response.gd")
const AUDIO := preload("res://scripts/mecha_audio.gd")
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var player: Node3D
var output := "res://outputs/combat-presence"
var capture := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int = 4) -> void:
	for index in count:
		await physics_frame
		await process_frame

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("capture")
	if OS.get_cmdline_user_args().has("mobile"):
		output = output.path_join("mobile")
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_test_preferences()
	await _duel()
	await _mode("training_ground")
	await _mode("survival")
	var report := {"checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_driver_name()}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	root.get_node("GameSfx").call("clear")
	await create_timer(0.4).timeout
	print("COMBAT PRESENCE: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_preferences() -> void:
	var preferences := root.get_node("GamePreferences")
	preferences.call("save_preferences", "user://combat_presence_preferences_backup.cfg")
	preferences.call("set_combat_zoom", 1.21, false)
	check(preferences.call("save_preferences", "user://combat_presence_zoom.cfg") == OK, "camera preference saves")
	preferences.call("set_combat_zoom", 1.0, false)
	preferences.call("load_preferences", "user://combat_presence_zoom.cfg")
	check(is_equal_approx(float(preferences.get("combat_zoom")), 1.21), "camera preference survives reload")
	preferences.call("set_combat_zoom", 4.0, false)
	check(is_equal_approx(float(preferences.get("combat_zoom")), 1.25), "camera preference stays within usable zoom")
	var legacy := ConfigFile.new()
	legacy.set_value("audio", "music", 0.6)
	legacy.save("user://combat_presence_legacy.cfg")
	preferences.call("load_preferences", "user://combat_presence_legacy.cfg")
	check(is_equal_approx(float(preferences.get("combat_zoom")), 1.14) and is_equal_approx(float(preferences.get("music_volume")), 0.6), "legacy preferences retain audio and gain default camera")
	preferences.call("load_preferences", "user://combat_presence_preferences_backup.cfg")
	preferences.call("set_combat_zoom", 1.14, false)

func load_scene(path: String) -> void:
	scene = (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(8)
	player = scene.get("player")
	check(scene.has_node("CombatPresentationPass"), path + " installs presentation director")
	check(player.has_node("CombatPresence"), path + " installs actor presentation")

func cleanup() -> void:
	root.get_node("GameSfx").call("clear")
	scene.get_node("VFXManager").call("clear")
	scene.queue_free()
	current_scene = null
	await frames(3)

func _duel() -> void:
	await load_scene("res://scenes/main.tscn")
	var flow: Node = scene.get("game_flow")
	flow.call("_open_settings")
	await frames(4)
	var zoom := scene.find_child("CombatZoom", true, false) as HSlider
	check(zoom != null and zoom.is_visible_in_tree(), "camera control is available in real settings screen")
	check(zoom != null and root.get_visible_rect().encloses(zoom.get_global_rect()), "camera control fits current viewport")
	await save("settings")
	scene.call("set_menu_showcase_enabled", false)
	scene.call("set_bot_build_seed", 42)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0, 2)
	player.set("aim_direction", Vector3.FORWARD)
	var target: Node3D = scene.get("target")
	target.global_position = Vector3(3.5, 0, -2)
	target.call("set_training_bot_enabled", true)
	var bot: Node = target.get_node("TrainingBot")
	bot.set_physics_process(false)
	bot.set_process(false)
	scene.set_meta("camera_shake_enabled", false)
	var camera_rig := scene.get_node("CameraRig")
	camera_rig.call("set_target", player)
	camera_rig.call("set_follow_offset", Vector3.ZERO, true)
	await frames(40)
	var presence := player.get_node("CombatPresence")
	var enemy_presence := target.get_node("CombatPresence")
	var director := scene.get_node("CombatPresentationPass")
	var manager := scene.get_node("VFXManager")
	var preferences := root.get_node("GamePreferences")
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	var health := float(player.call("get_health"))
	check(camera.fov < 37.0 and camera.fov > 29.0, "live combat uses closer framing")
	preferences.call("set_combat_zoom", 1.0, false)
	await frames(35)
	check(absf(camera.fov - 38.0) < 0.1, "wide view can be restored immediately")
	preferences.call("set_combat_zoom", 1.14, false)
	await frames(35)
	check(presence.get("weight") != null, "lower body mass layer is installed")
	check(float(player.call("get_health")) == health, "camera and presentation do not change health")
	var readout := player.get("_health_readout") as Node3D
	if readout != null:
		check(float(readout.get_node("HealthBarSprite").get("pixel_size")) < 0.012, "health plaque gives more room to robot")
	var passive := scene.find_child("PassiveSlot", true, false) as Control
	check(passive != null and passive.size.x <= 56.0 and passive.size.x * passive.size.y <= 3000.0, "passive occupies a small medallion")
	check(passive != null and passive.position.x + passive.size.x < 0.0 and passive.position.y >= 0.0, "passive sits beside active modules")
	check(passive.mouse_filter == Control.MOUSE_FILTER_IGNORE, "compact passive does not steal combat inputs")
	await save("duel-ready")
	# Accelerate and brake through the actor's real world positions, never via a
	# synthetic controller property. Presentation must not move the collision body.
	for index in 8:
		player.global_position.x += 0.08
		# Presence measures idle-frame motion; waiting for a physics tick may
		# add idle frames with no movement before the velocity is inspected.
		await process_frame
	check((presence.get("velocity") as Vector3).length() > 0.1, "mass layer observes actual motion")
	check((presence.get("_lean") as Vector2).length() > 0.001, "acceleration produces bounded body weight")
	var at := player.global_position
	await frames(2)
	check(player.global_position == at, "weight layer never moves gameplay actor")
	for weapon in ["blaster", "shotgun", "longshot"]:
		player.call("set_weapon", weapon)
		var direction := (target.global_position - player.global_position).normalized()
		player.set("aim_direction", direction)
		player.call("_begin_weapon_aim")
		player.call("_update_robot_motion", 0.016)
		await frames(12)
		var rig: Node = player.get("_visual_rig")
		rig.call("commit_firing_pose", direction)
		await frames(2)
		var actual: Vector3 = rig.call("get_weapon_forward_direction", weapon)
		print("PRESENCE AIM ", weapon, " dot=", actual.dot(direction), " aim=", direction, " muzzle=", actual)
		check(actual.dot(direction) > 0.999, weapon + " final muzzle retains exact aim")
		check(not bool(presence.get("weight").get("enabled")), weapon + " suppresses locomotion lean during aim")
	bot.set("_windup_remaining", 1.0)
	bot.set("_attack_mode", "fulguro")
	await frames(4)
	check(str(enemy_presence.call("intent")) == "strike", "warning is driven by the committed real windup")
	check(bool(enemy_presence.get("cue").get("visible")), "visible windup lights body vent")
	await save("enemy-windup")
	if capture and OS.get_cmdline_user_args().has("detail"):
		camera_rig.set_process(false)
		var previous_fov := camera.fov
		camera.fov = 12.0
		camera.look_at(target.global_position + Vector3.UP * 1.2, Vector3.UP)
		print("INTENT VENT position=", enemy_presence.get("cue").global_position, " target=", target.global_position)
		await save("enemy-windup-detail")
		camera.fov = previous_fov
		camera_rig.set_process(true)
	bot.set("_windup_remaining", 0.0)
	await frames(3)
	check(not bool(enemy_presence.get("cue").get("visible")), "cancelled windup removes its body cue")
	var metal := StaticBody3D.new()
	metal.name = "TestSteelCover"
	metal.set_meta("vfx_surface", "metal")
	var concrete := StaticBody3D.new()
	concrete.name = "TestConcreteWall"
	concrete.set_meta("vfx_surface", "environment")
	scene.add_child(metal)
	scene.add_child(concrete)
	check(SURFACES.classify(metal) == "metal", "authored cover keeps metal signature")
	check(SURFACES.classify(concrete) == "concrete", "concrete wall gets mineral signature")
	var contact := player.global_position + Vector3(1.0, 0.7, -1.0)
	check(bool(director.call("can_present", contact)), "contact in player's clear view is admitted")
	await _reactive_props(director, manager, contact)
	for surface in ["metal", "concrete", "sand", "shield"]:
		manager.call("impact", contact, Vector3.UP, surface, 1.4)
		await frames(2)
		await save("impact-" + surface)
		manager.call("clear")
		check(int(manager.call("get_debug_counts").active) == 0, surface + " pooled effects clear")
		await frames(5)
	for kind in ["motor", "servo", "concrete"]:
		var stream := AUDIO.stream(kind)
		check(stream.data.size() > 1000 and stream.get_length() > 0.1, kind + " has actual audio samples")
		check(stream == AUDIO.stream(kind), kind + " stream is shared without per-frame allocation")
		if capture:
			stream.save_to_wav(output.path_join(kind + ".wav"))
	_test_footsteps()
	player.call("set_weapon", "blaster")
	player.call("_begin_blaster_charge")
	await frames(3)
	check(str(presence.call("intent")) == "charge" and bool(presence.get("cue").get("visible")), "actual blaster charge lights the body cue")
	player.call("_cancel_blaster_charge")
	await frames(2)
	check(not bool(presence.get("cue").get("visible")), "actual charge cancellation removes body cue")
	var clock := float(presence.get("_clock"))
	paused = true
	for index in 8:
		await process_frame
	check(is_equal_approx(clock, float(presence.get("_clock"))), "pause freezes presentation simulation")
	paused = false
	await frames(3)
	# A real occulting wall must suppress meshes and their mechanical sound,
	# even while a controller still contains a charged attack.
	var wall := StaticBody3D.new()
	wall.name = "TestOccluder"
	wall.collision_layer = 1
	wall.position = Vector3(0, 1.5, -2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 3, 1)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	player.global_position = Vector3(0, 0, 2)
	target.global_position = Vector3(0, 0, -5)
	bot.set("_windup_remaining", 1.0)
	await frames(8)
	var face_contact := Vector3(0, 1, -1.5)
	check(bool(director.call("can_present", face_contact)), "first visible solid face admits its impact")
	var heard: Array[String] = []
	var hear := func(event: String) -> void: heard.append(event)
	root.get_node("GameSfx").connect("event_played", hear)
	manager.call("impact", face_contact, Vector3.BACK, "concrete", 1.0)
	check(heard.has("impact_concrete"), "real solid-face impact plays its material sound")
	root.get_node("GameSfx").disconnect("event_played", hear)
	check(not bool(enemy_presence.call("admitted")), "wall occlusion suppresses opponent presentation")
	check(not bool(enemy_presence.get("cue").get("visible")), "hidden windup does not reveal location")
	check(not bool(enemy_presence.get("motor").get("playing")), "hidden robot cannot leak location through motor")
	check(not bool(director.call("can_present", target.global_position + Vector3.UP)), "occluded contact cannot animate props or play surface audio")
	wall.queue_free()
	metal.queue_free()
	concrete.queue_free()
	await frames(2)
	manager.set("quality", 0)
	for index in 30:
		manager.call("locomotion_dust", player.global_position, Vector3.UP, 1.0)
	var counts: Dictionary = manager.call("get_debug_counts")
	check(int(counts.particles) <= int(manager.get("max_particles")), "low-quality locomotion stays in particle budget")
	manager.call("clear")
	check(not bool(presence.get("motor").get("playing")), "round cleanup immediately stops actor motor")
	check(int(manager.call("get_debug_counts").active) == 0, "round cleanup removes locomotion dust")
	var actor_count: int = director.get("_actors").size()
	target.queue_free()
	await frames(40)
	check(director.get("_actors").size() == actor_count - 1, "retired enemy is removed from presentation tracking")
	await cleanup()

func _test_footsteps() -> void:
	var sfx := root.get_node("GameSfx")
	for chassis in ["agile", "polyvalent", "puissant"]:
		sfx.call("reset_locomotion")
		seed(3185)
		var expected := randf()
		seed(3185)
		for index in 8:
			sfx.call("update_locomotion", 0.25, 0.10, false, true, chassis)
		check(is_equal_approx(randf(), expected), chassis + " footstep does not change gameplay randomness")
		var voice: AudioStreamPlayer = sfx.get("_step_player")
		check(voice.playing, chassis + " footstep is emitted during movement")
		var nominal: float = {"agile": 1.14, "polyvalent": 1.0, "puissant": 0.84}[chassis]
		check(absf(voice.pitch_scale - nominal) < 0.04, chassis + " has its own step weight")
	sfx.call("reset_locomotion")

func _reactive_props(director: Node, manager: Node, at: Vector3) -> void:
	var source := ShaderMaterial.new()
	source.shader = load("res://scripts/bush_foliage.gdshader")
	source.set_shader_parameter("wind_strength", 0.5)
	var nearby := MeshInstance3D.new()
	var remote := MeshInstance3D.new()
	for mesh in [nearby, remote]:
		mesh.mesh = QuadMesh.new()
		mesh.material_override = source
		mesh.hide()
		scene.add_child(mesh)
	nearby.global_position = at
	remote.global_position = at + Vector3.RIGHT * 8.0
	director.call("_scan")
	check(nearby.material_override != remote.material_override, "shared foliage finishes become independent local responses")
	manager.emit_signal("surface_contact", at, "concrete", 1.0)
	await frames(2)
	check(float(nearby.material_override.get_shader_parameter("wind_strength")) > 0.5, "visible impact disturbs nearby foliage")
	check(is_equal_approx(float(remote.material_override.get_shader_parameter("wind_strength")), 0.5), "same impact leaves remote foliage calm")
	manager.call("clear")
	check(is_equal_approx(float(nearby.material_override.get_shader_parameter("wind_strength")), 0.5), "cleanup restores authored foliage breeze")
	nearby.queue_free()
	remote.queue_free()
	await frames(2)

func _mode(mode: String) -> void:
	await load_scene("res://scenes/" + mode + ".tscn")
	if mode == "survival":
		scene.call("_choose_weapon", "blaster")
		scene.call("_begin_wave_combat")
	else:
		if bool(scene.get("_menu").get("visible")):
			scene.call("_toggle_menu")
	await frames(12)
	var actor_presence := player.get_node("CombatPresence")
	check(actor_presence.get("weight") != null, mode + " reuses mass layer")
	check(bool(actor_presence.call("admitted")), mode + " enables presentation while playing")
	await save(mode)
	await cleanup()

func save(label: String) -> void:
	if not capture:
		return
	player.call("_update_world_ui_anchor")
	var flow: Node = scene.get("game_flow") if "game_flow" in scene else null
	if flow != null:
		flow.call("_update_hud")
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, label + " native capture saved")
