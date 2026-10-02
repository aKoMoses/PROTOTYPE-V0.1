extends SceneTree

const BASKET := preload("res://scripts/rocket_basket.gd")
const ROCKET := preload("res://scripts/homing_rocket.gd")
const STATE := preload("res://scripts/combat_state.gd")
const LIVE := preload("res://scripts/live_projectile.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const NETWORK := preload("res://scripts/network_player.gd")
var failures: Array[String] = []
var integration_completed := false

class Actor extends StaticBody3D:
	var combat_state = STATE.new()
	var targets: Array = []
	var epoch := 0
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.55
		collision.shape = sphere
		collision.position.y = 0.9
		add_child(collision)
	func _module_target() -> Node:
		return targets[0] if not targets.is_empty() and is_instance_valid(targets[0]) else null
	func get_visibility_epoch() -> int:
		return epoch
	func get_health() -> float:
		return combat_state.health
	func take_damage(amount: float, source: String = "", attack: String = "") -> float:
		return combat_state.apply_damage(amount, source, attack)
	func apply_slow(duration: float, percent: float, source: String) -> void:
		combat_state.apply_slow(duration, percent, source)
	func apply_burn(duration: float, damage: float, source: String) -> void:
		combat_state.apply_burn(duration, damage, source)


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var caster := Actor.new()
	scene.add_child(caster)
	var enemy := Actor.new()
	scene.add_child(enemy)
	enemy.global_position = Vector3(0, 0, -4)
	caster.targets = [enemy]
	await frames(2)
	var cooldowns := {"rocket_basket": 10.0}
	var rockets := BASKET.launch(caster, Vector3.FORWARD, "test", "salve1", cooldowns)
	check(rockets.size() == 5, "Cinq roquettes par activation")
	var headings: Array[Vector3] = []
	for projectile in rockets:
		headings.append(projectile.direction)
	check(headings[0].angle_to(headings[4]) > deg_to_rad(55.0), "Le départ ouvre un cône de 60 degrés")
	check(headings[2].is_equal_approx(Vector3.FORWARD), "La roquette centrale conserve la visée")
	await frames(12)
	for index in range(rockets.size()):
		check(is_instance_valid(rockets[index]) and rockets[index].direction.is_equal_approx(headings[index]), "Le guidage ne referme pas le cône dès le départ")
	for index in range(rockets.size() - 1):
		check(rockets[index].global_position.distance_to(rockets[index + 1].global_position) > 0.30, "Les roquettes s'écartent malgré une cible commune")
	await frames(100)
	check(is_equal_approx(enemy.get_health(), 825.0), "Cinq vrais impacts infligent 175 dégâts")
	check(is_equal_approx(enemy.combat_state.get_slow_percent(), 35.0), "Les cinq slows s'additionnent à 35 %")
	check(enemy.combat_state.has_effect("BURN"), "BURN seulement après la salve complète")
	check(is_equal_approx(float(cooldowns.rocket_basket), 6.0), "Recharge réduite de 40 % exactement")
	check(get_nodes_in_group(ROCKET.GROUP).is_empty(), "Les roquettes disparaissent à l'impact")
	enemy.combat_state.update(3.1)
	check(is_zero_approx(enemy.combat_state.get_slow_percent()), "Les slows expirent")
	enemy.combat_state.reset()
	cooldowns.rocket_basket = 10.0
	rockets = BASKET.launch(caster, Vector3.FORWARD, "test", "salve2", cooldowns)
	rockets[0].take_damage(20.0, "enemy", "one")
	check(is_equal_approx(rockets[0].get_health(), 20.0), "Les roquettes ont quelques PV et encaissent un tir")
	rockets[0].take_damage(20.0, "enemy", "two")
	await frames(100)
	check(is_equal_approx(enemy.get_health(), 860.0), "Une roquette détruite ne touche pas")
	check(is_equal_approx(enemy.combat_state.get_slow_percent(), 28.0), "Quatre impacts : 28 % de slow")
	check(not enemy.combat_state.has_effect("BURN"), "Quatre impacts ne brûlent pas")
	check(float(cooldowns.rocket_basket) == 10.0, "Quatre impacts ne remboursent pas")
	enemy.combat_state.reset()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 0.04)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = Vector3(0, 1, -2)
	await frames(2)
	BASKET.launch(caster, Vector3.FORWARD, "test", "wall", cooldowns)
	await frames(80)
	check(enemy.get_health() == 1000.0, "Aucune roquette ne traverse un mur fin")
	check(get_nodes_in_group(ROCKET.GROUP).is_empty(), "Collision murale détruit les cinq roquettes")
	wall.global_position.z = -0.4
	await frames(2)
	BASKET.launch(caster, Vector3.FORWARD, "test", "close_wall", cooldowns)
	await frames(12)
	check(get_nodes_in_group(ROCKET.GROUP).is_empty(), "Les collisions restent actives pendant l'ouverture du cône")
	wall.queue_free()
	await frames(2)
	caster.targets.clear()
	enemy.global_position = Vector3(100, 0, 100)
	var diagonal := Vector3(1, 0, -1).normalized()
	rockets = BASKET.launch(caster, diagonal, "test", "scan", cooldowns)
	headings.clear()
	for projectile in rockets:
		headings.append(projectile.direction)
	check(headings[2].is_equal_approx(diagonal), "Le cône suit aussi une visée diagonale")
	await frames(12)
	for index in range(rockets.size()):
		check(rockets[index].direction.is_equal_approx(headings[index]), "Sans cible, la recherche respecte aussi l'ouverture initiale")
	await frames(100)
	check(get_nodes_in_group(ROCKET.GROUP).size() == 5, "Sans cible les roquettes continuent de rechercher")
	var first: Node3D = rockets[0]
	first.set_physics_process(false)
	caster.targets = [enemy]
	enemy.global_position = first.global_position + Vector3(0, -0.9, -1)
	check(first._nearest_target() == enemy, "Acquisition d'une cible apparue après le lancement")
	var nearer := Actor.new()
	scene.add_child(nearer)
	nearer.add_to_group("prototype0_combat_bots")
	nearer.global_position = first.global_position + Vector3(0.2, -0.9, 0)
	check(first._nearest_target() == nearer, "Recherche continue du plus proche, sans cône de visée")
	nearer.combat_state.apply_damage(1000.0)
	check(first._nearest_target() == enemy, "Réacquisition après la mort de la cible")
	BASKET.clear(caster)
	await frames(2)
	# Use an actual weapon projectile against a frozen opposing rocket.
	var rocket := ROCKET.new()
	rocket.configure(enemy, "shootable", Vector3.FORWARD)
	scene.add_child(rocket)
	rocket.global_position = Vector3(0, 0.9, -2)
	rocket.set_physics_process(false)
	var shot := LIVE.new()
	scene.add_child(shot)
	shot.global_position = Vector3(0, 0.9, 0)
	shot.configure(Vector3.FORWARD, 40.0, 4.0, 1 | 2 | 8, [caster.get_rid()])
	shot.finished.connect(func(hit: Dictionary, _distance: float) -> void:
		if hit.get("collider") == rocket:
			rocket.take_damage(40.0, "test", "actual_weapon")
	)
	await frames(15)
	check(not is_instance_valid(rocket), "Une auto-attaque réelle détruit une roquette adverse")
	# Independent slow expiration and preservation of normal strongest-slow rules.
	var state := STATE.new()
	state.apply_slow(1.0, 5.0, "rocket_stack:a")
	state.apply_slow(3.0, 5.0, "rocket_stack:b")
	state.apply_slow(3.0, 8.0, "ordinary")
	check(state.get_slow_percent() == 10.0, "Les slows roquettes cumulent sans modifier les slows ordinaires")
	state.update(1.1)
	check(state.get_slow_percent() == 8.0, "Chaque stack possède son expiration")
	var build := LOADOUT.defaults()
	build.offensive = "rocket_basket"
	check(LOADOUT.is_valid(build), "Le panier est un équipement valide")
	# Distribute one volley across two enemies; identical total hits is insufficient.
	enemy.combat_state.reset()
	nearer.combat_state.reset()
	cooldowns.rocket_basket = 10.0
	rockets = BASKET.launch(caster, Vector3.FORWARD, "test", "split", cooldowns)
	for index in range(5):
		rockets[index].set_physics_process(false)
		rockets[index].impacted.emit(enemy if index < 3 else nearer, rockets[index])
	check(not enemy.combat_state.has_effect("BURN") and not nearer.combat_state.has_effect("BURN"), "Trois plus deux impacts ne brûlent aucune cible")
	check(float(cooldowns.rocket_basket) == 10.0, "Une salve partagée ne réduit pas le cooldown")
	BASKET.clear(caster)
	await frames(2)
	# Persistent rockets from an older cast must never refund a newer cast.
	enemy.combat_state.reset()
	var old := BASKET.launch(caster, Vector3.FORWARD, "test", "old", cooldowns)
	rockets = BASKET.launch(caster, Vector3.FORWARD, "test", "new", cooldowns)
	for projectile in old:
		projectile.set_physics_process(false)
		projectile.impacted.emit(enemy, projectile)
	check(enemy.combat_state.has_effect("BURN"), "Une ancienne salve complète conserve sa brûlure")
	check(float(cooldowns.rocket_basket) == 10.0, "Une ancienne salve ne rembourse pas la nouvelle")
	BASKET.clear(caster)
	await frames(2)
	await _integration()
	check(integration_completed, "Le test d'intégration doit atteindre sa fin sans erreur de script")
	for failure in failures:
		push_error(failure)
	print("TEST ROCKET BASKET: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _integration() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node3D = scene.get_node("Player")
	var target: Node3D = scene.get_node("TargetDummy")
	player.call("set_training_options", false, false, false)
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	var build := LOADOUT.defaults()
	build.offensive = "rocket_basket"
	player.call("apply_loadout", build)
	player.call("reset_combat_state")
	player.global_position = Vector3(0, 0, 60)
	target.global_position = Vector3(0, 0, 56)
	player.set("aim_direction", Vector3.FORWARD)
	player.call("_perform_offensive_module")
	check(player.get("_active_module_id") == "rocket_basket", "Le cast verrouille les actions")
	check(is_equal_approx(float(player.call("get_current_move_speed")), float(player.get("move_speed")) * 0.85), "Le cast ralentit légèrement le vrai joueur")
	await frames(10)
	check(BASKET.snapshot(player).is_empty(), "Pas de lancement avant la fin du cast")
	player.call("apply_stun", 1.0, "test")
	await frames(20)
	check(BASKET.snapshot(player).is_empty(), "STUN interrompt le cast")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.call("_perform_offensive_module")
	await frames(25)
	check(BASKET.snapshot(player).size() == 5, "Le vrai joueur émet cinq roquettes")
	check(player.get("_active_module_id") == "", "Le cast libère les actions")
	var data := BASKET.snapshot(player)
	var replica := NETWORK.new()
	replica.authoritative = false
	replica.remote_controlled = true
	scene.add_child(replica)
	BASKET.receive_snapshot(replica, data)
	check(BASKET.snapshot(replica).size() == 5, "Snapshots : les cinq répliques et leurs PV")
	var visual: Node = get_nodes_in_group(ROCKET.GROUP).back()
	check(visual.take_damage(100.0) == 0.0, "Le client ne résout aucun dégât")
	BASKET.receive_snapshot(replica, [])
	await process_frame
	check(BASKET.snapshot(replica).is_empty(), "Snapshot : destruction autoritaire répliquée")
	player.call("reset_combat_state")
	await process_frame
	check(BASKET.snapshot(player).is_empty(), "Une nouvelle manche nettoie les roquettes")
	var controller: Node = target.get("_training_bot")
	var equipment: Node = controller.get("_duel_equipment")
	equipment.call("set_loadout", build)
	check(equipment.get("offensive_id") == "rocket_basket", "Le bot conserve le nouveau module")
	check(equipment.call("_begin_pending_module", "rocket_basket", 0.3, {"position": player.global_position}, controller), "Le bot démarre son cast")
	check(is_equal_approx(float(equipment.call("get_speed_multiplier")), 0.85), "Le cast du bot applique le même slow")
	equipment.call("_resolve_pending_module", target, player, controller, true)
	check(BASKET.snapshot(target).size() == 5, "Le bot lance aussi cinq roquettes")
	for projectile in get_nodes_in_group(ROCKET.GROUP):
		if projectile.caster == target:
			projectile.set_physics_process(false)
	var module_rocket: Node = get_nodes_in_group(ROCKET.GROUP).back()
	player.call("_on_javelin_finished", {"collider": module_rocket}, 0.0, player.get("_javelin_launch_token"))
	check(module_rocket.is_real_dead(), "Les dégâts du module Javelin détruisent une roquette adverse")
	equipment.call("reset")
	await process_frame
	check(BASKET.snapshot(target).is_empty(), "Le reset du bot nettoie ses roquettes")
	integration_completed = true
	scene.queue_free()
	await process_frame
