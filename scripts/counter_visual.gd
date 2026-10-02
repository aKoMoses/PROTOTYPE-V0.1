extends RefCounted

## Geometry-based cues also work without glow on the mobile renderer.
const GUARD_COLOR := Color("#45e5ff")
const REWARD_COLOR := Color("#ffbc42")


static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.albedo_color = color
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result


static func mesh(parent: Node3D, shape: Mesh, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material(color)
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result


static func ring(parent: Node3D, radius: float, thickness: float, color: Color) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - thickness
	shape.outer_radius = radius
	shape.rings = 40
	shape.ring_segments = 8
	return mesh(parent, shape, color)


static func guard_panels(parent: Node3D) -> Node3D:
	var result := Node3D.new()
	result.name = "GuardPanels"
	parent.add_child(result)
	# Eight open shield segments describe the actual 360-degree guard without
	# hiding the robot silhouette behind a solid bubble.
	for index in range(8):
		var angle := TAU * index / 8.0
		var pivot := Node3D.new()
		result.add_child(pivot)
		pivot.rotation.y = angle
		pivot.position = Vector3(sin(angle), 0.95, cos(angle)) * Vector3(0.91, 1.0, 0.91)
		var face := QuadMesh.new()
		face.size = Vector2(0.44, 0.60)
		mesh(pivot, face, Color(GUARD_COLOR, 0.13))
		for edge in [-1.0, 1.0]:
			var backing := BoxMesh.new()
			backing.size = Vector3(0.48, 0.065, 0.028)
			mesh(pivot, backing, Color("#163b4b")).position = Vector3(0, edge * 0.30, -0.012)
			var bar := BoxMesh.new()
			bar.size = Vector3(0.44, 0.035, 0.035)
			mesh(pivot, bar, GUARD_COLOR).position.y = edge * 0.30
	return result


static func timer_arc(parent: Node3D) -> MeshInstance3D:
	return mesh(parent, ImmediateMesh.new(), GUARD_COLOR)


static func update_timer(arc: MeshInstance3D, ratio: float) -> void:
	var shape := arc.mesh as ImmediateMesh
	shape.clear_surfaces()
	if ratio <= 0.0:
		return
	shape.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(40):
		var a := TAU * ratio * index / 40.0
		var b := TAU * ratio * (index + 1) / 40.0
		var inner_a := Vector3(sin(a), 0.0, cos(a)) * 1.04
		var outer_a := Vector3(sin(a), 0.0, cos(a)) * 1.14
		var inner_b := Vector3(sin(b), 0.0, cos(b)) * 1.04
		var outer_b := Vector3(sin(b), 0.0, cos(b)) * 1.14
		for point in [inner_a, outer_a, outer_b, inner_a, outer_b, inner_b]:
			shape.surface_add_vertex(point)
	shape.surface_end()


static func burst(scene: Node, center: Vector3, radius: float, duration: float, reward: bool) -> void:
	if not is_instance_valid(scene):
		return
	var effect := Node3D.new()
	effect.name = "CounterBurst"
	scene.add_child(effect)
	effect.add_to_group("prototype0_fx_budget")
	effect.global_position = center
	var color := REWARD_COLOR if reward else GUARD_COLOR
	var backing := ring(effect, radius + 0.025, 0.14, Color("#23313a"))
	backing.position.y = -0.012
	backing.scale = Vector3.ONE * 0.25
	var wave := ring(effect, radius, 0.09, color)
	wave.scale = Vector3.ONE * 0.25
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(wave, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave.material_override, "albedo_color:a", 0.0, duration)
	tween.tween_property(backing, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(backing.material_override, "albedo_color:a", 0.0, duration)
	var sparks := CPUParticles3D.new()
	sparks.emitting = false
	sparks.amount = 20 if reward else 16
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.lifetime = 0.32
	sparks.direction = Vector3.UP
	sparks.spread = 160.0
	sparks.gravity = Vector3(0, -2, 0)
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 4.5 if reward else 3.0
	sparks.scale_amount_min = 0.55
	sparks.scale_amount_max = 1.0
	var spark := BoxMesh.new()
	spark.size = Vector3(0.055, 0.13, 0.055)
	sparks.mesh = spark
	sparks.material_override = material(Color.WHITE)
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 1.0))
	fade.set_color(1, Color(Color("#e77423") if reward else Color("#1daecb"), 0.0))
	sparks.color_ramp = fade
	effect.add_child(sparks)
	sparks.emitting = true
	tween.chain().tween_interval(maxf(0.0, 0.4 - duration))
	tween.chain().tween_callback(effect.queue_free)
