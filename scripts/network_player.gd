extends "res://scripts/player.gd"

## The ordinary combat controller is used for both humans. Remote input is
## explicit; only host actors can change health or apply an on-hit effect.
const NETWORK_STATE := preload("res://scripts/network_combat_state.gd")

class ReplicaPassive extends "res://scripts/passive_state.gd":
	func process(delta: float) -> bool:
		# Interpolate the gauge; only a host snapshot can end Baroud or kill us.
		if baroud_active:
			baroud_remaining = maxf(0.0, baroud_remaining - delta)
			baroud_health = maxf(0.0, baroud_health - BAROUD_DRAIN_PER_SECOND * delta)
		return false

var controller: Node
var opponent: Node3D
var authoritative := true
var remote_controlled := false
var peer_id := 0
var remote_velocity := Vector3.ZERO
var received_actions := 0
var _replaying := false
var _contact_started_at := -1.0
var _mark_until := -1.0
var _network_hits: Dictionary = {}


func _ready() -> void:
	super._ready()
	collision_layer = 2
	combat_state = NETWORK_STATE.new(COMBAT_DATA.MAX_HEALTH)
	combat_state.authoritative = authoritative
	combat_state.health_changed.connect(_on_health_changed)
	combat_state.damage_applied.connect(_on_damage_applied)
	combat_state.healing_applied.connect(_on_healing_applied)
	combat_state.died.connect(_on_state_died)
	combat_state.damage_applied.connect(_on_network_damage)
	if not authoritative:
		passive_state = ReplicaPassive.new()
		passive_state.configure(_passive_id)
	if _health_readout != null and remote_controlled:
		_health_readout.call("update_actor_identity", Color("#ee6b4e"), "ADVERSAIRE")


func _notify(action: String, data: Dictionary = {}) -> void:
	if not _replaying and is_instance_valid(controller):
		controller.call("on_actor_action", self, action, data)


func _module_target() -> Node:
	return opponent if is_instance_valid(opponent) else null


func _update_aim() -> void:
	if not remote_controlled:
		super._update_aim()


func _update_movement(delta: float) -> void:
	if not remote_controlled:
		super._update_movement(delta)
	elif _dash_active:
		_update_dash(delta)


func _get_actual_move_velocity() -> Vector3:
	if remote_controlled and (_stasis_remaining > 0.0 or combat_state.is_stunned() or is_real_dead()):
		return Vector3.ZERO
	return remote_velocity if remote_controlled and not _dash_active else super._get_actual_move_velocity()


func _update_attack(ignore_module_lock: bool = false) -> void:
	if remote_controlled:
		_update_active_blaster_charge(Time.get_ticks_msec() / 1000.0)
	else:
		super._update_attack(ignore_module_lock)


func _update_debug_effects() -> void:
	if not remote_controlled:
		super._update_debug_effects()


func _update_shotgun_reload_input() -> void:
	if not remote_controlled:
		super._update_shotgun_reload_input()


func _camera_impulse(duration: float, strength: float) -> void:
	if not remote_controlled:
		super._camera_impulse(duration, strength)


func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if not authoritative or (attack_id != "" and _network_hits.has(attack_id)):
		return 0.0
	if is_instance_valid(controller) and str(controller.get("_phase")) != "live":
		return 0.0
	if attack_id != "":
		_network_hits[attack_id] = true
	var effective := super.take_damage(amount, source_id, attack_id)
	if effective > 0.0 and is_instance_valid(opponent):
		opponent.call("_on_damage_dealt", effective)
	return effective


func _on_network_damage(amount: float, source: String, _attack_id: String) -> void:
	# Burn ticks call CombatState directly; ordinary impacts are credited above.
	if authoritative and source.begins_with("player:") and is_instance_valid(opponent):
		opponent.call("_on_damage_dealt", amount)


