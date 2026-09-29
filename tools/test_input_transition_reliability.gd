extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var touch: Control = flow.get_node("TouchControls")
	var player: Node = scene.get_node("Player")
	flow.set_process(false)
	scene.set_process(false)
	player.set_physics_process(false)
	scene.get_node("TargetDummy").call("set_training_bot_enabled", false)
	touch.set_process(false)
	touch.call("set_hud_layout", load("res://scripts/hud_layout.gd").standard())
	player.call("set_gameplay_enabled", true)
	touch.visible = true
	var move_center: Vector2 = touch.call("_joystick_center")
	var aim_center: Vector2 = touch.call("_aim_center")
	_press(touch, 11, move_center + Vector2(40, 0))
	_press(touch, 12, aim_center + Vector2(0, -40))
	var drag := InputEventScreenDrag.new()
	drag.index = 11
	drag.position = aim_center + Vector2(0, -100)
	touch.call("_input", drag)
	_check(int(touch.get("_joystick_touch")) == 11 and int(touch.get("_aim_touch")) == 12, "a drag outside the initial zone preserves finger ownership")
	_release(touch, 11)
	_check(int(touch.get("_aim_touch")) == 12 and bool(player.get("_touch_fire_active")), "releasing movement preserves another finger's aim/fire")
	touch.notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_owners_empty(touch) and not bool(player.get("_touch_fire_active")) and (player.get("_touch_fire_requests") as Array).is_empty(), "focus loss clears every contact without firing")
	_release(touch, 12)
	_check((player.get("_touch_fire_requests") as Array).is_empty(), "a stale release after focus loss cannot fire")
	_press(touch, 21, move_center + Vector2(40, 0))
	_press(touch, 22, aim_center + Vector2(0, -40))
	player.call("set_gameplay_enabled", false)
	touch.call("_process", 0.01)
	_check(_owners_empty(touch), "disabling combat clears touch ownership before reactivation")
	player.call("set_gameplay_enabled", true)
	touch.call("_process", 0.01)
	drag.index = 21
	drag.position = move_center + Vector2(60, 0)
	touch.call("_input", drag)
	_release(touch, 22)
	_check((player.get("_touch_move_vector") as Vector2).is_zero_approx() and (player.get("_touch_fire_requests") as Array).is_empty(), "old drag and release cannot reactivate commands after combat resumes")
	touch.call("reset_inputs")
	player.call("apply_loadout", {"weapon": "blaster", "offensive": "fulguro_punch", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	var action_centers: Dictionary = touch.call("_action_centers")
	_press(touch, 31, action_centers.offensive)
	_check(bool(player.call("is_fulguro_charging")), "touch starts the existing FULGURO hold")
	touch.notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not bool(player.call("is_fulguro_charging")), "focus loss cancels the charge owned by the lost touch")
	_release(touch, 31)
	_check(not bool(player.get("_fulguro_release_requested")), "a canceled offensive contact cannot release a cast")
	player.call("reset_combat_state")
	player.call("_begin_fulguro_charge")
	touch.call("reset_inputs")
	_check(bool(player.call("is_fulguro_charging")), "an inactive touch overlay preserves a charge started by the PC path")
	player.call("_cancel_fulguro_attack")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	touch.call("_process", 0.01)
	_press(touch, 41, move_center + Vector2(40, 0))
	_press(touch, 42, aim_center + Vector2(0, -40))
	player.call("take_damage", 100000.0, "test", "death")
	_check(bool(player.call("is_real_dead")), "death fixture reaches real death without BAROUD")
	touch.call("_process", 0.01)
	_check(_owners_empty(touch), "death clears held finger ownership")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	touch.call("_process", 0.01)
	drag.index = 41
	drag.position = move_center + Vector2(70, 0)
	touch.call("_input", drag)
	_release(touch, 42)
	_check((player.get("_touch_move_vector") as Vector2).is_zero_approx() and (player.get("_touch_fire_requests") as Array).is_empty(), "respawn does not reuse the dead actor's contacts")
	touch.call("reset_inputs")
	_press(touch, 45, aim_center + Vector2(0, -40))
	paused = true
	touch.call("_process", 0.01)
	_check(_owners_empty(touch) and (player.get("_touch_fire_requests") as Array).is_empty(), "pause clears held touch input without queuing a shot")
	paused = false
	touch.call("_process", 0.01)
	_release(touch, 45)
	_check((player.get("_touch_fire_requests") as Array).is_empty(), "release from a paused contact cannot fire after resuming")
	_press(touch, 46, aim_center + Vector2(0, -40))
	var now := Time.get_ticks_msec() / 1000.0
	player.set("_touch_fire_started_at", now - 0.3)
	player.call("_update_mobile_blaster_contact", now)
	_check(bool(player.call("is_blaster_charging")), "system cancel fixture starts the unchanged mobile hold charge")
	var canceled := InputEventScreenTouch.new()
	canceled.index = 46
	canceled.canceled = true
	touch.call("_input", canceled)
	_check(_owners_empty(touch) and not bool(player.call("is_blaster_charging")) and (player.get("_touch_fire_requests") as Array).is_empty(), "system cancellation clears a charge without releasing it as a shot")
	_press(touch, 51, move_center + Vector2(40, 0))
	var trial: Node = load("res://scripts/player.gd").new()
	root.add_child(trial)
	trial.set_physics_process(false)
	touch.call("set_player", trial)
	_check(_owners_empty(touch) and (player.get("_touch_move_vector") as Vector2).is_zero_approx(), "rebinding touch controls releases the previous actor and contacts")
	touch.call("set_player", player)
	trial.queue_free()
	print("INPUT TRANSITION RELIABILITY: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _press(touch: Control, index: int, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = true
	event.position = point
	touch.call("_input", event)

func _release(touch: Control, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = false
	touch.call("_input", event)

func _owners_empty(touch: Control) -> bool:
	return int(touch.get("_joystick_touch")) == -1 and int(touch.get("_aim_touch")) == -1 and (touch.get("_action_touches") as Dictionary).is_empty()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
