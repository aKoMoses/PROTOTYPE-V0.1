extends "res://scripts/player.gd"

## The ordinary combat controller is used for both humans. Remote input is
## explicit; only host actors can change health or apply an on-hit effect.
const NETWORK_STATE := preload("res://scripts/network_combat_state.gd")
const VISIBILITY_FADE := preload("res://scripts/visibility_fade.gd")
const VISIBILITY_ECHO := preload("res://scripts/visibility_echo.gd")

class ReplicaPassive extends "res://scripts/passive_state.gd":
	func process(delta: float) -> bool:
		tick_triggers(delta)
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
var _permutation_revision := 0
var _visibility_fade: Node
var _visibility_echo: Node3D
var _presentation_visibility_weight := 1.0
var _presentation_silhouette := 0.0
var _last_observation_visible := false
var _presentation_observer_epoch := -1


func _ready() -> void:
	super._ready()
	_counter.authoritative = authoritative
	_counter.exploded.connect(_on_counter_exploded)
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
	if remote_controlled:
		_visibility_fade = VISIBILITY_FADE.new()
		_visibility_fade.name = "VisibilityFade"
		add_child(_visibility_fade)
		_visibility_fade.call("configure", [_visual_rig, _world_ui_anchor, _status_vfx])
		_visibility_echo = VISIBILITY_ECHO.new()
		_visibility_echo.name = "VisibilityEcho"
		add_child(_visibility_echo)
		_visibility_echo.call("configure", _visual_rig)


func get_tracker_locations() -> Array[Node3D]:
	if not authoritative:
		var result: Array[Node3D] = []
		if is_instance_valid(opponent) and passive_state.replica_reveal_remaining > 0.0:
			result.append(opponent)
		return result
	return super.get_tracker_locations()


func passive_authoritative() -> bool:
	return authoritative


func _notify(action: String, data: Dictionary = {}) -> void:
	if not _replaying and is_instance_valid(controller):
		controller.call("on_actor_action", self, action, data)


func _uses_local_feedback() -> bool:
	return not remote_controlled


func _mark_combat_event() -> void:
	if not remote_controlled:
		super._mark_combat_event()
	elif visibility_state != null:
		visibility_state.mark_combat_event()


func _update_bush_presentation() -> void:
	if remote_controlled:
		if _bush_status_label != null:
			_bush_status_label.visible = false
		return
	super._update_bush_presentation()
	if _bush_status_label != null and _bush_status_label.visible and not is_revealed() and is_instance_valid(opponent) and not bool(opponent.call("is_real_dead")) and BUSH_STATE.shares_bush(self, opponent) and is_visible_to(opponent):
		_bush_status_label.text = "DÉTECTÉ"
		_bush_status_label.modulate = Color("#ffc77a")
		_visual_rig.set_bush_concealed(false)


func _module_target() -> Node:
	return opponent if is_instance_valid(opponent) else null


func _update_aim() -> void:
	if not remote_controlled:
		super._update_aim()


func _update_movement(delta: float) -> void:
	if is_eclipse_travelling():
		velocity = Vector3.ZERO
		return
	if not remote_controlled:
		super._update_movement(delta)
	else:
		if _fulguro_projection_active:
			_update_fulguro_projection(delta)
			return
		var melee_owns_movement := _update_mekatana_attack(delta)
		if _dash_active and not melee_owns_movement:
			_update_dash(delta)


func _get_actual_move_velocity() -> Vector3:
	if is_eclipse_travelling():
		return Vector3.ZERO
	if remote_controlled and (_stasis_remaining > 0.0 or combat_state.is_stunned() or is_real_dead()):
		return Vector3.ZERO
	return remote_velocity if remote_controlled and not _fulguro_projection_active and not _dash_active and not _mekatana_movement_owned else super._get_actual_move_velocity()


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
	if is_eclipse_travelling():
		return 0.0
	if not authoritative or (attack_id != "" and _network_hits.has(attack_id)):
		return 0.0
	if is_instance_valid(controller) and str(controller.get("_phase")) != "live":
		return 0.0
	if attack_id != "":
		_network_hits[attack_id] = true
	var effective := super.take_damage(amount, source_id, attack_id)
	if effective > 0.0 and source_id != "surcharge" and is_instance_valid(opponent):
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


