extends Node3D
## Presentation only: no collision, damage, gameplay timers or combat random state.
signal surface_contact(at: Vector3, surface: String, power: float)
signal presentation_cleared
signal organic_contact(at: Vector3, normal: Vector3, surface: String, power: float)
signal organic_shot(socket: Node3D, weapon: String, charge: float)
signal organic_motion(at: Vector3, direction: Vector3, power: float)
const SURFACES := preload("res://scripts/surface_response.gd")
const PRESENTATION := preload("res://scripts/combat_presentation_pass.gd")
const ORGANIC_DETAILS := preload("res://scripts/environment/organic_world_details.gd")

const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const ASSETS := preload("res://scripts/vfx_assets.gd")
const SMOKE_SHADER := preload("res://shaders/vfx_smoke.gdshader")
const SURFACE_SHADER := preload("res://shaders/vfx_surface_wave.gdshader")
const PELTO_VISUALS := preload("res://scripts/pelto_smash.gd")
const MAX_IDLE_PROJECTILE_MESHES := 32

enum Quality { LOW, NORMAL }
@export var quality: Quality = Quality.NORMAL
@export_range(8, 96) var max_effects := 48
@export_range(0, 48) var max_decals := 24
@export_range(2, 24) var max_particles := 14
@export_range(0.02, 0.12) var muzzle_lifetime := 0.065
@export_range(0.02, 0.15) var tracer_lifetime := 0.075
@export_range(0.01, 0.08) var tracer_width := 0.026
@export_range(1.0, 20.0) var decal_duration := 7.0
@export_range(0.5, 2.0) var impact_scale := 1.0
@export_range(0.025, 0.10) var hit_flash_duration := 0.055

var _active: Array[Dictionary] = []
var _pool: Dictionary = {}
var _meshes: Dictionary = {}
var _textures: Dictionary = {}
var _hits: Dictionary = {}
var _hit_materials: Array[StandardMaterial3D] = []
var _projectile_mesh_pool: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	PELTO_VISUALS.prepare_visual_resources()
	# Select the existing lightweight scenery/VFX path before adapters install.
	_apply_device_budget(OS.has_feature("mobile"))
	_rng.randomize()
	_install_presentation.call_deferred()
	# Follow skeleton modifiers and weapon recoil when updating attached flashes.
	process_priority = 100
	# Build once before combat, rather than paying for textures on the first hit.
	for variant in range(3):
		ASSETS.texture("smoke", variant)
		ASSETS.texture("decal", variant)
	for style in ["spark", "energy", "debris", "dust"]:
		ASSETS.particle_mesh(style)
		_particle_ramp(style)
		_particle_curve(style)
	for critical in [false, true]:
		var material := _material(Color("#ffd7a3") if critical else Color("#9bc8d1"))
		material.albedo_color.a = 0.18 if critical else 0.12
		_hit_materials.append(material)
	# Separate from the disposable FX budget: a shot's gameplay owner is never
	# reclaimed. Prepare two salvos and a few plasma shots before interaction.
	for kind in ["blaster", "shotgun"]:
		_projectile_mesh_pool[kind] = []
		for index in (4 if kind == "blaster" else 12):
			_projectile_mesh_pool[kind].append(_new_projectile_mesh(kind))

func _apply_device_budget(mobile: bool) -> void:
	if mobile:
		quality = Quality.LOW
		max_effects = mini(max_effects, 24)
		max_decals = mini(max_decals, 8)
		max_particles = mini(max_particles, 6)

func _install_presentation() -> void:
	PRESENTATION.install(get_parent(), self)
	ORGANIC_DETAILS.install(get_parent(), self)


