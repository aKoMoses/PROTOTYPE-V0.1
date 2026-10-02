extends Node

# Robot construction, animation, weapon attachments and world readouts.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")
const MODULE_POSE := preload("res://scripts/mecha_module_pose.gd")

var player: PLAYER_STATE
var _threat_check_remaining := 0.0
var _nearby_threat := false
var _module_gesture_id := ""
var _module_gesture_time := 0.0
var _module_release_time := -1.0
var _module_variants: Dictionary = {}
var _module_gesture_accepted := false
var _module_release_confirmed := false


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "PresentationComponent"


func _update_robot_motion(delta: float) -> void:
	if player._robot_visuals == null:
		return
	player._locomotion_clock += delta
	var visual_velocity: Vector3 = player._get_actual_move_velocity()
	player.move_direction = visual_velocity.normalized() if visual_velocity.length() > 0.15 else Vector3.ZERO
	var visual_speed := visual_velocity.length()
	var desired_amount := clampf(visual_speed / maxf(player.move_speed, 0.01), 0.0, 1.0)
	player._locomotion_amount = move_toward(player._locomotion_amount, desired_amount, delta * 8.0)
	for node in player._locomotion_nodes:
		if node == null or not is_instance_valid(node):
			continue
		var base_position: Vector3 = node.get_meta("locomotion_base_position", node.position)
		var base_rotation: Vector3 = node.get_meta("locomotion_base_rotation", node.rotation)
		var phase := float(node.get_meta("locomotion_phase", 0.0))
		var role := str(node.get_meta("locomotion_role", "body"))
		var stride := sin(player._locomotion_clock * 9.5 + phase) * player._locomotion_amount
		if role == "limb":
			node.position = base_position + Vector3(0.0, absf(stride) * 0.035, 0.0)
			node.rotation = base_rotation + Vector3(stride * 0.18, 0.0, 0.0)
		elif role == "head":
			node.position = base_position + Vector3(0.0, sin(player._locomotion_clock * 9.5 + phase) * 0.035 * player._locomotion_amount, 0.0)
			node.rotation = base_rotation + Vector3(0.0, sin(player._locomotion_clock * 4.7 + phase) * 0.025 * player._locomotion_amount, 0.0)
		else:
			node.position = base_position + Vector3(0.0, sin(player._locomotion_clock * 9.5 + phase) * 0.045 * player._locomotion_amount, 0.0)
			node.rotation = base_rotation
	if player._visual_rig != null:
		player._update_aim_pose_state()
		var quiet: bool = player._gameplay_enabled and not player.is_real_dead() and not player._round_warmup_active and visual_speed < 0.15
		quiet = quiet and not player._action_gate.is_busy() and not player._shotgun_reloading and not player._blaster_charge_active
		quiet = quiet and player._stasis_remaining <= 0.0 and not player.combat_state.is_stunned() and not player.is_eclipse_travelling()
		quiet = quiet and player.get_combat_reveal_remaining() <= 0.0 and player._touch_move_vector.length_squared() < 0.01
		_threat_check_remaining -= delta
		if quiet and _threat_check_remaining <= 0.0:
			_nearby_threat = _has_nearby_threat()
			_threat_check_remaining = 0.4
		quiet = quiet and not _nearby_threat
		player._visual_rig.set_presence_context(quiet, not player._weapon_pose_uses_aim() and not player._action_gate.is_busy())
		_update_module_gesture(delta)
		var visual_aim := player._fulguro_direction if player._fulguro_phase != "" else player.aim_direction
		if player._pelto_phase != "":
			visual_aim = player._pelto_direction
		if player._mekatana_attack.is_direction_locked():
			visual_aim = player._mekatana_attack.direction
		player._visual_rig.update_visual_state(player.move_direction, visual_aim, visual_speed, player.move_speed, delta, player._gameplay_enabled and not player.is_real_dead())
	if not player._has_skeletal_weapon_attachment():
		player._update_player_debug_vectors()


func begin_module_gesture(id: String) -> void:
	if not MODULE_POSE.PROFILES.has(id) or player._visual_rig == null or not player._visual_rig.presence_modifier.autonomous:
		return
	_module_gesture_id = id
	_module_gesture_accepted = true
	_module_gesture_time = 0.0
	_module_release_time = -1.0
	_module_release_confirmed = false
	_module_variants[id] = int(_module_variants.get(id, -1)) + 1


func reset_module_gesture() -> void:
	_module_gesture_id = ""
	_module_gesture_accepted = false
	_module_gesture_time = 0.0
	_module_release_time = -1.0
	_module_release_confirmed = false
	if player._visual_rig != null:
		player._visual_rig.clear_module_pose()


func confirm_module_release(id: String) -> void:
	if _module_gesture_id == id:
		_module_release_confirmed = true


func cancel_module_gesture(id: String) -> void:
	if _module_gesture_id == id:
		reset_module_gesture()


func _module_pose(id: String, phase: String, elapsed: float, duration: float) -> void:
	player._visual_rig.set_module_pose(id, phase, clampf(elapsed / maxf(0.001, duration), 0.0, 1.0), duration, int(_module_variants.get(id, 0)))


