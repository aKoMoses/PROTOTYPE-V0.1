extends SceneTree

const GUIDE := preload("res://scripts/weapon_aim_guide.gd")
var _stage: Node3D
var _actor: PreviewActor
var _guide: Node3D
var _checks := 0
var _failures: Array[String] = []


class PreviewActor extends CharacterBody3D:
	var preview: Dictionary = {}
	func get_weapon_aim_preview() -> Dictionary:
		return preview


class ConcealedTarget extends StaticBody3D:
	func is_visible_to(_observer: Node3D) -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	current_scene = _stage
	var camera := Camera3D.new()
	_stage.add_child(camera)
	camera.position = Vector3(9, 15, 16)
	camera.look_at(Vector3(0, 1, -6))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	camera.make_current()
	_actor = PreviewActor.new()
	_stage.add_child(_actor)
	_guide = GUIDE.new()
	_actor.add_child(_guide)
	_guide.set_process(false)
	_actor.preview = {"origin": Vector3(0, 1, 0), "direction": Vector3.FORWARD,
		"range": 14.0, "radius": 0.0, "mask": 1 | 2 | 8, "exclude": [_actor.get_rid()],
		"support": Vector3(0, 1, 0.7), "weapon": "blaster"}
	await physics_frame
	await process_frame
	_guide.refresh()
	_check(_guide.visible, "blaster guide visible")
	_check(_guide.endpoint.is_equal_approx(Vector3(0, 1, -14)), "blaster uses its range")
	_check(not _guide.has_contact, "empty lane has no contact")
	var wall := _body(StaticBody3D.new(), Vector3(0, 1, -5), Vector3(3, 2, 0.2), 1)
	await physics_frame
	await process_frame
	_guide.refresh()
	_check(_guide.has_contact and absf(_guide.endpoint.z + 4.9) < 0.02, "ray stops at first wall surface")
	_actor.preview["exclude"] = [_actor.get_rid(), wall.get_rid()]
	_guide.refresh()
	_check(not _guide.has_contact, "own collision exclusions respected")
	wall.queue_free()
	await process_frame
	_actor.preview["exclude"] = [_actor.get_rid()]
	var hidden := _body(ConcealedTarget.new(), Vector3(0, 1, -3), Vector3(1, 2, 0.5), 2)
	await physics_frame
	await process_frame
	_guide.refresh()
	_check(not _guide.has_contact and _guide.endpoint.z < -13.9, "concealed actor cannot be found with guide")
	hidden.queue_free()
	await process_frame
	var field := Area3D.new()
	field.monitoring = false
	_body(field, Vector3(0, 1, -4), Vector3(3, 2, 0.1), 8)
	await physics_frame
	await process_frame
	_guide.refresh()
	_check(_guide.has_contact and absf(_guide.endpoint.z + 3.95) < 0.02, "energy area blocks preview")
	field.queue_free()
	await process_frame
	_actor.preview["weapon"] = "longshot"
	_actor.preview["range"] = 32.0
	_actor.preview["radius"] = 0.075
	_actor.preview["mask"] = 1 | 2 | 4 | 8
	_guide.refresh()
	_check(_guide.endpoint.is_equal_approx(Vector3(0, 1, -32)), "sniper uses its longer range")
	var edge := _body(StaticBody3D.new(), Vector3(0.12, 1, -5), Vector3(0.10, 2, 0.3), 1)
	await physics_frame
	await process_frame
	_actor.preview["radius"] = 0.0
	_guide.refresh()
	_check(not _guide.has_contact, "thin ray misses offset edge")
	_actor.preview["radius"] = 0.075
	_guide.refresh()
	_check(_guide.has_contact, "sniper sphere catches offset edge")
	_actor.preview["radius"] = 0.1125
	_guide.refresh()
	_check(_guide.has_contact, "enhanced sniper radius respected")
	edge.queue_free()
	await process_frame
	var guard := _body(StaticBody3D.new(), Vector3(0, 1, 0.3), Vector3(2, 2, 0.1), 1)
	await physics_frame
	await process_frame
	_guide.refresh()
	_check(_guide.has_contact and _guide.endpoint.z > 0.2, "sniper barrel obstruction prevents clear shot preview")
	guard.queue_free()
	await process_frame
	var overlap := _body(StaticBody3D.new(), Vector3(0, 1, 0), Vector3(1, 2, 1), 1)
	await physics_frame
	await process_frame
	_guide.refresh()
	_check(_guide.has_contact, "sniper detects initial overlap")
	overlap.queue_free()
	await process_frame
	_actor.preview["origin"] = Vector3(2, 1, 0)
	_actor.preview["support"] = Vector3(2, 1, 0.7)
	_actor.preview["direction"] = Vector3.LEFT
	_guide.refresh()
	_check(_guide.endpoint.is_equal_approx(Vector3(-30, 1, 0)), "turning follows input direction")
	_actor.preview = {}
	_guide.refresh()
	_check(not _guide.visible, "inactive weapon, remote actor or disabled combat hides guide")
	_check(get_nodes_in_group("prototype0_gameplay_projectiles").is_empty(), "preview creates no gameplay projectiles")
	await _check_player_integration()
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture()
	print("WEAPON AIM GUIDE: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _body(body: CollisionObject3D, at: Vector3, size: Vector3, layer: int) -> CollisionObject3D:
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	_stage.add_child(body)
	(body as Node3D).global_position = at
	return body


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)


