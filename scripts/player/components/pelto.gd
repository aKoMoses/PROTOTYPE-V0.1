extends Node

# Pelto preparation, waves, pull and weapon restoration.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "PeltoComponent"


func start_pelto_pull(pull_direction: Vector3, distance: float, duration: float, _source_id: String = "", _attack_id: String = "") -> void:
	if player.is_eclipse_travelling():
		return
	if distance > 0.0 and duration > 0.0 and player._counter != null:
		player._counter.cancel()
	if player.is_real_dead() or player._stasis_remaining > 0.0 or player._fulguro_projection_active or player._dash_active or (player.combat_state != null and player.combat_state.is_stunned()) or distance <= 0.0 or duration <= 0.0:
		return
	player._pelto_pull_active = true
	player._pelto_pull_direction = PLAYER_STATE.PELTO_SMASH.flat_direction(pull_direction)
	player._pelto_pull_distance_remaining = maxf(0.0, distance)
	player._pelto_pull_time_remaining = maxf(0.001, duration)
	player._pelto_pull_speed = player._pelto_pull_distance_remaining / player._pelto_pull_time_remaining


func _update_pelto_pull(delta: float) -> void:
	if not player._pelto_pull_active:
		return
	if player.is_real_dead() or player._stasis_remaining > 0.0 or player._fulguro_projection_active or (player.combat_state != null and player.combat_state.is_stunned()):
		player._cancel_pelto_pull()
		return
	var available_time := minf(maxf(delta, 0.0), player._pelto_pull_time_remaining)
	var step_distance := minf(player._pelto_pull_distance_remaining, player._pelto_pull_speed * available_time)
	if step_distance <= 0.0001:
		player._cancel_pelto_pull()
		return
	var collision := player.move_and_collide(ARENA_TRAVERSAL.motion(player, player._pelto_pull_direction * step_distance))
	ARENA_TRAVERSAL.snap(player)
	var travelled := collision.get_travel().length() if collision != null else step_distance
	player._pelto_pull_distance_remaining = maxf(0.0, player._pelto_pull_distance_remaining - travelled)
	player._pelto_pull_time_remaining = maxf(0.0, player._pelto_pull_time_remaining - available_time)
	if collision != null or player._pelto_pull_distance_remaining <= 0.001 or player._pelto_pull_time_remaining <= 0.001:
		player._cancel_pelto_pull()


func _cancel_pelto_pull() -> void:
	player._pelto_pull_active = false
	player._pelto_pull_direction = Vector3.ZERO
	player._pelto_pull_distance_remaining = 0.0
	player._pelto_pull_time_remaining = 0.0
	player._pelto_pull_speed = 0.0


func is_pelto_pulled() -> bool:
	return player._pelto_pull_active


func _perform_pelto_smash(aim_held: bool = false) -> void:
	if player._stasis_remaining > 0.0 or player._fulguro_projection_active or not player._module_ready("pelto_smash") or player.is_real_dead() or (player.combat_state != null and player.combat_state.is_stunned()):
		return
	var action_token: int = player._try_begin_module_action("pelto_smash")
	if action_token == 0:
		return
	player._mark_combat_event()
	player._module_busy = true
	player._module_token += 1
	player._pelto_attack_serial += 1
	player._pelto_phase = "preparation"
	player._pelto_elapsed = 0.0
	player._pelto_direction = PLAYER_STATE.PELTO_SMASH.flat_direction(player.aim_direction)
	player._pelto_aim_held = aim_held
	player._pelto_release_requested = false
	player._pelto_module_aim = Vector3.ZERO
	player._pelto_weapon_restore_serial += 1
	player._start_module_cooldown("pelto_smash", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"].cooldown))
	player._create_pelto_telegraph()
	player._set_pelto_weapon_hidden(true)
	player._update_pelto_pose()
	player._update_aim_pose_state()
	if player._attack_label != null:
		player._attack_label.text = "PELTO SMASH  •  PRÉPARATION"


func is_pelto_preparing() -> bool:
	return player._pelto_phase == "preparation"


func get_pelto_preparation_fraction() -> float:
	return clampf(player._pelto_elapsed / maxf(0.001, player._pelto_preparation), 0.0, 1.0) if player._pelto_phase == "preparation" else 0.0


func set_pelto_touch_aim(vector: Vector2) -> void:
	if not player.is_pelto_preparing() or not player._pelto_aim_held or player._pelto_release_requested or vector.length_squared() < 0.04:
		return
	player._pelto_module_aim = player._camera_relative_direction(vector)
	player._set_aim_direction(player._pelto_module_aim)
	player._pelto_direction = PLAYER_STATE.PELTO_SMASH.flat_direction(player.aim_direction)
	player._update_pelto_telegraph()


func _release_pelto_aim() -> void:
	if not player.is_pelto_preparing() or not player._pelto_aim_held or player._pelto_release_requested:
		return
	player._pelto_direction = PLAYER_STATE.PELTO_SMASH.flat_direction(player.aim_direction)
	player._pelto_release_requested = true


func _update_pelto_attack(delta: float) -> void:
	if player._pelto_phase == "":
		return
	if not player._module_action_can_execute(player._active_module_action_token, "pelto_smash"):
		player._cancel_pelto_smash()
		return
	if player.is_real_dead() or player._stasis_remaining > 0.0 or player._fulguro_projection_active or (player.combat_state != null and player.combat_state.is_stunned()):
		player._cancel_pelto_smash("PELTO SMASH  •  INTERROMPU")
		return
	player._pelto_elapsed += maxf(0.0, delta)
	if player._pelto_phase == "preparation":
		if player._pelto_aim_held and not player._pelto_release_requested:
			player._pelto_direction = PLAYER_STATE.PELTO_SMASH.flat_direction(player.aim_direction)
		player._update_pelto_telegraph()
		player._update_pelto_pose()
		var hold_limit := float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.pelto_smash.max_aim_hold)
		if player._pelto_elapsed >= player._pelto_preparation and (not player._pelto_aim_held or player._pelto_release_requested or player._pelto_elapsed >= hold_limit):
			var carry := maxf(0.0, player._pelto_elapsed - player._pelto_preparation) if not player._pelto_aim_held else 0.0
			player._commit_pelto_impact()
			player._pelto_elapsed = carry
		else:
			return
	if player._pelto_phase == "impact" and player._pelto_elapsed >= player._pelto_impact_duration:
		player._pelto_elapsed -= player._pelto_impact_duration
		player._pelto_phase = "recovery"
		if player._attack_label != null:
			player._attack_label.text = "PELTO SMASH  •  REPRISE"
	if player._pelto_phase == "recovery" and player._pelto_elapsed >= player._pelto_recovery:
		player._finish_pelto_smash()
		return
	player._update_pelto_pose()