func _update_module_gesture(delta: float) -> void:
	# Authority follows the real ability phases. Replicas use the same snapshot
	# as idle/hit reactions, including the source clip variation and phase clock.
	if not player._visual_rig.presence_modifier.autonomous:
		return
	if not player._gameplay_enabled or player.is_real_dead() or player._round_warmup_active or player.combat_state.is_stunned():
		reset_module_gesture()
		return
	if player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.WEAPON) or player._shotgun_reloading or player._mekatana_attack.phase != "":
		reset_module_gesture()
		return
	_module_gesture_time += delta
	if player._counter.phase != "":
		var counter_phase: String = player._counter.phase
		var duration: float = player._counter.definition.preparation if counter_phase == "preparation" else player._counter.definition.guard_duration if counter_phase == "guard" else player._counter.definition.failure_recovery
		_module_pose("counter", "active" if counter_phase == "guard" else counter_phase, duration - player._counter.remaining, duration)
		return
	var stasis: float = player._stasis_remaining
	if player.survival_mode and player.survival_evolution_effects != null:
		stasis = maxf(stasis, float(player.survival_evolution_effects.shield_remaining))
	if stasis > 0.0:
		var elapsed := maxf(0.0, player._static_duration - stasis)
		_module_pose("static_shield", "preparation" if elapsed < 0.12 else "active", elapsed if elapsed < 0.12 else 0.0, 0.12 if elapsed < 0.12 else 10.0)
		return
	if _module_gesture_id == "static_shield":
		reset_module_gesture()
		return
	if player._fulguro_phase != "":
		var duration: float = player._fulguro_preparation if player._fulguro_phase == "preparation" else player._fulguro_active_window if player._fulguro_phase == "active" else player._fulguro_recovery
		_module_pose("fulguro_punch", player._fulguro_phase, player._fulguro_elapsed, duration)
		return
	if player._pelto_phase != "":
		var duration: float = player._pelto_preparation if player._pelto_phase == "preparation" else player._pelto_impact_duration if player._pelto_phase == "impact" else player._pelto_recovery
		_module_pose("pelto_smash", "active" if player._pelto_phase == "impact" else player._pelto_phase, player._pelto_elapsed, duration)
		return
	if player._javelin_charging:
		_module_pose("javelin", "preparation", player._javelin_elapsed, player._javelin_preparation)
		return
	if player._dash_active:
		_module_pose("pyro_boots", "active", player._dash_elapsed, float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.pyro_boots.dash_duration))
		return
	if player.is_eclipse_aiming():
		if _module_gesture_id != "eclipse":
			_module_gesture_id = "eclipse"
			_module_gesture_accepted = false
			_module_gesture_time = 0.0
		_module_pose("eclipse", "preparation", _module_gesture_time, 0.18)
		return
	if player.is_eclipse_travelling():
		player._visual_rig.clear_module_pose()
		return
	if _module_gesture_id.is_empty():
		player._visual_rig.clear_module_pose()
		return
	if _module_gesture_id == "eclipse" and not _module_gesture_accepted:
		reset_module_gesture()
		return
	if _module_gesture_id in ["fulguro_punch", "pelto_smash", "counter"]:
		reset_module_gesture()
		return
	if _module_gesture_id == "javelin" and not _module_release_confirmed:
		reset_module_gesture()
		return
	if _module_gesture_id == "bio_injector":
		if player._bio_remaining <= 0.0:
			reset_module_gesture()
		elif _module_gesture_time < 0.12:
			_module_pose("bio_injector", "preparation", _module_gesture_time, 0.12)
		else:
			_follow_module_release(delta)
		return
	if _module_gesture_id == "projector" and player._projector_cast_remaining > 0.0:
		var duration: float = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.projector.cast_duration
		_module_pose("projector", "preparation", duration - player._projector_cast_remaining, duration)
		return
	if _module_gesture_id in ["rocket_basket", "magnetic_field", "permutation"]:
		var duration: float = player._magnetic_preparation if _module_gesture_id == "magnetic_field" else PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS[_module_gesture_id].preparation
		if player._active_module_id == _module_gesture_id:
			_module_pose(_module_gesture_id, "preparation", _module_gesture_time, duration)
			return
	if _module_gesture_id in ["rocket_basket", "magnetic_field", "permutation", "projector"] and not _module_release_confirmed:
		reset_module_gesture()
		return
	_follow_module_release(delta)


func _follow_module_release(delta: float) -> void:
	_module_release_time = 0.0 if _module_release_time < 0.0 else _module_release_time + delta
	if _module_release_time < 0.12:
		_module_pose(_module_gesture_id, "active", _module_release_time, 0.12)
	elif _module_release_time < 0.34:
		_module_pose(_module_gesture_id, "recovery", _module_release_time - 0.12, 0.22)
	else:
		reset_module_gesture()


func _world_offset_to_visual_local(world_offset: Vector3) -> Vector3:
	if player._visual_rig == null:
		return world_offset
	return player._visual_rig.global_basis.inverse() * world_offset


func _update_weapon_ambient_motion(delta: float) -> void:
	player._weapon_motion_clock += delta
	if player._has_skeletal_weapon_attachment():
		# Both equipped weapons follow the animated hand, including recovery.
		if player._blaster_sway_pivot != null:
			player._blaster_sway_pivot.transform = Transform3D.IDENTITY
		if player._blaster_recoil_pivot != null:
			player._blaster_recoil_pivot.transform = Transform3D.IDENTITY
		if player._shotgun_sway_pivot != null:
			player._shotgun_sway_pivot.transform = Transform3D.IDENTITY
		if player._shotgun_recoil_pivot != null:
			player._shotgun_recoil_pivot.transform = Transform3D.IDENTITY
	elif player._weapon_id == "blaster" and player._blaster_sway_pivot != null and not player._blaster_attack_busy and not player._blaster_charge_active and not player._is_weapon_recoil_running(player._blaster_recoil_tweens):
		var blaster_sway := sin(player._weapon_motion_clock * 2.4) * 0.018
		var blaster_transform := Transform3D.IDENTITY
		blaster_transform.origin += Vector3(0.0, blaster_sway, sin(player._weapon_motion_clock * 1.7) * 0.014)
		blaster_transform.basis = blaster_transform.basis * Basis.from_euler(Vector3(0.0, sin(player._weapon_motion_clock * 1.9) * 0.025, sin(player._weapon_motion_clock * 2.2) * 0.018))
		player._blaster_sway_pivot.transform = blaster_transform
	if not player._has_skeletal_weapon_attachment() and player._weapon_id == "shotgun" and player._shotgun_sway_pivot != null and not player._shotgun_attack_busy and not player._shotgun_reloading:
		var shotgun_sway := sin(player._weapon_motion_clock * 2.0 + 0.8) * 0.014
		var shotgun_transform := Transform3D.IDENTITY
		shotgun_transform.origin += Vector3(0.0, shotgun_sway, sin(player._weapon_motion_clock * 1.4) * 0.018)
		shotgun_transform.basis = shotgun_transform.basis * Basis.from_euler(Vector3(0.0, sin(player._weapon_motion_clock * 1.8) * 0.018, sin(player._weapon_motion_clock * 2.1) * 0.014))
		player._shotgun_sway_pivot.transform = shotgun_transform


