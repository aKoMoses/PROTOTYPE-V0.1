extends SceneTree

const DEFINITION: Dictionary = preload("res://scripts/combat_data.gd").WEAPON_DEFINITIONS.blaster

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
		await _test_desktop_rapid_taps(player, target)
		await _test_desktop_hold_through_cooldown(player, target)
		await _test_desktop_full_charge_input(player, target)
		await _test_normal_shot(player, target)
		await _test_target_dodges_projectile(player, target)
		await _test_target_enters_projectile_path(player, target)
		await _test_early_release_audio(player, target)
		await _test_cooldown(player, target)
		await _test_sustained_fire(player, target)
		await _test_long_range_and_cover(player, target)
		await _test_charge_damage(player, target, float(DEFINITION.charge_time) * 0.5, "charge 50%")
		await _test_charge_damage(player, target, float(DEFINITION.charge_time) + 0.15, "charge maximale")
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
	await _set_desktop_attack(false)
	player.call("set_gameplay_enabled", true)
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("set_weapon", "blaster")
	player.call("reset_combat_state")
	target.global_position = Vector3(0.0, 0.0, -4.0)
	target.call("reset_combat_state")
	await process_frame


func _set_desktop_attack(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	await physics_frame
	# `physics_frame` est émis avant les `_physics_process`; attendre aussi la
	# frame de rendu garantit que Player a consommé l'état clavier injecté.
	await process_frame


func _test_desktop_hold_through_cooldown(player: Node, target: Node) -> void:
	await _prepare(player, target)
	var token_before := int(player.get("_blaster_attack_token"))
	await _set_desktop_attack(true)
	if not bool(player.call("is_blaster_charging")):
		_failures.append("PC cadence : le premier maintien ne démarre pas la charge")
	await _wait_seconds(0.08)
	await _set_desktop_attack(false)
	await _wait_seconds(0.02)
	await _set_desktop_attack(true)
	if bool(player.call("is_blaster_charging")):
		_failures.append("PC cadence : la charge contourne le cooldown")
	var now := Time.get_ticks_msec() / 1000.0
	var ready_in := maxf(0.0, float(player.get("_blaster_next_attack_ready_at")) - now)
	await _wait_seconds(ready_in + 0.08)
	if not bool(player.call("is_blaster_charging")):
		_failures.append("PC cadence : le maintien commencé pendant le cooldown reste perdu")
	await _wait_seconds(float(DEFINITION.charge_time) * 0.5)
	var ratio := float(player.call("get_blaster_charge_ratio"))
	await _set_desktop_attack(false)
	await _wait_seconds(0.30)
	if int(player.get("_blaster_attack_token")) != token_before + 2:
		_failures.append("PC cadence : deux relâchements n'ont pas produit deux tirs")
	if ratio < 0.45 or ratio > 0.70:
		_failures.append("PC cadence : charge reprise incorrecte après cooldown (%.2f)" % ratio)


func _test_desktop_rapid_taps(player: Node, target: Node) -> void:
	await _prepare(player, target)
	var token_before := int(player.get("_blaster_attack_token"))
	await _set_desktop_attack(true)
	await _wait_seconds(0.02)
	await _set_desktop_attack(false)
	await _wait_seconds(0.02)
	await _set_desktop_attack(true)
	await _wait_seconds(0.01)
	await _set_desktop_attack(false)
	if int(player.get("_blaster_attack_token")) != token_before + 1:
		_failures.append("PC taps : le tap pendant cooldown a contourné la cadence")
	var now := Time.get_ticks_msec() / 1000.0
	var ready_in := maxf(0.0, float(player.get("_blaster_next_attack_ready_at")) - now)
	await _wait_seconds(ready_in + 0.10)
	if int(player.get("_blaster_attack_token")) != token_before + 2:
		_failures.append("PC taps : le tap bref pendant cooldown n'a pas enchaîné le tir suivant")


func _test_desktop_full_charge_input(player: Node, target: Node) -> void:
	await _prepare(player, target)
	var token_before := int(player.get("_blaster_attack_token"))
	await _set_desktop_attack(true)
	await _wait_seconds(float(DEFINITION.charge_time) + 0.08)
	if float(player.call("get_blaster_charge_ratio")) < 0.99:
		_failures.append("PC charge : le maintien n'atteint pas la pleine charge")
	var direction: Vector3 = player.get("aim_direction")
	target.global_position = player.global_position + direction.normalized() * 4.0
	await _set_desktop_attack(false)
	await _wait_seconds(0.30)
	if int(player.get("_blaster_attack_token")) != token_before + 1:
		_failures.append("PC charge : le relâchement n'a pas produit un tir unique")
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - float(DEFINITION.max_damage)) > 1.2:
		_failures.append("PC charge : %.2f dégâts au lieu de %.0f" % [damage, DEFINITION.max_damage])


