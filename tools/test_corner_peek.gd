extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const NETWORK_PLAYER := preload("res://scripts/network_player.gd")
const STEP := 1.0 / 60.0
var stage: Node3D
var player: Node3D
var wall: StaticBody3D
var failures: Array[String] = []
var checks := 0


class DamageProbe extends StaticBody3D:
	var damage := 0.0
	func take_damage(amount: float, _source: String = "", _attack: String = "") -> float:
		damage += amount
		return amount
	func get_health() -> float:
		return 10000.0 - damage
	func flash_impact(_enhanced: bool = false) -> void:
		pass


func _initialize() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	call_deferred("_run")


func _run() -> void:
	player = PLAYER.new()
	player.name = "Player"
	stage.add_child(player)
	await process_frame
	player.set_physics_process(false)
	var rig: PlayerVisualRig = player._visual_rig
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	wall = _box(Vector3(4.0, 3.0, 1.0), Vector3(-2.18, 1.5, -1.25))
	await physics_frame
	for weapon in ["blaster", "shotgun", "longshot"]:
		player.set_weapon(weapon)
		player.global_position = Vector3(-0.28, 0.0, 0.0)
		player.aim_direction = Vector3.FORWARD
		player._begin_weapon_aim()
		rig.set_aim_enabled(true, true)
		player._corner_peek.reset()
		await _step(0.0)
		var muzzle: Node3D = rig.get_weapon_muzzle(StringName(weapon))
		var neutral_muzzle := muzzle.global_position
		var neutral_hand := rig.aim_modifier.last_right_hand_world.origin
		var feet := _feet(rig)
		await _frames(18)
		var state: Dictionary = player.get_corner_peek_state()
		print("[Corner] %s offset=%s muzzle_delta=%s support=%s" % [weapon, state.offset, muzzle.global_position - neutral_muzzle, player._projectile_support_origin()])
		_check(float(state.side) == 1.0 and (state.offset as Vector3).x >= 0.24, weapon + " opens the right edge")
		_check(player.global_position.is_equal_approx(Vector3(-0.28, 0.0, 0.0)), weapon + " keeps the body position")
		_check((muzzle.global_position - neutral_muzzle).distance_to(state.offset) < 0.03, weapon + " muzzle follows the upper-body offset and roll")
		_check((rig.aim_modifier.last_right_hand_world.origin - neutral_hand).distance_to(state.offset) < 0.002, weapon + " firing hand follows the exact offset")
		_check(not rig.aim_modifier.left_grip_reachable or rig.aim_modifier.left_grip_error < 0.001, weapon + " support hand stays on its grip")
		_check(_feet(rig).distance_to(feet) < 0.002, weapon + " keeps the feet planted")
		_check(rig.get_weapon_forward_direction(StringName(weapon)).dot(Vector3.FORWARD) > 0.9999, weapon + " keeps the barrel aligned")
		var support: Vector3 = player._projectile_support_origin()
		_check(support.x > -0.05, weapon + " validates a shoulder route around the edge")
		_check(player._safe_projectile_origin(muzzle.global_position).distance_to(muzzle.global_position) < 0.001, weapon + " emits from the opened muzzle")
		if weapon == "longshot":
			_check(player._spawn_longshot_projectile(false, 1), "longshot emits at the corner")
			var projectile := stage.get_node_or_null("LongshotProjectile")
			_check(projectile != null and not projectile._finished, "longshot muzzle guard accepts the real route around cover")
			if projectile != null:
				projectile.queue_free()
		player.global_position = Vector3(-0.28, 0.0, 0.55)
		await _frames(14)
		_check(not player.get_corner_peek_state().active, weapon + " returns to neutral away from cover")
	# Mirror the same geometry; the selected side must follow the open edge.
	wall.position.x = 2.18
	player.global_position = Vector3(0.28, 0.0, 0.0)
	await physics_frame
	player._corner_peek.reset()
	await _frames(18)
	_check(player.get_corner_peek_state().side == -1.0, "left corner mirrors the pose")
	var left_muzzle: Vector3 = rig.get_weapon_muzzle(&"longshot").global_position
	_check(player._safe_projectile_origin(left_muzzle).distance_to(left_muzzle) < 0.001, "left corner exposes the whole barrel")
	_check(player._spawn_longshot_projectile(false, 2), "longshot emits at the left corner")
	var left_projectile := stage.get_node_or_null("LongshotProjectile")
	_check(left_projectile != null and not left_projectile._finished, "left corner preserves the projectile diameter")
	if left_projectile != null:
		left_projectile.queue_free()
	# No escape across a broad wall, even when the visual barrel reaches through.
	wall.position.x = 0.0
	player.global_position = Vector3.ZERO
	await physics_frame
	player._corner_peek.reset()
	await _frames(18)
	_check(not player.get_corner_peek_state().active, "wide wall has no opening")
	_check(player._safe_projectile_origin(Vector3(0.0, 0.9, -2.0)).is_equal_approx(Vector3(0.0, 0.9, 0.0)), "closed wall still blocks barrel clipping")
	# Obstacles on the lateral leg cannot be skipped by a bent firing route.
	wall.position.x = -2.18
	player.global_position = Vector3(-0.28, 0.0, 0.0)
	await physics_frame
	player._corner_peek.reset()
	await _frames(18)
	var side_obstacle := _box(Vector3(0.08, 2.0, 0.30), Vector3(-0.02, 1.0, 0.0))
	await physics_frame
	_check(player._projectile_support_origin().is_equal_approx(player.global_position + Vector3.UP * 0.9), "new obstacle blocks the lateral route before emission")
	await _step()
	_check(not player.get_corner_peek_state().active, "moving cover cancels an unsafe lean")
	side_obstacle.queue_free()
	await physics_frame
	await _frames(18)
	player.set_weapon("mekatana")
	await _step()
	_check(not player.get_corner_peek_state().active and rig.aim_modifier.corner_offset.is_zero_approx(), "melee weapon disables corner opening")
	player.set_weapon("blaster")
	player._begin_weapon_aim()
	rig.set_aim_enabled(true, true)
	await _frames(18)
	var module_token: int = player._action_gate.try_acquire(player.ACTION_GATE.Kind.MODULE, "rocket_basket", -1, true)
	await _step()
	_check(not player.get_corner_peek_state().active, "module actions cannot use corner opening")
	player._action_gate.release(module_token)
	await _frames(18)
	player._shotgun_reloading = true
	await _step()
	_check(not player.get_corner_peek_state().active, "reload clears the corner pose")
	player._shotgun_reloading = false
	await _frames(18)
	player.global_position += Vector3.RIGHT * 5.0
	await _step()
	_check(not player.get_corner_peek_state().active, "teleport clears the old corner")
	player.global_position = Vector3(-0.28, 0.0, 0.0)
	player._corner_peek.reset()
	await _frames(18)
	player.set_gameplay_enabled(false)
	player._physics_process(STEP)
	_check(not player.get_corner_peek_state().active and rig.aim_modifier.corner_offset.is_zero_approx(), "round stop clears the pose")
	# A host's remote actor uses the same world geometry and weapon pose.
	var remote := NETWORK_PLAYER.new()
	remote.name = "RemotePlayer"
	remote.remote_controlled = true
	stage.add_child(remote)
	remote.set_physics_process(false)
	remote.global_position = Vector3(-0.28, 0.0, 0.0)
	remote._begin_weapon_aim()
	remote._corner_peek.reset()
	for frame in range(18):
		remote._corner_peek.update(STEP)
	_check(remote.get_corner_peek_state().side == 1.0, "network remote actor detects the same corner")
	remote.queue_free()
	await _test_live_touch_fire()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()
	print("CORNER PEEK: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	current_scene = null
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _test_live_touch_fire() -> void:
	player.set_gameplay_enabled(true)
	player.set_weapon("blaster")
	player.reset_combat_state()
	player.global_position = Vector3(-0.28, 0.0, 0.0)
	player.aim_direction = Vector3.FORWARD
	player._corner_peek.reset()
	var rig: PlayerVisualRig = player._visual_rig
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	player.set_physics_process(true)
	player.set_touch_aim_vector(Vector2(0.0, -1.0))
	player.begin_touch_fire()
	for frame in range(20):
		await physics_frame
		await process_frame
	_check(player.is_blaster_charging(), "live touch starts an accepted aim")
	_check(player.get_corner_peek_state().side == 1.0, "production physics opens the corner while touch is held")
	var muzzle: Vector3 = player._blaster_muzzle.global_position
	var probe := DamageProbe.new()
	probe.collision_layer = 2
	probe.collision_mask = 0
	probe.position = Vector3(muzzle.x, 0.9, -4.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.40, 1.5, 0.40)
	collision.shape = shape
	probe.add_child(collision)
	stage.add_child(probe)
	await physics_frame
	await process_frame
	_check(player.end_touch_fire(Vector2(0.0, -1.0)), "live touch releases a real shot")
	for frame in range(20):
		await physics_frame
		await process_frame
	_check(probe.damage > 0.0, "real blaster projectile damages the target beyond the open edge")
	player.set_physics_process(false)
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	probe.queue_free()
	player.set_gameplay_enabled(false)
	await create_timer(0.35).timeout


func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#536573")
	visual.material_override = material
	body.add_child(visual)
	stage.add_child(body)
	return body


func _step(delta: float = STEP) -> void:
	await process_frame
	var rig: PlayerVisualRig = player._visual_rig
	rig.update_visual_state(Vector3.ZERO, player.aim_direction, 0.0, player.move_speed, delta)
	player._corner_peek.update(delta)
	rig.animation_tree.advance(STEP)
	rig.skeleton.advance(STEP)
	await rig.skeleton.skeleton_updated


func _frames(count: int) -> void:
	for frame in range(count):
		await _step()


func _feet(rig: PlayerVisualRig) -> Vector3:
	var index := rig.skeleton.find_bone("mixamorig_LeftFoot")
	if index < 0:
		for bone in range(rig.skeleton.get_bone_count()):
			if rig.skeleton.get_bone_name(bone).to_lower().ends_with("leftfoot"):
				index = bone
				break
	return (rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(index)).origin if index >= 0 else Vector3.ZERO


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)


func _capture() -> void:
	player.set_gameplay_enabled(true)
	player.global_position = Vector3(-0.28, 0.0, 0.0)
	player.set_weapon("blaster")
	player._begin_weapon_aim()
	player._visual_rig.set_aim_enabled(true, true)
	player._corner_peek.reset()
	_box(Vector3(8.0, 0.1, 8.0), Vector3(0.0, -0.06, 0.0))
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.global_position = Vector3(3.2, 3.5, 4.5)
	camera.look_at(Vector3(-0.2, 1.0, -0.6))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	stage.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#1c2731")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	DirAccess.make_dir_recursive_absolute("res://captures/corner-peek")
	await _step(0.0)
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://captures/corner-peek/neutral.png")
	await _frames(18)
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://captures/corner-peek/right-corner.png")