func flash_impact(critical: bool = false) -> void:
	if player._robot_visuals == null:
		return
	var vfx: Node = player._vfx_manager()
	if vfx != null:
		vfx.call("hit_flash", player._robot_visuals, critical)
	player._camera_impulse(0.09 if critical else 0.045, 0.065 if critical else 0.025)


func _clear_player_impact_material(_unused: float = 0.0) -> void:
	if player._player_body_material != null:
		player._player_body_material.emission_enabled = false


func _update_baroud_presentation() -> void:
	if player._baroud_bar_bg == null or player._baroud_bar_fill == null or player.passive_state == null:
		return
	var visible: bool = bool(player.passive_state.baroud_active)
	player._baroud_bar_bg.visible = visible
	player._baroud_bar_fill.visible = visible
	if not visible:
		return
	var fraction: float = clampf(float(player.passive_state.baroud_health) / maxf(1.0, float(player.passive_state.baroud_max_health)), 0.0, 1.0)
	var width: float = 1.8 * fraction
	player._baroud_bar_fill.scale = Vector3(width, 1.0, 1.0)
	player._baroud_bar_fill.position.x = -0.9 + width * 0.5


func _update_world_ui_anchor() -> void:
	if player._world_ui_anchor != null:
		# Keep the world-space UI above the robot while ignoring the player's aim
		# yaw, recoil and attack animation transforms.
		player._world_ui_anchor.global_position = player.global_position


func _sync_weapon_readout() -> void:
	if player._health_readout == null:
		return
	player._health_readout.call("set_shotgun_ammo", player._weapon_id == "shotgun", player._shotgun_ammo, player._shotgun_magazine_size, player._shotgun_reloading, player.get_shotgun_reload_progress())
	player._health_readout.call("set_blaster_charge", player._weapon_id == "blaster", player._blaster_charge_active, player.get_blaster_charge_ratio())
	if player._health_readout.has_method("set_longshot_cycle"):
		player._health_readout.call("set_longshot_cycle", player._weapon_id == "longshot", player.get_longshot_cycle_count(), player.is_longshot_enhanced_ready())
	if player._longshot_visual != null:
		player._longshot_visual.call("set_cycle", player.get_longshot_cycle_count(), player.is_longshot_enhanced_ready())


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.85
	player.add_child(collision)


func _register_locomotion_node(node: Node3D, role: String, phase: float = 0.0) -> void:
	if node == null:
		return
	node.set_meta("locomotion_role", role)
	node.set_meta("locomotion_phase", phase)
	node.set_meta("locomotion_base_position", node.position)
	node.set_meta("locomotion_base_rotation", node.rotation)
	player._locomotion_nodes.append(node)


func _play_player_animation(animation_name: StringName, blend_time: float = 0.16, speed_scale: float = 1.0) -> bool:
	if player._visual_rig == null:
		return false
	return player._visual_rig.play_action(animation_name, blend_time, speed_scale)


func react_to_damage(amount: float) -> void:
	if amount <= 0.0 or not player._gameplay_enabled or player.get_health() <= 0.0 or player.is_real_dead() or not player.passive_authoritative():
		return
	if player._visual_rig == null or player._visual_rig.presence_modifier == null or player._visual_rig._active_action != &"":
		return
	if player._stasis_remaining > 0.0 or player.is_eclipse_travelling():
		return
	player._visual_rig.presence_modifier.react_to_hit()


func _has_nearby_threat() -> bool:
	for target in player._fulguro_targets():
		if not is_instance_valid(target) or not target is Node3D or not target.has_method("get_health") or float(target.call("get_health")) <= 0.0:
			continue
		if player.global_position.distance_squared_to(target.global_position) > 64.0:
			continue
		if not target.has_method("is_visible_to") or bool(target.call("is_visible_to", player)):
			return true
	return false


func _has_skeletal_weapon_attachment() -> bool:
	return player._visual_rig != null and player._visual_rig.skeleton != null and player._visual_rig.right_hand_attachment != null


func _update_aim_pose_state(immediate: bool = false) -> void:
	if player._visual_rig != null:
		var punch_pose := player._fulguro_phase != "" or player._pelto_phase != "" or player._mekatana_attack.is_busy()
		player._visual_rig.set_aim_enabled(player._gameplay_enabled and not player.is_real_dead() and (punch_pose or (player._weapon_id in ["blaster", "shotgun", "longshot"] and player._weapon_pose_uses_aim())), immediate)


func _start_round_warmup_animation() -> void:
	player._round_warmup_active = player._play_player_animation(&"warm_up", 0.18)
	if not player._round_warmup_active:
		player._update_player_animation()


func _update_player_animation() -> void:
	if player._visual_rig == null or not player._gameplay_enabled or player.is_real_dead():
		return
	if player._round_warmup_active:
		return
	player._visual_rig.update_locomotion_state(player._get_actual_move_velocity().length(), player.move_speed)


func _on_player_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"fire" and player.weapon_pose_state == PLAYER_STATE.WeaponPoseState.FIRE:
		player._begin_aim_hold()
	if animation_name == &"warm_up":
		player._round_warmup_active = false
	if animation_name == &"warm_up":
		player._update_player_animation()