func apply_javelin_mark(duration: float, source_id: String = "") -> void:
	if authoritative:
		_mark_until = Time.get_ticks_msec() / 1000.0 + maxf(0.0, duration)
		apply_spotted(maxf(0.0, duration), source_id)


func has_javelin_mark() -> bool:
	return get_javelin_mark_remaining() > 0.0 and not is_real_dead()


func get_javelin_mark_remaining() -> float:
	return maxf(0.0, _mark_until - Time.get_ticks_msec() / 1000.0)


func clear_javelin_mark() -> void:
	_mark_until = -1.0


func reset_combat_state() -> void:
	_permutation_revision = 0
	_network_hits.clear()
	_contact_started_at = -1.0
	_mark_until = -1.0
	super.reset_combat_state()
	_last_observation_visible = false
	_presentation_observer_epoch = -1
	if _visibility_fade != null:
		_visibility_fade.call("restore")
	if _visibility_echo != null:
		_visibility_echo.call("reset")


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


func _can_apply_mekatana_damage() -> bool:
	return authoritative


func _perform_mekatana_attack() -> void:
	var was_busy: bool = _mekatana_attack.is_busy()
	super._perform_mekatana_attack()
	if not was_busy and _mekatana_attack.is_busy():
		_notify("mekatana", {"step": _mekatana_attack.step})


func _perform_longshot_attack() -> void:
	var token := _longshot_attack_token
	super._perform_longshot_attack()
	if not authoritative and token != _longshot_attack_token:
		_notify("longshot")


func _on_longshot_emitted(enhanced: bool, shot_number: int) -> void:
	if authoritative:
		_notify("longshot_fired", {"enhanced": enhanced, "shot_number": shot_number})


func _play_network_longshot(data: Dictionary) -> void:
	_begin_weapon_fire()
	if _has_skeletal_weapon_attachment():
		await _visual_rig.skeleton.skeleton_updated
		if not _gameplay_enabled or is_real_dead():
			return
	# The reliable event is visual only. Snapshots own the cycle, so a snapshot
	# arriving first cannot turn this into a second fifth shot.
	_spawn_longshot_projectile(bool(data.get("enhanced", false)), int(data.get("shot_number", 1)), true)


func _perform_rocket_basket() -> void:
	var token := _module_token
	super._perform_rocket_basket()
	if token != _module_token:
		_notify("offensive")


func _begin_javelin_charge() -> bool:
	var was_charging := is_javelin_charging()
	var accepted := super._begin_javelin_charge()
	if not was_charging and is_javelin_charging():
		_notify("javelin_charge")
	return accepted


func _perform_pelto_smash(aim_held: bool = false) -> void:
	var serial := _pelto_attack_serial
	super._perform_pelto_smash(aim_held)
	if serial != _pelto_attack_serial:
		_notify("pelto_begin", {"held": aim_held})


func _release_pelto_aim() -> void:
	var releasing := is_pelto_preparing() and _pelto_aim_held and not _pelto_release_requested
	super._release_pelto_aim()
	if releasing:
		_notify("pelto_release")


func _cancel_pelto_smash(reason: String = "") -> void:
	var was_preparing := is_pelto_preparing()
	super._cancel_pelto_smash(reason)
	if was_preparing:
		_notify("pelto_cancel")


func _release_javelin_charge() -> void:
	var releasing := is_javelin_charging() and _javelin_release_at < 0.0
	super._release_javelin_charge()
	if releasing:
		_notify("javelin_release")


func _cancel_javelin_charge() -> void:
	var was_charging := is_javelin_charging()
	super._cancel_javelin_charge()
	if was_charging:
		_notify("javelin_cancel")


func _recast_javelin(preferred_destination: Vector3 = Vector3.INF) -> void:
	var previous := global_position
	super._recast_javelin(preferred_destination)
	if previous.distance_squared_to(global_position) > 0.001:
		_notify("javelin_recast", {"origin": previous})


func _projector_authoritative() -> bool:
	return authoritative


func _perform_projector() -> bool:
	var accepted := super._perform_projector()
	if accepted and not authoritative:
		_notify("defensive")
	return accepted


