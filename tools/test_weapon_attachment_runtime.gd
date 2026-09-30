extends SceneTree

## Runtime regression for a carried weapon appearing above its rendered hand.
## Keep production physics callbacks; compare against the final modified bone
## cached in skeleton_updated, immediately before each rendered frame.
## Run with --path <project> --script res://tools/test_weapon_attachment_runtime.gd.
const MAXIMUM_GRIP_ERROR := 0.001
var _stage: Node3D
var _player: Node3D
var _rig: PlayerVisualRig
var _final_hand := Transform3D.IDENTITY
var _pose_seen := false
var _case := ""
var _case_maximum := 0.0
var _case_samples := 0
var _render_samples := 0
var _physics_samples := 0
var _failures: Array[String] = []
var _checks := 0
var _old_physics_rate := 60
var _old_max_fps := 0
var _capture_pending := false
var _capture_saved := false


func _initialize() -> void:
	_old_physics_rate = Engine.physics_ticks_per_second
	_old_max_fps = Engine.max_fps
	Engine.physics_ticks_per_second = 10
	Engine.max_fps = 240
	_stage = Node3D.new()
	_stage.name = "WeaponAttachmentRuntimeStage"
	root.add_child(_stage)
	current_scene = _stage
	var player_script := load("res://scripts/player.gd") as Script
	if player_script == null or not player_script.can_instantiate():
		_check(false, "production player script loads")
		_finish()
		return
	_player = player_script.new() as Node3D
	_player.name = "Player"
	_stage.add_child(_player)
	var camera := Camera3D.new()
	camera.name = "RuntimeCamera"
	camera.position = Vector3(0.0, 10.0, 10.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	_stage.add_child(camera)
	camera.current = true
	var lighting := DirectionalLight3D.new()
	lighting.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	lighting.light_energy = 1.5
	_stage.add_child(lighting)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.7
	_stage.add_child(world)
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_stage.get_node("RuntimeCamera").look_at(Vector3.UP)
	if DisplayServer.get_name() == "headless":
		_check(false, "runtime attachment test requires a real renderer; omit --headless")
		_finish()
		return
	_rig = _player.get_node_or_null("VisualRoot") as PlayerVisualRig
	_check(_rig != null and _rig.skeleton != null, "standalone production player installs its animated skeleton")
	if _rig == null or _rig.skeleton == null:
		_finish()
		return
	_check(_rig.animation_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS and _rig.skeleton.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS, "animation and modifiers retain production physics callbacks")
	_rig.skeleton.skeleton_updated.connect(_cache_final_pose)
	RenderingServer.frame_pre_draw.connect(_sample_render_pose)
	RenderingServer.frame_post_draw.connect(_capture_rendered_frame)
	physics_frame.connect(func() -> void: _physics_samples += 1)
	_player.call("set_gameplay_enabled", true)
	_player.set("training_instant_cooldowns", true)
	await _wait_seconds(0.60)
	for weapon in ["shotgun", "blaster"]:
		_player.call("apply_loadout", {
			"weapon": weapon,
			"offensive": "pelto_smash",
			"defensive": "magnetic_field",
			"mobility": "pyro_boots",
			"passive": "omnivamp",
		})
		_player.set("aim_direction", Vector3.FORWARD)
		_player.call("_reset_weapon_pose_to_locomotion", true)
		await _observe(weapon + " ready", 0.35)
		if weapon == "shotgun":
			await _shotgun_reload_case("shotgun first reload")
			_player.call("set_weapon", "blaster")
			await _observe("blaster after shotgun reload", 0.30)
			_player.call("set_weapon", "shotgun")
			await _observe("shotgun reequipped after reload", 0.30)
			_player.call("reset_combat_state")
			_player.call("set_gameplay_enabled", true)
			await _observe("shotgun reset after reload", 0.30)
			await _shotgun_reload_case("shotgun repeated reload")
			await _interrupt_shotgun_reload("switch")
			await _interrupt_shotgun_reload("reset")
			await _automatic_shotgun_reload()
		_player.call("_begin_weapon_aim")
		await _observe(weapon + " raised", 0.35)
		if weapon == "shotgun":
			_player.call("_perform_shotgun_attack")
		else:
			_player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.FORWARD)
		await _observe(weapon + " fire", 0.70)
		_player.call("_begin_aim_hold")
		await _observe(weapon + " lowering", 0.70)
		await _pelto_case(weapon, "finish")
		await _pelto_case(weapon, "cancel")
		await _pelto_case(weapon, "reset")
		await _pelto_case(weapon, "pause")
	_check(_pose_seen and _render_samples > 0, "test samples both committed skeleton poses and rendered frames")
	_check(_render_samples > _physics_samples * 2, "render sampling exceeds physics rate to expose intervening stale attachment frames")
	print("[WeaponAttachmentRuntime] render_samples=%d physics_samples=%d" % [_render_samples, _physics_samples])
	_finish()


func _shotgun_reload_case(label: String) -> void:
	_player.set("_shotgun_ammo", 0)
	_player.call("_start_shotgun_reload")
	_check(bool(_player.call("is_shotgun_reloading")), label + " starts actual empty-magazine reload")
	await _observe(label + " active", 0.60)
	var deadline := Time.get_ticks_msec() + 3000
	while bool(_player.call("is_shotgun_reloading")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(_player.call("is_shotgun_reloading")), label + " completes")
	await _observe(label + " completed", 0.30)


