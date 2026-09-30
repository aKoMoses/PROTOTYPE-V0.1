extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const BUILDS := preload("res://scripts/bot_build_presets.gd")
const DUEL_BUILDS := preload("res://scripts/duel_bot_builds.gd")

var _failures: Array[String] = []
var _elapsed := 0.0
var _hits: Array[Dictionary] = []


class FriendlyBot extends StaticBody3D:
	var health := 1000.0
	var hits := 0
	func take_damage(amount: float, _source: String = "", _attack_id: String = "") -> float:
		hits += 1
		health -= amount
		return amount


class OpenMotionController extends Node:
	func _safe_bot_motion(_body: Node3D, motion: Vector3) -> Vector3:
		return motion


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.set("menu_mode", false)
	var actor := scene.get_node("TargetDummy") as Node3D
	var player := scene.get_node("Player") as Node3D
	var bot := actor.get_node("TrainingBot")
	var equipment := bot.get_node("DuelEquipment")
	player.call("set_gameplay_enabled", true)
	player.call("set_passive", "omnivamp")
	player.set_physics_process(false)
	actor.call("set_duel_mode", true)
	actor.call("set_training_bot_enabled", false)
	actor.set_process(false)
	actor.set_physics_process(false)
	_test_catalog()
	_prepare(actor, player, equipment)
	_check(str(equipment.get("profile")) == "mekatana", "MEKATANA équipé par le bot")
	_check(float(bot.call("_ideal_combat_range")) <= 2.3, "distance idéale adaptée à la mêlée")
	player.global_position = actor.global_position + Vector3.FORWARD * 8.0
	_tick(actor, player, bot, equipment)
	_check(not equipment.get("_mekatana").is_busy(), "pas d'attaque de mêlée à huit mètres")
	await _test_held_combo(actor, player, bot, equipment)
	await _test_dash_distances(actor, player, bot, equipment)
	await _test_combo_spacing(actor, player, bot, equipment)
	await _test_direction_and_interruptions(actor, player, bot, equipment)
	await _test_feedback(actor, player, bot, equipment, scene)
	await _test_no_friendly_fire(actor, player, bot, equipment, scene)
	await _test_collision_motion(actor, player, bot, equipment, scene)
	root.get_node("GameSfx").call("clear")
	_stop_test_audio(scene)
	scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(0.10).timeout
	if _failures.is_empty():
		print("MEKATANA BOT TEST: PASS")
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("MEKATANA BOT TEST: FAIL (%d)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _stop_test_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.call("stop")
	for child in node.get_children():
		_stop_test_audio(child)


func _test_catalog() -> void:
	var has_melee := false
	for definition in BUILDS.PRESETS:
		if str(definition.weapon) == "mekatana":
			has_melee = true
			_check(float(definition.personality.ideal_range) < 3.3, "preset utilise une portée proche")
	_check(has_melee, "preset aléatoire MEKATANA présent")
	var has_duel_melee := false
	for definition in DUEL_BUILDS.BUILDS:
		if str(definition.weapon) == "mekatana":
			has_duel_melee = true
	_check(has_duel_melee, "build de duel MEKATANA présent")
	_check(LOADOUT.sanitize({"weapon": "mekatana"}).weapon == "mekatana", "catalogue conserve MEKATANA")


func _prepare(actor: Node3D, player: Node3D, equipment: Node) -> void:
	actor.call("set_duel_loadout", {"weapon": "mekatana", "robot": "polyvalent", "offensive": "fulguro_punch", "defensive": "magnetic_field", "mobility": "bio_injector", "passive": "omnivamp"})
	actor.call("reset_combat_state")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	actor.global_position = Vector3.ZERO
	player.global_position = Vector3.FORWARD * 2.0
	equipment.set("next_attack_at", 0.0)
	equipment.set("_next_module_at", 10000.0)
	_elapsed = 0.0
	_hits.clear()


func _tick(actor: Node3D, player: Node3D, bot: Node, equipment: Node, visible: bool = true, delta: float = 0.01) -> void:
	_elapsed += delta
	equipment.call("tick", delta, _elapsed, visible, player.global_position, actor, player, bot, {"line_of_fire": visible, "velocity": Vector3.ZERO}, {"aim_error_degrees": 0.0, "prediction_quality": 0.0, "module_skill": 0.0})


func _record_hit(_target: Node, applied: float, multiplier: float, melee) -> void:
	_hits.append({"step": int(melee.step), "applied": applied, "multiplier": multiplier})


func _test_held_combo(actor: Node3D, player: Node3D, bot: Node, equipment: Node) -> void:
	_prepare(actor, player, equipment)
	_tick(actor, player, bot, equipment)
	var melee = equipment.get("_mekatana")
	melee.hit.connect(Callable(self, "_record_hit").bind(melee))
	for _frame in range(400):
		# Each committed dash ends one metre ahead of the same stationary foe.
		# Reposition only between swings, preserving that actor's combo history.
		if not melee.is_busy() or melee.phase == "recovery":
			player.global_position = actor.global_position + Vector3.FORWARD * (float(equipment.call("get_mekatana_dash_distance")) + 1.0)
		_tick(actor, player, bot, equipment, _hits.size() < 3)
		if _hits.size() >= 3 and not melee.is_busy():
			break
		await physics_frame
	_check(_hits.size() == 3, "maintien bot : exactement trois touches")
	if _hits.size() == 3:
		for index in range(3):
			_check(int(_hits[index].step) == index, "maintien bot : ordre des coups %d" % index)
		var expected := [65.0, 90.0, 160.0]
		for index in range(3):
			_check(absf(float(_hits[index].applied) - expected[index]) < 0.01, "bonus bot : coup %d" % (index + 1))
	_check(not melee.is_busy() and str(equipment.call("get_action_owner")) == "", "fin du maintien libère le cast")
	var hits_after_release := _hits.size()
	for _frame in range(12):
		_tick(actor, player, bot, equipment, false)
	_check(_hits.size() == hits_after_release and not melee.is_busy(), "perte de cible arrête les attaques futures")


func _test_dash_distances(actor: Node3D, player: Node3D, bot: Node, equipment: Node) -> void:
	_prepare(actor, player, equipment)
	_tick(actor, player, bot, equipment, false)
	var melee = equipment.get("_mekatana")
	var expected := [1.3, 1.9, 2.6]
	for rank in range(3):
		var distance := float(expected[rank])
		var origin := actor.global_position
		player.global_position = origin + Vector3.FORWARD * (distance + 1.0)
		await physics_frame
		_check(is_equal_approx(float(bot.call("_ideal_combat_range")), distance + 1.0), "placement prépare le dash du coup %d" % (rank + 1))
		_tick(actor, player, bot, equipment)
		_check(melee.is_busy() and int(melee.step) == rank, "engagement du rang %d à sa portée propre" % (rank + 1))
		_tick(actor, player, bot, equipment, false, float(melee.definition.preparation[rank]))
		_check(absf(actor.global_position.distance_to(origin) - distance) < 0.01, "dash bot du coup %d parcourt toute sa distance doublée" % (rank + 1))
		_check((player.global_position - actor.global_position).dot(melee.direction) > 0.9, "cible reste devant après le dash %d" % (rank + 1))
		_tick(actor, player, bot, equipment, false, 1.0)
	_check(is_equal_approx(float(equipment.call("get_mekatana_dash_distance")), 1.3), "fin de combo retrouve la distance du premier dash")


func _test_combo_spacing(actor: Node3D, player: Node3D, bot: Node, equipment: Node) -> void:
	_prepare(actor, player, equipment)
	_tick(actor, player, bot, equipment)
	_tick(actor, player, bot, equipment, false, 1.0)
	var melee = equipment.get("_mekatana")
	for rank in [1, 2]:
		player.global_position = actor.global_position + Vector3.FORWARD * 1.8
		await physics_frame
		_tick(actor, player, bot, equipment)
		_check(not melee.is_busy() and int(equipment.call("get_mekatana_next_step")) == rank, "coup %d attend de la place pour son dash complet" % (rank + 1))
		var before := actor.global_position.distance_to(player.global_position)
		bot.set("_current_intent", "pressure")
		bot.set("_has_tactical_destination", true)
		bot.set("_tactical_destination", player.global_position)
		bot.set("_move_velocity", Vector3.ZERO)
		bot.call("_update_duel_movement", actor, player.global_position, true, 0.15)
		_check(actor.global_position.distance_to(player.global_position) > before, "bot recule plutôt que dépasser une cible trop proche au coup %d" % (rank + 1))
		player.global_position = actor.global_position + Vector3.FORWARD * (float(equipment.call("get_mekatana_dash_distance")) + 1.0)
		await physics_frame
		_tick(actor, player, bot, equipment)
		_check(melee.is_busy() and int(melee.step) == rank, "repositionnement permet de poursuivre le combo au rang %d" % (rank + 1))
		_tick(actor, player, bot, equipment, false, 1.0)


func _test_direction_and_interruptions(actor: Node3D, player: Node3D, bot: Node, equipment: Node) -> void:
	_prepare(actor, player, equipment)
	await physics_frame
	_tick(actor, player, bot, equipment)
	var melee = equipment.get("_mekatana")
	var locked: Vector3 = melee.direction
	player.global_position = Vector3.RIGHT * 2.0
	_tick(actor, player, bot, equipment)
	_check(melee.direction.dot(locked) > 0.999, "visée bot verrouillée pendant préparation")
	_check(bool(equipment.call("owns_mekatana_movement")), "dash ne cumule pas locomotion normale")
	var visual_direction: Vector3 = bot.call("get_visual_aim_point") - actor.global_position
	visual_direction.y = 0.0
	_check(visual_direction.normalized().dot(locked) > 0.999, "orientation visuelle suit le slash engagé")
	var rig := actor.get("_visual_rig") as Node3D
	_check(Vector3(rig.get("_mekatana_direction")).dot(locked) > 0.999, "rig bot reçoit la direction engagée")
	_check((-rig.global_basis.z).dot(locked) > 0.999, "yaw du corps aligné immédiatement pendant le slash")
	await physics_frame
	_check(bool(equipment.call("_begin_module_action", "fulguro_punch")), "module prioritaire interrompt la mêlée")
	_check(not melee.is_busy() and str(equipment.call("get_action_owner")) == "fulguro_punch", "interruption conserve seulement le token du module")
	_check(str(rig.get("_mekatana_phase")) == "" and Vector3(rig.get("_mekatana_direction")) == Vector3.ZERO, "interruption efface la pose et le verrou visuel")
	equipment.call("cancel_action")
	_prepare(actor, player, equipment)
	await physics_frame
	_tick(actor, player, bot, equipment)
	actor.call("apply_stun", 0.5, "mekatana_bot_test")
	_tick(actor, player, bot, equipment)
	_check(not melee.is_busy() and str(equipment.call("get_action_owner")) == "", "stun annule le coup et libère le cast")
	_prepare(actor, player, equipment)
	await physics_frame
	_tick(actor, player, bot, equipment)
	equipment.call("set_profile", "blaster")
	_check(not melee.is_busy() and str(equipment.get("profile")) == "blaster", "changement d'arme annule la mêlée")
	_prepare(actor, player, equipment)
	await physics_frame
	_tick(actor, player, bot, equipment)
	actor.call("take_damage", 10000.0, "fixture", "mekatana_bot_death")
	_tick(actor, player, bot, equipment)
	_check(not melee.is_busy(), "mort annule la mêlée")


func _test_feedback(actor: Node3D, player: Node3D, bot: Node, equipment: Node, scene: Node) -> void:
	var vfx := scene.get_node("VFXManager")
	_prepare(actor, player, equipment)
	player.global_position = Vector3.FORWARD * 8.0
	await physics_frame
	_tick(actor, player, bot, equipment, false)
	_check(bool(equipment.call("_begin_mekatana", actor, Vector3.FORWARD * 2.0, {}, {"aim_error_degrees": 0.0, "prediction_quality": 0.0})), "slash de test engagé à vide")
	var weapon: Node = actor.get("_visual_rig").get("_mekatana_weapon")
	var audio := weapon.get("_audio") as AudioStreamPlayer
	equipment.call("_update_mekatana", 0.30)
	_check(str(equipment.call("get_mekatana_phase")) == "recovery", "gros delta traverse toute la phase active")
	_check(audio.stream == weapon.get("_slash_sounds")[0], "son de slash conservé lorsque la phase active tient dans une frame")
	_prepare(actor, player, equipment)
	await physics_frame
	vfx.call("clear")
	_tick(actor, player, bot, equipment)
	weapon = actor.get("_visual_rig").get("_mekatana_weapon")
	audio = weapon.get("_audio") as AudioStreamPlayer
	_tick(actor, player, bot, equipment, false, 0.30)
	_check(float(player.call("get_health")) < float(player.call("get_max_health")), "contact du slash validé")
	_check(int(vfx.call("get_debug_counts").active) >= 5, "contact validé produit impact et arc électrique du premier coup")
	_check(audio.stream == weapon.get("_impact_sounds")[0], "contact validé produit son d'impact")
	_prepare(actor, player, equipment)
	await physics_frame
	vfx.call("clear")
	player.set("_stasis_remaining", 1.0)
	_tick(actor, player, bot, equipment)
	weapon = actor.get("_visual_rig").get("_mekatana_weapon")
	audio = weapon.get("_audio") as AudioStreamPlayer
	_tick(actor, player, bot, equipment, false, 0.30)
	_check(is_equal_approx(float(player.call("get_health")), float(player.call("get_max_health"))), "stase refuse le contact")
	_check(int(vfx.call("get_debug_counts").active) == 0, "contact refusé ne produit aucun impact électrique")
	_check(audio.stream == weapon.get("_slash_sounds")[0], "contact refusé garde seulement le son du slash")
	player.set("_stasis_remaining", 0.0)


func _test_no_friendly_fire(actor: Node3D, player: Node3D, bot: Node, equipment: Node, scene: Node) -> void:
	_prepare(actor, player, equipment)
	var friendly := FriendlyBot.new()
	friendly.collision_layer = 2
	friendly.collision_mask = 0
	var shape := CapsuleShape3D.new()
	shape.radius = 0.7
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	friendly.add_child(collider)
	scene.add_child(friendly)
	# Both bodies overlap the same horizontal cleave; their team layer differs.
	friendly.global_position = Vector3(0.9, 0.0, -1.8)
	await physics_frame
	var before := float(player.call("get_health"))
	_tick(actor, player, bot, equipment)
	_tick(actor, player, bot, equipment, false, 0.23)
	_check(is_equal_approx(before - float(player.call("get_health")), 65.0), "cleave du bot atteint le joueur layer 4")
	_check(friendly.hits == 0 and is_equal_approx(friendly.health, 1000.0), "cleave du bot ignore son voisin allié layer 2")
	friendly.queue_free()
	await process_frame


func _test_collision_motion(actor: Node3D, player: Node3D, bot: Node, equipment: Node, scene: Node) -> void:
	_prepare(actor, player, equipment)
	_tick(actor, player, bot, equipment, false)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 3.0, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	scene.add_child(wall)
	wall.global_position = Vector3(0.0, 1.5, -1.1)
	await physics_frame
	var melee = equipment.get("_mekatana")
	var distances := [1.3, 1.9, 2.6]
	for rank in range(3):
		actor.global_position = Vector3.ZERO
		player.global_position = Vector3.FORWARD * (float(distances[rank]) + 1.0)
		await physics_frame
		_check(bool(equipment.call("_begin_mekatana", actor, player.global_position, {}, {"aim_error_degrees": 0.0})), "dash %d engagé vers le mur" % (rank + 1))
		equipment.call("_update_mekatana", float(melee.definition.preparation[rank]))
		_check(actor.global_position.length() < 0.6 and actor.global_position.z > -0.6, "dash bot %d arrêté contre un mur" % (rank + 1))
		equipment.call("_update_mekatana", 1.0)
	wall.queue_free()
	await physics_frame
	_prepare(actor, player, equipment)
	# Isolate the arena clamp from the real perimeter wall, whose capsule sweep
	# can stop earlier. Wall collision was exercised for every rank above.
	var open_controller := OpenMotionController.new()
	scene.add_child(open_controller)
	equipment.set("_mekatana_controller", open_controller)
	for rank in range(3):
		actor.global_position = Vector3(26.8, 0.0, 20.0)
		player.global_position = actor.global_position + Vector3.RIGHT * (float(distances[rank]) + 1.0)
		await physics_frame
		_check(bool(equipment.call("_begin_mekatana", actor, player.global_position, {}, {"aim_error_degrees": 0.0})), "dash %d engagé vers la limite" % (rank + 1))
		equipment.call("_update_mekatana", float(melee.definition.preparation[rank]))
		_check(actor.global_position.x <= 27.0 and actor.global_position.x > 26.9, "dash bot %d respecte la limite d'arène" % (rank + 1))
		equipment.call("_update_mekatana", 1.0)
	equipment.set("_mekatana_controller", bot)
	open_controller.queue_free()
