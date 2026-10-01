extends "res://scripts/player/components/player_state.gd"

# Preserve the Player API used by scenes, bots, HUD, network and test tools.
# Logic lives in focused components; this node owns their shared state and tick.
const COMPONENT_BLASTER := preload("res://scripts/player/components/blaster.gd")
const COMPONENT_COMBAT := preload("res://scripts/player/components/combat.gd")
const COMPONENT_CONTROLS := preload("res://scripts/player/components/controls.gd")
const COMPONENT_EFFECTS := preload("res://scripts/player/components/effects.gd")
const COMPONENT_FULGURO := preload("res://scripts/player/components/fulguro.gd")
const COMPONENT_LEGACY_AXE := preload("res://scripts/player/components/legacy_axe.gd")
const COMPONENT_LOADOUT := preload("res://scripts/player/components/loadout.gd")
const COMPONENT_LONGSHOT := preload("res://scripts/player/components/longshot.gd")
const COMPONENT_MEKATANA := preload("res://scripts/player/components/mekatana.gd")
const COMPONENT_PELTO := preload("res://scripts/player/components/pelto.gd")
const COMPONENT_PRESENTATION := preload("res://scripts/player/components/presentation.gd")
const COMPONENT_PROJECTILE_MODULES := preload("res://scripts/player/components/projectile_modules.gd")
const COMPONENT_SHOTGUN := preload("res://scripts/player/components/shotgun.gd")
const COMPONENT_DEFENSIVE_MODULES := preload("res://scripts/player/components/defensive_modules.gd")
const COMPONENT_MOBILITY_MODULES := preload("res://scripts/player/components/mobility_modules.gd")
const COMPONENT_UTILITY_MODULES := preload("res://scripts/player/components/utility_modules.gd")

var _blaster_component := COMPONENT_BLASTER.new(self)
var _combat_component := COMPONENT_COMBAT.new(self)
var _controls_component := COMPONENT_CONTROLS.new(self)
var _effects_component := COMPONENT_EFFECTS.new(self)
var _fulguro_component := COMPONENT_FULGURO.new(self)
var _legacy_axe_component := COMPONENT_LEGACY_AXE.new(self)
var _loadout_component := COMPONENT_LOADOUT.new(self)
var _longshot_component := COMPONENT_LONGSHOT.new(self)
var _mekatana_component := COMPONENT_MEKATANA.new(self)
var _pelto_component := COMPONENT_PELTO.new(self)
var _presentation_component := COMPONENT_PRESENTATION.new(self)
var _projectile_modules_component := COMPONENT_PROJECTILE_MODULES.new(self)
var _shotgun_component := COMPONENT_SHOTGUN.new(self)
var _defensive_modules_component := COMPONENT_DEFENSIVE_MODULES.new(self)
var _mobility_modules_component := COMPONENT_MOBILITY_MODULES.new(self)
var _utility_modules_component := COMPONENT_UTILITY_MODULES.new(self)


func _init() -> void:
	# Children share the player lifetime, including pending timer callbacks.
	for component in [
		_blaster_component,
		_combat_component,
		_controls_component,
		_effects_component,
		_fulguro_component,
		_legacy_axe_component,
		_loadout_component,
		_longshot_component,
		_mekatana_component,
		_pelto_component,
		_presentation_component,
		_projectile_modules_component,
		_shotgun_component,
		_utility_modules_component,
		_defensive_modules_component,
		_mobility_modules_component,
	]:
		add_child(component)


func _ready() -> void:
	_counter = COUNTER.ensure(self)
	_counter.finished.connect(_on_counter_finished)
	add_to_group("permutation_relocation_observers")
	get_node("/root/GamePreferences").bindings_changed.connect(_refresh_control_bindings)
	collision_layer = 4
	collision_mask = 1
	combat_state = COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH)
	add_child(preload("res://scripts/permutation_shield.gd").new())
	combat_state.health_changed.connect(_on_health_changed)
	combat_state.damage_applied.connect(_on_damage_applied)
	combat_state.healing_applied.connect(_on_healing_applied)
	combat_state.died.connect(_on_state_died)
	var passive_fx := preload("res://scripts/passive_fx.gd").new()
	passive_fx.name = "PassiveFX"
	add_child(passive_fx)
	passive_state = PASSIVE_STATE.new()
	passive_state.configure(_passive_id)
	visibility_state = VISIBILITY_STATE.new()
	_load_weapon_definitions()
	_build_collision()
	_build_robot()
	var aim_guide := WEAPON_AIM_GUIDE.new()
	aim_guide.name = "WeaponAimGuide"
	add_child(aim_guide)
	_mekatana_attack.configure(self, "player", Callable(self, "_move_mekatana_dash"))
	_mekatana_attack.slash_started.connect(_on_mekatana_slash_started)
	_mekatana_attack.hit.connect(_on_mekatana_hit)
	_mekatana_attack.finished.connect(_on_mekatana_finished)
	_status_vfx = STATUS_VFX.new()
	_status_vfx.name = "StatusVFX"
	add_child(_status_vfx)
	_status_vfx.set("marker_height", 3.30 * COMBAT_DATA.CHARACTER_VISUAL_SCALE)
	_status_vfx.call("configure", self)
	_blaster_charge_audio = AudioStreamPlayer.new()
	_blaster_charge_audio.name = "BlasterChargeAudio"
	_blaster_charge_audio.stream = BLASTER_CHARGE_SOUND
	_blaster_charge_audio.volume_db = -9.0
	add_child(_blaster_charge_audio)
	_blaster_charge_hold_audio = AudioStreamPlayer.new()
	_blaster_charge_hold_audio.name = "BlasterChargeHoldAudio"
	var hold_stream := BLASTER_CHARGE_HOLD_SOUND.duplicate() as AudioStreamWAV
	hold_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hold_stream.loop_end = roundi(hold_stream.get_length() * hold_stream.mix_rate)
	_blaster_charge_hold_audio.stream = hold_stream
	_blaster_charge_hold_audio.volume_db = -10.0
	add_child(_blaster_charge_hold_audio)
	_blaster_ready_audio = AudioStreamPlayer.new()
	_blaster_ready_audio.name = "BlasterReadyAudio"
	_blaster_ready_audio.stream = BLASTER_READY_SOUND
	_blaster_ready_audio.volume_db = -4.0
	add_child(_blaster_ready_audio)
	_blaster_shot_audio = AudioStreamPlayer.new()
	_blaster_shot_audio.name = "BlasterShotAudio"
	_blaster_shot_audio.stream = BLASTER_SHOT_SOUND
	_blaster_shot_audio.max_polyphony = 4
	_blaster_shot_audio.volume_db = -8.0
	add_child(_blaster_shot_audio)
	_blaster_charged_shot_audio = AudioStreamPlayer.new()
	_blaster_charged_shot_audio.name = "BlasterChargedShotAudio"
	_blaster_charged_shot_audio.stream = BLASTER_CHARGED_SHOT_SOUND
	_blaster_charged_shot_audio.max_polyphony = 4
	_blaster_charged_shot_audio.volume_db = -7.0
	add_child(_blaster_charged_shot_audio)
	_shotgun_shot_audio = AudioStreamPlayer.new()
	_shotgun_shot_audio.name = "ShotgunShotAudio"
	_shotgun_shot_audio.stream = SHOTGUN_SHOT_SOUND
	_shotgun_shot_audio.volume_db = -7.0
	add_child(_shotgun_shot_audio)
	_shotgun_cycle_audio = AudioStreamPlayer.new()
	_shotgun_cycle_audio.name = "ShotgunCycleAudio"
	_shotgun_cycle_audio.stream = SHOTGUN_CYCLE_SOUND
	_shotgun_cycle_audio.volume_db = -5.0
	add_child(_shotgun_cycle_audio)
	_shotgun_reload_audio = AudioStreamPlayer.new()
	_shotgun_reload_audio.name = "ShotgunReloadAudio"
	_shotgun_reload_audio.stream = SHOTGUN_RELOAD_SOUND
	_shotgun_reload_audio.volume_db = -2.0
	add_child(_shotgun_reload_audio)
	_fulguro_charge_audio = AudioStreamPlayer.new()
	_fulguro_charge_audio.name = "FulguroChargeAudio"
	_fulguro_charge_audio.stream = BLASTER_CHARGE_SOUND
	_fulguro_charge_audio.volume_db = -10.0
	_fulguro_charge_audio.pitch_scale = 1.35
	add_child(_fulguro_charge_audio)
	_fulguro_release_audio = AudioStreamPlayer.new()
	_fulguro_release_audio.name = "FulguroReleaseAudio"
	_fulguro_release_audio.stream = FULGURO_RELEASE_SOUND
	_fulguro_release_audio.volume_db = -5.0
	_fulguro_release_audio.pitch_scale = 0.88
	add_child(_fulguro_release_audio)
	_pelto_impact_audio = AudioStreamPlayer.new()
	_pelto_impact_audio.name = "PeltoImpactAudio"
	_pelto_impact_audio.stream = SHOTGUN_SHOT_SOUND
	_pelto_impact_audio.volume_db = -7.0
	_pelto_impact_audio.pitch_scale = 0.52
	add_child(_pelto_impact_audio)


