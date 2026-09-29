extends StaticBody3D

signal died

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const DUEL_STATE := preload("res://scripts/duel_bot_state.gd")
const COMBAT_STATE := preload("res://scripts/combat_state.gd")
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")
const TRAINING_BOT := preload("res://scripts/training_bot.gd")
const ENEMY_DROID_VISUAL := preload("res://scripts/enemy_droid_visual.gd")
const STATUS_VFX := preload("res://scripts/status_vfx.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
const PELTO_SMASH := preload("res://scripts/pelto_smash.gd")

var combat_state
var visibility_state
var _resetting := false
const COMBAT_READOUT := preload("res://scripts/combat_readout.gd")
var _health_readout: Node3D
var _status_label: Label3D
var _visual_rig: Node3D
var _status_vfx: Node3D
var _javelin_mark_label: Label3D
var _javelin_mark_until := -1.0
var _effect_clock := 0.0
var _training_bot: Node
var _last_visual_position := Vector3.ZERO
var _duel_mode := false
var _duel_paused := false
var network_proxy := false
var _fulguro_projection_active := false
var _fulguro_projection_direction := Vector3.ZERO
var _fulguro_projection_distance_remaining := 0.0
var _fulguro_projection_time_remaining := 0.0
var _fulguro_projection_speed := 0.0
var _fulguro_projection_wall_damage := 0.0
var _fulguro_projection_wall_stun := 0.0
var _fulguro_projection_source_id := ""
var _fulguro_projection_attack_id := ""
var _fulguro_wall_stun_active := false
var _pelto_pull_active := false
var _pelto_pull_direction := Vector3.ZERO
var _pelto_pull_distance_remaining := 0.0
var _pelto_pull_time_remaining := 0.0
var _pelto_pull_speed := 0.0
var _defensive_buffer: Dictionary = {}


func _ready() -> void:
	# Sample displacement after TrainingBot's default-priority physics step.
	process_physics_priority = 10
	add_to_group("prototype0_combat_bots")
	collision_layer = 2
	collision_mask = 0
	combat_state = COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH)
	visibility_state = VISIBILITY_STATE.new()
	combat_state.health_changed.connect(_on_health_changed)
	combat_state.damage_applied.connect(_on_damage_applied)
	combat_state.healing_applied.connect(_on_healing_applied)
	combat_state.effect_changed.connect(_on_effect_changed)
	combat_state.died.connect(_on_state_died)
	_build_collision()
	_build_visuals()
	_training_bot = TRAINING_BOT.new()
	_training_bot.name = "TrainingBot"
	add_child(_training_bot)
	_training_bot.call("set_enabled", false)
	_last_visual_position = global_position
	_update_label()
	_update_effect_presentation()


func _process(delta: float) -> void:
	_effect_clock += delta
	if visibility_state != null:
		visibility_state.update(delta)
	if combat_state != null and not _resetting and not _duel_paused:
		combat_state.update(delta)
	if _fulguro_wall_stun_active and (combat_state == null or not combat_state.is_stunned()):
		_fulguro_wall_stun_active = false
	_try_execute_defensive_buffer()
	if _javelin_mark_until >= 0.0 and Time.get_ticks_msec() / 1000.0 >= _javelin_mark_until:
		_javelin_mark_until = -1.0
	_update_effect_presentation()
	_update_visibility_presentation()


func _physics_process(delta: float) -> void:
	if _fulguro_projection_active and not _duel_paused:
		_update_fulguro_projection(delta)
	elif _pelto_pull_active and not _duel_paused:
		_update_pelto_pull(delta)
	var displacement := global_position - _last_visual_position
	_last_visual_position = global_position
	if _visual_rig == null or delta <= 0.0:
		return
	displacement.y = 0.0
	var actual_velocity := Vector3.ZERO
	var active := is_training_bot_enabled() and not is_real_dead() and not _duel_paused
	# Resets and showcase teleports are not strides. Normal dodge displacement
	# still passes at any physics tick rate, including a slow diagnostic run.
	var maximum_step := maxf(0.5, TRAINING_BOT.DODGE_SPEED * delta * 2.0)
	if active and not is_stunned() and displacement.length() <= maximum_step:
		actual_velocity = displacement / delta
	var aim_point := global_position - global_basis.z * 4.0 + Vector3.UP * 0.92
	if _training_bot != null:
		aim_point = _training_bot.call("get_visual_aim_point")
	_visual_rig.call("update_visual", delta, actual_velocity, aim_point, active, is_stunned(), _duel_paused)


