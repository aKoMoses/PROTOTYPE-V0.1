extends SceneTree

const HEAT := preload("res://scripts/blaster_heat.gd")
const DATA := preload("res://scripts/combat_data.gd")
const NETWORK := preload("res://scripts/network_player.gd")
const HUD := preload("res://scripts/hud_vitals.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _state_checks() -> void:
	var heat := HEAT.new()
	for shot in 5:
		check(heat.commit_shot(0.0), "normal shot %d accepted" % (shot + 1))
		check(heat.overheated == (shot == 4), "overload only on the fifth quick shot")
		if shot < 4:
			heat.tick(0.2)
	check(not heat.commit_shot(1.0) and is_equal_approx(heat.fraction(), 1.0), "blocked shots spend no heat")
	heat.tick(1.9)
	check(heat.overheated and not heat.commit_shot(0.0), "partial cooling never unlocks fire early")
	heat.tick(0.1)
	check(not heat.overheated and heat.commit_shot(0.0), "full two-second recovery unlocks")
	heat.reset()
	for shot in 3:
		check(heat.commit_shot(1.0), "charged shot accepted")
		if shot < 2:
			heat.tick(0.65)
	check(heat.overheated, "three full charges overheat at the real charge cadence")
	heat.reset()
	for shot in 10:
		heat.commit_shot(0.0)
		heat.tick(1.2)
	check(not heat.overheated and is_zero_approx(heat.heat), "spaced normal shots can fire indefinitely")
	var fine := HEAT.new()
	var coarse := HEAT.new()
	fine.commit_shot(0.5)
	coarse.commit_shot(0.5)
	for frame in 60:
		fine.tick(1.0 / 60.0)
	coarse.tick(1.0)
	check(is_equal_approx(fine.heat, coarse.heat), "cooling independent of frame size across delay")
	fine.tick(0.0)
	check(is_equal_approx(fine.heat, coarse.heat), "paused time does not cool")
	fine.restore({"heat": 100.0, "overheated": true})
	coarse.restore(fine.snapshot())
	check(coarse.overheated and is_equal_approx(coarse.remaining(), 2.0), "heat and lock survive replication")
	coarse.restore({"heat": 10000.0, "delay": -10.0, "overheated": false})
	check(coarse.overheated and is_equal_approx(coarse.fraction(), 1.0), "restored capacity always locks")
	check(not coarse.commit_shot(NAN), "invalid charge never changes heat")

func _actor(authority: bool, at: Vector3) -> Node3D:
	var actor := NETWORK.new()
	actor.authoritative = authority
	actor.remote_controlled = true
	current_scene.add_child(actor)
	actor.apply_loadout({"weapon": "blaster", "passive": "omnivamp"})
	actor.set_gameplay_enabled(true)
	actor.set_physics_process(false)
	actor.global_position = at
	actor.collision_layer = 0
	return actor

func _fire(actor: Node, ratio: float = 0.0) -> void:
	# Headless rendering may advance several process frames in one physics
	# frame. Each test shot must own a distinct action-gate frame.
	await physics_frame
	await process_frame
	actor.set("_blaster_next_attack_ready_at", -1.0)
	actor.call("_fire_blaster_projectile", lerpf(float(actor.get("_blaster_damage")), float(actor.get("_blaster_max_damage")), ratio), ratio, Vector3.FORWARD)
	await process_frame
	await process_frame

func _run() -> void:
	_state_checks()
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.get_node("Player")
	var target := scene.get_node("TargetDummy")
	player.call("set_gameplay_enabled", true)
	player.call("apply_loadout", {"weapon": "blaster", "mobility": "bio_injector", "passive": "omnivamp"})
	player.call("reset_combat_state")
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.set_process(false)
	target.call("reset_combat_state")
	player.global_position = Vector3(0, 40, 0)
	target.global_position = Vector3(0, 40, -4)
	player.call("_begin_blaster_charge")
	player.call("_cancel_blaster_charge")
	check(is_zero_approx(float(player.call("get_blaster_heat_fraction"))), "cancelling charge spends no heat")
	# The cancelled charge still owns its physics frame in the shared action gate.
	await physics_frame
	await process_frame
	for shot in 5:
		await _fire(player)
	await create_timer(0.15).timeout
	check(is_equal_approx(float(target.call("get_health")), float(target.call("get_max_health")) - 5.0 * float(DATA.WEAPON_DEFINITIONS.blaster.damage)), "fifth real projectile damages before the lock")
	check(bool(player.call("is_blaster_overheated")), "player overheats after five emissions")
	var token := int(player.get("_blaster_attack_token"))
	await _fire(player, 1.0)
	player.call("_begin_blaster_charge")
	check(int(player.get("_blaster_attack_token")) == token and not bool(player.call("is_blaster_charging")), "direct fire and charge denied while hot")
	check(not player.get("_action_gate").is_busy(), "overheat never holds the module action gate")
	player.call("begin_touch_fire")
	check(not bool(player.get("_touch_fire_active")) and not bool(player.call("end_touch_fire")), "touch contact during overload queues no shot")
	check(str(player.call("get_mobile_blaster_input_state")) == "overheated", "touch HUD reports overload even with no contact")
	var hud := HUD.new()
	scene.add_child(hud)
	hud.set_player(player)
	check(hud._weapon.text.contains("SURCHAUFFE") and is_equal_approx(hud._heat_fill.size.x, 256.0), "HUD displays lock and full heat gauge")
	check(hud._weapon.get_theme_font("font").get_string_size(hud._weapon.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x <= 256.0, "overheat label fits the existing HUD")
	var readout: Node3D = player.get("_health_readout")
	var muzzle_fx: Node3D = player.get("_blaster_charge_visual")
	check(readout.get("_blaster_warning").visible and not readout.get("_blaster_coil").visible, "last shot immediately replaces the world charge coil with the red lock warning")
	var world_label: Label = readout.get("_blaster_warning_label")
	check(world_label.text.contains("SURCHAUFFE") and world_label.get_theme_font("font").get_string_size(world_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x <= 266.0, "world lock countdown fits above the cooling gauge")
	check(muzzle_fx.visible and muzzle_fx.get("_energy_material").albedo_color.r > muzzle_fx.get("_energy_material").albedo_color.b and not player.call("is_blaster_charging"), "red muzzle cooling effect appears without a held charge")
	check(hud._shell.border_width_left == 2 and hud._heat_fill.size.y == 7.0, "overheat highlights the whole HUD frame and a thicker heat gauge")
	player.get("_blaster_component").update_heat(1.8)
	player.call("_update_blaster_charge_visual", 0.0)
	player.call("_sync_weapon_readout")
	hud._refresh()
	check(readout.get("_blaster_warning").visible and muzzle_fx.visible and hud._weapon.text.contains("SURCHAUFFE"), "all lock warnings persist even at ten percent heat during final cooling")
	check(is_equal_approx(readout.get("_blaster_heat_fill").size.x, 26.6) and world_label.text.contains("0.2 s"), "world gauge and countdown follow actual cooling")
	player.call("set_weapon", "shotgun")
	hud._refresh()
	check(not readout.get("_blaster_warning").visible and not muzzle_fx.visible and hud._shell.border_width_left == 1, "equipping another weapon clears Blaster-only cues")
	player.call("set_weapon", "blaster")
	check(bool(player.call("is_blaster_overheated")), "weapon switching cannot erase heat")
	check(readout.get("_blaster_warning").visible and muzzle_fx.visible, "re-equipping a still-hot Blaster restores its lock cues")
	player.call("_perform_mobility_module")
	check(player.get("_bio_remaining") > 0.0, "overheated gun still allows mobility module")
	player.call("reset_combat_state")
	check(not bool(player.call("is_blaster_overheated")), "round reset clears heat")
	check(not readout.get("_blaster_warning").visible and not muzzle_fx.visible, "round reset immediately clears world and muzzle lock cues")
	player.call("configure_survival_build", {"weapon": "blaster", "upgrades": {}})
	player.get("_blaster_heat").restore({"heat": 80.0})
	player.call("configure_survival_build", {"weapon": "blaster", "upgrades": {"weapon": {"power": 1}}})
	check(is_equal_approx(float(player.call("get_blaster_heat_fraction")), 0.8), "mid-wave Survival upgrades preserve heat")
	player.call("apply_loadout", {"weapon": "blaster", "mobility": "bio_injector", "passive": "omnivamp"})
	player.call("reset_combat_state")
	player.get("_blaster_heat").restore({"heat": 100.0, "overheated": true})
	player.set_physics_process(true)
	paused = true
	await create_timer(0.12, true).timeout
	check(is_equal_approx(float(player.call("get_blaster_heat_fraction")), 1.0), "tree pause freezes live player cooling")
	paused = false
	await create_timer(0.12).timeout
	check(float(player.call("get_blaster_heat_fraction")) < 1.0, "physics resumes cooling after pause")
	player.set_physics_process(false)
	player.get("_attack_label").text = "BLASTER  •  SURCHAUFFE"
	player.get("_blaster_component").update_heat(2.0)
	check(player.get("_attack_label").text.is_empty(), "cooling clears the expired world overheat message")
	hud._refresh()
	check(not readout.get("_blaster_warning").visible and not muzzle_fx.visible and not hud._weapon.text.contains("SURCHAUFFE") and hud._shell.border_width_left == 1, "fully cooled Blaster clears all lock warnings together")
	await _fire(player)
	check(not bool(player.call("is_blaster_overheated")) and float(player.call("get_blaster_heat_fraction")) > 0.0, "real fire resumes after cooling")
	await _network_checks()
	await _bot_checks(target, player)
	current_scene = null
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("BLASTER HEAT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _network_checks() -> void:
	var host := _actor(true, Vector3(30, 40, 0))
	var replica := _actor(false, Vector3(60, 40, 0))
	for shot in 5:
		await physics_frame
		await process_frame
		host._blaster_next_attack_ready_at = -1.0
		host.receive_action("blaster", {"ratio": 1.0, "heat": 0.0})
		await process_frame
		await process_frame
	check(host.is_blaster_overheated(), "host charges heat despite fabricated client fields")
	var token: int = host._blaster_attack_token
	host.receive_action("contact", {})
	host.receive_action("charge", {})
	host.receive_action("blaster", {"ratio": 1.0})
	check(host._blaster_attack_token == token and host._contact_started_at < 0.0, "host rejects hot contact, charge and fire")
	replica.receive_snapshot(host.network_snapshot())
	check(replica.is_blaster_overheated() and is_equal_approx(replica.get_blaster_heat_fraction(), 1.0), "snapshot replicates full heat and lock")
	var replica_token: int = replica._blaster_attack_token
	replica.receive_action("blaster", {"ratio": 0.0}, true)
	await process_frame
	await process_frame
	check(replica._blaster_attack_token == replica_token + 1, "late visual final shot still plays after overheated snapshot")
	check(replica.is_blaster_overheated() and is_equal_approx(replica.get_blaster_heat_fraction(), 1.0), "visual replay does not spend or clear confirmed heat")
	host.receive_snapshot({"blaster_heat": {"heat": 0.0}})
	check(host.is_blaster_overheated(), "client snapshot cannot cool the authority")
	host._blaster_heat.tick(2.0)
	replica.receive_snapshot(host.network_snapshot())
	check(not replica.is_blaster_overheated(), "authoritative cooling unlocks replica")

func _bot_checks(target: Node3D, player: Node3D) -> void:
	var equipment := target.get_node("TrainingBot/DuelEquipment")
	equipment.call("set_profile", "blaster")
	equipment.set("_aim_position", player.global_position)
	equipment.set("charge_duration", 0.0)
	var initial: int = equipment.get("_shot_serial")
	for shot in 5:
		equipment.call("_fire", target, player)
		await process_frame
	check(equipment.get("blaster_heat").overheated and int(equipment.get("_shot_serial")) == initial + 5, "bot uses the same five-shot capacity")
	equipment.call("_fire", target, player)
	check(int(equipment.get("_shot_serial")) == initial + 5 and not equipment.get("_action_gate").is_busy(), "bot overload blocks emission without owning actions")
	equipment.call("set_profile", "shotgun")
	equipment.call("set_profile", "blaster")
	check(equipment.get("blaster_heat").overheated, "bot switching retains overload")
	equipment.get("blaster_heat").tick(2.0)
	check(bool(equipment.call("_begin_weapon_action")), "bot can shoot after cooling")
	equipment.call("reset")
	check(not equipment.get("blaster_heat").overheated, "bot round reset clears overload")
