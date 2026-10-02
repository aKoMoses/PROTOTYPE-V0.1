extends SceneTree

const STATE := preload("res://scripts/combat_state.gd")
const NETWORK_STATE := preload("res://scripts/network_combat_state.gd")
const CAMERA := preload("res://scripts/camera_rig.gd")
class TestPlayer extends "res://scripts/player.gd":
	var simulated_attack := false
	func _desktop_attack_input_held() -> bool:
		return simulated_attack

class ActionRecorder extends Node:
	var _phase := "live"
	var actions: Array[String] = []
	func on_actor_action(_actor: Node, action: String, _data: Dictionary) -> void:
		actions.append(action)

var failures: Array[String] = []
var checks := 0
var player: Node3D
var controls: Node


func _initialize() -> void:
	_test_stun_recovery()
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	player = TestPlayer.new()
	scene.add_child(player)
	await process_frame
	player.set_physics_process(false)
	controls = player.get("_controls_component")
	await _test_modules()
	await _test_weapons()
	await _test_charge_release()
	await _test_dash(scene)
	await _test_network_buffer(scene)
	_test_camera(scene)
	player.call("set_gameplay_enabled", false)
	scene.queue_free()
	current_scene = null
	await create_timer(0.8).timeout
	for failure in failures:
		push_error(failure)
	print("GAMEPLAY FLUIDITY: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func prepare(weapon: String = "blaster") -> void:
	player.call("set_gameplay_enabled", true)
	player.call("apply_loadout", {"weapon": weapon, "offensive": "fulguro_punch", "defensive": "counter", "mobility": "pyro_boots", "passive": "omnivamp"})
	player.call("reset_combat_state")
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3.RIGHT)
	player.set("_last_move_direction", Vector3.RIGHT)
	await physics_frame


func lock() -> int:
	return int(player.call("_try_begin_module_action", "fixture"))


func unlock(token: int) -> void:
	player.call("_end_module_action", token, "fixture")
	await physics_frame


func _test_modules() -> void:
	await prepare()
	var token := lock()
	check(bool(player.call("begin_touch_action", "mobility")), "Late module input accepted into buffer")
	check(not bool(player.call("is_dash_active")), "Buffer respects ongoing cast")
	controls.call("advance_input_time", 0.08)
	await unlock(token)
	controls.call("execute_buffered_command")
	check(bool(player.call("is_dash_active")) and int(player.call("get_pyro_charges")) == 1, "Buffered module executes once after release")
	controls.call("execute_buffered_command")
	check(int(player.call("get_pyro_charges")) == 1, "No duplicate activation")
	await prepare()
	token = lock()
	player.call("begin_touch_action", "mobility")
	controls.call("advance_input_time", 0.15)
	await unlock(token)
	controls.call("execute_buffered_command")
	check(not bool(player.call("is_dash_active")), "Old input expires")
	await prepare()
	token = lock()
	player.call("begin_touch_action", "mobility")
	player.call("cancel_touch_action", "mobility")
	await unlock(token)
	controls.call("execute_buffered_command")
	check(not bool(player.call("is_dash_active")), "Canceled touch cannot fire later")
	await prepare()
	token = lock()
	controls.call("request_module_command", "mobility")
	player.call("reset_desktop_inputs")
	await unlock(token)
	controls.call("execute_buffered_command")
	check(not bool(player.call("is_dash_active")), "Focus loss clears desktop buffer")
	await prepare()
	player.call("_start_module_cooldown", "counter", 0.10)
	player.call("begin_touch_action", "defensive")
	controls.call("advance_input_time", 0.10)
	player.call("_update_module_cooldowns", 0.10)
	controls.call("execute_buffered_command")
	check(str(player.call("get_action_owner")) == "counter", "Module accepts anticipation of cooldown end")
	await prepare()
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	await physics_frame
	player.call("begin_touch_action", "defensive")
	player.call("_update_dash", 0.5)
	controls.call("advance_input_time", 0.08)
	controls.call("execute_buffered_command")
	check(str(player.call("get_action_owner")) == "counter", "Guard can be anticipated during the end of a dash")
	await prepare()
	token = lock()
	player.call("begin_touch_action", "mobility")
	player.call("set_gameplay_enabled", false)
	player.call("set_gameplay_enabled", true)
	await physics_frame
	controls.call("execute_buffered_command")
	check(not bool(player.call("is_dash_active")), "Scene suspension discards pending input")
	await prepare()
	token = lock()
	player.call("begin_touch_action", "mobility")
	player.call("apply_stun", 0.05, "interruption")
	var state: RefCounted = player.get("combat_state")
	state.call("update", 0.06)
	await physics_frame
	controls.call("execute_buffered_command")
	check(not bool(player.call("is_dash_active")), "Accepted stun invalidates an older queued command")


