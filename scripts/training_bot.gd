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

var enabled := false
var _elapsed := 0.0
var _next_attack_at := 1.0
var _attack_serial := 0
var _spawn_position := Vector3.ZERO
var _windup_remaining := 0.0
var _windup_player: Node3D
var _telegraph_ring: MeshInstance3D
var _telegraph_clock := 0.0


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
	_update_telegraph()


func is_enabled() -> bool:
	return enabled


func is_telegraph_active() -> bool:
	return enabled and _windup_remaining > 0.0


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
	_update_patrol(bot_body, delta)
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


func _update_patrol(bot_body: Node3D, delta: float) -> void:
	var desired := _spawn_position + Vector3(
		sin(_elapsed * 0.72) * MOVE_RADIUS_X,
		0.0,
		cos(_elapsed * 0.53) * MOVE_RADIUS_Z
	)
	var blend := clampf(delta * MOVE_SPEED, 0.0, 1.0)
	bot_body.global_position = bot_body.global_position.lerp(desired, blend)
	bot_body.global_position.y = 0.0


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
	_spawn_attack_visual(player)
	player.call("take_damage", ATTACK_DAMAGE, "training_bot", "training_bot:%d" % _attack_serial)


func _spawn_attack_visual(player: Node3D) -> void:
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	if bot_body == null or scene == null:
		return
	var tracer := MeshInstance3D.new()
	tracer.name = "TrainingBotProjectile"
	var projectile_mesh := SphereMesh.new()
	projectile_mesh.radius = 0.12
	projectile_mesh.height = 0.24
	tracer.mesh = projectile_mesh
	var projectile_material := StandardMaterial3D.new()
	projectile_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	projectile_material.albedo_color = Color("#ff8b4b")
	projectile_material.emission_enabled = true
	projectile_material.emission = Color("#ff3d20")
	projectile_material.emission_energy_multiplier = 3.2
	tracer.material_override = projectile_material
	scene.add_child(tracer)
	tracer.global_position = bot_body.global_position + Vector3.UP * 0.95
	var impact_position := player.global_position + Vector3.UP * 0.72
	var travel := tracer.create_tween()
	travel.tween_property(tracer, "global_position", impact_position, PROJECTILE_TRAVEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	travel.tween_callback(Callable(self, "_spawn_impact_visual").bind(scene, impact_position))
	travel.tween_callback(tracer.queue_free)


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
	impact.global_position = impact_position
	var pulse := impact.create_tween()
	pulse.tween_property(impact, "scale", Vector3.ONE * 2.2, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_callback(impact.queue_free)
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
	add_child(_telegraph_ring)


func _update_telegraph() -> void:
	if _telegraph_ring == null:
		return
	var bot_body := get_parent() as Node3D
	var scene := get_tree().current_scene if get_tree() != null else null
	var player := scene.get_node_or_null("Player") as Node3D if scene != null else null
	var visible_to_player := true
	if bot_body != null and player != null and bot_body.has_method("is_visible_to"):
		visible_to_player = bool(bot_body.call("is_visible_to", player))
	_telegraph_ring.visible = enabled and _windup_remaining > 0.0 and visible_to_player
	if _telegraph_ring.visible:
		var pulse := 1.0 + sin(_telegraph_clock * 18.0) * 0.12
		_telegraph_ring.scale = Vector3.ONE * pulse
