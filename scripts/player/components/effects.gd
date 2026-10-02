extends Node

# Shared targeting, collision queries, projectile registration and Survival effects.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "EffectsComponent"


func _vfx_manager() -> Node:
	var scene := player.get_tree().current_scene if player.get_tree() != null else null
	return scene.get_node_or_null("VFXManager") if scene != null else null


func _camera_impulse(duration: float, strength: float) -> void:
	var scene := player.get_tree().current_scene if player.get_tree() != null else null
	var rig := scene.get_node_or_null("CameraRig") if scene != null else null
	if rig != null and rig.has_method("shake"):
		rig.call("shake", duration, strength)


func _create_muzzle_burst(_origin: Vector3, _direction: Vector3, _color: Color, scale: float = 1.0, muzzle_anchor: Node3D = null) -> void:
	var socket = muzzle_anchor if muzzle_anchor != null else player._active_muzzle()
	var vfx: Node = player._vfx_manager()
	if vfx != null and socket != null:
		vfx.call("muzzle", socket, "shotgun" if socket == player._shotgun_muzzle else "blaster", clampf((scale - 1.0) / 0.65, 0.0, 1.0))


func _active_muzzle() -> Node3D:
	return player._shotgun_muzzle if player._weapon_id == "shotgun" else player._blaster_muzzle


func _visual_contact(start: Vector3, end: Vector3, target: Node = null) -> Dictionary:
	var delta := end - start
	if delta.length_squared() < 0.0001 or player.get_world_3d() == null:
		return {}
	# This query only positions VFX. Assisted combat ranges and hit tests stay unchanged.
	var query := PhysicsRayQueryParameters3D.create(start, end + delta.normalized() * 0.08, 9)
	if target is CollisionObject3D:
		query.collision_mask |= target.collision_layer
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()])
	query.collide_with_areas = true
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _contact_fx(contact: Dictionary, color: Color, power: float = 1.0, weapon: String = "") -> void:
	var vfx: Node = player._vfx_manager()
	if vfx == null or contact.is_empty():
		return
	var collider := contact.get("collider") as Node
	if not is_instance_valid(collider):
		collider = null
	var surface: String = vfx.call("surface_for", collider)
	if weapon == "shotgun":
		vfx.call("shotgun_impact", contact["position"], contact["normal"], surface, power)
	else:
		vfx.call("impact", contact["position"], contact["normal"], surface, power, color)
	if surface == "shield" and collider != null and collider.name == "MagneticField":
		player.get_node("/root/GameSfx").play_event("magnetic_absorb")
	elif surface != "robot" and surface != "shield":
		player.get_node("/root/GameSfx").play_event("impact_decor")


func _create_surface_impact_fx(origin: Vector3, direction: Vector3, color: Color = Color("#ff9c52")) -> void:
	var normal := direction.normalized() if direction.length_squared() > 0.001 else Vector3.UP
	player._contact_fx(player._visual_contact(origin + normal * 0.15, origin - normal * 0.15), color)


func _survival_evolved(category: String) -> bool:
	return player.survival_mode and bool(player._survival_evolutions.get(category, false)) and (player.survival_evolution_effects == null or player.survival_evolution_effects.rank(category) == 0)


func _survival_targets() -> Array:
	var scene := player.get_tree().current_scene
	return scene.call("get_training_targets") if scene != null and scene.has_method("get_training_targets") else []


func _survival_area_damage(center: Vector3, radius: float, damage: float, attack_name: String, color: Color, excluded: Node = null) -> void:
	if not player.survival_mode:
		return
	player._survival_pulse_fx(center, radius, color)
	var attack_id := "%s:%d" % [attack_name, Time.get_ticks_usec()]
	for enemy in player._survival_targets():
		if enemy == excluded or not is_instance_valid(enemy) or float(enemy.call("get_health")) <= 0.0:
			continue
		if center.distance_to(enemy.global_position) <= radius:
			var applied := float(enemy.call("take_damage", damage, "player", attack_id))
			if applied > 0.0:
				enemy.call("flash_impact", false)