func _exit_tree() -> void:
	if passive_state != null:
		passive_state.clear_triggers()
	if _counter != null:
		_counter.cancel(true)
	_eclipse.cancel(self)
	_longshot_attack_token += 1
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.reset_locomotion()
	_blaster_attack_token += 1
	_shotgun_attack_token += 1
	_module_token += 1
	_javelin_launch_token += 1
	_static_pulse_token += 1
	_action_gate.reset()


func _load_weapon_definitions() -> void:
	_loadout_component._load_weapon_definitions()


func _physics_process(delta: float) -> void:
	if not _gameplay_enabled:
		velocity = Vector3.ZERO
		clear_touch_inputs()
		return
	if visibility_state != null:
		visibility_state.update(delta)
	var baroud_expired: bool = passive_state != null and bool(passive_state.process(delta))
	if baroud_expired:
		_finalize_passive_death()
	_update_baroud_presentation()
	if passive_state != null and passive_state.real_dead:
		velocity = Vector3.ZERO
		get_node("/root/GameSfx").reset_locomotion()
		return
	var stasis_active := _stasis_remaining > 0.0
	if stasis_active:
		_cancel_mekatana_attack()
		_stasis_remaining = maxf(0.0, _stasis_remaining - delta)
	if combat_state != null:
		combat_state.update(delta, stasis_active or is_eclipse_travelling())
	if _fulguro_wall_stun_active and (combat_state == null or not combat_state.is_stunned()):
		_fulguro_wall_stun_active = false
	if _status_vfx != null:
		_status_vfx.call("sync", get_active_effect_types())
	_update_module_cooldowns(delta)
	_update_projector_cast(delta)
	if _counter != null:
		_counter.update(delta)
	if _survival_evolved("defensive") and _defensive_module_id == "magnetic_field" and _magnetic_wall != null and is_instance_valid(_magnetic_wall):
		_survival_magnetic_clock += delta
		if _survival_magnetic_clock >= 0.8:
			_survival_magnetic_clock = 0.0
			_survival_area_damage(_magnetic_wall.global_position, 3.0, 35.0, "magnetic_shock", Color("#53d9e5"))
	_update_aim()
	_eclipse.update(self, delta)
	if combat_state != null and combat_state.is_stunned() and _dash_active:
		_cancel_dash()
	if combat_state != null and combat_state.is_stunned() and _fulguro_phase != "":
		_cancel_fulguro_attack("FULGURO PUNCH  •  INTERROMPU")
	if combat_state != null and combat_state.is_stunned() and _pelto_phase != "":
		_cancel_pelto_smash("PELTO SMASH  •  INTERROMPU")
	_try_execute_defensive_buffer()
	var sound_start_position := global_position
	var sound_walking := not (_dash_active or _fulguro_projection_active or _pelto_pull_active or _stasis_remaining > 0.0)
	_update_movement(delta)
	# Sample action commands while the current cast still owns the frame. This
	# prevents a held input from slipping through on the exact recovery frame.
	_update_debug_effects()
	var cast_locked_before_action_updates := _action_gate.is_kind(ACTION_GATE.Kind.MODULE)
	_update_fulguro_attack(delta)
	_update_javelin_charge(delta)
	_update_pelto_attack(delta)
	_update_weapon_pose_state(delta)
	_update_robot_motion(delta)
	_update_world_ui_anchor()
	_update_bush_state(delta)
	if _uses_local_feedback():
		get_node("/root/GameSfx").update_locomotion(
			global_position.distance_to(sound_start_position), delta,
			_current_bush != null, sound_walking)
	_update_javelin_mark()
	if combat_state != null and combat_state.is_stunned() and (_blaster_charge_active or _touch_fire_active):
		cancel_touch_fire("BLASTER  •  INTERROMPU")
	if combat_state != null and combat_state.is_stunned() and _blaster_attack_busy:
		_cancel_blaster_attack()
	if combat_state != null and combat_state.is_stunned() and _shotgun_attack_busy:
		_cancel_shotgun_attack()
	if combat_state != null and combat_state.is_stunned() and _active_module_action_token != 0:
		_cancel_pending_module_action("MODULE  •  INTERROMPU")
	_update_shotgun_reload_input()
	_update_shotgun_reload(delta)
	_update_attack(cast_locked_before_action_updates)
	_update_weapon_ambient_motion(delta)
	_update_shotgun_reload_visual()
	_update_blaster_charge_visual(delta)
	_sync_weapon_readout()


func _update_movement(delta: float) -> void:
	_controls_component._update_movement(delta)


func _update_robot_motion(delta: float) -> void:
	_presentation_component._update_robot_motion(delta)


func _get_actual_move_velocity() -> Vector3:
	return _controls_component._get_actual_move_velocity()


func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	return _controls_component._camera_relative_direction(input_vector)


func _world_offset_to_visual_local(world_offset: Vector3) -> Vector3:
	return _presentation_component._world_offset_to_visual_local(world_offset)


func _update_weapon_ambient_motion(delta: float) -> void:
	_presentation_component._update_weapon_ambient_motion(delta)


func _update_aim() -> void:
	_controls_component._update_aim()


func _aim_at_screen_position(mouse_position: Vector2, camera: Camera3D) -> void:
	_controls_component._aim_at_screen_position(mouse_position, camera)


func _set_aim_direction(direction: Vector3) -> void:
	_controls_component._set_aim_direction(direction)


func _normalized_aim_direction() -> Vector3:
	return _controls_component._normalized_aim_direction()


func get_weapon_aim_preview() -> Dictionary:
	return _controls_component.get_weapon_aim_preview()


func _weapon_pose_uses_aim() -> bool:
	return _controls_component._weapon_pose_uses_aim()


func get_weapon_pose_state_name() -> StringName:
	return _controls_component.get_weapon_pose_state_name()


func _set_weapon_pose_state(next_state: WeaponPoseState, restart_hold: bool = false) -> void:
	_controls_component._set_weapon_pose_state(next_state, restart_hold)


func _begin_weapon_aim() -> void:
	_controls_component._begin_weapon_aim()


func _begin_weapon_fire() -> void:
	_controls_component._begin_weapon_fire()


func _begin_aim_hold() -> void:
	_controls_component._begin_aim_hold()


