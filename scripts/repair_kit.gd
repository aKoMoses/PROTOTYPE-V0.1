class_name RepairKit
extends Area3D

signal consumed(actor: Node3D, amount: float)
signal availability_changed(available: bool)

enum KitState {
	DISABLED,
	AVAILABLE,
	RECHARGING,
}

const ACTOR_COLLISION_MASK := 2 | 4
const ENVIRONMENT_COLLISION_MASK := 1 | 8
const GREEN := Color("#2fd46b")
const GREEN_BRIGHT := Color("#72f49a")
const GREEN_HALO := Color("#47ed7d")
const GREY := Color("#858c8a")
const GREY_DARK := Color("#4d5452")
const BAR_WIDTH := 1.12
const BAR_HEIGHT := 0.17
const BAR_INNER_WIDTH := 1.02
const BAR_INNER_HEIGHT := 0.105

@export_range(0.01, 1.0, 0.01) var heal_fraction := 0.30
@export_range(0.05, 120.0, 0.05) var respawn_delay := 20.0
@export_range(0.5, 4.0, 0.05) var collection_radius := 1.45
@export_range(0.5, 3.0, 0.05) var visual_scale := 1.75
@export var point_enabled := true

var _state := KitState.AVAILABLE
var _collection_active := true
var _consume_locked := false
var _respawn_remaining := 0.0
var _animation_clock := 0.0
var _kit_visual: Node3D
var _floating_cross: Node3D
var _permanent_base: MeshInstance3D
var _ground_halo: Node3D
var _ground_halo_material: StandardMaterial3D
var _cross_face_parts: Array[MeshInstance3D] = []
var _cross_back_parts: Array[MeshInstance3D] = []
var _available_face_material: StandardMaterial3D
var _available_back_material: StandardMaterial3D
var _recharging_face_material: StandardMaterial3D
var _recharging_back_material: StandardMaterial3D
var _recharge_bar: Node3D
var _recharge_fill: MeshInstance3D
var _return_animation_remaining := 0.0
var _return_tween: Tween


func _ready() -> void:
	add_to_group("repair_kits")
	add_to_group("health_kit_placeholder")
	collision_layer = 0
	collision_mask = ACTOR_COLLISION_MASK
	monitoring = true
	monitorable = false
	_build_collection_shape()
	_build_visuals()
	body_entered.connect(_on_body_entered)
	_state = KitState.AVAILABLE if point_enabled else KitState.DISABLED
	_apply_state_visuals(false)


func _process(delta: float) -> void:
	_animation_clock += maxf(0.0, delta)
	_return_animation_remaining = maxf(0.0, _return_animation_remaining - delta)
	if _state == KitState.AVAILABLE:
		_animate_available_kit()
		return
	if _state != KitState.RECHARGING:
		return
	_respawn_remaining = maxf(0.0, _respawn_remaining - delta)
	_update_recharge_bar()
	if _respawn_remaining <= 0.0:
		_respawn()


func _physics_process(_delta: float) -> void:
	if is_available():
		_try_overlapping_bodies()


func is_available() -> bool:
	return point_enabled and _collection_active and _state == KitState.AVAILABLE and not _consume_locked


func get_visual_state() -> int:
	return _state


func get_visual_state_name() -> String:
	match _state:
		KitState.AVAILABLE:
			return "available"
		KitState.RECHARGING:
			return "recharging"
		_:
			return "disabled"


func get_collection_radius() -> float:
	return collection_radius


func get_respawn_remaining() -> float:
	return maxf(0.0, _respawn_remaining)


func get_respawn_progress() -> float:
	if _state != KitState.RECHARGING or respawn_delay <= 0.0:
		return 1.0 if _state == KitState.AVAILABLE else 0.0
	return clampf(1.0 - _respawn_remaining / respawn_delay, 0.0, 1.0)


func set_collection_active(value: bool) -> void:
	_collection_active = value
	if value and is_available():
		call_deferred("_try_overlapping_bodies")


func set_point_enabled(value: bool) -> void:
	point_enabled = value
	_consume_locked = false
	_respawn_remaining = 0.0
	_set_state(KitState.AVAILABLE if point_enabled else KitState.DISABLED, false)


