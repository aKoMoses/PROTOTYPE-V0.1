class_name TrainingBot
extends Node

## Lightweight local opponent used for manual combat/visibility testing.
## It is opt-in (F7), uses a readable wind-up telegraph, and deliberately
## applies raw damage only: status effects must still come from the player's
## weapons/modules or explicit diagnostics.

const ATTACK_INTERVAL := 2.20
const ATTACK_DAMAGE := 35.0
const ATTACK_RANGE := 9.5
const WINDUP_DURATION := 0.55
const MOVE_RADIUS_X := 2.8
const MOVE_RADIUS_Z := 2.0
const MOVE_SPEED := 1.8
const PROJECTILE_TRAVEL_TIME := 0.16
const IDEAL_RANGE_MIN := 5.6
const IDEAL_RANGE_MAX := 8.4
const DODGE_DURATION := 0.34
const DODGE_COOLDOWN := 3.5
const DODGE_SPEED := 7.2
const MOVE_ACCELERATION := 7.0

var enabled := false
var _elapsed := 0.0
var _next_attack_at := 1.0
var _attack_serial := 0
var _spawn_position := Vector3.ZERO
var _windup_remaining := 0.0
var _windup_player: Node3D
var _telegraph_ring: MeshInstance3D
var _telegraph_line: MeshInstance3D
var _telegraph_target: MeshInstance3D
var _telegraph_beacon: MeshInstance3D
var _telegraph_clock := 0.0
var _dodge_remaining := 0.0
var _dodge_cooldown_remaining := 0.0
var _dodge_direction := Vector3.ZERO
var _move_velocity := Vector3.ZERO


func _ready() -> void:
	var owner_3d := get_parent() as Node3D
	if owner_3d != null:
		_spawn_position = owner_3d.global_position
	_build_telegraph()
	set_physics_process(false)


func set_enabled(value: bool) -> void:
	enabled = value
	_elapsed = 0.0
	_next_attack_at = 1.0
	_attack_serial = 0
	_windup_remaining = 0.0
	_windup_player = null
	_dodge_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_dodge_direction = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_update_telegraph()
	set_physics_process(enabled)
	var owner_3d := get_parent() as Node3D
	if owner_3d != null:
		owner_3d.set_meta("training_bot_enabled", enabled)


func toggle() -> bool:
	set_enabled(not enabled)
	return enabled


func reset_clock() -> void:
	_elapsed = 0.0
	_next_attack_at = 1.0
	_attack_serial = 0
	_windup_remaining = 0.0
	_windup_player = null
	_dodge_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_dodge_direction = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_update_telegraph()


func is_enabled() -> bool:
	return enabled


func is_telegraph_active() -> bool:
	return enabled and _windup_remaining > 0.0


func is_dodging() -> bool:
	return enabled and _dodge_remaining > 0.0


func get_dodge_cooldown_remaining() -> float:
	return maxf(0.0, _dodge_cooldown_remaining)


func get_attack_phase() -> String:
	if not enabled:
		return "DISABLED"
	return "WINDUP" if _windup_remaining > 0.0 else "READY"


func _physics_process(delta: float) -> void:
	if not enabled or delta <= 0.0:
		return
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	var player := scene.get_node_or_null("Player") as Node3D if scene != null else null
	if bot_body == null or player == null or not is_instance_valid(player):
		return
	_elapsed += delta
	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	if _dodge_remaining > 0.0:
		_dodge_remaining = maxf(0.0, _dodge_remaining - delta)
		_move_velocity = _move_velocity.move_toward(_dodge_direction * DODGE_SPEED, MOVE_ACCELERATION * delta)
		_move_bot(bot_body, delta)
	else:
		_try_dodge(bot_body, player)
		if _dodge_remaining <= 0.0:
			_update_patrol(bot_body, player, delta)
	_telegraph_clock += delta
	if _windup_remaining > 0.0:
		_windup_remaining = maxf(0.0, _windup_remaining - delta)
		_update_telegraph()
		if _windup_remaining <= 0.0:
			_resolve_attack(bot_body, _windup_player)
			_windup_player = null
			_next_attack_at = _elapsed + ATTACK_INTERVAL
		return
	if _elapsed < _next_attack_at:
		return
	if _can_attack(bot_body, player):
		_begin_attack(player)
	else:
		# Recheck quickly when the player is behind cover instead of locking the
		# bot into a long empty cooldown.
		_next_attack_at = _elapsed + 0.35


