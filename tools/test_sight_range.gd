extends SceneTree

## Real actor, bot and HUD integration. Deterministic geometry isolates the
## distance transition; dedicated wall/bush fixtures retain occlusion checks.
class ObserverProbe extends Node3D:
	var vision_radius := 10.0
	var vision_fade_width := 2.0
	func get_vision_radius() -> float:
		return vision_radius
	func get_vision_fade_width() -> float:
		return vision_fade_width

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _player: Node3D
var _target: Node3D
var _tracker: Node
var _bot: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	_player = _scene.get_node_or_null("Player")
	_target = _scene.get_node_or_null("TargetDummy")
	_tracker = _scene.get_node_or_null("SightTracker")
	_check(_player != null and _target != null and _tracker != null, "live scene creates both actors and SightTracker")
	if _player == null or _target == null or _tracker == null:
		_report()
		return
	var flow := _scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	_scene.set_process(false)
	_player.set_process(false)
	_player.set_physics_process(false)
	_target.set_process(false)
	_target.set_physics_process(false)
	_target.call("set_training_bot_enabled", false)
	_bot = _target.get_node("TrainingBot")
	_bot.set_physics_process(false)
	_tracker.set_process(false)
	for bush in get_nodes_in_group("bush_placeholder"):
		bush.queue_free()
	for body in _scene.find_children("*", "StaticBody3D", true, false):
		if body != _target:
			(body as StaticBody3D).collision_layer = 0
	for kit in get_nodes_in_group("repair_kits"):
		kit.call("set_collection_active", false)
	await physics_frame
	_player.global_position = Vector3.ZERO
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	_test_radial_visibility()
	await _test_fog()
	await _test_occlusion()
	_test_presentation()
	await _test_echo_pose_and_pause()
	_test_echo_gameplay_gate()
	_test_bot_perception()
	_test_tracking()
	_test_survival_search()
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	current_scene = null
	_scene.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	_report()


func _test_radial_visibility() -> void:
	_check(is_equal_approx(float(_player.call("get_vision_radius")), 22.0), "default player outer vision radius is 22 world units")
	_check(is_equal_approx(float(_player.call("get_vision_fade_width")), 8.0), "default player halo occupies the final eight units")
	_check(is_equal_approx(float(_target.call("get_vision_radius")), 22.0), "bot observes through the same default radius")
	for sample in [[0.0, 1.0], [14.0, 1.0], [18.0, 0.5], [22.0, 0.0], [26.0, 0.0]]:
		_target.global_position = Vector3(float(sample[0]), 0.0, 0.0)
		_check(is_equal_approx(float(_target.call("get_visibility_weight", _player)), float(sample[1])), "radial opacity at %.1f units = %.1f" % sample)
		_check(bool(_target.call("is_visible_to", _player)) == (float(sample[1]) > 0.0), "enemy visibility matches radial opacity at %.1f units" % float(sample[0]))
	var last_weight := 1.0
	for step in range(1, 80):
		_target.global_position = Vector3(14.0 + float(step) * 0.1, 0.0, 0.0)
		var weight := float(_target.call("get_visibility_weight", _player))
		if weight >= last_weight or weight <= 0.0:
			_check(false, "every interior fade step decreases smoothly and stays visible")
			return
		last_weight = weight
	_check(true, "every interior fade step decreases smoothly and stays visible")
	_target.global_position = Vector3(18.0, 12.0, 0.0)
	_check(is_equal_approx(float(_target.call("get_visibility_weight", _player)), 0.5), "arena radius uses horizontal distance, independent of height")
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	_target.call("mark_combat_event")
	_target.call("apply_spotted", 5.0, "test")
	_check(float(_target.call("get_visibility_weight", _player)) == 0.0, "combat and SPOTTED do not reveal enemies beyond the observer radius")
	_check(float(_target.call("get_visibility_weight", _target)) == 1.0, "self observation remains fully visible")
	var probe := ObserverProbe.new()
	_scene.add_child(probe)
	_target.global_position = Vector3(9.0, 0.0, 0.0)
	_check(is_equal_approx(float(_target.call("get_visibility_weight", probe)), 0.5), "visibility uses the observer's configurable radius and fade width")
	_target.global_position = Vector3(10.0, 0.0, 0.0)
	_check(float(_target.call("get_visibility_weight", probe)) == 0.0, "a shorter observer radius has its own hidden boundary")
	probe.queue_free()
	_target.call("reset_combat_state")