func reset_for_round(collection_active: bool = false) -> void:
	_collection_active = collection_active
	_consume_locked = false
	_respawn_remaining = 0.0
	_set_state(KitState.AVAILABLE if point_enabled else KitState.DISABLED, false)
	availability_changed.emit(is_available())
	if is_available():
		call_deferred("_try_overlapping_bodies")


func try_collect(actor: Node3D) -> float:
	if not is_available() or not _actor_can_receive_repair(actor):
		return 0.0
	var flat_distance := Vector2(actor.global_position.x - global_position.x, actor.global_position.z - global_position.z).length()
	if flat_distance > collection_radius + 0.35:
		return 0.0
	if not _has_clear_access(actor):
		return 0.0
	_consume_locked = true
	var maximum := float(actor.call("get_max_health"))
	var applied := float(actor.call("heal", maximum * heal_fraction, "repair_pickup"))
	if applied <= 0.0:
		_consume_locked = false
		return 0.0
	_respawn_remaining = maxf(0.05, respawn_delay)
	_consume_locked = false
	_set_state(KitState.RECHARGING, false)
	_play_pickup_feedback(actor)
	consumed.emit(actor, applied)
	availability_changed.emit(false)
	return applied


func is_accessible_to(actor: Node3D) -> bool:
	return actor != null and is_instance_valid(actor) and _has_clear_access(actor)


func _on_body_entered(body: Node3D) -> void:
	try_collect(body)


func _actor_can_receive_repair(actor: Node3D) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if not actor.has_method("heal") or not actor.has_method("get_health") or not actor.has_method("get_max_health"):
		return false
	if actor.has_method("is_real_dead") and bool(actor.call("is_real_dead")):
		return false
	var current := float(actor.call("get_health"))
	var maximum := float(actor.call("get_max_health"))
	return maximum > 0.0 and current > 0.0 and current < maximum - 0.001


func _has_clear_access(actor: Node3D) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var origin := global_position + Vector3.UP * 0.55
	var destination := actor.global_position + Vector3.UP * 0.72
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	query.collision_mask = ENVIRONMENT_COLLISION_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _try_overlapping_bodies() -> void:
	if not is_available():
		return
	# A respawned kit is immediately collectible by an injured actor who never
	# left the pad. The availability lock still permits only the first body.
	var bodies := get_overlapping_bodies()
	bodies.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position)
	)
	for body in bodies:
		if try_collect(body) > 0.0:
			return


func _respawn() -> void:
	if not point_enabled:
		return
	_respawn_remaining = 0.0
	_set_state(KitState.AVAILABLE, true)
	availability_changed.emit(is_available())
	call_deferred("_try_overlapping_bodies")


func _set_state(next_state: int, play_return_animation: bool) -> void:
	_state = next_state
	_apply_state_visuals(play_return_animation)


func _apply_state_visuals(play_return_animation: bool) -> void:
	if _kit_visual == null:
		return
	if _return_tween != null and _return_tween.is_valid():
		_return_tween.kill()
	_return_tween = null
	_return_animation_remaining = 0.0
	var enabled := _state != KitState.DISABLED
	var available := _state == KitState.AVAILABLE
	var recharging := _state == KitState.RECHARGING
	_kit_visual.visible = enabled
	if _permanent_base != null:
		_permanent_base.visible = enabled
	if _ground_halo != null:
		_ground_halo.visible = available
	for part in _cross_face_parts:
		part.material_override = _available_face_material if available else _recharging_face_material
	for part in _cross_back_parts:
		part.material_override = _available_back_material if available else _recharging_back_material
	if _recharge_bar != null:
		_recharge_bar.visible = recharging
	if _floating_cross != null:
		_floating_cross.position.y = 0.34
		_floating_cross.scale = Vector3.ONE
	if available and play_return_animation:
		_return_animation_remaining = 0.44
		_floating_cross.scale = Vector3.ONE * 0.62
		_return_tween = create_tween()
		_return_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_return_tween.tween_property(_floating_cross, "scale", Vector3.ONE * 1.14, 0.23)
		_return_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_return_tween.tween_property(_floating_cross, "scale", Vector3.ONE, 0.17)
	_update_recharge_bar()