func _reset_weapon_pose_to_locomotion(immediate: bool = false) -> void:
	_controls_component._reset_weapon_pose_to_locomotion(immediate)


func _update_weapon_pose_state(delta: float) -> void:
	_controls_component._update_weapon_pose_state(delta)


func _input(event: InputEvent) -> void:
	# Releases can arrive over a GUI control after a valid combat press.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and not event.pressed:
		_desktop_mouse_attack_held = false


func _unhandled_input(event: InputEvent) -> void:
	# Touch-to-mouse emulation is needed by menus, but must never create a
	# second combat command. GUI presses also stop before this input stage.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and event.pressed:
		if _gameplay_enabled and not get_tree().paused and not is_real_dead():
			_desktop_mouse_attack_held = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _eclipse != null and _eclipse.aiming:
		_eclipse.cancel(self)
	# The local window cannot cancel the other human's authoritative input.
	if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED) and _uses_local_feedback():
		reset_desktop_inputs()


func reset_desktop_inputs() -> void:
	_controls_component.reset_desktop_inputs()


func _desktop_attack_input_held() -> bool:
	return _controls_component._desktop_attack_input_held()


func _action_incapacitated() -> bool:
	return _controls_component._action_incapacitated()


func _try_begin_weapon_action(action_id: String) -> int:
	return _controls_component._try_begin_weapon_action(action_id)


func _try_begin_module_action(module_id: String) -> int:
	return _controls_component._try_begin_module_action(module_id)


func _interrupt_weapon_for_module() -> void:
	_controls_component._interrupt_weapon_for_module()


func _module_action_can_execute(action_token: int, module_id: String) -> bool:
	return _controls_component._module_action_can_execute(action_token, module_id)


func _end_module_action(action_token: int, module_id: String) -> bool:
	return _controls_component._end_module_action(action_token, module_id)


func _cancel_pending_module_action(reason: String = "") -> void:
	_controls_component._cancel_pending_module_action(reason)


func _reset_action_ownership() -> void:
	_controls_component._reset_action_ownership()


func get_action_owner() -> String:
	return _controls_component.get_action_owner()


func _update_attack(force_action_blocked: bool = false) -> void:
	_controls_component._update_attack(force_action_blocked)


func _update_active_blaster_charge(now: float) -> void:
	_controls_component._update_active_blaster_charge(now)


func _update_mobile_blaster_contact(now: float) -> void:
	_controls_component._update_mobile_blaster_contact(now)


func _process_touch_fire_request() -> void:
	_controls_component._process_touch_fire_request()


func _update_debug_effects() -> void:
	_controls_component._update_debug_effects()


func _refresh_control_bindings() -> void:
	_controls_component._refresh_control_bindings()


func _pressed_action_once(action: String) -> bool:
	return _controls_component._pressed_action_once(action)


func _pressed_once(keycode: Key) -> bool:
	return _controls_component._pressed_once(keycode)


func set_touch_move_vector(value: Vector2) -> void:
	_controls_component.set_touch_move_vector(value)


func set_touch_aim_vector(value: Vector2) -> void:
	_controls_component.set_touch_aim_vector(value)


func set_move_input(value: Vector2) -> void:
	_controls_component.set_move_input(value)


func set_aim_input(value: Vector2) -> void:
	_controls_component.set_aim_input(value)


func set_touch_attack_held(value: bool) -> void:
	_controls_component.set_touch_attack_held(value)


func begin_touch_fire() -> void:
	_controls_component.begin_touch_fire()


func end_touch_fire(final_aim: Vector2 = Vector2.ZERO) -> bool:
	return _controls_component.end_touch_fire(final_aim)


func cancel_touch_fire(reason: String = "") -> void:
	_controls_component.cancel_touch_fire(reason)


static func mobile_blaster_release_ratio(hold_seconds: float, charge_threshold: float, charge_time: float) -> float:
	if hold_seconds < maxf(0.0, charge_threshold):
		return 0.0
	return clampf(hold_seconds / maxf(0.001, charge_time), 0.0, 1.0)


func get_mobile_blaster_input_state() -> StringName:
	return _controls_component.get_mobile_blaster_input_state()


func trigger_touch_action(action: String) -> bool:
	return _controls_component.trigger_touch_action(action)


func begin_touch_action(action: String) -> bool:
	return _controls_component.begin_touch_action(action)


func end_touch_action(action: String) -> void:
	_controls_component.end_touch_action(action)


func cancel_touch_action(action: String) -> void:
	_controls_component.cancel_touch_action(action)


func clear_touch_inputs() -> void:
	_controls_component.clear_touch_inputs()


func set_gameplay_enabled(value: bool) -> void:
	_controls_component.set_gameplay_enabled(value)


func is_gameplay_enabled() -> bool:
	return _controls_component.is_gameplay_enabled()


func _consume_touch_action(action: String) -> bool:
	return _controls_component._consume_touch_action(action)


func _mark_combat_event() -> void:
	_combat_component._mark_combat_event()


func get_combat_reveal_remaining() -> float:
	return _combat_component.get_combat_reveal_remaining()


func get_spotted_reveal_remaining() -> float:
	return _combat_component.get_spotted_reveal_remaining()


func is_revealed() -> bool:
	return _combat_component.is_revealed()


func is_attack_committed() -> bool:
	return _combat_component.is_attack_committed()


func is_in_bush() -> bool:
	return _combat_component.is_in_bush()


func get_current_bush_name() -> String:
	return _combat_component.get_current_bush_name()


func get_current_bush() -> Node3D:
	return _combat_component.get_current_bush()


func is_bush_concealed() -> bool:
	return _combat_component.is_bush_concealed()


func get_bush_transition_clock() -> float:
	return _combat_component.get_bush_transition_clock()


func is_visible_to(observer: Node3D) -> bool:
	return _combat_component.is_visible_to(observer)


func get_vision_radius() -> float:
	return _combat_component.get_vision_radius()


func get_vision_fade_width() -> float:
	return _combat_component.get_vision_fade_width()


func get_visibility_epoch() -> int:
	return _combat_component.get_visibility_epoch()


func get_visibility_weight(observer: Node3D) -> float:
	return _combat_component.get_visibility_weight(observer)


func _update_bush_state(delta: float) -> void:
	_combat_component._update_bush_state(delta)


func _sync_bush_state() -> void:
	_combat_component._sync_bush_state()


func _uses_local_feedback() -> bool:
	return _combat_component._uses_local_feedback()


func _find_bush_at_position() -> Node3D:
	return _combat_component._find_bush_at_position()


func _update_bush_presentation() -> void:
	_combat_component._update_bush_presentation()


func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	return _combat_component.take_damage(amount, source_id, attack_id)


func flash_impact(critical: bool = false) -> void:
	_presentation_component.flash_impact(critical)


func _clear_player_impact_material(_unused: float = 0.0) -> void:
	_presentation_component._clear_player_impact_material(_unused)


func _vfx_manager() -> Node:
	return _effects_component._vfx_manager()


func _camera_impulse(duration: float, strength: float) -> void:
	_effects_component._camera_impulse(duration, strength)


func _create_muzzle_burst(_origin: Vector3, _direction: Vector3, _color: Color, scale: float = 1.0, muzzle_anchor: Node3D = null) -> void:
	_effects_component._create_muzzle_burst(_origin, _direction, _color, scale, muzzle_anchor)


func _active_muzzle() -> Node3D:
	return _effects_component._active_muzzle()


func _visual_contact(start: Vector3, end: Vector3, target: Node = null) -> Dictionary:
	return _effects_component._visual_contact(start, end, target)


func _contact_fx(contact: Dictionary, color: Color, power: float = 1.0, weapon: String = "") -> void:
	_effects_component._contact_fx(contact, color, power, weapon)