func _survival_secondary_hit(primary: Node, damage: float, radius: float, attack_name: String, aligned: bool, direction: Vector3 = Vector3.ZERO) -> void:
	var candidate: Node = null
	var best_distance := INF
	for enemy in player._survival_targets():
		if enemy == primary or not is_instance_valid(enemy) or float(enemy.call("get_health")) <= 0.0:
			continue
		var offset: Vector3 = enemy.global_position - primary.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > radius or distance >= best_distance:
			continue
		if aligned and (direction.dot(offset) <= 0.0 or absf(direction.cross(offset.normalized()).y) > 0.24):
			continue
		var path_excluded: Array[RID] = [primary.get_rid(), enemy.get_rid()]
		if not player._solid_path_clear(primary.global_position, enemy.global_position, path_excluded):
			continue
		candidate = enemy
		best_distance = distance
	if candidate != null:
		var applied := float(candidate.call("take_damage", damage, "player", "%s:%d" % [attack_name, Time.get_ticks_usec()]))
		if applied > 0.0:
			candidate.call("flash_impact", false)
			player._create_lightning_arc(primary.global_position + Vector3.UP, candidate.global_position + Vector3.UP, Color("#8feaff"), 0.04, 0.25)


func _survival_pulse_fx(center: Vector3, radius: float, color: Color) -> void:
	var scene := player.get_tree().current_scene
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	ring.name = "SurvivalEvolutionPulse"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.90
	mesh.outer_radius = 1.0
	ring.mesh = mesh
	ring.rotation_degrees.x = 90
	ring.material_override = player._create_fx_material(color, 0.85)
	scene.add_child(ring)
	ring.global_position = center + Vector3.UP * 0.08
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * radius, 0.32)
	tween.tween_callback(ring.queue_free)


func _module_target() -> Node:
	var active_scene := player.get_tree().current_scene
	if active_scene != null and active_scene.has_method("get_training_targets"):
		return player._best_training_target(player.global_position, player.aim_direction, 20.0, 1.0)
	return active_scene.get_node_or_null("TargetDummy") if active_scene != null else null


func _best_training_target(origin: Vector3, direction: Vector3, max_range: float, radius_scale: float) -> Node:
	var scene := player.get_tree().current_scene
	if scene == null or not scene.has_method("get_training_targets"):
		return null
	var best: Node = null
	var best_along := INF
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	for candidate in scene.call("get_training_targets"):
		if not is_instance_valid(candidate) or not candidate.has_method("get_health") or float(candidate.call("get_health")) <= 0.0:
			continue
		var offset: Vector3 = candidate.global_position - origin
		offset.y = 0.0
		var along := flat_direction.dot(offset)
		if along <= 0.0 or along > max_range or along >= best_along:
			continue
		var lateral := (offset - flat_direction * along).length()
		var hit_radius := float(candidate.call("get_training_hit_radius")) if candidate.has_method("get_training_hit_radius") else 0.8
		var path_excluded: Array[RID] = [candidate.get_rid()]
		if lateral <= hit_radius * radius_scale and player._solid_path_clear(origin, candidate.global_position, path_excluded):
			best = candidate
			best_along = along
	return best


func _module_visual_start(direction: Vector3) -> Vector3:
	var muzzle: Node3D = player._active_muzzle()
	return muzzle.global_position if muzzle != null else player.global_position + Vector3.UP * 0.85 + direction * 0.45


func _module_obstacle_endpoint(start: Vector3, end: Vector3, excluded: Array[RID] = []) -> Vector3:
	var world := player.get_world_3d()
	if world == null:
		return end
	var query := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 0.72, end + Vector3.UP * 0.72)
	query.collision_mask = 9
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()] + excluded)
	var result := world.direct_space_state.intersect_ray(query)
	return result["position"] if not result.is_empty() else end


func _module_path_clear(from_position: Vector3, to_position: Vector3, excluded: Array[RID] = []) -> bool:
	var world := player.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_position + Vector3.UP * 0.72, to_position + Vector3.UP * 0.72)
	query.collision_mask = 9
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()] + excluded)
	return world.direct_space_state.intersect_ray(query).is_empty()