func _attach_weapon_pivot_to_hand(pivot: Node3D, weapon_id: StringName, desired_position: Vector3, desired_rotation: Vector3, carry_pitch_degrees: float = 0.0) -> Transform3D:
	if pivot == null:
		return Transform3D.IDENTITY
	if player._visual_rig == null or player._visual_rig.skeleton == null or player._visual_rig.right_hand_attachment == null:
		player._robot_visuals.add_child(pivot)
		pivot.position = desired_position
		pivot.rotation = desired_rotation
		return pivot.transform
	player._visual_rig.equip_weapon(weapon_id, pivot, {
		"position": desired_position,
		"rotation": desired_rotation,
		"scale": Vector3.ONE,
		"carry_pitch_degrees": carry_pitch_degrees,
	})
	return pivot.transform


func _build_robot() -> void:
	player._visual_rig = PlayerVisualRig.new()
	player._visual_rig.name = "VisualRoot"
	# Apply the shared presentation multiplier exactly once at the visual root so
	# the skeleton, weapon attachments, accessories and muzzle markers stay one rig.
	player._visual_rig.scale = Vector3.ONE * PLAYER_STATE.PLAYER_BASE_VISUAL_SCALE * PLAYER_STATE.COMBAT_DATA.CHARACTER_VISUAL_SCALE
	player.add_child(player._visual_rig)
	player._visual_rig.configure_aim_transition(player.aim_raise_time, player.aim_lower_time)
	var visuals := player._visual_rig.setup_visual_motion()
	player._robot_visuals = visuals
	preload("res://scripts/robot_surface_polish.gd").add_contact(visuals)
	player._world_ui_anchor = Node3D.new()
	player._world_ui_anchor.name = "WorldUIAnchor"
	player._world_ui_anchor.top_level = true
	player.add_child(player._world_ui_anchor)
	player._update_world_ui_anchor()

	player._attack_label = Label3D.new()
	player._attack_label.position = Vector3(0.0, 4.15 * PLAYER_STATE.COMBAT_DATA.CHARACTER_VISUAL_SCALE, 0.0)
	player._attack_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player._attack_label.font_size = 26
	player._attack_label.outline_size = 6
	player._attack_label.modulate = Color("#8beaff")
	player._world_ui_anchor.add_child(player._attack_label)

	player._health_readout = Node3D.new()
	player._health_readout.name = "PlayerHealthReadout"
	player._health_readout.set_script(PLAYER_STATE.COMBAT_READOUT)
	player._world_ui_anchor.add_child(player._health_readout)
	# The plaque keeps its original size; only its anchor rises with the model.
	player._health_readout.position.y = PLAYER_STATE.HEALTH_READOUT_BASE_HEIGHT * (PLAYER_STATE.COMBAT_DATA.CHARACTER_VISUAL_SCALE - 1.0)
	player._health_readout.call("configure", Color("#42d9e5"), "JOUEUR", -1.0)
	player._on_health_changed(player.get_health(), player.get_max_health())
	player._sync_weapon_readout()
	player._bush_status_label = Label3D.new()
	player._bush_status_label.name = "BushStatus"
	player._bush_status_label.position = Vector3(0.0, 4.30 * PLAYER_STATE.COMBAT_DATA.CHARACTER_VISUAL_SCALE, 0.0)
	player._bush_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player._bush_status_label.font_size = 28
	player._bush_status_label.pixel_size = 0.009
	player._bush_status_label.outline_size = 4
	player._bush_status_label.no_depth_test = true
	player._bush_status_label.visible = false
	player._world_ui_anchor.add_child(player._bush_status_label)

	player._baroud_bar_bg = MeshInstance3D.new()
	var baroud_bg_mesh := BoxMesh.new()
	baroud_bg_mesh.size = Vector3(1.8, 0.14, 0.06)
	player._baroud_bar_bg.mesh = baroud_bg_mesh
	player._baroud_bar_bg.position = Vector3(0.0, 2.52 * PLAYER_STATE.COMBAT_DATA.CHARACTER_VISUAL_SCALE, 0.0)
	player._baroud_bar_bg.material_override = player._material(Color("#2a1820"), 0.2, Color("#3a1824"))
	player._world_ui_anchor.add_child(player._baroud_bar_bg)
	player._baroud_bar_fill = MeshInstance3D.new()
	var baroud_fill_mesh := BoxMesh.new()
	baroud_fill_mesh.size = Vector3(1.0, 0.10, 0.07)
	player._baroud_bar_fill.mesh = baroud_fill_mesh
	player._baroud_bar_fill.position = Vector3(-0.45, 2.52 * PLAYER_STATE.COMBAT_DATA.CHARACTER_VISUAL_SCALE, -0.01)
	player._baroud_bar_fill.material_override = player._material(Color("#ef5a6f"), 0.1, Color("#ff4e7a"))
	player._world_ui_anchor.add_child(player._baroud_bar_fill)
	player._baroud_bar_bg.visible = false
	player._baroud_bar_fill.visible = false

	var selection_ring := MeshInstance3D.new()
	selection_ring.name = "PlayerSelectionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.895
	ring_mesh.outer_radius = 0.93
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 8
	selection_ring.mesh = ring_mesh
	selection_ring.position.y = 0.045
	var ring_material: StandardMaterial3D = player._material(Color("#65c2ccd9"), 0.8)
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_ring.material_override = ring_material
	selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visuals.add_child(selection_ring)
	var procedural_body := Node3D.new()
	procedural_body.name = "ProceduralRobot"
	visuals.add_child(procedural_body)

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.25
	body.mesh = body_mesh
	body.position.y = 0.8
	body.material_override = player._robot_textured_material(Color.WHITE, 0.78, PLAYER_STATE.ROBOT_CREAM_TEXTURE)
	player._player_body_material = body.material_override as StandardMaterial3D
	procedural_body.add_child(body)
	player._register_locomotion_node(body, "body")

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.48
	head_mesh.height = 0.85
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.55, 0.0)
	head.material_override = player._robot_textured_material(Color.WHITE, 0.72, PLAYER_STATE.ROBOT_CREAM_TEXTURE)
	procedural_body.add_child(head)
	player._register_locomotion_node(head, "head")

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.18
	eye_mesh.height = 0.26
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 1.58, -0.42)
	eye.scale = Vector3(1.2, 0.75, 0.45)
	eye.material_override = player._material(Color("#4ee8ff"), 0.25, Color("#21cfff"))
	procedural_body.add_child(eye)

	var chest_plate := MeshInstance3D.new()
	var chest_mesh := BoxMesh.new()
	chest_mesh.size = Vector3(0.72, 0.48, 0.14)
	chest_plate.mesh = chest_mesh
	chest_plate.position = Vector3(0.0, 0.88, -0.52)
	chest_plate.rotation_degrees.x = -7.0
	chest_plate.material_override = player._robot_textured_material(Color.WHITE, 0.70, PLAYER_STATE.ROBOT_RUST_TEXTURE)
	procedural_body.add_child(chest_plate)
	player._register_locomotion_node(chest_plate, "body")
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.19
	core_mesh.height = 0.28
	core.mesh = core_mesh
	core.position = Vector3(0.0, 0.90, -0.61)
	core.scale = Vector3(1.35, 0.72, 0.48)
	core.material_override = player._material(Color("#49e8f1"), 0.16, Color("#22d8e8"))
	player._player_core_material = core.material_override as StandardMaterial3D
	procedural_body.add_child(core)
	player._register_locomotion_node(core, "body")
	player._add_robot_arm(procedural_body, -1.0)
	player._add_robot_arm(procedural_body, 1.0)
	player._add_robot_leg(procedural_body, -1.0)
	player._add_robot_leg(procedural_body, 1.0)
	player._add_robot_backpack(procedural_body)
	if player._visual_rig.install_animated_model(procedural_body, 2.0):
		player._player_body_material = null
		player._visual_rig.action_finished.connect(player._on_player_animation_finished)
	player._blaster_pivot = Node3D.new()
	player._blaster_pivot.name = "BlasterPivot"
	player._blaster_sway_pivot = Node3D.new()
	player._blaster_sway_pivot.name = "WeaponSway"
	player._blaster_pivot.add_child(player._blaster_sway_pivot)
	player._blaster_recoil_pivot = Node3D.new()
	player._blaster_recoil_pivot.name = "WeaponRecoil"
	player._blaster_sway_pivot.add_child(player._blaster_recoil_pivot)
	var procedural_blaster_visual := Node3D.new()
	procedural_blaster_visual.name = "ProceduralBlasterFallback"
	player._blaster_recoil_pivot.add_child(procedural_blaster_visual)
	var blaster_grip := MeshInstance3D.new()
	var blaster_grip_mesh := BoxMesh.new()
	blaster_grip_mesh.size = Vector3(0.30, 0.34, 0.55)
	blaster_grip.mesh = blaster_grip_mesh
	blaster_grip.position = Vector3(0.0, -0.12, 0.22)
	blaster_grip.rotation_degrees.x = -12.0
	blaster_grip.material_override = player._robot_textured_material(Color.WHITE, 0.82, PLAYER_STATE.ROBOT_STEEL_TEXTURE)
	procedural_blaster_visual.add_child(blaster_grip)
	var blaster_receiver := MeshInstance3D.new()
	var blaster_receiver_mesh := BoxMesh.new()
	blaster_receiver_mesh.size = Vector3(0.52, 0.42, 0.72)
	blaster_receiver.mesh = blaster_receiver_mesh
	blaster_receiver.position = Vector3(0.0, 0.06, -0.16)
	blaster_receiver.material_override = player._robot_textured_material(Color.WHITE, 0.74, PLAYER_STATE.ROBOT_RUST_TEXTURE)
	procedural_blaster_visual.add_child(blaster_receiver)
	var blaster_barrel := MeshInstance3D.new()
	var blaster_barrel_mesh := CylinderMesh.new()
	blaster_barrel_mesh.top_radius = 0.10
	blaster_barrel_mesh.bottom_radius = 0.14
	blaster_barrel_mesh.height = 1.15
	blaster_barrel.mesh = blaster_barrel_mesh
	blaster_barrel.rotation_degrees.x = -90.0
	blaster_barrel.position = Vector3(0.0, 0.09, -0.92)
	blaster_barrel.material_override = player._robot_textured_material(Color.WHITE, 0.68, PLAYER_STATE.ROBOT_STEEL_TEXTURE)
	procedural_blaster_visual.add_child(blaster_barrel)
	var blaster_muzzle := MeshInstance3D.new()
	var blaster_muzzle_mesh := CylinderMesh.new()
	blaster_muzzle_mesh.top_radius = 0.18
	blaster_muzzle_mesh.bottom_radius = 0.11
	blaster_muzzle_mesh.height = 0.34
	blaster_muzzle.mesh = blaster_muzzle_mesh
	blaster_muzzle.rotation_degrees.x = -90.0
	blaster_muzzle.position = Vector3(0.0, 0.09, -1.58)
	blaster_muzzle.material_override = player._material(Color("#2f3a45"), 0.52, Color("#2ad9ff"))
	procedural_blaster_visual.add_child(blaster_muzzle)
	var blaster_muzzle_ring := MeshInstance3D.new()
	var blaster_muzzle_ring_mesh := TorusMesh.new()
	blaster_muzzle_ring_mesh.inner_radius = 0.12
	blaster_muzzle_ring_mesh.outer_radius = 0.19
	blaster_muzzle_ring.mesh = blaster_muzzle_ring_mesh
	blaster_muzzle_ring.rotation_degrees.x = 90.0
	blaster_muzzle_ring.position = Vector3(0.0, 0.09, -1.78)
	blaster_muzzle_ring.material_override = player._material(Color("#7cf0ff"), 0.22, Color("#2fe1ff"))
	procedural_blaster_visual.add_child(blaster_muzzle_ring)
	player._blaster_muzzle = Node3D.new()
	player._blaster_muzzle.name = "Muzzle"
	player._blaster_muzzle.set_meta("weapon_forward_axis", Vector3.FORWARD)
	player._blaster_muzzle.position = Vector3(0.0, 0.09, -1.86)
	player._blaster_recoil_pivot.add_child(player._blaster_muzzle)
	var blaster_left_hand_grip := Marker3D.new()
	blaster_left_hand_grip.name = "LeftHandGrip"
	blaster_left_hand_grip.position = Vector3(0.0, 0.06, -0.48)
	player._blaster_recoil_pivot.add_child(blaster_left_hand_grip)
	var blaster_right_hand_grip := Marker3D.new()
	blaster_right_hand_grip.name = "RightHandGrip"
	# This is the rear handle contact point, expressed in weapon-root space.
	# Keeping it explicit lets the socket seat the grip on the animated wrist.
	blaster_right_hand_grip.position = Vector3(0.0, -0.08, 0.08)
	player._blaster_recoil_pivot.add_child(blaster_right_hand_grip)
	player._blaster_charge_visual = PLAYER_STATE.BLASTER_CHARGE_VISUAL.new()
	player._blaster_charge_visual.name = "BlasterChargeGlow"
	player._blaster_charge_visual.position = Vector3(0.0, 0.0, 0.24)
	player._blaster_charge_visual.visible = false
	player._blaster_muzzle.add_child(player._blaster_charge_visual)
	player._blaster_light = OmniLight3D.new()
	player._blaster_light.name = "BlasterMuzzleLight"
	player._blaster_light.light_color = Color("#55eaff")
	player._blaster_light.light_energy = 0.0
	player._blaster_light.shadow_enabled = false
	player._blaster_light.omni_range = 3.5
	player._blaster_light.position = Vector3(0.0, 0.09, -1.62)
	player._blaster_recoil_pivot.add_child(player._blaster_light)
	if ResourceLoader.exists(PLAYER_STATE.HEAVY_BLASTER_MODEL_PATH):
		var heavy_blaster_scene := load(PLAYER_STATE.HEAVY_BLASTER_MODEL_PATH) as PackedScene
		if heavy_blaster_scene != null:
			var heavy_blaster_model := heavy_blaster_scene.instantiate() as Node3D
			if heavy_blaster_model != null:
				procedural_blaster_visual.visible = false
				var heavy_blaster_mount := Node3D.new()
				heavy_blaster_mount.name = "ImportedHeavyBlasterMount"
				heavy_blaster_mount.rotation.y = PI * 0.5
				heavy_blaster_mount.scale = Vector3.ONE * 1.35
				heavy_blaster_mount.position = Vector3(0.0, -0.14, -0.20)
				player._blaster_recoil_pivot.add_child(heavy_blaster_mount)
				heavy_blaster_model.name = "ImportedHeavyBlaster"
				heavy_blaster_mount.add_child(heavy_blaster_model)
				player._blaster_muzzle.position = Vector3(0.0, 0.08, -0.88)
				blaster_left_hand_grip.position = Vector3(-0.10, -0.04, -0.20)
				player._blaster_light.position = Vector3(0.0, 0.08, -0.86)
	player._blaster_pivot_home_transform = player._attach_weapon_pivot_to_hand(
		player._blaster_pivot,
		&"blaster",
		Vector3(0.58, 0.93, -0.42),
		Vector3.ZERO,
		-22.0
	)
	if player._has_skeletal_weapon_attachment():
		player._visual_rig.configure_left_hand_support(&"blaster")

	player._shotgun_pivot = Node3D.new()
	player._shotgun_pivot.name = "ShotgunPivot"
	player._shotgun_sway_pivot = Node3D.new()
	player._shotgun_sway_pivot.name = "WeaponSway"
	player._shotgun_pivot.add_child(player._shotgun_sway_pivot)
	player._shotgun_recoil_pivot = Node3D.new()
	player._shotgun_recoil_pivot.name = "WeaponRecoil"
	player._shotgun_sway_pivot.add_child(player._shotgun_recoil_pivot)
	var shotgun := PLAYER_STATE.SHOTGUN_SCENE.instantiate() as Node3D
	player._shotgun_recoil_pivot.add_child(shotgun)
	player._shotgun_muzzle = shotgun.get_node("Muzzle") as Node3D
	player._shotgun_light = shotgun.get_node("Muzzle/ShotgunMuzzleLight") as OmniLight3D
	player._shotgun_pivot_home_transform = player._attach_weapon_pivot_to_hand(
		player._shotgun_pivot,
		&"shotgun",
		Vector3(0.58, 0.88, -0.36),
		Vector3.ZERO,
		-22.0
	)
	player._create_longshot_visual()
	player._mekatana_pivot = PLAYER_STATE.MEKATANA_SCENE.instantiate() as Node3D
	player._attach_weapon_pivot_to_hand(player._mekatana_pivot, &"mekatana", Vector3(0.58, 0.93, -0.42), Vector3.ZERO, 0.0)
	player._update_weapon_visuals()

	var scarf := MeshInstance3D.new()
	var scarf_mesh := BoxMesh.new()
	scarf_mesh.size = Vector3(0.6, 0.08, 1.15)
	scarf.mesh = scarf_mesh
	scarf.position = Vector3(0.0, 1.2, 0.65)
	scarf.rotation_degrees.x = -18.0
	scarf.material_override = player._material(Color("#a62f25"), 0.9)
	procedural_body.add_child(scarf)
	player._create_player_direction_debug()
	player._visual_rig.set_chassis_appearance(player._robot_id)