func _animate_available_kit() -> void:
	if _floating_cross == null or not _kit_visual.visible:
		return
	var pulse_phase := sin(_animation_clock * 3.9)
	_floating_cross.position.y = 0.34 + sin(_animation_clock * 2.4) * 0.025
	if _return_animation_remaining <= 0.0:
		var pulse := 1.0 + pulse_phase * 0.025
		_floating_cross.scale = Vector3.ONE * pulse
	if _available_face_material != null:
		_available_face_material.emission_energy_multiplier = 0.86 + pulse_phase * 0.12
	if _ground_halo != null:
		var halo_pulse := 1.0 + pulse_phase * 0.035
		_ground_halo.scale = Vector3(halo_pulse, 1.0, halo_pulse)
	if _ground_halo_material != null:
		_ground_halo_material.emission_energy_multiplier = 0.52 + pulse_phase * 0.08


func _update_recharge_bar() -> void:
	if _recharge_fill == null:
		return
	var progress := get_respawn_progress() if _state == KitState.RECHARGING else 0.0
	_recharge_fill.visible = _state == KitState.RECHARGING and progress > 0.0001
	_recharge_fill.scale = Vector3(maxf(progress, 0.0001), 1.0, 1.0)
	_recharge_fill.position.x = -BAR_INNER_WIDTH * (1.0 - progress) * 0.5


func _play_pickup_feedback(actor: Node3D) -> void:
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null and sfx.has_method("play_event"):
		sfx.call("play_event", "repair_pickup")
	var pulse := Node3D.new()
	pulse.name = "RepairPulse"
	actor.add_child(pulse)
	pulse.position = Vector3.UP * 0.10
	for index in range(2):
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.62 + float(index) * 0.13
		ring_mesh.outer_radius = 0.72 + float(index) * 0.13
		ring_mesh.rings = 8
		ring_mesh.ring_segments = 24
		ring.mesh = ring_mesh
		ring.position.y = 0.18 + float(index) * 0.42
		ring.material_override = _material(Color(GREEN, 0.88), 0.30, GREEN, 1.6, true)
		pulse.add_child(ring)
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.24
	beam_mesh.bottom_radius = 0.55
	beam_mesh.height = 1.9
	beam_mesh.radial_segments = 16
	beam.mesh = beam_mesh
	beam.position.y = 0.95
	beam.material_override = _material(Color(GREEN, 0.16), 0.20, GREEN, 0.85, true)
	pulse.add_child(beam)
	pulse.scale = Vector3(0.45, 0.65, 0.45)
	var tween := pulse.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "scale", Vector3(1.55, 1.10, 1.55), 0.42)
	for child in pulse.get_children():
		if child is GeometryInstance3D:
			tween.tween_property(child, "transparency", 1.0, 0.42)
	tween.set_parallel(false)
	tween.tween_callback(pulse.queue_free)


func _build_collection_shape() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollectionShape"
	var shape := SphereShape3D.new()
	shape.radius = collection_radius
	collision.shape = shape
	collision.position.y = 0.58
	add_child(collision)


