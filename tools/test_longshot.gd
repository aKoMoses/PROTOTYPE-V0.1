extends SceneTree

const DATA := preload("res://scripts/combat_data.gd")
const STATE := preload("res://scripts/longshot_state.gd")

var _player: RecordingPlayer
var _probe: DamageProbe
var _failures: Array[String] = []
var _checks := 0
var _legacy_projectiles := 0


class RecordingPlayer extends "res://scripts/player.gd":
	var emissions: Array[Dictionary] = []
	var impacts: Array[Dictionary] = []
	var fixture_velocity := Vector3.ZERO

	func _get_actual_move_velocity() -> Vector3:
		return fixture_velocity

	func _on_longshot_emitted(enhanced: bool, shot_number: int) -> void:
		var projectile: Node3D
		for candidate in get_tree().get_nodes_in_group("prototype0_gameplay_projectiles"):
			if candidate.get_script() == LONGSHOT_PROJECTILE and int(candidate.get_meta("ai_projectile_source", -1)) == get_instance_id():
				projectile = candidate
		if projectile == null:
			emissions.append({"enhanced": enhanced, "rank": shot_number, "missing": true})
			return
		emissions.append({"enhanced": enhanced, "rank": shot_number, "missing": false,
			"origin": projectile.get("_origin"), "direction": projectile.get("_direction"),
			"speed": projectile.get("_speed"), "radius": projectile.get("_radius"),
			"muzzle": _longshot_muzzle.global_position,
			"model_forward": _visual_rig.get_weapon_forward_direction(&"longshot")})

	func _on_longshot_projectile_finished(hit: Dictionary, distance: float, definition: Dictionary, enhanced: bool, shot_id: String, visual_only: bool = false, passive_attack: Dictionary = {}) -> void:
		impacts.append({"hit": hit, "distance": distance, "enhanced": enhanced, "shot_id": shot_id})
		super._on_longshot_projectile_finished(hit, distance, definition, enhanced, shot_id, visual_only, passive_attack)


class DamageProbe extends StaticBody3D:
	var total_damage := 0.0
	var hit_count := 0
	var attack_ids: Dictionary = {}
	var status_applications := 0

	func take_damage(amount: float, _source: String = "", attack_id: String = "") -> float:
		if attack_ids.has(attack_id):
			return 0.0
		attack_ids[attack_id] = true
		total_damage += amount
		hit_count += 1
		return amount

	func flash_impact(_enhanced: bool = false) -> void:
		pass

	func get_health() -> float:
		return 10000.0 - total_damage

	func apply_burn(_duration: float, _damage_per_second: float, _source: String = "") -> void:
		status_applications += 1

	func clear_damage() -> void:
		total_damage = 0.0
		hit_count = 0
		attack_ids.clear()
		status_applications = 0


func _initialize() -> void:
	var stage := Node3D.new()
	stage.name = "LongshotPlayerFixture"
	root.add_child(stage)
	current_scene = stage
	call_deferred("_run")