func _test_weapons() -> void:
	for weapon in ["blaster", "shotgun", "longshot", "mekatana"]:
		await prepare(weapon)
		var token := lock()
		player.call("begin_touch_fire")
		check(bool(player.call("end_touch_fire", Vector2(1, 0))), weapon + ": late touch release retained")
		controls.call("advance_input_time", 0.06)
		await unlock(token)
		controls.call("execute_buffered_command")
		var started: bool = bool(player.get("_blaster_attack_busy")) if weapon == "blaster" else bool(player.get("_shotgun_attack_busy")) if weapon == "shotgun" else bool(player.get("_longshot_attack_busy")) if weapon == "longshot" else str(player.call("get_action_owner")) == "mekatana"
		check(started, weapon + ": buffered tap starts actual weapon action")
		player.call("set_gameplay_enabled", false)
		await create_timer(0.7).timeout
	await prepare()
	var token := lock()
	player.set("simulated_attack", true)
	player.call("_update_attack", true)
	player.set("simulated_attack", false)
	player.call("_update_attack", true)
	await unlock(token)
	controls.call("execute_buffered_command")
	check(bool(player.get("_blaster_attack_busy")), "Fresh desktop tap during recovery survives release")
	await prepare()
	player.set("simulated_attack", true)
	player.call("_update_attack")
	await physics_frame
	token = lock()
	player.call("_update_attack", true)
	player.set("simulated_attack", false)
	player.call("_update_attack", true)
	player.set("simulated_attack", true)
	player.call("_update_attack", true)
	await unlock(token)
	controls.call("execute_buffered_command")
	check(bool(player.call("is_blaster_charging")), "Release during cast rearms a genuinely new late press")
	player.set("simulated_attack", false)
	await prepare()
	player.set("_blaster_next_attack_ready_at", Time.get_ticks_msec() / 1000.0 + 0.06)
	player.call("begin_touch_fire")
	check(bool(player.get("_touch_fire_active")), "Contact can aim throughout weapon cooldown")
	player.call("end_touch_fire", Vector2(1, 0))
	player.call("_update_attack")
	check(not bool(player.get("_blaster_attack_busy")), "Touch shot obeys cooldown")
	await create_timer(0.08).timeout
	player.call("_update_attack")
	check(bool(player.get("_blaster_attack_busy")), "Touch release waits briefly for weapon cooldown")
	await prepare("shotgun")
	player.set("_shotgun_ammo", 1)
	player.call("_start_shotgun_reload")
	player.set("_shotgun_reload_remaining", 0.08)
	player.call("begin_touch_fire")
	player.call("end_touch_fire")
	player.call("_update_shotgun_reload", 0.09)
	controls.call("advance_input_time", 0.09)
	controls.call("execute_buffered_command")
	check(bool(player.get("_shotgun_attack_busy")), "Shotgun tap chains into reload completion")


func _test_charge_release() -> void:
	await prepare()
	var token := lock()
	check(bool(player.call("begin_touch_action", "offensive")), "Charge can be queued")
	player.call("end_touch_action", "offensive")
	await unlock(token)
	controls.call("execute_buffered_command")
	check(bool(player.get("_fulguro_release_requested")), "Deferred charge receives its already-released finger")
	player.call("_cancel_fulguro_attack")
	await prepare()
	player.call("_begin_fulguro_charge")
	player.call("_release_fulguro_charge")
	player.call("_update_fulguro_attack", 0.5)
	player.call("_update_fulguro_attack", 0.5)
	await physics_frame
	var recovery: float = player.get("_fulguro_recovery")
	player.set("_fulguro_elapsed", maxf(0.0, recovery - 0.08))
	check(bool(player.call("begin_touch_action", "mobility")), "Dash accepted near actual Fulguro recovery end")
	controls.call("advance_input_time", 0.09)
	player.call("_update_fulguro_attack", 0.09)
	controls.call("execute_buffered_command")
	check(bool(player.call("is_dash_active")), "Dash starts in the same update that releases Fulguro")
	await prepare()
	player.call("apply_stun", 0.05, "first")
	var state: RefCounted = player.get("combat_state")
	state.call("update", 0.06)
	player.call("_begin_fulguro_charge")
	player.call("apply_stun", 0.5, "repeat")
	check(bool(player.call("is_fulguro_charging")), "Ignored stun during grace cannot interrupt an action")


