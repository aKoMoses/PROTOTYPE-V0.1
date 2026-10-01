extends SceneTree

const NET_PLAYER := preload("res://scripts/network_player.gd")
const SURVIVAL_EFFECTS := preload("res://scripts/survival_evolution_effects.gd")
var _failures: Array[String] = []
var _player: Node3D
var _target: Node3D
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _run() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	_player = _scene.get_node("Player")
	_target = _scene.get_node("TargetDummy")
	await _test_tap()
	await _test_power(1.045, 210.0, 12.0, 28.0, 3.75)
	await _test_power(1.74, 280.0, 16.0, 36.0, 5.0)
	await _test_extended_recast()
	await _test_front_recast()
	await _test_survival_recast()
	await _test_keyboard_recast()
	await _test_touch_aim()
	await _test_cancel_and_lock()
	await _test_desktop_hold()
	await _test_network()
	current_scene = null
	_scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("JAVELIN CHARGE TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _prepare(distance: float = 2.0) -> void:
	_player.set("survival_mode", false)
	_player.call("set_gameplay_enabled", true)
	_player.call("apply_loadout", {"weapon": "blaster", "offensive": "javelin", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	_player.call("reset_combat_state")
	_player.set("training_instant_cooldowns", false)
	_player.set_physics_process(false)
	_player.global_position = Vector3.ZERO
	_player.set("aim_direction", Vector3.FORWARD)
	_target.call("set_training_bot_enabled", false)
	_target.call("reset_combat_state")
	_target.global_position = Vector3(0, 0, -distance)
	_target.rotation = Vector3.ZERO
	var rig: Node3D = _target.get("_visual_rig")
	rig.rotation = Vector3.ZERO
	await physics_frame
	await process_frame


func _shot() -> Node3D:
	for node in get_nodes_in_group("prototype0_gameplay_projectiles"):
		if str(node.name).begins_with("JavelinProjectile"):
			return node
	return null


func _wait_shot() -> void:
	for frame in range(90):
		await physics_frame
		if _shot() == null:
			return


func _test_tap() -> void:
	await _prepare()
	_check(bool(_player.call("begin_touch_action", "offensive")), "tap refused")
	_player.call("end_touch_action", "offensive")
	_player.call("_update_javelin_charge", 0.34)
	_check(_shot() == null and bool(_player.call("is_javelin_charging")), "tap launched before 0.35 s")
	_player.call("_update_javelin_charge", 0.011)
	_check(_shot() != null and not bool(_player.call("is_module_busy")), "tap did not emit or kept cast lock")
	await _wait_shot()
	_check(absf(float(_target.call("get_health")) - 860.0) < 1.0, "tap damage differs from 140")


func _test_power(seconds: float, damage: float, distance: float, speed: float, mark: float) -> void:
	await _prepare()
	_player.call("begin_touch_action", "offensive")
	_player.call("_update_javelin_charge", seconds)
	_check(_shot() == null, "holding emitted before release")
	if seconds >= 1.74:
		_player.call("_update_javelin_charge", 5.0)
		_check(_shot() == null and is_equal_approx(float(_player.call("get_javelin_charge_fraction")), 1.0), "max hold is not capped at 1.74 s")
		var visual: Node = _player.get("_javelin_charge_visual")
		_check(visual.find_children("TridentProng*", "", true, false).size() == 3, "trident does not have three prongs")
	_player.call("end_touch_action", "offensive")
	_player.call("_update_javelin_charge", 0.0)
	var shot := _shot()
	_check(shot != null, "release did not emit")
	if shot != null:
		_check(is_equal_approx(float(shot.get("_range")), distance), "charged range incorrect")
		_check(is_equal_approx(float(shot.get("_speed")), speed), "charged speed incorrect")
	await _wait_shot()
	_check(absf(1000.0 - float(_target.call("get_health")) - damage) < 1.0, "charged damage incorrect")
	_check(absf(float(_target.call("get_javelin_mark_remaining")) - mark) < 0.2, "charged mark duration incorrect")
	_check(float(_player.call("get_javelin_recast_fraction")) > 0.94, "charged mark HUD denominator incorrect")
	_check(_target.call("get_active_effect_types").has("SPOTTED"), "Javelin mark did not apply SPOTTED")
	_check(absf(float(_target.get("combat_state").get_remaining("SPOTTED")) - mark) < 0.2, "SPOTTED duration differs from charge-scaled mark")


func _test_extended_recast() -> void:
	await _prepare(12.0)
	# Clear the authored north cover for this distance test. Obstacle rejection
	# remains covered separately by test_offensive_modules.gd.
	var blockers: Array = _scene.get("_arena_blockers")
	var layers: Array[int] = []
	for blocker in blockers:
		layers.append(blocker.collision_layer)
		blocker.collision_layer = 0
	await physics_frame
	_player.call("begin_touch_action", "offensive")
	_player.call("_update_javelin_charge", 1.74)
	_player.call("end_touch_action", "offensive")
	_player.call("_update_javelin_charge", 0.0)
	await _wait_shot()
	_check(bool(_target.call("has_javelin_mark")), "charged shot cannot hit at 12 m")
	var cooldown := float(_player.call("get_module_cooldown", "javelin"))
	_player.call("begin_touch_action", "offensive")
	_check(_player.global_position.length() > 10.0, "charged recast refused beyond base range")
	_check(not bool(_target.call("has_javelin_mark")), "recast did not consume mark")
	_check(is_equal_approx(float(_player.call("get_module_cooldown", "javelin")), cooldown), "recast restarted cooldown")
	for index in range(blockers.size()):
		blockers[index].collision_layer = layers[index]


func _test_front_recast() -> void:
	await _prepare()
	_target.rotation.y = PI * 0.5
	var rig: Node3D = _target.get("_visual_rig")
	rig.rotation.y = PI * 0.5
	_player.call("_perform_javelin")
	_player.call("_update_javelin_charge", 0.35)
	await _wait_shot()
	var front: Vector3 = _target.call("get_javelin_front_direction")
	_check(front.dot(-rig.global_basis.z.normalized()) > 0.99, "recast heading ignores independent robot rig rotation")
	var controls: Node = _scene.get_node("Interface/TouchControls")
	controls.visible = true
	var center: Vector2 = controls.call("_widget_center", "offensive_button")
	controls.call("_begin_touch", 93, center)
	var offset := _player.global_position - _target.global_position
	_check(offset.normalized().dot(front) > 0.99, "touch recast does not land in front of rotated target")
	_check(not bool(_player.call("is_javelin_charging")), "recast started another charge")
	_check(not bool(_target.call("has_javelin_mark")), "touch recast did not consume mark")
	controls.call("_end_touch", 93)
	controls.call("reset_inputs")


func _test_survival_recast() -> void:
	await _prepare()
	var effects := SURVIVAL_EFFECTS.new()
	effects.player = _player
	_player.add_child(effects)
	_player.set("survival_evolution_effects", effects)
	_player.set("survival_mode", true)
	_player.call("begin_touch_action", "offensive")
	_player.call("_update_javelin_charge", 1.74)
	_player.call("end_touch_action", "offensive")
	_player.call("_update_javelin_charge", 0.0)
	await _wait_shot()
	_check(effects.has_javelin_anchor() and bool(_target.call("has_javelin_mark")), "survival test did not create anchor and mark")
	_check(float(_player.call("get_javelin_recast_fraction")) > 0.94, "survival HUD did not prioritize live mark")
	_player.call("begin_touch_action", "offensive")
	_check(_player.global_position.distance_to(_target.global_position + Vector3.FORWARD * 1.4) < 0.05, "survival recast recalled instead of teleporting in front")
	_check(not effects.has_javelin_anchor() and not bool(_target.call("has_javelin_mark")), "survival teleport left a second recast available")
	_player.set("survival_mode", false)
	_player.set("survival_evolution_effects", null)
	effects.queue_free()
	await process_frame


func _test_keyboard_recast() -> void:
	await _prepare()
	_target.call("apply_javelin_mark", 5.0, "test")
	_player.set("_javelin_mark_target", _target)
	_player.call("_start_module_cooldown", "javelin", 12.0)
	_player.set_physics_process(true)
	Input.action_press("game_offensive")
	await physics_frame
	await physics_frame
	Input.action_release("game_offensive")
	_check(_player.global_position.distance_to(_target.global_position + Vector3.FORWARD * 1.4) < 0.05, "keyboard reactivation is blocked by first launch cooldown")
	_check(float(_player.call("get_module_cooldown", "javelin")) > 11.0, "keyboard recast discarded original cooldown")
	await physics_frame
	_player.set_physics_process(false)


func _test_touch_aim() -> void:
	await _prepare(20.0)
	var controls: Node = _scene.get_node("Interface/TouchControls")
	controls.visible = true
	var center: Vector2 = controls.call("_widget_center", "offensive_button")
	controls.call("_begin_touch", 70, center)
	controls.call("_begin_touch", 71, center)
	controls.call("_end_touch", 71)
	_check(float(_player.get("_javelin_release_at")) < 0.0, "rejected finger released first finger's cast")
	controls.call("_update_touch", 70, center + Vector2(80, 0))
	var direction: Vector3 = _player.get("aim_direction")
	var expected: Vector3 = _player.call("_camera_relative_direction", Vector2.RIGHT)
	_check(direction.dot(expected) > 0.99, "cast joystick does not aim relative to camera")
	controls.call("_end_touch", 70)
	_player.set("aim_direction", Vector3.FORWARD)
	_player.call("_update_javelin_charge", 0.35)
	var shot := _shot()
	_check(shot != null, "touch release did not launch")
	if shot != null:
		_check(Vector3(shot.get("_direction")).dot(expected) > 0.99, "release direction was overwritten before minimum cast completed")
	await _wait_shot()
	controls.call("reset_inputs")


func _test_cancel_and_lock() -> void:
	await _prepare()
	_player.call("begin_touch_action", "offensive")
	_player.call("_activate_defensive_module")
	_check(is_zero_approx(float(_player.call("get_module_cooldown", "magnetic_field"))), "charge allowed concurrent module")
	_player.call("apply_stun", 0.5, "test")
	_player.call("_update_javelin_charge", 2.0)
	_check(_shot() == null and not bool(_player.call("is_javelin_charging")) and not bool(_player.call("is_module_busy")), "stun did not cancel charge and action lock")
	await _prepare()
	_player.call("begin_touch_action", "offensive")
	_player.call("cancel_touch_action", "offensive")
	_check(_player.get("_javelin_charge_visual") == null and _shot() == null, "lost finger emitted or leaked charge effect")
	await _prepare()
	_player.call("begin_touch_action", "offensive")
	_player.call("set_gameplay_enabled", false)
	_check(not bool(_player.call("is_javelin_charging")), "disabled gameplay retained charge")


func _test_desktop_hold() -> void:
	await _prepare(20.0)
	_player.set_physics_process(true)
	Input.action_press("game_offensive")
	await create_timer(1.85).timeout
	_check(bool(_player.call("is_javelin_charging")) and is_equal_approx(float(_player.call("get_javelin_charge_fraction")), 1.0), "desktop physics hold does not reach full power without firing")
	Input.action_release("game_offensive")
	await physics_frame
	await physics_frame
	_check(not bool(_player.call("is_javelin_charging")), "desktop key release did not launch")
	await _wait_shot()
	_player.set_physics_process(false)


func _test_network() -> void:
	var network_script: Script = NET_PLAYER
	if not network_script.can_instantiate():
		_check(false, "network player cannot compile; network verification is blocked")
		return
	var actor := NET_PLAYER.new()
	_scene.add_child(actor)
	actor.call("apply_loadout", {"weapon": "blaster", "offensive": "javelin", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	actor.call("set_gameplay_enabled", true)
	actor.set_physics_process(false)
	actor.global_position = Vector3(5, 0, 0)
	actor.aim_direction = Vector3.FORWARD
	actor.apply_javelin_mark(5.0, "test")
	_check(actor.get_active_effect_types().has("SPOTTED") and actor.has_javelin_mark(), "authoritative network mark did not reveal target")
	actor.clear_javelin_mark()
	actor.receive_action("javelin_release", {"ratio": 1.0})
	_check(not actor.is_javelin_charging(), "network release accepted without begin")
	actor.receive_action("javelin_charge", {})
	_check(actor.is_javelin_charging(), "host did not start network charge")
	actor.call("_update_javelin_charge", 0.7)
	actor.receive_action("javelin_release", {"ratio": 999.0})
	_check(is_equal_approx(float(actor.get("_javelin_release_at")), 0.7), "host trusted client-supplied power")
	actor.call("_update_javelin_charge", 0.0)
	await _wait_shot()
	actor.queue_free()
	await process_frame