func _run() -> void:
	_player = RecordingPlayer.new()
	_player.name = "Player"
	current_scene.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.apply_loadout(_loadout())
	_probe = DamageProbe.new()
	_probe.name = "LongshotDamageProbe"
	_probe.collision_layer = 2
	_probe.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 3.0, 0.2)
	collision.shape = box
	_probe.add_child(collision)
	current_scene.add_child(_probe)
	_probe.position = Vector3(100, 1.5, 100)
	physics_frame.connect(_animate_fixture)
	node_added.connect(_observe_added_node)
	await _settle()
	_check(_player._visual_rig.skeleton != null and _player._longshot_visual.find_child("LongshotGLB", true, false) != null, "real skeletal player carries the imported LONGSHOT")
	await _test_damage_and_flight()
	await _test_emitted_cycle()
	await _test_rejections_and_cancellation()
	await _test_instance_lifecycle()
	await _test_mouse_hold_release()
	await _test_touch_hold_release()
	await _test_moving_aim_and_recoil()
	await _test_survival_upgrade()
	_mouse(false)
	_player.clear_touch_inputs()
	physics_frame.disconnect(_animate_fixture)
	node_added.disconnect(_observe_added_node)
	await _clear_projectiles()
	current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in _failures:
		push_error("LONGSHOT PLAYER: " + failure)
	print("LONGSHOT PLAYER TEST: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_damage_and_flight() -> void:
	var previous_damage := -1.0
	for distance in [3.0, 12.0, 22.0, 30.0]:
		await _reset_fixture()
		var shot := await _fire()
		if bool(shot.get("missing", true)):
			continue
		var origin: Vector3 = shot.origin
		var direction: Vector3 = shot.direction
		# Move both actors after actual emission. The target is still on the live
		# path, so the impact must use its new position, never the original aim.
		_probe.position = origin + direction * (distance + 0.1)
		_player.position = Vector3(60, 0, 60)
		await create_timer(0.65).timeout
		_check(_probe.hit_count == 1, "live shot hits the relocated target exactly once at %.0f m" % distance)
		var impact := _last_hit_on(_probe)
		_check(not impact.is_empty(), "physical impact recorded at %.0f m" % distance)
		if impact.is_empty():
			continue
		_check(absf(float(impact.distance) - distance) < 0.01, "damage distance uses exact impact from old muzzle at %.0f m" % distance)
		var expected: float = STATE.damage_at_distance(distance, false)
		_check(absf(_probe.total_damage - expected) < 0.03, "absolute normal damage %.2f at %.0f m" % [expected, distance])
		_check(_probe.total_damage >= previous_damage, "damage progression is monotonic")
		previous_damage = _probe.total_damage
	_check(is_equal_approx(previous_damage, 81.0), "long-range damage stays capped at 81")
	await _reset_fixture()
	_player._longshot_state.shots_fired = 4
	var enhanced := await _fire()
	if not bool(enhanced.get("missing", true)):
		_probe.position = Vector3(enhanced.origin) + Vector3(enhanced.direction) * 22.1
		_player.position = Vector3(-60, 0, 60)
		await create_timer(0.5).timeout
		_check(bool(enhanced.enhanced) and _probe.hit_count == 1, "fifth long-range shot remains one projectile and one hit")
		_check(absf(_probe.total_damage - 113.4) < 0.03, "enhanced maximum is 113.4 damage after shooter relocation")


func _test_emitted_cycle() -> void:
	await _reset_fixture()
	var wall := _box(Vector3(0, 1.5, -8), Vector3(8, 3, 0.05))
	wall.collision_layer = 0
	await _settle()
	var enhanced_ranks: Array[int] = []
	for rank in range(1, 16):
		wall.collision_layer = 1 if rank % 3 == 0 else 0
		await _settle()
		var shot := await _fire()
		_check(_player.get_longshot_shots_fired() == rank, "emission advances cycle despite miss or wall at rank %d" % rank)
		_check(_player.get_longshot_cycle_count() == rank % 5, "public cycle is real emitted count at rank %d" % rank)
		_check(_player.is_longshot_enhanced_ready() == (rank % 5 == 4), "ready state advertises the fifth shot at rank %d" % rank)
		_check(int(_player._longshot_visual.get("_cycle_count")) == rank % 5 and bool(_player._longshot_visual.get("_enhanced_ready")) == (rank % 5 == 4), "weapon core follows authoritative cycle at rank %d" % rank)
		if not bool(shot.get("missing", true)):
			if bool(shot.enhanced):
				enhanced_ranks.append(rank)
			var expected_speed := 75.0 if bool(shot.enhanced) else 60.0
			var expected_radius := 0.1125 if bool(shot.enhanced) else 0.075
			_check(is_equal_approx(float(shot.speed), expected_speed) and is_equal_approx(float(shot.radius), expected_radius), "emitted size and speed match rank %d" % rank)
		await create_timer(0.13 if rank % 3 == 0 else 0.01).timeout
		if rank % 3 == 0:
			_check(not _last_hit_on(wall).is_empty(), "wall impact still leaves the cycle advanced at rank %d" % rank)
		await _clear_projectiles()
	_check(enhanced_ranks == [5, 10, 15], "enhanced projectiles occur at exactly 5, 10 and 15")
	wall.queue_free()
	await _settle()


func _test_rejections_and_cancellation() -> void:
	await _reset_fixture(false)
	await _fire()
	var emitted := _player.get_longshot_shots_fired()
	_player._perform_longshot_attack()
	await create_timer(0.15).timeout
	_check(_player.get_longshot_shots_fired() == emitted and not _player._longshot_attack_busy, "cooldown rejection never emits or advances")
	var ready_at := _player._longshot_next_attack_ready_at
	_player.set_weapon("shotgun")
	_player.set_weapon("longshot")
	_player._perform_longshot_attack()
	await create_timer(0.15).timeout
	_check(_player.get_longshot_shots_fired() == emitted and is_equal_approx(_player._longshot_next_attack_ready_at, ready_at), "weapon switch preserves cycle and recovery deadline")
	for interruption in ["explicit", "switch", "module", "stun", "disable"]:
		await _reset_fixture()
		await _fire()
		await _clear_projectiles()
		_player._longshot_next_attack_ready_at = 0.0
		await _settle()
		var before := _player.get_longshot_shots_fired()
		_player._perform_longshot_attack()
		_check(_player._longshot_attack_busy, "%s cancellation fixture starts real preparation" % interruption)
		await create_timer(0.025).timeout
		match interruption:
			"explicit": _player._cancel_longshot_attack()
			"switch": _player.set_weapon("blaster")
			"module": _player._try_begin_module_action("javelin")
			"stun": _player.apply_stun(1.0, "longshot_test")
			"disable": _player.set_gameplay_enabled(false)
		await create_timer(0.15).timeout
		_check(_player.get_longshot_shots_fired() == before and not _player._longshot_attack_busy, "%s cancellation before emission preserves cycle" % interruption)
		if interruption == "module" or interruption == "stun" or interruption == "disable":
			_player._perform_longshot_attack()
			await create_timer(0.13).timeout
			_check(_player.get_longshot_shots_fired() == before, "%s ownership/incapacity rejects attempted attack" % interruption)


func _test_instance_lifecycle() -> void:
	await _reset_fixture()
	for _shot in range(4):
		await _fire()
		await _clear_projectiles()
	_check(_player.is_longshot_enhanced_ready(), "four real emissions prepare fifth shot")
	_player.set_weapon("shotgun")
	await _settle()
	_player.set_weapon("longshot")
	await _settle()
	_check(_player.get_longshot_cycle_count() == 4 and _player.is_longshot_enhanced_ready(), "same carried instance retains ready state after switch")
	await create_timer(0.3).timeout
	_check(_player.is_longshot_enhanced_ready(), "progression does not expire between shots")
	var shot := await _fire()
	_check(bool(shot.get("enhanced", false)) and _player.get_longshot_cycle_count() == 0, "next shot after switch is enhanced and then wraps")
	await _clear_projectiles()
	await _fire()
	_player.take_damage(2000.0, "longshot_test", "longshot_player_death")
	_check(_player.is_real_dead() and _player.get_longshot_shots_fired() == 0, "real death resets cycle")
	_player.reset_combat_state()
	_player.set_gameplay_enabled(true)
	await _settle()
	await _clear_projectiles()
	await _fire()
	_player.reset_combat_state()
	_check(_player.get_longshot_shots_fired() == 0, "new round resets cycle")
	_player.set_gameplay_enabled(true)
	await _settle()
	await _clear_projectiles()
	await _fire()
	_player.apply_loadout(_loadout())
	_check(_player.get_longshot_shots_fired() == 0, "replacement loadout resets its weapon instance")


func _test_mouse_hold_release() -> void:
	await _reset_fixture(false)
	_mouse(true)
	await _poll_attack_for(1.25)
	_check(_player.emissions.size() == 2, "real PC mouse hold automatically repeats at configured cadence")
	_check(not _player.is_blaster_charging(), "LONGSHOT PC hold has no charge stage")
	_mouse(false)
	var emitted := _player.get_longshot_shots_fired()
	await _poll_attack_for(1.1)
	_check(_player.get_longshot_shots_fired() == emitted and not _player._desktop_mouse_attack_held, "PC release ends repeated fire without a release shot")


func _test_touch_hold_release() -> void:
	await _reset_fixture(false)
	_player.begin_touch_fire()
	await _poll_attack_for(1.25)
	_check(_player.emissions.size() == 2 and _player._touch_attack_held, "mobile attack contact repeats through existing held command")
	_check(not _player.is_blaster_charging(), "LONGSHOT mobile hold has no charge stage")
	_player.end_touch_fire()
	var emitted := _player.get_longshot_shots_fired()
	await _poll_attack_for(1.1)
	_check(_player.get_longshot_shots_fired() == emitted and not _player._touch_attack_held and not _player._touch_fire_active, "mobile release ends repeated fire without a release shot")
	_player.begin_touch_fire()
	_player._update_attack()
	_check(_player._longshot_attack_busy, "cancelled mobile contact starts a real preparation")
	_player.cancel_touch_fire("test cancelled contact")
	await create_timer(0.15).timeout
	_check(_player.get_longshot_shots_fired() == emitted, "cancelled mobile preparation never commits a projectile")
	_player.begin_touch_fire()
	_player._update_attack()
	_check(_player._longshot_attack_busy, "cleared mobile contact starts a real preparation")
	_player.clear_touch_inputs()
	await create_timer(0.15).timeout
	_check(_player.get_longshot_shots_fired() == emitted, "system clearing mobile inputs cancels its pending preparation")
	_mouse(true)
	_player._update_attack()
	_check(_player._longshot_attack_busy, "desktop control fixture starts preparation after cleared touch")
	_player.clear_touch_inputs()
	await create_timer(0.15).timeout
	_check(_player.get_longshot_shots_fired() == emitted + 1, "clearing inactive mobile overlay preserves desktop preparation")
	_mouse(false)


func _test_moving_aim_and_recoil() -> void:
	for angle in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		await _reset_fixture()
		var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
		_player.fixture_velocity = Vector3.RIGHT * 5.0
		_player._set_aim_direction(direction)
		await _settle()
		var shot := await _fire()
		if bool(shot.get("missing", true)):
			continue
		_check(Vector3(shot.origin).distance_to(Vector3(shot.muzzle)) < 0.001, "projectile leaves live moving muzzle at %.0f degrees" % angle)
		_check(Vector3(shot.direction).dot(direction) > 0.999, "moving projectile follows input aim at %.0f degrees" % angle)
		_check(Vector3(shot.model_forward).normalized().dot(Vector3(shot.direction)) > 0.999, "visible barrel aligns to emitted direction at %.0f degrees" % angle)
		await create_timer(0.32).timeout
		_check(not _player._visual_rig.is_shot_kick_active(), "short recoil finishes at %.0f degrees" % angle)
		var barrel := _player._visual_rig.get_weapon_forward_direction(&"longshot")
		_check(barrel.dot(direction) > 0.999 and absf(barrel.y) < 0.01, "barrel returns to aim rather than staying raised at %.0f degrees" % angle)
		await _clear_projectiles()


func _fire() -> Dictionary:
	# The action gate deliberately refuses a second acquisition in the same
	# physics frame, even after the preceding shot released its ownership.
	await _settle()
	var previous := _player.emissions.size()
	_player._perform_longshot_attack()
	var deadline := Time.get_ticks_msec() + 1000
	while _player.emissions.size() == previous and Time.get_ticks_msec() < deadline:
		await _settle()
	_check(_player.emissions.size() == previous + 1, "accepted attack emits one real projectile")
	return _player.emissions.back() if _player.emissions.size() > previous else {"missing": true}


func _test_survival_upgrade() -> void:
	await _reset_fixture()
	var progression = preload("res://scripts/survival_progression.gd").new()
	_check(progression.choose_weapon("longshot"), "Survival progression accepts LONGSHOT selection")
	await _fire()
	await _clear_projectiles()
	await _fire()
	await _clear_projectiles()
	var before := _player.get_longshot_shots_fired()
	var build: Dictionary = progression.build()
	build.upgrades.weapon.power = 1
	build.upgrades.weapon.tempo = 1
	build.aspects = {}
	build.evolutions = {}
	_player.configure_survival_build(build)
	_check(_player.get_longshot_shots_fired() == before and _player.get_weapon_id() == "longshot", "Survival stat upgrade preserves carried cycle")
	_check(is_equal_approx(float(_player._longshot_definition.damage), 36.0 * 1.25), "Survival power rank applies damage multiplier once")
	_check(is_equal_approx(float(_player._longshot_definition.cooldown), 1.05 * 0.864), "Survival tempo rank applies configured cadence multiplier")
	# Reapplying the same rewards must read base settings instead of compounding.
	_player.configure_survival_build(build)
	_check(is_equal_approx(float(_player._longshot_definition.damage), 45.0) and _player.get_longshot_shots_fired() == before, "reapplying Survival upgrades neither compounds power nor resets cycle")
	# Generic weapon evolution cannot accidentally route this new weapon through
	# the Blaster's secondary damage and piercing effects.
	build.evolutions = {"weapon": true}
	_player.configure_survival_build(build)
	var previous_legacy := _legacy_projectiles
	var shot := await _fire()
	if not bool(shot.get("missing", true)):
		_probe.clear_damage()
		_probe.position = Vector3(shot.origin) + Vector3(shot.direction) * 22.1
		_player.position = Vector3(60, 0, 60)
		await create_timer(0.5).timeout
		_check(_probe.hit_count == 1 and absf(_probe.total_damage - 101.25) < 0.03, "Survival LONGSHOT applies upgraded distance damage once")
		_check(_legacy_projectiles == previous_legacy and _probe.status_applications == 0, "Survival LONGSHOT adds no Blaster secondary projectile or burn")
	_player.apply_loadout(_loadout())


func _reset_fixture(instant_cooldowns: bool = true) -> void:
	_mouse(false)
	_player.clear_touch_inputs()
	_player.fixture_velocity = Vector3.ZERO
	_player.position = Vector3.ZERO
	_player.reset_combat_state()
	_player.set_gameplay_enabled(true)
	_player.set_weapon("longshot")
	_player.set_training_options(false, instant_cooldowns, true)
	_player._set_aim_direction(Vector3.FORWARD)
	_player.emissions.clear()
	_player.impacts.clear()
	_probe.clear_damage()
	_probe.position = Vector3(100, 1.5, 100)
	await _clear_projectiles()
	await _settle()


func _poll_attack_for(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_player._update_attack()
		await _settle()


func _animate_fixture() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var delta := 1.0 / Engine.physics_ticks_per_second
	_player.position += _player.fixture_velocity * delta
	_player._update_robot_motion(delta)
	_player._update_weapon_pose_state(delta)


func _observe_added_node(node: Node) -> void:
	var script = node.get_script()
	if script != null and script.resource_path == "res://scripts/live_projectile.gd":
		_legacy_projectiles += 1


func _last_hit_on(collider: Node) -> Dictionary:
	for index in range(_player.impacts.size() - 1, -1, -1):
		var impact: Dictionary = _player.impacts[index]
		if impact.hit.get("collider") == collider:
			return impact
	return {}


func _clear_projectiles() -> void:
	for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
		projectile.queue_free()
	await process_frame


func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_player._input(event)
	_player._unhandled_input(event)


func _box(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	current_scene.add_child(body)
	return body


func _loadout() -> Dictionary:
	return {"robot": "polyvalent", "weapon": "longshot", "offensive": "javelin", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "omnivamp"}


func _settle() -> void:
	await physics_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
