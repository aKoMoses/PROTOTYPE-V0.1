extends Node3D
class_name PlayerVisualRig

signal action_finished(animation_name: StringName)

const PLAYER_MODEL_PATH := "res://art/player_mecha_animated.glb"
const LOWER_BODY_MODIFIER_SCRIPT := preload("res://scripts/player_lower_body_direction_modifier.gd")
const AIM_MODIFIER_SCRIPT := preload("res://scripts/player_aim_modifier.gd")
const MODEL_AXIS_CORRECTION_YAW := PI
const AIM_TURN_SPEED := 20.0
const LOCOMOTION_TURN_SPEED := 12.0
const MOVE_DEADZONE := 0.15
const DEFAULT_WEAPON_FORWARD_AXIS := Vector3.FORWARD
const LOCOMOTION_NODE_NAME := &"Locomotion"
const AIM_POSE_NAME := &"runtime/AimPose"
const READY_POSE_NAME := &"runtime/ReadyPose"
const READY_BLEND_NODE_NAME := &"UpperBodyReady"
const AIM_BLEND_NODE_NAME := &"UpperBodyAim"
const BASE_POSE_NODE_NAME := &"BasePose"
const LOWER_BODY_BLEND_NODE_NAME := &"LowerBodyBlend"
const AIM_BLEND_PARAMETER := "parameters/UpperBodyAim/blend_amount"
const READY_BLEND_PARAMETER := "parameters/UpperBodyReady/blend_amount"
const LOWER_BODY_BLEND_PARAMETER := "parameters/LowerBodyBlend/blend_amount"

var visual_motion: Node3D
var model_axis_correction: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var lower_body_modifier: PlayerLowerBodyDirectionModifier
var right_hand_attachment: BoneAttachment3D
var aim_blend: AnimationNodeBlend2
var ready_blend: AnimationNodeBlend2
var aim_modifier: PlayerAimModifier
var aim_pose_sample_time := 0.0
var aim_pose_stability_degrees := 0.0
var ready_pose_sample_time := 0.0
var aim_filtered_track_paths: Array[NodePath] = []
var ready_filtered_track_paths: Array[NodePath] = []
var _aim_requested := false
var _aim_blend_amount := 0.0
var _aim_raise_time := 0.10
var _aim_lower_time := 0.18
var _aim_hand_pose := Transform3D.IDENTITY
var lower_body_blend: AnimationNodeBlend2

var detected_animation_names: Array[StringName] = []
var detected_bone_names: Array[StringName] = []
var locomotion_filtered_track_paths: Array[NodePath] = []
var right_hand_bone_name: StringName = &""
var left_hand_bone_name: StringName = &""
var hips_bone_name: StringName = &""
var root_motion_bone_name: StringName = &""
var source_forward_axis := Vector3(0.0, 0.0, 1.0)

var _animation_states: Dictionary = {}
var _locomotion_reference_speeds: Dictionary = {}
var _playback: AnimationNodeStateMachinePlayback
var _locomotion_playback: AnimationNodeStateMachinePlayback
var _base_state_machine: AnimationNodeStateMachine
var _locomotion_state_machine: AnimationNodeStateMachine
var _fire_animation_name: StringName = &""
var _active_action: StringName = &""
var _current_locomotion: StringName = &""
var _locomotion_blend_amount := 0.0
var _right_hand_bone_index := -1
var _hips_bone_index := -1
var _spine_bone_index := -1
var _animation_library_names: Array[StringName] = []


func setup_visual_motion() -> Node3D:
	visual_motion = Node3D.new()
	visual_motion.name = "VisualMotion"
	add_child(visual_motion)
	return visual_motion


func install_animated_model(procedural_body: Node3D, model_scale: float = 2.0) -> bool:
	if not ResourceLoader.exists(PLAYER_MODEL_PATH):
		push_warning("GLB joueur absent ; le robot procédural reste actif.")
		return false
	var packed_model := load(PLAYER_MODEL_PATH) as PackedScene
	if packed_model == null:
		push_warning("Impossible de charger le GLB joueur ; le robot procédural reste actif.")
		return false
	var imported_root := packed_model.instantiate() as Node3D
	if imported_root == null:
		push_warning("La racine du GLB joueur n'est pas un Node3D.")
		return false
	if visual_motion == null:
		setup_visual_motion()
	model_axis_correction = Node3D.new()
	model_axis_correction.name = "ModelAxisCorrection"
	# Inspection du clip run : Hips avance en +Z. Cette unique correction convertit
	# l'avant du GLB vers le -Z de gameplay de Godot, sans toucher au CharacterBody3D.
	model_axis_correction.rotation.y = MODEL_AXIS_CORRECTION_YAW
	model_axis_correction.scale = Vector3.ONE * model_scale
	visual_motion.add_child(model_axis_correction)
	imported_root.name = "ImportedAnimatedModel"
	model_axis_correction.add_child(imported_root)
	skeleton = _find_skeleton(imported_root)
	animation_player = _find_animation_player(imported_root)
	if skeleton == null:
		push_warning("Le GLB joueur ne contient aucun Skeleton3D ; maintien du robot procédural.")
		model_axis_correction.queue_free()
		model_axis_correction = null
		return false
	if animation_player == null:
		push_warning("Le GLB joueur ne contient aucun AnimationPlayer ; modèle conservé sans animation.")
		if procedural_body != null:
			procedural_body.visible = false
		return true
	_collect_rig_metadata(imported_root)
	_duplicate_animation_libraries_for_runtime()
	_configure_locomotion_clips()
	_create_aim_pose()
	_create_ready_pose()
	_configure_hand_attachment()
	_configure_lower_body_modifier()
	_configure_aim_modifier()
	_configure_animation_tree(imported_root)
	# Evaluate the actual authored pose before creating ANY hand-local socket.
	animation_tree.set(AIM_BLEND_PARAMETER, 0.0)
	animation_tree.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	animation_tree.set(AIM_BLEND_PARAMETER, 1.0)
	animation_tree.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	aim_modifier.spine_basis = skeleton.get_bone_global_pose(_spine_bone_index).basis
	_aim_hand_pose = skeleton.get_bone_global_pose(_right_hand_bone_index)
	_refresh_aim_state()
	if procedural_body != null:
		procedural_body.visible = false
	print("[PlayerVisualRig] animations=%s | bones=%d | mesh=%d | right=%s | left=%s | hips=%s | forward=+Z | root_motion=Hips(run/walk)" % [
		", ".join(PackedStringArray(detected_animation_names)),
		detected_bone_names.size(),
		_count_meshes(imported_root),
		String(right_hand_bone_name),
		String(left_hand_bone_name),
		String(hips_bone_name)
	])
	return true


