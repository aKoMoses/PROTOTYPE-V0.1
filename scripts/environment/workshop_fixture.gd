extends Node3D
## Compact service equipment attached to a real workshop face. Visuals only.
const SCREEN := preload("res://scripts/environment/workshop_monitor.gdshader")
const VAPOUR := preload("res://scripts/environment/workshop_vapour.gdshader")
var phase := 0.0
var fan_speed := 0.0
var _fan: Node3D
var _screen: ShaderMaterial
var _leds: MultiMesh
var _steam: Array[MeshInstance3D] = []
var _drop: MeshInstance3D
var _ripple: MeshInstance3D
var _arc: MeshInstance3D
var _hardware_material: StandardMaterial3D
var arc_active := false

func setup(seed_value: int, color: Color) -> void:
	phase = float(absi(seed_value) % 997) * 0.031
	_hardware_material = _metal(Color("#545e61"))
	var housing := SurfaceTool.new()
	housing.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [
		[Vector3(0, 0, 0), Vector3(0.77, 0.40, 0.12)],
		[Vector3(-0.17, 0.0, 0.075), Vector3(0.38, 0.27, 0.055)],
		[Vector3(0.40, -0.07, 0.035), Vector3(0.28, 0.33, 0.12)],
		[Vector3(0.62, -0.16, 0.0), Vector3(0.065, 0.58, 0.09)],
		[Vector3(0.57, 0.16, 0.015), Vector3(0.17, 0.065, 0.12)],
		[Vector3(-0.44, 0.24, 0.09), Vector3(0.10, 0.02, 0.026)],
		[Vector3(-0.16, 0.355, 0.09), Vector3(0.12, 0.02, 0.026)]
	]:
		var box := BoxMesh.new()
		box.size = part[1]
		housing.append_from(box, 0, Transform3D(Basis.IDENTITY, part[0]))
	_mesh("ServiceHousing", housing.commit(), _hardware_material)
	var face := QuadMesh.new()
	face.size = Vector2(0.32, 0.20)
	_screen = ShaderMaterial.new()
	_screen.shader = SCREEN
	_screen.set_shader_parameter("phase", phase)
	_screen.set_shader_parameter("screen_tint", color.lerp(Color("#73d8b0"), 0.65))
	_mesh("DiagnosticScreen", face, _screen, Vector3(-0.17, 0, 0.108))
	var leds := MultiMeshInstance3D.new()
	leds.name = "MachineStatusLights"
	_leds = MultiMesh.new()
	_leds.transform_format = MultiMesh.TRANSFORM_3D
	_leds.use_colors = true
	var bead := SphereMesh.new()
	bead.radius = 0.024
	bead.height = 0.048
	bead.radial_segments = 8
	bead.rings = 4
	_leds.mesh = bead
	_leds.instance_count = 3
	leds.multimesh = _leds
	var led_material := _metal(Color.WHITE)
	led_material.vertex_color_use_as_albedo = true
	led_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leds.material_override = led_material
	leds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leds)
	for index in 3:
		_leds.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(-0.28 + index * 0.11, -0.158, 0.092)))
	_fan = Node3D.new()
	_fan.name = "InertialFanRotor"
	_fan.position = Vector3(0.40, -0.035, 0.108)
	add_child(_fan)
	var blades := SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 5:
		var angle := float(index) * TAU / 5.0
		var blade := BoxMesh.new()
		blade.size = Vector3(0.035, 0.105, 0.009)
		var basis := Basis(Vector3.FORWARD, angle)
		blades.append_from(blade, 0, Transform3D(basis, basis * Vector3(0, 0.05, 0)))
	var rotor := _mesh("FiveFanBlades", blades.commit(), _metal(Color("#a5aaa3")))
	rotor.reparent(_fan, false)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.107
	rim.outer_radius = 0.120
	rim.rings = 16
	rim.ring_segments = 6
	var grille := _mesh("VentilatorRim", rim, _hardware_material, _fan.position + Vector3(0, 0, 0.015))
	grille.rotation.x = PI * 0.5
	for index in 2:
		var plume := QuadMesh.new()
		plume.size = Vector2(0.32, 0.54)
		var material := ShaderMaterial.new()
		material.shader = VAPOUR
		material.set_shader_parameter("phase", phase + index)
		_steam.append(_mesh("IntermittentSteam%d" % index, plume, material))
	var droplet := SphereMesh.new()
	droplet.radius = 0.012
	droplet.height = 0.038
	droplet.radial_segments = 6
	droplet.rings = 3
	_drop = _mesh("CondensationDrop", droplet, _metal(Color("#86b9bd")))
	var ring := PlaneMesh.new()
	ring.size = Vector2(0.42, 0.42)
	var ripple_material := ShaderMaterial.new()
	ripple_material.shader = VAPOUR
	ripple_material.set_shader_parameter("effect_kind", 1)
	ripple_material.set_shader_parameter("tint", Color("#678184"))
	_ripple = _mesh("CondensationRipple", ring, ripple_material)
	var arc_mesh := SurfaceTool.new()
	arc_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.39, 0.24, 0.09), Vector3(-0.31, 0.28, 0.11), Vector3(-0.34, 0.31, 0.1), Vector3(-0.22, 0.35, 0.09)]
	for index in 3:
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var side := Vector3((b - a).y, -(b - a).x, 0).normalized() * 0.006
		for point in [a - side, a + side, b + side, a - side, b + side, b - side]:
			arc_mesh.add_vertex(point)
	arc_mesh.generate_normals()
	var arc_material := _metal(Color("#bef7ff"))
	arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_material.emission_enabled = true
	arc_material.emission = Color("#7fe8ff")
	arc_material.emission_energy_multiplier = 2.0
	_arc = _mesh("RareCableArc", arc_mesh.commit(), arc_material)
	_arc.hide()