func _update_weapon_visuals() -> void:
	if player._visual_rig != null:
		player._visual_rig.set_equipped_modules({
			"offensive": player._offensive_module_id, "defensive": player._defensive_module_id,
			"mobility": player._mobility_module_id, "passive": player.get_passive_id(),
		})
	if player._mekatana_pivot != null:
		player._mekatana_pivot.visible = player._weapon_id == "mekatana" and not player._pelto_weapon_hidden
	if player._longshot_pivot != null:
		player._longshot_pivot.visible = player._weapon_id == "longshot" and not player._pelto_weapon_hidden
	if player._axe_pivot != null:
		player._axe_pivot.visible = false
	if player._blaster_pivot != null:
		player._blaster_pivot.visible = player._weapon_id == "blaster" and not player._pelto_weapon_hidden
	if player._shotgun_pivot != null:
		player._shotgun_pivot.visible = player._weapon_id == "shotgun" and not player._pelto_weapon_hidden
	if player._has_skeletal_weapon_attachment():
		player._visual_rig._cancel_shot_kick()
		player._visual_rig.configure_left_hand_support(StringName(player._weapon_id))
	player._update_aim_pose_state()


func _create_player_direction_debug() -> void:
	player._direction_debug_enabled = player._direction_debug_enabled or player.enable_direction_debug
	player._direction_debug_geometry = ImmediateMesh.new()
	player._direction_debug_material = StandardMaterial3D.new()
	player._direction_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	player._direction_debug_material.vertex_color_use_as_albedo = true
	player._direction_debug_material.albedo_color = Color.WHITE
	player._direction_debug_mesh = MeshInstance3D.new()
	player._direction_debug_mesh.name = "PlayerDirectionDebug"
	player._direction_debug_mesh.mesh = player._direction_debug_geometry
	player._direction_debug_mesh.material_override = player._direction_debug_material
	player._direction_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player._direction_debug_mesh.visible = player._direction_debug_enabled
	player.add_child(player._direction_debug_mesh)
	player._direction_debug_label = Label3D.new()
	player._direction_debug_label.name = "MuzzleAimAngleDebug"
	player._direction_debug_label.position = Vector3(0.0, 2.8, 0.0)
	player._direction_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player._direction_debug_label.font_size = 28
	player._direction_debug_label.outline_size = 6
	player._direction_debug_label.no_depth_test = true
	player._direction_debug_label.visible = player._direction_debug_enabled
	player.add_child(player._direction_debug_label)
	if player._has_skeletal_weapon_attachment():
		# Read final modified bones/attachments, after aim support and ShotKick.
		player._visual_rig.skeleton.skeleton_updated.connect(player._update_player_debug_vectors)
	player._update_player_debug_vectors()