func update_visual_state(move_direction: Vector3, aim_direction: Vector3, horizontal_speed: float, max_speed: float, delta: float, allow_locomotion: bool = true) -> void:
	_update_aim_blend(delta)
	var combat_aim_active := _aim_requested and _active_action == &""
	var facing_direction := aim_direction if combat_aim_active else move_direction
	facing_direction.y = 0.0
	if facing_direction.length_squared() > 0.001:
		facing_direction = facing_direction.normalized()
		var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
		# Combat aim is exact. Outside combat, the body eases back toward travel.
		var turn_speed := AIM_TURN_SPEED if combat_aim_active else LOCOMOTION_TURN_SPEED
		var next_yaw := target_yaw if combat_aim_active else lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
		rotation = Vector3(0.0, next_yaw, 0.0)
	var local_move := global_basis.inverse() * move_direction
	local_move.y = 0.0
	if local_move.length_squared() > 0.001:
		local_move = local_move.normalized()
	var source_local_move := model_axis_correction.basis.inverse() * local_move if model_axis_correction != null else local_move
	if lower_body_modifier != null:
		lower_body_modifier.set_locomotion_direction(source_local_move, allow_locomotion and _active_action == "" and horizontal_speed > MOVE_DEADZONE)
	_update_locomotion(horizontal_speed if allow_locomotion else 0.0, max_speed, delta)


func play_action(animation_name: StringName, _blend_time: float = 0.16, speed_scale: float = 1.0) -> bool:
	var state_name := _find_state_name(animation_name)
	if state_name == &"fire":
		return play_shot_kick()
	if state_name == &"":
		if animation_player != null and animation_player.has_animation(animation_name):
			animation_player.play(animation_name, _blend_time, speed_scale)
			return true
		return false
	if state_name in [&"idle", &"walk", &"run"]:
		_cancel_shot_kick()
		_active_action = &""
		_refresh_aim_state()
		if _playback != null and _base_state_machine.has_node(&"idle"):
			_travel_to(&"idle")
		if state_name == &"idle":
			_current_locomotion = &""
			_set_locomotion_blend(0.0)
			return true
		if _locomotion_playback == null or not _locomotion_state_machine.has_node(state_name):
			return false
		_current_locomotion = state_name
		_set_state_speed(state_name, speed_scale)
		_travel_to_locomotion(state_name)
		_set_locomotion_blend(1.0, 0.016, true)
		return true
	if _base_state_machine == null or not _base_state_machine.has_node(state_name):
		return false
	_active_action = state_name
	_cancel_shot_kick()
	_refresh_aim_state()
	if lower_body_modifier != null:
		lower_body_modifier.set_locomotion_direction(Vector3.ZERO, false)
	_set_state_speed(state_name, speed_scale)
	_travel_to(state_name)
	_set_locomotion_blend(0.0, 0.016, true)
	return true


func equip_weapon(weapon_id: StringName, weapon_root: Node3D, profile: Dictionary) -> bool:
	if weapon_root == null:
		return false
	if right_hand_attachment == null or skeleton == null or _right_hand_bone_index < 0:
		push_warning("Attachement main droite indisponible ; arme conservée sur le fallback visuel.")
		if visual_motion != null and weapon_root.get_parent() == null:
			visual_motion.add_child(weapon_root)
		return false
	unequip_weapon(weapon_id)
	skeleton.force_update_all_bone_transforms()
	right_hand_attachment.force_update_transform()
	var socket := Node3D.new()
	socket.name = "WeaponSocket_%s" % String(weapon_id)
	right_hand_attachment.add_child(socket)
	var local_position: Vector3 = profile.get("position", Vector3.ZERO)
	var local_rotation: Vector3 = profile.get("rotation", Vector3.ZERO)
	var local_scale: Vector3 = profile.get("scale", Vector3.ONE)
	var carry_pitch_degrees: float = float(profile.get("carry_pitch_degrees", 0.0))
	var right_grip := weapon_root.find_child("RightHandGrip", true, false) as Node3D
	var right_grip_from_root := _descendant_transform_from(weapon_root, right_grip) if right_grip != null else Transform3D.IDENTITY
	socket.set_meta("weapon_alignment_profile", {
		"position": local_position,
		"rotation": local_rotation,
		"scale": local_scale,
		"carry_pitch_degrees": carry_pitch_degrees,
		"right_grip_from_root": right_grip_from_root,
	})
	var aim_transform := _get_weapon_socket_transform(local_position, local_rotation, local_scale, weapon_id, right_grip_from_root.origin, right_grip != null)
	var carry_rotation := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(carry_pitch_degrees)), Vector3.ZERO)
	var grip_pivot := Transform3D(Basis.IDENTITY, right_grip_from_root.origin)
	socket.set_meta("weapon_aim_transform", aim_transform)
	# Lower the weapon around its rear grip, rather than around the imported scene
	# origin, so the handle cannot peel away from the hand in the ready pose.
	socket.set_meta("weapon_carry_transform", aim_transform * grip_pivot * carry_rotation * grip_pivot.affine_inverse())
	socket.transform = _get_weapon_socket_pose(socket)
	weapon_root.name = "Weapon_%s" % String(weapon_id)
	weapon_root.transform = Transform3D.IDENTITY
	socket.add_child(weapon_root)
	weapon_root.set_meta("weapon_profile_id", weapon_id)
	return true


func unequip_weapon(weapon_id: StringName) -> void:
	if right_hand_attachment == null:
		return
	var socket := right_hand_attachment.get_node_or_null("WeaponSocket_%s" % String(weapon_id))
	if socket != null:
		socket.queue_free()


func get_weapon_socket(weapon_id: StringName) -> Node3D:
	if right_hand_attachment == null:
		return null
	return right_hand_attachment.get_node_or_null("WeaponSocket_%s" % String(weapon_id)) as Node3D