func _process(delta: float) -> void:
	for index in range(_active.size() - 1, -1, -1):
		var effect: Dictionary = _active[index]
		effect.age += delta
		var node: Node3D = effect.node
		if effect.age >= effect.life or not _follow_attachment(effect):
			_release(index)
			continue
		if effect.age < 0.0:
			node.visible = false
			continue
		node.visible = true
		if node is GPUParticles3D:
			if effect.pending_start:
				node.restart()
				node.emitting = true
				effect.pending_start = false
			continue
		var progress: float = effect.age / effect.life
		if effect.kind in ["smoke", "surface_wave"]:
			var shader_material := node.material_override as ShaderMaterial
			shader_material.set_shader_parameter("progress", progress)
			if effect.kind == "smoke":
				node.position += effect.drift * delta
				node.scale = effect.size * (0.65 + progress * 1.65)
			continue
		var material: StandardMaterial3D = node.material_override
		var fade: float = 1.0 - progress
		if effect.kind == "decal":
			fade = 1.0 - smoothstep(0.65, 1.0, progress)
		elif effect.kind in ["shotgun_trail", "plasma_trail", "needle_trail"]:
			if effect.attachment != null:
				var projectile: Node3D = effect.attachment.get_ref()
				var length := minf(effect.trail_length, projectile.global_position.distance_to(effect.origin))
				node.scale = Vector3(effect.size.x, effect.size.y, maxf(length, 0.001))
				fade = 1.0
		elif effect.kind == "shotgun_flame":
			node.scale = effect.size * (0.75 + sin(progress * PI) * 0.35)
			fade = 1.0 - smoothstep(0.16, 1.0, progress)
		elif effect.kind == "shotgun_pressure":
			node.position += effect.drift * delta
			node.scale = effect.size * lerpf(0.35, 1.65, 1.0 - pow(1.0 - progress, 2.0))
			fade = pow(1.0 - progress, 2.0)
		elif effect.kind == "shotgun_spark":
			node.position += effect.drift * delta
			node.scale = effect.size * Vector3(1.0 - progress, 1.0 - progress, 1.0 + progress * 0.5)
			fade = pow(1.0 - progress, 1.5)
		elif effect.kind == "ring":
			var expansion := 1.0 - pow(1.0 - progress, 3.0)
			node.scale = effect.size * (0.42 + expansion * 1.58)
			fade = 1.0 - smoothstep(0.42, 1.0, progress)
		elif effect.kind in ["muzzle", "tracer", "flash", "precision_flash"]:
			fade = 1.0 - smoothstep(0.34, 1.0, progress)
		material.albedo_color.a = effect.alpha * fade
	for key in _hits.keys():
		var hit: Dictionary = _hits[key]
		hit.remaining -= delta
		if hit.remaining <= 0.0:
			_restore_hit(key)


func muzzle(socket: Node3D, weapon: String, charge: float = 0.0) -> void:
	if not is_instance_valid(socket) or not socket.is_inside_tree():
		return
	organic_shot.emit(socket, weapon, charge)
	if weapon == "shotgun":
		_shotgun_muzzle(socket)
		return
	var enemy := weapon == "enemy"
	var charge_curve := charge * charge
	var color := Color("#ff5b50") if enemy else Color("#52dff4").lerp(Color("#718cff"), charge_curve * 0.72)
	var length := 0.48 if enemy else lerpf(0.46, 0.80, charge_curve)
	var radius := 0.16 if enemy else lerpf(0.145, 0.24, charge_curve)
	var life := muzzle_lifetime + (0.014 if charge > 0.6 else 0.0)
	if weapon == "longshot":
		color = Color("#55e5f2") if charge < 0.5 else Color("#a7f5ff")
		length = 0.85 if charge < 0.5 else 1.1
		radius = 0.095 if charge < 0.5 else 0.14
	var variation := _rng.randf_range(0.92, 1.08)
	for core in [false, true]:
		var core_color := Color("#ffe0d8") if enemy else Color("#e8fdff")
		var effect := _mesh_effect("muzzle", core_color if core else color, life, 0.96 if core else 0.62)
		effect.attachment = weakref(socket)
		effect.offset = Vector3(0.0, 0.0, -length * 0.5)
		effect.size = Vector3(radius, radius, length) * variation * (Vector3(0.38, 0.38, 0.82) if core else Vector3.ONE)
		if weapon == "longshot":
			effect.node.mesh = _mesh("needle_muzzle")
		else:
			effect.node.mesh = _mesh("muzzle")
		effect.node.scale = effect.size
		_follow_attachment(effect)
	var direction := -socket.global_basis.z.normalized()
	if charge > 0.6:
		burst(socket.global_position, direction, color, 4, 2.6, 0.15, 0.032, 24.0)


func projectile_visual(parent: Node3D, weapon: String, charge: float = 0.0) -> void:
	# This mesh belongs to the gameplay projectile; the visual budget never frees its parent.
	if weapon == "longshot":
		_longshot_projectile_visual(parent, charge >= 0.5)
		return
	if weapon == "shotgun":
		_shotgun_projectile(parent)
		return
	var enemy := weapon == "enemy"
	var power := clampf(charge, 0.0, 1.0)
	var charge_curve := power * power
	var size_multiplier := lerpf(1.0, float(COMBAT_DATA.WEAPON_DEFINITIONS.blaster.charged_size_multiplier), power)
	var color := Color("#ff5b50") if enemy else Color("#52dff4").lerp(Color("#718cff"), charge_curve * 0.74)
	var core := _borrow_projectile_mesh(parent, "blaster", "ProjectileCore")
	var core_color := Color("#ffe0d8") if enemy else Color("#e8fdff")
	_color_projectile_mesh(core, core_color, 0.98)
	# Smooth, shorter plasma with about 23% more width than the faceted bolt.
	core.scale = Vector3(0.040 if enemy else 0.048, 0.040 if enemy else 0.048, 0.32) * size_multiplier
	var sheath := _borrow_projectile_mesh(parent, "blaster", "ProjectileSheath")
	_color_projectile_mesh(sheath, color, lerpf(0.28, 0.38, charge_curve))
	sheath.scale = core.scale * Vector3(2.10, 2.10, 1.16)
	sheath.position.z = 0.035 * size_multiplier
	_recycle_on_projectile_finish(parent, [core, sheath])
	_attach_trail(parent, "plasma_trail", color, Vector2(0.085, 0.070) * size_multiplier, lerpf(0.48, 0.72, power), 0.055)