func _update_player_debug_vectors() -> void:
	if player._direction_debug_geometry == null or not player._direction_debug_enabled:
		return
	player._direction_debug_geometry.clear_surfaces()
	player._direction_debug_geometry.surface_begin(Mesh.PRIMITIVE_LINES, player._direction_debug_material)
	player._add_debug_direction_line(player.move_direction, Color("#38a8ff"), 1.8)
	player._add_debug_direction_line(player.aim_direction, Color("#ff4b45"), 2.0)
	player._add_debug_direction_line(player._last_projectile_direction, Color("#d05cff"), 2.25)
	if player._visual_rig != null:
		player._add_debug_direction_line(player._visual_rig.get_aim_forward_direction(), Color("#64e572"), 1.65)
		if player._visual_rig.right_hand_attachment != null:
			var hand_transform := player._visual_rig.right_hand_attachment.global_transform
			var hand_forward := -hand_transform.basis.z.normalized()
			player._add_debug_segment(hand_transform.origin, hand_transform.origin + hand_forward * 0.8, Color("#ffdc58"))
	var weapon := player._longshot_pivot if player._weapon_id == "longshot" else (player._blaster_pivot if player._weapon_id == "blaster" else player._shotgun_pivot)
	if weapon != null:
		var weapon_forward := -weapon.global_basis.z.normalized()
		player._add_debug_segment(weapon.global_position, weapon.global_position + weapon_forward * 1.2, Color.WHITE)
	var muzzle := player._longshot_muzzle if player._weapon_id == "longshot" else (player._blaster_muzzle if player._weapon_id == "blaster" else player._shotgun_muzzle)
	if muzzle != null:
		var muzzle_forward := player._visual_rig.get_weapon_forward_direction(StringName(player._weapon_id)) if player._visual_rig != null else -muzzle.global_basis.z.normalized()
		player._add_debug_segment(muzzle.global_position, muzzle.global_position + muzzle_forward * 1.0, Color("#48f3ed"))
		if player.aim_direction.length_squared() > 0.001:
			var angle := rad_to_deg(acos(clampf(muzzle_forward.dot(player.aim_direction.normalized()), -1.0, 1.0)))
			var projectile_angle := rad_to_deg(acos(clampf(player._last_projectile_direction.normalized().dot(player.aim_direction.normalized()), -1.0, 1.0))) if player._last_projectile_direction.length_squared() > 0.001 else 0.0
			player._direction_debug_label.text = "%s  •  Muzzle/Aim %.2f°  •  Projectile/Aim %.2f°" % [player.get_weapon_pose_state_name(), angle, projectile_angle]
		else:
			player._direction_debug_label.text = "Muzzle/Aim angle = —"
	player._direction_debug_geometry.surface_end()