func _on_projector_activated() -> void:
	_notify("projector_pulse", {"origin": global_position})


func _on_projector_cast_started() -> void:
	if authoritative:
		_notify("projector_cast", {})


func start_fulguro_projection(direction: Vector3, distance: float, duration: float, wall_damage: float, wall_stun: float, source_id: String, attack_id: String) -> void:
	super.start_fulguro_projection(direction, distance, duration, wall_damage, wall_stun, source_id, attack_id)
	if authoritative and _fulguro_projection_active:
		_permutation_revision += 1


func _finish_fulguro_projection(crushed_wall: bool, impact_position: Vector3 = Vector3.ZERO, impact_normal: Vector3 = Vector3.ZERO) -> void:
	var was_active := _fulguro_projection_active
	super._finish_fulguro_projection(crushed_wall, impact_position, impact_normal)
	if authoritative and was_active:
		_permutation_revision += 1


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


func _perform_counter() -> bool:
	var accepted := super._perform_counter()
	if accepted:
		_notify("defensive")
	return accepted


func _on_counter_exploded(center: Vector3) -> void:
	if authoritative:
		_notify("counter_explosion", {"center": center})


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


func _credit_eclipse_damage(_amount: float) -> void:
	# Network victim.take_damage already credits its opponent's omnivamp.
	pass


func _perform_eclipse(destination: Vector3) -> bool:
	var accepted := super._perform_eclipse(destination)
	if accepted:
		_notify("eclipse", {"destination": destination})
	return accepted


func _permutation_authoritative() -> bool:
	return authoritative


func _perform_permutation() -> void:
	var token := _module_token
	super._perform_permutation()
	if _module_token != token:
		_notify("permutation")


func on_permutation_relocated() -> void:
	super.on_permutation_relocated()
	if authoritative:
		_permutation_revision += 1


func receive_permutation_relocation(at: Vector3, revision: int) -> bool:
	if authoritative or revision <= _permutation_revision or not at.is_finite():
		return false
	_permutation_revision = revision
	global_position = at
	super.on_permutation_relocated()
	PERMUTATION.refresh_sweeps(get_tree())
	return true


func _on_permutation_arrived(origin: Vector3, destination: Vector3) -> void:
	super._on_permutation_arrived(origin, destination)
	if authoritative and is_instance_valid(opponent):
		_notify("permutation_swap", {"target_position": opponent.global_position,
			"caster_revision": _permutation_revision, "target_revision": opponent.get("_permutation_revision")})


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
	if action == "counter_explosion":
		if visual_only and not authoritative:
			COUNTER.spawn_ring(get_tree().current_scene, data.get("center", global_position), float(COMBAT_DATA.MODULE_DEFINITIONS.counter.surcharge_radius))
		return
	if action == "projector_cast":
		if visual_only and not authoritative and _projector_cast_token == 0:
			PROJECTOR.spawn_cast(self, float(COMBAT_DATA.MODULE_DEFINITIONS.projector.cast_duration))
		return
	if action == "projector_pulse":
		if visual_only and not authoritative:
			PROJECTOR.spawn_visual(get_tree().current_scene, data.get("origin", global_position))
		return
	if action == "contact":
		_contact_started_at = Time.get_ticks_msec() / 1000.0
		return
	if action == "cancel":
		_replaying = visual_only
		_cancel_longshot_attack()
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
		if action == "mekatana":
			_cancel_mekatana_attack()
			_action_gate.reset()
			_mekatana_attack.next_step = clampi(int(data.get("step", 0)), 0, 2)
			_mekatana_attack.combo_remaining = float(COMBAT_DATA.WEAPON_DEFINITIONS.mekatana.combo_window)
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
		"mekatana": _perform_mekatana_attack()
		"longshot":
			if not visual_only:
				# Host determines the fifth shot from its own instance, never client data.
				_perform_longshot_attack()
		"longshot_fired":
			if visual_only:
				_play_network_longshot(data)
		"offensive": _perform_offensive_module()
		"javelin_charge":
			if _offensive_module_id == "javelin":
				_begin_javelin_charge()
		"javelin_release": _release_javelin_charge()
		"javelin_cancel": _cancel_javelin_charge()
		"pelto_begin":
			if _offensive_module_id == "pelto_smash":
				_perform_pelto_smash(bool(data.get("held", false)))
		"pelto_release": _release_pelto_aim()
		"pelto_cancel": _cancel_pelto_smash()
		"permutation": _perform_permutation()
		"eclipse":
			var destination: Variant = data.get("destination")
			if destination is Vector3 and destination.is_finite():
				_perform_eclipse(destination)
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
	return {"rockets": ROCKET_BASKET.snapshot(self), "counter": _counter.snapshot(),"combat": combat_state.snapshot(), "position": global_position, "aim": aim_direction,
		"projector_passive": _projector_passive_remaining,
		"knockback": {"active": _fulguro_projection_active, "direction": _fulguro_projection_direction, "distance": _fulguro_projection_distance_remaining, "time": _fulguro_projection_time_remaining},
		"eclipse": _eclipse.snapshot(),
		"javelin_mark_duration": _javelin_active_mark_duration, "javelin_recast_range": _javelin_active_recast_range,
		"relocation": _permutation_revision, "permutation_speed": _permutation_speed_remaining,
		"mekatana": _mekatana_attack.presentation_snapshot(),
		"velocity": _get_actual_move_velocity(), "weapon": _weapon_id,
		"cooldowns": _module_cooldowns.duplicate(), "ammo": _shotgun_ammo,
		"longshot_shots": _longshot_state.shots_fired,
		"longshot_recovery": maxf(0.0, _longshot_next_attack_ready_at - Time.get_ticks_msec() / 1000.0),
		"reload": _shotgun_reload_remaining, "stasis": _stasis_remaining, "bio": _bio_remaining,
		"baroud_active": passive_state.baroud_active, "baroud_used": passive_state.baroud_used,
		"baroud_health": passive_state.baroud_health, "baroud_remaining": passive_state.baroud_remaining,
		"passive_status": passive_state.snapshot(), "real_dead": passive_state.real_dead, "mark": get_javelin_mark_remaining(),
		"reveal": visibility_state.combat_remaining, "spotted": visibility_state.spotted_remaining}


