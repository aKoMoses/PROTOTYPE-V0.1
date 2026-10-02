extends Node3D
class_name EnemyDroidVisual

## Presentation only. TargetDummy/TrainingBot own health, collision and movement.
## One manual AnimationTree evaluation, then a single pose solve, then sockets.
const MODEL_PATH := "res://art/enemy_droid.glb"
const WEAPON_PATH := "res://art/player_heavy_blaster.glb"
const POSE_SOLVER := preload("res://scripts/enemy_droid_pose.gd")
const SHOTGUN_SCENE := preload("res://scenes/weapons/shotgun.tscn")
const MEKATANA_SCENE := preload("res://scenes/weapons/mekatana.tscn")
const LONGSHOT_SCENE := preload("res://scenes/weapons/longshot.tscn")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const MODEL_SCALE := 1.9
const WEAPON_SCALE := 0.75
const AIM_SAMPLE := 1.45
const EXPECTED_CLIPS := [&"turn", &"idle", &"warm_up", &"walk", &"wait", &"look_around", &"cast_a_spell", &"run", &"fall", &"fire"]
const WALK_SPEED := 0.713336 * MODEL_SCALE * COMBAT_DATA.CHARACTER_VISUAL_SCALE
const RUN_SPEED := 2.599736 * MODEL_SCALE * COMBAT_DATA.CHARACTER_VISUAL_SCALE

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var hand_attachment: BoneAttachment3D
var weapon_socket: Node3D
var muzzle: Marker3D
var support_grip: Marker3D
var model_axis: Node3D
var pose_solver
var animation_state: StringName = &"idle"
var aim_weight := 0.0
var dead := false
var left_grip_error := 0.0
var locomotion_speed := 0.0
var locomotion_rate := 1.0
var leg_yaw := 0.0
var _playback: AnimationNodeStateMachinePlayback
var _right_hand := -1
var _spine := -1
var _hips := -1
var _aim_spine := Basis.IDENTITY
var _aim_point := Vector3.ZERO
var _shot_clock := 10.0
var _hit_clock := 10.0
var _hit_strength := 1.0
var _ambient_clock := 0.0
var _ambient_index := 0
var _death_clock := 0.0
var _preview := false
var _ready_ok := false
var weapon_id := "blaster"
var _weapon_hand_pose := Transform3D.IDENTITY
var _mekatana_weapon: Node3D
var _mekatana_phase := ""
var _mekatana_direction := Vector3.ZERO


func setup() -> bool:
	# This root is the single presentation scale boundary. Its origin remains at
	# ground level; skeleton, hand socket, weapon and muzzle all inherit it once.
	scale = Vector3.ONE * COMBAT_DATA.CHARACTER_VISUAL_SCALE
	var packed := load(MODEL_PATH) as PackedScene
	var blaster := load(WEAPON_PATH) as PackedScene
	if packed == null or blaster == null:
		push_error("Enemy droid: model or blaster missing")
		return false
	model_axis = Node3D.new()
	model_axis.name = "ModelAxisCorrection"
	model_axis.rotation.y = PI # Inspected anatomical forward +Z -> Godot -Z.
	model_axis.scale = Vector3.ONE * MODEL_SCALE
	add_child(model_axis)
	var model := packed.instantiate() as Node3D
	model.name = "DroidGLB"
	model_axis.add_child(model)
	preload("res://scripts/robot_surface_polish.gd").apply(model)
	preload("res://scripts/robot_surface_polish.gd").add_contact(self)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or animation_player == null:
		push_error("Enemy droid: inspected skeleton/AnimationPlayer unavailable")
		return false
	_right_hand = skeleton.find_bone("mixamorig_RightHand")
	_spine = skeleton.find_bone("mixamorig_Spine")
	_hips = skeleton.find_bone("mixamorig_Hips")
	if mini(_right_hand, mini(_spine, _hips)) < 0:
		push_error("Enemy droid: required bones unavailable")
		return false
	for clip in EXPECTED_CLIPS:
		if not animation_player.has_animation(clip):
			push_error("Enemy droid: missing inspected clip %s" % clip)
			return false
	_prepare_clips()
	# Calibrate once from the ACTUAL authored firing pose, before the tree owns it.
	animation_player.play(&"fire")
	animation_player.seek(AIM_SAMPLE, true)
	skeleton.force_update_all_bone_transforms()
	_aim_spine = skeleton.get_bone_global_pose(_spine).basis.orthonormalized()
	_weapon_hand_pose = skeleton.get_bone_global_pose(_right_hand)
	_build_weapon_socket()
	animation_player.stop(true)
	_build_tree(model)
	pose_solver = POSE_SOLVER.new()
	set_weapon("blaster")
	_ready_ok = true
	reset_visual()
	return true