func get_animation_state() -> StringName:
	if _active_action == "" and _locomotion_blend_amount > 0.5 and _locomotion_playback != null:
		return _locomotion_playback.get_current_node()
	if _playback != null:
		return _playback.get_current_node()
	return &""


func get_animation_speed_for_duration(animation_name: StringName, target_duration: float) -> float:
	var state_name := _find_state_name(animation_name)
	if state_name == &"" or target_duration <= 0.0:
		return 1.0
	var clip_path: StringName = _animation_states.get(state_name, &"")
	var clip := animation_player.get_animation(clip_path) if animation_player != null else null
	return clampf(clip.length / target_duration, 0.35, 6.0) if clip != null else 1.0


func is_shot_kick_active() -> bool:
	return aim_modifier != null and aim_modifier.is_shot_active()


func set_fulguro_pose(phase: String, progress: float) -> void:
	if aim_modifier != null:
		aim_modifier.set_fulguro_pose(phase, progress)
	_aim_requested = true
	_refresh_aim_state()


func clear_fulguro_pose() -> void:
	if aim_modifier != null:
		aim_modifier.clear_fulguro_pose()


func set_pelto_pose(phase: String, progress: float) -> void:
	if aim_modifier != null:
		aim_modifier.set_pelto_pose(phase, progress)
	_aim_requested = true
	_refresh_aim_state()


func clear_pelto_pose() -> void:
	if aim_modifier != null:
		aim_modifier.clear_pelto_pose()


func settle_weapon_attachment_after_transient_pose() -> void:
	# Transient ability modifiers are cleared during Player._process(), after the
	# skeleton may already have evaluated their last pose. Re-evaluate once while
	# the weapon is still hidden so its BoneAttachment cannot be revealed at the
	# stale Pelto hand position.
	_update_weapon_socket_poses()
	if animation_tree != null:
		animation_tree.advance(0.000001)
	if skeleton != null:
		skeleton.advance(0.000001)
		skeleton.force_update_all_bone_transforms()
	if right_hand_attachment != null:
		right_hand_attachment.force_update_transform()


func configure_aim_transition(raise_time: float, lower_time: float) -> void:
	_aim_raise_time = maxf(0.001, raise_time)
	_aim_lower_time = maxf(0.001, lower_time)


func set_aim_enabled(enabled: bool, immediate: bool = false) -> void:
	_aim_requested = enabled
	if immediate:
		_aim_blend_amount = 1.0 if enabled else 0.0
		_update_weapon_socket_poses()
	_refresh_aim_state()


func _refresh_aim_state() -> void:
	var enabled := _aim_requested and _active_action == &""
	if animation_tree != null and ready_blend != null:
		animation_tree.set(READY_BLEND_PARAMETER, 1.0 if _active_action == &"" else 0.0)
	if animation_tree != null and aim_blend != null:
		# Keep the current weight while lowering; full-body actions alone bypass it.
		animation_tree.set(AIM_BLEND_PARAMETER, _aim_blend_amount if _active_action == &"" else 0.0)
	if aim_modifier != null:
		aim_modifier.aiming = enabled
		if not enabled:
			aim_modifier.cancel_shot()


func _update_aim_blend(delta: float) -> void:
	var enabled := _aim_requested and _active_action == &""
	var target := 1.0 if enabled else 0.0
	var duration := _aim_raise_time if target > _aim_blend_amount else _aim_lower_time
	_aim_blend_amount = move_toward(_aim_blend_amount, target, maxf(delta, 0.0) / duration)
	_update_weapon_socket_poses()
	if animation_tree != null and aim_blend != null:
		animation_tree.set(AIM_BLEND_PARAMETER, _aim_blend_amount if _active_action == &"" else 0.0)


func _get_weapon_socket_pose(socket: Node3D) -> Transform3D:
	var aim_transform: Transform3D = socket.get_meta("weapon_aim_transform", socket.transform)
	var carry_transform: Transform3D = socket.get_meta("weapon_carry_transform", aim_transform)
	var pose := carry_transform.interpolate_with(aim_transform, _aim_blend_amount)
	var profile: Dictionary = socket.get_meta("weapon_alignment_profile", {})
	var right_grip_from_root: Transform3D = profile.get("right_grip_from_root", Transform3D.IDENTITY)
	# Transform interpolation blends translation and rotation independently. Pin the
	# common pivot again so the rear grip also remains exact while raising/lowering.
	var grip_position := right_grip_from_root.origin
	var grip_anchor := aim_transform * grip_position
	pose.origin += grip_anchor - pose * grip_position
	return pose


func _update_weapon_socket_poses() -> void:
	if right_hand_attachment == null:
		return
	for child in right_hand_attachment.get_children():
		var socket := child as Node3D
		if socket == null or not socket.has_meta("weapon_aim_transform"):
			continue
		socket.transform = _get_weapon_socket_pose(socket)


func is_aim_pose_committed() -> bool:
	return _aim_requested and _active_action == &"" and _aim_blend_amount >= 0.999


func commit_firing_pose(direction: Vector3) -> void:
	# A very short tap may release before the raise blend completes. Snap only at
	# actual emission so muzzle, flash and projectile still share the same axis.
	_aim_requested = true
	_aim_blend_amount = 1.0
	_update_weapon_socket_poses()
	var flat_direction := direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.001:
		flat_direction = flat_direction.normalized()
		rotation.y = atan2(-flat_direction.x, -flat_direction.z)
	_refresh_aim_state()
	if animation_tree != null:
		animation_tree.advance(0.0)
	if skeleton != null:
		# Evaluate eagerly where the callback mode allows it. Player still waits for
		# skeleton_updated when a shot began below full aim, which is the hard
		# guarantee that BoneAttachment3D is current before projectile emission.
		skeleton.advance(0.000001)
		skeleton.force_update_all_bone_transforms()
	if right_hand_attachment != null:
		right_hand_attachment.force_update_transform()


