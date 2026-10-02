extends SceneTree
## Production scene, camera, projectiles and shield. Run with a graphics backend.
const WALL := preload("res://scripts/magnetic_wall.gd")
const ASSETS := preload("res://scripts/vfx_assets.gd")
var scene: Node3D
var player: Node3D
var target: Node3D
var manager: Node3D
var output := "res://captures/vfx-materials/desktop"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	if args.size() > 1 and args[1] == "small":
		root.size = Vector2i(960, 540)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var controller := load("res://scripts/player.gd") as GDScript
	if controller == null or not controller.can_instantiate():
		push_error("Production controller failed to compile; capture aborted.")
		quit(1)
		return
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	if scene.get_node("Player").get("_utility_modules_component") == null:
		push_error("Production player failed to load; capture aborted.")
		quit(1)
		return
	scene.get_node("Interface").call("_start_duel")
	scene.get_node("Interface").call("_begin_live_round")
	scene.set_meta("camera_shake_enabled", false)
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	manager = scene.get_node("VFXManager")
	scene.get("touch_controls").set_process(false)
	scene.get("touch_controls").set_physics_process(false)
	for kind in ["smoke", "decal"]:
		for variant in range(3):
			ASSETS.texture(kind, variant).get_image().save_png(output.path_join("%s-%d.png" % [kind, variant]))
	for mode in ["blaster", "charged", "shotgun", "longshot", "execution", "metal", "ground", "shield", "shield-low"]:
		await _prepare()
		await _capture_mode(mode)
	scene.call("clear_transient_fx")
	current_scene = null
	scene.queue_free()
	await process_frame
	print("VFX MATERIALS CAPTURE: %s output=%s" % ["PASS" if failures == 0 else "FAIL", output])
	quit(0 if failures == 0 else 1)


func _prepare() -> void:
	manager.quality = 1
	manager.clear()
	player.call("reset_combat_state")
	player.call("clear_touch_inputs")
	target.call("reset_combat_state")
	target.call("set_training_bot_enabled", false)
	player.call("set_gameplay_enabled", true)
	player.position = Vector3(-2.0, 0.0, 1.0)
	target.position = Vector3(3.0, 0.0, -0.8)
	player.set("aim_direction", (target.position - player.position).normalized())
	var direction := (target.position - player.position).normalized()
	player.call("set_touch_aim_vector", Vector2(direction.x, direction.z))
	scene.get_node("CameraRig").call("set_follow_offset", Vector3.ZERO, true)
	await create_timer(0.45).timeout


func _capture_mode(mode: String) -> void:
	var shield: Node3D
	if mode in ["metal", "ground"]:
		manager.impact(Vector3(0.0, 0.025, 0.0), Vector3.UP, mode, 1.4)
	elif mode.begins_with("shield"):
		shield = WALL.new()
		shield.configure(player, 3.0, 2.4, 4.0)
		scene.add_child(shield)
		shield.position = Vector3(0.0, 0.0, -0.8)
		await create_timer(0.22).timeout
		if mode == "shield-low":
			manager.quality = 0
		var contact := shield.global_position + Vector3(0.0, 1.2, 0.075)
		shield.projectile_impact(contact)
		manager.impact(contact, Vector3.BACK, "shield", 1.0)
	else:
		player.call("set_weapon", "longshot" if mode in ["longshot", "execution"] else ("shotgun" if mode == "shotgun" else "blaster"))
		await create_timer(0.25).timeout
		if mode in ["longshot", "execution"]:
			player.call("_spawn_longshot_projectile", mode == "execution", 1)
		elif mode == "shotgun":
			player.call("_perform_shotgun_attack")
		else:
			player.call("_fire_blaster_projectile", 50.0 if mode == "charged" else 20.0, 1.0 if mode == "charged" else 0.0, (target.position - player.position).normalized())
	for frame in range(42):
		await RenderingServer.frame_post_draw
		if frame in [1, 5, 10, 18, 30, 41]:
			var filename := output.path_join("%s-%02d.png" % [mode, frame])
			if root.get_texture().get_image().save_png(filename) != OK:
				failures += 1
	if is_instance_valid(shield):
		shield.queue_free()
		await process_frame
	print("CAPTURE VFX MATERIALS: " + mode)