func _prepare_clips() -> void:
	# Never edit shared imported animations: two bots must remain independent.
	for library_name in animation_player.get_animation_library_list():
		var library := animation_player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, library)
	var rest_origin := skeleton.get_bone_rest(_hips).origin
	for name in EXPECTED_CLIPS:
		var clip := animation_player.get_animation(name)
		clip.loop_mode = Animation.LOOP_LINEAR if name in [&"idle", &"wait", &"walk", &"run"] else Animation.LOOP_NONE
		for track in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or not str(clip.track_get_path(track)).ends_with(":mixamorig_Hips"):
				continue
			var first: Vector3 = clip.track_get_key_value(track, 0)
			for key in clip.track_get_key_count(track):
				var position_value: Vector3 = clip.track_get_key_value(track, key)
				if name == &"fall":
					# Preserve the authored collapse, relative to the actor's start.
					position_value.x += rest_origin.x - first.x
					position_value.z += rest_origin.z - first.z
				else:
					position_value.x = rest_origin.x
					position_value.z = rest_origin.z
				clip.track_set_key_value(track, key, position_value)
		if name in [&"walk", &"run"]:
			_close_cycle(clip)
	var fire := animation_player.get_animation(&"fire")
	var pose := Animation.new()
	pose.length = 1.0
	pose.loop_mode = Animation.LOOP_LINEAR
	for source_track in fire.get_track_count():
		var type := fire.track_get_type(source_track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var track := pose.add_track(type)
		pose.track_set_path(track, fire.track_get_path(source_track))
		var value: Variant
		match type:
			Animation.TYPE_POSITION_3D: value = fire.position_track_interpolate(source_track, AIM_SAMPLE)
			Animation.TYPE_ROTATION_3D: value = fire.rotation_track_interpolate(source_track, AIM_SAMPLE)
			Animation.TYPE_SCALE_3D: value = fire.scale_track_interpolate(source_track, AIM_SAMPLE)
		pose.track_insert_key(track, 0.0, value)
		pose.track_insert_key(track, 1.0, value)
	var runtime := AnimationLibrary.new()
	runtime.add_animation(&"AimPose", pose)
	animation_player.add_animation_library(&"droid", runtime)


func _close_cycle(clip: Animation) -> void:
	# The source run's last legs differ by ~12 degrees. Ease into the first
	# pose over 100 ms instead of allowing a visible snap on every wrap.
	for track in clip.get_track_count():
		var type := clip.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			continue
		var first: Variant = clip.track_get_key_value(track, 0)
		for key in clip.track_get_key_count(track):
			var time := clip.track_get_key_time(track, key)
			var weight := smoothstep(clip.length - 0.10, clip.length, time)
			if weight <= 0.0:
				continue
			var value: Variant = clip.track_get_key_value(track, key)
			clip.track_set_key_value(track, key, value.slerp(first, weight) if type == Animation.TYPE_ROTATION_3D else value.lerp(first, weight))


func _build_weapon_socket() -> void:
	hand_attachment = BoneAttachment3D.new()
	hand_attachment.name = "RightHandAttachment"
	skeleton.add_child(hand_attachment)
	hand_attachment.bone_name = "mixamorig_RightHand"
	hand_attachment.override_pose = false
	weapon_socket = Node3D.new()
	weapon_socket.name = "WeaponSocket"
	hand_attachment.add_child(weapon_socket)


func set_weapon(identifier: String) -> void:
	if weapon_socket == null:
		return
	clear_mekatana_pose()
	_mekatana_weapon = null
	weapon_id = identifier if identifier in ["blaster", "shotgun", "longshot", "mekatana"] else "blaster"
	for child in weapon_socket.get_children():
		weapon_socket.remove_child(child)
		child.queue_free()
	var weapon: Node3D
	var right_grip := Vector3.ZERO
	if weapon_id == "mekatana":
		weapon = MEKATANA_SCENE.instantiate() as Node3D
		_mekatana_weapon = weapon
		muzzle = weapon.get_node("BladeTip") as Marker3D
		support_grip = weapon.get_node("LeftHandGrip") as Marker3D
		right_grip = (weapon.get_node("RightHandGrip") as Marker3D).position
	elif weapon_id in ["shotgun", "longshot"]:
		weapon = (LONGSHOT_SCENE if weapon_id == "longshot" else SHOTGUN_SCENE).instantiate() as Node3D
		muzzle = weapon.get_node("Muzzle") as Marker3D
		support_grip = weapon.get_node("LeftHandGrip") as Marker3D
		right_grip = (weapon.get_node("RightHandGrip") as Marker3D).position
	else:
		weapon = Node3D.new()
		weapon.name = "Blaster"
		var mount := Node3D.new()
		mount.name = "ImportedBlasterAlignment"
		mount.rotation.y = PI * 0.5
		mount.scale = Vector3.ONE * 1.35
		mount.position = Vector3(0, -0.14, -0.20)
		weapon.add_child(mount)
		mount.add_child((load(WEAPON_PATH) as PackedScene).instantiate())
		muzzle = Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(0, 0.08, -0.88)
		weapon.add_child(muzzle)
		support_grip = Marker3D.new()
		support_grip.name = "LeftHandGrip"
		support_grip.position = Vector3(-0.08, -0.06, -0.14)
		weapon.add_child(support_grip)
		right_grip = Vector3(0.0, -0.08, 0.08)
	weapon_socket.add_child(weapon)
	var weapon_scale := 0.88 if weapon_id == "mekatana" else WEAPON_SCALE
	var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * weapon_scale / MODEL_SCALE)
	var desired := Transform3D(basis, _weapon_hand_pose.origin - basis * right_grip)
	weapon_socket.transform = _weapon_hand_pose.affine_inverse() * desired
	if pose_solver != null:
		pose_solver.mekatana_equipped = weapon_id == "mekatana"
		pose_solver._mekatana_guard_yaw = 0.0
		pose_solver.configure(skeleton, weapon_socket.transform, support_grip.position, muzzle.position, _aim_spine)
	_refresh_attachment()