func _shotgun_muzzle(socket: Node3D) -> void:
	var variation := _rng.randf_range(0.93, 1.07)
	for layer in [0, 1, 2]:
		var color: Color = [Color("#ff641c"), Color("#ffb54f"), Color("#fff5d9")][layer]
		var effect := _mesh_effect("shotgun_flame", color, [0.11, 0.085, 0.065][layer], [0.45, 0.68, 0.96][layer])
		effect.attachment = weakref(socket)
		effect.size = [Vector3(0.72, 0.50, 1.30), Vector3(0.44, 0.32, 1.04), Vector3(0.18, 0.17, 0.80)][layer] * variation
		effect.offset = Vector3(0.0, 0.0, -effect.size.z * 0.48)
		_follow_attachment(effect)
	var direction := -socket.global_basis.z.normalized()
	var pressure := _mesh_effect("shotgun_pressure", Color("#ffc789"), 0.15, 0.42)
	pressure.node.position = socket.global_position + direction * 0.18
	pressure.node.basis = _surface_basis(direction)
	pressure.size = Vector3(0.48, 0.48, 0.48)
	pressure.node.scale = pressure.size * 0.35
	pressure.drift = direction * 3.4
	burst(socket.global_position + direction * 0.12, direction, Color("#ffd18a"), 9, 5.0, 0.22, 0.036, 28.0)
	_smoke(socket.global_position + direction * 0.25, direction, 0.42, 0.52, Color("#525052"), 0.055)


func _shotgun_projectile(projectile: Node3D) -> void:
	var core := _borrow_projectile_mesh(projectile, "shotgun", "ProjectileCore")
	_color_projectile_mesh(core, Color("#fff1cb"), 0.98)
	# The sweep position is the leading edge; all light stays behind it.
	core.scale = Vector3(0.085, 0.07, 0.24)
	core.position.z = 0.12
	_recycle_on_projectile_finish(projectile, [core])
	_attach_trail(projectile, "shotgun_trail", Color("#ff9b38"), Vector2(0.13, 0.09), 0.95, 0.065)