func _create_surface_impact_fx(origin: Vector3, direction: Vector3, color: Color = Color("#ff9c52")) -> void:
	_effects_component._create_surface_impact_fx(origin, direction, color)


func _finalize_passive_death() -> void:
	_combat_component._finalize_passive_death()


func _on_state_died() -> void:
	_combat_component._on_state_died()


func is_real_dead() -> bool:
	return _combat_component.is_real_dead()


func apply_loadout(next_loadout: Dictionary) -> void:
	_loadout_component.apply_loadout(next_loadout)


func set_robot(identifier: String) -> void:
	_loadout_component.set_robot(identifier)


func get_robot_id() -> String:
	return _loadout_component.get_robot_id()


func configure_survival_build(build: Dictionary) -> void:
	_loadout_component.configure_survival_build(build)


func set_training_options(invulnerable: bool, instant_cooldowns: bool, unlimited_ammo: bool) -> void:
	_loadout_component.set_training_options(invulnerable, instant_cooldowns, unlimited_ammo)


func set_training_health_ratio(ratio: float) -> void:
	_loadout_component.set_training_health_ratio(ratio)


func shift_pause_timers(seconds: float) -> void:
	_loadout_component.shift_pause_timers(seconds)


func _update_baroud_presentation() -> void:
	_presentation_component._update_baroud_presentation()


func _update_world_ui_anchor() -> void:
	_presentation_component._update_world_ui_anchor()


func set_passive(passive_id: String) -> void:
	_combat_component.set_passive(passive_id)


func passive_authoritative() -> bool:
	return _combat_component.passive_authoritative()


func emit_passive_weapon() -> Dictionary:
	return _combat_component.emit_passive_weapon()


func passive_weapon_damage(target: Node, amount: float, source: String, component: String, attack: Dictionary, impact_point: Vector3 = Vector3.INF) -> float:
	return _combat_component.passive_weapon_damage(target, amount, source, component, attack, impact_point)


func register_offensive_attack(activation: String) -> void:
	_combat_component.register_offensive_attack(activation)


func on_direct_offensive_hit(activation: String, applied: float, target: Node = null) -> void:
	_combat_component.on_direct_offensive_hit(activation, applied, target)


func get_passive_weapon_point() -> Vector3:
	return _combat_component.get_passive_weapon_point()


func get_tracker_locations() -> Array[Node3D]:
	return _combat_component.get_tracker_locations()


func get_passive_status() -> Dictionary:
	return _combat_component.get_passive_status()


func get_passive_id() -> String:
	return _combat_component.get_passive_id()


func get_baroud_remaining() -> float:
	return _combat_component.get_baroud_remaining()


func get_baroud_health() -> float:
	return _combat_component.get_baroud_health()


func _on_damage_dealt(effective_damage: float, target: Node3D = null) -> void:
	_combat_component._on_damage_dealt(effective_damage, target)


func get_health() -> float:
	return _combat_component.get_health()


func get_max_health() -> float:
	return _combat_component.get_max_health()


func get_shield_health() -> float:
	return _combat_component.get_shield_health()


func get_active_effect_types() -> Array[String]:
	return _combat_component.get_active_effect_types()


func _on_health_changed(current: float, maximum: float) -> void:
	_combat_component._on_health_changed(current, maximum)


func _on_damage_applied(amount: float, source_id: String, _attack_id: String) -> void:
	_combat_component._on_damage_applied(amount, source_id, _attack_id)


func _on_healing_applied(amount: float, _source_id: String) -> void:
	_combat_component._on_healing_applied(amount, _source_id)


func heal(amount: float, source_id: String = "") -> float:
	return _combat_component.heal(amount, source_id)