func get_weapon_muzzle(weapon_id: StringName) -> Node3D:
	var socket := get_weapon_socket(weapon_id)
	if socket == null:
		return null
	var weapon_root := socket.get_node_or_null("Weapon_%s" % String(weapon_id))
	if weapon_root == null:
		return null
	var muzzle := weapon_root.find_child("MuzzlePoint", true, false) as Node3D
	return muzzle if muzzle != null else weapon_root.find_child("Muzzle", true, false) as Node3D


func get_weapon_forward_direction(weapon_id: StringName) -> Vector3:
	var muzzle := get_weapon_muzzle(weapon_id)
	if muzzle == null:
		return get_aim_forward_direction()
	var local_forward: Vector3 = muzzle.get_meta("weapon_forward_axis", DEFAULT_WEAPON_FORWARD_AXIS)
	var forward := muzzle.global_basis * local_forward
	return forward.normalized() if forward.length_squared() > 0.001 else get_aim_forward_direction()


func get_aim_forward_direction() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)


func get_source_forward_direction() -> Vector3:
	if model_axis_correction == null:
		return get_aim_forward_direction()
	var forward := global_basis * model_axis_correction.basis * source_forward_axis
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else get_aim_forward_direction()


func get_right_hand_bone_index() -> int:
	return _right_hand_bone_index


func update_locomotion_state(horizontal_speed: float, max_speed: float, delta: float = 0.016) -> void:
	_update_locomotion(horizontal_speed, max_speed, delta)


func _update_locomotion(horizontal_speed: float, max_speed: float, delta: float = 0.016) -> void:
	if animation_tree == null or _locomotion_playback == null:
		return
	if _active_action != "":
		_set_locomotion_blend(0.0, delta)
		return
	var speed := maxf(horizontal_speed, 0.0)
	if speed <= MOVE_DEADZONE:
		_current_locomotion = &""
		_set_locomotion_blend(0.0, delta)
		return
	var state := _choose_locomotion_state(speed, max_speed)
	if state == &"" or state == &"idle" or not _locomotion_state_machine.has_node(state):
		_set_locomotion_blend(0.0, delta)
		return
	var reference_speed := float(_locomotion_reference_speeds.get(state, max_speed))
	var time_scale := clampf(speed / maxf(reference_speed, 0.1), 0.55, 1.5)
	_set_state_speed(state, time_scale)
	if state != _current_locomotion or _locomotion_playback.get_current_node() != state:
		_current_locomotion = state
		_travel_to_locomotion(state)
	_set_locomotion_blend(1.0, delta)


func _set_locomotion_blend(target: float, delta: float = 0.016, immediate: bool = false) -> void:
	if animation_tree == null:
		return
	if immediate:
		_locomotion_blend_amount = target
		animation_tree.set(LOWER_BODY_BLEND_PARAMETER, target)
		return
	var transition_rate := 9.0 if target > _locomotion_blend_amount else 12.0
	_locomotion_blend_amount = move_toward(_locomotion_blend_amount, target, maxf(delta, 0.001) * transition_rate)
	animation_tree.set(LOWER_BODY_BLEND_PARAMETER, _locomotion_blend_amount)


func _choose_locomotion_state(speed: float, max_speed: float) -> StringName:
	if speed <= MOVE_DEADZONE:
		if &"idle" in _animation_states:
			return &"idle"
		if &"walk" in _animation_states:
			return &"walk"
		return &"run" if &"run" in _animation_states else &""
	var use_walk := speed < maxf(max_speed * 0.48, 0.9)
	if use_walk and &"walk" in _animation_states:
		return &"walk"
	if &"run" in _animation_states:
		return &"run"
	if &"walk" in _animation_states:
		return &"walk"
	return &"idle" if &"idle" in _animation_states else &""


