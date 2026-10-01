extends SceneTree

const BUSH_STATE := preload("res://scripts/bush_state.gd")
const SESSION := preload("res://scripts/network_session.gd")
const MATCH := preload("res://scripts/network_match.gd")
const NETWORK_PLAYER := preload("res://scripts/network_player.gd")
const CONCEALED_ALPHA_MULTIPLIER := 0.38

class RelayProbe extends Node:
	var sent: Array[Dictionary] = []
	func get_client_id() -> int:
		return 11
	var host_id := 22
	func is_host() -> bool: return host_id == 11
	func get_host() -> int: return host_id
	func get_sender_id() -> int: return host_id
	func call_func_unreliable(callback: Callable, ...parameters: Array) -> void:
		sent.append({"method": str(callback.get_method()), "parameters": parameters})
	func call_func(callback: Callable, ...parameters: Array) -> void:
		sent.append({"method": str(callback.get_method()), "parameters": parameters})

var _failures: Array[String] = []
var _scene: Node3D
var _player: Node3D
var _target: Node3D
var _bot: Node
var _bush: Node3D
var _other_bush: Node3D
var _bush_events: Array[Dictionary] = []
var _heard: Array[String] = []
var _local_materials: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	_player = _scene.get_node_or_null("Player")
	_target = _scene.get_node_or_null("TargetDummy")
	_bot = _target.get_node_or_null("TrainingBot") if _target != null else null
	if _player == null or _target == null or _bot == null:
		_check(false, "real player and bot must initialise")
		_report()
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	_target.set_physics_process(false)
	_target.set_process(false)
	_target.call("set_training_bot_enabled", false)
	_target.call("set_duel_mode", true)
	_capture_local_materials()
	_test_arena_footprints()
	# Keep actual actors, collision queries and presentation. Replace arena
	# placement with two explicit bushes and a wall so visibility is unambiguous.
	for bush in get_nodes_in_group("bush_placeholder"):
		bush.queue_free()
	for child in _scene.get_children():
		if child is StaticBody3D and child != _target:
			child.queue_free()
	for kit in get_nodes_in_group("repair_kits"):
		kit.call("set_collection_active", false)
	await physics_frame
	_bush = _fixture_bush("TestOffsetBush", Vector3(3, 0, 4), Vector3(6, 0, 4), 2.0)
	_other_bush = _fixture_bush("TestOtherBush", Vector3(-6, 0, 4), Vector3(-6, 0, 4), 2.0)
	_player.connect("bush_state_changed", func(inside: bool, bush_name: String) -> void:
		_bush_events.append({"inside": inside, "name": bush_name})
	)
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	await physics_frame
	_test_offset_footprint_and_transitions()
	_test_observer_bush_visibility()
	_test_local_conceal_cue()
	_test_local_material_lifecycle()
	_test_conceal_presentation_and_reveal()
	_test_burn_combat_reveal()
	await _test_same_bush_wall()
	await _test_network_bush_reveal()
	await _test_bush_knowledge_and_search()
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stop()
	# The dummy audio driver releases its active WAV playbacks on a mixer tick.
	await create_timer(0.15).timeout
	# The opacity snapshots own Resource references, including originals that
	# concealment temporarily removed from their mesh slots. Release them before
	# destroying the actors so the shutdown check sees no test-owned materials.
	_local_materials.clear()
	current_scene = null
	_scene.queue_free()
	_scene = null
	_player = null
	_target = null
	_bot = null
	_bush = null
	_other_bush = null
	await process_frame
	_report()


func _test_arena_footprints() -> void:
	var bushes := get_nodes_in_group("bush_placeholder")
	_check(not bushes.is_empty(), "arena exposes playable bushes")
	for node in bushes:
		var bush := node as Node3D
		var foliage: Vector3 = bush.get_meta("bush_visual_position", bush.global_position)
		_check(BUSH_STATE.center(bush).distance_to(foliage) < 0.01, "%s concealment matches its grounded foliage" % bush.name)
		_check(BUSH_STATE.radius(bush) > 0.5, "%s keeps a useful concealment footprint" % bush.name)


