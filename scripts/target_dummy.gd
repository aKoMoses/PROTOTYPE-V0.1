extends StaticBody3D

signal died

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const COMBAT_STATE := preload("res://scripts/combat_state.gd")
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")
const TRAINING_BOT := preload("res://scripts/training_bot.gd")

var combat_state
var visibility_state
var _resetting := false
var _health_label: Label3D
var _health_bar_bg: MeshInstance3D
var _health_bar_fill: MeshInstance3D
var _body_material: StandardMaterial3D
var _status_label: Label3D
var _body_mesh: MeshInstance3D
var _impact_light: OmniLight3D
var _burn_fx: Node3D
var _burn_light: OmniLight3D
var _slow_fx: Node3D
var _slow_ring: MeshInstance3D
var _slow_light: OmniLight3D
var _stun_fx: MeshInstance3D
var _spotted_fx: Label3D
var _spotted_emblem: MeshInstance3D
var _spotted_pupil: MeshInstance3D
var _spotted_light: OmniLight3D
var _javelin_mark_label: Label3D
var _javelin_mark_until := -1.0
var _effect_clock := 0.0
var _training_bot: Node
var _locomotion_nodes: Array[Node3D] = []
var _locomotion_clock := 0.0
var _locomotion_amount := 0.0
var _last_visual_position := Vector3.ZERO
var _duel_mode := false
var _duel_paused := false


func _ready() -> void:
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
	var displacement := global_position.distance_to(_last_visual_position)
	_last_visual_position = global_position
	var moving := displacement > 0.0005
	_update_robot_motion(delta, moving)
	if visibility_state != null:
		visibility_state.update(delta)
	if combat_state != null and not _resetting and not _duel_paused:
		combat_state.update(delta)
	if _javelin_mark_until >= 0.0 and Time.get_ticks_msec() / 1000.0 >= _javelin_mark_until:
		_javelin_mark_until = -1.0
	_update_effect_presentation()
	_update_visibility_presentation()


func _register_locomotion_node(node: Node3D, role: String, phase: float = 0.0) -> void:
	if node == null:
		return
	node.set_meta("locomotion_role", role)
	node.set_meta("locomotion_phase", phase)
	node.set_meta("locomotion_base_position", node.position)
	node.set_meta("locomotion_base_rotation", node.rotation)
	_locomotion_nodes.append(node)


func _update_robot_motion(delta: float, moving: bool) -> void:
	_locomotion_clock += delta
	var target_amount := 1.0 if moving else 0.0
	_locomotion_amount = move_toward(_locomotion_amount, target_amount, delta * 7.0)
	for node in _locomotion_nodes:
		if node == null or not is_instance_valid(node):
			continue
		var base_position: Vector3 = node.get_meta("locomotion_base_position", node.position)
		var base_rotation: Vector3 = node.get_meta("locomotion_base_rotation", node.rotation)
		var phase := float(node.get_meta("locomotion_phase", 0.0))
		var role := str(node.get_meta("locomotion_role", "body"))
		var stride := sin(_locomotion_clock * 9.0 + phase) * _locomotion_amount
		if role == "limb":
			node.position = base_position + Vector3(0.0, absf(stride) * 0.03, 0.0)
			node.rotation = base_rotation + Vector3(stride * 0.16, 0.0, 0.0)
		elif role == "head":
			node.position = base_position + Vector3(0.0, sin(_locomotion_clock * 9.0 + phase) * 0.03 * _locomotion_amount, 0.0)
			node.rotation = base_rotation + Vector3(0.0, sin(_locomotion_clock * 4.4 + phase) * 0.022 * _locomotion_amount, 0.0)
		else:
			node.position = base_position + Vector3(0.0, sin(_locomotion_clock * 9.0 + phase) * 0.04 * _locomotion_amount, 0.0)
			node.rotation = base_rotation


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
	_resetting = false
	_javelin_mark_until = -1.0
	if combat_state != null:
		combat_state.reset()
	if visibility_state != null:
		visibility_state.reset()
	if _body_material != null:
		_body_material.albedo_color = Color("#8f302b")
	if _training_bot != null:
		_training_bot.call("reset_clock")
	_update_status("")
	_update_label()