func _update_patrol(bot_body: Node3D, player: Node3D, delta: float) -> void:
	var to_player := player.global_position - bot_body.global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var desired: Vector3
	if distance < IDEAL_RANGE_MIN and distance > 0.05:
		desired = bot_body.global_position - to_player.normalized() * 2.2
	elif distance > IDEAL_RANGE_MAX and distance > 0.05:
		desired = bot_body.global_position + to_player.normalized() * 2.0
	else:
		desired = _spawn_position + Vector3(
			sin(_elapsed * 0.72) * MOVE_RADIUS_X,
			0.0,
			cos(_elapsed * 0.53) * MOVE_RADIUS_Z
		)
	desired.x = clampf(desired.x, -27.0, 27.0)
	desired.z = clampf(desired.z, -27.0, 27.0)
	var to_desired := desired - bot_body.global_position
	to_desired.y = 0.0
	var desired_velocity := Vector3.ZERO
	if to_desired.length_squared() > 0.04:
		desired_velocity = to_desired.normalized() * MOVE_SPEED
	_move_velocity = _move_velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)
	_move_bot(bot_body, delta)


func _move_bot(bot_body: Node3D, delta: float) -> void:
	if _move_velocity.length_squared() <= 0.04:
		_move_velocity = Vector3.ZERO
	bot_body.global_position += _move_velocity * delta
	bot_body.global_position.x = clampf(bot_body.global_position.x, -27.0, 27.0)
	bot_body.global_position.z = clampf(bot_body.global_position.z, -27.0, 27.0)
	bot_body.global_position.y = 0.0


func _try_dodge(bot_body: Node3D, player: Node3D) -> void:
	if _dodge_cooldown_remaining > 0.0 or not player.has_method("is_attack_committed"):
		return
	if not bool(player.call("is_attack_committed")):
		return
	var away := bot_body.global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.RIGHT
	else:
		away = away.normalized()
	_dodge_direction = Vector3(-away.z, 0.0, away.x).normalized()
	if int(_attack_serial + int(_elapsed * 10.0)) % 2 == 0:
		_dodge_direction = -_dodge_direction
	_dodge_remaining = DODGE_DURATION
	_dodge_cooldown_remaining = DODGE_COOLDOWN
	_move_velocity = _dodge_direction * DODGE_SPEED


func _can_attack(bot_body: Node3D, player: Node3D) -> bool:
	if bot_body.global_position.distance_to(player.global_position) > ATTACK_RANGE:
		return false
	if player.has_method("is_visible_to") and not bool(player.call("is_visible_to", bot_body)):
		return false
	return _line_of_sight_clear(bot_body, player)


func _begin_attack(player: Node3D) -> void:
	_windup_player = player
	_windup_remaining = WINDUP_DURATION
	_telegraph_clock = 0.0
	_update_telegraph()