func _commit_pelto_impact() -> void:
	if not player._module_action_can_execute(player._active_module_action_token, "pelto_smash"):
		player._cancel_pelto_smash()
		return
	player._pelto_phase = "impact"
	player._pelto_elapsed = 0.0
	player._pelto_aim_held = false
	player._pelto_module_aim = Vector3.ZERO
	player._clear_pelto_telegraph()
	# The shared wave owns its outbound, return and confirmed contact sounds.
	player._camera_impulse(0.08, 0.05)
	player._spawn_particle_burst(player.global_position + Vector3.UP * 0.08, Color("#c47b43"), 14, 0.30, 3.5, 0.13, player._pelto_direction + Vector3.UP * 0.22, 45.0)
	var scene := player.get_tree().current_scene if player.get_tree() != null else null
	if scene != null:
		var wave := PLAYER_STATE.PELTO_SMASH.new()
		wave.name = "PeltoSmashWave_%d" % player._pelto_attack_serial
		scene.add_child(wave)
		wave.call("configure", player, player.global_position, player._pelto_direction, "player", "pelto:%d" % player._pelto_attack_serial, player._pelto_damage_multiplier)
		player._pelto_waves.append(wave)
		wave.finished.connect(Callable(player, "_on_pelto_wave_finished").bind(wave), CONNECT_ONE_SHOT)
		player._register_fx_budget(wave, "projectile")
	if player._attack_label != null:
		player._attack_label.text = "PELTO SMASH  •  IMPACT"
	player._update_pelto_pose()


func _on_pelto_wave_finished(wave: Node) -> void:
	player._pelto_waves.erase(wave)


func _on_pelto_hit(target: Node, returning: bool, applied_damage: float) -> void:
	if not returning or not player._survival_evolved("offensive") or target == null or not target is Node3D:
		return
	player._survival_area_damage((target as Node3D).global_position, 2.5, applied_damage * 0.35, "pelto_aftershock", Color("#d99a5b"), target)


func _create_pelto_telegraph() -> void:
	player._clear_pelto_telegraph()
	var values: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"]
	var root := Node3D.new()
	root.name = "PeltoSmashTelegraph"
	var lane := MeshInstance3D.new()
	player._pelto_lane_mesh = BoxMesh.new()
	player._pelto_lane_mesh.size = Vector3(float(values.width), 0.022, float(values.max_range))
	lane.mesh = player._pelto_lane_mesh
	lane.position = Vector3(0.0, 0.0, -float(values.max_range) * 0.5)
	lane.material_override = player._pelto_ground_material(Color("#8b593b"), 0.30)
	root.add_child(lane)
	for segment in range(1, 7):
		var ridge := MeshInstance3D.new()
		var ridge_mesh := BoxMesh.new()
		ridge_mesh.size = Vector3(float(values.width) * 0.94, 0.035, 0.045)
		ridge.mesh = ridge_mesh
		ridge.position = Vector3(0.0, 0.018, -float(values.max_range) * float(segment) / 7.0)
		ridge.material_override = player._pelto_ground_material(Color("#d39a5c"), 0.62)
		root.add_child(ridge)
	var strike := MeshInstance3D.new()
	var strike_mesh := CylinderMesh.new()
	strike_mesh.top_radius = 0.34
	strike_mesh.bottom_radius = 0.42
	strike_mesh.height = 0.035
	strike_mesh.radial_segments = 16
	strike.mesh = strike_mesh
	strike.position = Vector3(0.0, 0.025, -0.28)
	strike.material_override = player._pelto_ground_material(Color("#f0ba6a"), 0.82)
	root.add_child(strike)
	player._scene_add_child(root)
	player._pelto_indicator = root
	player._update_pelto_telegraph()