func set_training_bot_enabled(value: bool) -> void:
	if _training_bot != null:
		_training_bot.call("set_enabled", value)


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
	# Visibility must not turn status visuals on by itself. The previous broad
	# loop overwrote _update_effect_presentation() every frame, making a fresh
	# mannequin render BURN/SLOW/STUN/SPOTTED as if all four were active.
	for node in [_body_mesh, _health_label, _health_bar_bg, _health_bar_fill, _status_label, _impact_light]:
		if node != null:
			node.visible = should_show
	var burning: bool = combat_state != null and combat_state.has_effect(COMBAT_DATA.EFFECT_BURN)
	var slowed: bool = combat_state != null and combat_state.has_effect(COMBAT_DATA.EFFECT_SLOW)
	var stunned: bool = combat_state != null and combat_state.has_effect(COMBAT_DATA.EFFECT_STUN)
	var spotted: bool = combat_state != null and combat_state.has_effect(COMBAT_DATA.EFFECT_SPOTTED)
	if _burn_fx != null:
		_burn_fx.visible = should_show and burning
	if _burn_light != null:
		_burn_light.visible = should_show and burning
	if _slow_fx != null:
		_slow_fx.visible = should_show and slowed
	if _slow_ring != null:
		_slow_ring.visible = should_show and slowed
	if _slow_light != null:
		_slow_light.visible = should_show and slowed
	if _stun_fx != null:
		_stun_fx.visible = should_show and stunned
	if _spotted_fx != null:
		_spotted_fx.visible = should_show and spotted
	if _spotted_emblem != null:
		_spotted_emblem.visible = should_show and spotted
	if _spotted_light != null:
		_spotted_light.visible = should_show and spotted
	if _javelin_mark_label != null:
		_javelin_mark_label.visible = should_show and has_javelin_mark()


func apply_javelin_mark(duration: float, _source_id: String = "") -> void:
	_javelin_mark_until = Time.get_ticks_msec() / 1000.0 + maxf(0.0, duration)


func has_javelin_mark() -> bool:
	return _javelin_mark_until > Time.get_ticks_msec() / 1000.0 and not _resetting and get_health() > 0.0


func clear_javelin_mark() -> void:
	_javelin_mark_until = -1.0


func flash_impact(critical: bool = false) -> void:
	if _body_mesh == null:
		return
	var original_scale := _body_mesh.scale
	var tween := create_tween()
	tween.tween_property(_body_mesh, "scale", original_scale * (1.24 if critical else 1.12), 0.055)
	tween.tween_property(_body_mesh, "scale", original_scale, 0.14)
	var recoil := create_tween()
	var kick_direction := Vector3(randf_range(-0.18, 0.18), 0.0, randf_range(-0.18, 0.18))
	recoil.tween_property(_body_mesh, "position", Vector3(kick_direction.x, 0.96, kick_direction.z), 0.045)
	recoil.tween_property(_body_mesh, "position", Vector3(0.0, 0.9, 0.0), 0.22)
	recoil.tween_property(_body_mesh, "rotation", Vector3(0.0, 0.0, deg_to_rad(randf_range(-7.0, 7.0))), 0.04)
	recoil.tween_property(_body_mesh, "rotation", Vector3.ZERO, 0.20)
	_body_material.emission_enabled = true
	_body_material.emission = Color("#fff0b0") if critical else Color("#ff684d")
	_body_material.emission_energy_multiplier = 4.0 if critical else 2.5
	if _impact_light != null:
		_impact_light.light_color = Color("#fff2b2") if critical else Color("#ff5b43")
		_impact_light.light_energy = 7.0 if critical else 4.0
		var light_tween := create_tween()
		light_tween.tween_property(_impact_light, "light_energy", 0.0, 0.20)
	_spawn_target_impact_fx(critical)
	tween.tween_callback(_clear_impact_flash)


