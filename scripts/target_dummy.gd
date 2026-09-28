extends StaticBody3D

signal died

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const COMBAT_STATE := preload("res://scripts/combat_state.gd")
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")
const TRAINING_BOT := preload("res://scripts/training_bot.gd")
const ENEMY_DROID_VISUAL := preload("res://scripts/enemy_droid_visual.gd")
const STATUS_VFX := preload("res://scripts/status_vfx.gd")

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


func _ready() -> void:
	# Sample displacement after TrainingBot's default-priority physics step.
	process_physics_priority = 10
	collision_layer = 2
	collision_mask = 0
	combat_state = COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH)
	visibility_state = VISIBILITY_STATE.new()
	combat_state.health_changed.connect(_on_health_changed)
	combat_state.damage_applied.connect(_on_damage_applied)
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
	if _javelin_mark_until >= 0.0 and Time.get_ticks_msec() / 1000.0 >= _javelin_mark_until:
		_javelin_mark_until = -1.0
	_update_effect_presentation()
	_update_visibility_presentation()


func _physics_process(delta: float) -> void:
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
		return _visual_rig.call("prepare_shot", aim_point)
	return Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 1.30)


func get_training_bot_muzzle_transform() -> Transform3D:
	if _visual_rig != null:
		return _visual_rig.call("get_muzzle_transform")
	return Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 1.30)


## Shared combat API used by the player, future bot and Training Lab.
func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if _resetting or combat_state == null:
		return 0.0
	if amount > 0.0 and visibility_state != null:
		visibility_state.mark_combat_event()
	return combat_state.apply_damage(amount, source_id, attack_id)


func heal(amount: float, source_id: String = "") -> float:
	if _resetting or combat_state == null:
		return 0.0
	return combat_state.heal(amount, source_id)


func apply_burn(duration: float = COMBAT_DATA.BURN_DURATION, damage_per_second: float = COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_burn(duration, damage_per_second, source_id)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_slow(duration, percent, source_id)


func apply_stun(duration: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_stun(duration, source_id)


func apply_spotted(duration: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_spotted(duration, source_id)
	if visibility_state != null:
		visibility_state.mark_spotted(duration)


func reset_combat_state() -> void:
	if _health_readout != null:
		_health_readout.call("clear_damage_numbers")
	_resetting = false
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


func _on_damage_applied(amount: float, source_id: String, _attack_id: String) -> void:
	if _health_readout != null:
		_health_readout.call("show_damage", amount)
	# The prototype has one player attacker. Keep attribution on effective PV
	# removed so Omnivamp also sees criticals and BURN ticks, never overkill.
	if not (source_id == "player" or source_id.begins_with("player:")):
		return
	var attacker := get_tree().current_scene.get_node_or_null("Player") if get_tree().current_scene != null else null
	if attacker != null and is_instance_valid(attacker):
		attacker.call("_on_damage_dealt", amount)


func _on_effect_changed(_effect_type: String, _active: bool) -> void:
	_update_effect_presentation()


func set_duel_mode(value: bool) -> void:
	_duel_mode = value
	if not value:
		_duel_paused = false


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
		_health_readout.call("set_health", combat_state.health, combat_state.max_health)


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
	_health_readout.call("configure", Color("#ee6b4e"), "BOT")

	_status_label = Label3D.new()
	_status_label.name = "StatusReadout"
	_status_label.position = Vector3(1.35, 3.75, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 27
	_status_label.outline_size = 7
	_status_label.modulate = Color("#ffe0ac")
	add_child(_status_label)

	_status_vfx = STATUS_VFX.new()
	add_child(_status_vfx)
	_status_vfx.call("configure", self)

	_javelin_mark_label = Label3D.new()
	_javelin_mark_label.name = "JavelinMark"
	_javelin_mark_label.text = "JAVELIN"
	_javelin_mark_label.position = Vector3(0.0, 3.62, 0.0)
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
