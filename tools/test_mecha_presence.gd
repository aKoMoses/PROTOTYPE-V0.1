extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const NETWORK_PLAYER := preload("res://scripts/network_player.gd")
const BANK := preload("res://scripts/mecha_animation_bank.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []
var checks := 0
var actor: Node3D
var rig: PlayerVisualRig
var final_head := Quaternion.IDENTITY
var final_spine := Quaternion.IDENTITY
var head_index := -1
var spine_index := -1

class Threat extends Node3D:
	var spotted := true
	func get_health() -> float: return 100.0
	func is_visible_to(_observer: Node3D) -> bool: return spotted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	actor = PLAYER.new()
	actor.name = "Player"
	scene.add_child(actor)
	await process_frame
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.call("set_gameplay_enabled", true)
	actor.call("set_passive", "")
	var arguments := OS.get_cmdline_user_args()
	if "--chassis" in arguments:
		actor.call("set_robot", arguments[arguments.find("--chassis") + 1])
	rig = actor.get("_visual_rig")
	rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	head_index = rig.skeleton.find_bone("mixamorig_Head")
	spine_index = rig.skeleton.find_bone("mixamorig_Spine2")
	rig.skeleton.skeleton_updated.connect(func() -> void:
		final_head = rig.skeleton.get_bone_pose_rotation(head_index)
		final_spine = rig.skeleton.get_bone_pose_rotation(spine_index))
	var presence = rig.presence_modifier
	check(presence != null and presence.get_index() < rig.aim_modifier.get_index(), "presence runs before aim/support")
	check(BANK.LIBRARY.get_animation_list().size() == 28, "compact bank contains the selected twenty-eight clips")
	var states := rig._base_state_machine.get_node_list()
	states.erase(&"Start")
	states.erase(&"End")
	check(states.size() == 12, "only the six contextual result states extend the combat graph")
	for clip_name in BANK.RESULT_CLIPS:
		var clip := rig.animation_player.get_animation("context/" + String(clip_name))
		check(rig._animation_states[clip_name] == StringName("context/" + String(clip_name)), "result graph selects the adapted clip: " + String(clip_name))
		check(clip.length <= BANK.LIBRARY.get_animation(clip_name).length, "result uses the short authored window")
		check(clip != BANK.LIBRARY.get_animation(clip_name), "instance owns its result clip: " + String(clip_name))
		for track in clip.get_track_count():
			check(rig.skeleton.find_bone(clip.track_get_path(track).get_subname(0)) >= 0, "result track resolves on the actual skeleton")
	var character_transform := actor.transform
	actor.call("_update_robot_motion", STEP)
	presence.set("_quiet_delay", 0.0)
	await step()
	check(presence.quiet_clip in BANK.REST_CLIPS and rig._active_action == &"", "quiet gesture does not lock the full body")
	check(not actor.get("_action_gate").is_busy(), "quiet gesture leaves action ownership free")
	var maximum_head := 0.0
	var maximum_spine := 0.0
	for clip_name in BANK.REST_CLIPS:
		presence.quiet_clip = clip_name
		presence.quiet_time = 0.0
		for frame in ceili(BANK.LIBRARY.get_animation(clip_name).length / presence.REST_SPEED / STEP) + 1:
			await process_frame
			rig.animation_tree.advance(STEP)
			var baseline_head := rig.skeleton.get_bone_pose_rotation(head_index)
			var baseline_spine := rig.skeleton.get_bone_pose_rotation(spine_index)
			rig.skeleton.advance(STEP)
			await rig.skeleton.skeleton_updated
			maximum_head = maxf(maximum_head, rad_to_deg(baseline_head.angle_to(final_head)))
			maximum_spine = maxf(maximum_spine, rad_to_deg(baseline_spine.angle_to(final_spine)))
	check(maximum_head > 0.3 and maximum_head < 19.0, "authored head motion is visible and bounded")
	check(maximum_spine > 0.1 and maximum_spine < 10.0, "authored torso motion is subtle and bounded")
	print("PRESENCE_MOTION head=%.3fdeg spine=%.3fdeg" % [maximum_head, maximum_spine])
	presence.quiet_clip = &"look_around"
	presence.quiet_time = 3.0
	actor.call("set_touch_move_vector", Vector2.RIGHT)
	actor.call("_update_robot_motion", STEP)
	check(presence.quiet_clip == &"", "movement interrupts quiet gestures immediately")
	actor.call("set_touch_move_vector", Vector2.ZERO)
	presence.quiet_clip = &"look_around"
	rig.set_aim_enabled(true, true)
	check(presence.quiet_clip == &"" and not presence.torso_allowed, "aim immediately releases idle motion and protects the torso")
	for frame in 24: await step()
	var aim_socket := rig.get_weapon_socket(&"blaster").transform
	var hit_peak := 0.0
	for clip_name in BANK.HIT_CLIPS:
		presence.reset_presence()
		presence.hit_clip = clip_name
		presence.hit_time = 0.0
		presence.torso_allowed = false
		for frame in 24:
			await process_frame
			rig.update_visual_state(Vector3.LEFT, Vector3.FORWARD, 4.0, 5.0, STEP, true)
			rig.animation_tree.advance(STEP)
			var baseline := rig.skeleton.get_bone_pose_rotation(head_index)
			rig.skeleton.advance(STEP)
			await rig.skeleton.skeleton_updated
			hit_peak = maxf(hit_peak, rad_to_deg(baseline.angle_to(final_head)))
			check(rig.get_weapon_forward_direction(&"blaster").dot(Vector3.FORWARD) > 0.999999, "impact preserves muzzle alignment while strafing")
		check(presence.hit_clip == &"", "impact completes in 340 ms: " + String(clip_name))
	check(hit_peak > 0.3, "impact clips produce visible head reactions")
	print("PRESENCE_IMPACT head_peak=%.3fdeg" % hit_peak)
	check(actor.transform.is_equal_approx(character_transform), "context animations never move the CharacterBody")
	check(rig.get_weapon_socket(&"blaster").transform.is_equal_approx(aim_socket), "impacts preserve the calibrated aim socket")
	rig.set_aim_enabled(false, true)
	presence.reset_presence()
	actor.call("take_damage", 10.0, "test", "presence-hit-1")
	check(presence.hit_clip != &"", "accepted direct damage starts one reaction")
	var serial: int = presence.serial
	actor.call("take_damage", 10.0, "test", "presence-hit-1")
	check(presence.serial == serial, "duplicate attacks do not restart a reaction")
	actor.call("take_damage", 10.0, "test", "presence-hit-2")
	check(presence.serial == serial, "rapid damage is visually rate limited")
	presence.reset_presence()
	actor.get("combat_state").apply_burn(3.0, 10.0, "test-burn")
	actor.get("combat_state").update(0.5)
	check(presence.hit_clip == &"" and not actor.get("combat_state").processing_burn, "burn ticks keep damage without repetitive flinching")
	actor.get("combat_state").update(4.0)
	actor.get("combat_state").grant_shield(100.0, 3.0)
	actor.call("take_damage", 10.0, "test", "presence-shield")
	check(presence.hit_clip == &"", "fully absorbed damage does not pretend to hit the body")
	actor.get("combat_state").clear_shield()
	presence.quiet_clip = &"wait"
	actor.call("set_gameplay_enabled", false)
	check(presence.quiet_clip == &"" and presence.hit_clip == &"", "gameplay disable clears all contextual motion")
	actor.call("show_round_result", true)
	check(rig._active_action == &"cheer", "living winner celebrates after the round is frozen")
	for frame in 240: await step()
	check(rig._active_action == &"", "victory finishes and returns to idle")
	actor.call("show_round_result", false)
	check(rig._active_action == &"defeat_02", "living loser receives a standing disappointment")
	actor.call("show_round_result", true)
	check(rig._active_action == &"greet_04", "successive victories select a different authored gesture")
	actor.call("show_round_result", true)
	check(rig._active_action == &"laugh_02", "third victory receives its own variant")
	actor.call("show_round_result", false)
	check(rig._active_action == &"frustrated_01", "standing defeat varies on the next loss")
	actor.call("show_round_result", false)
	check(rig._active_action == &"frustrated_02", "third standing defeat has a different reaction")
	actor.call("set_gameplay_enabled", true)
	check(rig._active_action == &"" and not actor.get("_action_gate").is_busy(), "next round releases result pose and action ownership")
	var threat := Threat.new()
	threat.name = "TargetDummy"
	scene.add_child(threat)
	threat.position = Vector3(2.0, 0.0, 0.0)
	actor.get("visibility_state").combat_remaining = 0.0
	actor.get("_presentation_component").set("_threat_check_remaining", 0.0)
	actor.call("_update_robot_motion", STEP)
	check(not presence.quiet_allowed, "nearby visible opponent keeps the robot alert")
	threat.spotted = false
	actor.get("_presentation_component").set("_threat_check_remaining", 0.0)
	actor.call("_update_robot_motion", STEP)
	check(presence.quiet_allowed, "concealed opponents do not leak through presentation")
	presence.quiet_clip = &"look_around"
	presence.quiet_time = 1.0
	paused = true
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	for frame in 5: await process_frame
	check(is_equal_approx(presence.quiet_time, 1.0), "pause freezes contextual animation clocks")
	paused = false
	rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	threat.free()
	await test_network(scene)
	actor.call("set_passive", "")
	actor.call("take_damage", 5000.0, "test", "presence-lethal")
	check(presence.hit_clip == &"" and rig._active_action == &"fall", "lethal damage prioritizes the authored fall")
	actor.call("show_round_result", true)
	check(rig._active_action == &"fall", "round result never revives an eliminated actor")
	scene.queue_free()
	await process_frame
	await process_frame
	actor = null
	rig = null
	print("MECHA PRESENCE TEST: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


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
		node.get("_visual_rig").skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var host_presence = host.get("_visual_rig").presence_modifier
	var replica_presence = replica.get("_visual_rig").presence_modifier
	check(host_presence.autonomous and not replica_presence.autonomous, "only authority chooses contextual gestures")
	host.call("take_damage", 10.0, "test", "network-presence")
	var packet: Dictionary = host.call("network_snapshot")
	check(packet.presence.hit_clip != "", "authority embeds accepted impact in the gameplay snapshot")
	replica.call("receive_snapshot", packet)
	check(replica_presence.hit_clip == host_presence.hit_clip, "replica receives the same accepted impact")
	replica.get("_visual_rig").skeleton.advance(0.2)
	await replica.get("_visual_rig").skeleton.skeleton_updated
	await process_frame
	var time: float = replica_presence.hit_time
	replica.call("receive_snapshot", packet)
	check(replica_presence.hit_time >= time, "repeated snapshots do not rewind the reaction")
	replica.get("_visual_rig").skeleton.advance(0.2)
	await replica.get("_visual_rig").skeleton.skeleton_updated
	await process_frame
	replica.call("receive_snapshot", packet)
	check(replica_presence.hit_clip == &"", "late repeated snapshot cannot restart a finished impact")
	host_presence.reset_presence()
	host_presence.set_context(true, true)
	host_presence.set("_quiet_delay", 0.0)
	host.get("_visual_rig").skeleton.advance(STEP)
	await host.get("_visual_rig").skeleton.skeleton_updated
	await process_frame
	packet = host.call("network_snapshot")
	replica.call("receive_snapshot", packet)
	check(replica_presence.quiet_clip == host_presence.quiet_clip and replica_presence.quiet_clip != &"", "replica follows the authority's idle selection")
	var stale := packet.duplicate(true)
	host_presence.reset_presence()
	replica.call("receive_snapshot", host.call("network_snapshot"))
	replica.call("receive_snapshot", stale)
	check(replica_presence.quiet_clip == &"", "older snapshots cannot resurrect a cancelled gesture")
	replica_presence.set_context(true, true)
	replica.get("_visual_rig").skeleton.advance(20.0)
	await replica.get("_visual_rig").skeleton.skeleton_updated
	check(replica_presence.quiet_clip == &"", "replica never invents its own idle animation")
	for node in [host, replica]: node.queue_free()
	await process_frame


func step() -> void:
	await process_frame
	rig.animation_tree.advance(STEP)
	rig.skeleton.advance(STEP)
	await rig.skeleton.skeleton_updated


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("PRESENCE: " + description)
