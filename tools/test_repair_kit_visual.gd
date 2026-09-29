extends SceneTree

class RepairActor:
	extends CharacterBody3D

	var health := 500.0
	var maximum_health := 1000.0
	var dead := false

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.35
		shape.height = 1.4
		collision.shape = shape
		collision.position.y = 0.7
		add_child(collision)

	func heal(amount: float, _source: String = "") -> float:
		if dead or health <= 0.0 or health >= maximum_health:
			return 0.0
		var applied := minf(amount, maximum_health - health)
		health += applied
		return applied

	func get_health() -> float:
		return health

	func get_max_health() -> float:
		return maximum_health

	func is_real_dead() -> bool:
		return dead


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var kit_scene := load("res://scenes/repair_kit.tscn") as PackedScene
	var first := kit_scene.instantiate() as Area3D
	var second := kit_scene.instantiate() as Area3D
	first.name = "FirstKit"
	second.name = "SecondKit"
	second.position.x = 5.0
	world.add_child(first)
	world.add_child(second)
	first.call("set_collection_active", false)
	second.call("set_collection_active", false)
	var actor_a := RepairActor.new()
	var actor_b := RepairActor.new()
	actor_a.position = Vector3(20.0, 0.0, 20.0)
	actor_b.position = Vector3(22.0, 0.0, 20.0)
	world.add_child(actor_a)
	world.add_child(actor_b)
	await process_frame
	await physics_frame

	_check(is_equal_approx(float(first.get("visual_scale")), 1.75), "échelle visuelle x1,75 exposée")
	_check(is_equal_approx(float(first.call("get_collection_radius")), 1.45), "rayon de collecte inchangé et séparé")
	_check(first.call("get_visual_state_name") == "available", "état initial AVAILABLE")
	_check((first.get_node("ConsumableKit/GroundHalo") as Node3D).visible, "halo vert visible quand disponible")
	_check(not (first.get_node("ConsumableKit/RechargeBar") as Node3D).visible, "barre masquée quand disponible")
	_check(first.get("_available_face_material") != second.get("_available_face_material"), "matériaux propres à chaque kit")

	actor_a.health = actor_a.maximum_health
	actor_a.global_position = first.global_position
	first.call("set_collection_active", true)
	_check(is_zero_approx(float(first.call("try_collect", actor_a))), "pleine vie ne consomme pas")
	_check(first.call("get_visual_state_name") == "available", "pleine vie conserve AVAILABLE")

	actor_a.health = 500.0
	actor_b.health = 500.0
	actor_b.global_position = first.global_position
	var first_result := float(first.call("try_collect", actor_a))
	var second_result := float(first.call("try_collect", actor_b))
	_check(is_equal_approx(first_result, 300.0) and is_zero_approx(second_result), "collecte contestée : un seul bénéficiaire")
	_check(is_equal_approx(actor_a.health, 800.0) and is_equal_approx(actor_b.health, 500.0), "soin 30 % inchangé")
	_check(first.call("get_visual_state_name") == "recharging" and second.call("get_visual_state_name") == "available", "états indépendants sur plusieurs kits")
	var first_visual := first.get_node("ConsumableKit") as Node3D
	var halo := first.get_node("ConsumableKit/GroundHalo") as Node3D
	var bar := first.get_node("ConsumableKit/RechargeBar") as Node3D
	var fill := first.get_node("ConsumableKit/RechargeBar/Fill") as MeshInstance3D
	var face := first.get_node("ConsumableKit/FloatingCross/CrossFaceX") as MeshInstance3D
	var face_material := face.material_override as StandardMaterial3D
	_check(first_visual.visible and not halo.visible and bar.visible, "croix grise persistante, halo coupé, barre visible")
	_check(face_material != null and not face_material.emission_enabled and face_material.albedo_color.is_equal_approx(Color("#858c8a")), "matériau gris mat")
	_check(not fill.visible, "barre vide immédiatement")
	first.set("_respawn_remaining", 10.0)
	first.call("_update_recharge_bar")
	_check(fill.visible and is_equal_approx(fill.scale.x, 0.5), "barre à 50 % depuis le timer")
	first.set("_respawn_remaining", 5.0)
	first.call("_update_recharge_bar")
	_check(is_equal_approx(fill.scale.x, 0.75) and fill.position.x < 0.0, "remplissage progressif gauche-droite")

	first.call("set_collection_active", false)
	first.call("_respawn")
	_check(first.call("get_visual_state_name") == "available" and halo.visible and not bar.visible, "retour simultané du vert et disparition de la barre")
	_check((first.get_node("ConsumableKit/FloatingCross") as Node3D).scale.x < 1.0, "impulsion courte au retour")

	actor_b.global_position = Vector3(20.0, 0.0, 20.0)
	actor_b.force_update_transform()
	first.respawn_delay = 0.05
	first.call("reset_for_round", false)
	actor_a.health = 400.0
	actor_a.global_position = first.global_position
	actor_a.force_update_transform()
	await physics_frame
	first.call("set_collection_active", true)
	_check(float(first.call("try_collect", actor_a)) > 0.0, "ramassage avant test d'occupation")
	actor_a.health -= 200.0
	var before_respawn := actor_a.health
	await create_timer(0.12).timeout
	await physics_frame
	_check(actor_a.health > before_respawn, "acteur déjà présent soigné à la réapparition")

	first.call("reset_for_round", false)
	_check(first.call("get_visual_state_name") == "available" and is_zero_approx(float(first.call("get_respawn_remaining"))), "redémarrage de manche restaure état et timer")

	world.queue_free()
	await process_frame
	if _failures.is_empty():
		print("REPAIR KIT VISUAL TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("REPAIR KIT VISUAL TEST: %s" % failure)
	print("REPAIR KIT VISUAL TEST: FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