func prepare_training_bot_shot(aim_point: Vector3) -> Transform3D:
	if _visual_rig != null:
		var shot: Transform3D = _visual_rig.call("prepare_shot", aim_point)
		var origin := global_position + Vector3.UP * 0.9
		var query := PhysicsRayQueryParameters3D.create(origin, shot.origin)
		query.collision_mask = 1 | 2 | 4 | 8
		query.collide_with_areas = true
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			shot.origin = origin
			shot.basis = Basis.looking_at((aim_point - origin).normalized(), Vector3.UP)
		return shot
	return Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 1.30)


func get_training_bot_muzzle_transform() -> Transform3D:
	if _visual_rig != null:
		return _visual_rig.call("get_muzzle_transform")
	return Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 1.30)


## Shared combat API used by the player, future bot and Training Lab.
func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if _resetting or combat_state == null:
		return 0.0
	if network_proxy:
		get_node("/root/NetworkSession").send_hit(amount, source_id, attack_id)
	if _duel_mode and bool(get_meta("duel_static_shield", false)):
		return 0.0
	if amount > 0.0 and visibility_state != null:
		visibility_state.mark_combat_event()
	if get_meta("survival_elite", "") == "shield" and source_id == "player":
		var attacker := get_tree().current_scene.get_node_or_null("Player") as Node3D
		if attacker != null:
			var incoming := (attacker.global_position - global_position).normalized()
			var facing: Vector3 = get_meta("shield_facing", Vector3.FORWARD)
			if incoming.dot(facing) > 0.5:
				amount *= 0.45
	if _duel_mode and combat_state.get_script() != DUEL_STATE and _training_bot != null and _training_bot.has_method("intercept_duel_damage"):
		var intercepted: Dictionary = _training_bot.call("intercept_duel_damage", amount, combat_state.health)
		if bool(intercepted.get("triggered_baroud", false)):
			return 0.0
		var effective := float(intercepted.get("effective", amount))
		if not bool(intercepted.get("apply_to_health", true)):
			return effective
		if bool(intercepted.get("real_death", false)):
			combat_state.apply_damage(combat_state.health, source_id, attack_id)
			return effective
		amount = effective
	return combat_state.apply_damage(amount, source_id, attack_id)


func heal(amount: float, source_id: String = "") -> float:
	if _resetting or combat_state == null:
		return 0.0
	return combat_state.heal(amount, source_id)