func _configure_animation_tree(model_root: Node3D) -> void:
	_base_state_machine = AnimationNodeStateMachine.new()
	_locomotion_state_machine = AnimationNodeStateMachine.new()
	var base_index := 0
	var locomotion_index := 0
	for animation_name in animation_player.get_animation_list():
		var state_name := _canonical_animation_name(animation_name)
		if state_name == &"" or state_name in [&"aimpose", &"readypose"] or state_name in _animation_states:
			continue
		_animation_states[state_name] = animation_name
		if state_name == &"fire":
			_fire_animation_name = animation_name
			continue
		if state_name in [&"walk", &"run"]:
			_locomotion_state_machine.add_node(state_name, _make_scaled_animation_state(animation_name), Vector2(float(locomotion_index) * 240.0, 80.0))
			locomotion_index += 1
		else:
			var animation_node := AnimationNodeAnimation.new()
			animation_node.animation = animation_name
			var state_node: AnimationNode = _make_scaled_animation_state(animation_name) if state_name in [&"idle", &"warm_up", &"fall"] else animation_node
			_base_state_machine.add_node(state_name, state_node, Vector2(float(base_index % 3) * 240.0, float(base_index / 3) * 120.0))
			base_index += 1
	if base_index == 0:
		return
	_add_state_machine_transitions(_base_state_machine)
	if locomotion_index > 0:
		_add_state_machine_transitions(_locomotion_state_machine)
	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node(BASE_POSE_NODE_NAME, _base_state_machine, Vector2(0.0, 0.0))
	if locomotion_index > 0:
		blend_tree.add_node(LOCOMOTION_NODE_NAME, _locomotion_state_machine, Vector2(0.0, 220.0))
		lower_body_blend = AnimationNodeBlend2.new()
		# Full-body locomotion gives the unalerted character a natural carried-weapon
		# run. The filtered AimPose above it replaces only torso/arms during combat,
		# so legs continue the same walk/run phase while firing.
		lower_body_blend.filter_enabled = false
		for animation_name in animation_player.get_animation_list():
			if _canonical_animation_name(animation_name) not in [&"walk", &"run"]:
				continue
			for track_path in _collect_lower_body_track_paths(animation_name):
				if track_path not in locomotion_filtered_track_paths:
					locomotion_filtered_track_paths.append(track_path)
		for track_path in locomotion_filtered_track_paths:
			lower_body_blend.set_filter_path(track_path, true)
		blend_tree.add_node(LOWER_BODY_BLEND_NODE_NAME, lower_body_blend, Vector2(280.0, 80.0))
		blend_tree.connect_node(LOWER_BODY_BLEND_NODE_NAME, 0, BASE_POSE_NODE_NAME)
		blend_tree.connect_node(LOWER_BODY_BLEND_NODE_NAME, 1, LOCOMOTION_NODE_NAME)
		blend_tree.set_node_position(&"output", Vector2(960.0, 80.0))
	else:
		blend_tree.connect_node(&"output", 0, BASE_POSE_NODE_NAME)
	if _fire_animation_name != &"":
		var ready_input_name: StringName = LOWER_BODY_BLEND_NODE_NAME if locomotion_index > 0 else BASE_POSE_NODE_NAME
		if animation_player.has_animation(READY_POSE_NAME):
			var ready_clip := AnimationNodeAnimation.new()
			ready_clip.animation = READY_POSE_NAME
			blend_tree.add_node(&"ReadyPose", ready_clip, Vector2(280.0, 420.0))
			ready_blend = AnimationNodeBlend2.new()
			ready_blend.filter_enabled = true
			for track_path in ready_filtered_track_paths:
				ready_blend.set_filter_path(track_path, true)
			blend_tree.add_node(READY_BLEND_NODE_NAME, ready_blend, Vector2(520.0, 80.0))
			blend_tree.connect_node(READY_BLEND_NODE_NAME, 0, ready_input_name)
			blend_tree.connect_node(READY_BLEND_NODE_NAME, 1, &"ReadyPose")
			ready_input_name = READY_BLEND_NODE_NAME
		var aim_clip := AnimationNodeAnimation.new()
		aim_clip.animation = AIM_POSE_NAME
		blend_tree.add_node(&"AimPose", aim_clip, Vector2(0.0, 420.0))
		aim_blend = AnimationNodeBlend2.new()
		aim_blend.filter_enabled = true
		for track_path in aim_filtered_track_paths:
			aim_blend.set_filter_path(track_path, true)
		blend_tree.add_node(AIM_BLEND_NODE_NAME, aim_blend, Vector2(760.0, 80.0))
		blend_tree.connect_node(AIM_BLEND_NODE_NAME, 0, ready_input_name)
		blend_tree.connect_node(AIM_BLEND_NODE_NAME, 1, &"AimPose")
		blend_tree.connect_node(&"output", 0, AIM_BLEND_NODE_NAME)
	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.tree_root = blend_tree
	model_root.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.root_node = NodePath("..")
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animation_tree.animation_finished.connect(_on_animation_finished)
	animation_tree.active = true
	_playback = animation_tree.get("parameters/BasePose/playback") as AnimationNodeStateMachinePlayback
	_locomotion_playback = animation_tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	var initial_base_state: StringName = &"idle" if _base_state_machine.has_node(&"idle") else _base_state_machine.get_node_list()[0]
	if _playback != null and initial_base_state != "":
		_playback.start(initial_base_state)
	var initial_locomotion_state: StringName = &"run" if _locomotion_state_machine.has_node(&"run") else (&"walk" if _locomotion_state_machine.has_node(&"walk") else &"")
	if _locomotion_playback != null and initial_locomotion_state != "":
		_locomotion_playback.start(initial_locomotion_state)
		_current_locomotion = initial_locomotion_state
	_locomotion_blend_amount = 0.0
	if lower_body_blend != null:
		animation_tree.set(LOWER_BODY_BLEND_PARAMETER, 0.0)
	if ready_blend != null:
		animation_tree.set(READY_BLEND_PARAMETER, 1.0)
	print("[PlayerAnimationTree] BasePose + full-body locomotion + low-ready arms + transient upper-body AimPose + skeleton ShotKick/support | locomotion_tracks=%d ready_tracks=%d aim_tracks=%d samples=%.6f/%.6fs" % [locomotion_filtered_track_paths.size(), ready_filtered_track_paths.size(), aim_filtered_track_paths.size(), ready_pose_sample_time, aim_pose_sample_time])


func _add_state_machine_transitions(state_machine: AnimationNodeStateMachine) -> void:
	var state_names := state_machine.get_node_list()
	for from_state in state_names:
		if from_state in [&"Start", &"End"]:
			continue
		for to_state in state_names:
			if from_state == to_state or to_state in [&"Start", &"End"]:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			transition.xfade_time = 0.12
			state_machine.add_transition(from_state, to_state, transition)


func play_shot_kick(charge_ratio: float = 0.0) -> bool:
	if aim_modifier == null or not aim_modifier.aiming:
		return false
	aim_modifier.trigger_shot(charge_ratio)
	return true


func _cancel_shot_kick() -> void:
	if aim_modifier != null:
		aim_modifier.cancel_shot()


func _get_weapon_socket_transform(local_position: Vector3, local_rotation: Vector3, local_scale: Vector3, weapon_id: StringName, right_grip_position: Vector3 = Vector3.ZERO, has_right_grip: bool = false) -> Transform3D:
	var desired_basis := Basis.from_euler(local_rotation).scaled(local_scale)
	# Always calibrate against the cached, evaluated AimPose, even if equipped mid-kick.
	var hand_pose := _aim_hand_pose
	var hand_world := skeleton.global_transform * hand_pose
	var desired_world := visual_motion.global_transform * Transform3D(desired_basis, local_position)
	if weapon_id == &"blaster":
		# Production weapons expose an authored rear-grip marker. Keep the legacy
		# offset only for minimal fixtures or third-party weapons without one.
		desired_world.origin = hand_world.origin
		if not has_right_grip:
			desired_world.origin += visual_motion.global_basis * Vector3(0.0, 0.08, -0.08)
	elif weapon_id == &"shotgun":
		# Anchor the authored rear-grip marker to the wrist instead of assuming the
		# imported mesh origin is the contact point. This keeps the stock and grip
		# seated in the hand while preserving the calibrated firing direction.
		desired_world.origin = hand_world.origin
	desired_world.origin -= desired_world.basis * right_grip_position
	return hand_world.affine_inverse() * desired_world


func _descendant_transform_from(ancestor: Node3D, descendant: Node3D) -> Transform3D:
	if ancestor == null or descendant == null:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	var current := descendant
	while current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
		if current == null:
			return Transform3D.IDENTITY
	return result


