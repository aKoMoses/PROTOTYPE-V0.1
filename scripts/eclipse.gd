extends RefCounted

## Destination selection and particle-only transit. The actor stays at its
## departure point until arrival; its body and all attached visuals disappear.
const DATA := preload("res://scripts/combat_data.gd")
const TINT := Color("#a996ff")
var aiming := false
var travelling := false
var touch_owned := false
var destination := Vector3.ZERO
var origin := Vector3.ZERO
var remaining := 0.0
var serial := 0
var _completed_serial := 0
var _action_token := 0
var _touch_vector := Vector2.ZERO
var _has_touch_vector := false
var _old_layer := 0
var _old_mask := 0
var _old_visible := true
var _preview: Node3D
var _range_ring: MeshInstance3D
var _target_ring: MeshInstance3D
var _target_disc: MeshInstance3D
var _caption: Label3D
var _flight: Node3D
var _particles: Array[MeshInstance3D] = []


func begin(actor: CharacterBody3D, from_touch: bool = false) -> bool:
	if aiming or travelling or actor.call("_action_incapacitated") or actor.get("_dash_active") or actor.get("_pelto_pull_active") or not actor.call("_module_ready", "eclipse"):
		return false
	_action_token = int(actor.call("_try_begin_module_action", "eclipse"))
	if _action_token == 0:
		return false
	aiming = true
	touch_owned = from_touch
	_has_touch_vector = false
	destination = actor.global_position + actor.get("aim_direction") * float(DATA.MODULE_DEFINITIONS.eclipse.max_range)
	_build_preview(actor)
	update_aim(actor)
	return true


func set_touch_vector(actor: CharacterBody3D, value: Vector2) -> void:
	if not aiming or not touch_owned or not value.is_finite():
		return
	_touch_vector = value.limit_length(1.0)
	_has_touch_vector = true
	update_aim(actor)


func update_aim(actor: CharacterBody3D) -> void:
	if not aiming:
		return
	var max_range := float(DATA.MODULE_DEFINITIONS.eclipse.max_range)
	var offset: Vector3 = actor.get("aim_direction") * max_range
	if touch_owned:
		if _has_touch_vector:
			offset = actor.call("_camera_relative_direction", _touch_vector) * max_range * _touch_vector.length()
	else:
		var camera := actor.get_viewport().get_camera_3d()
		if camera != null:
			var screen := actor.get_viewport().get_mouse_position()
			var ray := camera.project_ray_normal(screen)
			var start := camera.project_ray_origin(screen)
			if absf(ray.y) > 0.001:
				var distance := (actor.global_position.y - start.y) / ray.y
				if distance > 0.0:
					offset = start + ray * distance - actor.global_position
	var sticks := Input.get_connected_joypads()
	if not touch_owned and not sticks.is_empty():
		var stick := Vector2(Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_Y)).limit_length(1.0)
		if stick.length() > 0.15:
			offset = actor.call("_camera_relative_direction", stick) * max_range * stick.length()
	offset.y = 0.0
	destination = actor.global_position + offset.limit_length(max_range)
	if offset.length_squared() > 0.01:
		actor.call("_set_aim_direction", offset.normalized())
	var valid := fits(actor, destination)
	var color := TINT if valid else Color("#ff635d")
	_range_ring.global_position = actor.global_position + Vector3.UP * 0.045
	_target_ring.global_position = destination + Vector3.UP * 0.08
	_target_disc.global_position = destination + Vector3.UP * 0.06
	_caption.global_position = destination + Vector3.UP * 0.75
	_caption.text = "ÉCLIPSE · RELÂCHER" if valid else "ARRIVÉE BLOQUÉE"
	_caption.modulate = color
	_target_ring.material_override.albedo_color = Color(color, 0.95)
	_target_disc.material_override.albedo_color = Color(color, 0.13)


func release(actor: CharacterBody3D) -> bool:
	if not aiming:
		return false
	update_aim(actor)
	var at := destination
	var accepted := bool(actor.call("_perform_eclipse", at))
	if not accepted:
		cancel(actor)
	return accepted


