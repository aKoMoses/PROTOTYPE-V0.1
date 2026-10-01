extends SceneTree

const WALL := preload("res://scripts/magnetic_wall.gd")
const LIVE := preload("res://scripts/live_projectile.gd")
const LONGSHOT := preload("res://scripts/longshot_projectile.gd")
const BOT := preload("res://scripts/training_bot.gd")
var failures: Array[String] = []
var checks := 0
var stage: Node3D
var owner_actor: CharacterBody3D
var enemy_actor: CharacterBody3D


func _initialize() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	call_deferred("_run")


func _run() -> void:
	owner_actor = _actor(4, Vector3(0, 0, 3))
	enemy_actor = _actor(2, Vector3(0, 0, -3))
	var wall := _wall(owner_actor)
	await _settle()
	for source in [owner_actor, enemy_actor]:
		for direction in [Vector3.FORWARD, Vector3.BACK]:
			for sphere in [false, true]:
				var origin: Vector3 = -direction * 2.0 + Vector3.UP
				var result := _shot(source, origin, direction, sphere)
				_check(result.hit.is_empty() if source == owner_actor else result.hit.get("collider") == wall,
					"tirs %s %s dans les deux sens" % ["propres" if source == owner_actor else "ennemis", "sphère" if sphere else "rayon"])
				await process_frame
	owner_actor.global_position = Vector3(0, 0, 2)
	var own_contact := owner_actor.move_and_collide(Vector3(0, 0, -4))
	_check(own_contact == null and owner_actor.global_position.z < -1.9, "le propriétaire traverse physiquement")
	owner_actor.global_position = Vector3(6, 0, 2)
	enemy_actor.global_position = Vector3(0, 0, -2)
	var enemy_contact := enemy_actor.move_and_collide(Vector3(0, 0, 4))
	_check(enemy_contact != null and enemy_actor.global_position.z < -0.3, "l'adversaire est arrêté physiquement à grande vitesse")
	var bot := BOT.new()
	stage.add_child(bot)
	owner_actor.global_position = Vector3(0, 0, 2)
	enemy_actor.global_position = Vector3(0, 0, -2)
	var own_motion: Vector3 = bot.call("_safe_bot_motion", owner_actor, Vector3(0, 0, -4))
	var enemy_motion: Vector3 = bot.call("_safe_bot_motion", enemy_actor, Vector3(0, 0, 4))
	_check(own_motion.length() > 3.99, "le bot propriétaire traverse son mur")
	_check(enemy_motion.length() < 1.8, "la hitbox du bot adverse est bloquée")
	var late_actor := _actor(2, Vector3(0, 0, -2))
	await _settle()
	_check(late_actor.move_and_collide(Vector3(0, 0, 4)) != null, "un acteur apparu après le mur est bloqué")
	late_actor.queue_free()
	owner_actor.global_position = Vector3(6, 0, 3)
	enemy_actor.global_position = Vector3(6, 0, -3)
	for sphere in [false, true]:
		var overlap := _shot(enemy_actor, Vector3(0, 1, 0), Vector3.FORWARD, sphere)
		_check(overlap.hit.get("collider") == wall, "un tir adverse déjà dans le mur est arrêté")
		await process_frame
	var hostile_wall := _wall(enemy_actor, Vector3(0, 0, -1))
	await _settle()
	var both_exclusions := WALL.owned_exclusions(stage, [owner_actor.get_rid(), enemy_actor.get_rid()])
	_check(both_exclusions.has(wall.get_rid()) and not both_exclusions.has(hostile_wall.get_rid()), "exclure une cible ne rend pas son mur traversable")
	var result := _shot(owner_actor, Vector3(0, 1, 2), Vector3.FORWARD, true)
	_check(result.hit.get("collider") == hostile_wall, "un tir traverse son mur puis touche le mur adverse")
	wall.queue_free()
	hostile_wall.queue_free()
	await _settle()
	for sphere in [false, true]:
		var projectile: Node3D = LONGSHOT.new() if sphere else LIVE.new()
		stage.add_child(projectile)
		projectile.global_position = Vector3(0, 1, 2)
		projectile.set_physics_process(false)
		var excluded: Array[RID] = [owner_actor.get_rid()]
		if sphere:
			projectile.configure(Vector3.FORWARD, 20.0, 8.0, 8, excluded, 0.075)
		else:
			projectile.configure(Vector3.FORWARD, 20.0, 8.0, 8, excluded)
		var record := {"hit": {}}
		projectile.finished.connect(func(hit: Dictionary, _distance: float) -> void: record.hit = hit)
		var new_wall := _wall(owner_actor)
		await _settle()
		projectile._physics_process(0.4)
		_check(record.hit.is_empty(), "un mur déployé après le tir laisse passer son projectile")
		new_wall.queue_free()
		await _settle()
	stage.queue_free()
	await process_frame
	await _survival_runtime()
	for failure in failures:
		push_error(failure)
	print("MAGNETIC WALL: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _survival_runtime() -> void:
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	scene.set("records_path", "user://test_wall_survival.json")
	root.add_child(scene)
	current_scene = scene
	await _settle()
	scene.call("_choose_weapon", "blaster")
	scene.call("_begin_wave_combat")
	scene.call("_clear_enemies")
	var player := scene.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0, 2)
	scene.call("_spawn_enemy", Vector3(0, 0, -4), "shooter")
	var enemies: Array = scene.get("_enemies")
	var enemy: Node3D = enemies[0]
	enemy.call("set_training_bot_enabled", false)
	var wall := WALL.new()
	wall.configure(player, 4.0, 2.4, 10.0)
	scene.add_child(wall)
	await _settle()
	var before := float(enemy.call("get_health"))
	player.call("_spawn_blaster_projectile", Vector3(0, 1, 1), 20.0, 0.0, 1, Vector3.FORWARD)
	await create_timer(0.4).timeout
	_check(float(enemy.call("get_health")) < before, "le vrai Blaster traverse le Wall en survie")
	var health := float(player.call("get_health"))
	var bot := enemy.get_node("TrainingBot")
	bot.set("_charge_target", player.global_position)
	bot.call("_spawn_attack_visual", player, "wall_survival_enemy")
	await create_timer(0.5).timeout
	_check(is_equal_approx(float(player.call("get_health")), health), "le vrai tir ennemi est absorbé en survie")
	_check(float(wall.get("_impact_age")) < 0.5, "le projectile absorbé déclenche l'onde visuelle")
	scene.queue_free()
	await process_frame


func _actor(layer: int, position_value: Vector3) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.collision_layer = layer
	actor.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	actor.add_child(collision)
	stage.add_child(actor)
	actor.global_position = position_value
	return actor


func _wall(actor: CollisionObject3D, position_value := Vector3.ZERO) -> Area3D:
	var wall := WALL.new()
	wall.configure(actor, 4.0, 2.4, 10.0)
	stage.add_child(wall)
	wall.global_position = position_value
	return wall


func _shot(actor: CollisionObject3D, origin: Vector3, direction: Vector3, sphere: bool) -> Dictionary:
	var projectile: Node3D = LONGSHOT.new() if sphere else LIVE.new()
	stage.add_child(projectile)
	projectile.global_position = origin
	projectile.set_physics_process(false)
	var excluded: Array[RID] = [actor.get_rid()]
	if sphere:
		projectile.configure(direction, 20.0, 4.0, 8, excluded, 0.075)
	else:
		projectile.configure(direction, 20.0, 4.0, 8, excluded)
	var record := {"hit": {}}
	projectile.finished.connect(func(hit: Dictionary, _distance: float) -> void: record.hit = hit)
	projectile._physics_process(0.2)
	return record


func _settle() -> void:
	await physics_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