func set_counter_pose(active: bool, weight: float = 1.0) -> void:
	if pose_solver != null:
		pose_solver.counter_guard = active
		pose_solver.counter_weight = clampf(weight, 0.0, 1.0)


func set_mekatana_pose(step: int, phase: String, progress: float) -> void:
	_mekatana_phase = phase
	if phase != "":
		aim_weight = 1.0
	if pose_solver != null:
		pose_solver.set_mekatana_pose(step, phase, progress)
	if is_instance_valid(_mekatana_weapon):
		_mekatana_weapon.call("set_phase", step, phase, progress)


func clear_mekatana_pose() -> void:
	_mekatana_phase = ""
	_mekatana_direction = Vector3.ZERO
	if pose_solver != null:
		pose_solver.clear_mekatana_pose()
	if is_instance_valid(_mekatana_weapon):
		_mekatana_weapon.call("clear_mekatana_pose")


func set_mekatana_direction(direction: Vector3) -> void:
	var flat := direction * Vector3(1.0, 0.0, 1.0)
	if flat.is_finite() and flat.length_squared() > 0.0001:
		_mekatana_direction = flat.normalized()
		rotation.y = atan2(-flat.x, -flat.z)


func set_mekatana_impact(target: Node3D, power: float = 1.0) -> void:
	if is_instance_valid(_mekatana_weapon):
		_mekatana_weapon.call("set_mekatana_impact", target, power)


func set_longshot_cycle(normal_shots: int, enhanced_ready: bool) -> void:
	if weapon_id != "longshot" or weapon_socket == null or weapon_socket.get_child_count() == 0:
		return
	var weapon := weapon_socket.get_child(0)
	if weapon.has_method("set_cycle"):
		weapon.call("set_cycle", normal_shots, enhanced_ready)