func configure_left_hand_support(weapon_id: StringName) -> void:
	if aim_modifier == null:
		return
	aim_modifier.support_enabled = false
	aim_modifier.support_use_orientation = false
	aim_modifier.grip_from_hand = Transform3D.IDENTITY
	var socket := get_weapon_socket(weapon_id)
	var weapon := socket.get_node_or_null("Weapon_%s" % String(weapon_id)) if socket != null else null
	var grip := weapon.find_child("LeftHandGrip", true, false) as Node3D if weapon != null else null
	if grip == null:
		return
	var grip_local := Transform3D.IDENTITY
	var node: Node3D = grip
	while node != right_hand_attachment:
		var node_transform := node.transform
		# Support is only solved while aiming. If the weapon was equipped in its
		# lowered carry pose, cache the grip against the canonical firing socket
		# rather than against that temporary carry rotation.
		if node.get_parent() == right_hand_attachment and node.has_meta("weapon_aim_transform"):
			node_transform = node.get_meta("weapon_aim_transform", node_transform)
		grip_local = node_transform * grip_local
		node = node.get_parent() as Node3D
	aim_modifier.grip_from_hand = grip_local
	aim_modifier.support_use_orientation = bool(grip.get_meta("orient_hand", false))
	aim_modifier.support_enabled = true


func _collect_upper_body_track_paths(animation_name: StringName) -> Array[NodePath]:
	var result: Array[NodePath] = []
	if animation_player == null or skeleton == null or _spine_bone_index < 0:
		return result
	var animation := animation_player.get_animation(animation_name)
	if animation == null:
		return result
	for track_index in range(animation.get_track_count()):
		var track_path := animation.track_get_path(track_index)
		var path_text := str(track_path)
		var separator := path_text.rfind(":")
		if separator < 0:
			continue
		var bone_index := skeleton.find_bone(StringName(path_text.substr(separator + 1)))
		if bone_index >= 0 and _is_bone_descendant_of(bone_index, _spine_bone_index):
			result.append(track_path)
	return result


func _is_bone_descendant_of(bone_index: int, ancestor_index: int) -> bool:
	var current_index := bone_index
	while current_index >= 0:
		if current_index == ancestor_index:
			return true
		current_index = skeleton.get_bone_parent(current_index)
	return false


func _collect_lower_body_track_paths(animation_name: StringName) -> Array[NodePath]:
	var result: Array[NodePath] = []
	if animation_player == null or skeleton == null or _hips_bone_index < 0:
		return result
	var animation := animation_player.get_animation(animation_name)
	if animation == null:
		return result
	for track_index in range(animation.get_track_count()):
		var track_path := animation.track_get_path(track_index)
		var path_text := str(track_path)
		var separator := path_text.rfind(":")
		if separator < 0:
			continue
		var bone_index := skeleton.find_bone(StringName(path_text.substr(separator + 1)))
		if bone_index < 0 or not _is_bone_descendant_of(bone_index, _hips_bone_index):
			continue
		if _spine_bone_index >= 0 and _is_bone_descendant_of(bone_index, _spine_bone_index):
			continue
		result.append(track_path)
	return result


func _make_scaled_animation_state(animation_name: StringName) -> AnimationNodeBlendTree:
	var state_tree := AnimationNodeBlendTree.new()
	var clip := AnimationNodeAnimation.new()
	clip.animation = animation_name
	var time_scale := AnimationNodeTimeScale.new()
	state_tree.add_node("Animation", clip, Vector2.ZERO)
	state_tree.add_node("TimeScale", time_scale, Vector2(220.0, 0.0))
	state_tree.connect_node("TimeScale", 0, "Animation")
	state_tree.connect_node("output", 0, "TimeScale")
	return state_tree


func _configure_locomotion_clips() -> void:
	if animation_player == null:
		return
	for animation_name in animation_player.get_animation_list():
		var state_name := _canonical_animation_name(animation_name)
		var animation := animation_player.get_animation(animation_name)
		if animation == null:
			continue
		if state_name in [&"idle", &"walk", &"run"]:
			animation.loop_mode = Animation.LOOP_LINEAR
		if state_name in [&"fire", &"fall", &"warm_up", &"bow", &"box_01", &"afraid"]:
			animation.loop_mode = Animation.LOOP_NONE
		if state_name in [&"walk", &"run"]:
			var travel_speed := _measure_root_travel_speed(animation)
			_make_locomotion_animation_in_place(animation)
			if travel_speed > 0.05:
				_locomotion_reference_speeds[state_name] = travel_speed * _get_model_world_scale()


func _create_ready_pose() -> void:
	var source_name: StringName = &""
	for preferred_state in [&"run", &"walk"]:
		for animation_name in animation_player.get_animation_list():
			if _canonical_animation_name(animation_name) == preferred_state:
				source_name = animation_name
				break
		if source_name != &"":
			break
	if source_name == &"":
		return
	var source := animation_player.get_animation(source_name)
	var upper_paths := _collect_upper_body_track_paths(source_name)
	# This phase has both arms beside the body in the authored run cycle. Freezing
	# only the arm rotations gives a stable one-handed carry while the pelvis,
	# legs and torso retain their complete locomotion animation.
	ready_pose_sample_time = minf(0.30, source.length * 0.5)
	var pose := Animation.new()
	pose.length = 1.0
	pose.loop_mode = Animation.LOOP_LINEAR
	for source_track in range(source.get_track_count()):
		var path := source.track_get_path(source_track)
		if source.track_get_type(source_track) != Animation.TYPE_ROTATION_3D or path not in upper_paths:
			continue
		var bone_name := _normalize_bone_name(StringName(str(path).get_slice(":", 1)))
		if not bone_name.begins_with("right") and not bone_name.begins_with("left"):
			continue
		var track := pose.add_track(Animation.TYPE_ROTATION_3D)
		pose.track_set_path(track, path)
		var rotation_value := source.rotation_track_interpolate(source_track, ready_pose_sample_time)
		pose.rotation_track_insert_key(track, 0.0, rotation_value)
		pose.rotation_track_insert_key(track, pose.length, rotation_value)
		ready_filtered_track_paths.append(path)
	var library := animation_player.get_animation_library(&"runtime")
	if library == null:
		library = AnimationLibrary.new()
		animation_player.add_animation_library(&"runtime", library)
	library.add_animation(&"ReadyPose", pose)
	print("[ReadyPose] %s sample=%.6fs frame=%d arm_rotation_tracks=%d" % [source_name, ready_pose_sample_time, roundi(ready_pose_sample_time * 60.0), ready_filtered_track_paths.size()])