func _interrupt_shotgun_reload(ending: String) -> void:
	_player.set("_shotgun_ammo", 1)
	_player.call("_start_shotgun_reload")
	_check(bool(_player.call("is_shotgun_reloading")), "shotgun reload interrupted by " + ending + " starts")
	await _observe("shotgun reload before " + ending, 0.40)
	if ending == "switch":
		_player.call("set_weapon", "blaster")
		await _observe("blaster interrupts shotgun reload", 0.20)
		_player.call("set_weapon", "shotgun")
	else:
		_player.call("reset_combat_state")
		_player.call("set_gameplay_enabled", true)
	_check(not bool(_player.call("is_shotgun_reloading")), "shotgun " + ending + " cancels its reload")
	await _observe("shotgun after interrupted reload " + ending, 0.30)


func _automatic_shotgun_reload() -> void:
	_player.set("_shotgun_ammo", 1)
	_player.call("_perform_shotgun_attack")
	var deadline := Time.get_ticks_msec() + 2000
	while not bool(_player.call("is_shotgun_reloading")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(bool(_player.call("is_shotgun_reloading")) and int(_player.call("get_shotgun_ammo")) == 0, "firing the last actual shotgun shell automatically starts reload")
	await _observe("shotgun automatic reload active", 0.60)
	deadline = Time.get_ticks_msec() + 3000
	while bool(_player.call("is_shotgun_reloading")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(_player.call("is_shotgun_reloading")) and int(_player.call("get_shotgun_ammo")) == 3, "automatic reload finishes with the complete three-shell magazine")
	await _observe("shotgun automatic reload completed", 0.30)


func _pelto_case(weapon: String, ending: String) -> void:
	_player.call("reset_module_state")
	_player.call("_reset_weapon_pose_to_locomotion", true)
	await _observe(weapon + " before Pelto " + ending, 0.20)
	_case = weapon + " Pelto " + ending
	_case_maximum = 0.0
	_case_samples = 0
	_player.call("_perform_pelto_smash")
	_check(str(_player.get("_pelto_phase")) != "", _case + " starts the real module cast")
	await _wait_seconds(0.25)
	if ending == "cancel":
		_player.call("_cancel_pelto_smash")
	elif ending == "reset":
		_player.call("reset_combat_state")
		_player.call("set_gameplay_enabled", true)
	elif ending == "pause":
		_player.call("_cancel_pelto_smash")
		paused = true
		await _wait_seconds(0.25)
		paused = false
	else:
		var deadline := Time.get_ticks_msec() + 3500
		while str(_player.get("_pelto_phase")) != "" and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(str(_player.get("_pelto_phase")) == "", _case + " completes naturally")
	await _wait_seconds(0.40)
	var socket := _rig.get_weapon_socket(StringName(weapon))
	var weapon_root := socket.get_node("Weapon_%s" % weapon) as Node3D
	_check(weapon_root.visible, _case + " restores the equipped weapon")
	_report_case()


func _observe(label: String, seconds: float) -> void:
	_case = label
	_case_maximum = 0.0
	_case_samples = 0
	await _wait_seconds(seconds)
	_report_case()


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _cache_final_pose() -> void:
	_final_hand = _rig.skeleton.get_bone_global_pose(_rig.get_right_hand_bone_index())
	_pose_seen = true


func _sample_render_pose() -> void:
	if not _pose_seen or _case.is_empty():
		return
	_render_samples += 1
	var weapon_id := StringName(_player.call("get_weapon_id"))
	var socket := _rig.get_weapon_socket(weapon_id)
	var weapon_root := socket.get_node("Weapon_%s" % weapon_id) as Node3D
	if not weapon_root.is_visible_in_tree():
		return
	var right_grip := weapon_root.find_child("RightHandGrip", true, false) as Node3D
	var rendered_grip := _rig.skeleton.global_transform.affine_inverse() * right_grip.global_position
	var error := rendered_grip.distance_to(_final_hand.origin)
	_case_samples += 1
	if error > _case_maximum:
		if _case_maximum <= MAXIMUM_GRIP_ERROR and error > MAXIMUM_GRIP_ERROR:
			print("[WeaponAttachmentDrift] case=%s error=%.6f hand=%s grip=%s paused=%s" % [_case, error, _final_hand.origin, rendered_grip, paused])
			_capture_pending = true
		_case_maximum = error


func _capture_rendered_frame() -> void:
	if not _capture_pending or _capture_saved:
		return
	_capture_pending = false
	_capture_saved = true
	var capture_path := "res://.godot/weapon-attachment-runtime-drift.png"
	root.get_texture().get_image().save_png(capture_path)
	print("[WeaponAttachmentCapture] " + ProjectSettings.globalize_path(capture_path))


func _report_case() -> void:
	print("[WeaponAttachmentCase] %s visible_render_samples=%d maximum_grip_error=%.6f" % [_case, _case_samples, _case_maximum])
	_check(_case_samples > 0 and _case_maximum <= MAXIMUM_GRIP_ERROR, _case + " keeps every rendered rear grip attached to the final modified hand")
	_case = ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)
		push_error("FAIL: " + label)


func _finish() -> void:
	paused = false
	Engine.physics_ticks_per_second = _old_physics_rate
	Engine.max_fps = _old_max_fps
	print("WEAPON ATTACHMENT RUNTIME: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