func _fixture_bush(node_name: String, at: Vector3, foliage_center: Vector3, footprint: float) -> Node3D:
	var bush := Node3D.new()
	bush.name = node_name
	bush.position = at
	bush.set_meta("bush_center", foliage_center)
	bush.set_meta("bush_radius", footprint)
	bush.add_to_group("bush_placeholder")
	_scene.add_child(bush)
	return bush


func _fixture_wall(node_name: String, at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = node_name
	wall.position = at
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	collision.shape = box
	wall.add_child(collision)
	_scene.add_child(wall)
	return wall


func _test_offset_footprint_and_transitions() -> void:
	var center := BUSH_STATE.center(_bush)
	_player.global_position = _bush.global_position
	_target.global_position = _bush.global_position
	_check(not bool(_player.call("is_in_bush")) and not bool(_target.call("is_in_bush")), "authored origin outside offset foliage does not provide invisible cover")
	_bush_events.clear()
	_player.global_position = center
	_target.global_position = center
	_check(bool(_player.call("is_in_bush")) and bool(_target.call("is_in_bush")), "player and bot enter the actual foliage footprint")
	_check(str(_player.call("get_current_bush_name")) == str(_bush.name), "player reports the entered bush identity")
	_check(_bush_events.size() == 1 and bool(_bush_events[0].inside), "entry emits a single usable concealment transition")
	_player.global_position = center + Vector3.RIGHT * 1.0
	_player.call("is_in_bush")
	_player.call("is_in_bush")
	_check(_bush_events.size() == 1, "movement inside the same bush does not replay its entry transition")
	_player.global_position = center + Vector3.RIGHT * 2.0
	_check(bool(_player.call("is_in_bush")), "footprint edge still belongs to the visible foliage")
	_player.global_position = center + Vector3.RIGHT * 2.03
	_check(not bool(_player.call("is_in_bush")), "stepping outside the foliage removes concealment immediately")
	_check(_bush_events.size() == 2 and not bool(_bush_events[1].inside), "exit emits one concealment transition")


func _test_observer_bush_visibility() -> void:
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	_player.global_position = BUSH_STATE.center(_bush)
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 5.0
	_check(not bool(_player.call("is_visible_to", _target)), "outside enemy cannot see an out-of-combat player in a bush")
	_check(bool(_player.call("is_visible_to", _player)), "concealment never hides the local player from itself")
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.RIGHT * 0.8
	_check(bool(_player.call("is_visible_to", _target)) and bool(_target.call("is_visible_to", _player)), "opponents entering the same bush see one another")
	_target.global_position = BUSH_STATE.center(_other_bush)
	_check(not bool(_player.call("is_visible_to", _target)) and not bool(_target.call("is_visible_to", _player)), "a different bush does not grant vision into the target bush")
	_player.global_position = BUSH_STATE.center(_bush) + Vector3.BACK * 5.0
	_check(not bool(_target.call("is_visible_to", _player)), "leaving a bush loses vision of an enemy that stayed concealed")


func _test_local_conceal_cue() -> void:
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	var sfx := root.get_node("GameSfx")
	sfx.call("clear")
	sfx.connect("event_played", func(event_id: String) -> void: _heard.append(event_id))
	_player.call("set_gameplay_enabled", true)
	_player.global_position = BUSH_STATE.center(_bush)
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 5.0
	_player.call("_update_bush_state", 0.0)
	var cue := _player.get("_bush_status_label") as Label3D
	_check(cue != null, "local concealment has a readable player cue")
	if cue == null:
		return
	_check(cue.visible and cue.text == "CAMOUFLÉ", "local cue reports that the player is concealed")
	_check_local_opacity(true, "entering concealed foliage")
	var concealed_materials: Array[Material] = []
	for records in _local_materials.values():
		for record in records:
			concealed_materials.append(record.mesh.get_active_material(record.surface))
	_player.call("_update_bush_state", 0.0)
	var unchanged_materials := true
	var material_index := 0
	for records in _local_materials.values():
		for record in records:
			unchanged_materials = unchanged_materials and record.mesh.get_active_material(record.surface) == concealed_materials[material_index]
			material_index += 1
	_check(unchanged_materials, "remaining concealed reuses the existing translucent materials")
	_player.call("set_weapon", "shotgun")
	_check(_player.get("_shotgun_pivot").visible, "shotgun can become the equipped weapon while concealed")
	_check_local_opacity(true, "switching to shotgun while concealed")
	_player.call("set_weapon", "blaster")
	_check(_heard == ["bush_entry"], "entering foliage plays the local entry feedback once")
	_player.call("_mark_combat_event")
	_check_local_opacity(false, "immediate combat reveal")
	_player.call("_update_bush_state", 0.0)
	_check(cue.visible and cue.text.begins_with("RÉVÉLÉ"), "local cue distinguishes active combat reveal from concealment")
	_player.get("visibility_state").update(3.01)
	_player.call("_update_bush_state", 0.0)
	_check_local_opacity(true, "combat reveal expiry inside foliage")
	_player.call("apply_spotted", 0.5, "bush_test")
	_check_local_opacity(false, "immediate SPOTTED reveal")
	_player.get("visibility_state").update(0.51)
	_player.call("_update_bush_state", 0.0)
	_check_local_opacity(true, "SPOTTED expiry inside foliage")
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.RIGHT
	_target.call("is_in_bush")
	_player.call("_update_bush_state", 0.0)
	_check(cue.visible and cue.text == "DÉTECTÉ", "local cue warns that an enemy shares the bush")
	_check_local_opacity(false, "visible enemy sharing the bush")
	_check(_heard == ["bush_entry"], "an enemy moving inside foliage does not play location-revealing bush sounds")
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 5.0
	_player.call("_update_bush_state", 0.0)
	_check_local_opacity(true, "shared-bush enemy leaving the foliage")
	# The selected feedback shares the collaborator's 650 ms transition limiter.
	# Advance only that fixture clock before checking the next audible exit.
	sfx.set("_bush_transition_ms", Time.get_ticks_msec() - 650)
	_player.global_position = BUSH_STATE.center(_bush) + Vector3.BACK * 5.0
	_player.call("_update_bush_state", 0.0)
	_check(not cue.visible, "local concealment cue disappears on exiting the foliage")
	_check_local_opacity(false, "exiting foliage")
	_check(_heard == ["bush_entry", "bush_exit"], "exiting foliage plays local exit feedback once")
	_player.global_position = BUSH_STATE.center(_bush)
	_player.call("_update_bush_state", 0.0)
	_player.call("set_gameplay_enabled", false)
	_check(not cue.visible, "local concealment cue disappears when gameplay is disabled")
	_check_local_opacity(false, "gameplay disabled inside foliage")


func _capture_local_materials() -> void:
	var rig := _player.get_node("VisualRoot")
	var blaster := _player.get("_blaster_pivot") as Node3D
	var shotgun := _player.get("_shotgun_pivot") as Node3D
	var charge_visual := _player.get("_blaster_charge_visual") as Node3D
	_local_materials = {"body": [], "blaster": [], "shotgun": []}
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		# The charge glow animates its own alpha during attack tests. Snapshot
		# the robot and weapon surfaces, whose source colors are stable.
		if mesh.mesh == null or (charge_visual != null and charge_visual.is_ancestor_of(mesh)):
			continue
		var group := "body"
		if blaster.is_ancestor_of(mesh):
			group = "blaster"
		elif shotgun.is_ancestor_of(mesh):
			group = "shotgun"
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			_local_materials[group].append({
				"mesh": mesh,
				"surface": surface,
				"material": material,
				"alpha": material.albedo_color.a,
				"transparency": material.transparency,
				"override": mesh.material_override,
				"surface_override": mesh.get_surface_override_material(surface),
			})
	for group in _local_materials:
		_check(not _local_materials[group].is_empty(), "local %s exposes actual mesh materials for opacity checks" % group)


func _check_local_opacity(concealed: bool, context: String) -> void:
	for group in _local_materials:
		var correct_opacity := true
		var sources_unchanged := true
		var overrides_restored := true
		for record in _local_materials[group]:
			var active := record.mesh.get_active_material(record.surface) as BaseMaterial3D
			var original := record.material as BaseMaterial3D
			sources_unchanged = sources_unchanged and is_equal_approx(original.albedo_color.a, record.alpha) and original.transparency == record.transparency
			if concealed:
				correct_opacity = correct_opacity and active != null and active != original and active.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and is_equal_approx(active.albedo_color.a, float(record.alpha) * CONCEALED_ALPHA_MULTIPLIER)
			else:
				correct_opacity = correct_opacity and active == original
				overrides_restored = overrides_restored and record.mesh.material_override == record.override and record.mesh.get_surface_override_material(record.surface) == record.surface_override
		_check(correct_opacity, "%s: local %s is %s" % [context, group, "translucent" if concealed else "restored to its original material"])
		_check(sources_unchanged, "%s: local %s source materials stay untouched" % [context, group])
		if not concealed:
			_check(overrides_restored, "%s: local %s restores the original override slots" % [context, group])


func _test_local_material_lifecycle() -> void:
	_player.global_position = BUSH_STATE.center(_bush)
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 5.0
	_player.call("reset_combat_state")
	_check_local_opacity(false, "reset while gameplay is disabled")
	_player.call("set_gameplay_enabled", true)
	_check_local_opacity(true, "gameplay resumed inside foliage")
	_player.call("_mark_combat_event")
	_player.call("reset_combat_state")
	_check_local_opacity(true, "combat reset clears reveal inside foliage")
	var passive_id := str(_player.call("get_passive_id"))
	_player.call("set_passive", "")
	_player.call("take_damage", float(_player.call("get_health")), "bush_test", "bush_test_death")
	_check(bool(_player.call("is_real_dead")), "lethal damage reaches actual death in the opacity lifecycle check")
	_check_local_opacity(false, "death inside foliage")
	_player.call("set_passive", passive_id)
	_player.call("reset_combat_state")
	_check_local_opacity(false, "reset after death while gameplay remains disabled")
	_player.call("set_gameplay_enabled", true)
	_check_local_opacity(true, "new life can conceal in the same foliage")
	_player.call("set_gameplay_enabled", false)


func _test_conceal_presentation_and_reveal() -> void:
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	_player.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 5.0
	_target.global_position = BUSH_STATE.center(_bush)
	_target.call("apply_slow", 1.0, 30.0, "bush_test")
	_target.call("apply_javelin_mark", 1.0, "bush_test")
	_check(bool(_target.call("is_visible_to", _player)), "Javelin's SPOTTED mark reveals its target in foliage")
	_target.call("clear_javelin_mark")
	_target.get("visibility_state").update(1.01)
	_target.call("_update_visibility_presentation")
	for node_name in ["VisualRoot", "TargetHealthReadout", "StatusReadout", "JavelinMark"]:
		var node := _target.get_node_or_null(node_name) as Node3D
		_check(node != null and not node.visible, "hidden enemy suppresses %s and its location" % node_name)
	var status_vfx := _target.get("_status_vfx") as Node3D
	_check(status_vfx != null and not status_vfx.visible, "hidden enemy suppresses status markers")
	_target.call("apply_spotted", 0.5, "bush_test")
	_target.call("_update_visibility_presentation")
	_check(bool(_target.call("is_visible_to", _player)) and _target.get_node("VisualRoot").visible, "SPOTTED reveals the enemy and its presentation in foliage")
	_check(float(_target.call("get_combat_reveal_remaining")) <= 0.0, "SPOTTED remains independent of combat reveal")
	_target.get("visibility_state").update(0.51)
	_check(not bool(_target.call("is_visible_to", _player)), "SPOTTED expiry restores concealment without leaving the bush")
	_target.call("take_damage", 1.0, "bush_test", "bush_damage_reveal")
	_check(bool(_target.call("is_visible_to", _player)), "a hit reveals the concealed enemy")
	_target.get("visibility_state").update(2.95)
	_check(bool(_target.call("is_visible_to", _player)), "combat reveal lasts for the existing three-second combat window")
	_target.get("visibility_state").update(0.06)
	_check(not bool(_target.call("is_visible_to", _player)), "combat expiry conceals the enemy again inside foliage")
	_player.global_position = BUSH_STATE.center(_bush)
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 5.0
	_player.call("set_gameplay_enabled", true)
	_player.call("_begin_blaster_charge")
	_player.call("_cancel_blaster_charge")
	_check(bool(_player.call("is_visible_to", _target)), "committing an attack reveals a concealed player even before projectile release")
	_player.get("visibility_state").update(3.01)
	_check(not bool(_player.call("is_visible_to", _target)), "the attacking player becomes concealed again after combat ends")


func _test_burn_combat_reveal() -> void:
	for actor in [_player, _target]:
		_player.call("reset_combat_state")
		_target.call("reset_combat_state")
		var enemy := _target if actor == _player else _player
		actor.global_position = BUSH_STATE.center(_bush)
		enemy.global_position = BUSH_STATE.center(_other_bush)
		var source := "duel_bot:bush_test" if actor == _player else "player:bush_test"
		actor.call("apply_burn", 4.0, 2.0, source)
		for tick in range(4):
			actor.get("visibility_state").update(1.0)
			enemy.get("visibility_state").update(1.0)
			actor.get("combat_state").update(1.0)
			_check(bool(actor.call("is_visible_to", enemy)), "%s BURN damage tick %d maintains combat reveal in foliage" % [actor.name, tick + 1])
			_check(bool(enemy.call("is_visible_to", actor)), "%s dealing BURN tick %d maintains the attacker's combat reveal" % [enemy.name, tick + 1])
		actor.get("visibility_state").update(3.01)
		enemy.get("visibility_state").update(3.01)
		_check(not bool(actor.call("is_visible_to", enemy)), "%s can conceal again after the last BURN tick's combat window" % actor.name)
		_check(not bool(enemy.call("is_visible_to", actor)), "%s attacker can conceal again after its last BURN damage" % enemy.name)


func _test_same_bush_wall() -> void:
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	var center := BUSH_STATE.center(_bush)
	_player.global_position = center + Vector3.LEFT * 0.8
	_target.global_position = center + Vector3.RIGHT * 0.8
	var wall := _fixture_wall("TestSharedBushWall", center + Vector3.UP, Vector3(0.15, 2.0, 3.0))
	await physics_frame
	_check(not bool(_player.call("is_visible_to", _target)) and not bool(_target.call("is_visible_to", _player)), "sharing foliage still respects an intervening wall when neither actor is revealed")
	_player.call("set_gameplay_enabled", true)
	_player.call("_update_bush_state", 0.0)
	_check_local_opacity(true, "shared-bush enemy occluded by a wall")
	_target.call("apply_spotted", 0.5, "bush_test")
	_check(not bool(_target.call("is_visible_to", _player)), "SPOTTED reveals foliage only when the wall does not obstruct line of sight")
	_target.call("reset_combat_state")
	_target.call("mark_combat_event")
	_check(not bool(_target.call("is_visible_to", _player)), "combat reveal cannot expose a bush occupant through a solid wall")
	_target.call("apply_spotted", 0.5, "bush_test")
	_check(not bool(_target.call("is_visible_to", _player)), "combined combat and SPOTTED reveal still cannot bypass a bush wall")
	_player.call("_mark_combat_event")
	_player.call("apply_spotted", 0.5, "bush_test")
	_check(not bool(_player.call("is_visible_to", _target)), "the concealed player obeys strict wall occlusion even during combat and SPOTTED")
	_target.call("_update_visibility_presentation")
	for node_name in ["VisualRoot", "TargetHealthReadout", "StatusReadout", "JavelinMark"]:
		var presentation := _target.get_node_or_null(node_name) as Node3D
		_check(presentation != null and not presentation.visible, "%s remains hidden behind a wall despite an active bush reveal" % node_name)
	wall.queue_free()
	await physics_frame
	_check(bool(_target.call("is_visible_to", _player)) and bool(_player.call("is_visible_to", _target)), "revealed bush occupants become visible again as soon as their line of sight clears")


func _test_network_bush_reveal() -> void:
	# True human replicas use host combat snapshots, including independent
	# reveal clocks. They share the same physical bush/wall visibility rules.
	var relay := RelayProbe.new()
	root.add_child(relay)
	var session := SESSION.new()
	root.add_child(session)
	session._service = relay
	session.current_room = {"host_id": 22, "guest_id": 11}
	session._match_token = "bush-visibility-fixture"
	session._round_number = 1
	session._phase = "live"
	var local := CharacterBody3D.new()
	local.set_script(NETWORK_PLAYER)
	local.set("authoritative", false)
	local.set("peer_id", 11)
	_scene.add_child(local)
	var remote := CharacterBody3D.new()
	remote.set_script(NETWORK_PLAYER)
	remote.set("authoritative", false)
	remote.set("remote_controlled", true)
	remote.set("peer_id", 22)
	_scene.add_child(remote)
	local.set("opponent", remote)
	remote.set("opponent", local)
	for actor in [local, remote]:
		actor.call("set_gameplay_enabled", true)
		actor.set_process(false)
		actor.set_physics_process(false)
	local.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 5.0
	remote.global_position = BUSH_STATE.center(_bush)
	var controller := MATCH.new()
	root.add_child(controller)
	controller.set_process(false)
	controller.set_physics_process(false)
	controller._player = local
	controller._target = remote
	controller._session = session
	controller._host_id = 22
	controller._guest_id = 11
	controller._phase = "live"
	session.combat_received.connect(controller._on_combat_received)
	var received_states: Array[Dictionary] = []
	session.combat_received.connect(func(value: Dictionary) -> void: received_states.append(value))
	_send_network_bush_snapshot(session, local, remote, 1, 0.0, 0.0)
	remote.call("update_remote_visibility")
	_check(received_states.size() == 1 and not bool(remote.call("is_visible_to", local)), "a confirmed human snapshot does not invent combat reveal")
	_check(not remote.get("_health_readout").is_visible_in_tree(), "network HUD does not expose health changes of an unseen opponent")
	_send_network_bush_snapshot(session, local, remote, 2, 2.8, 0.0)
	remote.call("update_remote_visibility")
	_check(bool(remote.call("is_visible_to", local)), "remote attack snapshot reveals the opponent inside a bush")
	_check(remote.get("_health_readout").is_visible_in_tree(), "network HUD restores opponent health when revealed")
	remote.get("visibility_state").update(2.81)
	_check(not bool(remote.call("is_visible_to", local)), "remote combat reveal expires back into concealment")
	_send_network_bush_snapshot(session, local, remote, 3, 0.0, 1.2)
	_check(bool(remote.call("is_visible_to", local)) and is_zero_approx(float(remote.call("get_combat_reveal_remaining"))), "remote SPOTTED reveals without manufacturing combat")
	var wall_position := remote.global_position.lerp(local.global_position, 0.5) + Vector3.UP
	var wall := _fixture_wall("TestNetworkVisibilityWall", wall_position, Vector3(2.0, 2.0, 0.15))
	await physics_frame
	remote.call("update_remote_visibility")
	_check(not bool(remote.call("is_visible_to", local)), "remote SPOTTED snapshot cannot reveal its bush occupant through a wall")
	for property_name in ["_robot_visuals", "_world_ui_anchor", "_status_vfx"]:
		var presentation := remote.get(property_name) as Node3D
		_check(presentation != null and not presentation.visible, "network %s respects wall occlusion despite transmitted SPOTTED" % property_name)
	_check(not remote.get("_health_readout").is_visible_in_tree(), "network HUD withholds opponent health behind a wall even while SPOTTED")
	_send_network_bush_snapshot(session, local, remote, 4, 2.8, 0.0)
	_check(not bool(remote.call("is_visible_to", local)), "remote combat snapshot cannot reveal its bush occupant through a wall")
	wall.queue_free()
	await physics_frame
	remote.call("update_remote_visibility")
	_check(bool(remote.call("is_visible_to", local)) and remote.get("_robot_visuals").visible, "remote combat reveal and enemy model return when line of sight becomes clear")
	_check(remote.get("_health_readout").is_visible_in_tree(), "network opponent health returns with line of sight while its reveal timer remains active")
	_send_network_bush_snapshot(session, local, remote, 2, 0.0, 0.0)
	_check(bool(remote.call("is_visible_to", local)), "an older network sequence cannot erase the latest confirmed reveal")
	local.call("_mark_combat_event")
	local.get("visibility_state").mark_spotted(1.0)
	relay.host_id = 11
	session.current_room = {"host_id": 11, "guest_id": 22}
	controller._host_id = 11
	controller._guest_id = 22
	controller.call("_publish_snapshot", true)
	_check(relay.sent.size() == 1, "host publishes one coherent combat snapshot")
	if relay.sent.size() == 1:
		var arguments: Array = relay.sent[0].parameters
		_check(arguments.size() == 1 and arguments[0] is PackedByteArray, "authoritative snapshot uses the compressed relay packet")
		if arguments.size() == 1 and arguments[0] is PackedByteArray:
			var packet: Dictionary = bytes_to_var(arguments[0].decompress_dynamic(32768, FileAccess.COMPRESSION_DEFLATE))
			var reveal: Dictionary = packet.host
			_check(is_equal_approx(float(reveal.reveal), 3.0) and is_equal_approx(float(reveal.spotted), 1.0), "snapshot transmits the local combat and SPOTTED clocks independently")
	controller._cleanup_done = true
	controller.queue_free()
	local.queue_free()
	remote.queue_free()
	session.queue_free()
	relay.queue_free()
	await process_frame


func _send_network_bush_snapshot(session: Node, local: Node3D, remote: Node3D, sequence: int, combat: float, spotted: float) -> void:
	var host: Dictionary = remote.call("network_snapshot")
	host.reveal = combat
	host.spotted = spotted
	var packet := {"host": host, "guest": local.call("network_snapshot"), "ack": 0,
		"sequence": sequence, "token": session.get("_match_token"), "round": session.get("_round_number")}
	session.call("_remote_combat", var_to_bytes(packet).compress(FileAccess.COMPRESSION_DEFLATE))


func _test_bush_knowledge_and_search() -> void:
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	_bot.call("set_difficulty_profile", "normal")
	_bot.call("reset_clock")
	_bot.get("_navigation").invalidate(true)
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 6.0
	var entrance := BUSH_STATE.center(_bush) + Vector3.RIGHT * 1.2
	_player.global_position = entrance
	_player.call("_mark_combat_event")
	for observed_at in [0.0, 0.30]:
		_bot.set("_elapsed", observed_at)
		_bot.call("_observe_bush_knowledge", _target, _player, true)
		_bot.call("_update_duel_perception", _target, _player, true)
	var remembered: Vector3 = _bot.get("_last_observed_position")
	_check(remembered.is_equal_approx(entrance), "bot first acquires an actually visible bush occupant after reaction delay")
	_player.get("visibility_state").update(3.01)
	_player.global_position = BUSH_STATE.center(_bush) + Vector3.LEFT * 1.3
	_bot.set("_elapsed", 0.35)
	_bot.call("_observe_bush_knowledge", _target, _player, false)
	_bot.call("_update_duel_perception", _target, _player, false)
	_check(_bot.call("get_suspected_bush") == _bush, "lost vision remembers the observed bush rather than forgetting the entrance")
	_check(Vector3(_bot.get("_last_observed_position")).is_equal_approx(remembered), "concealed movement does not change the remembered target position")
	var first: Vector3 = _bot.call("_select_bush_search_destination", _target)
	_check(BUSH_STATE.contains(_bush, first), "bot searches a reachable point inside the suspected foliage")
	_bot.set("_bush_search_index", 0)
	_bot.set("_bush_search_goal", Vector3.INF)
	_bot.set("_next_bush_search_goal_at", 0.0)
	_player.global_position = BUSH_STATE.center(_other_bush)
	var same_evidence: Vector3 = _bot.call("_select_bush_search_destination", _target)
	_check(same_evidence.is_equal_approx(first), "identical observed evidence chooses the same bush search even if the hidden opponent moved elsewhere")
	_bot.set("_elapsed", 2.7)
	_bot.call("_observe_bush_knowledge", _target, _player, false)
	var second: Vector3 = _bot.call("_select_bush_search_destination", _target)
	_check(BUSH_STATE.contains(_bush, second) and second.distance_to(first) > 0.4, "bot checks multiple interior locations instead of locking to one imaginary target")
	_check(_bot.call("get_suspected_bush") == _bush, "hidden relocation cannot teleport the bot's suspected bush")
	_bot.set("_elapsed", 8.5)
	_bot.call("_observe_bush_knowledge", _target, _player, false)
	_check(_bot.call("get_suspected_bush") == null, "unconfirmed bush knowledge expires after its limited search window")
	# No observed entrance: standing hidden at spawn must not grant the AI the
	# occupant's bush identity or position.
	_bot.call("reset_clock")
	_bot.set("_elapsed", 1.0)
	_bot.call("_observe_bush_knowledge", _target, _player, false)
	_check(_bot.call("get_suspected_bush") == null, "a never-seen hidden player does not manufacture bush knowledge")
	# The bot may use another reachable bush as shelter, then stop attacking long
	# enough for its combat timer to finish. This is a tactical action, not a
	# permanent ban on fighting from grass.
	_bot.call("reset_clock")
	_target.call("reset_combat_state")
	_target.global_position = BUSH_STATE.center(_bush) + Vector3.FORWARD * 2.5
	_bot.set("_elapsed", 1.0)
	_bot.set("_last_observed_position", BUSH_STATE.center(_bush) + Vector3.FORWARD * 8.0)
	_bot.set("_has_last_observed_position", true)
	var shelter: Dictionary = _bot.call("_select_shelter_bush", _target, false)
	_check(not shelter.is_empty(), "bot can select reachable grass as retreat shelter")
	if not shelter.is_empty():
		var selected: Node3D = shelter.bush
		_check(BUSH_STATE.contains(selected, shelter.position), "shelter destination sits fully inside its actual footprint")
		_target.global_position = shelter.position
		_target.call("take_damage", 1.0, "bush_test", "bot_shelter_reveal")
		_bot.set("_current_intent", "hide_bush")
		_bot.set("_tactical_bush", selected)
		_bot.set("_perception", {"visible": true, "distance": 8.0})
		_check(bool(_bot.call("_should_hold_bush_fire", _target)), "sheltering bot holds fire while its combat reveal is active")
		_target.get("visibility_state").update(3.01)
		_bot.set("_elapsed", 4.1)
		_check(bool(_bot.call("_should_hold_bush_fire", _target)), "out-of-combat retreat preserves concealment against a distant enemy")
		_bot.set("_current_intent", "ambush_bush")
		_bot.set("_perception", {"visible": true, "distance": 3.0})
		_check(not bool(_bot.call("_should_hold_bush_fire", _target)), "concealed ambush releases fire when the visible enemy reaches attack range")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("BUSH GAMEPLAY TEST: %s (%d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	quit(0 if _failures.is_empty() else 1)