func apply_burn(duration: float = COMBAT_DATA.BURN_DURATION, damage_per_second: float = COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	if network_proxy:
		get_node("/root/NetworkSession").send_effect("burn", duration, damage_per_second)
		return
	if combat_state != null:
		combat_state.apply_burn(duration, damage_per_second, source_id)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	if network_proxy:
		get_node("/root/NetworkSession").send_effect("slow", duration, percent)
	if combat_state != null:
		combat_state.apply_slow(duration, percent, source_id)


func apply_stun(duration: float, source_id: String = "") -> void:
	if network_proxy:
		get_node("/root/NetworkSession").send_effect("stun", duration)
	if duration > 0.0:
		_cancel_pelto_pull()
	if combat_state != null:
		combat_state.apply_stun(duration, source_id)


func apply_spotted(duration: float, source_id: String = "") -> void:
	if network_proxy:
		get_node("/root/NetworkSession").send_effect("spotted", duration)
	if combat_state != null:
		combat_state.apply_spotted(duration, source_id)
	if visibility_state != null:
		visibility_state.mark_spotted(duration)


func reset_combat_state() -> void:
	if _health_readout != null:
		_health_readout.call("clear_damage_numbers")
	_resetting = false
	# Revived targets can be hit again after their corpse stopped intercepting shots.
	collision_layer = 2
	_cancel_fulguro_projection()
	_cancel_pelto_pull()
	_defensive_buffer.clear()
	_javelin_mark_until = -1.0
	if combat_state != null:
		combat_state.reset()
	if visibility_state != null:
		visibility_state.reset()
	if _training_bot != null:
		_training_bot.call("reset_clock")
	_last_visual_position = global_position
	if _visual_rig != null:
		_visual_rig.call("reset_visual")
	if _status_vfx != null:
		_status_vfx.call("clear")
	_update_status("")
	_update_label()
	_update_effect_presentation()


func set_training_bot_enabled(value: bool) -> void:
	_last_visual_position = global_position
	if _training_bot != null:
		_training_bot.call("set_enabled", value)


func set_training_bot_spawn_position(value: Vector3) -> void:
	_last_visual_position = global_position
	if _training_bot != null:
		_training_bot.call("set_spawn_position", value)


func toggle_training_bot() -> bool:
	if _training_bot == null:
		return false
	return bool(_training_bot.call("toggle"))


func is_training_bot_enabled() -> bool:
	return _training_bot != null and bool(_training_bot.call("is_enabled"))


func get_health() -> float:
	return combat_state.health if combat_state != null else 0.0


func get_max_health() -> float:
	return combat_state.max_health if combat_state != null else COMBAT_DATA.MAX_HEALTH


func is_stunned() -> bool:
	return combat_state != null and combat_state.is_stunned()


func get_fulguro_hit_radius() -> float:
	return 0.70 * maxf(absf(scale.x), absf(scale.z))


func is_fulguro_projected() -> bool:
	return _fulguro_projection_active


func is_action_locked() -> bool:
	return is_real_dead() or _resetting or _fulguro_projection_active or is_stunned()


func start_fulguro_projection(direction: Vector3, max_distance: float, max_duration: float, wall_damage: float, wall_stun: float, source_id: String, attack_id: String) -> void:
	if is_real_dead() or _resetting or max_distance <= 0.0 or max_duration <= 0.0:
		return
	if _training_bot != null and _training_bot.has_method("cancel_action"):
		_training_bot.call("cancel_action")
	_cancel_pelto_pull()
	_fulguro_projection_active = true
	_fulguro_projection_direction = FULGURO.flat_direction(direction)
	_fulguro_projection_distance_remaining = maxf(0.0, max_distance)
	_fulguro_projection_time_remaining = maxf(0.001, max_duration)
	_fulguro_projection_speed = _fulguro_projection_distance_remaining / _fulguro_projection_time_remaining
	_fulguro_projection_wall_damage = maxf(0.0, wall_damage)
	_fulguro_projection_wall_stun = maxf(0.0, wall_stun)
	_fulguro_projection_source_id = source_id
	_fulguro_projection_attack_id = attack_id
	_spawn_fulguro_motion_visual(Color("#65e9ff"), 0.70)


func _update_fulguro_projection(delta: float) -> void:
	if not _fulguro_projection_active:
		return
	if is_real_dead() or _resetting:
		_cancel_fulguro_projection()
		return
	var available_time := minf(maxf(delta, 0.0), _fulguro_projection_time_remaining)
	var step_distance := minf(_fulguro_projection_distance_remaining, _fulguro_projection_speed * available_time)
	if step_distance <= 0.0001:
		_finish_fulguro_projection(false)
		return
	var radius := get_fulguro_hit_radius()
	var height := 1.8 * maxf(0.1, absf(scale.y))
	var result := FULGURO.sweep_static_body(self, _fulguro_projection_direction * step_distance, radius, height)
	var travel: Vector3 = result.get("travel", Vector3.ZERO)
	global_position += travel
	global_position.y = 0.0
	_fulguro_projection_distance_remaining = maxf(0.0, _fulguro_projection_distance_remaining - travel.length())
	_fulguro_projection_time_remaining = maxf(0.0, _fulguro_projection_time_remaining - available_time)
	if bool(result.get("collided", false)):
		var normal: Vector3 = result.get("normal", Vector3.ZERO)
		var crushing := FULGURO.is_crushing_wall(result.get("collider", null), normal, _fulguro_projection_direction)
		_finish_fulguro_projection(crushing, result.get("position", global_position), normal)
		return
	if _fulguro_projection_distance_remaining <= 0.001 or _fulguro_projection_time_remaining <= 0.001:
		_finish_fulguro_projection(false)


func _finish_fulguro_projection(crushed_wall: bool, impact_position: Vector3 = Vector3.ZERO, impact_normal: Vector3 = Vector3.ZERO) -> void:
	if not _fulguro_projection_active:
		return
	_fulguro_projection_active = false
	_fulguro_projection_distance_remaining = 0.0
	_fulguro_projection_time_remaining = 0.0
	_fulguro_projection_speed = 0.0
	if crushed_wall and not is_real_dead():
		var applied := take_damage(_fulguro_projection_wall_damage, _fulguro_projection_source_id, "%s:wall" % _fulguro_projection_attack_id)
		if applied > 0.0 and not is_real_dead():
			_fulguro_wall_stun_active = true
			apply_stun(_fulguro_projection_wall_stun, "fulguro_wall")
			_spawn_fulguro_wall_visual(impact_position, impact_normal)
	_try_execute_defensive_buffer()


func _cancel_fulguro_projection() -> void:
	_fulguro_projection_active = false
	_fulguro_projection_direction = Vector3.ZERO
	_fulguro_projection_distance_remaining = 0.0
	_fulguro_projection_time_remaining = 0.0
	_fulguro_projection_speed = 0.0
	_fulguro_wall_stun_active = false


func start_pelto_pull(pull_direction: Vector3, distance: float, duration: float, _source_id: String = "", _attack_id: String = "") -> void:
	if is_real_dead() or _resetting or _fulguro_projection_active or is_stunned() or distance <= 0.0 or duration <= 0.0:
		return
	_pelto_pull_active = true
	_pelto_pull_direction = PELTO_SMASH.flat_direction(pull_direction)
	_pelto_pull_distance_remaining = maxf(0.0, distance)
	_pelto_pull_time_remaining = maxf(0.001, duration)
	_pelto_pull_speed = _pelto_pull_distance_remaining / _pelto_pull_time_remaining


func _update_pelto_pull(delta: float) -> void:
	if not _pelto_pull_active:
		return
	if is_real_dead() or _resetting or _fulguro_projection_active or is_stunned():
		_cancel_pelto_pull()
		return
	var available_time := minf(maxf(delta, 0.0), _pelto_pull_time_remaining)
	var step_distance := minf(_pelto_pull_distance_remaining, _pelto_pull_speed * available_time)
	if step_distance <= 0.0001:
		_cancel_pelto_pull()
		return
	var result := FULGURO.sweep_static_body(self, _pelto_pull_direction * step_distance, get_fulguro_hit_radius(), 1.8 * maxf(0.1, absf(scale.y)))
	var travel: Vector3 = result.get("travel", Vector3.ZERO)
	global_position += travel
	global_position.y = 0.0
	_pelto_pull_distance_remaining = maxf(0.0, _pelto_pull_distance_remaining - travel.length())
	_pelto_pull_time_remaining = maxf(0.0, _pelto_pull_time_remaining - available_time)
	if bool(result.get("collided", false)) or _pelto_pull_distance_remaining <= 0.001 or _pelto_pull_time_remaining <= 0.001:
		_cancel_pelto_pull()


func _cancel_pelto_pull() -> void:
	_pelto_pull_active = false
	_pelto_pull_direction = Vector3.ZERO
	_pelto_pull_distance_remaining = 0.0
	_pelto_pull_time_remaining = 0.0
	_pelto_pull_speed = 0.0


func is_pelto_pulled() -> bool:
	return _pelto_pull_active


func request_defensive_dodge(direction: Vector3) -> bool:
	var flat := FULGURO.flat_direction(direction)
	if _fulguro_projection_active or _fulguro_wall_stun_active:
		_defensive_buffer = {"type": "dash", "direction": flat}
		return true
	if is_action_locked() or _training_bot == null or not _training_bot.has_method("execute_buffered_dodge"):
		return false
	_cancel_pelto_pull()
	return bool(_training_bot.call("execute_buffered_dodge", flat))


func _try_execute_defensive_buffer() -> void:
	if _defensive_buffer.is_empty() or is_action_locked():
		return
	var command := _defensive_buffer.duplicate()
	_defensive_buffer.clear()
	if str(command.get("type", "")) != "dash" or _training_bot == null or not _training_bot.has_method("execute_buffered_dodge"):
		return
	var direction: Vector3 = command.get("direction", Vector3.ZERO)
	if direction.length_squared() > 0.001:
		_training_bot.call("execute_buffered_dodge", direction)


func get_buffered_defensive_action() -> String:
	return str(_defensive_buffer.get("type", ""))


func _spawn_fulguro_motion_visual(color: Color, alpha: float) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.62
	mesh.outer_radius = 0.78
	mesh.rings = 10
	mesh.ring_segments = 28
	ring.mesh = mesh
	ring.position = Vector3(0.0, 0.12, 0.0)
	ring.material_override = _fulguro_material(color, alpha)
	add_child(ring)
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 1.65, 0.28)
	tween.tween_method(Callable(self, "_set_fulguro_material_alpha").bind(ring.material_override), alpha, 0.0, 0.28)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)