func apply_burn(duration: float = COMBAT_DATA.BURN_DURATION, damage_per_second: float = COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	if authoritative:
		super.apply_burn(duration, damage_per_second, source_id)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	if authoritative:
		super.apply_slow(duration, percent, source_id)


func apply_stun(duration: float, source_id: String = "") -> void:
	if authoritative:
		super.apply_stun(duration, source_id)


func apply_spotted(duration: float, source_id: String = "") -> void:
	if authoritative:
		super.apply_spotted(duration, source_id)


func apply_javelin_mark(duration: float, _source_id: String = "") -> void:
	if authoritative:
		_mark_until = Time.get_ticks_msec() / 1000.0 + duration


func has_javelin_mark() -> bool:
	return get_javelin_mark_remaining() > 0.0 and not is_real_dead()


func get_javelin_mark_remaining() -> float:
	return maxf(0.0, _mark_until - Time.get_ticks_msec() / 1000.0)


func clear_javelin_mark() -> void:
	_mark_until = -1.0


func reset_combat_state() -> void:
	_network_hits.clear()
	_contact_started_at = -1.0
	_mark_until = -1.0
	super.reset_combat_state()


func begin_touch_fire() -> void:
	var was_active := _touch_fire_active
	super.begin_touch_fire()
	if _touch_fire_active and not was_active:
		_notify("contact")


func cancel_touch_fire(reason: String = "") -> void:
	var was_active := _touch_fire_active or _blaster_charge_active or _contact_started_at >= 0.0
	super.cancel_touch_fire(reason)
	_contact_started_at = -1.0
	if was_active:
		_notify("cancel")


func clear_touch_inputs() -> void:
	var was_touch_active := _touch_fire_active
	super.clear_touch_inputs()
	if was_touch_active:
		_contact_started_at = -1.0
		_notify("cancel")


func _begin_blaster_charge(now: float = -1.0) -> void:
	var was_active := _blaster_charge_active
	super._begin_blaster_charge(now)
	if _blaster_charge_active and not was_active:
		_notify("charge")


func _fire_blaster_projectile(damage: float, charge_ratio: float, direction: Vector3, action_token: int = 0) -> void:
	var token := _blaster_attack_token
	super._fire_blaster_projectile(damage, charge_ratio, direction, action_token)
	if token != _blaster_attack_token:
		_notify("blaster", {"ratio": charge_ratio})


func _perform_shotgun_attack() -> void:
	var token := _shotgun_attack_token
	super._perform_shotgun_attack()
	if token != _shotgun_attack_token:
		_notify("shotgun")


func _perform_modulo_drone() -> void:
	var token := _module_token
	super._perform_modulo_drone()
	if token != _module_token:
		_notify("offensive")


func _perform_javelin() -> void:
	var token := _javelin_launch_token
	super._perform_javelin()
	if token != _javelin_launch_token:
		_notify("offensive")


func _recast_javelin(preferred_destination: Vector3 = Vector3.INF) -> void:
	var previous := global_position
	super._recast_javelin(preferred_destination)
	if previous.distance_squared_to(global_position) > 0.001:
		_notify("javelin_recast", {"origin": previous})


func _perform_magnetic_field() -> void:
	var token := _module_token
	super._perform_magnetic_field()
	if token != _module_token:
		_notify("defensive")


func _perform_static_shield() -> void:
	var previous := _stasis_remaining
	super._perform_static_shield()
	if _stasis_remaining > previous:
		_notify("defensive")


func _perform_pyro_boots(direction_override: Vector3 = Vector3.ZERO) -> void:
	var token := _dash_token
	super._perform_pyro_boots(direction_override)
	if token != _dash_token:
		_notify("mobility", {"move": _dash_direction})


func _perform_bio_injector() -> void:
	var previous := _bio_remaining
	super._perform_bio_injector()
	if _bio_remaining > previous:
		_notify("mobility")


func _start_shotgun_reload() -> void:
	var token := _shotgun_reload_token
	super._start_shotgun_reload()
	if token != _shotgun_reload_token:
		_notify("reload")


func set_weapon(weapon_id: String) -> void:
	var previous := _weapon_id
	super.set_weapon(weapon_id)
	if previous != _weapon_id:
		_notify("weapon", {"weapon": _weapon_id})


func receive_action(action: String, data: Dictionary, visual_only := false) -> void:
	if not _gameplay_enabled or is_real_dead():
		return
	if action == "contact":
		_contact_started_at = Time.get_ticks_msec() / 1000.0
		return
	if action == "cancel":
		_replaying = visual_only
		cancel_touch_fire()
		_replaying = false
		return
	if not visual_only and (_stasis_remaining > 0.0 or combat_state.is_stunned()):
		return
	_replaying = visual_only
	if visual_only:
		received_actions += 1
		# Snapshots can precede a reliable action. Accepted visual events must not
		# be suppressed by the cooldown they themselves started on the host.
		_module_cooldowns.clear()
		_module_busy = false
		_stasis_remaining = 0.0
		_shotgun_attack_busy = false
		_shotgun_reloading = false
		_shotgun_ammo = maxi(1, _shotgun_ammo)
		_blaster_next_attack_ready_at = 0.0
	match action:
		"charge": _begin_blaster_charge(_contact_started_at if not visual_only and _contact_started_at >= 0.0 else -1.0)
		"blaster":
			var ratio := float(data.get("ratio", 0.0)) if visual_only else 0.0
			if not visual_only:
				var started := _blaster_charge_started_at if _blaster_charge_active else _contact_started_at
				if started >= 0.0:
					var duration := maxf(0.0, Time.get_ticks_msec() / 1000.0 - started)
					ratio = duration / _blaster_charge_time if _blaster_charge_active or duration >= mobile_blaster_charge_threshold else 0.0
			ratio = clampf(ratio, 0.0, 1.0)
			_contact_started_at = -1.0
			_cancel_blaster_charge()
			_fire_blaster_projectile(lerpf(_blaster_damage, _blaster_max_damage, ratio), ratio, aim_direction)
		"shotgun": _perform_shotgun_attack()
		"offensive": _perform_offensive_module()
		"defensive": _perform_defensive_module()
		"mobility":
			var move: Vector3 = data.get("move", Vector3.ZERO)
			if move.is_finite() and move.length_squared() > 0.001:
				_last_move_direction = move.normalized()
			_perform_mobility_module()
		"reload": _start_shotgun_reload()
		"weapon": set_weapon(str(data.get("weapon", "")))
		"javelin_recast":
			if visual_only:
				global_position = data.get("position", global_position)
				_create_teleport_fx(global_position)
			else:
				_recast_javelin()
	_replaying = false


func network_snapshot() -> Dictionary:
	return {"combat": combat_state.snapshot(), "position": global_position, "aim": aim_direction,
		"velocity": _get_actual_move_velocity(), "weapon": _weapon_id,
		"cooldowns": _module_cooldowns.duplicate(), "ammo": _shotgun_ammo,
		"reload": _shotgun_reload_remaining, "stasis": _stasis_remaining, "bio": _bio_remaining,
		"baroud_active": passive_state.baroud_active, "baroud_used": passive_state.baroud_used,
		"baroud_health": passive_state.baroud_health, "baroud_remaining": passive_state.baroud_remaining,
		"real_dead": passive_state.real_dead, "mark": get_javelin_mark_remaining(),
		"reveal": visibility_state.combat_remaining, "spotted": visibility_state.spotted_remaining}


func receive_snapshot(value: Dictionary, controls_confirmed := true) -> void:
	if authoritative:
		return
	var was_dead := is_real_dead()
	var previous_health := get_health()
	combat_state.receive_snapshot(value.combat)
	if get_health() < previous_health:
		flash_impact(false)
		if not remote_controlled:
			get_node("/root/GameSfx").play_event("damage_received")
	passive_state.baroud_active = bool(value.baroud_active)
	passive_state.baroud_used = bool(value.baroud_used)
	passive_state.baroud_health = float(value.baroud_health)
	passive_state.baroud_remaining = float(value.baroud_remaining)
	passive_state.real_dead = bool(value.real_dead)
	if remote_controlled or controls_confirmed:
		_stasis_remaining = float(value.stasis)
		_bio_remaining = float(value.bio)
	_mark_until = Time.get_ticks_msec() / 1000.0 + float(value.mark)
	visibility_state.combat_remaining = float(value.reveal)
	visibility_state.spotted_remaining = float(value.spotted)
	if remote_controlled or controls_confirmed:
		# Weapon changes reset ammunition, so apply the confirmed weapon first.
		_replaying = true
		set_weapon(str(value.weapon))
		_replaying = false
		_module_cooldowns = value.cooldowns.duplicate()
		_shotgun_ammo = int(value.ammo)
		_shotgun_reload_remaining = float(value.reload)
		_shotgun_reloading = _shotgun_reload_remaining > 0.0
		if is_instance_valid(_magnetic_wall) and get_module_cooldown("magnetic_field") <= 0.0:
			_magnetic_wall.queue_free()
			_magnetic_wall = null
		if is_instance_valid(_stasis_visual) and _stasis_remaining <= 0.0:
			_stasis_visual.queue_free()
			_stasis_visual = null
	if is_instance_valid(opponent) and opponent.call("has_javelin_mark") and _offensive_module_id == "javelin":
		_javelin_mark_target = opponent
	if is_real_dead() and not was_dead:
		_on_state_died()


func update_remote_visibility() -> void:
	if not remote_controlled:
		return
	var show := is_visible_to(opponent)
	for node in [_robot_visuals, _world_ui_anchor, _status_vfx]:
		if node != null:
			node.visible = show