func _test_fog() -> void:
	var fog := _scene.get_node_or_null("FogOfWar")
	_check(fog != null, "live arena creates the world fog renderer")
	if fog == null:
		return
	fog.set_process(false)
	fog.set_physics_process(false)
	_player.global_position = Vector3.ZERO
	_player.call("set_gameplay_enabled", true)
	_target.set("network_proxy", false)
	_scene.set("duel_active", true)
	_scene.call("_process", 0.0)
	_check(bool((fog.call("get_debug_snapshot") as Dictionary).enabled), "live local duel enables the fog")
	fog.call("refresh_vision")
	await physics_frame
	fog.call("_physics_process", 0.1)
	fog.call("_process", 0.2)
	var snapshot: Dictionary = fog.call("get_debug_snapshot")
	_check(bool(snapshot.ready) and int(snapshot.profile_updates) > 0, "fog samples physical cover before exposing its rendered mask")
	_check(is_equal_approx(float(snapshot.full_radius), 14.0) and is_equal_approx(float(snapshot.radius), 22.0), "fog shares the player's inner and outer vision radii")
	for sample in [[14.0, 1.0], [18.0, 0.5], [23.0, 0.0]]:
		var weight := float(fog.call("sample_world_visibility", Vector3(float(sample[0]), 0.0, 0.0)))
		_check(is_equal_approx(weight, float(sample[1])), "world fog visibility at %.1f units = %.1f" % sample)
	var wall := StaticBody3D.new()
	wall.position = Vector3(8.0, 0.7, 0.0)
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 1.4, 3.0)
	collision.shape = box
	wall.add_child(collision)
	_scene.add_child(wall)
	await physics_frame
	fog.call("refresh_vision")
	fog.call("_physics_process", 0.1)
	fog.call("_process", 0.2)
	_check(float(fog.call("sample_world_visibility", Vector3(7.875, 0.0, 0.0))) > 0.95, "fog keeps the observed front face clear within the soft penumbra")
	_check(is_zero_approx(float(fog.call("sample_world_visibility", Vector3(12.0, 0.0, 0.0)))), "layer-one wall darkens the map behind it inside the inner radius")
	wall.queue_free()
	await physics_frame
	_player.call("set_gameplay_enabled", false)
	_scene.call("_process", 0.0)
	_check(not bool((fog.call("get_debug_snapshot") as Dictionary).enabled), "countdown or disabled gameplay hides the fog")
	_scene.set("duel_active", false)
	_scene.call("_process", 0.0)
	_check(not bool((fog.call("get_debug_snapshot") as Dictionary).enabled), "returning to the menu keeps the fog disabled")
	var network_controller := load("res://scripts/network_match.gd").new() as CanvasLayer
	_scene.add_child(network_controller)
	_scene.set("network_match", network_controller)
	network_controller.call("configure", _scene, root.get_node("NetworkSession").call("local_peer_id"), 22)
	network_controller.set_process(false)
	network_controller.set_physics_process(false)
	network_controller.set("_phase", "live")
	var network_player := network_controller.get("_player") as Node3D
	var network_target := network_controller.get("_target") as Node3D
	network_player.global_position = Vector3(5.0, 0.0, 5.0)
	network_player.call("set_gameplay_enabled", true)
	network_target.call("set_gameplay_enabled", true)
	_scene.call("_process", 0.0)
	fog.call("_physics_process", 0.1)
	snapshot = fog.call("get_debug_snapshot")
	_check(bool(snapshot.enabled) and (snapshot.origin as Vector3).is_equal_approx(network_player.global_position), "live human network round enables the fog and tracks its actual local fighter")
	_check(_tracker.get("_player") == network_player and _tracker.get("_target") == network_target, "network controller retargets the sight tracker to its actual human fighters")
	network_controller.call("_cleanup_actors")
	network_controller.queue_free()
	_scene.set("network_match", null)
	_check(_tracker.get("_player") == _player and _tracker.get("_target") == _target, "network cleanup restores the original sight tracker actors")
	_player.call("set_gameplay_enabled", true)
	_scene.set("duel_active", true)
	_scene.call("_process", 0.0)
	fog.call("refresh_vision")
	fog.call("_physics_process", 0.1)
	fog.call("_process", 0.2)