func _resolve_attack(bot_body: Node3D, player: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _can_attack(bot_body, player):
		_attack_player(player)


func _line_of_sight_clear(bot_body: Node3D, player: Node3D) -> bool:
	var world := bot_body.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(bot_body.global_position + Vector3.UP * 0.72, player.global_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [bot_body.get_rid(), player.get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


func _attack_player(player: Node3D) -> void:
	if not player.has_method("take_damage"):
		return
	_attack_serial += 1
	# Le dégât est résolu à l'arrivée du projectile : le flash, la secousse et
	# l'impact visuel restent ainsi synchronisés avec le tir réellement affiché.
	_spawn_attack_visual(player, "training_bot:%d" % _attack_serial)


func _spawn_attack_visual(player: Node3D, attack_id: String) -> void:
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	if bot_body == null or scene == null:
		return
	var tracer := Node3D.new()
	tracer.name = "TrainingBotProjectile"
	var start_position := bot_body.global_position + Vector3.UP * 1.30
	var impact_position := player.global_position + Vector3.UP * 0.92
	var direction := (impact_position - start_position).normalized()
	scene.add_child(tracer)
	_register_fx_budget(tracer, "projectile")
	tracer.global_position = start_position
	tracer.look_at(start_position + direction, Vector3.UP)
	_spawn_muzzle_visual(scene, start_position, direction)
	var projectile_mesh := CylinderMesh.new()
	projectile_mesh.top_radius = 0.035
	projectile_mesh.bottom_radius = 0.16
	projectile_mesh.height = 0.48
	var slug := MeshInstance3D.new()
	slug.mesh = projectile_mesh
	slug.rotation_degrees.x = -90.0
	slug.position = Vector3(0.0, 0.0, -0.10)
	var projectile_material := StandardMaterial3D.new()
	projectile_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	projectile_material.albedo_color = Color("#ffb85c")
	projectile_material.emission_enabled = true
	projectile_material.emission = Color("#ff4b25")
	projectile_material.emission_energy_multiplier = 4.0
	slug.material_override = projectile_material
	tracer.add_child(slug)
	var core := MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.018
	core_mesh.bottom_radius = 0.065
	core_mesh.height = 0.33
	core.mesh = core_mesh
	core.rotation_degrees.x = -90.0
	core.position = Vector3(0.0, 0.0, -0.25)
	core.material_override = _fx_material(Color("#fff1b2"), 0.98, Color("#ffb73d"))
	tracer.add_child(core)
	var trail := MeshInstance3D.new()
	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = 0.015
	trail_mesh.bottom_radius = 0.09
	trail_mesh.height = 0.70
	trail.mesh = trail_mesh
	trail.rotation_degrees.x = -90.0
	trail.position = Vector3(0.0, 0.0, 0.34)
	trail.material_override = _fx_material(Color("#ff5d32"), 0.28, Color("#ff2a1b"))
	tracer.add_child(trail)
	var tracer_light := OmniLight3D.new()
	tracer_light.light_color = Color("#ff6a32")
	tracer_light.light_energy = 1.2
	tracer_light.omni_range = 1.8
	tracer.add_child(tracer_light)
	var pulse := tracer.create_tween()
	pulse.set_loops(8)
	pulse.tween_property(slug, "scale", Vector3(1.18, 1.0, 1.18), 0.08).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(slug, "scale", Vector3.ONE, 0.08).set_trans(Tween.TRANS_SINE)
	var travel := tracer.create_tween()
	travel.tween_property(tracer, "global_position", impact_position, PROJECTILE_TRAVEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	travel.tween_callback(Callable(self, "_resolve_projectile").bind(player, scene, impact_position, attack_id))
	travel.tween_callback(tracer.queue_free)


func _resolve_projectile(player: Node3D, scene: Node, impact_position: Vector3, attack_id: String) -> void:
	if player != null and is_instance_valid(player) and player.has_method("take_damage"):
		player.call("take_damage", ATTACK_DAMAGE, "training_bot", attack_id)
	_spawn_impact_visual(scene, impact_position)


func _spawn_muzzle_visual(scene: Node, origin: Vector3, direction: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.16
	flash_mesh.height = 0.30
	flash.mesh = flash_mesh
	flash.material_override = _fx_material(Color("#ffe0a1"), 0.98, Color("#ff4b25"))
	scene.add_child(flash)
	_register_fx_budget(flash, "burst")
	flash.global_position = origin + direction * 0.22
	var flash_tween := flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector3(2.2, 1.0, 1.5), 0.08)
	flash_tween.tween_property(flash.material_override, "albedo_color", Color(1.0, 0.55, 0.30, 0.0), 0.10)
	flash_tween.set_parallel(false)
	flash_tween.tween_callback(flash.queue_free)
	_spawn_particle_burst(scene, origin, Color("#ff8b43"), 10, 3.6, 0.18, direction)


func _spawn_particle_burst(scene: Node, origin: Vector3, color: Color, amount: int, speed: float, lifetime: float, direction: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "TrainingBotBurst"
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-4.0, -4.0, -4.0), Vector3(8.0, 8.0, 8.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = direction.normalized()
	process_material.spread = 40.0
	process_material.initial_velocity_min = speed * 0.55
	process_material.initial_velocity_max = speed
	process_material.gravity = Vector3(0.0, -4.0, 0.0)
	process_material.scale_min = 0.045
	process_material.scale_max = 0.09
	particles.process_material = process_material
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.055
	spark_mesh.height = 0.11
	spark_mesh.material = _fx_material(color, 0.95, color)
	particles.draw_pass_1 = spark_mesh
	scene.add_child(particles)
	_register_fx_budget(particles, "particle")
	particles.global_position = origin
	particles.emitting = true
	scene.get_tree().create_timer(lifetime + 0.25).timeout.connect(particles.queue_free)


func _fx_material(color: Color, alpha: float, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 3.5
	if alpha < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _register_fx_budget(node: Node, category: String = "burst") -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_method("register_fx_node"):
		scene.call("register_fx_node", node, category)


func _spawn_impact_visual(scene: Node, impact_position: Vector3) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	var flash := OmniLight3D.new()
	flash.name = "TrainingBotImpactLight"
	flash.position = impact_position
	flash.light_color = Color("#ff754b")
	flash.light_energy = 2.8
	flash.omni_range = 2.2
	scene.add_child(flash)
	var impact := MeshInstance3D.new()
	impact.name = "TrainingBotImpact"
	var impact_mesh := SphereMesh.new()
	impact_mesh.radius = 0.18
	impact_mesh.height = 0.36
	impact.mesh = impact_mesh
	var impact_material := StandardMaterial3D.new()
	impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	impact_material.albedo_color = Color("#ffb15a")
	impact_material.emission_enabled = true
	impact_material.emission = Color("#ff4a26")
	impact_material.emission_energy_multiplier = 2.6
	impact.material_override = impact_material
	scene.add_child(impact)
	_register_fx_budget(impact, "burst")
	impact.global_position = impact_position
	var pulse := impact.create_tween()
	pulse.tween_property(impact, "scale", Vector3.ONE * 2.2, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_callback(impact.queue_free)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.22
	ring_mesh.outer_radius = 0.30
	ring.mesh = ring_mesh
	ring.rotation_degrees.x = 90.0
	ring.material_override = _fx_material(Color("#ffd38b"), 0.92, Color("#ff572f"))
	scene.add_child(ring)
	_register_fx_budget(ring, "burst")
	ring.global_position = impact_position + Vector3.DOWN * 0.18
	var ring_tween := ring.create_tween()
	ring_tween.set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector3.ONE * 2.0, 0.24)
	ring_tween.tween_property(ring.material_override, "albedo_color", Color(1.0, 0.45, 0.22, 0.0), 0.24)
	ring_tween.set_parallel(false)
	ring_tween.tween_callback(ring.queue_free)
	_spawn_particle_burst(scene, impact_position, Color("#ff7440"), 18, 4.8, 0.28, Vector3.UP)
	var fade := flash.create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 0.18)
	fade.tween_callback(flash.queue_free)


func _build_telegraph() -> void:
	_telegraph_ring = MeshInstance3D.new()
	_telegraph_ring.name = "AttackTelegraph"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.02
	ring_mesh.outer_radius = 1.16
	ring_mesh.rings = 12
	ring_mesh.ring_segments = 28
	_telegraph_ring.mesh = ring_mesh
	_telegraph_ring.position.y = 0.08
	_telegraph_ring.rotation_degrees.x = 90.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ffba58")
	material.emission_enabled = true
	material.emission = Color("#ff6b32")
	material.emission_energy_multiplier = 2.4
	_telegraph_ring.material_override = material
	_telegraph_ring.visible = false
	_add_telegraph_node(_telegraph_ring)

	# Secondary floor telegraph: a readable lane and destination marker. These
	# are visual-only and deliberately do not participate in physics or damage.
	_telegraph_line = MeshInstance3D.new()
	_telegraph_line.name = "AttackTelegraphLine"
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(0.18, 0.035, 1.0)
	_telegraph_line.mesh = line_mesh
	_telegraph_line.top_level = true
	_telegraph_line.position.y = 0.10
	_telegraph_line.material_override = _fx_material(Color("#ffb25c"), 1.0, Color("#ff4d2f"))
	_telegraph_line.visible = false
	_add_telegraph_node(_telegraph_line)

	_telegraph_target = MeshInstance3D.new()
	_telegraph_target.name = "AttackTelegraphTarget"
	var target_mesh := TorusMesh.new()
	target_mesh.inner_radius = 0.52
	target_mesh.outer_radius = 0.68
	target_mesh.rings = 10
	target_mesh.ring_segments = 24
	_telegraph_target.mesh = target_mesh
	_telegraph_target.top_level = true
	_telegraph_target.position.y = 0.11
	_telegraph_target.rotation_degrees.x = 90.0
	_telegraph_target.material_override = _fx_material(Color("#ffd17a"), 1.0, Color("#ff4b25"))
	_telegraph_target.visible = false
	_add_telegraph_node(_telegraph_target)

	_telegraph_beacon = MeshInstance3D.new()
	_telegraph_beacon.name = "AttackTelegraphBeacon"
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.05
	beacon_mesh.bottom_radius = 0.18
	beacon_mesh.height = 0.42
	beacon_mesh.radial_segments = 8
	_telegraph_beacon.mesh = beacon_mesh
	_telegraph_beacon.top_level = true
	_telegraph_beacon.material_override = _fx_material(Color("#ffe0a2"), 1.0, Color("#ff5a2d"))
	_telegraph_beacon.visible = false
	_add_telegraph_node(_telegraph_beacon)


func _add_telegraph_node(node: Node) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null:
		scene.add_child(node)
	else:
		add_child(node)


func _update_telegraph() -> void:
	if _telegraph_ring == null or _telegraph_line == null or _telegraph_target == null or _telegraph_beacon == null:
		return
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	var player := scene.get_node_or_null("Player") as Node3D if scene != null else null
	var visible_to_player := true
	if bot_body != null and player != null and bot_body.has_method("is_visible_to"):
		visible_to_player = bool(bot_body.call("is_visible_to", player))
	var active := enabled and _windup_remaining > 0.0 and visible_to_player and _windup_player != null and is_instance_valid(_windup_player)
	_telegraph_ring.visible = active
	_telegraph_line.visible = active
	_telegraph_target.visible = active
	_telegraph_beacon.visible = active
	if not active:
		return
	var target_position := _windup_player.global_position
	var bot_position := bot_body.global_position if bot_body != null else Vector3.ZERO
	var flat_delta := target_position - bot_position
	flat_delta.y = 0.0
	var distance := maxf(flat_delta.length(), 0.05)
	var pulse := 1.0 + sin(_telegraph_clock * 18.0) * 0.12
	_telegraph_ring.global_position = bot_position + Vector3.UP * 0.08
	_telegraph_ring.scale = Vector3.ONE * pulse
	_telegraph_target.global_position = target_position + Vector3.UP * 0.11
	_telegraph_target.scale = Vector3.ONE * (0.92 + sin(_telegraph_clock * 16.0) * 0.10)
	_telegraph_beacon.global_position = target_position + Vector3.UP * (2.55 + sin(_telegraph_clock * 14.0) * 0.08)
	_telegraph_beacon.scale = Vector3.ONE * (0.92 + sin(_telegraph_clock * 18.0) * 0.13)
	_telegraph_line.global_position = bot_position + flat_delta * 0.5 + Vector3.UP * 0.10
	_telegraph_line.look_at(target_position + Vector3.UP * 0.10, Vector3.UP)
	_telegraph_line.scale = Vector3(1.0, 1.0, distance)