func _test_normal_shot(player: Node, target: Node) -> void:
	await _prepare(player, target)
	player.call("_fire_blaster_projectile", float(DEFINITION.damage), 0.0, Vector3(0.0, 0.0, -1.0))
	var shot_audio := player.get_node_or_null("BlasterShotAudio") as AudioStreamPlayer
	if shot_audio == null or shot_audio.stream == null or shot_audio.stream.resource_path != "res://art/audio/blaster-shot-v2.wav":
		_failures.append("tir normal : nouveau son manquant")
	elif not shot_audio.playing:
		_failures.append("tir normal : nouveau son non joué")
	await _wait_seconds(0.35)
	var damage := 1000.0 - float(target.call("get_health"))
	if absf(damage - float(DEFINITION.damage)) > 0.6:
		_failures.append("tir normal : %.2f dégâts au lieu de %.0f" % [damage, DEFINITION.damage])


func _test_target_dodges_projectile(player: Node, target: Node) -> void:
	await _prepare(player, target)
	target.global_position = Vector3(0.0, 0.0, -6.0)
	await physics_frame
	player.call("_fire_blaster_projectile", float(DEFINITION.damage), 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.01)
	target.global_position.x = 3.0
	await _wait_seconds(0.40)
	if float(target.call("get_health")) < 999.9:
		_failures.append("cible mobile : un tir esquivé inflige encore des dégâts")


func _test_target_enters_projectile_path(player: Node, target: Node) -> void:
	await _prepare(player, target)
	target.global_position = Vector3(3.0, 0.0, -6.0)
	await physics_frame
	player.call("_fire_blaster_projectile", float(DEFINITION.damage), 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.01)
	var projectile := player.get_tree().current_scene.find_child("BlasterProjectile", false, false) as Node3D
	if projectile == null:
		_failures.append("cible mobile : projectile absent après lancement")
		return
	var direction: Vector3 = projectile.get("_direction")
	var distance: float = (target.global_position.z - projectile.global_position.z) / direction.z
	target.global_position.x = projectile.global_position.x + direction.x * distance
	await _wait_seconds(0.40)
	if absf(float(target.call("get_health")) - (1000.0 - float(DEFINITION.damage))) > 0.6:
		_failures.append("cible mobile : un projectile traversant la cible ne la touche pas")


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
	player.call("_fire_blaster_projectile", float(DEFINITION.damage), 0.0, Vector3(0.0, 0.0, -1.0))
	player.call("_fire_blaster_projectile", float(DEFINITION.damage), 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.35)
	var first_damage := 1000.0 - float(target.call("get_health"))
	if absf(first_damage - float(DEFINITION.damage)) > 0.6:
		_failures.append("cooldown : second tir immédiat accepté")
	await _wait_seconds(0.20)
	player.call("_fire_blaster_projectile", float(DEFINITION.damage), 0.0, Vector3(0.0, 0.0, -1.0))
	await _wait_seconds(0.35)
	if absf(float(target.call("get_health")) - (1000.0 - float(DEFINITION.damage) * 2.0)) > 0.6:
		_failures.append("cooldown : tir après récupération refusé")


func _test_sustained_fire(player: Node, target: Node) -> void:
	await _prepare(player, target)
	var started_at := Time.get_ticks_msec()
	var token_before := int(player.get("_blaster_attack_token"))
	for shot in range(3):
		player.call("_fire_blaster_projectile", float(DEFINITION.damage), 0.0, Vector3.FORWARD)
		await _wait_seconds(float(DEFINITION.cooldown) + 0.03)
	if int(player.get("_blaster_attack_token")) != token_before + 3 or absf(float(target.call("get_health")) - 700.0) > 0.6:
		_failures.append("rafale : trois tirs rapides doivent retirer 300 PV")
	if Time.get_ticks_msec() - started_at > 950:
		_failures.append("rafale : cadence renforcée trop lente")


