extends SceneTree

## Integration checks against the actual imported scene, hand sockets and pose
## solver. No simulation authority or source resource is changed by this test.
const VISUAL := preload("res://scripts/enemy_droid_visual.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []
var checks := 0
var measures := {}


func _initialize() -> void:
	call_deferred("run_tests")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func bone_poses(rig: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in rig.skeleton.get_bone_count():
		result.append(rig.skeleton.get_bone_pose(bone))
	return result


func pose_difference(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var difference := 0.0
	for i in a.size():
		difference = maxf(difference, a[i].origin.distance_to(b[i].origin))
		# Compare matrix axes directly: Quaternion.angle_to(q) can report ~0.04
		# degrees for identical float32 poses because of acos precision near 1.
		difference = maxf(difference, a[i].basis.x.distance_to(b[i].basis.x))
		difference = maxf(difference, a[i].basis.y.distance_to(b[i].basis.y))
		difference = maxf(difference, a[i].basis.z.distance_to(b[i].basis.z))
	return difference


func sample_frames(rig: Node3D, count: int, velocity: Vector3, target: Vector3, engaged := true, stunned := false, paused := false) -> void:
	for frame in count:
		rig.update_visual(STEP, velocity, target, engaged, stunned, paused)


func source_fingerprint(player: AnimationPlayer) -> Dictionary:
	var result := {}
	for name in VISUAL.EXPECTED_CLIPS:
		var clip := player.get_animation(name)
		var values := []
		for track in clip.get_track_count():
			if clip.track_get_type(track) == Animation.TYPE_POSITION_3D and str(clip.track_get_path(track)).ends_with(":mixamorig_Hips"):
				for key in clip.track_get_key_count(track):
					values.append(clip.track_get_key_value(track, key))
		result[name] = {"loop": clip.loop_mode, "length": clip.length, "hips_keys": values}
	return result


func run_tests() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var actor := Node3D.new()
	stage.add_child(actor)
	actor.position = Vector3(2.0, 0.2, -3.0)
	var initial_actor_position := actor.global_position
	var packed := load(VISUAL.MODEL_PATH) as PackedScene
	var original := packed.instantiate()
	stage.add_child(original)
	var source_player := original.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var before := source_fingerprint(source_player)
	var rig := VISUAL.new()
	actor.add_child(rig)
	check(rig.setup(), "first rig setup")
	if not rig._ready_ok:
		finish(stage)
		return
	var second := VISUAL.new()
	stage.add_child(second)
	check(second.setup(), "second rig setup")
	check(source_fingerprint(source_player) == before, "both rigs leave imported source root keys and loop modes unchanged")
	check(rig.skeleton.get_bone_count() == 65, "the inspected 65-bone skeleton is loaded")
	for name in VISUAL.EXPECTED_CLIPS:
		check(rig.animation_player.has_animation(name), "source clip preserved: %s" % name)
		check(rig.animation_player.get_animation(name) != second.animation_player.get_animation(name), "private animation resource per rig: %s" % name)
	var fixed_socket := rig.weapon_socket.transform
	check(rig.hand_attachment.get_parent() == rig.skeleton, "right-hand attachment belongs to skeleton")
	check(rig.hand_attachment.bone_name == "mixamorig_RightHand", "right-hand attachment resolves inspected bone")
	check(rig.weapon_socket.get_parent() == rig.hand_attachment, "weapon has a rigid hand socket")
	check(rig.muzzle.get_parent().get_parent() == rig.weapon_socket, "muzzle belongs to the weapon under hand socket")
	var max_angle := 0.0
	var max_grip := 0.0
	var max_origin_error := 0.0
	var max_hips_horizontal := 0.0
	var hips_index := rig.skeleton.find_bone("mixamorig_Hips")
	var right_index := rig.skeleton.find_bone("mixamorig_RightHand")
	var left_index := rig.skeleton.find_bone("mixamorig_LeftHand")
	var hip_rest: Vector3 = rig.skeleton.get_bone_rest(hips_index).origin
	var directions := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, -1).normalized(), Vector3(-1, 0, 1).normalized()]
	for target_direction in directions:
		for height in [-2.0, 0.92, 4.0]:
			for speed in [1.8, 4.6]:
				for movement_direction in directions:
					rig.reset_visual()
					var target: Vector3 = actor.global_position + target_direction * 8.0 + Vector3.UP * height
					var velocity: Vector3 = movement_direction * speed
					sample_frames(rig, 40, velocity, target)
					var shot: Transform3D = rig.prepare_shot(target)
					var aim_direction := (target - shot.origin).normalized()
					var angle := rad_to_deg(acos(clampf((-shot.basis.z).dot(aim_direction), -1.0, 1.0)))
					max_angle = maxf(max_angle, angle)
					var wrist: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(left_index).origin
					var actual_error: float = wrist.distance_to(rig.support_grip.global_position)
					max_grip = maxf(max_grip, actual_error)
					var right_hand: Transform3D = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(right_index)
					max_origin_error = maxf(max_origin_error, right_hand.origin.distance_to(rig.hand_attachment.global_position))
					var hip_position: Vector3 = rig.skeleton.get_bone_pose_position(hips_index)
					max_hips_horizontal = maxf(max_hips_horizontal, Vector2(hip_position.x - hip_rest.x, hip_position.z - hip_rest.z).length())
					check(rig.weapon_socket.transform.is_equal_approx(fixed_socket), "socket remains fixed across target/movement sampling")
					check(rig.global_position.is_equal_approx(initial_actor_position), "presentation cannot translate actor during locomotion")
	measures["aim_cases"] = directions.size() * 3 * 2 * directions.size()
	measures["maximum_muzzle_error_degrees"] = max_angle
	measures["maximum_support_wrist_error_metres"] = max_grip
	measures["maximum_hand_attachment_origin_error_metres"] = max_origin_error
	measures["maximum_hips_horizontal_offset_source_units"] = max_hips_horizontal
	check(max_angle < 0.75, "muzzle alignment under 0.75 degrees for movement/elevation matrix; measured %f" % max_angle)
	check(max_grip < 0.03, "support hand stays within 3 cm of grip; measured %f" % max_grip)
	check(max_origin_error < 0.0001, "weapon attachment follows evaluated wrist without a frame of lag")
	check(max_hips_horizontal < 0.0001, "walk, run and backwards animation root remains centred")
	check(actor.global_position.is_equal_approx(initial_actor_position), "actor root position is unchanged by every visual update")
	var target := actor.global_position + Vector3(0, 0.92, -8)
	rig.reset_visual()
	sample_frames(rig, 80, Vector3(0, 0, -1.8), target)
	check(rig.animation_state == &"walk", "forward movement selects walk")
	check(absf(rig.locomotion_rate - 1.8 / VISUAL.WALK_SPEED) < 0.0001, "walk cadence matches measured source root speed")
	sample_frames(rig, 80, Vector3(0, 0, 1.8), target)
	check(rig.animation_state == &"walk_back", "backwards movement selects reversed walk")
	sample_frames(rig, 80, Vector3(0, 0, -4.6), target)
	check(rig.animation_state == &"run", "fast movement selects run")
	sample_frames(rig, 80, Vector3.ZERO, target)
	check(rig.animation_state == &"idle", "stopping in combat returns to idle")
	var frozen := bone_poses(rig)
	var frozen_muzzle: Transform3D = rig.get_muzzle_transform()
	sample_frames(rig, 80, Vector3(5, 0, 0), target + Vector3.UP * 3, true, false, true)
	check(pose_difference(frozen, bone_poses(rig)) < 0.0001, "pause freezes all bone poses")
	check(rig.get_muzzle_transform().is_equal_approx(frozen_muzzle), "pause freezes muzzle transform")
	rig.prepare_shot(target)
	sample_frames(rig, 5, Vector3(2, 0, 0), target, true, true)
	check(rig._shot_clock >= 10.0, "stun cancels procedural shot recoil")
	check(not rig.animation_tree.get("parameters/Shot/active"), "stun aborts the shot animation")
	check(rig.animation_state == &"idle", "stun stops locomotion visual")
	# Run two independently prepared rigs through the same 240-frame sequence.
	# This exposes accumulated bone corrections and incomplete reset state.
	rig.reset_visual()
	second.reset_visual()
	second.global_position = actor.global_position
	for frame in 240:
		var velocity := Vector3(sin(frame * 0.02), 0, -1).normalized() * 2.2
		rig.update_visual(STEP, velocity, target, true, false, false)
		second.update_visual(STEP, velocity, target, true, false, false)
	var repeated_difference := pose_difference(bone_poses(rig), bone_poses(second))
	measures["independent_240_frame_pose_difference"] = repeated_difference
	check(repeated_difference < 0.001, "used/reset rig and fresh rig stay deterministic for 240 frames")
	check(rig.weapon_socket.transform.is_equal_approx(fixed_socket), "240 frames cannot accumulate socket drift")
	# Imported clips have no position track for RightShoulder. Repeated recoil
	# must therefore restore its authored local position explicitly; otherwise
	# every solve can accumulate its offset even though rotations are refreshed.
	rig.reset_visual()
	second.reset_visual()
	var right_shoulder := rig.skeleton.find_bone("mixamorig_RightShoulder")
	for frame in 240:
		if frame % 36 == 0:
			rig.prepare_shot(target)
		rig.update_visual(STEP, Vector3.ZERO, target, true, false, false)
		second.update_visual(STEP, Vector3.ZERO, target, true, false, false)
	sample_frames(rig, 120, Vector3.ZERO, target)
	sample_frames(second, 120, Vector3.ZERO, target)
	var shoulder_drift: float = rig.skeleton.get_bone_pose_position(right_shoulder).distance_to(second.skeleton.get_bone_pose_position(right_shoulder))
	var recovered_difference := pose_difference(bone_poses(rig), bone_poses(second))
	var recovered_muzzle: float = rig.get_muzzle_transform().origin.distance_to(second.get_muzzle_transform().origin)
	measures["seven_shot_recovery_shoulder_drift_source_units"] = shoulder_drift
	measures["seven_shot_recovery_pose_difference"] = recovered_difference
	measures["seven_shot_recovery_muzzle_error_metres"] = recovered_muzzle
	check(shoulder_drift < 0.0001, "seven repeated shots recover immutable shoulder local position")
	check(recovered_difference < 0.001, "repeated fire recovers the same authored pose as a rig that never fired")
	check(recovered_muzzle < 0.001, "repeated fire recovers baseline muzzle within 1 mm")
	rig.reset_visual()
	second.reset_visual()
	sample_frames(rig, 60, Vector3.ZERO, target)
	sample_frames(second, 60, Vector3.ZERO, target)
	var reset_muzzle: float = rig.get_muzzle_transform().origin.distance_to(second.get_muzzle_transform().origin)
	measures["seven_shot_reset_muzzle_error_metres"] = reset_muzzle
	check(reset_muzzle < 0.001, "reset after repeated fire reproduces fresh idle aim muzzle within 1 mm")
	rig.prepare_shot(target)
	sample_frames(rig, 5, Vector3.ZERO, target)
	rig.reset_visual()
	second.reset_visual()
	var interrupted_shoulder_drift: float = rig.skeleton.get_bone_pose_position(right_shoulder).distance_to(second.skeleton.get_bone_pose_position(right_shoulder))
	measures["mid_recoil_immediate_reset_shoulder_drift"] = interrupted_shoulder_drift
	check(interrupted_shoulder_drift < 0.0001, "reset clears recoil shoulder offset immediately without an extra update")
	rig.play_death()
	check(rig.dead and rig.animation_state == &"fall", "death immediately enters terminal fall state")
	sample_frames(rig, 80, Vector3.ZERO, target)
	var dead_pose := bone_poses(rig)
	var dead_hips: Vector3 = rig.skeleton.get_bone_global_pose(hips_index).origin
	measures["dead_hips_height_source_units"] = dead_hips.y
	check(dead_hips.y < 0.25, "death reaches authored fallen pose before existing reset delay")
	rig.play_hit(true)
	rig.prepare_shot(target)
	sample_frames(rig, 20, Vector3(5, 0, 0), target)
	check(rig.dead and rig.animation_state == &"fall", "hit, shot and movement cannot interrupt death")
	check(pose_difference(dead_pose, bone_poses(rig)) < 0.001, "terminal death pose remains held")
	rig.reset_visual()
	check(not rig.dead and rig.animation_state == &"idle", "respawn reset leaves terminal state")
	check(rig.skeleton.get_bone_global_pose(hips_index).origin.y > 0.5, "reset returns standing pose")
	for clip in VISUAL.EXPECTED_CLIPS:
		check(rig.preview_animation(clip), "preview accepts source clip %s" % clip)
		sample_frames(rig, 3, Vector3.ZERO, target, false)
		check(not rig.dead, "preview does not change gameplay death state for %s" % clip)
	check(not rig.preview_animation(&"not_a_real_clip"), "unknown clip is rejected")
	check(source_fingerprint(source_player) == before, "source resources remain unchanged after all runtime operations")
	finish(stage)


func finish(stage: Node3D) -> void:
	var report := {"checks": checks, "failure_count": failures.size(), "failures": failures, "measurements": measures}
	var file := FileAccess.open("res://exports/enemy-droid-review/test-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("ENEMY_DROID_TEST " + JSON.stringify(report))
	stage.free()
	quit(0 if failures.is_empty() else 1)