func apply_burn(duration: float = COMBAT_DATA.BURN_DURATION, damage_per_second: float = COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	_combat_component.apply_burn(duration, damage_per_second, source_id)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	_combat_component.apply_slow(duration, percent, source_id)


func apply_stun(duration: float, source_id: String = "") -> void:
	_combat_component.apply_stun(duration, source_id)


func apply_spotted(duration: float, source_id: String = "") -> void:
	_combat_component.apply_spotted(duration, source_id)


func reset_combat_state() -> void:
	_combat_component.reset_combat_state()


func reset_blaster_state() -> void:
	_blaster_component.reset_blaster_state()


func set_weapon(weapon_id: String) -> void:
	_loadout_component.set_weapon(weapon_id)


func get_offensive_module_id() -> String:
	return _loadout_component.get_offensive_module_id()


func _cycle_offensive_module() -> void:
	_loadout_component._cycle_offensive_module()


func _perform_offensive_module() -> void:
	_loadout_component._perform_offensive_module()


func _activate_defensive_module() -> void:
	_loadout_component._activate_defensive_module()


func _activate_mobility_module() -> void:
	_loadout_component._activate_mobility_module()


func get_weapon_id() -> String:
	return _loadout_component.get_weapon_id()


func get_mekatana_state() -> Dictionary:
	return _mekatana_component.get_mekatana_state()


func _can_apply_mekatana_damage() -> bool:
	return _mekatana_component._can_apply_mekatana_damage()


func _perform_mekatana_attack() -> void:
	_mekatana_component._perform_mekatana_attack()


func _update_mekatana_attack(delta: float) -> bool:
	return _mekatana_component._update_mekatana_attack(delta)


func _move_mekatana_dash(motion: Vector3) -> Vector3:
	return _mekatana_component._move_mekatana_dash(motion)


func _sync_mekatana_pose() -> void:
	_mekatana_component._sync_mekatana_pose()


func _on_mekatana_slash_started(rank: int) -> void:
	_mekatana_component._on_mekatana_slash_started(rank)


func _on_mekatana_hit(target: Node3D, _applied: float, multiplier: float) -> void:
	_mekatana_component._on_mekatana_hit(target, _applied, multiplier)


func _on_mekatana_finished() -> void:
	_mekatana_component._on_mekatana_finished()


func _cancel_mekatana_attack() -> void:
	_mekatana_component._cancel_mekatana_attack()


func _cycle_weapon() -> void:
	_loadout_component._cycle_weapon()


func get_longshot_cycle_count() -> int:
	return _longshot_component.get_longshot_cycle_count()


func is_longshot_enhanced_ready() -> bool:
	return _longshot_component.is_longshot_enhanced_ready()


func get_longshot_shots_fired() -> int:
	return _longshot_component.get_longshot_shots_fired()


func reset_longshot_state() -> void:
	_longshot_component.reset_longshot_state()


func _cancel_longshot_attack() -> void:
	_longshot_component._cancel_longshot_attack()


func _perform_longshot_attack() -> void:
	_longshot_component._perform_longshot_attack()


func _emit_longshot_shot(token: int, action_token: int) -> void:
	_longshot_component._emit_longshot_shot(token, action_token)


func _longshot_emission_valid(token: int, action_token: int) -> bool:
	return _longshot_component._longshot_emission_valid(token, action_token)


func _on_longshot_emitted(_enhanced: bool, _shot_number: int) -> void:
	_longshot_component._on_longshot_emitted(_enhanced, _shot_number)


func _spawn_longshot_projectile(enhanced: bool, shot_number: int, visual_only: bool = false) -> bool:
	return _longshot_component._spawn_longshot_projectile(enhanced, shot_number, visual_only)


func _on_longshot_projectile_finished(hit: Dictionary, distance: float, definition: Dictionary, enhanced: bool, shot_id: String, visual_only: bool = false, passive_attack: Dictionary = {}) -> void:
	_longshot_component._on_longshot_projectile_finished(hit, distance, definition, enhanced, shot_id, visual_only, passive_attack)


func _create_longshot_visual() -> void:
	_longshot_component._create_longshot_visual()


func _play_longshot_fallback_recoil(enhanced: bool) -> void:
	_longshot_component._play_longshot_fallback_recoil(enhanced)


func get_shotgun_ammo() -> int:
	return _shotgun_component.get_shotgun_ammo()


func get_shotgun_magazine_size() -> int:
	return _shotgun_component.get_shotgun_magazine_size()


func get_shotgun_reload_progress() -> float:
	return _shotgun_component.get_shotgun_reload_progress()


func is_shotgun_reloading() -> bool:
	return _shotgun_component.is_shotgun_reloading()


func reset_shotgun_state() -> void:
	_shotgun_component.reset_shotgun_state()


func reset_module_state() -> void:
	_utility_modules_component.reset_module_state()


func _update_shotgun_reload_input() -> void:
	_shotgun_component._update_shotgun_reload_input()


func _update_shotgun_attack(wants_to_attack: bool) -> void:
	_shotgun_component._update_shotgun_attack(wants_to_attack)


func _perform_shotgun_attack() -> void:
	_shotgun_component._perform_shotgun_attack()


func _play_shotgun_animation(speed_scale: float) -> void:
	_shotgun_component._play_shotgun_animation(speed_scale)


func _emit_shotgun_salvo(token: int, salvo: Dictionary) -> void:
	_shotgun_component._emit_shotgun_salvo(token, salvo)


func _play_shotgun_cycle_audio(token: int) -> void:
	_shotgun_component._play_shotgun_cycle_audio(token)


func _spawn_shotgun_projectile(start: Vector3, endpoint: Vector3, salvo: Dictionary, index: int) -> void:
	_shotgun_component._spawn_shotgun_projectile(start, endpoint, salvo, index)


func _on_shotgun_pellet_finished(hit: Dictionary, distance: float, salvo: Dictionary, index: int) -> void:
	_shotgun_component._on_shotgun_pellet_finished(hit, distance, salvo, index)


func _resolve_shotgun_projectile(salvo: Dictionary, index: int, did_hit: bool, target: Node, distance: float) -> void:
	_shotgun_component._resolve_shotgun_projectile(salvo, index, did_hit, target, distance)


func _shotgun_damage_at_distance(distance: float) -> float:
	return _shotgun_component._shotgun_damage_at_distance(distance)


func _finish_shotgun_attack(token: int) -> void:
	_shotgun_component._finish_shotgun_attack(token)


func _cancel_shotgun_attack() -> void:
	_shotgun_component._cancel_shotgun_attack()


func _start_shotgun_reload() -> void:
	_shotgun_component._start_shotgun_reload()


func _update_shotgun_reload(delta: float) -> void:
	_shotgun_component._update_shotgun_reload(delta)


func _update_shotgun_reload_visual() -> void:
	_shotgun_component._update_shotgun_reload_visual()


func _sync_weapon_readout() -> void:
	_presentation_component._sync_weapon_readout()


func _update_javelin_mark() -> void:
	_projectile_modules_component._update_javelin_mark()


func get_javelin_recast_fraction() -> float:
	return _projectile_modules_component.get_javelin_recast_fraction()


func _update_module_cooldowns(delta: float) -> void:
	_utility_modules_component._update_module_cooldowns(delta)


func get_module_cooldown(module_id: String) -> float:
	return _utility_modules_component.get_module_cooldown(module_id)


func is_module_busy() -> bool:
	return _utility_modules_component.is_module_busy()


func _module_ready(module_id: String) -> bool:
	return _utility_modules_component._module_ready(module_id)


func get_pyro_charges() -> int:
	return _mobility_modules_component.get_pyro_charges()


func _start_module_cooldown(module_id: String, duration: float) -> void:
	_utility_modules_component._start_module_cooldown(module_id, duration)


func get_mobility_module_id() -> String:
	return _utility_modules_component.get_mobility_module_id()


func get_defensive_module_id() -> String:
	return _utility_modules_component.get_defensive_module_id()


func get_stasis_remaining() -> float:
	return _utility_modules_component.get_stasis_remaining()


func _perform_counter() -> bool:
	return _defensive_modules_component._perform_counter()


func _on_counter_finished() -> void:
	_defensive_modules_component._on_counter_finished()


func is_counter_guarding() -> bool:
	return _defensive_modules_component.is_counter_guarding()


func get_surcharge_remaining() -> float:
	return _defensive_modules_component.get_surcharge_remaining()


func get_counter_hud_text() -> String:
	return _defensive_modules_component.get_counter_hud_text()


func _perform_defensive_module() -> void:
	_utility_modules_component._perform_defensive_module()


func _update_projector_threshold(current: float, maximum: float) -> void:
	_defensive_modules_component._update_projector_threshold(current, maximum)


func get_projector_passive_cooldown() -> float:
	return _defensive_modules_component.get_projector_passive_cooldown()


func _perform_projector() -> bool:
	return _defensive_modules_component._perform_projector()


func _update_projector_cast(delta: float) -> void:
	_defensive_modules_component._update_projector_cast(delta)


func _cancel_projector_cast() -> void:
	_defensive_modules_component._cancel_projector_cast()


func _on_projector_cast_started() -> void:
	_defensive_modules_component._on_projector_cast_started()


func _emit_projector_wave() -> void:
	_defensive_modules_component._emit_projector_wave()


func _projector_authoritative() -> bool:
	return _defensive_modules_component._projector_authoritative()


func _on_projector_activated() -> void:
	_defensive_modules_component._on_projector_activated()


func _perform_magnetic_field() -> void:
	_utility_modules_component._perform_magnetic_field()


func _magnetic_placement_valid(origin: Vector3, center: Vector3) -> bool:
	return _utility_modules_component._magnetic_placement_valid(origin, center)


func _create_magnetic_wall(token: int, action_token: int, center: Vector3, direction: Vector3) -> void:
	_utility_modules_component._create_magnetic_wall(token, action_token, center, direction)


func _perform_static_shield() -> void:
	_utility_modules_component._perform_static_shield()


func _create_stasis_fx() -> void:
	_utility_modules_component._create_stasis_fx()


func get_bio_remaining() -> float:
	return _utility_modules_component.get_bio_remaining()


func get_current_move_speed() -> float:
	return _utility_modules_component.get_current_move_speed()


func get_attack_speed_multiplier() -> float:
	return _utility_modules_component.get_attack_speed_multiplier()


func is_dash_active() -> bool:
	return _utility_modules_component.is_dash_active()


func _perform_mobility_module() -> void:
	_utility_modules_component._perform_mobility_module()


func is_eclipse_travelling() -> bool:
	return _mobility_modules_component.is_eclipse_travelling()


func is_eclipse_aiming() -> bool:
	return _mobility_modules_component.is_eclipse_aiming()


func set_eclipse_touch_vector(value: Vector2) -> void:
	_mobility_modules_component.set_eclipse_touch_vector(value)


func _perform_eclipse(destination: Vector3) -> bool:
	return _mobility_modules_component._perform_eclipse(destination)


func _on_eclipse_arrived(_origin: Vector3, destination: Vector3) -> void:
	_mobility_modules_component._on_eclipse_arrived(_origin, destination)


func _credit_eclipse_damage(amount: float) -> void:
	_mobility_modules_component._credit_eclipse_damage(amount)


func _permutation_target() -> Node3D:
	return _mobility_modules_component._permutation_target()


func _perform_permutation() -> void:
	_mobility_modules_component._perform_permutation()


func _permutation_authoritative() -> bool:
	return _mobility_modules_component._permutation_authoritative()


func _on_permutation_arrived(_origin: Vector3, _destination: Vector3) -> void:
	_mobility_modules_component._on_permutation_arrived(_origin, _destination)


func _on_permutation_failed() -> void:
	_mobility_modules_component._on_permutation_failed()


func _clear_permutation() -> void:
	_mobility_modules_component._clear_permutation()


func get_permutation_speed_remaining() -> float:
	return _mobility_modules_component.get_permutation_speed_remaining()


func on_permutation_relocated() -> void:
	_mobility_modules_component.on_permutation_relocated()


func refresh_permutation_sweeps() -> void:
	_mobility_modules_component.refresh_permutation_sweeps()


func _perform_pyro_boots(direction_override: Vector3 = Vector3.ZERO) -> void:
	_utility_modules_component._perform_pyro_boots(direction_override)


func _perform_bio_injector() -> void:
	_utility_modules_component._perform_bio_injector()


func _update_dash(delta: float) -> void:
	_utility_modules_component._update_dash(delta)


func _finish_dash(completed: bool = true) -> void:
	_utility_modules_component._finish_dash(completed)


func _cancel_dash() -> void:
	_utility_modules_component._cancel_dash()


func get_fulguro_hit_radius() -> float:
	return _fulguro_component.get_fulguro_hit_radius()


func is_fulguro_projected() -> bool:
	return _fulguro_component.is_fulguro_projected()


func is_action_locked() -> bool:
	return _fulguro_component.is_action_locked()


func start_knockback(direction: Vector3, distance: float, duration: float, source_id: String) -> void:
	_mobility_modules_component.start_knockback(direction, distance, duration, source_id)


func start_fulguro_projection(direction: Vector3, max_distance: float, max_duration: float, wall_damage: float, wall_stun: float, source_id: String, attack_id: String) -> void:
	_fulguro_component.start_fulguro_projection(direction, max_distance, max_duration, wall_damage, wall_stun, source_id, attack_id)


func _update_fulguro_projection(delta: float) -> void:
	_fulguro_component._update_fulguro_projection(delta)


func _finish_fulguro_projection(crushed_wall: bool, impact_position: Vector3 = Vector3.ZERO, impact_normal: Vector3 = Vector3.ZERO) -> void:
	_fulguro_component._finish_fulguro_projection(crushed_wall, impact_position, impact_normal)


func _cancel_fulguro_projection() -> void:
	_fulguro_component._cancel_fulguro_projection()


func start_pelto_pull(pull_direction: Vector3, distance: float, duration: float, _source_id: String = "", _attack_id: String = "") -> void:
	_pelto_component.start_pelto_pull(pull_direction, distance, duration, _source_id, _attack_id)


func _update_pelto_pull(delta: float) -> void:
	_pelto_component._update_pelto_pull(delta)


func _cancel_pelto_pull() -> void:
	_pelto_component._cancel_pelto_pull()


func is_pelto_pulled() -> bool:
	return _pelto_component.is_pelto_pulled()


func _spawn_fulguro_wall_impact(impact_position: Vector3, impact_normal: Vector3) -> void:
	_fulguro_component._spawn_fulguro_wall_impact(impact_position, impact_normal)


func _can_buffer_defensive_action() -> bool:
	return _utility_modules_component._can_buffer_defensive_action()


func _buffer_dash() -> void:
	_utility_modules_component._buffer_dash()


func _has_live_javelin_mark() -> bool:
	return _utility_modules_component._has_live_javelin_mark()


func _buffer_javelin_recast() -> void:
	_utility_modules_component._buffer_javelin_recast()


func _try_execute_defensive_buffer() -> void:
	_utility_modules_component._try_execute_defensive_buffer()


func _clear_defensive_buffer() -> void:
	_utility_modules_component._clear_defensive_buffer()


func get_buffered_defensive_action() -> String:
	return _utility_modules_component.get_buffered_defensive_action()


func _create_dash_fx(origin: Vector3) -> void:
	_utility_modules_component._create_dash_fx(origin)


func _create_bio_fx() -> void:
	_utility_modules_component._create_bio_fx()


func _survival_evolved(category: String) -> bool:
	return _effects_component._survival_evolved(category)


func _survival_targets() -> Array:
	return _effects_component._survival_targets()


func _survival_area_damage(center: Vector3, radius: float, damage: float, attack_name: String, color: Color, excluded: Node = null) -> void:
	_effects_component._survival_area_damage(center, radius, damage, attack_name, color, excluded)


func _survival_secondary_hit(primary: Node, damage: float, radius: float, attack_name: String, aligned: bool, direction: Vector3 = Vector3.ZERO) -> void:
	_effects_component._survival_secondary_hit(primary, damage, radius, attack_name, aligned, direction)


func _survival_pulse_fx(center: Vector3, radius: float, color: Color) -> void:
	_effects_component._survival_pulse_fx(center, radius, color)


func _perform_rocket_basket() -> void:
	_projectile_modules_component._perform_rocket_basket()


func _module_target() -> Node:
	return _effects_component._module_target()


func _best_training_target(origin: Vector3, direction: Vector3, max_range: float, radius_scale: float) -> Node:
	return _effects_component._best_training_target(origin, direction, max_range, radius_scale)


func _module_visual_start(direction: Vector3) -> Vector3:
	return _effects_component._module_visual_start(direction)


func _module_obstacle_endpoint(start: Vector3, end: Vector3, excluded: Array[RID] = []) -> Vector3:
	return _effects_component._module_obstacle_endpoint(start, end, excluded)


func _module_path_clear(from_position: Vector3, to_position: Vector3, excluded: Array[RID] = []) -> bool:
	return _effects_component._module_path_clear(from_position, to_position, excluded)


func _solid_path_clear(from_position: Vector3, to_position: Vector3, excluded: Array[RID] = []) -> bool:
	return _effects_component._solid_path_clear(from_position, to_position, excluded)


func _fulguro_targets() -> Array:
	return _fulguro_component._fulguro_targets()


func _perform_fulguro_punch() -> void:
	_fulguro_component._perform_fulguro_punch()


func _begin_fulguro_charge() -> void:
	_fulguro_component._begin_fulguro_charge()


func _release_fulguro_charge() -> void:
	_fulguro_component._release_fulguro_charge()


func get_fulguro_charge_fraction() -> float:
	return _fulguro_component.get_fulguro_charge_fraction()


func is_fulguro_charging() -> bool:
	return _fulguro_component.is_fulguro_charging()


func _update_fulguro_attack(delta: float) -> void:
	_fulguro_component._update_fulguro_attack(delta)


func _fulguro_power_ratio() -> float:
	return _fulguro_component._fulguro_power_ratio()


func _commit_fulguro_strike() -> void:
	_fulguro_component._commit_fulguro_strike()


func _resolve_fulguro_strike() -> void:
	_fulguro_component._resolve_fulguro_strike()


func _create_fulguro_telegraph() -> void:
	_fulguro_component._create_fulguro_telegraph()


func _update_fulguro_telegraph(delta: float = 0.0) -> void:
	_fulguro_component._update_fulguro_telegraph(delta)


func _clear_fulguro_telegraph() -> void:
	_fulguro_component._clear_fulguro_telegraph()


func _spawn_fulguro_strike_fx() -> void:
	_fulguro_component._spawn_fulguro_strike_fx()


func _update_fulguro_pose() -> void:
	_fulguro_component._update_fulguro_pose()


func _finish_fulguro_attack() -> void:
	_fulguro_component._finish_fulguro_attack()


func _cancel_fulguro_attack(reason: String = "") -> void:
	_fulguro_component._cancel_fulguro_attack(reason)


func _perform_pelto_smash(aim_held: bool = false) -> void:
	_pelto_component._perform_pelto_smash(aim_held)


func is_pelto_preparing() -> bool:
	return _pelto_component.is_pelto_preparing()


func get_pelto_preparation_fraction() -> float:
	return _pelto_component.get_pelto_preparation_fraction()


func set_pelto_touch_aim(vector: Vector2) -> void:
	_pelto_component.set_pelto_touch_aim(vector)


func _release_pelto_aim() -> void:
	_pelto_component._release_pelto_aim()


func _update_pelto_attack(delta: float) -> void:
	_pelto_component._update_pelto_attack(delta)


func _commit_pelto_impact() -> void:
	_pelto_component._commit_pelto_impact()


func _on_pelto_wave_finished(wave: Node) -> void:
	_pelto_component._on_pelto_wave_finished(wave)


func _on_pelto_hit(target: Node, returning: bool, applied_damage: float) -> void:
	_pelto_component._on_pelto_hit(target, returning, applied_damage)


func _create_pelto_telegraph() -> void:
	_pelto_component._create_pelto_telegraph()


func _scene_add_child(node: Node) -> void:
	_effects_component._scene_add_child(node)


func _update_pelto_telegraph() -> void:
	_pelto_component._update_pelto_telegraph()


func _clear_pelto_telegraph() -> void:
	_pelto_component._clear_pelto_telegraph()


func _update_pelto_pose() -> void:
	_pelto_component._update_pelto_pose()


func _finish_pelto_smash() -> void:
	_pelto_component._finish_pelto_smash()


func _cancel_pelto_smash(reason: String = "") -> void:
	_pelto_component._cancel_pelto_smash(reason)


func _set_pelto_weapon_hidden(hidden: bool) -> void:
	_pelto_component._set_pelto_weapon_hidden(hidden)


func _queue_pelto_weapon_restore() -> void:
	_pelto_component._queue_pelto_weapon_restore()


func _restore_pelto_weapon_after_skeleton(restore_serial: int) -> void:
	_pelto_component._restore_pelto_weapon_after_skeleton(restore_serial)


func _pelto_ground_material(color: Color, alpha: float) -> StandardMaterial3D:
	return _pelto_component._pelto_ground_material(color, alpha)


func _select_javelin_target(origin: Vector3, direction: Vector3, shot_range: float = -1.0) -> Node:
	return _projectile_modules_component._select_javelin_target(origin, direction, shot_range)


func _perform_javelin() -> void:
	_projectile_modules_component._perform_javelin()


func _begin_javelin_charge() -> bool:
	return _projectile_modules_component._begin_javelin_charge()


func is_javelin_charging() -> bool:
	return _projectile_modules_component.is_javelin_charging()


func get_javelin_charge_fraction() -> float:
	return _projectile_modules_component.get_javelin_charge_fraction()


func _javelin_power(seconds: float) -> float:
	return _projectile_modules_component._javelin_power(seconds)


func set_javelin_touch_aim(vector: Vector2) -> void:
	_projectile_modules_component.set_javelin_touch_aim(vector)


func _release_javelin_charge() -> void:
	_projectile_modules_component._release_javelin_charge()


func _update_javelin_charge(delta: float) -> void:
	_projectile_modules_component._update_javelin_charge(delta)


func _clear_javelin_charge_visual() -> void:
	_projectile_modules_component._clear_javelin_charge_visual()


func _cancel_javelin_charge() -> void:
	_projectile_modules_component._cancel_javelin_charge()


func _emit_javelin(token: int, action_token: int, origin: Vector3, direction: Vector3, power: float = 0.0) -> void:
	_projectile_modules_component._emit_javelin(token, action_token, origin, direction, power)


func _on_javelin_finished(hit: Dictionary, _distance: float, token: int, damage: float = 140.0, mark_duration: float = 2.5, shot_range: float = 8.0, power: float = 0.0) -> void:
	_projectile_modules_component._on_javelin_finished(hit, _distance, token, damage, mark_duration, shot_range, power)


func _recast_javelin(preferred_destination: Vector3 = Vector3.INF) -> void:
	_projectile_modules_component._recast_javelin(preferred_destination)


func _find_javelin_destination(target: Node) -> Vector3:
	return _projectile_modules_component._find_javelin_destination(target)


func get_javelin_front_direction() -> Vector3:
	return _projectile_modules_component.get_javelin_front_direction()


func _javelin_destination_valid(target: Node, candidate: Vector3) -> bool:
	return _projectile_modules_component._javelin_destination_valid(target, candidate)


func _begin_blaster_charge(now: float = -1.0) -> void:
	_blaster_component._begin_blaster_charge(now)


func _play_blaster_ready_sound() -> void:
	_blaster_component._play_blaster_ready_sound()


func _stop_blaster_charge_audio() -> void:
	_blaster_component._stop_blaster_charge_audio()


func _finish_blaster_charge_audio_stop() -> void:
	_blaster_component._finish_blaster_charge_audio_stop()


func _cancel_blaster_charge(reason: String = "", release_action: bool = true) -> void:
	_blaster_component._cancel_blaster_charge(reason, release_action)


func _cancel_blaster_attack() -> void:
	_blaster_component._cancel_blaster_attack()


func _release_blaster_charge() -> void:
	_blaster_component._release_blaster_charge()


func _fire_blaster_projectile(damage: float, charge_ratio: float, direction: Vector3, reserved_action_token: int = 0) -> void:
	_blaster_component._fire_blaster_projectile(damage, charge_ratio, direction, reserved_action_token)


func _play_blaster_recoil(charge_ratio: float) -> void:
	_blaster_component._play_blaster_recoil(charge_ratio)


func _kill_weapon_recoil_tweens(tweens: Array[Tween]) -> void:
	_effects_component._kill_weapon_recoil_tweens(tweens)


func _is_weapon_recoil_running(tweens: Array[Tween]) -> bool:
	return _effects_component._is_weapon_recoil_running(tweens)


func _safe_projectile_origin(muzzle: Vector3) -> Vector3:
	return _effects_component._safe_projectile_origin(muzzle)


func _spawn_blaster_projectile(start: Vector3, damage: float, charge_ratio: float, token: int, shot_direction: Vector3, passive_attack: Dictionary = {}) -> void:
	_blaster_component._spawn_blaster_projectile(start, damage, charge_ratio, token, shot_direction, passive_attack)


func _on_blaster_projectile_finished(hit: Dictionary, _distance: float, damage: float, charge_ratio: float, token: int, shot_direction: Vector3, passive_attack: Dictionary = {}) -> void:
	_blaster_component._on_blaster_projectile_finished(hit, _distance, damage, charge_ratio, token, shot_direction, passive_attack)


func _register_projectile_motion(projectile: Node3D, start: Vector3, endpoint: Vector3, duration: float, radius: float) -> void:
	_effects_component._register_projectile_motion(projectile, start, endpoint, duration, radius)


func _blaster_obstacle_endpoint(start: Vector3, end: Vector3) -> Vector3:
	return _blaster_component._blaster_obstacle_endpoint(start, end)


func _blaster_path_clear(target: Node, from_position: Vector3, to_position: Vector3) -> bool:
	return _blaster_component._blaster_path_clear(target, from_position, to_position)


func _update_blaster_charge_visual(delta: float) -> void:
	_blaster_component._update_blaster_charge_visual(delta)


func get_blaster_charge_ratio() -> float:
	return _blaster_component.get_blaster_charge_ratio()


func is_blaster_charging() -> bool:
	return _blaster_component.is_blaster_charging()


func _create_teleport_fx(origin: Vector3) -> void:
	_effects_component._create_teleport_fx(origin)


func _perform_axe_attack() -> void:
	_legacy_axe_component._perform_axe_attack()


func _attack_token_valid(token: int) -> bool:
	return _legacy_axe_component._attack_token_valid(token)


func _resolve_axe_strike(token: int, step: int) -> void:
	_legacy_axe_component._resolve_axe_strike(token, step)


func _resolve_axe_center(token: int) -> void:
	_legacy_axe_component._resolve_axe_center(token)


func _resolve_axe_wave(token: int) -> void:
	_legacy_axe_component._resolve_axe_wave(token)


func _apply_axe_hit(target: Node, impact_point: Vector3, damage: float, slow_duration: float, critical_hit: bool, token: int, phase: int) -> void:
	_legacy_axe_component._apply_axe_hit(target, impact_point, damage, slow_duration, critical_hit, token, phase)


func _finish_axe_attack(token: int) -> void:
	_legacy_axe_component._finish_axe_attack(token)


func _cancel_axe_attack() -> void:
	_legacy_axe_component._cancel_axe_attack()


func _axe_target_in_shape(target: Node, step: int) -> bool:
	return _legacy_axe_component._axe_target_in_shape(target, step)


func _axe_target_in_radius(target: Node, radius: float) -> bool:
	return _legacy_axe_component._axe_target_in_radius(target, radius)


func _axe_target_in_wave(target: Node) -> bool:
	return _legacy_axe_component._axe_target_in_wave(target)


func _axe_path_clear(target: Node, from_position: Vector3, to_position: Vector3) -> bool:
	return _legacy_axe_component._axe_path_clear(target, from_position, to_position)


func _play_axe_animation(step: int, speed_multiplier: float = 1.0) -> void:
	_legacy_axe_component._play_axe_animation(step, speed_multiplier)


func _begin_axe_trail(step: int, speed_multiplier: float = 1.0) -> void:
	_legacy_axe_component._begin_axe_trail(step, speed_multiplier)


func _update_axe_trail(delta: float) -> void:
	_legacy_axe_component._update_axe_trail(delta)


func _rebuild_axe_trail() -> void:
	_legacy_axe_component._rebuild_axe_trail()


func _finish_axe_trail(fade_duration: float) -> void:
	_legacy_axe_component._finish_axe_trail(fade_duration)


func _trigger_hit_stop(duration: float) -> void:
	_legacy_axe_component._trigger_hit_stop(duration)


func _create_fx_material(color: Color, alpha: float = 0.9) -> StandardMaterial3D:
	return _effects_component._create_fx_material(color, alpha)


func _register_fx_budget(node: Node, category: String = "burst") -> void:
	_effects_component._register_fx_budget(node, category)


func _set_material_alpha(alpha: float, material: StandardMaterial3D) -> void:
	_effects_component._set_material_alpha(alpha, material)


func _create_lightning_arc(start: Vector3, end: Vector3, color: Color, width: float = 0.045, lifetime: float = 0.24) -> void:
	_effects_component._create_lightning_arc(start, end, color, width, lifetime)


func _create_axe_lightning(step: int, tip_position: Vector3) -> void:
	_legacy_axe_component._create_axe_lightning(step, tip_position)


func _get_axe_forward() -> Vector3:
	return _legacy_axe_component._get_axe_forward()


func _spawn_particle_burst(origin: Vector3, color: Color, amount: int, lifetime: float, speed: float, particle_scale: float, emission_direction: Vector3 = Vector3.UP, emission_spread: float = 180.0) -> void:
	_effects_component._spawn_particle_burst(origin, color, amount, lifetime, speed, particle_scale, emission_direction, emission_spread)


func _play_impact_fx(step: int, impact_point: Vector3, did_hit: bool, tip_position: Vector3, tip_forward: Vector3, phase: String = "") -> void:
	_legacy_axe_component._play_impact_fx(step, impact_point, did_hit, tip_position, tip_forward, phase)


func _create_hit_flash(origin: Vector3, color: Color, radius: float) -> void:
	_effects_component._create_hit_flash(origin, color, radius)


func _create_target_hit_fx(origin: Vector3, critical: bool) -> void:
	_effects_component._create_target_hit_fx(origin, critical)


func _create_slash_fan(radius: float, half_angle: float) -> MeshInstance3D:
	return _legacy_axe_component._create_slash_fan(radius, half_angle)


func _create_slash_outline(radius: float, half_angle: float, color: Color) -> MeshInstance3D:
	return _legacy_axe_component._create_slash_outline(radius, half_angle, color)


func _create_cleave_arc(center: Vector3, forward: Vector3, side: Vector3, reach: float, height_offset: float, color: Color, lifetime: float) -> void:
	_legacy_axe_component._create_cleave_arc(center, forward, side, reach, height_offset, color, lifetime)


func _create_shockwave_fx(impact_point: Vector3) -> void:
	_legacy_axe_component._create_shockwave_fx(impact_point)


func _create_shockwave_wave(origin: Vector3, radius: float, color: Color, lifetime: float) -> void:
	_legacy_axe_component._create_shockwave_wave(origin, radius, color, lifetime)


func _create_crater_fractures(origin: Vector3) -> void:
	_legacy_axe_component._create_crater_fractures(origin)


func _create_lightning_spark(origin: Vector3, index: int) -> void:
	_legacy_axe_component._create_lightning_spark(origin, index)


func _show_attack_hitbox(step: int, impact_point: Vector3 = Vector3.ZERO, did_hit: bool = false, tip_position: Vector3 = Vector3.ZERO, tip_forward: Vector3 = Vector3.ZERO, phase: String = "") -> void:
	_legacy_axe_component._show_attack_hitbox(step, impact_point, did_hit, tip_position, tip_forward, phase)


func _build_collision() -> void:
	_presentation_component._build_collision()


func _register_locomotion_node(node: Node3D, role: String, phase: float = 0.0) -> void:
	_presentation_component._register_locomotion_node(node, role, phase)


func _play_player_animation(animation_name: StringName, blend_time: float = 0.16, speed_scale: float = 1.0) -> bool:
	return _presentation_component._play_player_animation(animation_name, blend_time, speed_scale)


func _has_skeletal_weapon_attachment() -> bool:
	return _presentation_component._has_skeletal_weapon_attachment()


func _update_aim_pose_state(immediate: bool = false) -> void:
	_presentation_component._update_aim_pose_state(immediate)


func _start_round_warmup_animation() -> void:
	_presentation_component._start_round_warmup_animation()


func _update_player_animation() -> void:
	_presentation_component._update_player_animation()


func _on_player_animation_finished(animation_name: StringName) -> void:
	_presentation_component._on_player_animation_finished(animation_name)


func _attach_weapon_pivot_to_hand(pivot: Node3D, weapon_id: StringName, desired_position: Vector3, desired_rotation: Vector3, carry_pitch_degrees: float = 0.0) -> Transform3D:
	return _presentation_component._attach_weapon_pivot_to_hand(pivot, weapon_id, desired_position, desired_rotation, carry_pitch_degrees)


func _build_robot() -> void:
	_presentation_component._build_robot()


func _update_weapon_visuals() -> void:
	_presentation_component._update_weapon_visuals()


func _create_player_direction_debug() -> void:
	_presentation_component._create_player_direction_debug()


func _update_player_debug_vectors() -> void:
	_presentation_component._update_player_debug_vectors()


func _add_debug_direction_line(direction: Vector3, color: Color, length: float) -> void:
	_presentation_component._add_debug_direction_line(direction, color, length)


func _add_debug_segment(from_world: Vector3, to_world: Vector3, color: Color) -> void:
	_presentation_component._add_debug_segment(from_world, to_world, color)


func _add_robot_arm(parent: Node3D, side: float) -> void:
	_presentation_component._add_robot_arm(parent, side)


func _add_robot_leg(parent: Node3D, side: float) -> void:
	_presentation_component._add_robot_leg(parent, side)


func _add_robot_backpack(parent: Node3D) -> void:
	_presentation_component._add_robot_backpack(parent)


func _material(color: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	return _presentation_component._material(color, roughness, emission)


func _robot_textured_material(color: Color, roughness: float, texture: Texture2D) -> StandardMaterial3D:
	return _presentation_component._robot_textured_material(color, roughness, texture)