func _spawn_fulguro_wall_visual(impact_position: Vector3, impact_normal: Vector3) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	var vfx := scene.get_node_or_null("VFXManager") if scene != null else null
	var normal := impact_normal if impact_normal.length_squared() > 0.001 else -_fulguro_projection_direction
	var position := impact_position if impact_position != Vector3.ZERO else global_position + Vector3.UP * 0.85
	if vfx != null:
		vfx.call("impact", position, normal, "environment", 1.65, Color("#ffb34f"))
	_spawn_fulguro_motion_visual(Color("#ffb34f"), 0.92)


func _fulguro_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.15
	return material


func _set_fulguro_material_alpha(alpha: float, material: StandardMaterial3D) -> void:
	if material != null:
		material.albedo_color.a = alpha


func is_spotted() -> bool:
	return combat_state != null and combat_state.is_spotted()


func get_slow_percent() -> float:
	return combat_state.get_slow_percent() if combat_state != null else 0.0


func get_active_effect_types() -> Array[String]:
	return combat_state.get_active_effect_types() if combat_state != null else []


func get_combat_reveal_remaining() -> float:
	return visibility_state.combat_remaining if visibility_state != null else 0.0


func get_spotted_reveal_remaining() -> float:
	return visibility_state.spotted_remaining if visibility_state != null else 0.0


