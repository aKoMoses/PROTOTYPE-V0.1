extends Node

const COMBAT_DATA := preload("res://scripts/combat_data.gd")

var profile := "blaster"
var ammo := 0
var reload_remaining := 0.0
var charge_remaining := 0.0
var charge_duration := 0.0
var next_attack_at := 1.0
var pyro_cooldown := 0.0
var bio_cooldown := 0.0
var bio_remaining := 0.0
var dash_remaining := 0.0
var dash_direction := Vector3.ZERO
var _shot_serial := 0
var _decision_serial := 0
var _aim_position := Vector3.ZERO
var _last_visible_at := -100.0


func set_profile(value: String) -> void:
	profile = "shotgun" if value == "shotgun" else "blaster"
	reset()


func reset() -> void:
	ammo = int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"])
	reload_remaining = 0.0
	charge_remaining = 0.0
	charge_duration = 0.0
	next_attack_at = 1.0
	pyro_cooldown = 0.0
	bio_cooldown = 0.0
	bio_remaining = 0.0
	dash_remaining = 0.0
	dash_direction = Vector3.ZERO
	_shot_serial = 0
	_decision_serial = 0
	_last_visible_at = -100.0
	_update_readout()


func get_speed_multiplier() -> float:
	return float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["speed_multiplier"]) if bio_remaining > 0.0 else 1.0


func is_dashing() -> bool:
	return dash_remaining > 0.0


func is_reloading() -> bool:
	return reload_remaining > 0.0


func tick(delta: float, elapsed: float, visible: bool, observed: Vector3, body: Node3D, player: Node3D, controller: Node) -> void:
	var cooldown_rate := float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["other_cooldown_rate"]) if bio_remaining > 0.0 else 1.0
	pyro_cooldown = maxf(0.0, pyro_cooldown - delta * cooldown_rate)
	bio_cooldown = maxf(0.0, bio_cooldown - delta)
	bio_remaining = maxf(0.0, bio_remaining - delta)
	if visible:
		_last_visible_at = elapsed
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			ammo = int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"])
		_update_readout()
	if profile == "shotgun" and ammo <= 0 and reload_remaining <= 0.0:
		_start_reload()
	var distance := body.global_position.distance_to(observed)
	if visible:
		if profile == "shotgun" and reload_remaining <= 0.0 and charge_remaining <= 0.0 and distance > 2.0 and distance < 6.0 and pyro_cooldown <= 0.0:
			_start_dash((observed - body.global_position).normalized())
		elif profile == "blaster" and distance < 5.0 and bio_cooldown <= 0.0:
			bio_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["duration"])
			bio_cooldown = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["cooldown"])
	if charge_remaining > 0.0:
		charge_remaining = maxf(0.0, charge_remaining - delta)
		controller.set("_windup_remaining", charge_remaining)
		controller.call("_update_telegraph")
		if charge_remaining <= 0.0:
			_fire(body, player)
			var recovery := float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["attack_recovery"]) if profile == "shotgun" else float(COMBAT_DATA.WEAPON_DEFINITIONS["blaster"]["cooldown"])
			next_attack_at = elapsed + recovery / (float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["attack_speed_multiplier"]) if bio_remaining > 0.0 else 1.0)
			controller.set("_windup_remaining", 0.0)
			controller.call("_update_telegraph")
		return
	if elapsed < next_attack_at or reload_remaining > 0.0 or not visible:
		return
	var maximum := float(COMBAT_DATA.WEAPON_DEFINITIONS[profile]["max_range"])
	if distance > maximum or not bool(controller.call("_line_of_sight_clear", body, player)):
		next_attack_at = elapsed + 0.2
		return
	if profile == "shotgun" and distance > 4.3:
		return
	_decision_serial += 1
	# Sometimes the bot fails to use a short opening even when its weapon is ready.
	if _decision_serial % 5 == 0:
		next_attack_at = elapsed + 0.4
		return
	var aim_error := deg_to_rad(4.0 if profile == "blaster" else 6.0)
	var direction := observed - body.global_position
	direction.y = 0.0
	direction = direction.normalized().rotated(Vector3.UP, randf_range(-aim_error, aim_error))
	_aim_position = body.global_position + direction * distance
	charge_duration = (0.55 + randf_range(0.0, 0.45)) if profile == "blaster" else float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["attack_preparation"])
	charge_remaining = charge_duration
	controller.set("_windup_remaining", charge_remaining)
	controller.call("_update_telegraph")
	_update_readout()


func advance_dash(body: Node3D, _controller: Node, delta: float) -> void:
	if dash_remaining <= 0.0:
		return
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]
	var step := float(definition["dash_distance"]) * minf(delta, dash_remaining) / float(definition["dash_duration"])
	var safe_step := _safe_dash_motion(body, dash_direction * step)
	body.global_position += safe_step
	body.global_position.y = 0.0
	dash_remaining = maxf(0.0, dash_remaining - delta)
	if safe_step.length_squared() + 0.0001 < step * step:
		dash_remaining = 0.0


func _safe_dash_motion(body: Node3D, motion: Vector3) -> Vector3:
	var world := body.get_world_3d()
	if world == null:
		return motion
	var collision: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D:
			collision = child as CollisionShape3D
			break
	if collision == null or collision.shape == null:
		return Vector3.ZERO
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.motion = motion
	query.margin = 0.04
	query.collision_mask = 1 | 8
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [body.get_rid()]
	var cast := world.direct_space_state.cast_motion(query)
	return motion * cast[0] if cast.size() >= 2 else Vector3.ZERO