func _add_debug_direction_line(direction: Vector3, color: Color, length: float) -> void:
	if direction.length_squared() <= 0.001:
		return
	player._add_debug_segment(player.global_position + Vector3.UP * 0.12, player.global_position + direction.normalized() * length + Vector3.UP * 0.12, color)


func _add_debug_segment(from_world: Vector3, to_world: Vector3, color: Color) -> void:
	player._direction_debug_geometry.surface_set_color(color)
	player._direction_debug_geometry.surface_add_vertex(player.to_local(from_world))
	player._direction_debug_geometry.surface_add_vertex(player.to_local(to_world))


func _add_robot_arm(parent: Node3D, side: float) -> void:
	var shoulder := MeshInstance3D.new()
	var shoulder_mesh := SphereMesh.new()
	shoulder_mesh.radius = 0.25
	shoulder_mesh.height = 0.42
	shoulder.mesh = shoulder_mesh
	shoulder.position = Vector3(side * 0.68, 1.05, 0.0)
	shoulder.material_override = player._robot_textured_material(Color.WHITE, 0.82, PLAYER_STATE.ROBOT_STEEL_TEXTURE)
	parent.add_child(shoulder)
	player._register_locomotion_node(shoulder, "body", 0.0 if side < 0.0 else PI)
	var upper := MeshInstance3D.new()
	var upper_mesh := CylinderMesh.new()
	upper_mesh.top_radius = 0.16
	upper_mesh.bottom_radius = 0.20
	upper_mesh.height = 0.58
	upper.mesh = upper_mesh
	upper.position = Vector3(side * 0.78, 0.78, 0.0)
	upper.rotation_degrees.z = side * -11.0
	upper.material_override = player._robot_textured_material(Color.WHITE, 0.82, PLAYER_STATE.ROBOT_CREAM_TEXTURE)
	parent.add_child(upper)
	player._register_locomotion_node(upper, "limb", 0.0 if side < 0.0 else PI)
	var forearm := MeshInstance3D.new()
	var forearm_mesh := BoxMesh.new()
	forearm_mesh.size = Vector3(0.30, 0.48, 0.34)
	forearm.mesh = forearm_mesh
	forearm.position = Vector3(side * 0.82, 0.43, -0.03)
	forearm.rotation_degrees.z = side * -18.0
	forearm.material_override = player._robot_textured_material(Color.WHITE, 0.84, PLAYER_STATE.ROBOT_RUST_TEXTURE)
	parent.add_child(forearm)
	player._register_locomotion_node(forearm, "limb", 0.0 if side < 0.0 else PI)
	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.17
	hand_mesh.height = 0.25
	hand.mesh = hand_mesh
	hand.position = Vector3(side * 0.84, 0.16, -0.08)
	hand.material_override = player._robot_textured_material(Color.WHITE, 0.90, PLAYER_STATE.ROBOT_STEEL_TEXTURE)
	parent.add_child(hand)
	player._register_locomotion_node(hand, "limb", 0.0 if side < 0.0 else PI)


