extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const TOUCH := preload("res://scripts/touch_controls.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []
var network_exercised := false

class Arena extends Node3D:
	var targets: Array = []
	func get_training_targets() -> Array:
		return targets

class Victim extends CharacterBody3D:
	var health := 1000.0
	var burn_duration := 0.0
	var burn_dps := 0.0
	func take_damage(amount: float, _source: String = "", _attack: String = "") -> float:
		health -= amount
		return amount
	func apply_burn(duration: float, damage_per_second: float, _source: String = "") -> void:
		burn_duration = duration
		burn_dps = damage_per_second

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func prepare(actor: CharacterBody3D) -> void:
	actor.call("reset_combat_state")
	actor.call("apply_loadout", {"mobility": "eclipse", "passive": "omnivamp"})
	actor.call("set_gameplay_enabled", true)
	actor.global_position = Vector3.ZERO
	actor.set_physics_process(false)

func blocker(scene: Node3D, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 2.0, 4.0)
	shape.shape = box
	body.add_child(shape)
	scene.add_child(body)
	body.global_position = at + Vector3.UP
	return body

func run() -> void:
	var arena := Arena.new()
	root.add_child(arena)
	current_scene = arena
	var player := PLAYER.new()
	arena.add_child(player)
	prepare(player)
	var first := Victim.new()
	var second := Victim.new()
	var outside := Victim.new()
	for victim in [first, second, outside]:
		arena.add_child(victim)
		arena.targets.append(victim)
	first.position = Vector3(5.0, 0.0, 0.0)
	second.position = Vector3(4.0, 0.0, 2.5)
	outside.position = Vector3(4.0, 0.0, 3.5)
	await physics_frame
	check(LOADOUT.sanitize({"mobility": "eclipse"}).mobility == "eclipse", "équipement rejeté")
	check(player.begin_touch_action("mobility"), "maintien tactile refusé")
	player.set_eclipse_touch_vector(Vector2.RIGHT)
	check(player._eclipse.destination.distance_to(Vector3(12, 0, 0)) < 0.01, "visée maximale ne rejoint pas les 12 m")
	player.set_eclipse_touch_vector(Vector2(1.0 / 3.0, 0.0))
	check(player.is_eclipse_aiming() and player.visible and player.get_module_cooldown("eclipse") == 0.0, "maintien consomme le sort ou masque le joueur")
	check(player._eclipse.destination.distance_to(Vector3(4, 0, 0)) < 0.01, "stick ne règle pas direction et distance")
	var old_layer := player.collision_layer
	var old_mask := player.collision_mask
	player.end_touch_action("mobility")
	check(player.is_eclipse_travelling() and not player.visible and player.collision_layer == 0 and player.collision_mask == 0, "départ : corps visible ou tangible")
	check(player._eclipse._flight.get_parent() == arena and player._eclipse._particles.size() > 20, "trajet en particules absent")
	var health := player.get_health()
	check(player.take_damage(100.0, "test", "transit") == 0.0, "dégâts pendant le trajet")
	player.apply_stun(1.0, "test")
	player.apply_slow(1.0, 50.0, "test")
	player.apply_burn(1.0, 20.0, "test")
	player.start_pelto_pull(Vector3.RIGHT, 1.0, 0.15)
	player.start_fulguro_projection(Vector3.RIGHT, 4.0, 0.3, 100.0, 0.5, "test", "projection")
	check(not player.is_pelto_pulled() and not player._fulguro_projection_active, "traction / projection pendant le transit")
	check(player.get_health() == health and not player.combat_state.is_stunned() and not player.combat_state.has_effect("BURN"), "effets pendant le trajet")
	player._perform_static_shield()
	player._begin_blaster_charge()
	check(player.get_module_cooldown("static_shield") == 0.0 and player.get_action_owner() == "eclipse", "action permise pendant le trajet")
	player._eclipse.update(player, 0.12)
	check(player.global_position == Vector3.ZERO and player.is_eclipse_travelling(), "TP instantanée au lieu du bref trajet")
	player._eclipse.update(player, 0.14)
	check(player.global_position.distance_to(Vector3(4, 0, 0)) < 0.01 and player.visible and player.collision_layer == old_layer and player.collision_mask == old_mask, "arrivée / restauration incorrecte")
	check(first.health == 880.0 and second.health == 880.0 and outside.health == 1000.0, "explosion ne respecte pas les cibles et le rayon")
	check(first.burn_duration == 3.5 and first.burn_dps == 20.0 and second.burn_duration == 3.5 and outside.burn_duration == 0.0, "burn absent ou appliqué hors rayon")
	check(player.get_shield_health() == 150.0 and player.combat_state.shield_remaining == 3.0, "bouclier sur impact absent ou cumulé par cible")
	player.take_damage(200.0, "test", "shield_absorption")
	check(player.get_health() == health - 50.0 and player.get_shield_health() == 0.0, "bouclier d'Éclipse n'absorbe pas les dégâts")
	player._eclipse.update(player, 1.0)
	check(first.health == 880.0 and not player._perform_eclipse(Vector3.ZERO), "explosion répétée ou recharge ignorée")

	prepare(player)
	await physics_frame
	check(player.begin_touch_action("mobility"), "second maintien refusé")
	player.cancel_touch_action("mobility")
	check(not player.is_eclipse_aiming() and player.get_action_owner().is_empty() and player.get_module_cooldown("eclipse") == 0.0, "annulation consomme le sort")
	await physics_frame
	check(player.begin_touch_action("mobility"), "tap refusé")
	player.end_touch_action("mobility")
	check(player.is_eclipse_travelling(), "tap dans la même frame refusé")
	player.set_gameplay_enabled(false)
	check(player.visible and player.collision_layer == old_layer and not player.is_eclipse_travelling(), "fin de manche laisse le joueur disparu")

	prepare(player)
	var wall := blocker(arena, Vector3(4, 0, 0))
	await physics_frame
	check(player._perform_eclipse(Vector3(4, 0, 0)), "destination obstruée ne rejoint pas une sortie libre")
	player._eclipse.update(player, 0.3)
	check(player._eclipse.fits(player, player.global_position, false) and absf(player.global_position.x - 4.0) > 0.8, "sortie de l'obstacle laisse le corps coincé")
	prepare(player)
	check(not player._perform_eclipse(Vector3(13, 0, 0)) and not player._perform_eclipse(Vector3.INF), "portée / coordonnées non finies acceptées")
	wall.queue_free()
	await physics_frame
	check(player._perform_eclipse(Vector3(12, 0, 0)), "téléportation à 12 m refusée")
	player._eclipse.update(player, 0.3)
	check(player.global_position == Vector3(12, 0, 0), "arrivée à 12 m incorrecte")
	check(player.get_shield_health() == 0.0, "bouclier accordé sur une explosion ratée")
	prepare(player)
	await physics_frame
	wall = blocker(arena, Vector3(2, 0, 0))
	await physics_frame
	check(player._perform_eclipse(Vector3(4, 0, 0)), "obstacle intermédiaire bloque une téléportation")
	player._eclipse.update(player, 0.3)
	check(player.global_position == Vector3(4, 0, 0), "traversée de l'obstacle échouée")
	wall.queue_free()
	prepare(player)
	await physics_frame
	check(player._perform_eclipse(Vector3(4, 0, 0)), "départ pour obstacle tardif refusé")
	wall = blocker(arena, Vector3(4, 0, 0))
	await physics_frame
	player._eclipse.update(player, 0.3)
	check(player.global_position != Vector3.ZERO and player.visible and player._eclipse.fits(player, player.global_position, false), "obstacle tardif ne rejoint pas une sortie libre")
	wall.queue_free()
	prepare(player)
	await physics_frame
	player.apply_stun(1.0, "test")
	check(not player.begin_touch_action("mobility"), "activation malgré stun")
	prepare(player)
	await physics_frame
	player._perform_eclipse(Vector3(4, 0, 0))
	player.reset_combat_state()
	await physics_frame
	player.begin_touch_action("mobility")
	player.reset_desktop_inputs()
	check(not player.is_eclipse_aiming() and player.get_module_cooldown("eclipse") == 0.0, "pause laisse une visée pendante")
	check(player.visible and not player.is_eclipse_travelling() and player.get_action_owner().is_empty(), "reset laisse une action ou collision perdue")
	await physics_frame
	Input.action_press("game_mobility")
	player._update_debug_effects()
	check(player.is_eclipse_aiming(), "maintien clavier ne démarre pas la visée")
	Input.action_release("game_mobility")
	player._update_debug_effects()
	check(player.is_eclipse_travelling(), "relâchement clavier ne téléporte pas")
	player.reset_combat_state()
	await physics_frame
	player.apply_burn(2.0, 20.0, "existing")
	player._perform_eclipse(Vector3(4, 0, 0))
	var before_burn := player.get_health()
	player._physics_process(0.1)
	check(player.get_health() == before_burn and player.is_eclipse_travelling(), "burn existant inflige des dégâts pendant le transit")
	player.reset_combat_state()
	await hit_effect_cases(arena, player)

	# Drive the actual touch overlay: one finger owns the button through its drag.
	prepare(player)
	var touch := TOUCH.new()
	arena.add_child(touch)
	touch.set_player(player)
	touch.set_editor_test(true)
	await physics_frame
	var center: Vector2 = touch._widget_center("mobility_button")
	check(touch._begin_touch(7, center), "contact du bouton non capturé")
	touch._update_touch(7, center + Vector2(touch._action_radius("mobility") * 2.2 / 3.0, 0))
	check(player._eclipse.destination.distance_to(Vector3(4, 0, 0)) < 0.01, "drag du bouton ne déplace pas la présélection")
	touch._end_touch(7)
	check(player.is_eclipse_travelling(), "relâchement tactile non exécuté")
	player.reset_combat_state()
	touch.queue_free()
	await process_frame
	var local_only := OS.get_cmdline_user_args().has("local_only")
	if not local_only:
		await network_cases(arena)
		check(network_exercised, "simulation réseau non exécutée")
	current_scene = null
	root.get_node("GameSfx").call("clear")
	arena.queue_free()
	await process_frame
	await process_frame
	for failure in failures:
		push_error(failure)
	var label := "ECLIPSE LOCAL TEST" if local_only else "ECLIPSE TEST"
	print(label + ": PASS" if failures.is_empty() else label + ": FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func hit_effect_cases(arena: Node3D, player: CharacterBody3D) -> void:
	var previous_targets: Array = arena.targets.duplicate()
	var victim := PLAYER.new()
	arena.add_child(victim)
	prepare(victim)
	victim.position = Vector3(4, 0, 2.5)
	arena.targets = [victim]
	prepare(player)
	victim.combat_state.grant_shield(200.0, 10.0)
	var before: float = victim.get_health()
	await physics_frame
	check(player._perform_eclipse(Vector3(4, 0, 0)), "test de cible protégée : départ refusé")
	player._eclipse.update(player, 0.3)
	check(victim.get_health() == before and victim.get_shield_health() == 80.0, "explosion ne réduit pas le bouclier adverse")
	check(victim.combat_state.has_effect("BURN") and player.get_shield_health() == 150.0, "impact absorbé ne déclenche pas burn et bouclier")
	victim.combat_state.update(1.0)
	check(victim.get_shield_health() == 60.0, "burn ne produit pas 20 dégâts par seconde")
	player.combat_state.update(3.01)
	check(player.get_shield_health() == 0.0, "bouclier ne disparaît pas après 3 s")
	prepare(player)
	prepare(victim)
	victim.position = Vector3(4, 0, 2.5)
	victim.training_invulnerable = true
	await physics_frame
	player._perform_eclipse(Vector3(4, 0, 0))
	player._eclipse.update(player, 0.3)
	check(player.get_shield_health() == 0.0 and not victim.combat_state.has_effect("BURN"), "cible invulnérable déclenche les effets sur impact")
	victim.training_invulnerable = false
	prepare(player)
	victim.position = Vector3(6.5, 0, 0)
	var wall := blocker(arena, Vector3(5.5, 0, 0))
	await physics_frame
	check(player._perform_eclipse(Vector3(4, 0, 0)), "test de couvert : départ refusé")
	player._eclipse.update(player, 0.3)
	check(victim.get_health() == before and not victim.combat_state.has_effect("BURN") and player.get_shield_health() == 0.0, "couvert ne bloque pas dégâts et effets d'explosion")
	wall.queue_free()
	victim.queue_free()
	arena.targets = previous_targets
	prepare(player)
	await physics_frame

func network_cases(arena: Node3D) -> void:
	var network_script = load("res://scripts/network_player.gd")
	if not network_script.can_instantiate():
		check(false, "contrôleur réseau non compilable")
		return
	var host = network_script.new()
	var replica = network_script.new()
	replica.authoritative = false
	replica.remote_controlled = true
	arena.add_child(host)
	arena.add_child(replica)
	prepare(host)
	prepare(replica)
	host.position = Vector3(-10, 0, 0)
	replica.position = host.position
	host.opponent = replica
	replica.opponent = host
	var victim = network_script.new()
	var victim_replica = network_script.new()
	victim_replica.authoritative = false
	victim_replica.remote_controlled = true
	arena.add_child(victim)
	arena.add_child(victim_replica)
	prepare(victim)
	prepare(victim_replica)
	victim.position = Vector3(-6, 0, 2.5)
	victim_replica.position = victim.position
	victim.opponent = host
	arena.targets.append(victim)
	await physics_frame
	host.receive_action("eclipse", {"destination": Vector3(-6, 0, 0)})
	check(host.is_eclipse_travelling(), "requête réseau refusée")
	var during: Dictionary = host.network_snapshot()
	replica.receive_snapshot(during)
	check(replica.is_eclipse_travelling() and not replica.visible, "snapshot ne restaure pas le transit")
	host._eclipse.update(host, 0.3)
	replica.receive_snapshot(host.network_snapshot())
	check(replica.visible and not replica.is_eclipse_travelling() and replica.position == host.position, "arrivée réseau incohérente")
	check(host.get_shield_health() == 150.0 and replica.get_shield_health() == 150.0, "bouclier d'impact désynchronisé")
	victim_replica.receive_snapshot(victim.network_snapshot())
	check(victim.combat_state.has_effect("BURN") and victim_replica.combat_state.has_effect("BURN"), "burn d'impact désynchronisé")
	var victim_health: float = victim.get_health()
	victim.combat_state.update(1.0)
	victim_replica.receive_snapshot(victim.network_snapshot())
	check(victim.get_health() == victim_health - 20.0 and victim_replica.get_health() == victim.get_health(), "dégâts du burn réseau incohérents")
	replica.receive_snapshot(during)
	check(not replica.is_eclipse_travelling(), "snapshot ancien relance le transit")
	prepare(replica)
	replica.remote_controlled = false
	await physics_frame
	replica._perform_eclipse(Vector3(4, 0, 0))
	var rejected: Dictionary = host.network_snapshot()
	rejected.eclipse = {"serial": 0, "remaining": 0.0}
	rejected.position = Vector3.ZERO
	replica.receive_snapshot(rejected, true)
	check(replica.visible and not replica.is_eclipse_travelling() and replica.position == Vector3.ZERO, "rejet hôte laisse un transit prédit")
	network_exercised = true
