extends SceneTree

const DATA := preload("res://scripts/combat_data.gd")
const STATE := preload("res://scripts/combat_state.gd")
const NETWORK := preload("res://scripts/network_player.gd")
const WAVE := preload("res://scripts/pelto_smash.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
var failures: Array[String] = []
var checks := 0
var player: Node3D
var target: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func prepare() -> void:
	player.call("apply_loadout", {"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "tracker"})
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3.FORWARD)
	target.call("reset_combat_state")
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.set_process(false)
	target.global_position = Vector3(0, 0, -4)

func ailments(actor: Node) -> void:
	actor.get("combat_state").apply_burn(8.0, 20.0, "test:burn")
	actor.get("combat_state").apply_slow(8.0, 30.0, "test:ordinary")
	actor.get("combat_state").apply_slow(8.0, 7.0, "rocket_stack:test:1")
	actor.get("combat_state").apply_slow(8.0, 7.0, "rocket_stack:test:2")

func marked() -> void:
	var token := int(player.get("_javelin_launch_token"))
	player.call("_on_javelin_finished", {"collider": target, "position": target.global_position + Vector3.UP}, 4.0, token)

func _run() -> void:
	_test_cleanse_state()
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	if player.get("_controls_component") == null:
		push_error("Player controls did not compile; integration cannot run.")
		quit(1)
		return
	scene.get_node("Interface").call("_start_duel")
	scene.get_node("Interface").call("_begin_live_round")
	_test_stasis()
	_test_network_stasis(scene)
	_test_tracker()
	await _test_javelin()
	await _test_bots()
	_test_pelto(scene)
	await _test_wall_opening(scene)
	if "capture-opportunities" in OS.get_cmdline_user_args():
		await _capture_tracker(scene)
	current_scene = null
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("MODULE OPPORTUNITIES: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _test_cleanse_state() -> void:
	var state := STATE.new()
	state.apply_damage(10.0, "test", "already_hit")
	state.grant_shield(50.0, 3.0)
	state.apply_burn(8.0, 20.0, "burn")
	state.apply_slow(8.0, 30.0, "ordinary")
	state.apply_slow(8.0, 7.0, "rocket_stack:a")
	state.apply_slow(8.0, 7.0, "rocket_stack:b")
	state.apply_stun(2.0)
	state.apply_spotted(6.0)
	var events: Array[String] = []
	state.effect_changed.connect(func(effect: String, active: bool) -> void:
		if not active:
			events.append(effect)
	)
	state.cleanse_burn_and_slow()
	state.cleanse_burn_and_slow()
	check(not state.has_effect("BURN") and state.get_slow_percent() == 0.0, "Cleanse removes burn and every slow source")
	check(events == ["BURN", "SLOW"], "Cleanse emits exactly one removal signal per active ailment")
	check(state.is_stunned() and state.is_spotted(), "Cleanse preserves stun and tracking")
	check(state.health == 990.0 and state.shield_health == 50.0, "Cleanse preserves health and shield")
	check(state.apply_damage(10.0, "test", "already_hit") == 0.0, "Cleanse preserves attack deduplication")
	state.update(1.0)
	check(state.health == 990.0 and state.shield_health == 50.0, "Purified burn cannot resume its ticks")

func _test_stasis() -> void:
	prepare()
	ailments(player)
	player.get("combat_state").apply_spotted(6.0)
	player.call("_perform_static_shield")
	check(not player.get("combat_state").has_effect("BURN") and player.get("combat_state").get_slow_percent() == 0.0, "Player stasis purifies on activation")
	check(player.get("combat_state").is_spotted(), "Stasis does not erase enemy tracking")
	check(float(player.call("get_module_cooldown", "static_shield")) == 12.0, "Stasis consumes exactly twelve seconds")
	check(float(player.call("take_damage", 100.0, "test", "protected")) == 0.0, "Stasis remains invulnerable")
	player.call("_perform_static_shield")
	check(float(player.call("get_stasis_remaining")) > 0.0, "Early exit still refused")
	player.set("_stasis_remaining", 1.0)
	player.call("_perform_static_shield")
	check(float(player.call("get_stasis_remaining")) == 0.0, "Voluntary exit after half a second still works")
	check(float(player.call("get_module_cooldown", "static_shield")) == 12.0, "Exit never refunds the cooldown")
	ailments(player)
	player.call("_perform_static_shield")
	check(player.get("combat_state").has_effect("BURN") and player.get("combat_state").get_slow_percent() > 0.0, "Rejected activation never purifies")

func _test_network_stasis(scene: Node) -> void:
	var host := NETWORK.new()
	host.remote_controlled = true
	scene.add_child(host)
	host.call("apply_loadout", {"defensive": "static_shield"})
	host.set_physics_process(false)
	ailments(host)
	host.call("receive_action", "defensive", {}, false)
	check(not host.get("combat_state").has_effect("BURN") and host.get("combat_state").get_slow_percent() == 0.0, "Network authority purifies accepted stasis")
	var replica := NETWORK.new()
	replica.authoritative = false
	replica.remote_controlled = true
	scene.add_child(replica)
	replica.call("apply_loadout", {"defensive": "static_shield"})
	replica.set_physics_process(false)
	ailments(replica)
	replica.call("receive_action", "defensive", {}, true)
	check(replica.get("combat_state").has_effect("BURN") and replica.get("combat_state").get_slow_percent() > 0.0, "Visual replica never decides purification")
	replica.call("receive_snapshot", host.call("network_snapshot"))
	check(not replica.get("combat_state").has_effect("BURN") and replica.get("combat_state").get_slow_percent() == 0.0, "Authoritative snapshot carries purification")
	host.queue_free()
	replica.queue_free()

func _test_tracker() -> void:
	prepare()
	for shot in 2:
		player.call("passive_weapon_damage", target, 10.0, "player", "tracker:%d" % shot, player.call("emit_passive_weapon"))
	check(is_equal_approx(float(target.get("combat_state").get_remaining("SPOTTED")), 6.0), "Two real weapon attacks reveal for six seconds")
	check(player.call("get_tracker_locations").has(target), "Tracker exposes the marked target to its locator")
	player.get("passive_state").process(1.0)
	player.call("passive_weapon_damage", target, 10.0, "player", "tracker:3", player.call("emit_passive_weapon"))
	check(is_equal_approx(float(player.get("passive_state").reveal_remaining()), 5.0), "Further hits never extend the tracking window")
	target.get("combat_state").update(5.5)
	check(target.get("combat_state").is_spotted(), "Target remains tracked beyond the old four seconds")
	target.get("combat_state").update(0.6)
	check(not target.get("combat_state").is_spotted(), "Tracking expires after six seconds")

func _test_javelin() -> void:
	prepare()
	await physics_frame
	marked()
	var damage_before := float(target.call("get_health"))
	player.call("_recast_javelin", Vector3(0, 0, 100))
	check(bool(player.call("_has_live_javelin_mark")) and target.get("combat_state").get_slow_percent() == 0.0, "Blocked destination retains mark without granting slow")
	player.call("_recast_javelin")
	check(player.global_position.length() > 1.0 and not bool(player.call("_has_live_javelin_mark")), "Successful approach consumes one mark")
	check(target.get("combat_state").get_slow_percent() == 25.0 and is_equal_approx(float(target.get("combat_state").get_remaining("SLOW")), 0.8), "Javelin approach opens a brief slow window")
	check(float(target.call("get_health")) == damage_before, "Approach adds no direct damage")
	check(not player.get("_action_gate").is_busy(), "Approach releases the action gate for a manual attack")
	var aim: Vector3 = player.get("aim_direction")
	check(aim.dot((target.global_position - player.global_position).normalized()) > 0.99, "Approach faces the target")
	target.get("combat_state").update(0.81)
	check(target.get("combat_state").get_slow_percent() == 0.0, "Approach slow expires")
	prepare()
	await physics_frame
	marked()
	target.set_meta("duel_static_shield", true)
	player.call("_recast_javelin")
	check(target.get("combat_state").get_slow_percent() == 0.0, "Approach cannot slow a target in stasis")
	target.remove_meta("duel_static_shield")

func _test_bots() -> void:
	prepare()
	target.call("set_duel_loadout", {"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "tracker"})
	var equipment: Node = target.get("_training_bot").get("_duel_equipment")
	ailments(target)
	equipment.call("_activate_static_shield", target)
	check(not target.get("combat_state").has_effect("BURN") and target.get("combat_state").get_slow_percent() == 0.0, "Bot stasis uses the same purification")
	check(float(equipment.call("get_module_cooldown", "static_shield")) == 12.0, "Bot stasis shares twelve-second cooldown")
	target.call("reset_combat_state")
	target.global_position = Vector3(0, 0, -4)
	player.global_position = Vector3.ZERO
	equipment.set("_javelin_marked_player", player)
	equipment.set("_javelin_mark_remaining", 2.5)
	await physics_frame
	var moved := bool(equipment.call("_try_javelin_recast", target, player, {"position": player.global_position}))
	check(moved and player.get("combat_state").get_slow_percent() == 25.0, "Bot approach shares the follow-up slow")

func _test_pelto(scene: Node) -> void:
	prepare()
	var wave := WAVE.new()
	scene.add_child(wave)
	wave.configure(player, player.global_position, Vector3.FORWARD, "player", "pelto_window")
	wave.set_physics_process(false)
	wave.call("_apply_hit", target, false)
	wave.call("_apply_hit", target, true)
	check(float(target.call("get_health")) == 740.0, "Pelto keeps its 160 plus 100 damage")
	check(target.get("combat_state").get_slow_percent() == 25.0 and is_equal_approx(float(target.get("combat_state").get_remaining("SLOW")), 1.1), "Pelto return opens a follow-up window")
	target.get("combat_state").update(0.5)
	wave.call("_apply_hit", target, true)
	check(is_equal_approx(float(target.get("combat_state").get_remaining("SLOW")), 0.6), "Repeated return collision never refreshes the slow")
	target.get("combat_state").update(0.61)
	check(target.get("combat_state").get_slow_percent() == 0.0, "Pelto return slow expires")
	wave.queue_free()

func _test_wall_opening(scene: Node) -> void:
	prepare()
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0, 0, -1.6)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.2)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = Vector3(0, 0.9, -3)
	await physics_frame
	var hit := FULGURO.resolve_strike(player, [target], Vector3.FORWARD, 200.0, 150.0, float(DATA.MODULE_DEFINITIONS.fulguro_punch.wall_stun), "player", "wall_opening")
	check(hit == target, "Real Fulguro strike selects the target")
	for frame in 30:
		target.call("_update_fulguro_projection", 1.0 / 60.0)
		if not bool(target.call("is_fulguro_projected")):
			break
	check(float(target.call("get_health")) == 650.0, "Wall opening preserves direct and collision damage")
	check(is_equal_approx(float(target.get("combat_state").get_remaining("STUN")), 1.0), "Wall impact leaves a full second to follow up")
	target.get("combat_state").update(1.01)
	check(not target.get("combat_state").is_stunned(), "Wall stun expires normally")
	wall.queue_free()

func _capture_tracker(scene: Node) -> void:
	prepare()
	player.position = Vector3(-3, 0, 17)
	target.position = Vector3(3, 0, 17)
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	camera.global_position = Vector3(0, 15, 31)
	camera.look_at(Vector3(0, 0.4, 17), Vector3.UP)
	for shot in 2:
		player.call("passive_weapon_damage", target, 10.0, "player", "capture:%d" % shot, player.call("emit_passive_weapon"))
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/module-opportunities-tracker.png") == OK, "Tracker capture saved")
