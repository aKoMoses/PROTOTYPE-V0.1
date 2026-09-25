extends SceneTree

const PASSIVE_STATE := preload("res://scripts/passive_state.gd")
var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player ou TargetDummy introuvable")
	else:
		await _test_baroud(player)
		await _test_omnivamp(player, target)
		_test_death_resolution()
	if _failures.is_empty():
		print("P0-108 PASSIVES TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-108 PASSIVES TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _test_baroud(player: Node) -> void:
	player.call("reset_combat_state")
	player.call("set_passive", "baroud")
	var initial := float(player.call("get_health"))
	var trigger_damage := float(player.call("take_damage", 1200.0, "enemy", "baroud_trigger"))
	if trigger_damage != 0.0:
		_failures.append("Baroud : le coup déclencheur inflige des dégâts à la jauge")
	if absf(float(player.call("get_health")) - initial) > 0.01:
		_failures.append("Baroud : PV normaux modifiés au déclenchement")
	if float(player.call("get_baroud_remaining")) < 2.4 or float(player.call("get_baroud_health")) < 999.0:
		_failures.append("Baroud : jauge ou durée initiale incorrecte")
	var follow_up := float(player.call("take_damage", 200.0, "enemy", "baroud_followup"))
	if absf(follow_up - 200.0) > 0.01 or float(player.call("get_baroud_health")) > 810.0:
		_failures.append("Baroud : dégâts suivants mal appliqués à la jauge")
	if float(player.call("heal", 100.0, "test")) != 0.0:
		_failures.append("Baroud : soin accepté pendant la dernière chance")
	player.set("_defensive_module_id", "static_shield")
	player.call("_perform_defensive_module")
	await create_timer(2.70, true, false, false).timeout
	if not bool(player.get("combat_state").is_dead()):
		_failures.append("Baroud : la stase prolonge la dernière chance")


func _test_omnivamp(player: Node, target: Node) -> void:
	player.call("reset_combat_state")
	player.call("set_passive", "omnivamp")
	player.call("take_damage", 800.0, "setup", "omnivamp_setup")
	target.call("reset_combat_state")
	target.call("take_damage", 980.0, "setup", "target_setup")
	var before := float(player.call("get_health"))
	var effective := float(target.call("take_damage", 100.0, "player", "omnivamp_overkill"))
	if absf(effective - 20.0) > 0.01:
		_failures.append("Omnivamp : dégâts effectifs d'overkill incorrects")
	if absf(float(player.call("get_health")) - (before + 3.0)) > 0.15:
		_failures.append("Omnivamp : 20 dégâts ne rendent pas 3 PV")
	await create_timer(1.50, true, false, false).timeout
	target.call("reset_combat_state")
	var burn_before := float(player.call("get_health"))
	target.call("apply_burn", 3.5, 20.0, "player:test_burn")
	await create_timer(3.80, true, false, false).timeout
	if absf(float(player.call("get_health")) - (burn_before + 10.5)) > 0.35:
		_failures.append("Omnivamp : BURN complet ne rend pas 10,5 PV")


func _test_death_resolution() -> void:
	if PASSIVE_STATE.resolve_simultaneous_death(true, true) != "draw":
		_failures.append("Résolution : double mort ne renvoie pas une manche nulle")
	if PASSIVE_STATE.resolve_simultaneous_death(true, false) != "right":
		_failures.append("Résolution : vainqueur incorrect quand seul le joueur gauche meurt")
	if PASSIVE_STATE.resolve_simultaneous_death(false, true) != "left":
		_failures.append("Résolution : vainqueur incorrect quand seul le joueur droit meurt")