func _build_tree(model: Node3D) -> void:
	var base := AnimationNodeStateMachine.new()
	for clip in EXPECTED_CLIPS:
		if clip == &"fire":
			continue
		base.add_node(clip, _scaled_clip(clip), Vector2.ZERO)
	base.add_node(&"walk_back", _scaled_clip(&"walk", true), Vector2.ZERO)
	base.add_node(&"run_back", _scaled_clip(&"run", true), Vector2.ZERO)
	for from_state in base.get_node_list():
		for to_state in base.get_node_list():
			if from_state == to_state or from_state in [&"Start", &"End"] or to_state in [&"Start", &"End"]:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.10 if to_state == &"fall" else 0.16
			base.add_transition(from_state, to_state, transition)
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"Base", base)
	var aim := AnimationNodeAnimation.new()
	aim.animation = &"droid/AimPose"
	tree.add_node(&"Aim", aim)
	var fire := AnimationNodeAnimation.new()
	fire.animation = &"fire"
	tree.add_node(&"Fire", fire)
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.035
	shot.fadeout_time = 0.16
	shot.filter_enabled = true
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for track in animation_player.get_animation(&"fire").get_track_count():
		var path := animation_player.get_animation(&"fire").track_get_path(track)
		var bone := skeleton.find_bone(str(path).get_slice(":", 1))
		if _is_upper_body(bone):
			upper.set_filter_path(path, true)
			shot.set_filter_path(path, true)
	tree.add_node(&"Shot", shot)
	tree.add_node(&"Armed", upper)
	tree.connect_node(&"Shot", 0, &"Aim")
	tree.connect_node(&"Shot", 1, &"Fire")
	tree.connect_node(&"Armed", 0, &"Base")
	tree.connect_node(&"Armed", 1, &"Shot")
	tree.connect_node(&"output", 0, &"Armed")
	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.tree_root = tree
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.root_node = animation_tree.get_path_to(model)
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_tree.active = true
	_playback = animation_tree.get("parameters/Base/playback")
	animation_tree.set("parameters/Base/fall/Rate/scale", 3.0)


func _scaled_clip(clip: StringName, backwards: bool = false) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var animation := AnimationNodeAnimation.new()
	animation.animation = clip
	if backwards:
		animation.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	tree.add_node(&"Clip", animation)
	tree.add_node(&"Rate", AnimationNodeTimeScale.new())
	tree.connect_node(&"Rate", 0, &"Clip")
	tree.connect_node(&"output", 0, &"Rate")
	return tree


func _is_upper_body(bone: int) -> bool:
	while bone >= 0:
		if bone == _spine:
			return true
		bone = skeleton.get_bone_parent(bone)
	return false


func update_visual(delta: float, actual_velocity: Vector3, aim_point: Vector3, engaged: bool, stunned: bool, paused: bool) -> void:
	if not _ready_ok or paused or delta <= 0.0:
		return
	if dead:
		_death_clock += delta
		# Hold the last authored pose until gameplay requests its usual reset.
		animation_tree.advance(delta if _death_clock < 1.2 else 0.0)
		_refresh_attachment()
		return
	if _preview:
		animation_tree.advance(delta)
		_refresh_attachment()
		return
	_aim_point = aim_point
	_shot_clock += delta
	_hit_clock += delta
	var flat := actual_velocity * Vector3(1, 0, 1)
	var speed := flat.length() if not stunned else 0.0
	locomotion_speed = speed
	var melee_locked := _mekatana_phase in ["preparation", "active"] and _mekatana_direction.length_squared() > 0.001
	var direction := _mekatana_direction if melee_locked else aim_point - global_position if engaged else flat
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		var world_yaw := atan2(-direction.x, -direction.z)
		rotation.y = world_yaw if melee_locked else lerp_angle(rotation.y, world_yaw, 1.0 - exp(-14.0 * delta))
	# A long blade keeps an authored two-handed guard during travel as well as
	# combat; unarmed run wrists would otherwise turn its tip into the floor.
	aim_weight = move_toward(aim_weight, 1.0 if engaged or _mekatana_phase != "" or weapon_id == "mekatana" else 0.0, delta * 7.0)
	var next: StringName = &"idle"
	var local_move := model_axis.global_basis.orthonormalized().inverse() * flat
	var backwards := engaged and local_move.z < -speed * 0.45
	var gait_direction := -local_move if backwards else local_move
	var yaw := atan2(gait_direction.x, gait_direction.z) if speed > 0.06 else 0.0
	leg_yaw = lerp_angle(leg_yaw, yaw, 1.0 - exp(-18.0 * delta))
	if speed > 0.06:
		var running := speed > (2.6 if animation_state in [&"run", &"run_back"] else 3.0)
		next = (&"run_back" if backwards else &"run") if running else (&"walk_back" if backwards else &"walk")
		locomotion_rate = clampf(speed / (RUN_SPEED if running else WALK_SPEED), 0.04, 2.0)
		animation_tree.set("parameters/Base/%s/Rate/scale" % next, locomotion_rate)
		_ambient_clock = 0.0
	elif not engaged and not stunned:
		_ambient_clock += delta
		# Quiet clips only. The spell and warm-up do not describe a gunfight.
		var cycle := [&"idle", &"wait", &"look_around"]
		if _ambient_clock > 10.0:
			_ambient_clock = 0.0
			_ambient_index = (_ambient_index + 1) % cycle.size()
		next = cycle[_ambient_index]
	else:
		_ambient_clock = 0.0
	if stunned:
		animation_tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_shot_clock = 10.0
	_travel(next)
	animation_tree.set("parameters/Armed/blend_amount", aim_weight)
	animation_tree.advance(delta)
	_solve_pose()


