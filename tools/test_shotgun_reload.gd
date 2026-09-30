extends SceneTree

# Keep the full duel/player physics loop alive and never reset the player
# between shots: the third cartouche must exercise the real automatic reload.
var player: CharacterBody3D
var target: StaticBody3D
var rig: PlayerVisualRig
var failures: Array[String] = []
var checks := 0
var maximum_grip_error := 0.0
var sampled_frames := 0
var reloading_frames := 0
var fourth_shot_grip_error := 0.0
var latest_grip_error := 0.0
var projectile_count := 0

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	call_deferred("_run")

func _run() -> void:
	var scene := current_scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	rig = player.get_node("VisualRoot")
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(-2.5, 0.0, 0.0)
	target.call("set_training_bot_enabled", false)
	player.call("set_weapon", "shotgun")
	player.call("set_touch_aim_vector", Vector2.LEFT)
	physics_frame.connect(_feed_aim)
	await create_timer(0.3).timeout
	rig.skeleton.skeleton_updated.connect(_sample_grip)
	node_added.connect(_observe_projectile)
	for shot in range(1, 10):
		await _wait_ready()
		target.call("reset_combat_state")
		var health: float = target.call("get_health")
		var ammo: int = player.call("get_shotgun_ammo")
		var previous_projectiles := projectile_count
		# A press/release runs through the same input and attack path as playing.
		player.call("set_touch_attack_held", true)
		await physics_frame
		await physics_frame
		player.call("set_touch_attack_held", false)
		await create_timer(0.4).timeout
		var damage: float = health - float(target.call("get_health"))
		_check(int(player.call("get_shotgun_ammo")) == ammo - 1, "shot %d consumes one cartridge" % shot)
		_check(projectile_count == previous_projectiles + 6, "shot %d emits six live pellets" % shot)
		_check(damage > 0.0, "shot %d damages the body after previous shots/reloads" % shot)
		print("RELOAD_SHOT: shot=%d damage=%.1f grip=%.4f root=%s aim=%s player=%s target=%s projectiles=%d" % [shot, damage, latest_grip_error, (player.get("_shotgun_pivot") as Node3D).position, player.get("aim_direction"), player.global_position, target.global_position, projectile_count])
		if shot == 4:
			fourth_shot_grip_error = latest_grip_error
			var args := OS.get_cmdline_user_args()
			if args.size() > 0 and DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(args[0])
	await _wait_ready()
	_check(reloading_frames > 0, "automatic reload was processed by the live player")
	_check(int(player.call("get_shotgun_ammo")) == 3, "three magazines reload without resetting combat state")
	_check(maximum_grip_error <= 0.002, "rear grip stays on the right hand through firing and reload (max %.4f m)" % maximum_grip_error)
	_check(fourth_shot_grip_error <= 0.002, "fourth shot remains in the right hand after first reload")
	# Switching weapons during reload must not carry an old transform forward.
	player.call("_perform_shotgun_attack")
	await create_timer(0.75).timeout
	player.call("_start_shotgun_reload")
	await create_timer(0.35).timeout
	player.call("set_weapon", "blaster")
	player.call("set_weapon", "shotgun")
	await create_timer(0.2).timeout
	_check((player.get("_shotgun_pivot") as Node3D).transform.is_equal_approx(Transform3D.IDENTITY), "weapon switch cancels reload with a seated shotgun root")
	rig.skeleton.skeleton_updated.disconnect(_sample_grip)
	node_added.disconnect(_observe_projectile)
	physics_frame.disconnect(_feed_aim)
	print("SHOTGUN LIVE RELOAD TEST: %s (%d checks, %d sampled poses, %d reload poses)" % ["PASS" if failures.is_empty() else "FAIL", checks, sampled_frames, reloading_frames])
	scene.queue_free()
	current_scene = null
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _wait_ready() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while bool(player.get("_shotgun_attack_busy")) or bool(player.call("is_shotgun_reloading")):
		if Time.get_ticks_msec() > deadline:
			_check(false, "attack/reload finishes within five seconds")
			return
		await physics_frame
	await physics_frame

func _grip_error() -> float:
	var weapon: Node3D = player.get("_shotgun_pivot")
	var grip := weapon.find_child("RightHandGrip", true, false) as Node3D
	var index := rig.skeleton.find_bone(String(rig.right_hand_bone_name))
	var hand := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(index)
	return hand.origin.distance_to(grip.global_position)

func _sample_grip() -> void:
	sampled_frames += 1
	latest_grip_error = _grip_error()
	maximum_grip_error = maxf(maximum_grip_error, latest_grip_error)
	if bool(player.call("is_shotgun_reloading")):
		reloading_frames += 1

func _observe_projectile(node: Node) -> void:
	if node.get_script() != null and node.get_script().resource_path == "res://scripts/live_projectile.gd":
		projectile_count += 1

func _feed_aim() -> void:
	# The hidden touchscreen HUD clears idle controls every render frame. Feed
	# the joystick like a held real input without bypassing Player._update_aim.
	player.call("set_touch_aim_vector", Vector2.LEFT)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("RELOAD_FAILURE: " + label)