func _solid_path_clear(from_position: Vector3, to_position: Vector3, excluded: Array[RID] = []) -> bool:
	var world := player.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_position + Vector3.UP * 0.72, to_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()] + excluded)
	return world.direct_space_state.intersect_ray(query).is_empty()


func _scene_add_child(node: Node) -> void:
	var scene := player.get_tree().current_scene if player.get_tree() != null else null
	if scene != null:
		scene.add_child(node)
	else:
		player.add_child(node)


func _kill_weapon_recoil_tweens(tweens: Array[Tween]) -> void:
	for tween in tweens:
		if tween != null and tween.is_running():
			tween.kill()
	tweens.clear()


func _is_weapon_recoil_running(tweens: Array[Tween]) -> bool:
	for tween in tweens:
		if tween != null and tween.is_running():
			return true
	return false


func _safe_projectile_origin(muzzle: Vector3) -> Vector3:
	var origin := player.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(origin, muzzle)
	query.collision_mask = 1 | 2 | 4 | 8
	query.collide_with_areas = true
	# A contact overlap can put the reference point inside the target. Without
	# inside hits this segment ignores it and emits beyond the far side.
	query.hit_from_inside = true
	query.exclude = PLAYER_STATE.MAGNETIC_WALL.owned_exclusions(player, [player.get_rid()])
	return origin if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty() else muzzle


func _register_projectile_motion(projectile: Node3D, start: Vector3, endpoint: Vector3, duration: float, radius: float) -> void:
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.set_meta("ai_projectile_source", player.get_instance_id())
	projectile.set_meta("ai_projectile_velocity", (endpoint - start) / maxf(0.025, duration))
	projectile.set_meta("ai_projectile_endpoint", endpoint)
	projectile.set_meta("ai_projectile_radius", radius)


func _create_teleport_fx(origin: Vector3) -> void:
	player._spawn_particle_burst(origin + Vector3.UP * 0.45, Color("#dac99a"), 10, 0.25, 2.8, 0.12, Vector3.UP, 48.0)


func _create_fx_material(color: Color, alpha: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	return material


func _register_fx_budget(node: Node, category: String = "burst") -> void:
	var scene := player.get_tree().current_scene if player.get_tree() != null else null
	if scene != null and scene.has_method("register_fx_node"):
		scene.call("register_fx_node", node, category)


func _set_material_alpha(alpha: float, material: StandardMaterial3D) -> void:
	if material == null:
		return
	var color := material.albedo_color
	color.a = alpha
	material.albedo_color = color


func _create_lightning_arc(start: Vector3, end: Vector3, color: Color, width: float = 0.045, lifetime: float = 0.24) -> void:
	var vfx: Node = player._vfx_manager()
	if vfx != null:
		vfx.call("tracer", start, end, width, color, lifetime)


func _spawn_particle_burst(origin: Vector3, color: Color, amount: int, lifetime: float, speed: float, particle_scale: float, emission_direction: Vector3 = Vector3.UP, emission_spread: float = 180.0) -> void:
	var vfx: Node = player._vfx_manager()
	if vfx != null:
		vfx.call("burst", origin, emission_direction, color, mini(amount, 12), minf(speed, 5.0), minf(lifetime, 0.4), minf(particle_scale * 0.45, 0.06), minf(emission_spread, 75.0))


func _create_hit_flash(origin: Vector3, color: Color, radius: float) -> void:
	player._spawn_particle_burst(origin, color, 6, 0.18, 2.4, minf(radius * 0.10, 0.11), Vector3.UP, 65.0)


func _create_target_hit_fx(origin: Vector3, critical: bool) -> void:
	var color := Color("#efd099") if critical else Color("#dca579")
	player._spawn_particle_burst(origin + Vector3.UP * 0.85, color, 9 if critical else 5, 0.23, 3.2, 0.10, -player.aim_direction, 55.0)