func _update_pelto_telegraph() -> void:
	if player._pelto_indicator == null or not is_instance_valid(player._pelto_indicator):
		return
	player._pelto_indicator.global_position = player.global_position + Vector3.UP * 0.045
	player._pelto_indicator.global_basis = Basis.looking_at(player._pelto_direction, Vector3.UP)
	var progress := clampf(player._pelto_elapsed / maxf(0.001, player._pelto_preparation), 0.0, 1.0)
	player._pelto_indicator.scale.y = lerpf(0.65, 1.0, smoothstep(0.0, 1.0, progress))


func _clear_pelto_telegraph() -> void:
	if player._pelto_indicator != null and is_instance_valid(player._pelto_indicator):
		player._pelto_indicator.queue_free()
	player._pelto_indicator = null
	player._pelto_lane_mesh = null


func _update_pelto_pose() -> void:
	if player._visual_rig == null or not player._visual_rig.has_method("set_pelto_pose"):
		return
	var duration := player._pelto_preparation if player._pelto_phase == "preparation" else player._pelto_impact_duration if player._pelto_phase == "impact" else player._pelto_recovery
	player._visual_rig.call("set_pelto_pose", player._pelto_phase, clampf(player._pelto_elapsed / maxf(0.001, duration), 0.0, 1.0))


func _finish_pelto_smash() -> void:
	player._desktop_pelto_aim_held = false
	player._pelto_aim_held = false
	player._pelto_release_requested = false
	player._pelto_module_aim = Vector3.ZERO
	var action_token := player._active_module_action_token if player._active_module_id == "pelto_smash" else 0
	player._clear_pelto_telegraph()
	if player._visual_rig != null and player._visual_rig.has_method("clear_pelto_pose"):
		player._visual_rig.call("clear_pelto_pose")
	player._pelto_phase = ""
	player._pelto_elapsed = 0.0
	player._end_module_action(action_token, "pelto_smash")
	player._update_aim_pose_state(true)
	player._queue_pelto_weapon_restore()
	if player._attack_label != null:
		player._attack_label.text = "PELTO SMASH  •  CD 10s"


func _cancel_pelto_smash(reason: String = "") -> void:
	player._desktop_pelto_aim_held = false
	player._pelto_aim_held = false
	player._pelto_release_requested = false
	player._pelto_module_aim = Vector3.ZERO
	var action_token := player._active_module_action_token if player._active_module_id == "pelto_smash" else 0
	player._clear_pelto_telegraph()
	if player._visual_rig != null and player._visual_rig.has_method("clear_pelto_pose"):
		player._visual_rig.call("clear_pelto_pose")
	player._pelto_phase = ""
	player._pelto_elapsed = 0.0
	player._end_module_action(action_token, "pelto_smash")
	player._update_aim_pose_state(true)
	player._queue_pelto_weapon_restore()
	if reason != "" and player._attack_label != null:
		player._attack_label.text = reason


func _set_pelto_weapon_hidden(hidden: bool) -> void:
	player._pelto_weapon_hidden = hidden
	if hidden:
		if player._blaster_pivot != null:
			player._blaster_pivot.visible = false
		if player._shotgun_pivot != null:
			player._shotgun_pivot.visible = false
	else:
		player._update_weapon_visuals()


func _queue_pelto_weapon_restore() -> void:
	player._pelto_weapon_restore_serial += 1
	player._restore_pelto_weapon_after_skeleton(player._pelto_weapon_restore_serial)


func _restore_pelto_weapon_after_skeleton(restore_serial: int) -> void:
	# BoneAttachment3D is refreshed after animation and SkeletonModifier3D. Keep
	# the weapon hidden until two complete frames have replaced the last Pelto
	# pose; revealing it earlier exposes the attachment at its stale world pose.
	var scene_tree := player.get_tree()
	if scene_tree == null:
		return
	for _frame in range(2):
		await scene_tree.process_frame
	if restore_serial != player._pelto_weapon_restore_serial or player._pelto_phase != "" or not player.is_inside_tree():
		return
	if player._visual_rig != null and player._visual_rig.has_method("settle_weapon_attachment_after_transient_pose"):
		player._visual_rig.call("settle_weapon_attachment_after_transient_pose")
	player._set_pelto_weapon_hidden(false)


func _pelto_ground_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.95
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color.darkened(0.62)
	material.emission_energy_multiplier = 0.16
	return material