func _new_projectile_mesh(kind: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mesh("blaster_plasma" if kind == "blaster" else "tracer")
	mesh.material_override = _material(Color.WHITE, 0.98, true)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("projectile_visual_kind", kind)
	mesh.hide()
	add_child(mesh)
	return mesh

func _borrow_projectile_mesh(projectile: Node3D, kind: String, label: String) -> MeshInstance3D:
	var available: Array = _projectile_mesh_pool.get(kind, [])
	var mesh: MeshInstance3D
	while not available.is_empty() and not is_instance_valid(mesh):
		mesh = available.pop_back() as MeshInstance3D
	if not is_instance_valid(mesh):
		mesh = _new_projectile_mesh(kind)
	mesh.reparent(projectile, false)
	mesh.name = label
	mesh.transform = Transform3D.IDENTITY
	mesh.material_overlay = null
	mesh.show()
	return mesh

func _color_projectile_mesh(mesh: MeshInstance3D, color: Color, alpha: float) -> void:
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission = color

func _recycle_on_projectile_finish(projectile: Node3D, meshes: Array) -> void:
	if projectile.has_signal("finished"):
		projectile.connect("finished", _return_projectile_meshes.bind(meshes))

func _idle_projectile_mesh_count() -> int:
	var count := 0
	for available in _projectile_mesh_pool.values():
		count += available.size()
	return count

func _return_projectile_meshes(_hit: Dictionary, _distance: float, meshes: Array) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	for mesh in meshes:
		if not is_instance_valid(mesh):
			continue
		if _idle_projectile_mesh_count() >= MAX_IDLE_PROJECTILE_MESHES:
			mesh.queue_free()
			continue
		mesh.hide()
		mesh.reparent(self, false)
		var kind: String = mesh.get_meta("projectile_visual_kind")
		if not _projectile_mesh_pool.has(kind):
			_projectile_mesh_pool[kind] = []
		_projectile_mesh_pool[kind].append(mesh)


func _attach_trail(projectile: Node3D, kind: String, color: Color, width: Vector2, length: float, fade_time: float) -> void:
	# Starts at zero length and only occupies space already crossed by the shot.
	var trail := _mesh_effect(kind, color, 4.0, 0.62)
	trail.attachment = weakref(projectile)
	trail.origin = projectile.global_position
	trail.size = Vector3(width.x, width.y, 0.001)
	trail.trail_length = length
	_follow_attachment(trail)
	if projectile.has_signal("finished"):
		projectile.connect("finished", func(_hit: Dictionary, _distance: float) -> void:
			if _active.has(trail):
				_follow_attachment(trail)
				trail.node.scale.z = maxf(0.001, minf(length, projectile.global_position.distance_to(trail.origin)))
				trail.attachment = null
				trail.age = 0.0
				trail.life = fade_time
		)


func shotgun_impact(position: Vector3, normal: Vector3, surface: String, power: float = 1.0) -> void:
	impact(position, normal, surface, power, Color("#ffaf59"))
	# Concrete chips and dust already carry the contact. Long incandescent
	# streaks belong to hard metal, armour and intercepted energy.
	if surface not in ["metal", "robot", "shield"]:
		return
	var n := normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	var basis := _surface_basis(n)
	# A few authored streaks give contacts a readable silhouette even on mobile.
	for index in range(2 if quality == Quality.LOW else 4):
		var angle := _rng.randf_range(-PI, PI)
		var direction := (n * 0.75 + (basis.x * cos(angle) + basis.z * sin(angle)) * 0.65).normalized()
		var spark := _mesh_effect("shotgun_spark", Color("#ffcd81"), _rng.randf_range(0.16, 0.23), 0.85)
		spark.node.position = position + n * 0.03
		spark.node.basis = _forward_basis(direction)
		spark.size = Vector3(0.038, 0.038, _rng.randf_range(0.18, 0.34))
		spark.node.scale = spark.size
		spark.drift = direction * _rng.randf_range(3.5, 6.0)


func _longshot_projectile_visual(parent: Node3D, enhanced: bool) -> void:
	# The bright outer sheath has exactly the gameplay collision diameter.
	var definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS["longshot"]
	var fallback_radius := float(definition["projectile_radius"]) * (float(definition["enhanced_size_multiplier"]) if enhanced else 1.0)
	var diameter := maxf(0.002, float(parent.get_meta("ai_projectile_radius", fallback_radius)) * 2.0)
	var length := 1.65 if enhanced else 0.85
	var color := Color("#ffd477") if enhanced else Color("#45dbe9")
	for core in [false, true]:
		var mesh := MeshInstance3D.new()
		mesh.name = "ProjectileCore" if core else "ProjectileSheath"
		mesh.mesh = _mesh("longshot_bolt")
		mesh.material_override = _material(Color("#f0feff") if core else color, 0.98 if core else 0.48, true)
		if enhanced and core:
			(mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0
		var width := diameter * (0.42 if core else 1.0)
		var bounds := mesh.mesh.get_aabb().size
		mesh.scale = Vector3(width / bounds.x, width / bounds.y, length * (0.82 if core else 1.0) / bounds.z)
		mesh.position.z = 0.0 if core else length * 0.12
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)
	if not enhanced:
		_attach_trail(parent, "needle_trail", color, Vector2(diameter * 0.6, diameter * 0.45), 0.68, 0.045)
	if parent.has_signal("impacted"):
		parent.connect("impacted", func(hit: Dictionary, _distance: float) -> void:
			if hit.is_empty():
				return
			var normal: Vector3 = hit.get("normal", Vector3.UP)
			var stamp := _mesh_effect("precision_flash", color.lerp(Color.WHITE, 0.55), 0.095 if enhanced else 0.065, 0.88)
			stamp.node.position = hit.position + normal * 0.026
			stamp.node.basis = _surface_basis(normal)
			stamp.node.scale = Vector3(1.05, 1.0, 0.78) if enhanced else Vector3(0.68, 1.0, 0.52)
		)


func tracer(start: Vector3, end: Vector3, width: float = 0.026, color: Color = Color("#b9e9ed"), lifetime: float = 0.065) -> void:
	var distance := start.distance_to(end)
	if distance < 0.005:
		return
	var actual_width := width if width > 0.0 else tracer_width
	var actual_lifetime := lifetime if lifetime > 0.0 else tracer_lifetime
	var midpoint := (start + end) * 0.5
	var basis := _forward_basis(end - start)
	var sheath := _mesh_effect("tracer", color, actual_lifetime, 0.30)
	sheath.node.position = midpoint
	sheath.node.basis = basis
	sheath.node.scale = Vector3(actual_width * 2.35, actual_width * 2.35, distance)
	var core := _mesh_effect("tracer", color.lerp(Color.WHITE, 0.78), actual_lifetime * 0.82, 0.96)
	core.node.position = midpoint
	core.node.basis = basis
	core.node.scale = Vector3(actual_width * 0.62, actual_width * 0.62, distance * 0.94)


func impact(position: Vector3, normal: Vector3, surface: String = "metal", power: float = 1.0, color: Color = Color("#88dbef")) -> void:
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var strength := clampf(power, 0.4, 2.0) * impact_scale
	var contact := position + n * 0.018
	surface_contact.emit(contact, surface, power)
	organic_contact.emit(contact, n, surface, power)
	var is_metal := surface == "metal"
	var is_robot := surface == "robot"
	var is_shield := surface == "shield"
	var flash_color := Color("#fff0cf") if is_metal else (color.lerp(Color.WHITE, 0.62) if is_robot or is_shield else Color("#c6cfce"))
	var flash := _mesh_effect("flash", flash_color, 0.065 + (0.015 if strength > 1.3 else 0.0), 0.94)
	flash.node.position = contact
	flash.node.basis = _surface_basis(n)
	var readable := _readable_scale(contact, 0.62 * strength)
	flash.node.scale = Vector3(0.62, 0.060, 0.62) * strength * readable
	if is_shield:
		var ripple := _acquire("surface_wave", 0.32)
		ripple.node.position = contact + n * 0.012
		ripple.node.basis = _surface_basis(n)
		ripple.node.scale = Vector3.ONE * 1.15 * strength
		var wave_material := ripple.node.material_override as ShaderMaterial
		wave_material.set_shader_parameter("tint", Color(color, 0.68))
		wave_material.set_shader_parameter("progress", 0.0)
		burst(contact, n, color, 5, 2.5, 0.24, 0.065, 62.0, "energy")
	elif is_robot:
		burst(contact, n, color.lerp(Color.WHITE, 0.34), int(6 * strength), 4.5, 0.24, 0.050, 62.0, "energy")
		if strength > 1.3 and quality == Quality.NORMAL:
			burst(contact, n, Color("#8b8073"), 3, 2.2, 0.34, 0.09, 65.0, "debris", 0.025)
		var robot_ripple := _mesh_effect("ring", color, 0.14 if strength < 1.3 else 0.19, 0.42)
		robot_ripple.node.position = contact
		robot_ripple.node.basis = _surface_basis(n)
		robot_ripple.size = Vector3.ONE * (0.22 + strength * 0.08)
		robot_ripple.node.scale = robot_ripple.size
	elif is_metal:
		burst(contact, n, Color("#ffbd6f"), int(7 * strength), 5.4, 0.26, 0.060, 62.0)
		if quality == Quality.NORMAL:
			burst(contact, n, Color("#80786c"), 3, 2.4, 0.38, 0.10, 65.0, "debris", 0.025)
		decal(position, n, 0.18 * strength, Color("#101316"))
		_smoke(contact, n, 0.52 * strength, 0.60, Color("#343a3e"), 0.055)
	else:
		var sand := surface == "sand"
		burst(contact, n, Color("#b5a793") if not sand else Color("#bba578"), int(4 * strength), 1.9, 0.32, 0.08 if sand else 0.11, 72.0, "dust" if sand else "debris")
		if quality == Quality.NORMAL:
			burst(contact, n, Color(0.48, 0.43, 0.36, 0.28), 3, 0.7, 0.48, 0.22, 70.0, "dust", 0.035)
		decal(position, n, 0.24 * strength, Color("#242729"))
		_smoke(contact, n, 0.66 * strength, 0.66, Color("#71675c"), 0.060)
	if not is_shield and not is_robot:
		if strength > 1.3:
			var ripple := _mesh_effect("ring", flash_color, 0.15, 0.26)
			ripple.node.position = contact
			ripple.node.basis = _surface_basis(n)
			ripple.size = Vector3.ONE * 0.28 * strength
			ripple.node.scale = ripple.size


func burst(origin: Vector3, normal: Vector3, color: Color, amount: int = 8, speed: float = 4.0, lifetime: float = 0.25, size: float = 0.045, spread: float = 55.0, style: String = "spark", delay: float = 0.0) -> void:
	var effect := _acquire("particle", clampf(lifetime, 0.06, 0.65) + 0.06)
	var particles: GPUParticles3D = effect.node
	particles.position = origin
	particles.basis = Basis.IDENTITY
	particles.amount = clampi(int(amount * (0.55 if quality == Quality.LOW else 1.0)), 2, 18)
	particles.lifetime = effect.life - 0.06
	var material: ParticleProcessMaterial = particles.process_material
	material.direction = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	# Outward hemisphere and no inward gravity: sparks cannot cross their contact plane.
	material.spread = clampf(spread, 0.0, 78.0)
	material.initial_velocity_min = speed * 0.45
	material.initial_velocity_max = speed
	material.scale_min = size * 0.65
	material.scale_max = size * 1.2
	material.particle_flag_align_y = style == "spark"
	material.angular_velocity_min = -100.0 if style == "debris" else -8.0
	material.angular_velocity_max = 100.0 if style == "debris" else 8.0
	material.damping_min = 1.5 if style == "spark" else 2.8
	material.damping_max = 3.0 if style == "spark" else 4.5
	material.color_ramp = _particle_ramp(style)
	material.scale_curve = _particle_curve(style)
	material.color = color
	particles.draw_pass_1 = ASSETS.particle_mesh(style)
	effect.style = style
	effect.age = -maxf(0.0, delay)
	effect.pending_start = delay > 0.0
	particles.visible = delay <= 0.0
	particles.emitting = false
	if delay <= 0.0:
		particles.restart()
		particles.emitting = true


func decal(position: Vector3, normal: Vector3, radius: float = 0.12, tint: Color = Color("#17191b")) -> void:
	if max_decals <= 0:
		return
	var effect := _mesh_effect("decal", tint, decal_duration, 0.85)
	effect.node.position = position + normal.normalized() * 0.022
	effect.node.basis = _surface_basis(normal).rotated(normal.normalized(), _rng.randf_range(-PI, PI))
	effect.node.scale = Vector3(radius * _rng.randf_range(1.55, 2.25), 1.0, radius * _rng.randf_range(1.35, 2.05))
	(effect.node.material_override as StandardMaterial3D).albedo_texture = ASSETS.texture("decal", _rng.randi_range(0, 2))


func hit_flash(actor: Node3D, critical: bool = false) -> void:
	if not is_instance_valid(actor) or _hit_materials.is_empty():
		return
	var key := actor.get_instance_id()
	if not _hits.has(key):
		var meshes: Array[Dictionary] = []
		for child in actor.find_children("*", "MeshInstance3D", true, false):
			if child.is_visible_in_tree() and not child.get_meta("ignore_hit_flash", false):
				meshes.append({"mesh": weakref(child), "original": child.material_overlay})
		_hits[key] = {"meshes": meshes, "remaining": 0.0}
	_hits[key].remaining = hit_flash_duration + (0.015 if critical else 0.0)
	for entry in _hits[key].meshes:
		var mesh: MeshInstance3D = entry.mesh.get_ref()
		if is_instance_valid(mesh):
			mesh.material_overlay = _hit_materials[1 if critical else 0]


func surface_for(collider: Node) -> String:
	return SURFACES.classify(collider)

func locomotion_dust(at: Vector3, direction: Vector3, power: float = 1.0) -> void:
	organic_motion.emit(at, direction, power)
	if quality == Quality.LOW and power < 0.5:
		return
	burst(at + Vector3.UP * 0.04, (direction + Vector3.UP * 0.6).normalized(), Color(0.55, 0.49, 0.37, 0.23), 5, 0.9 + power, 0.32, 0.12 * power, 65.0, "dust")


func clear() -> void:
	presentation_cleared.emit()
	for index in range(_active.size() - 1, -1, -1):
		_release(index)
	for key in _hits.keys():
		_restore_hit(key)


func get_debug_counts() -> Dictionary:
	var counts := {"active": _active.size(), "pooled": 0, "decals": 0, "particles": 0, "hit_flashes": _hits.size()}
	for effect in _active:
		if effect.kind == "decal":
			counts.decals += 1
		if effect.kind == "particle":
			counts.particles += 1
	for available in _pool.values():
		counts.pooled += available.size()
	return counts


func _smoke(origin: Vector3, normal: Vector3, size: float, lifetime: float, color: Color = Color("#9a9fa0"), delay: float = 0.0) -> void:
	if quality == Quality.LOW:
		return
	var primary_count := 0
	for active_effect in _active:
		if _category(active_effect.kind) == "effect":
			primary_count += 1
	if primary_count >= _limit("effect") - 4:
		return
	var effect := _acquire("smoke", lifetime)
	effect.node.position = origin + normal * 0.06 + Vector3.UP * 0.12
	effect.size = Vector3.ONE * size
	effect.node.scale = effect.size * 0.65
	effect.drift = normal * 0.28 + Vector3.UP * 0.34
	effect.age = -maxf(0.0, delay)
	effect.node.visible = delay <= 0.0
	var material := effect.node.material_override as ShaderMaterial
	material.set_shader_parameter("tint", Color(color, 0.48))
	material.set_shader_parameter("puff_texture", ASSETS.texture("smoke", _rng.randi_range(0, 2)))
	material.set_shader_parameter("spin", _rng.randf_range(-PI, PI))
	material.set_shader_parameter("progress", 0.0)


func _readable_scale(position: Vector3, diameter: float) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(position):
		return 1.0
	var pixels := camera.unproject_position(position).distance_to(camera.unproject_position(position + camera.global_basis.x * diameter))
	# Only the contact flash gets a screen-size floor, bounded to avoid giant VFX.
	return clampf(9.0 / maxf(pixels, 1.0), 1.0, 1.55)


func _mesh_effect(kind: String, color: Color, lifetime: float, alpha: float = 0.92) -> Dictionary:
	var effect := _acquire(kind, lifetime)
	var material: StandardMaterial3D = effect.node.material_override
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission = color if kind not in ["decal", "smoke"] else Color.BLACK
	effect.alpha = alpha
	return effect


func _acquire(kind: String, lifetime: float) -> Dictionary:
	var category := _category(kind)
	var limit := _limit(category)
	var count := 0
	var oldest := -1
	for index in range(_active.size()):
		if _category(_active[index].kind) == category:
			count += 1
			if oldest < 0 or _priority(_active[index].kind) < _priority(_active[oldest].kind):
				oldest = index
	if count >= limit and oldest >= 0:
		_release(oldest)
	if not _pool.has(kind):
		_pool[kind] = []
	var node: Node3D = _pool[kind].pop_back() if not _pool[kind].is_empty() else _make_node(kind)
	node.transform = Transform3D.IDENTITY
	node.visible = true
	var effect := {"node": node, "kind": kind, "age": 0.0, "life": maxf(lifetime, 0.01), "alpha": 1.0, "attachment": null, "offset": Vector3.ZERO, "size": Vector3.ONE, "drift": Vector3.ZERO, "pending_start": false, "trail_length": 0.95}
	_active.append(effect)
	return effect


func _release(index: int) -> void:
	var effect: Dictionary = _active[index]
	var node: Node3D = effect.node
	node.visible = false
	if node is GPUParticles3D:
		node.emitting = false
	_pool[effect.kind].append(node)
	_active.remove_at(index)
	# Keep idle capacity bounded across all mesh kinds, not one maximum per kind.
	var available_total := 0
	for available in _pool.values():
		available_total += available.size()
	if available_total > max_effects + max_decals + max_particles:
		_pool[effect.kind].erase(node)
		node.queue_free()


func _category(kind: String) -> String:
	return kind if kind in ["decal", "particle"] else "effect"


func _priority(kind: String) -> int:
	if kind in ["smoke", "shotgun_spark", "shotgun_pressure"]:
		return 0
	if kind in ["ring", "surface_wave"]:
		return 1
	return 2


func _limit(category: String) -> int:
	var value := max_decals if category == "decal" else (max_particles if category == "particle" else max_effects)
	return maxi(1, value / 2 if quality == Quality.LOW else value)


func _follow_attachment(effect: Dictionary) -> bool:
	if effect.attachment == null:
		return true
	var socket: Node3D = effect.attachment.get_ref()
	if not is_instance_valid(socket) or not socket.is_inside_tree() or not socket.is_visible_in_tree():
		return false
	var basis := socket.global_basis.orthonormalized()
	effect.node.global_transform = Transform3D(basis.scaled_local(effect.size), socket.global_position + basis * effect.offset)
	return true


func _restore_hit(key: int) -> void:
	for entry in _hits[key].meshes:
		var mesh: MeshInstance3D = entry.mesh.get_ref()
		if is_instance_valid(mesh) and mesh.material_overlay in _hit_materials:
			mesh.material_overlay = entry.original
	_hits.erase(key)


func _make_node(kind: String) -> Node3D:
	var node: Node3D
	if kind == "particle":
		var particles := GPUParticles3D.new()
		particles.emitting = false
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.local_coords = false
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.visibility_aabb = AABB(Vector3.ONE * -4.0, Vector3.ONE * 8.0)
		var process := ParticleProcessMaterial.new()
		process.gravity = Vector3.ZERO
		process.damping_min = 1.5
		process.damping_max = 3.0
		var gradient := Gradient.new()
		gradient.set_color(0, Color.WHITE)
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient
		process.color_ramp = ramp
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.05))
		var scale_curve := CurveTexture.new()
		scale_curve.curve = curve
		process.scale_curve = scale_curve
		particles.process_material = process
		particles.draw_pass_1 = ASSETS.particle_mesh("spark")
		node = particles
	elif kind in ["smoke", "surface_wave"]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _mesh(kind)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = SMOKE_SHADER if kind == "smoke" else SURFACE_SHADER
		mesh.material_override = material
		node = mesh
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _mesh(kind)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var additive := kind in ["muzzle", "tracer", "flash", "precision_flash", "ring", "shotgun_flame", "shotgun_pressure", "shotgun_trail", "plasma_trail", "needle_trail", "shotgun_spark"]
		var material := _material(Color.WHITE, 0.92, additive)
		if additive:
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if kind in ["shotgun_trail", "plasma_trail", "needle_trail"]:
			material.vertex_color_use_as_albedo = true
		if kind in ["decal", "smoke"]:
			material.emission_enabled = false
			material.albedo_texture = _texture(kind)
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if kind == "smoke":
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mesh.material_override = material
		node = mesh
	node.name = "VFX_" + kind
	add_child(node)
	return node