func _create_aim_pose() -> void:
	for animation_name in animation_player.get_animation_list():
		if _canonical_animation_name(animation_name) == &"fire":
			_fire_animation_name = animation_name
			break
	if _fire_animation_name == &"":
		return
	var source := animation_player.get_animation(_fire_animation_name)
	var upper_paths := _collect_upper_body_track_paths(_fire_animation_name)
	var measured_bones := ["spine", "spine1", "spine2", "neck", "head", "rightshoulder", "rightarm", "rightforearm", "righthand", "leftshoulder", "leftarm", "leftforearm", "lefthand"]
	var measured_tracks: Array[int] = []
	for track in range(source.get_track_count()):
		var path := source.track_get_path(track)
		if source.track_get_type(track) != Animation.TYPE_ROTATION_3D or path not in upper_paths:
			continue
		if _normalize_bone_name(StringName(str(path).get_slice(":", 1))) in measured_bones:
			measured_tracks.append(track)
	# Compare equal 100 ms windows, excluding endpoints which would otherwise
	# receive an unfair half-window. Earliest minimum wins deterministically.
	var best_score := INF
	var half_window := minf(0.05, source.length * 0.25)
	for frame in range(int(ceil(half_window * 60.0)), int(floor((source.length - half_window) * 60.0 + 0.0001)) + 1):
		var candidate := float(frame) / 60.0
		var sum_squared := 0.0
		for track in measured_tracks:
			var before := source.rotation_track_interpolate(track, candidate - half_window)
			var after := source.rotation_track_interpolate(track, candidate + half_window)
			var difference := before.inverse() * after
			# atan2 retains precision for sub-degree quaternion differences.
			var angle := 2.0 * atan2(Vector3(difference.x, difference.y, difference.z).length(), absf(difference.w))
			sum_squared += pow(angle / (2.0 * half_window), 2.0)
		var score := sqrt(sum_squared / maxf(1.0, measured_tracks.size()))
		if score < best_score:
			best_score = score
			aim_pose_sample_time = candidate
	aim_pose_stability_degrees = rad_to_deg(best_score)
	var pose := Animation.new()
	pose.length = 1.0
	pose.loop_mode = Animation.LOOP_LINEAR
	for source_track in range(source.get_track_count()):
		var path := source.track_get_path(source_track)
		if source.track_get_type(source_track) != Animation.TYPE_ROTATION_3D or path not in upper_paths:
			continue
		var track := pose.add_track(Animation.TYPE_ROTATION_3D)
		pose.track_set_path(track, path)
		var rotation_value := source.rotation_track_interpolate(source_track, aim_pose_sample_time)
		pose.rotation_track_insert_key(track, 0.0, rotation_value)
		pose.rotation_track_insert_key(track, pose.length, rotation_value)
		aim_filtered_track_paths.append(path)
	var library := AnimationLibrary.new()
	library.add_animation(&"AimPose", pose)
	animation_player.add_animation_library(&"runtime", library)
	print("[AimPose] fire sample=%.6fs frame=%d RMS=%.6fdeg/s rotation_tracks=%d" % [aim_pose_sample_time, roundi(aim_pose_sample_time * 60.0), aim_pose_stability_degrees, aim_filtered_track_paths.size()])


func _configure_aim_modifier() -> void:
	aim_modifier = AIM_MODIFIER_SCRIPT.new() as PlayerAimModifier
	aim_modifier.name = "AimPoseShotKickSupport"
	aim_modifier.spine_index = _spine_bone_index
	aim_modifier.right_hand_index = _right_hand_bone_index
	var bone_fields := {"hips": "hips_index", "leftupleg": "left_up_leg_index", "rightupleg": "right_up_leg_index", "spine2": "spine2_index", "rightshoulder": "right_shoulder_index", "rightarm": "right_arm_index", "rightforearm": "right_forearm_index", "leftarm": "left_arm_index", "leftforearm": "left_forearm_index", "lefthand": "left_hand_index"}
	for index in range(skeleton.get_bone_count()):
		var normalized := _normalize_bone_name(skeleton.get_bone_name(index))
		if normalized in bone_fields:
			aim_modifier.set(bone_fields[normalized], index)
	skeleton.add_child(aim_modifier)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	aim_modifier.shot_finished.connect(func(): action_finished.emit(&"fire"))


func _measure_root_travel_speed(animation: Animation) -> float:
	if _hips_bone_index < 0:
		return 0.0
	for track_index in range(animation.get_track_count()):
		var track_path := str(animation.track_get_path(track_index)).to_lower()
		if not (track_path.contains("hips") or track_path.contains("pelvis")):
			continue
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 2 or animation.length <= 0.0:
			continue
		var first: Variant = animation.track_get_key_value(track_index, 0)
		var last: Variant = animation.track_get_key_value(track_index, key_count - 1)
		if typeof(first) != TYPE_VECTOR3 or typeof(last) != TYPE_VECTOR3:
			continue
		var flat_delta: Vector3 = last - first
		flat_delta.y = 0.0
		return flat_delta.length() / animation.length
	return 0.0


func _make_locomotion_animation_in_place(animation: Animation) -> void:
	if skeleton == null or _hips_bone_index < 0:
		return
	var hips_rest_position := skeleton.get_bone_rest(_hips_bone_index).origin
	for track_index in range(animation.get_track_count()):
		var track_path := str(animation.track_get_path(track_index)).to_lower()
		if not (track_path.contains("hips") or track_path.contains("pelvis")):
			continue
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		for key_index in range(animation.track_get_key_count(track_index)):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if typeof(value) != TYPE_VECTOR3:
				continue
			var in_place: Vector3 = value
			# Pin horizontal root motion to the actual bind/rest origin, not the
			# first animation key (run starts ~45 cm away from rest in this GLB).
			in_place.x = hips_rest_position.x
			in_place.z = hips_rest_position.z
			animation.track_set_key_value(track_index, key_index, in_place)