func _check_player_integration() -> void:
	var player := load("res://scripts/player.gd").new() as CharacterBody3D
	_stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	var guide := player.get_node("WeaponAimGuide") as Node3D
	guide.set_process(false)
	_check_fire_input_visibility(player, guide)
	await _check_held_fire_pose(player, guide)
	player.call("set_weapon", "blaster")
	player.call("begin_touch_fire")
	player.call("_set_aim_direction", Vector3.RIGHT)
	player.call("_begin_weapon_fire")
	await process_frame
	await process_frame
	var preview: Dictionary = player.call("get_weapon_aim_preview")
	_check(preview["direction"].is_equal_approx(Vector3.RIGHT), "player exposes actual blaster aim")
	_check(preview["origin"].is_equal_approx(player.get("_blaster_muzzle").global_position), "blaster preview starts at actual muzzle")
	guide.refresh()
	_check(guide.visible and absf(guide.origin.distance_to(guide.endpoint) - float(preview["range"])) < 0.01, "production player draws blaster guide")
	player.call("set_weapon", "longshot")
	player.call("begin_touch_fire")
	player.call("_begin_weapon_fire")
	await process_frame
	await process_frame
	preview = player.call("get_weapon_aim_preview")
	_check(preview["origin"].is_equal_approx(player.get("_longshot_muzzle").global_position), "sniper preview starts at actual muzzle")
	player.call("_spawn_longshot_projectile", false, 1)
	var projectile: Node3D
	for shot in get_nodes_in_group("prototype0_gameplay_projectiles"):
		if shot.get_script() == player.LONGSHOT_PROJECTILE:
			projectile = shot
	if projectile != null:
		projectile.set_physics_process(false)
		_check(projectile.get("_origin").is_equal_approx(preview["origin"]), "sniper shot and preview share origin")
		_check(projectile.get("_direction").is_equal_approx(preview["direction"]), "sniper shot and preview share direction")
		_check(is_equal_approx(float(projectile.get("_radius")), float(preview["radius"])), "sniper shot and preview share radius")
		projectile.queue_free()
	else:
		_check(false, "production sniper projectile missing")
	player.call("set_weapon", "shotgun")
	guide.refresh()
	_check(not guide.visible, "shotgun has no long range guide")
	player.call("set_weapon", "mekatana")
	guide.refresh()
	_check(not guide.visible, "melee weapon has no long range guide")
	player.call("set_weapon", "blaster")
	player.call("set_gameplay_enabled", false)
	guide.refresh()
	_check(not guide.visible, "disabled gameplay hides production guide")
	player.call("set_gameplay_enabled", true)
	player.call("begin_touch_fire")
	player.set("_stasis_remaining", 1.0)
	_check((player.call("get_weapon_aim_preview") as Dictionary).is_empty(), "stasis hides production guide")
	player.set("_stasis_remaining", 0.0)
	player.get("passive_state").real_dead = true
	_check((player.call("get_weapon_aim_preview") as Dictionary).is_empty(), "elimination hides production guide")
	player.queue_free()
	var remote := load("res://scripts/network_player.gd").new() as CharacterBody3D
	remote.set("remote_controlled", true)
	_stage.add_child(remote)
	remote.set_physics_process(false)
	_check((remote.call("get_weapon_aim_preview") as Dictionary).is_empty(), "opponent never displays a local aiming guide")
	remote.queue_free()
	await process_frame


