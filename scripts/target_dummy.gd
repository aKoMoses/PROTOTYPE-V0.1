extends StaticBody3D

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const COMBAT_STATE := preload("res://scripts/combat_state.gd")

var combat_state
var _resetting := false
var _health_label: Label3D
var _body_material: StandardMaterial3D
var _status_label: Label3D
var _body_mesh: MeshInstance3D
var _impact_light: OmniLight3D
var _burn_fx: Node3D
var _slow_fx: Node3D
var _stun_fx: MeshInstance3D
var _spotted_fx: Label3D
var _effect_clock := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	combat_state = COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH)
	combat_state.health_changed.connect(_on_health_changed)
	combat_state.effect_changed.connect(_on_effect_changed)
	combat_state.died.connect(_on_state_died)
	_build_collision()
	_build_visuals()
	_update_label()
	_update_effect_presentation()


func _process(delta: float) -> void:
	_effect_clock += delta
	if combat_state != null and not _resetting:
		combat_state.update(delta)
	_update_effect_presentation()


## Shared combat API used by the player, future bot and Training Lab.
func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if _resetting or combat_state == null:
		return 0.0
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


func reset_combat_state() -> void:
	_resetting = false
	if combat_state != null:
		combat_state.reset()
	if _body_material != null:
		_body_material.albedo_color = Color("#8f302b")
	_update_status("")
	_update_label()


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
	tween.tween_callback(_clear_impact_flash)


func _clear_impact_flash() -> void:
	if _body_material != null:
		_body_material.emission_enabled = false


func _on_health_changed(_current: float, _maximum: float) -> void:
	_update_label()


func _on_effect_changed(_effect_type: String, _active: bool) -> void:
	_update_effect_presentation()


func _on_state_died() -> void:
	if _resetting:
		return
	_resetting = true
	if _health_label != null:
		_health_label.text = "CIBLE DÉTRUITE"
	if _body_material != null:
		_body_material.albedo_color = Color("#3b302e")
	_update_status("")
	_update_effect_presentation()
	call_deferred("_reset_target")


func _reset_target() -> void:
	await get_tree().create_timer(1.25).timeout
	reset_combat_state()


func _update_label() -> void:
	if _health_label != null and combat_state != null and not _resetting:
		_health_label.text = "CIBLE  %d / %d" % [int(round(combat_state.health)), int(round(combat_state.max_health))]


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
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.72
	body_mesh.height = 1.45
	_body_mesh.mesh = body_mesh
	_body_mesh.position.y = 0.9
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#8f302b")
	_body_material.metallic = 0.35
	_body_material.roughness = 0.62
	_body_mesh.material_override = _body_material
	add_child(_body_mesh)
	_impact_light = OmniLight3D.new()
	_impact_light.light_energy = 0.0
	_impact_light.omni_range = 3.0
	_impact_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(_impact_light)

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.2
	eye_mesh.height = 0.3
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 1.2, 0.66)
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color("#ff503f")
	eye_material.emission_enabled = true
	eye_material.emission = Color("#ff241d")
	eye_material.emission_energy_multiplier = 3.5
	eye.material_override = eye_material
	add_child(eye)

	_health_label = Label3D.new()
	_health_label.position = Vector3(0.0, 2.25, 0.0)
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.font_size = 38
	_health_label.outline_size = 8
	_health_label.modulate = Color("#ff8b78")
	add_child(_health_label)

	_status_label = Label3D.new()
	_status_label.position = Vector3(0.0, 2.75, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 28
	_status_label.outline_size = 6
	_status_label.modulate = Color("#ffe28a")
	add_child(_status_label)
	_build_effect_visuals()


func _build_effect_visuals() -> void:
	_burn_fx = Node3D.new()
	_burn_fx.name = "BurnVisual"
	for index in range(3):
		var flame := MeshInstance3D.new()
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.12
		flame_mesh.height = 0.34
		flame.mesh = flame_mesh
		flame.position = Vector3(-0.22 + float(index) * 0.22, 1.55 + float(index % 2) * 0.18, 0.0)
		flame.material_override = _effect_material(Color("#ff7b3e"), Color("#ff3d1e"))
		_burn_fx.add_child(flame)
	add_child(_burn_fx)

	_slow_fx = Node3D.new()
	_slow_fx.name = "SlowVisual"
	for index in range(5):
		var mote := MeshInstance3D.new()
		var mote_mesh := SphereMesh.new()
		mote_mesh.radius = 0.055
		mote_mesh.height = 0.11
		mote.mesh = mote_mesh
		var angle := TAU * float(index) / 5.0
		mote.position = Vector3(cos(angle) * 0.48, 0.10, sin(angle) * 0.48)
		mote.material_override = _effect_material(Color("#88dfff"), Color("#36b9ef"))
		_slow_fx.add_child(mote)
	add_child(_slow_fx)

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

	_spotted_fx = Label3D.new()
	_spotted_fx.name = "SpottedEye"
	_spotted_fx.text = "◉"
	_spotted_fx.position = Vector3(0.0, 3.22, 0.0)
	_spotted_fx.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_spotted_fx.font_size = 34
	_spotted_fx.outline_size = 6
	_spotted_fx.modulate = Color("#9ffaff")
	add_child(_spotted_fx)


func _effect_material(color: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 2.2
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
	if _slow_fx != null:
		_slow_fx.visible = slowed
		_slow_fx.rotation.y = -_effect_clock * 2.2
	if _stun_fx != null:
		_stun_fx.visible = stunned
		_stun_fx.rotation_degrees.y = fmod(_effect_clock * 180.0, 360.0)
	if _spotted_fx != null:
		_spotted_fx.visible = spotted
	var lines: Array[String] = []
	if burning:
		lines.append("BURN  %.1fs" % combat_state.get_remaining(COMBAT_DATA.EFFECT_BURN))
	if slowed:
		lines.append("SLOW  %d%%  %.1fs" % [int(round(combat_state.get_slow_percent())), combat_state.get_remaining(COMBAT_DATA.EFFECT_SLOW)])
	if stunned:
		lines.append("STUN  %.1fs" % combat_state.get_remaining(COMBAT_DATA.EFFECT_STUN))
	if spotted:
		lines.append("SPOTTED  %.1fs" % combat_state.get_remaining(COMBAT_DATA.EFFECT_SPOTTED))
	_update_status("\n".join(lines))


func _update_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