func _duplicate_animation_libraries_for_runtime() -> void:
	_animation_library_names = animation_player.get_animation_library_list()
	for library_name in _animation_library_names:
		var source_library := animation_player.get_animation_library(library_name)
		if source_library == null:
			continue
		var runtime_library := source_library.duplicate(true) as AnimationLibrary
		if runtime_library == null:
			continue
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, runtime_library)
	for animation_path in animation_player.get_animation_list():
		var canonical := _canonical_animation_name(animation_path)
		if canonical != "":
			detected_animation_names.append(canonical)


func _configure_hand_attachment() -> void:
	if skeleton == null:
		return
	_right_hand_bone_index = _find_hand_bone(true)
	if _right_hand_bone_index < 0:
		push_warning("Aucun bone de main droite détecté dans le GLB ; vérifie son squelette.")
		return
	right_hand_bone_name = skeleton.get_bone_name(_right_hand_bone_index)
	right_hand_attachment = BoneAttachment3D.new()
	right_hand_attachment.name = "BoneAttachment3D_RightHand"
	right_hand_attachment.bone_name = right_hand_bone_name
	skeleton.add_child(right_hand_attachment)


func _configure_lower_body_modifier() -> void:
	if skeleton == null or _hips_bone_index < 0 or _spine_bone_index < 0:
		return
	lower_body_modifier = LOWER_BODY_MODIFIER_SCRIPT.new() as PlayerLowerBodyDirectionModifier
	lower_body_modifier.name = "MoveAimLegsModifier"
	lower_body_modifier.configure(_hips_bone_index, _spine_bone_index)
	skeleton.add_child(lower_body_modifier)


func _collect_rig_metadata(root: Node) -> void:
	detected_bone_names.clear()
	for bone_index in range(skeleton.get_bone_count()):
		var bone_name := skeleton.get_bone_name(bone_index)
		detected_bone_names.append(bone_name)
		var normalized := _normalize_bone_name(bone_name)
		if hips_bone_name == "" and (normalized == "hips" or normalized == "pelvis"):
			_hips_bone_index = bone_index
			hips_bone_name = bone_name
		if _spine_bone_index < 0 and (normalized == "spine" or normalized == "spine1"):
			_spine_bone_index = bone_index
		if left_hand_bone_name == "" and _is_hand_name(normalized, false):
			left_hand_bone_name = bone_name
		if right_hand_bone_name == "" and _is_hand_name(normalized, true):
			_right_hand_bone_index = bone_index
			right_hand_bone_name = bone_name
	root_motion_bone_name = hips_bone_name
	if hips_bone_name == "":
		push_warning("Aucun bone Hips/Pelvis n'a été trouvé ; root motion visuel non neutralisé.")


func _find_hand_bone(right_hand: bool) -> int:
	var best_index := -1
	var best_score := 0
	for bone_index in range(skeleton.get_bone_count()):
		var normalized := _normalize_bone_name(skeleton.get_bone_name(bone_index))
		if not _is_hand_name(normalized, right_hand):
			continue
		var score := 1
		if normalized == ("righthand" if right_hand else "lefthand"):
			score = 100
		elif normalized == ("handr" if right_hand else "handl") or normalized == ("rhand" if right_hand else "lhand"):
			score = 80
		elif normalized.contains("right") or normalized.contains("left"):
			score = 50
		if score > best_score:
			best_score = score
			best_index = bone_index
	return best_index


func _is_hand_name(normalized: String, right_hand: bool) -> bool:
	if not normalized.contains("hand"):
		return false
	if normalized.contains("index") or normalized.contains("middle") or normalized.contains("pinky") or normalized.contains("ring") or normalized.contains("thumb"):
		return false
	if right_hand:
		return normalized.contains("right") or normalized.ends_with("handr") or normalized.begins_with("rhand")
	return normalized.contains("left") or normalized.ends_with("handl") or normalized.begins_with("lhand")


func _normalize_bone_name(bone_name: StringName) -> String:
	var name := String(bone_name).to_lower().replace(":", "_")
	var parts := name.split("_", false)
	if parts.size() > 1 and parts[0].begins_with("mixamorig"):
		parts.remove_at(0)
		name = "_".join(parts)
	return name.replace("_", "").replace(".", "").replace(" ", "")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _canonical_animation_name(animation_path: StringName) -> StringName:
	var parts := String(animation_path).to_lower().split("/", false)
	var name: String = parts[parts.size() - 1] if not parts.is_empty() else ""
	return StringName(name.replace(" ", "_").replace("-", "_"))


func _find_state_name(animation_name: StringName) -> StringName:
	var canonical := _canonical_animation_name(animation_name)
	return canonical if canonical in _animation_states else &""


func _travel_to(state_name: StringName) -> void:
	if _playback != null and state_name != "" and _playback.get_current_node() != state_name:
		_playback.travel(state_name)


func _travel_to_locomotion(state_name: StringName) -> void:
	if _locomotion_playback != null and state_name != "" and _locomotion_playback.get_current_node() != state_name:
		_locomotion_playback.travel(state_name)


func _set_state_speed(state_name: StringName, speed_scale: float) -> void:
	if animation_tree == null or not (state_name in [&"idle", &"walk", &"run", &"fire", &"warm_up", &"fall"]):
		return
	var node_name := LOCOMOTION_NODE_NAME if state_name in [&"walk", &"run"] else BASE_POSE_NODE_NAME
	var parameter_path := "parameters/%s/%s/TimeScale/scale" % [String(node_name), String(state_name)]
	if animation_tree.get(parameter_path) != null:
		animation_tree.set(parameter_path, clampf(speed_scale, 0.35, 1.6))


func _on_animation_finished(animation_path: StringName) -> void:
	var state_name := _find_state_name(animation_path)
	if state_name == &"fire":
		action_finished.emit(state_name)
		return
	if state_name == &"" or state_name != _active_action:
		return
	_active_action = &""
	_refresh_aim_state()
	if state_name != &"fall" and _playback != null and _base_state_machine.has_node(&"idle"):
		_travel_to(&"idle")
	action_finished.emit(state_name)


func _get_model_world_scale() -> float:
	var rig_scale := global_transform.basis.get_scale().x
	return absf(rig_scale * float(model_axis_correction.scale.x)) if model_axis_correction != null else absf(rig_scale)
