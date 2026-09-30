extends SceneTree

var _failures: Array[String] = []
var _heard_repair_sound := false


func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	call_deferred("_run")


func _run() -> void:
	var game_sfx: Node = root.get_node_or_null("GameSfx")
	if game_sfx != null:
		game_sfx.connect("event_played", Callable(self, "_on_sfx_event"))
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame
	var player := scene.get_node("Player") as Node3D
	var bot := scene.get_node("TargetDummy") as Node3D
	var kits := get_nodes_in_group("repair_kits")
	kits.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	_check(kits.size() == 4, "quatre points de réparation présents")
	for kit in kits:
		_check(kit is Area3D and (kit as Area3D).collision_layer == 0, "%s ne bloque pas les déplacements" % kit.name)
		_check(is_equal_approx(float(kit.get("heal_fraction")), 0.30), "%s soigne 30 %% des PV maximum" % kit.name)
		_check(is_equal_approx(float(kit.get("respawn_delay")), 20.0), "%s réapparaît après 20 s" % kit.name)
		_check(is_equal_approx(float(kit.get("visual_scale")), 1.75), "%s expose l'échelle visuelle x1,75" % kit.name)
		_check(is_equal_approx(float(kit.get("collection_radius")), 1.45), "%s conserve un rayon de collecte indépendant" % kit.name)
		_check(kit.get_node_or_null("PermanentBase") != null and kit.get_node_or_null("ConsumableKit") != null, "%s sépare socle et kit" % kit.name)
		_check((kit.get_node("ConsumableKit") as Node3D).visible, "%s affiche la croix disponible" % kit.name)
		_check((kit.get_node("ConsumableKit/GroundHalo") as Node3D).visible, "%s affiche le halo vert disponible" % kit.name)
		_check(not (kit.get_node("ConsumableKit/RechargeBar") as Node3D).visible, "%s masque la barre hors recharge" % kit.name)

	var kit: Node = scene.get_node("HealthPadNorth")
	_test_independent_kits(player, kits)
	_test_full_health_does_not_consume(player, kit)
	await _test_automatic_fast_pass(player, kit)
	_test_fraction_cap_and_status(player, kit)
	_test_single_consumer(player, bot, kit)
	_test_dead_actor(bot, kit)
	await _test_wall_occlusion(scene, player)
	await _test_respawn_with_occupant(player, kit)
	_test_round_reset(scene, player, kit)
	_test_bot_decision(scene, player, bot)
	_check(_heard_repair_sound, "son distinct joué au ramassage")
	scene.queue_free()
	await process_frame

	if _failures.is_empty():
		print("REPAIR KIT TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("REPAIR KIT TEST: %s" % failure)
	print("REPAIR KIT TEST: FAIL (%d)" % _failures.size())
	quit(1)


func _test_full_health_does_not_consume(player: Node3D, kit: Node) -> void:
	player.call("reset_combat_state")
	kit.call("reset_for_round", false)
	player.global_position = kit.global_position
	kit.call("set_collection_active", true)
	var applied := float(kit.call("try_collect", player))
	_check(is_zero_approx(applied), "un acteur à pleine vie ne consomme pas le kit")
	_check(bool(kit.call("is_available")), "le kit reste disponible à pleine vie")


func _test_independent_kits(player: Node3D, kits: Array[Node]) -> void:
	var first := kits[0]
	var second := kits[1]
	first.call("reset_for_round", false)
	second.call("reset_for_round", false)
	var first_available_material: Material = first.get("_available_face_material") as Material
	var second_available_material: Material = second.get("_available_face_material") as Material
	_check(first_available_material != second_available_material, "chaque kit possède ses propres matériaux")
	player.call("reset_combat_state")
	player.call("take_damage", 400.0, "test", "repair_independent")
	player.global_position = first.global_position
	first.call("set_collection_active", true)
	first.call("try_collect", player)
	_check(first.call("get_visual_state_name") == "recharging", "le kit pris passe en état RECHARGING")
	_check(second.call("get_visual_state_name") == "available", "prendre un kit ne grise pas les autres")
	var first_face := first.get_node("ConsumableKit/FloatingCross/CrossFaceX") as MeshInstance3D
	var second_face := second.get_node("ConsumableKit/FloatingCross/CrossFaceX") as MeshInstance3D
	_check(first_face.material_override != second_face.material_override, "états visuels indépendants entre plusieurs kits")
	_check((second.get_node("ConsumableKit/GroundHalo") as Node3D).visible, "le halo du second kit reste actif")
	first.call("reset_for_round", false)
	second.call("reset_for_round", false)


func _test_automatic_fast_pass(player: Node3D, kit: Node) -> void:
	player.call("reset_combat_state")
	kit.call("reset_for_round", false)
	player.call("take_damage", 500.0, "test", "repair_fast_pass")
	player.global_position = kit.global_position + Vector3(2.55, 0.0, 0.0)
	player.force_update_transform()
	await physics_frame
	kit.call("set_collection_active", true)
	player.set("_last_move_direction", Vector3.LEFT)
	player.call("_perform_mobility_module")
	var dash_started := bool(player.call("is_dash_active"))
	for _frame in range(30):
		await physics_frame
		if not bool(player.call("is_dash_active")):
			break
	_check(dash_started, "dash de validation déclenché")
	_check(is_equal_approx(float(player.call("get_health")), 800.0), "dash collecte automatiquement le kit")
	_check(not bool(kit.call("is_available")), "dash ne consomme le kit qu'une fois")


func _test_fraction_cap_and_status(player: Node3D, kit: Node) -> void:
	player.call("reset_combat_state")
	kit.call("reset_for_round", false)
	player.call("take_damage", 500.0, "test", "repair_fraction")
	player.call("apply_slow", 5.0, 20.0, "test_slow")
	player.global_position = kit.global_position
	kit.call("set_collection_active", true)
	var applied := float(kit.call("try_collect", player))
	_check(is_equal_approx(applied, 300.0), "soin égal à 30 % des PV maximum")
	_check(is_equal_approx(float(player.call("get_health")), 800.0), "barre de vie mise à jour avec le soin")
	var healing_popup: Node = null
	var readout: Node = player.get_node_or_null("WorldUIAnchor/PlayerHealthReadout")
	if readout != null:
		for child in readout.get_children():
			if str(child.name).begins_with("HealingNumber"):
				healing_popup = child
	var healing_label: Label3D = healing_popup.get("_label") as Label3D if healing_popup != null else null
	_check(healing_label != null and healing_label.text == "+300", "montant réellement récupéré affiché immédiatement")
	_check("SLOW" in (player.call("get_active_effect_types") as Array), "le soin conserve les effets de statut")
	_check(not bool(kit.call("is_available")), "kit indisponible pendant la recharge")
	var kit_visual := kit.get_node("ConsumableKit") as Node3D
	var ground_halo := kit.get_node("ConsumableKit/GroundHalo") as Node3D
	var recharge_bar := kit.get_node("ConsumableKit/RechargeBar") as Node3D
	var recharge_fill := kit.get_node("ConsumableKit/RechargeBar/Fill") as MeshInstance3D
	var grey_face := kit.get_node("ConsumableKit/FloatingCross/CrossFaceX") as MeshInstance3D
	var grey_material := grey_face.material_override as StandardMaterial3D
	_check(kit_visual.visible and (kit.get_node("PermanentBase") as Node3D).visible, "le kit reste présent avec sa silhouette après ramassage")
	_check(kit.call("get_visual_state_name") == "recharging", "apparence et collecte partagent l'état RECHARGING")
	_check(grey_material != null and not grey_material.emission_enabled and grey_material.albedo_color.is_equal_approx(Color("#858c8a")), "croix entièrement grise et mate pendant la recharge")
	_check(not ground_halo.visible, "halo vert désactivé pendant la recharge")
	_check(recharge_bar.visible and not recharge_fill.visible, "barre visible et vide immédiatement après consommation")
	var fill_material := recharge_fill.material_override as StandardMaterial3D
	_check(fill_material != null and fill_material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED, "barre orientée face à la caméra")
	kit.set("_respawn_remaining", 10.0)
	kit.call("_update_recharge_bar")
	_check(recharge_fill.visible and is_equal_approx(recharge_fill.scale.x, 0.5), "barre remplie à 50 % depuis le vrai timer")
	kit.set("_respawn_remaining", 5.0)
	kit.call("_update_recharge_bar")
	_check(is_equal_approx(recharge_fill.scale.x, 0.75), "remplissage progresse de gauche à droite avec le timer")
	kit.call("set_collection_active", false)
	kit.call("_respawn")
	_check(kit.call("get_visual_state_name") == "available" and ground_halo.visible and not recharge_bar.visible, "fin du timer restaure vert, halo et masque la barre")
	_check((kit.get_node("ConsumableKit/FloatingCross") as Node3D).scale.x < 1.0, "courte impulsion visuelle au retour")
	player.call("reset_combat_state")
	kit.call("reset_for_round", false)
	player.call("take_damage", 76.0, "test", "repair_cap")
	player.global_position = kit.global_position
	kit.call("set_collection_active", true)
	applied = float(kit.call("try_collect", player))
	_check(is_equal_approx(applied, 76.0) and is_equal_approx(float(player.call("get_health")), float(player.call("get_max_health"))), "soin plafonné et montant effectif exact")


func _test_single_consumer(player: Node3D, bot: Node3D, kit: Node) -> void:
	player.call("reset_combat_state")
	bot.call("reset_combat_state")
	kit.call("reset_for_round", false)
	player.call("take_damage", 400.0, "test", "repair_race_player")
	bot.call("take_damage", 400.0, "test", "repair_race_bot")
	player.global_position = kit.global_position
	bot.global_position = kit.global_position
	kit.call("set_collection_active", true)
	var first := float(kit.call("try_collect", player))
	var second := float(kit.call("try_collect", bot))
	_check(first > 0.0 and is_zero_approx(second), "une disponibilité ne soigne qu'un seul acteur")
	_check(is_equal_approx(float(bot.call("get_health")), 600.0), "le second acteur n'est pas soigné")


func _test_dead_actor(bot: Node3D, kit: Node) -> void:
	bot.call("reset_combat_state")
	kit.call("reset_for_round", false)
	bot.get("combat_state").apply_damage(float(bot.call("get_max_health")), "test", "repair_dead")
	bot.global_position = kit.global_position
	kit.call("set_collection_active", true)
	_check(is_zero_approx(float(kit.call("try_collect", bot))), "un personnage mort n'est ni soigné ni ressuscité")
	_check(bool(kit.call("is_available")), "un mort ne consomme pas le kit")
	bot.call("reset_combat_state")


func _test_wall_occlusion(scene: Node3D, player: Node3D) -> void:
	var probe := load("res://scenes/repair_kit.tscn").instantiate() as Area3D
	probe.name = "OcclusionRepairProbe"
	probe.position = Vector3(-3.0, 0.0, 0.0)
	scene.add_child(probe)
	probe.call("set_collection_active", false)
	var wall := StaticBody3D.new()
	wall.name = "RepairOcclusionProbe"
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(-2.35, 0.9, 0.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.18, 1.8, 2.2)
	collision.shape = shape
	wall.add_child(collision)
	scene.add_child(wall)
	player.call("reset_combat_state")
	player.call("take_damage", 300.0, "test", "repair_wall")
	player.global_position = Vector3(-1.75, 0.0, 0.0)
	await physics_frame
	probe.call("set_collection_active", true)
	_check(is_zero_approx(float(probe.call("try_collect", player))), "aucun ramassage à travers un obstacle")
	_check(bool(probe.call("is_available")), "l'occlusion ne consomme pas le kit")
	probe.queue_free()
	wall.queue_free()
	await process_frame


func _test_respawn_with_occupant(player: Node3D, kit: Node) -> void:
	player.call("reset_combat_state")
	kit.call("reset_for_round", false)
	kit.set("respawn_delay", 0.05)
	player.call("take_damage", 600.0, "test", "repair_respawn_first")
	player.global_position = kit.global_position
	player.force_update_transform()
	await physics_frame
	kit.call("set_collection_active", true)
	_check(float(kit.call("try_collect", player)) > 0.0, "premier ramassage avant réapparition")
	player.call("take_damage", 200.0, "test", "repair_respawn_waiting")
	var health_before := float(player.call("get_health"))
	await create_timer(0.12).timeout
	await physics_frame
	await process_frame
	_check(float(player.call("get_health")) > health_before, "acteur déjà sur le socle soigné à la réapparition")
	_check(not bool(kit.call("is_available")), "réapparition immédiatement consommée une seule fois")
	kit.set("respawn_delay", 20.0)


func _test_round_reset(scene: Node, player: Node3D, kit: Node) -> void:
	player.call("reset_combat_state")
	kit.call("reset_for_round", false)
	player.call("take_damage", 400.0, "test", "repair_round")
	player.global_position = kit.global_position
	kit.call("set_collection_active", true)
	kit.call("try_collect", player)
	_check(not bool(kit.call("is_available")), "kit consommé avant reset de manche")
	scene.call("prepare_round", {})
	_check(kit.call("get_visual_state_name") == "available" and is_zero_approx(float(kit.call("get_respawn_remaining"))), "reset de manche restaure kit et timer")
	_check(not bool(kit.call("is_available")), "collecte inactive pendant le décompte")


func _test_bot_decision(scene: Node, player: Node3D, bot: Node3D) -> void:
	scene.call("activate_round")
	bot.call("reset_combat_state")
	# Critical health is below every randomized archetype's repair threshold.
	bot.call("take_damage", float(bot.call("get_max_health")) * 0.70, "test", "repair_bot_seek")
	var controller := bot.get_node("TrainingBot")
	controller.set("_elapsed", 1.0)
	_check(bool(controller.call("_update_repair_target", bot, player)), "bot blessé recherche un kit disponible")
	var destination := controller.call("get_repair_target") as Node3D
	_check(destination != null, "bot choisit une destination de soin")
	if destination != null:
		destination.call("set_collection_active", false)
		controller.call("_update_repair_target", bot, player)
		_check(controller.call("get_repair_target") == null, "bot abandonne un kit devenu indisponible")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _on_sfx_event(event_id: String) -> void:
	if event_id == "repair_pickup":
		_heard_repair_sound = true