func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	if kind in ["decal", "surface_wave"]:
		mesh = PlaneMesh.new()
		mesh.size = Vector2.ONE
	elif kind == "smoke":
		mesh = QuadMesh.new()
	elif kind in ["ring", "shotgun_pressure"]:
		mesh = TorusMesh.new()
		mesh.inner_radius = 0.84
		mesh.outer_radius = 1.0
		mesh.rings = 8
		mesh.ring_segments = 20
	elif kind == "muzzle":
		mesh = _faceted_bolt_mesh([Vector2(0.06, 0.50), Vector2(0.48, 0.18), Vector2(0.30, -0.22), Vector2(0.02, -0.50)])
	elif kind in ["tracer", "shotgun_spark"]:
		mesh = _faceted_bolt_mesh([Vector2(0.08, 0.50), Vector2(0.46, 0.34), Vector2(0.46, -0.34), Vector2(0.08, -0.50)])
	elif kind == "shotgun_flame":
		mesh = _faceted_bolt_mesh([Vector2(0.10, 0.50), Vector2(0.42, 0.28), Vector2(0.50, 0.06), Vector2(0.22, -0.10), Vector2(0.31, -0.28), Vector2(0.0, -0.50)])
	elif kind == "needle_muzzle":
		mesh = _faceted_bolt_mesh([Vector2(0.0, 0.50), Vector2(0.38, -0.12), Vector2(0.0, -0.50)])
	elif kind in ["shotgun_trail", "plasma_trail", "needle_trail"]:
		mesh = _shotgun_trail_mesh(kind)
	elif kind == "flash":
		mesh = _impact_star_mesh()
	elif kind == "precision_flash":
		mesh = _precision_mesh()
	elif kind == "blaster_plasma":
		mesh = SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 24
		mesh.rings = 12
	else:
		mesh = SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 8
		mesh.rings = 4
	_meshes[kind] = mesh
	return mesh