func depart(actor: CharacterBody3D, at: Vector3) -> bool:
	if travelling or not fits(actor, at) or actor.call("_action_incapacitated") or actor.get("_dash_active") or actor.get("_pelto_pull_active") or not actor.call("_module_ready", "eclipse"):
		return false
	if not aiming:
		_action_token = int(actor.call("_try_begin_module_action", "eclipse"))
	if _action_token == 0:
		return false
	aiming = false
	touch_owned = false
	_free_visuals()
	serial += 1
	origin = actor.global_position
	destination = at
	destination.y = origin.y
	remaining = float(DATA.MODULE_DEFINITIONS.eclipse.travel_duration)
	travelling = true
	_old_layer = actor.collision_layer
	_old_mask = actor.collision_mask
	_old_visible = actor.visible
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.hide()
	actor.velocity = Vector3.ZERO
	actor.call("_mark_combat_event")
	actor.call("_start_module_cooldown", "eclipse", float(DATA.MODULE_DEFINITIONS.eclipse.cooldown))
	_build_flight(actor)
	return true


func update(actor: CharacterBody3D, delta: float) -> void:
	if aiming:
		if actor.call("_action_incapacitated") or (not touch_owned and Input.is_key_pressed(KEY_ESCAPE)):
			cancel(actor)
		else:
			update_aim(actor)
	if not travelling:
		return
	remaining = maxf(0.0, remaining - delta)
	var progress := 1.0 - remaining / float(DATA.MODULE_DEFINITIONS.eclipse.travel_duration)
	for index in range(_particles.size()):
		var phase := float(index) * 2.39996
		var t := clampf(progress - float(index % 7) * 0.022, 0.0, 1.0)
		var spread := sin(t * PI) * (0.15 + float(index % 5) * 0.08)
		_particles[index].global_position = origin.lerp(destination, t) + Vector3(cos(phase + t * 12.0) * spread, 0.8 + sin(phase + t * 9.0) * spread, sin(phase + t * 12.0) * spread)
	if remaining <= 0.0:
		arrive(actor)


func arrive(actor: CharacterBody3D) -> void:
	if not travelling:
		return
	var accepted := fits(actor, destination)
	actor.global_position = destination if accepted else origin
	_completed_serial = serial
	_restore_body(actor)
	_free_visuals()
	actor.call("_end_module_action", _action_token, "eclipse")
	_action_token = 0
	if accepted:
		burst(actor.get_tree().current_scene, actor.global_position)
		actor.call("_on_eclipse_arrived", origin, actor.global_position)


func cancel(actor: CharacterBody3D) -> void:
	if travelling:
		_completed_serial = serial
		_restore_body(actor)
	if aiming or _action_token != 0:
		actor.call("_end_module_action", _action_token, "eclipse")
	_action_token = 0
	aiming = false
	touch_owned = false
	_free_visuals()


func _restore_body(actor: CharacterBody3D) -> void:
	travelling = false
	remaining = 0.0
	actor.collision_layer = _old_layer
	actor.collision_mask = _old_mask
	actor.visible = _old_visible
	actor.velocity = Vector3.ZERO


func _free_visuals() -> void:
	for effect in [_preview, _flight]:
		if is_instance_valid(effect):
			effect.queue_free()
	_preview = null
	_flight = null
	_particles.clear()


static func fits(actor: CharacterBody3D, at: Vector3) -> bool:
	if not at.is_finite() or absf(at.y - actor.global_position.y) > 0.1 or at.distance_to(actor.global_position) > float(DATA.MODULE_DEFINITIONS.eclipse.max_range) + 0.05:
		return false
	# Use each arena's actual outer playable extent, with room for the body.
	var scene := actor.get_tree().current_scene
	var constants: Dictionary = scene.get_script().get_script_constant_map() if scene != null and scene.get_script() != null else {}
	var extent_x := float(constants.get("MAP_HALF_WIDTH", constants.get("ARENA_HALF_EXTENT", constants.get("ARENA_HALF", 23.0)))) - 1.0
	var extent_z := float(constants.get("MAP_HALF_DEPTH", extent_x + 1.0)) - 1.0
	if absf(at.x) > extent_x or absf(at.z) > extent_z:
		return false
	for child in actor.get_children():
		if not child is CollisionShape3D or child.shape == null or child.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.transform.origin += at - actor.global_position
		query.collision_mask = 1 | 2 | 8
		query.margin = 0.0
		query.exclude = [actor.get_rid()]
		if not actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func snapshot() -> Dictionary:
	return {"serial": serial, "remaining": remaining, "origin": origin, "destination": destination}


