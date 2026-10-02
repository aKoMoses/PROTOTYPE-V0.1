extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const NETWORK_PLAYER := preload("res://scripts/network_player.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []
var checks := 0
var actor: Node3D
var target: Node3D
var rig: PlayerVisualRig
var baseline_right := Transform3D.IDENTITY
var baseline_left := Transform3D.IDENTITY
var baseline_leg := Quaternion.IDENTITY
var final_right := Transform3D.IDENTITY
var final_left := Transform3D.IDENTITY
var final_leg := Quaternion.IDENTITY


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	actor = PLAYER.new()
	actor.name = "Player"
	scene.add_child(actor)
	target = PLAYER.new()
	target.name = "TargetDummy"
	scene.add_child(target)
	await process_frame
	target.set_physics_process(false)
	target.set_process(false)
	target.call("set_gameplay_enabled", true)
	target.position = Vector3(0, 0, -10)
	rig = actor.get("_visual_rig")
	var args := OS.get_cmdline_user_args()
	if "--chassis" in args:
		actor.call("set_robot", args[args.find("--chassis") + 1])
		rig = actor.get("_visual_rig")
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var right := rig.skeleton.find_bone("mixamorig_RightHand")
	var left := rig.skeleton.find_bone("mixamorig_LeftHand")
	var leg := rig.skeleton.find_bone("mixamorig_LeftUpLeg")
	rig.aim_modifier.modification_processed.connect(func() -> void:
		baseline_right = rig.skeleton.get_bone_global_pose(right)
		baseline_left = rig.skeleton.get_bone_global_pose(left)
		baseline_leg = rig.skeleton.get_bone_pose_rotation(leg))
	rig.module_pose.modification_processed.connect(func() -> void:
		final_right = rig.skeleton.get_bone_global_pose(right)
		final_left = rig.skeleton.get_bone_global_pose(left)
		final_leg = rig.skeleton.get_bone_pose_rotation(leg))
	check(rig.module_pose.get_index() > rig.aim_modifier.get_index(), "free-hand gestures run after weapon IK")
	await prepare("javelin", "offensive")
	check(actor.call("_begin_javelin_charge"), "actual Javelin charge accepted")
	actor.call("_update_javelin_charge", 0.6)
	await sample("javelin", "preparation")
	var hold: float = rig.module_pose.progress
	actor.call("_update_javelin_charge", 0.3)
	await sample("javelin", "preparation")
	check(hold == 1.0 and rig.module_pose.progress == 1.0, "held Javelin keeps its windup instead of throwing early")
	actor.call("_release_javelin_charge")
	actor.call("_update_javelin_charge", STEP)
	await sample("javelin", "active")
	check(not actor.call("is_module_busy"), "release gesture adds no action lock")
	await prepare("javelin", "offensive")
	actor.call("_begin_javelin_charge")
	actor.call("_update_javelin_charge", 0.3)
	actor.call("_cancel_javelin_charge")
	actor.call("_update_robot_motion", STEP)
	check(rig.module_pose.module_id == "", "cancelled charge never animates a throw")
	await prepare("javelin", "offensive")
	actor.call("_begin_javelin_charge")
	actor.call("_release_javelin_charge")
	actor.call("_update_javelin_charge", 0.2)
	actor.call("_cancel_javelin_charge")
	actor.call("_update_robot_motion", STEP)
	check(rig.module_pose.module_id == "", "cancelled tap before emission never animates a throw")
	for iteration in 2:
		await prepare("fulguro_punch", "offensive")
		actor.call("_begin_fulguro_charge")
		check(actor.get("_fulguro_phase") == "preparation", "actual Fulguro charge accepted")
		actor.call("_update_fulguro_attack", 0.25)
		await sample("fulguro_punch", "preparation")
		check(rig.module_pose.variant == iteration, "successive Fulguro casts use different boxing clips")
		actor.call("_release_fulguro_charge")
		actor.call("_update_fulguro_attack", 0.15)
		await sample("fulguro_punch", "active")
		actor.call("_update_fulguro_attack", 0.12)
		await sample("fulguro_punch", "recovery")
	await prepare("pelto_smash", "offensive")
	actor.call("_perform_pelto_smash", true)
	actor.call("_update_pelto_attack", 0.25)
	await sample("pelto_smash", "preparation")
	actor.call("_release_pelto_aim")
	actor.call("_update_pelto_attack", 0.2)
	await sample("pelto_smash", "active")
	await prepare("rocket_basket", "offensive")
	actor.call("_perform_rocket_basket")
	await sample("rocket_basket", "preparation", 0.25)
	await create_timer(0.34).timeout
	await sample("rocket_basket", "active")
	await prepare("projector", "defensive")
	check(actor.call("_perform_projector"), "actual Projector cast accepted")
	actor.call("_update_projector_cast", 0.1)
	await sample("projector", "preparation")
	actor.call("_update_projector_cast", 0.1)
	await sample("projector", "active")
	for id in ["magnetic_field", "permutation"]:
		await prepare(id, "defensive" if id == "magnetic_field" else "mobility")
		actor.call("_perform_" + id)
		await sample(id, "preparation", 0.1)
		await create_timer(0.22).timeout
		await sample(id, "active", 0.1)
	await prepare("counter", "defensive")
	check(actor.call("_perform_counter"), "actual Counter accepted")
	actor.get("_counter").update(0.1)
	await sample("counter", "active", STEP, false)
	check(final_left.is_equal_approx(baseline_left), "Counter retains its supporting weapon hand")
	await prepare("static_shield", "defensive")
	actor.call("_perform_static_shield")
	actor.set("_stasis_remaining", actor.get("_static_duration") - 0.2)
	await sample("static_shield", "active")
	actor.call("_perform_static_shield")
	actor.call("_update_robot_motion", STEP)
	check(rig.module_pose.module_id == "", "manual shield exit immediately releases the guard gesture")
	await prepare("pyro_boots", "mobility")
	actor.call("_perform_pyro_boots", Vector3.RIGHT)
	actor.call("_update_dash", 0.09)
	await sample("pyro_boots", "active")
	await prepare("bio_injector", "mobility")
	actor.call("_perform_bio_injector")
	await sample("bio_injector", "active", 0.2)
	check(not actor.get("_action_gate").is_busy(), "injector gesture does not delay weapon access")
	actor.get("_action_gate").try_acquire(1, "blaster", -1, true)
	actor.call("_update_robot_motion", STEP)
	check(rig.module_pose.module_id == "", "weapon input immediately wins over buff follow-through")
	await prepare("eclipse", "mobility")
	check(actor.get("_eclipse").begin(actor, true), "actual Eclipse aiming accepted")
	await sample("eclipse", "preparation", 0.1)
	actor.get("_eclipse").cancel(actor)
	actor.call("_update_robot_motion", STEP)
	check(rig.module_pose.module_id == "", "cancelled Eclipse aim does not animate arrival")
	await physics_frame
	check(actor.call("_perform_eclipse", actor.position + Vector3(0, 0, -3)), "actual Eclipse departure accepted")
	actor.get("_eclipse").update(actor, 0.3)
	await sample("eclipse", "active", 0.3)
	await test_network(scene)
	actor.call("set_gameplay_enabled", false)
	check(rig.module_pose.module_id == "", "round freeze clears a module pose")
	scene.queue_free()
	await process_frame
	await process_frame
	actor = null
	target = null
	rig = null
	print("MECHA MODULES TEST: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func prepare(id: String, category: String) -> void:
	actor.call("set_gameplay_enabled", false)
	actor.call("reset_combat_state")
	actor.call("set_gameplay_enabled", true)
	var loadout := {"weapon": "blaster", "offensive": "javelin", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": ""}
	loadout["robot"] = actor.call("get_robot_id")
	loadout[category] = id
	actor.call("apply_loadout", loadout)
	actor.call("set_passive", "")
	actor.set("training_instant_cooldowns", true)
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.position = Vector3.ZERO
	actor.set("aim_direction", Vector3.FORWARD)
	await physics_frame


func sample(id: String, phase: String, delta: float = STEP, expect_hand := true) -> void:
	actor.call("_update_robot_motion", delta)
	check(rig.module_pose.module_id == id and rig.module_pose.phase == phase, "real module phase selects authored gesture: %s/%s (got %s/%s)" % [id, phase, rig.module_pose.module_id, rig.module_pose.phase])
	var before := actor.transform
	await process_frame
	rig.animation_tree.advance(STEP)
	rig.skeleton.advance(STEP)
	await rig.skeleton.skeleton_updated
	check(final_right.is_equal_approx(baseline_right), "weapon hand and muzzle stay exact: " + id)
	check(final_leg.is_equal_approx(baseline_leg), "authored gesture leaves locomotion legs intact: " + id)
	check(actor.transform.is_equal_approx(before), "gesture never moves gameplay collision: " + id)
	if expect_hand and (phase == "active" or rig.module_pose.progress > 0.35):
		check(final_left.origin.distance_to(baseline_left.origin) > 0.005, "authored free hand actually moves: " + id)


func test_network(scene: Node3D) -> void:
	var host := NETWORK_PLAYER.new()
	host.remote_controlled = true
	scene.add_child(host)
	var replica := NETWORK_PLAYER.new()
	replica.authoritative = false
	replica.remote_controlled = true
	scene.add_child(replica)
	await process_frame
	for node in [host, replica]:
		node.set_physics_process(false)
		node.set_process(false)
		node.call("set_gameplay_enabled", true)
	host.set("_offensive_module_id", "javelin")
	host.call("_begin_javelin_charge")
	host.call("_update_javelin_charge", 0.2)
	host.call("_update_robot_motion", STEP)
	var packet: Dictionary = host.call("network_snapshot")
	check(packet.presence.module.id == "javelin", "module gesture travels in the existing authority snapshot")
	replica.call("receive_snapshot", packet)
	var pose = replica.get("_visual_rig").module_pose
	check(pose.module_id == "javelin" and pose.phase == "preparation", "replica follows the same authored charge")
	pose.progress = 0.9
	replica.call("receive_snapshot", packet)
	check(pose.progress >= 0.9, "repeated module snapshots never rewind an arm")
	host.call("_cancel_javelin_charge")
	host.call("_update_robot_motion", STEP)
	replica.call("receive_snapshot", host.call("network_snapshot"))
	replica.call("receive_snapshot", packet)
	check(pose.module_id == "", "stale snapshot cannot resurrect a cancelled module gesture")
	for node in [host, replica]: node.queue_free()
	await process_frame


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("MODULE POSE: " + description)