func animate(clock: float, delta: float, power: float, low: bool, floor_y: float, breeze: Vector3) -> void:
	var work_phase := fmod(clock + phase * 2.0, 18.0 + fmod(phase, 7.0))
	var working := work_phase < 11.0 and power > 0.25
	var target := (9.0 + sin(clock * 0.9 + phase) * 0.8) * power if working else 0.0
	fan_speed = lerpf(fan_speed, target, 1.0 - exp(-delta * (2.0 if working else 0.9)))
	_fan.rotation.z += fan_speed * delta
	_screen.set_shader_parameter("clock", clock)
	_screen.set_shader_parameter("working", 1.0 if working else 0.2)
	_screen.set_shader_parameter("power", power)
	for index in 3:
		var pulse := 0.3 + 0.7 * (0.5 + 0.5 * sin(clock * (2.4 if working and index == 1 else 1.15) + phase + index * 1.4))
		var color: Color = [Color("#65c9b0"), Color("#e7ad5e"), Color("#699baa")][index]
		_leds.set_instance_color(index, color * maxf(0.08, pulse * power))
	var camera := get_viewport().get_camera_3d()
	for index in _steam.size():
		var steam := _steam[index]
		var t := fmod(clock + phase + index * 0.55, 8.5)
		var progress := clampf(t / 1.8, 0.0, 1.0)
		steam.visible = not low and t < 1.8 and power > 0.4
		steam.global_position = to_global(Vector3(0.56, 0.17 + progress * 0.55, 0.12)) + breeze * progress * 0.18
		steam.scale = Vector3.ONE * (0.45 + progress * 0.85)
		if camera != null:
			steam.global_basis = camera.global_basis.orthonormalized().scaled(steam.scale)
		var material := steam.material_override as ShaderMaterial
		material.set_shader_parameter("progress", progress)
		material.set_shader_parameter("opacity", sin(progress * PI) * 0.25)
	var fall_duration := sqrt(maxf(0.0, global_position.y - 0.24 - floor_y) * 2.0 / 9.8)
	var drip_time := fmod(clock + phase, 4.2)
	_drop.visible = not low and drip_time < fall_duration and power > 0.3
	_drop.global_position = to_global(Vector3(0.62, -0.24, 0.02)) - Vector3.UP * 4.9 * drip_time * drip_time
	_ripple.visible = not low and drip_time >= fall_duration and drip_time < fall_duration + 0.65 and power > 0.3
	var splash := clampf((drip_time - fall_duration) / 0.65, 0.0, 1.0)
	var floor_point := to_global(Vector3(0.62, 0, 0.02))
	_ripple.global_transform = Transform3D(Basis.IDENTITY, Vector3(floor_point.x, floor_y + 0.024, floor_point.z))
	(_ripple.material_override as ShaderMaterial).set_shader_parameter("progress", splash)
	(_ripple.material_override as ShaderMaterial).set_shader_parameter("opacity", 0.20)
	arc_active = not low and fmod(clock + phase * 3.0, 19.0 + fmod(phase, 5.0)) < 0.10 and power > 0.25
	_arc.visible = arc_active
	set_meta("working", working)
	set_meta("fan_speed", fan_speed)

func reset_transients() -> void:
	for plume in _steam:
		plume.hide()
	_drop.hide()
	_ripple.hide()
	_arc.hide()
	arc_active = false

func _metal(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.metallic = 0.30
	return material

func _mesh(label: String, mesh: Mesh, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node