func is_revealed() -> bool:
	return visibility_state != null and visibility_state.is_revealed()


func is_in_bush() -> bool:
	for bush in get_tree().get_nodes_in_group("bush_placeholder"):
		if not is_instance_valid(bush):
			continue
		var radius := float(bush.get_meta("bush_radius", 0.0))
		if Vector2(global_position.x - bush.global_position.x, global_position.z - bush.global_position.z).length() <= radius:
			return true
	return false


func is_visible_to(observer: Node3D) -> bool:
	if observer == null or not is_instance_valid(observer):
		return true
	var line_of_sight := _line_of_sight_clear(observer)
	return VISIBILITY_STATE.visible_to_observer(is_revealed(), is_in_bush(), line_of_sight)


func _line_of_sight_clear(observer: Node3D) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(observer.global_position + Vector3.UP * 0.72, global_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [observer.get_rid(), get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


func _update_visibility_presentation() -> void:
	var observer: Node3D = get_tree().current_scene.get_node_or_null("Player") as Node3D if get_tree().current_scene != null else null
	var should_show := is_visible_to(observer)
	for node in [_visual_rig, _health_readout, _status_label]:
		if node != null:
			node.visible = should_show
	# Parent visibility gates the presentation without reviving expired groups.
	if _status_vfx != null:
		_status_vfx.visible = should_show and not _resetting and not is_real_dead()
	if _javelin_mark_label != null:
		_javelin_mark_label.visible = should_show and has_javelin_mark()


func apply_javelin_mark(duration: float, _source_id: String = "") -> void:
	_javelin_mark_until = Time.get_ticks_msec() / 1000.0 + maxf(0.0, duration)


func has_javelin_mark() -> bool:
	return _javelin_mark_until > Time.get_ticks_msec() / 1000.0 and not _resetting and get_health() > 0.0


func get_javelin_mark_remaining() -> float:
	if not has_javelin_mark():
		return 0.0
	return maxf(0.0, _javelin_mark_until - Time.get_ticks_msec() / 1000.0)


func clear_javelin_mark() -> void:
	_javelin_mark_until = -1.0


func flash_impact(critical: bool = false) -> void:
	# Damage callers already create the collision impact at its surface normal.
	# This is actor feedback only; a lethal hit must not interrupt the death pose.
	if _visual_rig == null:
		return
	if not _resetting and not is_real_dead() and get_health() > 0.0:
		_visual_rig.call("play_hit", critical)
	var scene := get_tree().current_scene
	var manager := scene.get_node_or_null("VFXManager") if scene != null else null
	if manager != null:
		manager.call("hit_flash", _visual_rig, critical)


func _on_health_changed(_current: float, _maximum: float) -> void:
	_update_label()


func _on_damage_applied(amount: float, source_id: String, attack_id: String) -> void:
	if _health_readout != null:
		_health_readout.call("show_damage", amount)
	# Burn ticks are damage but have no collision impact.
	if not attack_id.is_empty():
		get_node("/root/GameSfx").play_event("impact_critical" if attack_id.contains(":critical") else "impact_robot")
	# The prototype has one player attacker. Keep attribution on effective PV
	# removed so Omnivamp also sees criticals and BURN ticks, never overkill.
	if not (source_id == "player" or source_id.begins_with("player:")):
		return
	var attacker := get_tree().current_scene.get_node_or_null("Player") if get_tree().current_scene != null else null
	if attacker != null and is_instance_valid(attacker):
		attacker.call("_on_damage_dealt", amount, self)


func _on_damage_dealt(effective_damage: float) -> void:
	if _duel_mode and _training_bot != null and _training_bot.has_method("register_duel_damage"):
		_training_bot.call("register_duel_damage", effective_damage)


func _on_healing_applied(amount: float, _source_id: String) -> void:
	if _health_readout != null and _health_readout.has_method("show_healing"):
		_health_readout.call("show_healing", amount)


func _on_effect_changed(_effect_type: String, _active: bool) -> void:
	_update_effect_presentation()


func set_duel_mode(value: bool) -> void:
	if (not value or network_proxy) and combat_state != null and combat_state.get_script() == DUEL_STATE:
		_replace_combat_state(COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH))
	_duel_mode = value
	if not value:
		_duel_paused = false
		if _health_readout != null:
			_health_readout.call("update_actor_identity", Color("#ee6b4e"), "BOT")
			_health_readout.call("set_shotgun_ammo", false, 0, 3, false, 0.0)
			_health_readout.call("set_blaster_charge", false, false, 0.0)


func set_duel_profile(value: String) -> void:
	if _training_bot != null:
		_training_bot.call("set_duel_profile", value)
	if _visual_rig != null:
		_visual_rig.call("set_weapon", value)


func set_duel_loadout(value: Dictionary) -> void:
	var robot_id: String = str(value.get("robot", COMBAT_DATA.DEFAULT_ROBOT))
	var definition: Dictionary = COMBAT_DATA.ROBOT_DEFINITIONS.get(robot_id, COMBAT_DATA.ROBOT_DEFINITIONS[COMBAT_DATA.DEFAULT_ROBOT])
	var state := DUEL_STATE.new(float(definition.max_health))
	state.passive.configure(str(value.get("passive", "baroud")))
	state.blocked = Callable(self, "is_duel_stasis")
	_replace_combat_state(state)
	if _training_bot != null and _training_bot.has_method("set_duel_loadout"):
		_training_bot.call("set_duel_loadout", value)
	if _visual_rig != null:
		_visual_rig.call("set_weapon", str(value.get("weapon", "blaster")))


func get_duel_loadout() -> Dictionary:
	return _training_bot.call("get_duel_loadout") if _training_bot != null and _training_bot.has_method("get_duel_loadout") else {"weapon": get_duel_profile()}


func set_bot_difficulty(value: String) -> void:
	if _training_bot != null:
		_training_bot.call("set_difficulty_profile", value)


func get_bot_difficulty() -> String:
	return str(_training_bot.call("get_difficulty_profile")) if _training_bot != null else "normal"


func set_bot_diagnostics_enabled(value: bool) -> void:
	if _training_bot != null:
		_training_bot.call("set_diagnostics_enabled", value)


func get_bot_diagnostic_snapshot() -> Dictionary:
	return _training_bot.call("get_diagnostic_snapshot") if _training_bot != null else {}


func _replace_combat_state(state: Object) -> void:
	combat_state = state
	combat_state.health_changed.connect(_on_health_changed)
	combat_state.damage_applied.connect(_on_damage_applied)
	combat_state.healing_applied.connect(_on_healing_applied)
	combat_state.effect_changed.connect(_on_effect_changed)
	combat_state.died.connect(_on_state_died)


func is_duel_stasis() -> bool:
	return _duel_mode and not network_proxy and bool(get_meta("duel_static_shield", false))


func get_duel_profile() -> String:
	return str(_training_bot.call("get_duel_profile")) if _training_bot != null else "blaster"


func is_duel_mode() -> bool:
	return _duel_mode


func set_duel_paused(value: bool) -> void:
	_duel_paused = value
	_last_visual_position = global_position


func is_real_dead() -> bool:
	return combat_state != null and combat_state.is_dead()


func shift_pause_timers(seconds: float) -> void:
	# CombatState effects use simulation delta, while the Javelin mark uses an
	# absolute timestamp. Move that timestamp forward so a pause never consumes
	# gameplay duration in the background.
	if seconds > 0.0 and _javelin_mark_until > 0.0:
		_javelin_mark_until += seconds


func _on_state_died() -> void:
	if _resetting:
		return
	_resetting = true
	# Keep the death visual, but let later projectiles pass through the corpse.
	collision_layer = 0
	get_node("/root/GameSfx").play_event("robot_destruction")
	_cancel_fulguro_projection()
	_cancel_pelto_pull()
	_defensive_buffer.clear()
	if _training_bot != null and _training_bot.has_method("cancel_action"):
		_training_bot.call("cancel_action")
	if _visual_rig != null:
		_visual_rig.call("play_death")
	_update_status("")
	_update_effect_presentation()
	died.emit()
	if not _duel_mode:
		call_deferred("_reset_target")


func _reset_target() -> void:
	await get_tree().create_timer(1.25).timeout
	reset_combat_state()


func _update_label() -> void:
	if _health_readout != null and combat_state != null:
		_health_readout.call("set_health", combat_state.display_health() if combat_state.has_method("display_health") else combat_state.health, combat_state.display_max_health() if combat_state.has_method("display_max_health") else combat_state.max_health)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.7
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)