func _test_long_range_and_cover(player: Node, target: Node) -> void:
	await _prepare(player, target)
	# Isolate this corridor above the authored arena, with real target collisions.
	var start := Vector3(0.0, 40.9, 0.0)
	for power in [0.0, 1.0]:
		target.global_position = Vector3(0.0, 40.0, -20.0)
		target.call("reset_combat_state")
		await physics_frame
		var damage := lerpf(float(DEFINITION.damage), float(DEFINITION.max_damage), power)
		player.call("_spawn_blaster_projectile", start, damage, power, 910 + int(power), Vector3.FORWARD)
		var projectile := current_scene.get_node("BlasterProjectile")
		var speed := float(DEFINITION.projectile_speed) * lerpf(1.0, float(DEFINITION.charged_speed_multiplier), power)
		if not is_equal_approx(float(projectile.get("_speed")), speed):
			_failures.append("portée : vitesse du plasma incorrecte")
		await _wait_seconds(20.0 / speed + 0.08)
		if absf(float(target.call("get_health")) - (1000.0 - damage)) > 0.6:
			_failures.append("portée : le plasma doit toucher à 20 mètres")
	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.2)
	shape.shape = box
	cover.add_child(shape)
	current_scene.add_child(cover)
	cover.global_position = Vector3(0.0, 40.9, -10.0)
	target.call("reset_combat_state")
	await physics_frame
	player.call("_spawn_blaster_projectile", start, float(DEFINITION.max_damage), 1.0, 912, Vector3.FORWARD)
	await _wait_seconds(0.35)
	if float(target.call("get_health")) < 999.9:
		_failures.append("couvert : le plasma surpuissant traverse un mur")
	cover.queue_free()
	target.global_position = Vector3(0.0, 40.0, -26.0)
	target.call("reset_combat_state")
	await physics_frame
	player.call("_spawn_blaster_projectile", start, float(DEFINITION.max_damage), 1.0, 913, Vector3.FORWARD)
	await _wait_seconds(0.35)
	if float(target.call("get_health")) < 999.9 or current_scene.get_node_or_null("BlasterProjectile") != null:
		_failures.append("portée : le projectile doit expirer avant 26 mètres")


func _test_charge_damage(player: Node, target: Node, hold_time: float, label: String) -> void:
	await _prepare(player, target)
	player.call("_begin_blaster_charge")
	await _wait_seconds(hold_time)
	var ratio := float(player.call("get_blaster_charge_ratio"))
	player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
	player.call("_release_blaster_charge")
	var expected_audio := player.get_node("BlasterChargedShotAudio" if ratio >= 0.85 else "BlasterShotAudio") as AudioStreamPlayer
	if not expected_audio.playing:
		_failures.append("%s : son de tir incorrect" % label)
	await _wait_seconds(0.40)
	var damage := 1000.0 - float(target.call("get_health"))
	var expected_damage := lerpf(float(DEFINITION.damage), float(DEFINITION.max_damage), ratio)
	if absf(ratio - minf(1.0, hold_time / float(DEFINITION.charge_time))) > 0.10:
		_failures.append("%s : progression de charge incorrecte (%.2f)" % [label, ratio])
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
	if absf(float(player.call("get_current_move_speed")) - 5.0 * float(DEFINITION.charge_slow_multiplier)) > 0.05:
		_failures.append("déplacement pendant charge : mobilité complète perdue")
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
	if absf(damage - float(DEFINITION.damage)) > 0.8:
		_failures.append("mobile tap : %.2f dégâts au lieu de %.0f" % [damage, DEFINITION.damage])
	await _wait_seconds(0.15)
	player.call("set_aim_input", Vector2(1.0, 0.0))
	player.call("begin_touch_fire")
	await _wait_seconds(0.05)
	player.call("end_touch_fire", Vector2(1.0, 0.0))
	await _wait_seconds(0.38)
	if int(player.get("_blaster_attack_token")) != token_before + 2 or absf((1000.0 - float(target.call("get_health"))) - float(DEFINITION.damage) * 2.0) > 1.0:
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
	if absf(damage - float(DEFINITION.max_damage)) > 1.2:
		_failures.append("mobile charge : %.2f dégâts au lieu de %.0f" % [damage, DEFINITION.max_damage])


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