func _build_visuals() -> void:
	# The base is only a landmark. It has no collision and stays much smaller
	# than the old medical crate footprint.
	_permanent_base = MeshInstance3D.new()
	_permanent_base.name = "PermanentBase"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.57
	base_mesh.bottom_radius = 0.62
	base_mesh.height = 0.07
	base_mesh.radial_segments = 24
	_permanent_base.mesh = base_mesh
	_permanent_base.position.y = 0.035
	_permanent_base.material_override = _material(Color("#252a29"), 0.92)
	_permanent_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_permanent_base)

	_kit_visual = Node3D.new()
	_kit_visual.name = "ConsumableKit"
	_kit_visual.scale = Vector3.ONE * visual_scale
	add_child(_kit_visual)

	_ground_halo = Node3D.new()
	_ground_halo.name = "GroundHalo"
	_kit_visual.add_child(_ground_halo)
	_ground_halo_material = _material(Color(GREEN_HALO, 0.14), 0.35, GREEN_HALO, 0.52, true)
	var halo_disc := MeshInstance3D.new()
	halo_disc.name = "SoftDisc"
	var halo_disc_mesh := CylinderMesh.new()
	halo_disc_mesh.top_radius = 0.67
	halo_disc_mesh.bottom_radius = 0.67
	halo_disc_mesh.height = 0.008
	halo_disc_mesh.radial_segments = 32
	halo_disc.mesh = halo_disc_mesh
	halo_disc.position.y = 0.046
	halo_disc.material_override = _ground_halo_material
	halo_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_halo.add_child(halo_disc)
	var halo_ring := MeshInstance3D.new()
	halo_ring.name = "HaloRing"
	var halo_ring_mesh := TorusMesh.new()
	halo_ring_mesh.inner_radius = 0.64
	halo_ring_mesh.outer_radius = 0.70
	halo_ring_mesh.rings = 8
	halo_ring_mesh.ring_segments = 32
	halo_ring.mesh = halo_ring_mesh
	halo_ring.position.y = 0.055
	halo_ring.material_override = _ground_halo_material
	halo_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_halo.add_child(halo_ring)

	_available_face_material = _material(GREEN, 0.28, GREEN_BRIGHT, 0.86)
	_available_back_material = _material(Color(GREEN_HALO, 0.38), 0.30, GREEN_HALO, 0.82, true)
	_recharging_face_material = _material(GREY, 0.94)
	_recharging_back_material = _material(GREY_DARK, 0.96)
	_floating_cross = Node3D.new()
	_floating_cross.name = "FloatingCross"
	_floating_cross.position.y = 0.34
	_kit_visual.add_child(_floating_cross)
	_add_cross_parts(_floating_cross, -0.025, Vector2(1.46, 0.47), 0.10, _available_back_material, "CrossOutline", _cross_back_parts)
	_add_cross_parts(_floating_cross, 0.035, Vector2(1.30, 0.34), 0.11, _available_face_material, "CrossFace", _cross_face_parts)

	_build_recharge_bar()


func _build_recharge_bar() -> void:
	_recharge_bar = Node3D.new()
	_recharge_bar.name = "RechargeBar"
	_recharge_bar.position = Vector3(0.0, 0.92, 0.0)
	_kit_visual.add_child(_recharge_bar)
	var outline_material := _billboard_material(Color("#d2ddd7"), 0)
	var background_material := _billboard_material(Color("#151a19"), 1)
	var fill_material := _billboard_material(Color("#49df79"), 2)
	_create_bar_quad("Outline", Vector2(BAR_WIDTH, BAR_HEIGHT), outline_material)
	_create_bar_quad("Background", Vector2(BAR_WIDTH - 0.035, BAR_HEIGHT - 0.035), background_material)
	_recharge_fill = _create_bar_quad("Fill", Vector2(BAR_INNER_WIDTH, BAR_INNER_HEIGHT), fill_material)


func _create_bar_quad(node_name: String, size: Vector2, material: Material) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.name = node_name
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = size
	quad.mesh = quad_mesh
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_recharge_bar.add_child(quad)
	return quad


func _add_cross_parts(parent: Node, height: float, dimensions: Vector2, thickness: float, material: Material, prefix: String, target: Array[MeshInstance3D]) -> void:
	for entry in [
		{"name": "%sX" % prefix, "size": Vector3(dimensions.x, thickness, dimensions.y)},
		{"name": "%sZ" % prefix, "size": Vector3(dimensions.y, thickness, dimensions.x)},
	]:
		var cross := MeshInstance3D.new()
		cross.name = entry.name
		var mesh := BoxMesh.new()
		mesh.size = entry.size
		cross.mesh = mesh
		cross.position.y = height
		cross.material_override = material
		cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(cross)
		target.append(cross)


func _billboard_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := _material(color, 0.75, Color.BLACK, 0.0, true)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.render_priority = priority
	return material


func _material(color: Color, roughness: float = 0.8, emission: Color = Color.BLACK, emission_energy: float = 0.0, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	if transparent or color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
