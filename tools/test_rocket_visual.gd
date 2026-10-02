extends SceneTree

const ROCKET := preload("res://scripts/homing_rocket.gd")
const VISUAL := preload("res://scripts/rocket_visual.gd")
const NETWORK := preload("res://scripts/network_player.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var actor := StaticBody3D.new()
	scene.add_child(actor)
	var rocket := ROCKET.new()
	rocket.configure(actor, "visual:lifecycle", Vector3.FORWARD)
	scene.add_child(rocket)
	rocket.set_physics_process(false)
	rocket.position = Vector3(0, 1, 0)
	await create_timer(0.10).timeout
	var visual: Node3D = rocket.get("_visual")
	var smoke := visual.get("_smoke") as GPUParticles3D
	check(not smoke.local_coords and smoke.emitting, "La fumée reste dans le monde pendant les virages")
	check(not visual.get("_health_bar").visible, "Une salve intacte reste lisible sans cinq barres flottantes")
	var collision_before: Transform3D = rocket.global_transform
	rocket.direction = Vector3(0, 1, 0)
	rocket._update_visual()
	await process_frame
	await process_frame
	check(rocket.global_transform.is_equal_approx(collision_before), "L'inclinaison visuelle ne modifie pas la collision, même en vol vertical")
	rocket.take_damage(20.0, "test", "damage")
	await process_frame
	check(visual.get("_health_bar").visible, "Les PV apparaissent quand une roquette est endommagée")
	rocket.take_damage(20.0, "test", "destroy")
	await process_frame
	await process_frame
	check(not is_instance_valid(rocket), "Une interception libère immédiatement le projectile")
	check(get_nodes_in_group(VISUAL.BURST_GROUP).size() == 1, "Une interception déclenche un seul éclatement")
	check(get_nodes_in_group(VISUAL.WAKE_GROUP).size() == 1, "La fumée survit brièvement au projectile")
	await create_timer(1.35).timeout
	check(get_nodes_in_group(VISUAL.BURST_GROUP).is_empty() and get_nodes_in_group(VISUAL.WAKE_GROUP).is_empty(), "Explosions et fumée se nettoient complètement")
	rocket = ROCKET.new()
	rocket.configure(actor, "visual:reset", Vector3.FORWARD)
	scene.add_child(rocket)
	rocket._destroy()
	await process_frame
	check(get_nodes_in_group(VISUAL.BURST_GROUP).is_empty(), "Un reset ne déclenche pas de fausse explosion")
	for index in range(VISUAL.MAX_BURSTS + 5):
		VISUAL.spawn_burst(scene, Vector3(index, 1, 0))
	await process_frame
	await process_frame
	check(get_nodes_in_group(VISUAL.BURST_GROUP).size() == VISUAL.MAX_BURSTS, "Les explosions simultanées respectent leur budget")
	for effect in get_nodes_in_group("prototype0_fx_budget"):
		effect.queue_free()
	await process_frame
	var replica := NETWORK.new()
	replica.authoritative = false
	replica.remote_controlled = true
	scene.add_child(replica)
	replica.call("set_gameplay_enabled", true)
	replica.receive_action("rocket_end", {"sound": "rocket_impact", "center": Vector3(1, 1, 0), "normal": Vector3.LEFT}, true)
	check(get_nodes_in_group(VISUAL.BURST_GROUP).size() == 1, "L'impact réseau affiche aussi l'explosion")
	replica.receive_action("rocket_end", {"sound": "rocket_destroyed", "center": Vector3(2, 1, 0)}, true)
	check(get_nodes_in_group(VISUAL.BURST_GROUP).size() == 2, "Les anciens événements sans direction restent compatibles")
	replica.receive_action("rocket_end", {"sound": "invalid"}, true)
	check(get_nodes_in_group(VISUAL.BURST_GROUP).size() == 2, "Un événement inconnu ne produit aucun effet")
	for effect in get_nodes_in_group("prototype0_fx_budget"):
		effect.queue_free()
	await process_frame
	check(get_nodes_in_group("prototype0_fx_budget").is_empty(), "Le nettoyage de manche peut retirer tous les effets")
	for failure in failures:
		push_error(failure)
	print("TEST ROCKET VISUAL: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	root.get_node("GameSfx").clear()
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
