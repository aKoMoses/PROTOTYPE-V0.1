extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("INPUT GUI DISPATCH: SKIP (requires a rendered viewport for GUI hit testing)")
		quit(0)
		return
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(4):
		await process_frame
	var flow: Node = scene.get_node("Interface")
	var touch: Control = flow.get_node("TouchControls")
	var player: Node = scene.get_node("Player")
	scene.set_process(false)
	flow.set_process(false)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	scene.get_node("TargetDummy").call("set_training_bot_enabled", false)
	player.set_physics_process(false)
	player.call("apply_loadout", {"weapon": "blaster", "offensive": "fulguro_punch", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	for _frame in range(4):
		await process_frame
	var token := int(player.get("_blaster_attack_token"))
	await _mouse(true, Vector2(640, 360))
	player.call("_update_attack")
	_check(bool(player.call("is_blaster_charging")), "a real dispatched physical mouse press reaches combat through the HUD")
	await _mouse(false, Vector2(640, 360))
	player.call("_update_attack")
	_check(int(player.get("_blaster_attack_token")) == token + 1, "real mouse release fires the existing PC shot once")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	var pause_button: Button = flow.get("_hud").get_node("PauseButton")
	var pause_center := pause_button.get_global_rect().get_center()
	token = int(player.get("_blaster_attack_token"))
	await _mouse(true, pause_center)
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "a real Pause GUI press does not also start a weapon charge")
	await _mouse(false, pause_center)
	_check(paused, "the dispatched Pause click really opens pause")
	var resume_button := _find_button(flow.get("_pause_panel"), "REPRENDRE")
	_check(resume_button != null, "pause exposes its real Resume button")
	if resume_button != null:
		var resume_center: Vector2 = resume_button.get_global_rect().get_center()
		await _mouse(true, resume_center)
		await _mouse(false, resume_center)
		player.call("_update_attack")
		_check(not paused and not bool(player.call("is_blaster_charging")) and int(player.get("_blaster_attack_token")) == token, "a real Resume GUI click resumes without firing")
	else:
		flow.call("_resume")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	touch.visible = true
	var move_center: Vector2 = touch.call("_joystick_center")
	var aim_center: Vector2 = touch.call("_aim_center")
	token = int(player.get("_blaster_attack_token"))
	await _touch(true, 0, move_center + Vector2(40, 0))
	player.call("_update_attack")
	_check(int(touch.get("_joystick_touch")) == 0 and not bool(player.call("is_blaster_charging")), "a dispatched movement finger and its emulated mouse cannot attack")
	await _touch(true, 1, aim_center + Vector2(0, -40))
	_check(int(touch.get("_aim_touch")) == 1 and bool(player.get("_touch_fire_active")), "a second dispatched finger owns mobile aim/fire")
	await _touch(false, 0, move_center + Vector2(40, 0))
	_check(int(touch.get("_aim_touch")) == 1 and bool(player.get("_touch_fire_active")), "movement release keeps the dispatched aim contact")
	await _touch(false, 1, aim_center + Vector2(0, -40))
	player.call("_update_attack")
	_check(int(player.get("_blaster_attack_token")) == token + 1, "the dispatched mobile aim tap creates exactly one shot")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	await _mouse(true, Vector2(640, 360))
	player.call("_update_attack")
	flow.call("_toggle_pause")
	_check(paused and not bool(player.call("is_blaster_charging")), "pause cancels a PC charge already owned before the GUI transition")
	await _mouse(false, Vector2(640, 360))
	flow.call("_resume")
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "the old physical mouse hold cannot remain charged after pause")
	flow.call("_return_menu")
	player.call("set_gameplay_enabled", true)
	await _mouse(true, Vector2(20, 400))
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "navigation's real full-screen GUI blocks mouse combat commands")
	await _mouse(false, Vector2(20, 400))
	paused = false
	scene.queue_free()
	await process_frame
	await create_timer(0.12).timeout
	print("INPUT GUI DISPATCH: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _mouse(pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _touch(pressed: bool, index: int, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.pressed = pressed
	event.index = index
	event.position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, title)
		if found != null:
			return found
	return null

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