func _test_stun_recovery() -> void:
	var state := STATE.new()
	state.apply_stun(0.75, "first")
	check(is_equal_approx(state.get_remaining("STUN"), 0.75), "First stun retains exact duration")
	for step in range(24):
		state.update(0.05)
		state.apply_stun(0.75, "spam")
	check(state.get_remaining("STUN") < 0.01, "Repeated stun cannot sustain continuous lock")
	state.reset()
	state.apply_stun(0.75)
	state.update(0.76)
	state.apply_stun(0.75)
	check(not state.is_stunned(), "Recovery grace leaves a response window")
	state.update(0.18)
	state.apply_stun(0.75)
	check(is_equal_approx(state.get_remaining("STUN"), 0.375), "Second nearby stun has diminishing duration")
	state.update(3.0)
	state.apply_stun(0.75)
	check(is_equal_approx(state.get_remaining("STUN"), 0.75), "Resistance wears off")
	state.reset()
	state.apply_stun(0.75)
	check(is_equal_approx(state.get_remaining("STUN"), 0.75), "Round reset clears resistance")
	var host := NETWORK_STATE.new()
	var client := NETWORK_STATE.new()
	client.authoritative = false
	host.apply_stun(0.5)
	host.update(0.51)
	client.receive_snapshot(host.snapshot())
	check(not client.can_receive_stun(0.5), "Network snapshot preserves recovery protection")


func _test_dash(scene: Node3D) -> void:
	await prepare()
	var wall := StaticBody3D.new()
	wall.position = Vector3(1.5, 0.8, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3, 20)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	await physics_frame
	player.call("_perform_pyro_boots", Vector3(1, 0, -1).normalized())
	player.call("_update_dash", 0.09)
	check(bool(player.call("is_dash_active")), "Oblique wall contact continues dash")
	player.call("_update_dash", 0.5)
	check(player.global_position.x < 1.4 and player.global_position.z < -3.0, "Dash slides along wall without crossing it")
	check(player.global_position.length() <= 5.01, "Sliding never adds dash distance")
	await prepare()
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	player.call("_update_dash", 0.5)
	check(not bool(player.call("is_dash_active")) and player.global_position.x < 1.4, "Frontal collision stops before the wall")
	wall.queue_free()
	await physics_frame
	await prepare()
	player.call("_perform_pyro_boots", Vector3.RIGHT)
	player.call("_update_dash", 0.5)
	check(absf(player.global_position.x - 5.0) < 0.02, "Unobstructed dash retains its distance")


func _test_camera(scene: Node3D) -> void:
	var camera := CAMERA.new()
	scene.add_child(camera)
	camera.set_process(false)
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3.RIGHT)
	camera.set_target(player)
	camera.set_follow_offset(Vector3.ZERO, true)
	player.set("aim_direction", Vector3.LEFT)
	var before := camera.global_position
	camera._process(1.0 / 60.0)
	check(camera.global_position.distance_to(before) <= camera.max_aim_pan_speed / 60.0 + 0.001, "Aim reversal has bounded camera speed")
	player.global_position = Vector3(5, 0, 0)
	for frame in range(60):
		camera._process(1.0 / 60.0)
	check(absf(camera._follow_position.x - 5.0) < 0.01, "Camera quickly follows body independently of aim")
	camera.shake(0.1, 0.2)
	for frame in range(90):
		camera._process(1.0 / 60.0)
	check(camera.global_position.distance_to(camera._follow_position + camera._aim_offset) < 0.001, "Shake leaves no accumulated drift")
	camera.queue_free()


func _test_network_buffer(scene: Node3D) -> void:
	var actor: Node3D = load("res://scripts/network_player.gd").new()
	actor.position = Vector3(20, 0, 20)
	scene.add_child(actor)
	await process_frame
	actor.set_physics_process(false)
	actor.call("set_gameplay_enabled", true)
	var recorder := ActionRecorder.new()
	scene.add_child(recorder)
	actor.set("controller", recorder)
	var actor_controls: Node = actor.get("_controls_component")
	var token: int = actor.call("_try_begin_module_action", "fixture")
	actor.call("begin_touch_fire")
	check(not recorder.actions.has("contact"), "Network sends no rejected contact before the buffer executes")
	actor.call("_end_module_action", token, "fixture")
	await physics_frame
	actor_controls.call("execute_buffered_command")
	check(recorder.actions.count("contact") == 1 and bool(actor.get("_touch_fire_active")), "Deferred held contact uses the network actor API exactly once")
	actor.call("set_gameplay_enabled", false)
	actor.queue_free()
	recorder.queue_free()
	await process_frame