func _test_occlusion() -> void:
	_target.global_position = Vector3(18.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	var echo := _target.get_node("VisibilityEcho")
	echo.set_process(false)
	var last_seen := _target.global_position
	var wall := StaticBody3D.new()
	wall.position = Vector3(8.0, 0.7, 0.0)
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 1.4, 3.0)
	collision.shape = box
	wall.add_child(collision)
	_scene.add_child(wall)
	await physics_frame
	_target.call("mark_combat_event")
	_target.call("apply_spotted", 5.0, "test")
	_check(float(_target.call("get_visibility_weight", _player)) == 0.0, "opaque walls immediately hide an enemy even inside the fade band and revealed")
	_player.call("_mark_combat_event")
	_player.call("apply_spotted", 5.0, "test")
	_check(float(_player.call("get_visibility_weight", _target)) == 0.0, "wall occlusion also protects the player from bot vision")
	_target.call("_update_visibility_presentation", 0.016)
	var echo_state: Dictionary = echo.call("get_debug_state")
	_check(not (_target.get_node("VisualRoot") as Node3D).visible and bool(echo_state.visible), "wall occlusion immediately hides the live model but fades its last observation")
	_target.global_position = Vector3(18.0, 0.0, 1.0)
	_target.call("_update_visibility_presentation", 0.016)
	echo_state = echo.call("get_debug_state")
	_check(Vector3(echo_state.position).is_equal_approx(last_seen), "wall echo does not reveal movement behind cover")
	wall.queue_free()
	await physics_frame
	_target.call("reset_combat_state")
	_player.call("reset_combat_state")
	_target.global_position = Vector3(18.0, 0.0, 0.0)
	var bush := Node3D.new()
	bush.position = _target.global_position
	bush.set_meta("bush_radius", 1.2)
	bush.add_to_group("bush_placeholder")
	_scene.add_child(bush)
	_check(float(_target.call("get_visibility_weight", _player)) == 0.0, "concealed bush enemy is immediately hidden inside the fade band")
	_target.call("apply_spotted", 5.0, "test")
	_check(is_equal_approx(float(_target.call("get_visibility_weight", _player)), 0.5), "bush reveal retains the distance fade")
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	bush.global_position = _target.global_position
	_check(float(_target.call("get_visibility_weight", _player)) == 0.0, "revealed bush enemy beyond the radius stays hidden")
	bush.queue_free()
	await process_frame
	_target.call("reset_combat_state")