func _solve_pose() -> void:
	var kick := sin(clampf(_shot_clock / 0.18, 0.0, 1.0) * PI) if _shot_clock < 0.18 else 0.0
	var hit := sin(clampf(_hit_clock / 0.24, 0.0, 1.0) * PI) * _hit_strength if _hit_clock < 0.24 else 0.0
	pose_solver.solve(leg_yaw, aim_weight, _aim_point, kick, hit)
	left_grip_error = pose_solver.left_grip_error
	_refresh_attachment()


func _travel(next: StringName) -> void:
	if animation_state != next:
		animation_state = next
		_playback.travel(next)


func prepare_shot(aim_point: Vector3) -> Transform3D:
	if not _ready_ok or dead:
		return get_muzzle_transform()
	_preview = false
	_aim_point = aim_point
	var flat := aim_point - global_position
	flat.y = 0
	if flat.length_squared() > 0.001:
		rotation.y = atan2(-flat.x, -flat.z)
	aim_weight = 1.0
	animation_tree.set("parameters/Armed/blend_amount", 1.0)
	# A zero step can retain the previous unarmed blend on the first shot.
	animation_tree.advance(0.000001)
	_solve_pose()
	var shot_transform := get_muzzle_transform()
	# The projectile leaves the evaluated barrel, then the supplied upper-body
	# fire clip and shoulder impulse play. No animation event applies damage.
	animation_tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_shot_clock = 0.0
	return shot_transform


func play_hit(critical: bool = false) -> void:
	if dead or not _ready_ok:
		return
	_hit_clock = 0.0
	_hit_strength = 1.35 if critical else 1.0


func play_death() -> void:
	if not _ready_ok or dead:
		return
	dead = true
	clear_mekatana_pose()
	pose_solver.reset_offsets()
	_preview = false
	_death_clock = 0.0
	aim_weight = 0.0
	leg_yaw = 0.0
	animation_tree.set("parameters/Armed/blend_amount", 0.0)
	animation_tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_travel(&"fall")


func reset_visual() -> void:
	if not _ready_ok:
		return
	dead = false
	clear_mekatana_pose()
	pose_solver.reset_offsets()
	_preview = false
	_death_clock = 0.0
	_shot_clock = 10.0
	_hit_clock = 10.0
	_ambient_clock = 0.0
	_ambient_index = 0
	aim_weight = 0.0
	leg_yaw = 0.0
	locomotion_speed = 0.0
	rotation = Vector3.ZERO
	animation_state = &"idle"
	animation_tree.set("parameters/Armed/blend_amount", 0.0)
	animation_tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_playback.start(&"idle", true)
	animation_tree.advance(0.0)
	_refresh_attachment()


## Inspection-only entry point: all ten source clips are accessible. Unsupported
## gameplay actions (spell/warm-up/turn) do not silently become new AI abilities.
func preview_animation(clip: StringName) -> bool:
	if clip not in EXPECTED_CLIPS or not _ready_ok:
		return false
	reset_visual()
	_preview = true
	if clip == &"fire":
		aim_weight = 1.0
		animation_tree.set("parameters/Armed/blend_amount", 1.0)
		animation_tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		animation_state = clip
		_playback.start(clip, true)
	animation_tree.advance(0.0)
	return true


func _refresh_attachment() -> void:
	skeleton.force_update_all_bone_transforms()
	# BoneAttachment normally refreshes on skeleton_updated; force same-tick
	# synchronization for the projectile as well (no cached previous-frame muzzle).
	hand_attachment.transform = skeleton.get_bone_global_pose(_right_hand)
	hand_attachment.force_update_transform()
	if is_instance_valid(_mekatana_weapon):
		_mekatana_weapon.call("sample_blade_pose")


func get_muzzle_transform() -> Transform3D:
	return muzzle.global_transform.orthonormalized() if muzzle != null else global_transform