func _material(color: Color, alpha: float = 0.92, additive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.20 if additive else 0.80
	return material


func _texture(kind: String) -> Texture2D:
	return ASSETS.texture(kind)


func _particle_ramp(style: String) -> GradientTexture1D:
	var key := "ramp_" + style
	if not _textures.has(key):
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.62, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(0.95, 0.62, 0.30, 0.72) if style == "spark" else Color(1.0, 1.0, 1.0, 0.64), Color(1.0, 1.0, 1.0, 0.0)])
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient
		_textures[key] = ramp
	return _textures[key]


func _particle_curve(style: String) -> CurveTexture:
	var key := "curve_" + style
	if not _textures.has(key):
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.35 if style == "dust" else 1.0))
		curve.add_point(Vector2(0.5, 0.85 if style == "dust" else 0.70))
		curve.add_point(Vector2(1.0, 1.0 if style == "dust" else 0.10))
		var texture := CurveTexture.new()
		texture.curve = curve
		_textures[key] = texture
	return _textures[key]


func _surface_basis(normal: Vector3) -> Basis:
	var y := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := y.cross(reference).normalized()
	return Basis(x, y, x.cross(y).normalized())


func _forward_basis(direction: Vector3) -> Basis:
	var forward := direction.normalized()
	return Basis.looking_at(forward, Vector3.RIGHT if absf(forward.dot(Vector3.UP)) > 0.98 else Vector3.UP)


