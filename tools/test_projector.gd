extends SceneTree

const PROJECTOR := preload("res://scripts/projector.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const NETWORK_PLAYER := preload("res://scripts/network_player.gd")
const KNOCKBACK := preload("res://scripts/knockback_motion.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
var _failures: Array[String] = []

class TestEnemy extends StaticBody3D:
	var slow := 0.0
	var slow_duration := 0.0
	var hits := 0
	var health := 100.0
	var push_direction := Vector3.ZERO
	var push_distance := 0.0
	var push_time := 0.0
	func start_knockback(direction: Vector3, distance: float, duration: float, _source: String) -> void:
		push_direction = direction
		push_distance = distance
		push_time = duration
	func _update_fulguro_projection(delta: float) -> void:
		var step := KNOCKBACK.step(push_distance, push_time, delta)
		var sweep := FULGURO.sweep_static_body(self, push_direction * step, 0.3, 1.8)
		var travel: Vector3 = sweep.travel
		global_position += travel
		push_distance = maxf(0.0, push_distance - travel.length())
		push_time = maxf(0.0, push_time - delta)
		if sweep.collided:
			push_distance = 0.0
			push_time = 0.0
	func get_health() -> float:
		return health
	func apply_slow(duration: float, percent: float, _source: String) -> void:
		slow = percent
		slow_duration = duration
		hits += 1
	func get_fulguro_hit_radius() -> float:
		return 0.30

class ActionRecorder extends Node:
	var _phase := "live"
	var events: Array = []
	func on_actor_action(_actor: Node, action: String, data: Dictionary) -> void:
		events.append({"action": action, "data": data})


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _advance_recoil(actor: Node, duration: float = 0.42) -> void:
	for _tick in range(30):
		actor.call("_update_fulguro_projection", duration / 30.0)


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node("Player")
	var target: Node = scene.get_node("TargetDummy")
	player.call("set_training_options", false, false, false)
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	player.get_node("WeaponAimGuide").set_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	var build := LOADOUT.defaults()
	build.defensive = "projector"
	build.passive = "omnivamp"
	_check(LOADOUT.is_valid(build), "Projector doit être un équipement valide et sauvegardable")
	player.call("apply_loadout", build)
	player.call("reset_combat_state")
	_check(player.call("get_defensive_module_id") == "projector", "Le joueur doit conserver Projector")
	player.global_position = Vector3(0, 0, 60)
	target.global_position = Vector3(2, 0, 60)
	target.call("reset_combat_state")
	var hp: float = player.call("get_max_health")
	await _test_manual(player, target)
	player.call("reset_combat_state")
	target.call("reset_combat_state")
	target.global_position = Vector3(2, 0, 60)
	player.call("take_damage", hp * 0.75, "test", "projector_boundary")
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "25 % exactement ne déclenche pas")
	player.call("take_damage", 1.0, "test", "projector_crossing")
	_check(is_equal_approx(float(player.call("get_projector_passive_cooldown")), 25.0), "Le passage sous 25 % démarre 25 s de recharge")
	_check(bool(target.call("is_fulguro_projected")), "L'impulsion passive commence immédiatement")
	_advance_recoil(target)
	_check(target.global_position.x > 5.0, "La poussée progressive repousse plus loin")
	_check(float(target.get("combat_state").get_slow_percent()) > 15.0, "Ralentissement immédiat du mannequin réel")
	target.get("combat_state").update(2.6)
	_check(is_zero_approx(float(target.get("combat_state").get_slow_percent())), "Le ralentissement disparaît après 2,5 s")
	player.call("_update_module_cooldowns", 24.0)
	player.call("heal", hp, "test")
	player.call("take_damage", hp * 0.76, "test", "projector_cooldown")
	_check(is_equal_approx(float(player.call("get_projector_passive_cooldown")), 1.0), "Un nouveau franchissement pendant la recharge est bloqué")
	player.call("_update_module_cooldowns", 1.0)
	var state = player.get("combat_state")
	state.health_changed.emit(state.health, state.max_health)
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "Rester sous 25 % ne redéclenche pas")
	player.call("heal", hp, "test")
	player.call("apply_stun", 1.0, "test")
	player.call("take_damage", hp * 0.76, "test", "projector_again")
	_check(is_equal_approx(float(player.call("get_projector_passive_cooldown")), 25.0), "Nouveau franchissement après recharge, même sous STUN")
	player.call("reset_combat_state")
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "La nouvelle manche réinitialise la recharge")
	player.set("_defensive_module_id", "static_shield")
	player.call("take_damage", hp * 0.76, "test", "projector_unequipped")
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "Pas de déclenchement sans Projector équipé")
	player.set("_defensive_module_id", "projector")
	player.call("reset_combat_state")
	player.call("take_damage", hp, "test", "projector_lethal")
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "Un coup létal ne déclenche pas Projector")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.call("take_damage", hp * 0.74, "test", "projector_before_burn")
	player.call("apply_burn", 1.0, hp * 0.1, "test_burn")
	state.update(0.25)
	_check(is_equal_approx(float(player.call("get_projector_passive_cooldown")), 25.0), "Le franchissement par BURN déclenche aussi l'onde")
	player.call("reset_combat_state")
	state.health = hp * 0.15
	player.set("_projector_below_threshold", true)
	player.call("heal", hp * 0.05, "test")
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "Un soin sous 25 % ne déclenche pas l'onde")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", false)
	player.call("take_damage", hp * 0.76, "test", "projector_disabled")
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "Pas d'onde hors gameplay")
	player.call("set_gameplay_enabled", true)
	_check(not LOADOUT.stat_line("projector").is_empty(), "La fiche affiche les paramètres du module")
	await _test_radial(scene, player)
	await _test_network(scene)
	if _failures.is_empty():
		print("PROJECTOR TEST: PASS (activation manuelle, passif indépendant, gradient, collisions, réseau)")
	else:
		for failure in _failures:
			push_error("PROJECTOR FAIL: " + failure)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _test_manual(player: Node, target: Node) -> void:
	player.call("_activate_defensive_module")
	_check(is_equal_approx(float(player.call("get_module_cooldown", "projector")), 6.0), "L'entrée défensive active manuellement Projector et démarre sa recharge de 6 s")
	_check(is_zero_approx(float(target.get("combat_state").get_slow_percent())), "Le cast manuel précède l'effet")
	player.call("_update_projector_cast", 0.17)
	_check(not bool(target.call("is_fulguro_projected")), "Pas de poussée avant la fin des 0,18 s")
	player.call("_update_projector_cast", 0.01)
	_check(bool(target.call("is_fulguro_projected")) and float(target.get("combat_state").get_slow_percent()) > 0.0, "La fin du cast applique poussée et slow")
	_advance_recoil(target, 0.05)
	_check(float(player.call("get_projector_passive_cooldown")) == 0.0, "L'activation manuelle ne consomme pas le passif")
	var after_manual: Vector3 = target.global_position
	player.call("_activate_defensive_module")
	_check(target.global_position.is_equal_approx(after_manual), "Pas de deuxième activation manuelle pendant la recharge")
	var hp: float = player.call("get_max_health")
	player.call("take_damage", hp * 0.76, "test", "projector_manual_then_passive")
	_advance_recoil(target, 0.05)
	_check(target.global_position.x > after_manual.x, "Le passif fonctionne pendant la recharge manuelle")
	_check(is_equal_approx(float(player.call("get_projector_passive_cooldown")), 25.0), "Le passif possède sa propre recharge de 25 s")
	player.call("reset_combat_state")
	target.call("reset_combat_state")
	target.global_position = Vector3(2, 0, 60)
	player.call("take_damage", hp * 0.76, "test", "projector_passive_then_manual")
	_check(is_zero_approx(float(player.call("get_module_cooldown", "projector"))), "Le passif laisse l'activation manuelle disponible")
	await physics_frame
	_check(bool(player.call("_perform_projector")), "L'activation manuelle reste possible pendant la recharge passive")
	player.call("reset_combat_state")
	player.call("apply_stun", 1.0, "test")
	_check(not bool(player.call("_perform_projector")), "L'activation manuelle respecte STUN")
	_check(is_zero_approx(float(player.call("get_module_cooldown", "projector"))), "Une activation manuelle refusée ne consomme pas sa recharge")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", false)
	_check(not bool(player.call("_perform_projector")), "Pas d'activation manuelle hors gameplay")
	player.call("set_gameplay_enabled", true)
	player.call("reset_combat_state")
	_check(bool(player.call("trigger_touch_action", "defensive")), "Le bouton tactile accepte l'activation")
	player.call("_update_debug_effects")
	_check(float(player.call("get_module_cooldown", "projector")) > 0.0, "Le bouton tactile active Projector")
	player.call("_update_projector_cast", 0.18)
	player.call("_update_module_cooldowns", 5.9)
	await physics_frame
	_check(not bool(player.call("_perform_projector")), "L'activation manuelle reste indisponible avant 6 s")
	player.call("_update_module_cooldowns", 0.1)
	await physics_frame
	_check(bool(player.call("_perform_projector")), "L'activation manuelle redevient disponible après 6 s")
	player.call("apply_stun", 0.5, "test_cast_interrupt")
	player.call("_update_projector_cast", 0.18)
	_check(int(player.get("_projector_cast_token")) == 0 and str(player.get("_active_module_id")) == "", "Une interruption libère le cast et son verrou")