func receive_snapshot(actor: CharacterBody3D, value: Dictionary) -> void:
	var revision := int(value.get("serial", 0))
	var time_left := clampf(float(value.get("remaining", 0.0)), 0.0, float(DATA.MODULE_DEFINITIONS.eclipse.travel_duration))
	if revision < serial and time_left > 0.0:
		return
	if time_left <= 0.0:
		if travelling:
			if revision == serial:
				burst(actor.get_tree().current_scene, destination)
			cancel(actor)
		serial = revision
		_completed_serial = revision
		return
	if revision <= _completed_serial:
		return
	var at: Vector3 = value.get("destination", actor.global_position)
	var start: Vector3 = value.get("origin", actor.global_position)
	if not at.is_finite() or not start.is_finite():
		return
	if not travelling:
		# Replica-only restore; authority already checked collision and cooldown.
		cancel(actor)
		actor.global_position = start
		actor.set("_replaying", true)
		actor.get("_module_cooldowns").erase("eclipse")
		depart(actor, at)
		actor.set("_replaying", false)
	serial = revision
	remaining = time_left


static func material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func ring(parent: Node3D, radius: float, alpha: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - 0.035)
	mesh.outer_radius = radius + 0.035
	mesh.rings = 48
	mesh.ring_segments = 8
	visual.mesh = mesh
	visual.material_override = material(TINT, alpha)
	parent.add_child(visual)
	return visual


func _build_preview(actor: CharacterBody3D) -> void:
	_preview = Node3D.new()
	_preview.name = "EclipseDestinationPreview"
	actor.get_tree().current_scene.add_child(_preview)
	_range_ring = ring(_preview, float(DATA.MODULE_DEFINITIONS.eclipse.max_range), 0.28)
	_target_ring = ring(_preview, float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius), 0.95)
	_target_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius)
	disc.bottom_radius = disc.top_radius
	disc.height = 0.01
	_target_disc.mesh = disc
	_target_disc.material_override = material(TINT, 0.13)
	_preview.add_child(_target_disc)
	_caption = Label3D.new()
	_caption.font_size = 30
	_caption.pixel_size = 0.009
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_preview.add_child(_caption)


func _build_flight(actor: CharacterBody3D) -> void:
	_flight = Node3D.new()
	_flight.name = "EclipseParticleTransit"
	actor.get_tree().current_scene.add_child(_flight)
	var mesh := SphereMesh.new()
	mesh.radius = 0.065
	mesh.height = 0.13
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := material(Color("#9e64ff"), 0.95)
	for index in range(35):
		var particle := MeshInstance3D.new()
		particle.mesh = mesh
		particle.material_override = mat
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particle.scale = Vector3.ONE * (0.6 + float(index % 5) * 0.22)
		_flight.add_child(particle)
		particle.global_position = origin + Vector3.UP * 0.8
		_particles.append(particle)


static func burst(parent: Node, at: Vector3) -> void:
	var effect := Node3D.new()
	effect.name = "EclipseArrivalExplosion"
	parent.add_child(effect)
	effect.add_to_group("prototype0_fx_budget")
	effect.global_position = at + Vector3.UP * 0.1
	var wave := ring(effect, 1.0, 0.95)
	wave.scale = Vector3.ONE * 0.15
	var core := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	core.mesh = mesh
	core.material_override = material(Color("#f0e8ff"), 0.7)
	core.position.y = 0.8
	effect.add_child(core)
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(wave, "scale", Vector3.ONE * float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius), 0.3)
	tween.tween_property(wave.material_override, "albedo_color:a", 0.0, 0.3)
	tween.tween_property(core, "scale", Vector3(2.4, 1.8, 2.4), 0.22)
	tween.tween_property(core.material_override, "albedo_color:a", 0.0, 0.22)
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.09
	spark_mesh.height = 0.18
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	var sparks_material := material(Color("#9861f0"), 0.95)
	for index in range(18):
		var spark := MeshInstance3D.new()
		spark.mesh = spark_mesh
		spark.material_override = sparks_material
		spark.position = Vector3.UP * 0.65
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effect.add_child(spark)
		var angle := float(index) * TAU / 18.0
		var radius := float(DATA.MODULE_DEFINITIONS.eclipse.explosion_radius)
		var end := Vector3(cos(angle) * radius, 0.2 + float(index % 3) * 0.25, sin(angle) * radius)
		tween.tween_property(spark, "position", end, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.3)
	tween.tween_property(sparks_material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(effect.queue_free)