func _spawn_target_impact_fx(critical: bool) -> void:
	var origin := global_position + Vector3.UP * (0.92 if not critical else 1.05)
	var color := Color("#fff0a1") if critical else Color("#ff7052")
	var particles := GPUParticles3D.new()
	particles.name = "TargetImpactSparks"
	particles.amount = 20 if critical else 10
	particles.lifetime = 0.32 if critical else 0.22
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-4.0, -4.0, -4.0), Vector3(8.0, 8.0, 8.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 70.0
	process_material.initial_velocity_min = 3.0 if not critical else 4.8
	process_material.initial_velocity_max = 4.6 if not critical else 6.8
	process_material.gravity = Vector3(0.0, -9.0, 0.0)
	process_material.scale_min = 0.06
	process_material.scale_max = 0.14 if critical else 0.10
	particles.process_material = process_material
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.08
	spark_mesh.height = 0.16
	spark_mesh.material = _effect_material(color, color)
	particles.draw_pass_1 = spark_mesh
	get_tree().current_scene.add_child(particles)
	_register_fx_budget(particles, "particle")
	particles.global_position = origin
	particles.emitting = true
	get_tree().create_timer(particles.lifetime + 0.30).timeout.connect(particles.queue_free)


func _clear_impact_flash() -> void:
	if _body_material != null:
		_body_material.emission_enabled = false


func _on_health_changed(_current: float, _maximum: float) -> void:
	_update_label()


func _on_damage_applied(amount: float, source_id: String, _attack_id: String) -> void:
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
	if _health_label != null:
		_health_label.text = "CIBLE DÉTRUITE"
	if _health_bar_fill != null:
		_health_bar_fill.visible = false
	if _body_material != null:
		_body_material.albedo_color = Color("#3b302e")
	_update_status("")
	_update_effect_presentation()
	died.emit()
	if not _duel_mode:
		call_deferred("_reset_target")


func _reset_target() -> void:
	await get_tree().create_timer(1.25).timeout
	reset_combat_state()


func _update_label() -> void:
	if _health_label != null and combat_state != null and not _resetting:
		_health_label.text = "CIBLE  %d / %d" % [int(round(combat_state.health)), int(round(combat_state.max_health))]
	if _health_bar_fill != null and combat_state != null:
		var fraction := clampf(combat_state.health / maxf(combat_state.max_health, 0.001), 0.0, 1.0)
		var bar_width := 2.7 * fraction
		_health_bar_fill.visible = not _resetting and fraction > 0.0
		_health_bar_fill.scale = Vector3(bar_width, 1.0, 1.0)
		_health_bar_fill.position.x = -1.35 + bar_width * 0.5


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.7
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)