func receive_snapshot(value: Dictionary, controls_confirmed := true) -> void:
	if authoritative:
		return
	ROCKET_BASKET.receive_snapshot(self, value.get("rockets", []))
	_projector_passive_remaining = maxf(0.0, float(value.get("projector_passive", 0.0)))
	var eclipse_needs_correction := is_eclipse_travelling() or int(value.get("eclipse", {}).get("serial", 0)) != _eclipse.serial
	receive_permutation_relocation(value.get("position", global_position), int(value.get("relocation", 0)))
	if value.has("knockback"):
		var recoil: Dictionary = value.knockback
		if bool(recoil.get("active", false)):
			if not _fulguro_projection_active:
				super.start_fulguro_projection(recoil.direction, float(recoil.distance), float(recoil.time), 0.0, 0.0, "network_knockback", "")
			_fulguro_projection_direction = recoil.direction
			_fulguro_projection_distance_remaining = maxf(0.0, float(recoil.distance))
			_fulguro_projection_time_remaining = maxf(0.0, float(recoil.time))
			_fulguro_projection_speed = KNOCKBACK.speed(_fulguro_projection_distance_remaining, _fulguro_projection_time_remaining)
			global_position = value.get("position", global_position)
		elif _fulguro_projection_active:
			_cancel_fulguro_projection()
			global_position = value.get("position", global_position)
	if remote_controlled or controls_confirmed:
		_eclipse.receive_snapshot(self, value.get("eclipse", {}))
		if eclipse_needs_correction and not is_eclipse_travelling() and value.has("eclipse"):
			global_position = value.get("position", global_position)
	_permutation_speed_remaining = maxf(0.0, float(value.get("permutation_speed", 0.0)))
	if remote_controlled or controls_confirmed:
		_counter.restore(value.get("counter", {}))
	if _counter.phase != "" and not _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		_interrupt_weapon_for_module()
		_action_gate.reset()
		_active_module_action_token = _action_gate.try_acquire(ACTION_GATE.Kind.MODULE, "counter", -1, true)
		_active_module_id = "counter"
	elif _counter.phase == "":
		_on_counter_finished()
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
	passive_state.restore_snapshot(value.get("passive_status", {}))
	if remote_controlled or controls_confirmed:
		_stasis_remaining = float(value.stasis)
		_bio_remaining = float(value.bio)
		_javelin_active_mark_duration = float(value.get("javelin_mark_duration", _javelin_mark_duration))
		_javelin_active_recast_range = float(value.get("javelin_recast_range", _javelin_max_range))
	_mark_until = Time.get_ticks_msec() / 1000.0 + float(value.mark)
	visibility_state.combat_remaining = float(value.reveal)
	visibility_state.spotted_remaining = float(value.spotted)
	if remote_controlled or controls_confirmed:
		# Weapon changes reset ammunition, so apply the confirmed weapon first.
		_replaying = true
		set_weapon(str(value.weapon))
		_replaying = false
		if value.has("mekatana") and _weapon_id == "mekatana":
			_mekatana_attack.damage_enabled = false
			_mekatana_attack.restore_presentation(value.mekatana)
			if _mekatana_attack.is_busy():
				if not _action_gate.owns(_mekatana_action_token, ACTION_GATE.Kind.WEAPON, "mekatana"):
					_action_gate.reset()
					_mekatana_action_token = _action_gate.try_acquire(ACTION_GATE.Kind.WEAPON, "mekatana")
			else:
				_action_gate.release(_mekatana_action_token)
				_mekatana_action_token = 0
			_sync_mekatana_pose()
		_module_cooldowns = value.cooldowns.duplicate()
		_shotgun_ammo = int(value.ammo)
		_shotgun_reload_remaining = float(value.reload)
		_shotgun_reloading = _shotgun_reload_remaining > 0.0
		_longshot_state.shots_fired = maxi(0, int(value.get("longshot_shots", 0)))
		_longshot_next_attack_ready_at = Time.get_ticks_msec() / 1000.0 + maxf(0.0, float(value.get("longshot_recovery", 0.0)))
		_sync_weapon_readout()
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
	_update_bush_presentation()


