class_name ProjectorShockwave
extends RefCounted

## Resolve contacts once; actors own the collision-aware, decelerating recoil.
const COMBAT_DATA := preload("res://scripts/combat_data.gd")


static func activate(caster: Node3D, targets: Array, source_id: String, emergency := false) -> void:
	var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.projector
	var center := caster.global_position
	var hit_ids: Dictionary = {}
	for candidate in targets:
		if not is_instance_valid(candidate) or not candidate is CollisionObject3D or candidate == caster:
			continue
		var target := candidate as CollisionObject3D
		if not target.has_method("apply_slow") or not target.has_method("get_health") or float(target.call("get_health")) <= 0.0:
			continue
		if target.has_method("is_real_dead") and bool(target.call("is_real_dead")):
			continue
		if target.has_method("get_stasis_remaining") and float(target.call("get_stasis_remaining")) > 0.0:
			continue
		if bool(target.get_meta("duel_static_shield", false)) or hit_ids.has(target.get_instance_id()):
			continue
		var offset := target.global_position - center
		offset.y = 0.0
		var distance := offset.length()
		if distance > float(definition.radius):
			continue
		hit_ids[target.get_instance_id()] = true
		var strength := clampf(1.0 - distance / float(definition.radius), 0.0, 1.0)
		var push := lerpf(float(definition.push_min), float(definition.push_max), strength)
		var slow := lerpf(float(definition.slow_min), float(definition.slow_max), strength)
		var direction := offset / distance if distance > 0.001 else Vector3.FORWARD
		if target.has_method("is_eclipse_travelling") and bool(target.call("is_eclipse_travelling")):
			continue
		if target.has_method("start_knockback"):
			target.call("start_knockback", direction, push, float(definition.push_duration), source_id)
		target.call("apply_slow", float(definition.slow_duration), slow, source_id)
	spawn_visual(caster.get_tree().current_scene, center, emergency)


static func _material(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _ring(parent: Node3D, height: float, color: Color, thickness: float = 0.025) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.0 - thickness
	mesh.outer_radius = 1.0 + thickness
	mesh.rings = 96
	mesh.ring_segments = 12
	ring.mesh = mesh
	ring.material_override = _material(color)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.position.y = height
	return ring


static func spawn_cast(caster: Node3D, duration: float) -> Node3D:
	var effect := Node3D.new()
	effect.name = "ProjectorCast"
	caster.add_child(effect)
	var sfx := caster.get_node_or_null("/root/GameSfx")
	if sfx != null:
		effect.set_meta("charge_voice", sfx.call("play_module_event", "projector_charge", caster.global_position))
	effect.add_to_group("prototype0_fx_budget")
	var floor_ring := _ring(effect, 0.1, Color(0.3, 0.85, 1.0, 0.8), 0.04)
	floor_ring.scale = Vector3(1.3, 0.8, 1.3)
	var halo := _ring(effect, 0.65, Color(0.7, 0.95, 1.0, 0.65), 0.03)
	halo.scale = Vector3(0.85, 1.0, 0.85)
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(floor_ring, "scale", Vector3(0.45, 1.0, 0.45), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(halo, "scale", Vector3(0.38, 1.0, 0.38), duration)
	tween.tween_property(halo, "position:y", 0.95, duration)
	tween.tween_property(floor_ring.material_override, "emission_energy_multiplier", 4.0, duration)
	tween.chain().tween_interval(0.06)
	tween.chain().tween_callback(effect.queue_free)
	return effect


static func spawn_visual(scene: Node, center: Vector3, emergency := false) -> void:
	if scene == null:
		return
	var sfx := scene.get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.call("play_module_event", "projector_passive" if emergency else "projector_wave", center)
		sfx.call("play_module_event", "projector_push", center)
	var effect := Node3D.new()
	effect.name = "ProjectorShockwave"
	scene.add_child(effect)
	effect.global_position = center
	effect.add_to_group("prototype0_fx_budget")
	var radius := float(COMBAT_DATA.MODULE_DEFINITIONS.projector.radius)
	var front := _ring(effect, 0.14, Color(0.6, 0.94, 1.0, 0.95))
	front.scale = Vector3(0.15, 0.7, 0.15)
	var echo := _ring(effect, 0.45, Color(0.2, 0.7, 1.0, 0.65), 0.018)
	echo.scale = Vector3(0.12, 0.5, 0.12)
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 16
	shell.mesh = sphere
	shell.material_override = _material(Color(0.25, 0.8, 1.0, 0.14), 1.2)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.add_child(shell)
	shell.position.y = 0.3
	shell.scale = Vector3(0.2, 0.2, 0.2)
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(front, "scale", Vector3(radius, 0.5, radius), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(front.material_override, "albedo_color:a", 0.0, 0.23).set_delay(0.13)
	tween.tween_property(echo, "scale", Vector3(radius * 0.96, 0.2, radius * 0.96), 0.34).set_delay(0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(echo.material_override, "albedo_color:a", 0.0, 0.25).set_delay(0.16)
	tween.tween_property(shell, "scale", Vector3(radius, 0.8, radius), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell.material_override, "albedo_color:a", 0.0, 0.25)
	for i in range(18):
		var angle := TAU * float(i) / 18.0
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		var streak := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.035, 0.035, 0.55)
		streak.mesh = mesh
		streak.material_override = _material(Color(0.55, 0.92, 1.0, 0.7))
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effect.add_child(streak)
		streak.position = direction * 0.7 + Vector3.UP * (0.22 + float(i % 3) * 0.2)
		streak.rotation.y = angle
		tween.tween_property(streak, "position", direction * (radius + 0.2) + Vector3.UP * 0.18, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(streak.material_override, "albedo_color:a", 0.0, 0.22).set_delay(0.08)
	tween.chain().tween_callback(effect.queue_free)
