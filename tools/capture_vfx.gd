extends SceneTree

# Run with a graphics backend: --script res://tools/capture_vfx.gd -- OUTPUT_DIR MODE.
# MODE: suite, blaster, charged, shotgun, moving, metal, wall, ground,
# burn, slow, stun, spotted, or statuses. Uses the production gameplay camera.
var _output_directory := "res://exports/vfx-review"
var _scene: Node
var _player: Node3D
var _target: Node3D
var _manager: Node
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("VFX capture requires a graphics backend; omit --headless.")
		quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_output_directory = arguments[0]
	var mode := arguments[1].to_lower() if arguments.size() > 1 else "suite"
	var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_directory))
	if output_error != OK:
		push_error("Cannot create VFX capture directory: %s" % error_string(output_error))
		quit(1)
		return
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	var flow := _scene.get_node_or_null("Interface")
	if flow != null:
		flow.call("_start_duel")
		flow.call("_begin_live_round")
	_player = _scene.get_node("Player") as Node3D
	_target = _scene.get_node("TargetDummy") as Node3D
	_manager = _scene.get_node_or_null("VFXManager")
	if _manager == null:
		push_error("VFXManager missing from gameplay scene")
		quit(1)
		return
	_scene.set_meta("camera_shake_enabled", false)
	_target.call("set_training_bot_enabled", false)
	var modes: Array[String] = []
	if mode == "suite":
		modes.assign(["blaster", "charged", "shotgun", "moving", "metal", "wall", "ground", "burn", "slow", "stun", "spotted", "statuses"])
	else:
		modes.append(mode)
	for effect_mode in modes:
		await _prepare()
		await _capture_mode(effect_mode)
	_scene.call("clear_transient_fx")
	current_scene = null
	_scene.queue_free()
	await process_frame
	await create_timer(0.10).timeout
	print("VFX CAPTURE: %s (%s)" % ["PASS" if _failures == 0 else "FAIL", ProjectSettings.globalize_path(_output_directory)])
	quit(0 if _failures == 0 else 1)


func _prepare() -> void:
	_player.call("clear_touch_inputs")
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	_target.call("set_training_bot_enabled", false)
	_manager.call("clear")
	_player.position = Vector3(-1.7, 0.0, 0.8)
	_target.position = Vector3(1.0, 0.0, -2.4)
	_player.call("set_gameplay_enabled", true)
	_player.call("set_weapon", "blaster")
	_player.set("aim_direction", (_target.position - _player.position).normalized())
	await create_timer(0.65).timeout


func _capture_mode(mode: String) -> void:
	match mode:
		"blaster", "charged", "moving":
			if mode == "moving":
				_player.call("set_touch_move_vector", Vector2(1.0, 0.0))
				await create_timer(0.15).timeout
			var direction := (_target.position - _player.position).normalized()
			var charge := 1.0 if mode == "charged" else 0.0
			# First-tap emission may await skeleton_updated. Observe the real
			# emitted flash before sampling; render latency must not expire it.
			_manager.set_process(false)
			_player.call("_fire_blaster_projectile", 50.0 if charge > 0.0 else 20.0, charge, direction)
			await _wait_for_muzzle()
			await _save_frame(mode + "_muzzle")
			_manager.set_process(true)
			await create_timer(0.07).timeout
			await _save_frame(mode + "_travel")
			await _capture_first_damage(mode + "_impact")
			_player.call("clear_touch_inputs")
		"shotgun":
			_player.call("set_weapon", "shotgun")
			await create_timer(0.25).timeout
			_manager.set_process(false)
			_player.call("_perform_shotgun_attack")
			await _wait_for_muzzle()
			await _save_frame(mode + "_muzzle")
			_manager.set_process(true)
			await _capture_first_damage(mode + "_impact")
		"metal", "wall", "ground":
			var position := Vector3(0.0, 0.1, -1.0)
			var normal := Vector3.UP
			if mode != "ground":
				position = Vector3(0.0, 0.8, -2.0)
				normal = Vector3.BACK
			_manager.set_process(false)
			_manager.call("impact", position, normal, mode, 1.3)
			_manager.call("_process", 0.03)
			await _save_frame(mode + "_impact")
			_manager.set_process(true)
			await create_timer(0.4).timeout
			await _save_frame(mode + "_decal")
		"burn", "slow", "stun", "spotted", "statuses":
			if mode in ["burn", "statuses"]:
				_target.call("apply_burn", 1.5, 0.0, "vfx_capture")
			if mode in ["slow", "statuses"]:
				_target.call("apply_slow", 1.5, 30.0, "vfx_capture")
			if mode in ["stun", "statuses"]:
				_target.call("apply_stun", 1.5, "vfx_capture")
			if mode in ["spotted", "statuses"]:
				_target.call("apply_spotted", 1.5, "vfx_capture")
			await create_timer(0.22).timeout
			await _save_frame(mode)
			await create_timer(1.45).timeout
			await _save_frame(mode + "_expired")
		_:
			_failures += 1
			push_error("Unknown VFX capture mode: " + mode)


func _wait_for_muzzle() -> void:
	for _frame in range(90):
		for effect in _manager.get("_active"):
			if effect["kind"] == "muzzle":
				_manager.call("_process", 0.0)
				return
		await process_frame
	_failures += 1
	push_error("No confirmed muzzle flash observed for capture")


func _capture_first_damage(filename: String) -> void:
	for _frame in range(90):
		if float(_target.call("get_health")) < 999.0:
			await _save_frame(filename)
			return
		await process_frame
	_failures += 1
	push_error("No gameplay hit observed for capture: " + filename)


func _save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var frame_image := root.get_texture().get_image()
	var error := frame_image.save_png(_output_directory.path_join(filename + ".png"))
	if error != OK:
		_failures += 1
		push_error("Capture failed: %s (%s)" % [filename, error_string(error)])
	else:
		print("CAPTURE VFX: %s" % _output_directory.path_join(filename + ".png"))
