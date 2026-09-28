extends SceneTree

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
		target.call("set_training_bot_enabled", false)
		player.call("set_weapon", "blaster")
		await _test_normal_shot(player, target)
		await _test_early_release_audio(player, target)
		await _test_cooldown(player, target)
		await _test_charge_damage(player, target, 0.50, 35.0, "charge 50%")
		await _test_charge_damage(player, target, 1.15, 50.0, "charge maximale")
		await _test_charge_cap(player)
		await _test_charge_speed(player)
		await _test_cancel_on_weapon_change(player)
		await _test_cancel_on_death(player, target)
		await _test_mobile_tap_snapshot(player, target)
		await _test_mobile_full_charge_release(player, target)
		await _test_mobile_cancel_without_shot(player, target)
		var shot_audio := player.get_node_or_null("BlasterShotAudio") as AudioStreamPlayer
		if shot_audio != null:
			shot_audio.stop()
	current_scene = null
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("P0-127 BLASTER TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-127 BLASTER TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _prepare(player: Node, target: Node) -> void:
	player.call("set_gameplay_enabled", true)
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("set_weapon", "blaster")
	player.call("reset_combat_state")
	target.global_position = Vector3(0.0, 0.0, -4.0)
	target.call("reset_combat_state")
	await process_frame


func _test_normal_shot(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	var shot_audio := player.get_node_or_null("BlasterShotAudio") as AudioStreamPlayer
	if shot_audio == null or shot_audio.stream == null or shot_audio.stream.resource_path != "res://art/audio/blaster-shot-v2.wav":
		_failures.append("tir normal : nouveau son manquant")
	elif not shot_audio.playing:
		_failures.append("tir normal : nouveau son non joué")
	await _wait_seconds(0.35)
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - 20.0) > 0.6:
		_failures.append("tir normal : %.2f dégâts au lieu de 20" % damage)


func _test_early_release_audio(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_begin_blaster_charge")
	var charge_audio := player.get_node("BlasterChargeAudio") as AudioStreamPlayer
	var hold_audio := player.get_node("BlasterChargeHoldAudio") as AudioStreamPlayer
	var ready_audio := player.get_node("BlasterReadyAudio") as AudioStreamPlayer
	if not charge_audio.playing:
		_failures.append("charge courte : son de charge non joué")
	await _wait_seconds(0.16)
	player.call("_release_blaster_charge")
	await _wait_seconds(0.05)
	if charge_audio.playing or hold_audio.playing or ready_audio.playing:
		_failures.append("tir avant charge complète : son de charge encore actif")
	var shot_audio := player.get_node("BlasterShotAudio") as AudioStreamPlayer
	if not shot_audio.playing:
		_failures.append("tir avant charge complète : son du tir absent")


func _test_cooldown(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.35)
	var first_damage := 1000.0 - float(target.call("get_health"))
	if absf(first_damage - 20.0) > 0.6:
		_failures.append("cooldown : second tir immédiat accepté")
	await _wait_seconds(0.20)
	player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.35)
	if float(target.call("get_health")) >= 981.0:
		_failures.append("cooldown : tir après 0,45 s refusé")


func _test_charge_damage(player: Node, target: Node, hold_time: float, expected: float, label: String) -> void:
	await _prepare(player, target)
	player.call("_begin_blaster_charge")
	await _wait_seconds(hold_time)
	var ratio := float(player.call("get_blaster_charge_ratio"))
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("_release_blaster_charge")
	var expected_audio := player.get_node("BlasterChargedShotAudio" if hold_time >= 1.0 else "BlasterShotAudio") as AudioStreamPlayer
	if not expected_audio.playing:
		_failures.append("%s : son de tir incorrect" % label)
	await _wait_seconds(0.40)
	var damage := 1000.0 - float(target.call("get_health"))
	var expected_damage := expected if hold_time < 1.0 else 50.0
	if absf(damage - expected_damage) > 1.2:
		_failures.append("%s : %.2f dégâts au lieu de %.2f (ratio %.2f)" % [label, damage, expected_damage, ratio])


func _test_charge_cap(player: Node) -> void:
	await _prepare(player, current_scene.get_node("TargetDummy"))
	player.call("_begin_blaster_charge")
	await _wait_seconds(1.75)
	if float(player.call("get_blaster_charge_ratio")) > 1.001:
		_failures.append("charge prolongée : ratio supérieur à 1")
	var hold_audio := player.get_node("BlasterChargeHoldAudio") as AudioStreamPlayer
	if not hold_audio.playing:
		_failures.append("charge prolongée : fond sonore absent")
	player.call("_cancel_blaster_charge")


func _test_charge_speed(player: Node) -> void:
	if absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("déplacement : vitesse initiale incorrecte")
	player.call("_begin_blaster_charge")
	await physics_frame
	if absf(float(player.call("get_current_move_speed")) - 4.0) > 0.05:
		_failures.append("déplacement pendant charge : vitesse différente de 80%")
	player.call("_cancel_blaster_charge")
	if absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("déplacement après charge : vitesse non restaurée")


func _test_cancel_on_weapon_change(player: Node) -> void:
	player.call("_begin_blaster_charge")
	await physics_frame
	player.call("set_weapon", "shotgun")
	if bool(player.call("is_blaster_charging")) or absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("changement d'arme : charge non annulée")
	player.call("set_weapon", "blaster")


func _test_cancel_on_death(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("set_passive", "omnivamp")
	player.call("_begin_blaster_charge")
	player.call("take_damage", 1000.0, "test", "blaster_death")
	await process_frame
	if bool(player.call("is_blaster_charging")) or absf(float(player.call("get_current_move_speed")) - 5.0) > 0.05:
		_failures.append("mort pendant charge : état de charge bloqué")
	player.call("set_gameplay_enabled", true)
	player.call("reset_combat_state")


func _test_mobile_tap_snapshot(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("set_aim_input", Vector2(1.0, 0.0))
	var expected: Vector3 = player.get("aim_direction")
	target.global_position = player.global_position + expected * 4.0
	var token_before := int(player.get("_blaster_attack_token"))
	player.call("begin_touch_fire")
	await _wait_seconds(0.06)
	if int(player.get("_blaster_attack_token")) != token_before:
		_failures.append("mobile tap : projectile créé au toucher initial")
	player.call("end_touch_fire", Vector2(1.0, 0.0))
	# Reproduit la remise à zéro/une entrée ultérieure avant le traitement de la
	# requête : la direction du tir doit rester celle capturée au relâchement.
	player.call("set_aim_input", Vector2(-1.0, 0.0))
	await physics_frame
	await physics_frame
	if int(player.get("_blaster_attack_token")) != token_before + 1:
		_failures.append("mobile tap : le relâchement n'a pas demandé exactement un tir")
	var actual: Vector3 = player.get("_last_projectile_direction")
	if actual.dot(expected) < 0.999:
		_failures.append("mobile tap : direction relâchée perdue (dot %.4f)" % actual.dot(expected))
	await _wait_seconds(0.36)
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - 20.0) > 0.8:
		_failures.append("mobile tap : %.2f dégâts au lieu d'un tir normal de 20" % damage)
	await _wait_seconds(0.15)
	player.call("set_aim_input", Vector2(1.0, 0.0))
	player.call("begin_touch_fire")
	await _wait_seconds(0.05)
	player.call("end_touch_fire", Vector2(1.0, 0.0))
	await _wait_seconds(0.38)
	if int(player.get("_blaster_attack_token")) != token_before + 2 or absf((1000.0 - float(target.call("get_health"))) - 40.0) > 1.0:
		_failures.append("mobile tap : gestes courts successifs hors cadence")


func _test_mobile_full_charge_release(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("set_aim_input", Vector2(0.0, -1.0))
	var token_before := int(player.get("_blaster_attack_token"))
	player.call("begin_touch_fire")
	await _wait_seconds(0.48)
	player.call("set_aim_input", Vector2(1.0, 0.0))
	var expected: Vector3 = player.get("aim_direction")
	target.global_position = player.global_position + expected * 4.0
	await _wait_seconds(0.70)
	if int(player.get("_blaster_attack_token")) != token_before:
		_failures.append("mobile charge : tir automatique avant relâchement")
	if str(player.call("get_mobile_blaster_input_state")) != "ready" or float(player.call("get_blaster_charge_ratio")) < 0.99:
		_failures.append("mobile charge : pleine charge non maintenue")
	player.call("end_touch_fire", Vector2(1.0, 0.0))
	player.call("set_aim_input", Vector2(-1.0, 0.0))
	await physics_frame
	await physics_frame
	if int(player.get("_blaster_attack_token")) != token_before + 1:
		_failures.append("mobile charge : le relâchement n'a pas produit un tir unique")
	var actual: Vector3 = player.get("_last_projectile_direction")
	if actual.dot(expected) < 0.999:
		_failures.append("mobile charge : changement de direction non conservé")
	await _wait_seconds(0.36)
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - 50.0) > 1.2:
		_failures.append("mobile charge : %.2f dégâts au lieu de 50" % damage)


func _test_mobile_cancel_without_shot(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("set_aim_input", Vector2(0.0, -1.0))
	var token_before := int(player.get("_blaster_attack_token"))
	player.call("begin_touch_fire")
	await _wait_seconds(0.28)
	if not bool(player.call("is_blaster_charging")):
		_failures.append("mobile annulation : charge non démarrée après le seuil")
	player.call("clear_touch_inputs")
	await _wait_seconds(0.10)
	if bool(player.call("is_blaster_charging")) or bool(player.get("_touch_fire_active")):
		_failures.append("mobile annulation : contact/charge encore actifs")
	if int(player.get("_blaster_attack_token")) != token_before or float(target.call("get_health")) < 999.9:
		_failures.append("mobile annulation : interruption interprétée comme un tir")


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true, false, false).timeout