func _build_visuals() -> void:
	_body_mesh = MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.05, 1.10, 0.82)
	_body_mesh.mesh = body_mesh
	_body_mesh.position.y = 0.96
	_body_mesh.rotation_degrees.z = -2.0
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#8f302b")
	_body_material.metallic = 0.35
	_body_material.roughness = 0.62
	_body_mesh.material_override = _body_material
	add_child(_body_mesh)
	_register_locomotion_node(_body_mesh, "body")
	var chest_plate := MeshInstance3D.new()
	var chest_mesh := BoxMesh.new()
	chest_mesh.size = Vector3(0.78, 0.48, 0.10)
	chest_plate.mesh = chest_mesh
	chest_plate.position = Vector3(0.0, 1.02, 0.47)
	chest_plate.rotation_degrees.x = -5.0
	chest_plate.material_override = _robot_material(Color("#c46c3f"), 0.42)
	add_child(chest_plate)
	_register_locomotion_node(chest_plate, "body")
	var reactor := MeshInstance3D.new()
	var reactor_mesh := CylinderMesh.new()
	reactor_mesh.top_radius = 0.16
	reactor_mesh.bottom_radius = 0.22
	reactor_mesh.height = 0.10
	reactor.mesh = reactor_mesh
	reactor.position = Vector3(0.0, 1.03, 0.55)
	reactor.rotation_degrees.x = 90.0
	reactor.material_override = _effect_material(Color("#8cf6ff"), Color("#32dceb"))
	add_child(reactor)
	_register_locomotion_node(reactor, "body")
	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.16
	neck_mesh.bottom_radius = 0.20
	neck_mesh.height = 0.20
	neck.mesh = neck_mesh
	neck.position.y = 1.60
	neck.material_override = _robot_material(Color("#3f3536"), 0.72)
	add_child(neck)
	_register_locomotion_node(neck, "body")
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.47
	head_mesh.height = 0.62
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.93, 0.0)
	head.scale = Vector3(1.0, 0.86, 0.92)
	head.material_override = _robot_material(Color("#a34432"), 0.48)
	add_child(head)
	_register_locomotion_node(head, "head")
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.58, 0.14, 0.08)
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 1.95, 0.42)
	visor.material_override = _effect_material(Color("#ff8a65"), Color("#ff2d22"))
	add_child(visor)
	_register_locomotion_node(visor, "head")
	for side in [-1.0, 1.0]:
		var shoulder := MeshInstance3D.new()
		var shoulder_mesh := SphereMesh.new()
		shoulder_mesh.radius = 0.27
		shoulder_mesh.height = 0.40
		shoulder.mesh = shoulder_mesh
		shoulder.position = Vector3(side * 0.68, 1.24, 0.0)
		shoulder.scale = Vector3(1.0, 0.85, 0.88)
		shoulder.material_override = _robot_material(Color("#5a3837"), 0.72)
		add_child(shoulder)
		_register_locomotion_node(shoulder, "body", 0.0 if side < 0.0 else PI)
		var upper_arm := MeshInstance3D.new()
		var upper_mesh := CylinderMesh.new()
		upper_mesh.top_radius = 0.13
		upper_mesh.bottom_radius = 0.18
		upper_mesh.height = 0.50
		upper_arm.mesh = upper_mesh
		upper_arm.position = Vector3(side * 0.76, 0.88, 0.0)
		upper_arm.rotation_degrees.z = side * -12.0
		upper_arm.material_override = _robot_material(Color("#b65a3e"), 0.60)
		add_child(upper_arm)
		_register_locomotion_node(upper_arm, "limb", 0.0 if side < 0.0 else PI)
		var fist := MeshInstance3D.new()
		var fist_mesh := BoxMesh.new()
		fist_mesh.size = Vector3(0.28, 0.28, 0.30)
		fist.mesh = fist_mesh
		fist.position = Vector3(side * 0.81, 0.54, 0.03)
		fist.rotation_degrees.z = side * -8.0
		fist.material_override = _robot_material(Color("#43383b"), 0.86)
		add_child(fist)
		_register_locomotion_node(fist, "limb", 0.0 if side < 0.0 else PI)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.18
		leg_mesh.height = 0.55
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.29, 0.32, 0.0)
		leg.material_override = _robot_material(Color("#43383b"), 0.86)
		add_child(leg)
		_register_locomotion_node(leg, "limb", 0.0 if side < 0.0 else PI)
		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.34, 0.16, 0.52)
		foot.mesh = foot_mesh
		foot.position = Vector3(side * 0.29, 0.04, 0.13)
		foot.material_override = _robot_material(Color("#8d4435"), 0.60)
		add_child(foot)
		_register_locomotion_node(foot, "limb", 0.0 if side < 0.0 else PI)
	_impact_light = OmniLight3D.new()
	_impact_light.light_energy = 0.0
	_impact_light.omni_range = 3.0
	_impact_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(_impact_light)

	_health_label = Label3D.new()
	_health_label.position = Vector3(0.0, 2.72, 0.0)
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.font_size = 46
	_health_label.outline_size = 10
	_health_label.modulate = Color("#ffd0c5")
	add_child(_health_label)

	_health_bar_bg = MeshInstance3D.new()
	_health_bar_bg.name = "HealthBarBackground"
	var health_bar_bg_mesh := BoxMesh.new()
	health_bar_bg_mesh.size = Vector3(2.7, 0.24, 0.08)
	_health_bar_bg.mesh = health_bar_bg_mesh
	_health_bar_bg.position = Vector3(0.0, 2.38, 0.0)
	_health_bar_bg.material_override = _effect_material(Color("#251b1d"), Color("#080405"))
	add_child(_health_bar_bg)

	_health_bar_fill = MeshInstance3D.new()
	_health_bar_fill.name = "HealthBarFill"
	var health_bar_fill_mesh := BoxMesh.new()
	health_bar_fill_mesh.size = Vector3(1.0, 0.17, 0.10)
	_health_bar_fill.mesh = health_bar_fill_mesh
	_health_bar_fill.position = Vector3(-1.35, 2.38, 0.06)
	_health_bar_fill.material_override = _effect_material(Color("#62ef78"), Color("#25c954"))
	add_child(_health_bar_fill)

	_status_label = Label3D.new()
	_status_label.position = Vector3(1.35, 3.02, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 32
	_status_label.outline_size = 10
	_status_label.modulate = Color("#fff1a8")
	add_child(_status_label)
	_build_effect_visuals()


func _build_effect_visuals() -> void:
	_burn_fx = Node3D.new()
	_burn_fx.name = "BurnVisual"
	for index in range(3):
		var flame := MeshInstance3D.new()
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.21
		flame_mesh.height = 0.60
		flame.mesh = flame_mesh
		flame.position = Vector3(-0.30 + float(index) * 0.30, 1.48 + float(index % 2) * 0.28, 0.70)
		flame.material_override = _effect_material(Color("#ff7b3e"), Color("#ff3d1e"))
		_burn_fx.add_child(flame)
	for index in range(3):
		var ember := MeshInstance3D.new()
		var ember_mesh := BoxMesh.new()
		ember_mesh.size = Vector3(0.06, 0.16, 0.06)
		ember.mesh = ember_mesh
		ember.position = Vector3(-0.36 + float(index) * 0.36, 1.68 + float(index % 2) * 0.22, 0.74)
		ember.material_override = _effect_material(Color("#ffd37a"), Color("#ff5a25"))
		_burn_fx.add_child(ember)
	add_child(_burn_fx)
	_burn_light = OmniLight3D.new()
	_burn_light.name = "BurnLight"
	_burn_light.light_color = Color("#ff733c")
	_burn_light.omni_range = 3.0
	_burn_light.shadow_enabled = false
	_burn_light.position = Vector3(0.0, 1.35, 0.62)
	_burn_light.light_energy = 0.0
	add_child(_burn_light)

	_slow_fx = Node3D.new()
	_slow_fx.name = "SlowVisual"
	for index in range(5):
		var mote := MeshInstance3D.new()
		var mote_mesh := SphereMesh.new()
		mote_mesh.radius = 0.10
		mote_mesh.height = 0.20
		mote.mesh = mote_mesh
		var angle := TAU * float(index) / 5.0
		mote.position = Vector3(cos(angle) * 0.76, 0.14, sin(angle) * 0.76)
		mote.material_override = _effect_material(Color("#88dfff"), Color("#36b9ef"))
		_slow_fx.add_child(mote)
	add_child(_slow_fx)
	_slow_ring = MeshInstance3D.new()
	_slow_ring.name = "SlowRing"
	var slow_ring_mesh := TorusMesh.new()
	slow_ring_mesh.inner_radius = 0.66
	slow_ring_mesh.outer_radius = 0.84
	slow_ring_mesh.rings = 12
	slow_ring_mesh.ring_segments = 24
	_slow_ring.mesh = slow_ring_mesh
	_slow_ring.position.y = 0.06
	_slow_ring.rotation_degrees.x = 90.0
	_slow_ring.material_override = _effect_material(Color("#63dcff"), Color("#20cfff"))
	add_child(_slow_ring)
	_slow_light = OmniLight3D.new()
	_slow_light.name = "SlowLight"
	_slow_light.light_color = Color("#38d5e6")
	_slow_light.omni_range = 2.8
	_slow_light.shadow_enabled = false
	_slow_light.position = Vector3(0.0, 0.30, 0.0)
	_slow_light.light_energy = 0.0
	add_child(_slow_light)

	_stun_fx = MeshInstance3D.new()
	_stun_fx.name = "StunHalo"
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.40
	halo_mesh.outer_radius = 0.58
	halo_mesh.rings = 10
	halo_mesh.ring_segments = 16
	_stun_fx.mesh = halo_mesh
	_stun_fx.position.y = 2.22
	_stun_fx.rotation_degrees.x = 90.0
	_stun_fx.material_override = _effect_material(Color("#ffe16a"), Color("#ffb52e"))
	add_child(_stun_fx)
	for index in range(4):
		var stun_spark := MeshInstance3D.new()
		var stun_mesh := BoxMesh.new()
		stun_mesh.size = Vector3(0.06, 0.30, 0.06)
		stun_spark.mesh = stun_mesh
		var angle := TAU * float(index) / 4.0
		stun_spark.position = Vector3(cos(angle) * 0.50, 2.22, sin(angle) * 0.50)
		stun_spark.rotation_degrees.z = -32.0 if index % 2 == 0 else 32.0
		stun_spark.material_override = _effect_material(Color("#fff2a4"), Color("#ff9d2e"))
		_stun_fx.add_child(stun_spark)

	_spotted_fx = Label3D.new()
	_spotted_fx.name = "SpottedEye"
	_spotted_fx.text = "◎"
	_spotted_fx.position = Vector3(-0.10, 4.08, 0.0)
	_spotted_fx.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_spotted_fx.font_size = 118
	_spotted_fx.outline_size = 18
	_spotted_fx.modulate = Color("#efffff")
	add_child(_spotted_fx)
	_spotted_emblem = MeshInstance3D.new()
	_spotted_emblem.name = "SpottedEmblem"
	var spotted_emblem_mesh := TorusMesh.new()
	spotted_emblem_mesh.inner_radius = 0.20
	spotted_emblem_mesh.outer_radius = 0.30
	spotted_emblem_mesh.rings = 10
	spotted_emblem_mesh.ring_segments = 20
	_spotted_emblem.mesh = spotted_emblem_mesh
	_spotted_emblem.position = Vector3(-0.10, 3.86, 0.0)
	_spotted_emblem.rotation_degrees.x = 90.0
	_spotted_emblem.scale = Vector3(1.15, 1.0, 1.15)
	_spotted_emblem.material_override = _effect_material(Color("#9ffaff"), Color("#38d5e6"))
	add_child(_spotted_emblem)
	_spotted_pupil = MeshInstance3D.new()
	_spotted_pupil.name = "SpottedPupil"
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = 0.12
	pupil_mesh.height = 0.08
	_spotted_pupil.mesh = pupil_mesh
	_spotted_pupil.position = Vector3(-0.10, 3.86, -0.02)
	_spotted_pupil.scale = Vector3(1.0, 0.55, 1.0)
	_spotted_pupil.material_override = _effect_material(Color("#e8ffff"), Color("#ffffff"))
	add_child(_spotted_pupil)
	_spotted_light = OmniLight3D.new()
	_spotted_light.name = "SpottedLight"
	_spotted_light.light_color = Color("#38d5e6")
	_spotted_light.omni_range = 3.2
	_spotted_light.shadow_enabled = false
	_spotted_light.position = Vector3(0.0, 3.20, 0.45)
	_spotted_light.light_energy = 0.0
	add_child(_spotted_light)

	_javelin_mark_label = Label3D.new()
	_javelin_mark_label.name = "JavelinMark"
	_javelin_mark_label.text = "✦ JAVELIN"
	_javelin_mark_label.position = Vector3(0.0, 3.62, 0.0)
	_javelin_mark_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_javelin_mark_label.font_size = 42
	_javelin_mark_label.outline_size = 10
	_javelin_mark_label.modulate = Color("#ffdb75")
	add_child(_javelin_mark_label)


func _effect_material(color: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 2.2
	return material


func _register_fx_budget(node: Node, category: String = "burst") -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_method("register_fx_node"):
		scene.call("register_fx_node", node, category)


func _robot_material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.58
	return material


func _update_effect_presentation() -> void:
	if combat_state == null:
		return
	var burning: bool = bool(combat_state.has_effect(COMBAT_DATA.EFFECT_BURN))
	var slowed: bool = bool(combat_state.has_effect(COMBAT_DATA.EFFECT_SLOW))
	var stunned: bool = bool(combat_state.has_effect(COMBAT_DATA.EFFECT_STUN))
	var spotted: bool = bool(combat_state.has_effect(COMBAT_DATA.EFFECT_SPOTTED))
	if _burn_fx != null:
		_burn_fx.visible = burning
		_burn_fx.rotation.y = _effect_clock * 1.8
		_burn_fx.scale = Vector3.ONE * (1.0 + sin(_effect_clock * 8.0) * 0.08)
		for index in range(_burn_fx.get_child_count()):
			var flame := _burn_fx.get_child(index) as MeshInstance3D
			if flame == null:
				continue
			var pulse := 0.92 + sin(_effect_clock * 12.0 + float(index) * 1.7) * 0.22
			flame.scale = Vector3(pulse, 1.0 + sin(_effect_clock * 10.0 + float(index)) * 0.28, pulse)
			flame.position.y = 1.48 + float(index % 2) * 0.28 + sin(_effect_clock * 7.0 + float(index) * 2.0) * 0.10
			flame.position.z = 0.70 + sin(_effect_clock * 6.0 + float(index)) * 0.06
			flame.rotation.z = sin(_effect_clock * 9.0 + float(index)) * 0.35
	if _burn_light != null:
		_burn_light.light_energy = (2.0 + sin(_effect_clock * 11.0) * 0.55) if burning else 0.0
	if _slow_fx != null:
		_slow_fx.visible = slowed
		_slow_fx.rotation.y = -_effect_clock * 2.2
		for index in range(_slow_fx.get_child_count()):
			var mote := _slow_fx.get_child(index) as MeshInstance3D
			if mote == null:
				continue
			var angle := _effect_clock * 2.6 + TAU * float(index) / 5.0
			mote.position = Vector3(cos(angle) * 0.78, 0.14 + sin(_effect_clock * 5.0 + float(index)) * 0.12, sin(angle) * 0.78)
			var mote_scale := 0.90 + sin(_effect_clock * 8.0 + float(index)) * 0.18
			mote.scale = Vector3.ONE * mote_scale
	if _slow_ring != null:
		_slow_ring.visible = slowed
		_slow_ring.rotation_degrees.y = fmod(_effect_clock * 165.0, 360.0)
		_slow_ring.scale = Vector3.ONE * (1.0 + sin(_effect_clock * 7.0) * 0.12)
	if _slow_light != null:
		_slow_light.light_energy = (1.25 + sin(_effect_clock * 8.0) * 0.35) if slowed else 0.0
	if _stun_fx != null:
		_stun_fx.visible = stunned
		_stun_fx.rotation_degrees.y = fmod(_effect_clock * 180.0, 360.0)
	if _spotted_fx != null:
		_spotted_fx.visible = spotted
		_spotted_fx.scale = Vector3.ONE * (1.0 + sin(_effect_clock * 5.0) * 0.12)
	if _spotted_emblem != null:
		_spotted_emblem.visible = spotted
		_spotted_emblem.scale = Vector3(1.15, 1.0, 1.15) * (1.0 + sin(_effect_clock * 5.0) * 0.10)
	if _spotted_pupil != null:
		_spotted_pupil.visible = spotted
		_spotted_pupil.scale = Vector3.ONE * (1.0 + sin(_effect_clock * 6.0) * 0.08)
	if _spotted_light != null:
		_spotted_light.light_energy = (2.0 + sin(_effect_clock * 7.0) * 0.45) if spotted else 0.0
	if _javelin_mark_label != null:
		_javelin_mark_label.visible = has_javelin_mark()
		if _javelin_mark_label.visible:
			_javelin_mark_label.scale = Vector3.ONE * (1.0 + sin(_effect_clock * 9.0) * 0.10)
	var lines: Array[String] = []
	if burning:
		lines.append("BURN  %.1fs" % combat_state.get_remaining(COMBAT_DATA.EFFECT_BURN))
	if slowed:
		lines.append("SLOW  %d%%  %.1fs" % [int(round(combat_state.get_slow_percent())), combat_state.get_remaining(COMBAT_DATA.EFFECT_SLOW)])
	if stunned:
		lines.append("STUN  %.1fs" % combat_state.get_remaining(COMBAT_DATA.EFFECT_STUN))
	if spotted:
		lines.append("SPOTTED  %.1fs" % combat_state.get_remaining(COMBAT_DATA.EFFECT_SPOTTED))
	if has_javelin_mark():
		lines.append("JAVELIN  %.1fs" % maxf(0.0, _javelin_mark_until - Time.get_ticks_msec() / 1000.0))
	_update_status("\n".join(lines))


func _update_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