func _enemy(scene: Node, at: Vector3) -> TestEnemy:
	var enemy := TestEnemy.new()
	enemy.collision_layer = 2
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	enemy.add_child(collision)
	scene.add_child(enemy)
	enemy.global_position = at
	return enemy


func _test_radial(scene: Node, player: Node3D) -> void:
	player.global_position = Vector3(0, 0, 60)
	var near := _enemy(scene, Vector3(1, 0, 60))
	var far := _enemy(scene, Vector3(-5, 0, 60))
	var edge := _enemy(scene, Vector3(0, 0, 66))
	var outside := _enemy(scene, Vector3(0, 0, 53.9))
	var center := _enemy(scene, player.global_position)
	var dead := _enemy(scene, Vector3(0, 0, 58))
	dead.health = 0.0
	await physics_frame
	PROJECTOR.activate(player, [near, near, far, edge, outside, center, dead, player], "test")
	for enemy in [near, far, edge, center]:
		_advance_recoil(enemy)
	_check(near.hits == 1 and far.hits == 1, "Chaque cible n'est touchée qu'une fois")
	_check(near.slow > far.slow and near.global_position.x - 1.0 > absf(far.global_position.x + 5.0), "Poussée et slow décroissent avec la distance")
	_check(is_equal_approx(near.slow_duration, 2.5), "Durée du slow : 2,5 s")
	_check(is_equal_approx(edge.slow, 15.0), "La limite du rayon reçoit le minimum")
	_check(center.hits == 1 and center.global_position.is_finite() and is_equal_approx(center.slow, 65.0), "Au centre exact : maximum sans division par zéro")
	_check(outside.hits == 0 and dead.hits == 0, "Cibles hors rayon ou mortes ignorées")
	for enemy in [near, far, edge, outside, center, dead]:
		enemy.queue_free()
	await process_frame
	var blocked := _enemy(scene, Vector3(2, 0, 60))
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 2.0, 2.0)
	collision.shape = shape
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = Vector3(3.0, 1.0, 60)
	await physics_frame
	PROJECTOR.activate(player, [blocked], "wall_test")
	_advance_recoil(blocked)
	_check(blocked.global_position.x < 2.75 and blocked.global_position.x > 2.0, "La poussée s'arrête avant le mur")
	_check(blocked.slow > 0.0, "Le mur n'annule pas le slow sur la cible touchée")
	blocked.queue_free()
	wall.queue_free()
	await process_frame