func get_presentation_visibility_weight() -> float:
	return _presentation_visibility_weight


func update_remote_visibility(delta: float = 0.0) -> void:
	if not remote_controlled:
		return
	var observer_epoch := int(opponent.call("get_visibility_epoch")) if is_instance_valid(opponent) else -1
	if observer_epoch != _presentation_observer_epoch:
		_presentation_observer_epoch = observer_epoch
		_last_observation_visible = false
		_visibility_echo.call("reset")
	var raw_weight := get_visibility_weight(opponent)
	var show := raw_weight > 0.0
	var display_weight := raw_weight
	if show and is_instance_valid(opponent):
		var offset := global_position - opponent.global_position
		display_weight = VISIBILITY_STATE.silhouette_visibility(Vector2(offset.x, offset.z).length(), VISIBILITY_STATE.observer_radius(opponent), VISIBILITY_STATE.observer_fade_width(opponent))
	var silhouette := 1.0 - smoothstep(0.12, 0.95, raw_weight)
	if delta <= 0.0 or not show:
		_presentation_visibility_weight = display_weight
		_presentation_silhouette = silhouette
	else:
		_presentation_visibility_weight = move_toward(_presentation_visibility_weight, display_weight, delta / 0.18)
		_presentation_silhouette = move_toward(_presentation_silhouette, silhouette, delta / 0.22)
	var detail_weight := raw_weight * raw_weight
	for node in [_robot_visuals, _world_ui_anchor, _status_vfx]:
		if node != null:
			node.visible = show if node == _robot_visuals else detail_weight > 0.01
	_visibility_fade.call("apply_presentation", _presentation_visibility_weight, _presentation_silhouette, detail_weight)
	var echo_allowed := _gameplay_enabled and not is_eclipse_travelling() and not is_real_dead() and is_instance_valid(opponent) and not bool(opponent.call("is_real_dead")) and bool(opponent.call("is_gameplay_enabled"))
	if delta <= 0.0 or not echo_allowed:
		_visibility_echo.call("reset")
	if show and echo_allowed:
		_visibility_echo.call("observe", global_position)
	elif _last_observation_visible and delta > 0.0 and echo_allowed:
		_visibility_echo.call("begin_loss")
	_last_observation_visible = show and echo_allowed