func _faceted_bolt_mesh(profile: Array[Vector2]) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 4
	for slice in range(profile.size() - 1):
		var radius_a := profile[slice].x
		var z_a := profile[slice].y
		var radius_b := profile[slice + 1].x
		var z_b := profile[slice + 1].y
		for side in range(sides):
			var angle_a := TAU * float(side) / float(sides) + PI * 0.25
			var angle_b := TAU * float(side + 1) / float(sides) + PI * 0.25
			var a0 := Vector3(cos(angle_a) * radius_a, sin(angle_a) * radius_a, z_a)
			var a1 := Vector3(cos(angle_b) * radius_a, sin(angle_b) * radius_a, z_a)
			var b0 := Vector3(cos(angle_a) * radius_b, sin(angle_a) * radius_b, z_b)
			var b1 := Vector3(cos(angle_b) * radius_b, sin(angle_b) * radius_b, z_b)
			for point in [a0, a1, b1, a0, b1, b0]:
				mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh


func _impact_star_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := 12
	for index in range(points):
		var angle_a := TAU * float(index) / float(points)
		var angle_b := TAU * float(index + 1) / float(points)
		var radius_a := 0.50 if index % 2 == 0 else 0.23
		var radius_b := 0.50 if (index + 1) % 2 == 0 else 0.23
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(cos(angle_a) * radius_a, 0.0, sin(angle_a) * radius_a))
		mesh.surface_add_vertex(Vector3(cos(angle_b) * radius_b, 0.0, sin(angle_b) * radius_b))
	mesh.surface_end()
	return mesh