func _build_visuals() -> void:
	_visual_rig = ENEMY_DROID_VISUAL.new()
	_visual_rig.name = "VisualRoot"
	add_child(_visual_rig)
	if not bool(_visual_rig.call("setup")):
		push_error("Le rig du droïde ennemi n'a pas pu être initialisé.")

	_health_readout = Node3D.new()
	_health_readout.name = "TargetHealthReadout"
	_health_readout.set_script(COMBAT_READOUT)
	add_child(_health_readout)
	_health_readout.position.y = 2.95 * (COMBAT_DATA.CHARACTER_VISUAL_SCALE - 1.0)
	_health_readout.call("configure", Color("#ee6b4e"), "BOT")

	_status_label = Label3D.new()
	_status_label.name = "StatusReadout"
	_status_label.position = Vector3(1.35, 3.75 * COMBAT_DATA.CHARACTER_VISUAL_SCALE, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 27
	_status_label.outline_size = 7
	_status_label.modulate = Color("#ffe0ac")
	add_child(_status_label)

	_status_vfx = STATUS_VFX.new()
	add_child(_status_vfx)
	_status_vfx.set("marker_height", 3.30 * COMBAT_DATA.CHARACTER_VISUAL_SCALE)
	_status_vfx.call("configure", self)

	_javelin_mark_label = Label3D.new()
	_javelin_mark_label.name = "JavelinMark"
	_javelin_mark_label.text = "JAVELIN"
	_javelin_mark_label.position = Vector3(0.0, 3.62 * COMBAT_DATA.CHARACTER_VISUAL_SCALE, 0.0)
	_javelin_mark_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_javelin_mark_label.font_size = 32
	_javelin_mark_label.outline_size = 7
	_javelin_mark_label.modulate = Color("#ffdb75")
	add_child(_javelin_mark_label)


func _update_effect_presentation() -> void:
	if combat_state == null:
		return
	var alive := not _resetting and not is_real_dead()
	var active_effects: Array = combat_state.get_active_effect_types() if alive else []
	if _status_vfx != null:
		_status_vfx.call("sync", active_effects)
	if _javelin_mark_label != null:
		_javelin_mark_label.visible = has_javelin_mark()
		_javelin_mark_label.scale = Vector3.ONE * (1.0 + sin(_effect_clock * 7.0) * 0.035)
	var lines: Array[String] = []
	for effect: String in active_effects:
		if effect == COMBAT_DATA.EFFECT_SLOW:
			lines.append("SLOW  %d%%  %.1fs" % [int(round(combat_state.get_slow_percent())), combat_state.get_remaining(effect)])
		else:
			lines.append("%s  %.1fs" % [effect, combat_state.get_remaining(effect)])
	if has_javelin_mark():
		lines.append("JAVELIN  %.1fs" % maxf(0.0, _javelin_mark_until - Time.get_ticks_msec() / 1000.0))
	_update_status("\n".join(lines))


func _update_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