func _add_robot_leg(parent: Node3D, side: float) -> void:
	var thigh := MeshInstance3D.new()
	var thigh_mesh := CapsuleMesh.new()
	thigh_mesh.radius = 0.20
	thigh_mesh.height = 0.62
	thigh.mesh = thigh_mesh
	thigh.position = Vector3(side * 0.31, 0.36, 0.02)
	thigh.rotation_degrees.z = side * 7.0
	thigh.material_override = player._robot_textured_material(Color.WHITE, 0.84, PLAYER_STATE.ROBOT_STEEL_TEXTURE)
	parent.add_child(thigh)
	player._register_locomotion_node(thigh, "limb", 0.0 if side < 0.0 else PI)
	var shin := MeshInstance3D.new()
	var shin_mesh := BoxMesh.new()
	shin_mesh.size = Vector3(0.28, 0.48, 0.34)
	shin.mesh = shin_mesh
	shin.position = Vector3(side * 0.33, 0.05, -0.04)
	shin.rotation_degrees.z = side * -4.0
	shin.material_override = player._robot_textured_material(Color.WHITE, 0.78, PLAYER_STATE.ROBOT_CREAM_TEXTURE)
	parent.add_child(shin)
	player._register_locomotion_node(shin, "limb", 0.0 if side < 0.0 else PI)
	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.40, 0.18, 0.62)
	foot.mesh = foot_mesh
	foot.position = Vector3(side * 0.33, -0.17, -0.17)
	foot.material_override = player._robot_textured_material(Color.WHITE, 0.90, PLAYER_STATE.ROBOT_RUST_TEXTURE)
	parent.add_child(foot)
	player._register_locomotion_node(foot, "limb", 0.0 if side < 0.0 else PI)


func _add_robot_backpack(parent: Node3D) -> void:
	var pack := MeshInstance3D.new()
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.66, 0.78, 0.34)
	pack.mesh = pack_mesh
	pack.position = Vector3(0.0, 1.02, 0.55)
	pack.rotation_degrees.x = -8.0
	pack.material_override = player._robot_textured_material(Color.WHITE, 0.86, PLAYER_STATE.ROBOT_RUST_TEXTURE)
	parent.add_child(pack)
	var coil := MeshInstance3D.new()
	var coil_mesh := TorusMesh.new()
	coil_mesh.inner_radius = 0.14
	coil_mesh.outer_radius = 0.20
	coil.mesh = coil_mesh
	coil.position = Vector3(0.0, 1.18, 0.76)
	coil.rotation_degrees.x = 90.0
	coil.material_override = player._material(Color("#52e5ed"), 0.30, Color("#2bd4df"))
	parent.add_child(coil)


func _material(color: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 3.0
	return material


func _robot_textured_material(color: Color, roughness: float, texture: Texture2D) -> StandardMaterial3D:
	var material: StandardMaterial3D = player._material(color, roughness)
	material.albedo_texture = texture
	material.uv1_scale = Vector3(1.1, 1.1, 1.1)
	material.metallic = 0.18 if texture == PLAYER_STATE.ROBOT_RUST_TEXTURE else (0.38 if texture == PLAYER_STATE.ROBOT_STEEL_TEXTURE else 0.04)
	return material