func _test_presentation() -> void:
	_player.global_position = Vector3.ZERO
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_target.call("apply_spotted", 5.0, "test")
	_target.call("apply_javelin_mark", 5.0, "test")
	_target.call("_update_effect_presentation")
	_target.call("_update_visibility_presentation", 0.0)
	var rig := _target.get_node("VisualRoot") as Node3D
	var fade := _target.get_node("VisibilityFade")
	var echo := _target.get_node("VisibilityEcho")
	echo.set_process(false)
	var status := _target.get_node_or_null("StatusReadout") as Label3D
	var body_meshes: Array[MeshInstance3D] = []
	var full_colors: Array[Color] = []
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		# Inactive weapon effects (such as Mekatana's BladeTrail) are hidden
		# presentation nodes; only meshes actually rendered need an alpha fade.
		if (mesh as MeshInstance3D).is_visible_in_tree() and material != null and material.albedo_color.a > 0.05:
			body_meshes.append(mesh)
			full_colors.append(material.albedo_color)
	_check(rig.visible and is_equal_approx(float(_target.call("get_presentation_visibility_weight")), 1.0), "inner vision keeps the opponent fully rendered")
	_target.global_position = Vector3(18.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	var halo_opacity := float(_target.call("get_presentation_visibility_weight"))
	var counts: Dictionary = fade.call("get_debug_counts")
	_check(rig.visible and halo_opacity >= 0.24 and halo_opacity < 1.0, "outer halo retains a readable body silhouette")
	_check(float(counts.silhouette) > 0.0 and is_equal_approx(float(counts.detail_opacity), 0.25), "halo dims body silhouette and separately suppresses readable details")
	var faded := not body_meshes.is_empty()
	var darkened := false
	for index in range(body_meshes.size()):
		var material := body_meshes[index].get_active_material(0) as BaseMaterial3D
		faded = faded and is_equal_approx(material.albedo_color.a, full_colors[index].a * halo_opacity)
		darkened = darkened or material.albedo_color.get_luminance() < full_colors[index].get_luminance() * 0.9
	_check(faded and darkened, "opponent body and weapons become a darker translucent silhouette")
	_check(status != null and is_equal_approx(status.modulate.a, 0.25), "status details fade faster than the body in the halo")
	_target.global_position = Vector3(20.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	_check(float(_target.call("get_presentation_visibility_weight")) >= 0.24, "silhouette stays legible up to the outer fringe")
	_target.global_position = Vector3(21.99, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	var fringe_opacity := float(_target.call("get_presentation_visibility_weight"))
	_check(fringe_opacity > 0.0 and fringe_opacity < 0.0001 and rig.visible, "final two-unit fringe smoothly removes the silhouette before the exact boundary")
	var fringe_alpha_ok := true
	for mesh in body_meshes:
		var material := mesh.get_active_material(0) as BaseMaterial3D
		fringe_alpha_ok = fringe_alpha_ok and material.albedo_color.a <= 0.0001
	_check(fringe_alpha_ok and (not status.visible or status.modulate.a <= 0.0001), "body, weapons and labels never flash opaque at the hidden boundary")
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	_check(not bool((echo.call("get_debug_state") as Dictionary).visible), "settled deterministic updates do not leave a stale visual echo")
	for node_name in ["VisualRoot", "TargetHealthReadout", "StatusReadout", "JavelinMark"]:
		var presentation := _target.get_node_or_null(node_name) as Node3D
		if presentation != null:
			_check(not presentation.visible, "fully hidden live opponent never leaks through %s" % node_name)
	var status_vfx := _target.get("_status_vfx") as Node3D
	_check(status_vfx != null and not status_vfx.visible, "fully hidden live opponent never leaks through attached status effects")
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	var restored := not body_meshes.is_empty()
	for index in range(body_meshes.size()):
		var material := body_meshes[index].get_active_material(0) as BaseMaterial3D
		restored = restored and material.albedo_color.is_equal_approx(full_colors[index]) and is_zero_approx(body_meshes[index].transparency)
	_check(restored, "reentering inner vision restores original body color and opacity")
	_target.global_position = Vector3(18.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.016)
	var moving_opacity := float(_target.call("get_presentation_visibility_weight"))
	_check(moving_opacity > halo_opacity and moving_opacity < 1.0, "live halo transition eases body opacity over time")
	_check(is_equal_approx(float(_target.call("get_visibility_weight", _player)), 0.5), "presentation easing never changes raw gameplay sensing")
	_target.call("_update_visibility_presentation", 0.0)
	var last_seen := _target.global_position
	_target.global_position = Vector3(24.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.016)
	var echo_state: Dictionary = echo.call("get_debug_state")
	_check(not rig.visible and bool(echo_state.visible) and float(echo_state.opacity) > 0.0, "vision loss hides the live model and leaves a short faint echo")
	_check(Vector3(echo_state.position).is_equal_approx(last_seen), "echo begins at the last actually observed location")
	_target.global_position = Vector3(-24.0, 0.0, 8.0)
	_target.call("_update_visibility_presentation", 0.05)
	echo.call("_process", 0.20)
	var fading_echo: Dictionary = echo.call("get_debug_state")
	_check(Vector3(fading_echo.position).is_equal_approx(last_seen) and float(fading_echo.opacity) < float(echo_state.opacity), "hidden movement never moves the frozen echo while it fades")
	echo.call("_process", 0.40)
	_check(not bool((echo.call("get_debug_state") as Dictionary).visible), "frozen echo expires after its 0.55-second presentation window")
	_target.global_position = Vector3(18.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	var counts_before: Dictionary = fade.call("get_debug_counts")
	var readout := _target.get_node("TargetHealthReadout")
	readout.call("show_damage", 40.0)
	var popup := readout.get("_latest_popup") as Node3D
	_check(popup != null, "damage produces a late-created world popup")
	if popup != null:
		popup.set_process(false)
		popup.call("_process", 0.1)
		fade.call("_process", 0.0)
		var number := popup.get("_label") as Label3D
		var ghost := popup.get("_ghost") as Label3D
		_check(is_equal_approx(number.modulate.a, 0.25) and is_equal_approx(ghost.modulate.a, 0.095), "late-created damage popup and ghost inherit the halo detail fade")
		_check(is_equal_approx(number.outline_modulate.a, 0.25), "damage number outlines inherit the halo detail fade")
		fade.call("restore")
		popup.call("_process", 0.44)
		fade.call("_process", 0.0)
		_check(is_equal_approx(number.modulate.a, 0.125) and is_equal_approx(ghost.modulate.a, 0.0475), "popup lifetime and halo detail alpha compose without restoring expired opacity")
		var counts_after: Dictionary = fade.call("get_debug_counts")
		_check(int(counts_after.visuals) >= int(counts_before.visuals) + 2, "fade cache picks up dynamically-created damage labels")
	var vfx := _scene.get_node("VFXManager")
	var shared_hit: BaseMaterial3D = vfx.get("_hit_materials")[0]
	var shared_alpha := shared_hit.albedo_color.a
	fade.call("restore")
	vfx.call("hit_flash", rig)
	fade.call("_process", 0.0)
	var overlay_ok := not body_meshes.is_empty()
	for mesh in body_meshes:
		var overlay := mesh.material_overlay as BaseMaterial3D
		overlay_ok = overlay_ok and overlay != null and overlay != shared_hit and overlay.albedo_color.a > 0.0 and overlay.albedo_color.a < shared_alpha
	_check(overlay_ok and is_equal_approx(shared_hit.albedo_color.a, shared_alpha), "hit flashes dim privately without changing shared VFX materials")
	fade.call("restore")
	vfx.call("_process", 0.2)
	fade.call("_process", 0.0)
	var overlay_expired := true
	for mesh in body_meshes:
		overlay_expired = overlay_expired and mesh.material_overlay == null
	_check(overlay_expired, "expired hit overlays do not reappear under the fade helper")
	_target.call("reset_combat_state")
	_check(not bool((echo.call("get_debug_state") as Dictionary).visible), "reset clears any silhouette left from the previous round")


func _test_echo_pose_and_pause() -> void:
	var rig := _target.get_node("VisualRoot") as Node3D
	var echo := _target.get_node("VisibilityEcho")
	var source_skeleton := rig.get("skeleton") as Skeleton3D
	var weapon_socket := rig.get("weapon_socket") as Node3D
	var source_weapon: MeshInstance3D
	if weapon_socket != null:
		for mesh: MeshInstance3D in weapon_socket.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh != null:
				source_weapon = mesh
				break
	var snapshot_skeleton: Skeleton3D
	var snapshot_weapon: MeshInstance3D
	for record: Dictionary in echo.get("_skeletons"):
		if record.source.get_ref() == source_skeleton:
			snapshot_skeleton = record.snapshot
	for record: Dictionary in echo.get("_meshes"):
		if record.source.get_ref() == source_weapon:
			snapshot_weapon = record.snapshot
	var bone := source_skeleton.find_bone("mixamorig_RightHand") if source_skeleton != null else -1
	_check(source_skeleton != null and snapshot_skeleton != null and source_weapon != null and snapshot_weapon != null and bone >= 0, "echo contains the live droid skeleton and equipped weapon snapshots")
	if snapshot_skeleton == null or snapshot_weapon == null or bone < 0:
		return
	_player.global_position = Vector3.ZERO
	_player.call("set_gameplay_enabled", true)
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.0)
	var saved_target_transform := _target.global_transform
	var saved_pose := source_skeleton.get_bone_pose(bone)
	var saved_socket_transform := weapon_socket.transform
	var frozen_pose := snapshot_skeleton.get_bone_pose(bone)
	var frozen_skeleton_transform := snapshot_skeleton.global_transform
	var frozen_weapon_transform := snapshot_weapon.global_transform
	_check(frozen_pose.is_equal_approx(saved_pose) and frozen_weapon_transform.is_equal_approx(source_weapon.global_transform), "echo samples the actual observed bone pose and weapon transform")
	_target.global_position = Vector3(24.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.016)
	var hidden_pose := saved_pose
	hidden_pose.basis = hidden_pose.basis.rotated(Vector3.UP, 0.45)
	source_skeleton.set_bone_pose(bone, hidden_pose)
	source_skeleton.force_update_all_bone_transforms()
	weapon_socket.position += Vector3(0.6, 0.2, 0.4)
	_target.rotate_y(0.8)
	_target.global_position = Vector3(-24.0, 0.0, 8.0)
	_target.call("_update_visibility_presentation", 0.016)
	_check(not source_skeleton.get_bone_pose(bone).is_equal_approx(frozen_pose) and snapshot_skeleton.get_bone_pose(bone).is_equal_approx(frozen_pose) and snapshot_skeleton.global_transform.is_equal_approx(frozen_skeleton_transform), "hidden bone animation and actor rotation never update the frozen skeleton")
	_check(not source_weapon.global_transform.is_equal_approx(frozen_weapon_transform) and snapshot_weapon.global_transform.is_equal_approx(frozen_weapon_transform), "hidden weapon movement never updates the observed weapon snapshot")
	echo.set_process(true)
	paused = true
	var before_pause: Dictionary = echo.call("get_debug_state")
	for _frame in range(3):
		await process_frame
	var during_pause: Dictionary = echo.call("get_debug_state")
	_check(bool(during_pause.visible) and is_equal_approx(float(during_pause.remaining), float(before_pause.remaining)), "actual SceneTree pause suspends the echo lifetime")
	paused = false
	for _frame in range(3):
		await process_frame
	var after_resume: Dictionary = echo.call("get_debug_state")
	_check(float(after_resume.remaining) < float(during_pause.remaining), "resuming SceneTree processing resumes the echo fade")
	echo.set_process(false)
	source_skeleton.set_bone_pose(bone, saved_pose)
	source_skeleton.force_update_all_bone_transforms()
	weapon_socket.transform = saved_socket_transform
	_target.global_transform = saved_target_transform
	_target.call("reset_combat_state")


func _test_echo_gameplay_gate() -> void:
	var echo := _target.get_node("VisibilityEcho")
	echo.set_process(false)
	_player.global_position = Vector3.ZERO
	for mode in ["menu", "menu_showcase", "countdown"]:
		_target.call("reset_combat_state")
		_scene.set("duel_active", mode == "countdown")
		_player.call("set_gameplay_enabled", mode == "menu_showcase")
		_target.global_position = Vector3(14.0, 0.0, 0.0)
		_target.call("_update_visibility_presentation", 0.016)
		_scene.set("duel_active", true)
		_player.call("set_gameplay_enabled", true)
		_target.global_position = Vector3(24.0, 0.0, 0.0)
		_target.call("_update_visibility_presentation", 0.016)
		_check(not bool((echo.call("get_debug_state") as Dictionary).visible), "%s preview cannot prime a stale echo when gameplay starts with an unseen target" % mode)
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.016)
	_target.global_position = Vector3(24.0, 0.0, 0.0)
	_target.call("_update_visibility_presentation", 0.016)
	_check(bool((echo.call("get_debug_state") as Dictionary).visible), "normal live sight followed by loss still produces the frozen echo")
	_target.call("reset_combat_state")


func _test_bot_perception() -> void:
	_player.global_position = Vector3.ZERO
	_target.global_position = Vector3(18.0, 0.0, 0.0)
	_check(is_equal_approx(float(_player.call("get_visibility_weight", _target)), 0.5), "bot gets the same half-opacity vision inside its fade band")
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	_player.call("_mark_combat_event")
	_player.call("apply_spotted", 5.0, "test")
	var visible := bool(_player.call("is_visible_to", _target))
	_bot.call("reset_clock")
	_bot.call("_update_duel_perception", _target, _player, visible)
	var perception: Dictionary = _bot.get("_perception")
	_check(not bool(perception.get("raw_visible", true)) and not bool(perception.get("known", true)), "bot does not acquire revealed player positions outside its radius")
	_check(not bool(_bot.call("_can_attack", _target, _player)), "bot rejects attacks on a player outside its vision")
	_player.call("reset_combat_state")


func _test_tracking() -> void:
	_player.global_position = Vector3.ZERO
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	_tracker.call("reset_tracking")
	_tracker.call("_process", 0.1)
	var state: Dictionary = _tracker.call("get_tracking_state")
	_check(not bool(state.known), "unseen enemy has no minimap location")
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_tracker.call("_process", 0.1)
	state = _tracker.call("get_tracking_state")
	_check(bool(state.known) and bool(state.visible) and Vector3(state.last_position).is_equal_approx(_target.global_position), "visible enemy records a fresh minimap position")
	var seen_position: Vector3 = state.last_position
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	_tracker.call("_process", 0.4)
	state = _tracker.call("get_tracking_state")
	_check(bool(state.known) and not bool(state.visible) and Vector3(state.last_position).is_equal_approx(seen_position), "vision loss displays only the last observed location")
	_target.global_position = Vector3(-24.0, 0.0, 9.0)
	_tracker.call("_process", 0.6)
	state = _tracker.call("get_tracking_state")
	_check(Vector3(state.last_position).is_equal_approx(seen_position) and float(state.age) >= 0.9, "hidden movement does not move the marker and memory grows older")
	var age_before_pause := float(state.age)
	paused = true
	_tracker.call("_process", 2.0)
	state = _tracker.call("get_tracking_state")
	_check(is_equal_approx(float(state.age), age_before_pause), "pause freezes sight memory age")
	var panel := _tracker.get_node_or_null("SightPanel") as Control
	_check(panel != null and not panel.visible, "pause hides the tracking HUD")
	paused = false
	_tracker.call("_process", float(state.expires_after) + 0.1)
	state = _tracker.call("get_tracking_state")
	_check(not bool(state.known), "stale last-known location disappears after its memory window")
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_tracker.call("_process", 0.1)
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	_tracker.call("_process", 0.1)
	_target.call("reset_combat_state")
	_tracker.call("_process", 0.1)
	state = _tracker.call("get_tracking_state")
	_check(not bool(state.known), "opponent reset epoch clears last-round tracking")
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_tracker.call("_process", 0.1)
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	_tracker.call("_process", 0.1)
	_player.call("reset_combat_state")
	_tracker.call("_process", 0.1)
	state = _tracker.call("get_tracking_state")
	_check(not bool(state.known), "player reset epoch also clears last-round tracking")
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_tracker.call("_process", 0.1)
	_scene.set("duel_active", false)
	_player.call("set_gameplay_enabled", false)
	_tracker.call("_process", 0.1)
	state = _tracker.call("get_tracking_state")
	_check(not bool(state.known) and not bool(state.active), "returning to the menu clears tracking and hides its HUD")
	_player.call("set_gameplay_enabled", true)
	_target.set("network_proxy", true)
	_target.global_position = Vector3(14.0, 0.0, 0.0)
	_tracker.call("_process", 0.1)
	state = _tracker.call("get_tracking_state")
	_check(bool(state.known) and bool(state.active), "network proxy rounds activate the same sight tracker without local duel mode")
	_target.set("network_proxy", false)
	_scene.set("duel_active", true)
	_target.global_position = Vector3(22.0, 0.0, 0.0)
	# Baroud can prevent lethal damage; this fixture exercises a confirmed
	# death rather than the independent temporary survival passive.
	var death_loadout: Dictionary = _target.call("get_duel_loadout")
	death_loadout["passive"] = "omnivamp"
	_target.call("set_duel_loadout", death_loadout)
	_target.call("take_damage", float(_target.call("get_max_health")) * 2.0, "test", "sight_death")
	_tracker.call("_process", 0.1)
	state = _tracker.call("get_tracking_state")
	_check(not bool(state.known), "opponent death clears its last-known marker")
	_target.call("reset_combat_state")


func _test_survival_search() -> void:
	_check(_bot.has_method("_select_survival_search_destination"), "survival enemies have a search destination when a player is outside vision")
	if not _bot.has_method("_select_survival_search_destination"):
		return
	_bot.set("survival_role", "chaser")
	_target.global_position = Vector3(0.0, 0.0, -12.0)
	_player.global_position = Vector3(24.0, 0.0, -18.0)
	_bot.call("reset_clock")
	_bot.set("_next_attack_at", INF)
	_bot.call("_update_survival_bot", _target, _player, 0.0)
	var first_goal: Vector3 = _bot.get("_survival_search_goal")
	_check(not bool(_bot.get("_has_last_observed_position")) and first_goal.distance_to(_target.global_position) > 8.0, "initially unseen survival enemy searches across the arena without acquiring the player")
	_player.global_position = Vector3(-20.0, 0.0, 18.0)
	_bot.call("reset_clock")
	_bot.set("_next_attack_at", INF)
	_bot.call("_update_survival_bot", _target, _player, 0.0)
	var second_goal: Vector3 = _bot.get("_survival_search_goal")
	_check(first_goal.is_equal_approx(second_goal), "survival search is independent of the hidden player's actual location")
	_bot.call("reset_clock")
	_bot.set("_next_attack_at", INF)
	_player.global_position = Vector3(5.0, 0.0, -12.0)
	_bot.call("_update_survival_bot", _target, _player, 0.0)
	var last_seen: Vector3 = _player.global_position
	_check(bool(_bot.get("_has_last_observed_position")), "survival enemy samples the player only while visible")
	_player.global_position = Vector3(20.0, 0.0, 20.0)
	_bot.set("_elapsed", 4.5)
	_bot.call("_update_survival_bot", _target, _player, 0.0)
	_check(not bool(_bot.get("_has_last_observed_position")) and Vector3(_bot.get("_survival_search_goal")).is_equal_approx(last_seen), "survival enemy keeps investigating its observed destination after precise memory expires")
	_bot.call("reset_clock")
	_bot.set("_next_attack_at", INF)
	_target.global_position = Vector3(-16.0, 0.0, 0.0)
	_player.global_position = Vector3(-22.0, 0.0, 0.0)
	_bot.call("_update_survival_bot", _target, _player, 0.0)
	var reachable_edge_goal: Vector3 = _bot.get("_survival_search_goal")
	_check(absf(reachable_edge_goal.x) <= 20.0 and absf(reachable_edge_goal.z) <= 20.0, "survival investigation caches the same reachable boundary used by movement")
	_target.global_position = reachable_edge_goal
	_player.global_position = Vector3(20.0, 0.0, 20.0)
	_bot.set("_elapsed", 4.5)
	_bot.call("_update_survival_bot", _target, _player, 0.0)
	var next_edge_goal: Vector3 = _bot.get("_survival_search_goal")
	_check(next_edge_goal.is_finite() and next_edge_goal.distance_to(reachable_edge_goal) > 1.2, "survival search advances after reaching a clamped map-edge destination")
	_bot.set("survival_role", "")
	_bot.call("reset_clock")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)
		push_error("FAIL: " + label)


func _report() -> void:
	print("SIGHT RANGE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