func _check_fire_input_visibility(player: Node, guide: Node3D) -> void:
	for weapon in ["blaster", "longshot"]:
		player.call("set_weapon", weapon)
		player.call("set_touch_move_vector", Vector2.RIGHT)
		player.call("set_touch_aim_vector", Vector2.UP)
		guide.refresh()
		_check(not guide.visible, "%s: movement and aim alone hide guide" % weapon)
		_mouse(player, true, 0, false)
		guide.refresh()
		_check(not guide.visible, "%s: GUI mouse press hides guide" % weapon)
		_mouse(player, false, 0, false)
		_mouse(player, true, InputEvent.DEVICE_ID_EMULATION, true)
		guide.refresh()
		_check(not guide.visible, "%s: movement mouse emulation hides guide" % weapon)
		_mouse(player, false, InputEvent.DEVICE_ID_EMULATION, false)
		_mouse(player, true, 0, true)
		guide.refresh()
		_check(guide.visible, "%s: accepted held mouse shows guide" % weapon)
		player.set("_desktop_attack_rearm_required", true)
		guide.refresh()
		_check(not guide.visible, "%s: interrupted mouse hold hides guide" % weapon)
		player.set("_desktop_attack_rearm_required", false)
		_mouse(player, false, 0, false)
		player.call("_begin_aim_hold")
		guide.refresh()
		_check(not guide.visible, "%s: mouse release hides guide despite aim pose" % weapon)
		player.call("begin_touch_fire")
		guide.refresh()
		_check(guide.visible, "%s: active attack joystick shows guide" % weapon)
		player.set("_touch_attack_rearm_required", true)
		guide.refresh()
		_check(not guide.visible, "%s: interrupted joystick hides guide" % weapon)
		player.set("_touch_attack_rearm_required", false)
		player.call("end_touch_fire")
		guide.refresh()
		_check(not guide.visible, "%s: joystick release hides guide immediately" % weapon)
		player.call("clear_touch_inputs")
		player.call("begin_touch_fire")
		player.call("cancel_touch_fire")
		guide.refresh()
		_check(not guide.visible, "%s: canceled touch hides guide" % weapon)
		player.call("clear_touch_inputs")


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