func _precision_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(8):
		var a := TAU * index / 8.0
		var b := TAU * (index + 1) / 8.0
		var radius_a := 0.50 if index % 2 == 0 else 0.075
		var radius_b := 0.50 if (index + 1) % 2 == 0 else 0.075
		for point in [Vector3.ZERO, Vector3(cos(a) * radius_a, 0.0, sin(a) * radius_a), Vector3(cos(b) * radius_b, 0.0, sin(b) * radius_b)]:
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh


func _shotgun_trail_mesh(kind: String = "shotgun_trail") -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in range(4):
		var a := TAU * float(side) / 4.0 + PI * 0.25
		var b := a + PI * 0.5
		var front_a := Vector3(cos(a) * 0.5, sin(a) * 0.5, 0.0)
		var front_b := Vector3(cos(b) * 0.5, sin(b) * 0.5, 0.0)
		var tail_a := Vector3(cos(a) * 0.04, sin(a) * 0.04, 1.0)
		var tail_b := Vector3(cos(b) * 0.04, sin(b) * 0.04, 1.0)
		for point in [front_a, front_b, tail_b, front_a, tail_b, tail_a]:
			var front := Color(1.0, 0.86, 0.60, 1.0) if kind == "shotgun_trail" else Color.WHITE
			mesh.surface_set_color(front if point.z < 0.5 else Color(1.0, 1.0, 1.0, 0.0))
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh
