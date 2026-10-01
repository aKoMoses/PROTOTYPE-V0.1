extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const NETWORK_PLAYER := preload("res://scripts/network_player.gd")
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.call("set_gameplay_enabled", true)
	player.call("set_training_options", false, false, false)
	player.set_physics_process(false)
	player.get_node("WeaponAimGuide").set_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	for actor in [player, target]:
		for hz in [15, 30, 60, 120]:
			actor.call("reset_combat_state")
			actor.global_position = Vector3(0, 0, 60)
			actor.call("start_fulguro_projection", Vector3.RIGHT, 4.0, 0.35, 150.0, 0.75, "test", "curve_%d" % hz)
			var previous_step := INF
			for _tick in range(ceili(0.35 * hz)):
				var before: Vector3 = actor.global_position
				actor.call("_update_fulguro_projection", 1.0 / hz)
				var distance: float = before.distance_to(actor.global_position)
				_check(distance <= previous_step + 0.0001, "Le recul doit ralentir à chaque tick (%d Hz)" % hz)
				previous_step = distance
			_check(absf(actor.global_position.x - 4.0) < 0.002, "Distance identique à %d Hz" % hz)
			_check(not bool(actor.call("is_fulguro_projected")), "Le contrôle revient après la projection")
			_check(is_equal_approx(float(actor.call("get_health")), float(actor.call("get_max_health"))), "Pas de dégâts muraux sans mur")
		actor.call("reset_combat_state")
		actor.global_position = Vector3(0, 0, 60)
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1, 2, 4)
		collision.shape = box
		wall.add_child(collision)
		scene.add_child(wall)
		wall.global_position = Vector3(2, 1, 60)
		await physics_frame
		actor.call("start_fulguro_projection", Vector3.RIGHT, 4.0, 0.35, 150.0, 0.75, "test", "wall_curve")
		actor.call("_update_fulguro_projection", 0.35)
		_check(actor.global_position.x < 1.5, "Une grande frame ne traverse pas un mur fin")
		_check(is_equal_approx(float(actor.call("get_health")), float(actor.call("get_max_health")) - 150.0) and actor.get("combat_state").is_stunned(), "Fulguro conserve les dégâts et le stun contre un mur")
		actor.call("reset_combat_state")
		actor.global_position = Vector3(0, 0, 60)
		actor.call("start_knockback", Vector3.RIGHT, 5.5, 0.42, "projector")
		actor.call("_update_fulguro_projection", 0.42)
		_check(actor.global_position.x < 1.5 and not actor.get("combat_state").is_stunned() and is_equal_approx(float(actor.call("get_health")), float(actor.call("get_max_health"))), "Projector s'arrête au mur sans ajouter les dégâts de Fulguro")
		wall.queue_free()
		await physics_frame
		actor.call("reset_combat_state")
		actor.call("start_knockback", Vector3.RIGHT, 5.5, 0.42, "projector")
		actor.call("reset_combat_state")
		var reset_position: Vector3 = actor.global_position
		actor.call("_update_fulguro_projection", 0.42)
		_check(actor.global_position.is_equal_approx(reset_position), "Le reset annule le déplacement restant")
	if _failures.is_empty():
		print("KNOCKBACK TEST: PASS (15/30/60/120 Hz, décélération, distance, murs, dégâts, reset)")
	else:
		for failure in _failures:
			push_error(failure)
	scene.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