func _check_held_fire_pose(player: Node3D, guide: Node3D) -> void:
	var rig := player.get_node("VisualRoot") as PlayerVisualRig
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	# BoneAttachment transforms are final during skeleton_updated; Godot restores
	# unmodified bone poses after the modifier pass.
	var final_barrel := {"direction": Vector3.FORWARD}
	var capture_barrel := func() -> void:
		final_barrel.direction = rig.get_weapon_forward_direction(StringName(player.get("_weapon_id")))
	rig.skeleton.skeleton_updated.connect(capture_barrel)
	var keyboard := InputEventKey.new()
	keyboard.keycode = KEY_SPACE
	for weapon in ["longshot", "blaster", "shotgun"]:
		for source in ["keyboard", "mouse", "touch"]:
			player.call("set_weapon", weapon)
			player.call("clear_touch_inputs")
			player.set("_desktop_attack_rearm_required", false)
			if source == "keyboard":
				keyboard.pressed = true
				Input.parse_input_event(keyboard.duplicate())
				Input.flush_buffered_events()
			elif source == "mouse":
				_mouse(player, true, 0, true)
			else:
				player.call("set_touch_attack_held", true)
			player.call("_set_aim_direction", Vector3.RIGHT)
			player.call("_begin_weapon_fire")
			var kept_aim := true
			var max_guide_error := 0.0
			var max_barrel_error := 0.0
			# Exercise the complete fire/hold/idle transitions beyond the Longshot
			# cooldown, then fire again while changing direction during recovery.
			for frame in range(150):
				await process_frame
				var direction := Vector3.RIGHT if frame < 80 else Vector3.LEFT
				player.call("_set_aim_direction", direction)
				if frame == 90:
					player.call("_begin_weapon_fire")
				player.call("_update_weapon_pose_state", 1.0 / 60.0)
				player.call("_update_robot_motion", 1.0 / 60.0)
				rig.animation_tree.advance(1.0 / 60.0)
				rig.skeleton.advance(1.0 / 60.0)
				await rig.skeleton.skeleton_updated
				kept_aim = kept_aim and bool(player.call("_weapon_pose_uses_aim"))
				max_barrel_error = maxf(max_barrel_error, rad_to_deg((final_barrel.direction as Vector3).angle_to(direction)))
				if weapon in ["longshot", "blaster"]:
					guide.refresh()
					kept_aim = kept_aim and guide.visible
					var preview: Dictionary = player.call("get_weapon_aim_preview")
					if not preview.is_empty():
						max_guide_error = maxf(max_guide_error, rad_to_deg((preview.direction as Vector3).angle_to(direction)))
			_check(kept_aim, "%s %s: held fire keeps aim between shots" % [weapon, source])
			_check(max_barrel_error < 0.1, "%s %s: barrel follows changing aim (%.3f deg)" % [weapon, source, max_barrel_error])
			_check(max_guide_error < 0.1, "%s %s: guide follows changing aim (%.3f deg)" % [weapon, source, max_guide_error])
			if source == "keyboard":
				keyboard.pressed = false
				Input.parse_input_event(keyboard.duplicate())
				Input.flush_buffered_events()
			elif source == "mouse":
				_mouse(player, false, 0, false)
			else:
				player.call("set_touch_attack_held", false)
			guide.refresh()
			_check(not guide.visible, "%s %s: release hides guide immediately" % [weapon, source])
			player.call("_update_weapon_pose_state", 1.0)
			_check(not bool(player.call("_weapon_pose_uses_aim")), "%s %s: release allows aim to expire" % [weapon, source])
			# An interrupted hold still down must not keep the pose raised.
			if source == "keyboard":
				keyboard.pressed = true
				Input.parse_input_event(keyboard.duplicate())
				Input.flush_buffered_events()
			elif source == "mouse":
				_mouse(player, true, 0, true)
			else:
				player.call("set_touch_attack_held", true)
			player.call("_begin_aim_hold")
			player.set("_desktop_attack_rearm_required", true)
			player.set("_touch_attack_rearm_required", true)
			player.call("_update_weapon_pose_state", 1.0)
			_check(not bool(player.call("_weapon_pose_uses_aim")), "%s %s: blocked input does not preserve aim" % [weapon, source])
			keyboard.pressed = false
			Input.parse_input_event(keyboard.duplicate())
			Input.flush_buffered_events()
			_mouse(player, false, 0, false)
			player.call("clear_touch_inputs")
	rig.skeleton.skeleton_updated.disconnect(capture_barrel)
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	player.call("clear_touch_inputs")
	player.call("reset_desktop_inputs")


func _capture() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#182832")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.9
	_stage.add_child(environment)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 36)
	floor.mesh = plane
	floor.position.z = -8
	_stage.add_child(floor)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#384b52")
	floor.material_override = material
	var obstacle := _body(StaticBody3D.new(), Vector3(0, 1, -9), Vector3(3, 2, 0.3), 1)
	var box_visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3, 2, 0.3)
	box_visual.mesh = box
	obstacle.add_child(box_visual)
	var player := load("res://scripts/player.gd").new() as CharacterBody3D
	_stage.add_child(player)
	player.set_physics_process(false)
	player.get_node("WorldUIAnchor").hide()
	player.call("_set_aim_direction", Vector3.FORWARD)
	player.call("_update_robot_motion", 1.0)
	player.call("_begin_weapon_fire")
	player.call("begin_touch_fire")
	var guide := player.get_node("WeaponAimGuide") as Node3D
	guide.set_process(false)
	await physics_frame
	await process_frame
	await process_frame
	guide.refresh()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures/weapon-aim-guide")
	root.get_texture().get_image().save_png("res://captures/weapon-aim-guide/blocked.png")
	player.call("set_weapon", "longshot")
	player.call("begin_touch_fire")
	player.call("_set_aim_direction", Vector3(-0.45, 0, -1).normalized())
	player.call("_update_robot_motion", 1.0)
	player.call("_begin_weapon_fire")
	await process_frame
	await process_frame
	guide.refresh()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/weapon-aim-guide/clear.png")