func _start_dash(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	dash_direction = direction.normalized()
	dash_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["dash_duration"])
	pyro_cooldown = float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["cooldown"])


func _start_reload() -> void:
	reload_remaining = float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["reload_duration"])
	_update_readout()


func _fire(body: Node3D, player: Node3D) -> void:
	if profile == "shotgun":
		if ammo <= 0:
			return
		ammo -= 1
	_shot_serial += 1
	var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS[profile]
	var direction := _aim_position - body.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	direction = direction.normalized()
	var muzzle := body.global_position + Vector3.UP * 0.9
	if body.has_method("prepare_training_bot_shot"):
		var shot_transform: Transform3D = body.call("prepare_training_bot_shot", _aim_position + Vector3.UP * 0.9)
		muzzle = shot_transform.origin
	if profile == "shotgun":
		var volley := {"hits": 0, "base": 0.0}
		var angles: Array = definition["pellet_angles"]
		for index in range(angles.size()):
			_launch_projectile(body, player, muzzle, direction.rotated(Vector3.UP, deg_to_rad(float(angles[index]))), index, volley)
		if ammo <= 0:
			_start_reload()
	else:
		_launch_projectile(body, player, muzzle, direction, 0, {})
	_update_readout()


func _launch_projectile(body: Node3D, player: Node3D, muzzle: Vector3, direction: Vector3, pellet: int, volley: Dictionary) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS[profile]
	var maximum := float(definition["max_range"])
	var speed := float(definition["pellet_speed"] if profile == "shotgun" else definition["projectile_speed"])
	var endpoint := muzzle + direction * maximum
	var world := body.get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(muzzle, endpoint)
		query.collision_mask = 1 | 4 | 8
		query.collide_with_areas = true
		query.exclude = [body.get_rid()]
		var hit := world.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			endpoint = hit.position
	var distance := muzzle.distance_to(endpoint)
	var projectile := Node3D.new()
	projectile.name = "DuelBotPellet" if profile == "shotgun" else "DuelBotBlaster"
	scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = muzzle
	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("projectile_visual", projectile, "enemy")
		vfx.call("burst", muzzle, direction, Color("#ffbf83"), 4, 2.8, 0.10, 0.03, 30.0)
	var shot_profile := profile
	var shot_damage := float(definition["pellet_damage"]) if profile == "shotgun" else lerpf(float(definition["damage"]), float(definition["max_damage"]), clampf(charge_duration / float(definition["charge_time"]), 0.0, 1.0))
	var shot_id := "duel_bot:%d:%d" % [_shot_serial, pellet]
	var travel := projectile.create_tween()
	travel.tween_property(projectile, "global_position", endpoint, maxf(0.025, distance / speed))
	travel.tween_callback(Callable(self, "_resolve_projectile").bind(player, body, endpoint, distance, shot_profile, shot_damage, shot_id, volley))
	travel.tween_callback(projectile.queue_free)


func _resolve_projectile(player: Node3D, body: Node3D, endpoint: Vector3, distance: float, shot_profile: String, base_damage: float, shot_id: String, volley: Dictionary) -> void:
	if not is_instance_valid(player) or not is_instance_valid(body) or not player.has_method("take_damage"):
		return
	if not body.has_method("is_duel_mode") or not bool(body.call("is_duel_mode")) or not bool(get_parent().get("enabled")):
		return
	var target_point := player.global_position + Vector3.UP * 0.9
	var radius := float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["hitbox_radius"]) if shot_profile == "shotgun" else 0.95
	if target_point.distance_to(endpoint) > radius:
		return
	var damage := base_damage
	if shot_profile == "shotgun":
		var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]
		var ratio := clampf((distance - float(definition["falloff_start"])) / (float(definition["max_range"]) - float(definition["falloff_start"])), 0.0, 1.0)
		damage = lerpf(base_damage, float(definition["minimum_damage"]), ratio)
	var dealt := float(player.call("take_damage", damage, "duel_bot", shot_id))
	if dealt <= 0.0:
		return
	if shot_profile == "shotgun":
		volley["hits"] = int(volley["hits"]) + 1
		volley["base"] = float(volley["base"]) + damage
		if int(volley["hits"]) == int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["pellets_per_shot"]):
			player.call("take_damage", float(volley["base"]) * (COMBAT_DATA.CRIT_MULTIPLIER - 1.0), "duel_bot", shot_id + ":critical")
			if player.has_method("apply_burn"):
				player.call("apply_burn", COMBAT_DATA.BURN_DURATION, COMBAT_DATA.BURN_DAMAGE_PER_SECOND, "duel_bot:shotgun")


func _update_readout() -> void:
	var body := get_parent().get_parent() as Node3D if get_parent() != null else null
	if body == null or not body.has_method("is_duel_mode") or not bool(body.call("is_duel_mode")):
		return
	var readout := body.get_node_or_null("TargetHealthReadout")
	if readout == null:
		return
	readout.call("update_actor_identity", Color("#ee6b4e"), "ASSAILLANT · SHOTGUN" if profile == "shotgun" else "HARCELEUR · BLASTER")
	readout.call("set_shotgun_ammo", profile == "shotgun", ammo, int(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["magazine_size"]), reload_remaining > 0.0, 1.0 - reload_remaining / float(COMBAT_DATA.WEAPON_DEFINITIONS["shotgun"]["reload_duration"]))
	readout.call("set_blaster_charge", profile == "blaster", charge_remaining > 0.0, 1.0 - charge_remaining / maxf(0.01, charge_duration))