func _test_network(scene: Node) -> void:
	var host := CharacterBody3D.new()
	host.set_script(NETWORK_PLAYER)
	var victim := CharacterBody3D.new()
	victim.set_script(NETWORK_PLAYER)
	var replica := CharacterBody3D.new()
	replica.set_script(NETWORK_PLAYER)
	replica.set("authoritative", false)
	for actor in [host, victim, replica]:
		scene.add_child(actor)
		actor.call("set_gameplay_enabled", true)
		actor.set_physics_process(false)
		actor.get_node("WeaponAimGuide").set_process(false)
	replica.global_position = Vector3(0, 0, 90)
	host.global_position = Vector3(0, 0, 80)
	victim.global_position = Vector3(2, 0, 80)
	host.set("opponent", victim)
	victim.set("opponent", host)
	var recorder := ActionRecorder.new()
	scene.add_child(recorder)
	host.set("controller", recorder)
	host.set("_defensive_module_id", "projector")
	replica.set("_defensive_module_id", "projector")
	await physics_frame
	host.call("take_damage", float(host.call("get_max_health")) * 0.76, "test", "projector_network")
	_advance_recoil(victim, 0.1)
	_check(victim.global_position.x > 2.0 and int(victim.get("_permutation_revision")) == 1, "Le serveur pousse la cible et invalide les anciennes positions")
	_check(recorder.events.size() == 1 and recorder.events[0].action == "projector_pulse", "Un seul événement visuel réseau")
	replica.call("receive_snapshot", victim.call("network_snapshot"), false)
	_check(replica.global_position.is_equal_approx(victim.global_position), "La poussée serveur corrige le client même avec une entrée non confirmée")
	_check(float(replica.get("combat_state").get_slow_percent()) > 0.0, "Le slow est synchronisé sur le client")
	_check(bool(replica.call("is_fulguro_projected")), "Le client reçoit la poussée en cours malgré une entrée non confirmée")
	var before_prediction: Vector3 = replica.global_position
	replica.call("_update_movement", 1.0 / 60.0)
	_check(replica.global_position.x > before_prediction.x, "La poussée est simulée entre deux snapshots")
	_advance_recoil(victim)
	replica.call("receive_snapshot", victim.call("network_snapshot"), false)
	_check(not bool(replica.call("is_fulguro_projected")) and replica.global_position.is_equal_approx(victim.global_position), "Fin de poussée et position finale confirmées")
	replica.call("receive_snapshot", host.call("network_snapshot"))
	_check(is_equal_approx(float(replica.call("get_projector_passive_cooldown")), 25.0), "La réplique reçoit la recharge sans créer une deuxième onde")
	var cooldown: float = replica.call("get_projector_passive_cooldown")
	replica.call("receive_action", "projector_pulse", {"origin": host.global_position}, true)
	_check(is_equal_approx(float(replica.call("get_projector_passive_cooldown")), cooldown), "L'événement visuel conserve la recharge confirmée")
	_check(is_zero_approx(float(host.call("get_module_cooldown", "projector"))), "Le passif réseau n'utilise pas la recharge active")
	await physics_frame
	_check(bool(host.call("_perform_projector")), "Le serveur accepte aussi l'activation manuelle")
	_check(recorder.events.size() == 2 and recorder.events[1].action == "projector_cast", "Le cast est annoncé avant l'onde")
	host.call("_update_projector_cast", 0.18)
	_check(recorder.events.size() == 3 and recorder.events[2].action == "projector_pulse", "L'activation manuelle publie une seule onde serveur après le cast")
	replica.call("receive_snapshot", host.call("network_snapshot"))
	_check(is_equal_approx(float(replica.call("get_module_cooldown", "projector")), 6.0), "La recharge active de 6 s est synchronisée séparément du passif")
	var client_recorder := ActionRecorder.new()
	scene.add_child(client_recorder)
	replica.set("controller", client_recorder)
	replica.set("opponent", victim)
	replica.call("reset_combat_state")
	await physics_frame
	var victim_before: Vector3 = victim.global_position
	_check(bool(replica.call("_perform_projector")), "Le client peut demander l'activation manuelle")
	_check(client_recorder.events.size() == 1 and client_recorder.events[0].action == "defensive", "Le client envoie la demande au serveur")
	_check(victim.global_position.is_equal_approx(victim_before), "Le client n'applique pas lui-même de poussée")
	host.call("reset_combat_state")
	await physics_frame
	host.call("receive_action", "defensive", {})
	_check(is_equal_approx(float(host.call("get_module_cooldown", "projector")), 6.0), "La demande réseau active Projector côté serveur avec 6 s de recharge")
	client_recorder.queue_free()
	for actor in [host, victim, replica, recorder]:
		actor.queue_free()
	await process_frame
