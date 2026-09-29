extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(4):
		await process_frame
	var player: Node = scene.get_node("Player")
	var touch: Control = scene.get_node("Interface/TouchControls")
	scene.set_process(false)
	scene.get_node("Interface").set_process(false)
	scene.get_node("TargetDummy").call("set_training_bot_enabled", false)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	touch.set_process(false)
	touch.set_process_input(false)
	touch.call("set_hud_layout", load("res://scripts/hud_layout.gd").standard())
	touch.visible = true
	_prepare(player, touch)
	_check(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)), "fixture uses the production touch-to-mouse emulation setting")
	var move_center: Vector2 = touch.call("_joystick_center")
	var aim_center: Vector2 = touch.call("_aim_center")
	var touch_press := InputEventScreenTouch.new()
	touch_press.index = 0
	touch_press.pressed = true
	touch_press.position = move_center + Vector2(40, 0)
	touch.call("_input", touch_press)
	Input.parse_input_event(touch_press)
	Input.flush_buffered_events()
	_check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "the touch fixture really produces an emulated left mouse hold")
	var token := int(player.get("_blaster_attack_token"))
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "movement alone cannot create a PC blaster charge")
	var aim_press := InputEventScreenTouch.new()
	aim_press.index = 1
	aim_press.pressed = true
	aim_press.position = aim_center + Vector2(0, -40)
	touch.call("_input", aim_press)
	Input.parse_input_event(aim_press)
	Input.flush_buffered_events()
	player.call("_update_attack")
	_check(int(touch.get("_joystick_touch")) == 0 and int(touch.get("_aim_touch")) == 1, "movement and aim keep separate fingers despite mouse emulation")
	_check(bool(player.get("_touch_fire_active")), "the aim finger retains the existing mobile firing gesture")
	touch_press = touch_press.duplicate()
	touch_press.pressed = false
	touch.call("_input", touch_press)
	Input.parse_input_event(touch_press)
	Input.flush_buffered_events()
	_check(bool(player.get("_touch_fire_active")), "releasing the mouse-emulating movement finger preserves aim")
	aim_press = aim_press.duplicate()
	aim_press.pressed = false
	touch.call("_input", aim_press)
	Input.parse_input_event(aim_press)
	Input.flush_buffered_events()
	player.call("_update_attack")
	_check(int(player.get("_blaster_attack_token")) == token + 1, "a mobile aim tap produces exactly one requested shot")
	_prepare(player, touch)
	_mouse(player, true, InputEvent.DEVICE_ID_EMULATION, true)
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "an emulated MouseButton cannot independently attack")
	_mouse(player, false, InputEvent.DEVICE_ID_EMULATION, true)
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "emulated release cannot leave a PC charge")
	_prepare(player, touch)
	# Simulate Godot's two input stages explicitly: a GUI-handled event reaches
	# _input, while a combat-area press also reaches _unhandled_input. Input's
	# global state still comes from real InputEvent objects in each case.
	_mouse(player, true, 0, false)
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "a physical GUI press cannot start a charge")
	_mouse(player, false, 0, false)
	player.call("_update_attack")
	_check((player.get("_touch_fire_requests") as Array).is_empty(), "a GUI release cannot queue touch fire")
	_prepare(player, touch)
	token = int(player.get("_blaster_attack_token"))
	_mouse(player, true, 0, true)
	player.call("_update_attack")
	_check(bool(player.call("is_blaster_charging")), "a physical combat mouse press retains PC charge")
	_mouse(player, false, 0, false)
	player.call("_update_attack")
	_check(int(player.get("_blaster_attack_token")) == token + 1 and not bool(player.call("is_blaster_charging")), "a valid physical press releases once even over GUI")
	_prepare(player, touch)
	token = int(player.get("_blaster_attack_token"))
	_mouse(player, true, 0, true)
	player.call("_update_attack")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not bool(player.call("is_blaster_charging")), "focus loss cancels a PC-owned charge")
	_mouse(player, false, 0, false)
	player.call("_update_attack")
	_check(int(player.get("_blaster_attack_token")) == token, "a mouse release from before focus loss cannot fire")
	_prepare(player, touch)
	_key(true)
	player.call("_update_attack")
	_check(bool(player.call("is_blaster_charging")), "Space retains its existing PC charge mapping")
	token = int(player.get("_blaster_attack_token"))
	player.call("reset_desktop_inputs")
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "a Space hold cannot restart after input suspension")
	_key(false)
	player.call("_update_attack")
	_check(int(player.get("_blaster_attack_token")) == token, "the stale Space release cannot fire")
	await physics_frame
	_key(true)
	player.call("_update_attack")
	_check(bool(player.call("is_blaster_charging")), "a new Space press rearms normally")
	_key(false)
	player.call("_update_attack")
	_check(int(player.get("_blaster_attack_token")) == token + 1, "the new Space release still fires once")
	_prepare(player, touch)
	player.call("set_weapon", "shotgun")
	token = int(player.get("_shotgun_attack_token"))
	_mouse(player, true, InputEvent.DEVICE_ID_EMULATION, true)
	player.call("_update_attack")
	_check(int(player.get("_shotgun_attack_token")) == token, "mouse emulation cannot fire the Shotgun")
	_mouse(player, false, InputEvent.DEVICE_ID_EMULATION, true)
	player.call("reset_combat_state")
	_mouse(player, true, 0, true)
	player.call("_update_attack")
	_check(int(player.get("_shotgun_attack_token")) > token, "physical mouse retains the Shotgun press/hold path")
	_mouse(player, false, 0, false)
	_prepare(player, touch)
	player.call("set_gameplay_enabled", false)
	_mouse(player, true, 0, true)
	player.call("set_gameplay_enabled", true)
	player.call("_update_attack")
	_check(not bool(player.call("is_blaster_charging")), "a mouse button held before combat cannot become a new combat press")
	_mouse(player, false, 0, false)
	_prepare(player, touch)
	player.call("apply_loadout", {"weapon": "blaster", "offensive": "fulguro_punch", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	_key(true, KEY_A)
	player.call("_update_debug_effects")
	_check(bool(player.call("is_fulguro_charging")), "the PC A hold starts its existing FULGURO charge")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not bool(player.call("is_fulguro_charging")), "focus loss cancels only the held PC FULGURO charge")
	_key(false, KEY_A)
	player.call("_update_debug_effects")
	_check(not bool(player.get("_fulguro_release_requested")), "an old A release cannot discharge after focus loss")
	player.call("reset_combat_state")
	_key(true, KEY_A)
	player.call("_update_debug_effects")
	player.call("reset_desktop_inputs")
	_check(not bool(player.call("is_fulguro_charging")), "pause suspension cancels the held PC FULGURO charge")
	_key(false, KEY_A)
	player.call("_update_debug_effects")
	_check(not bool(player.get("_fulguro_release_requested")), "resume cannot discharge the old A contact")
	_key(false)
	player.call("reset_desktop_inputs")
	touch.call("reset_inputs")
	scene.queue_free()
	await process_frame
	await create_timer(0.12).timeout
	print("MOUSE/TOUCH INPUT ROUTING: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _prepare(player: Node, touch: Control) -> void:
	_mouse(player, false, 0, false)
	_key(false)
	touch.call("reset_inputs")
	player.call("apply_loadout", {"weapon": "blaster", "offensive": "modulo_drone", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"})
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)

func _mouse(player: Node, pressed: bool, device: int, unhandled: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.device = device
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	player.call("_input", event)
	if unhandled:
		player.call("_unhandled_input", event)

func _key(pressed: bool, key: Key = KEY_SPACE) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
