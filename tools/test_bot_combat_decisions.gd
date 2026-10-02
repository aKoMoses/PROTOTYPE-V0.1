extends SceneTree

const EQUIPMENT := preload("res://scripts/duel_bot_equipment.gd")
const DATA := preload("res://scripts/combat_data.gd")

class CombatBody extends CharacterBody3D:
	func is_duel_mode() -> bool:
		return true

class ObservedPlayer extends StaticBody3D:
	var health := 1000.0
	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.7
		shape.height = 1.8
		collision.shape = shape
		collision.position.y = 0.9
		add_child(collision)
	func take_damage(amount: float, _source: String, _attack_id: String) -> float:
		health -= amount
		return amount

class Controller extends Node:
	var enabled := true
	var _windup_remaining := 0.0
	var blocked := false
	func _safe_bot_motion(_body: Node3D, motion: Vector3) -> Vector3:
		return Vector3.ZERO if blocked else motion
	func _line_of_sight_clear(_body: Node3D, _player: Node3D) -> bool:
		return true
	func _update_telegraph() -> void:
		pass

var failures: Array[String] = []


func _initialize() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var body := CombatBody.new()
	scene.add_child(body)
	var controller := Controller.new()
	body.add_child(controller)
	var equipment: Node = EQUIPMENT.new()
	controller.add_child(equipment)
	var player := ObservedPlayer.new()
	scene.add_child(player)
	await physics_frame
	equipment.call("set_loadout", {"weapon": "blaster", "mobility": "bio_injector", "defensive": "static_shield"})
	var perception := {"visible": true, "known": true, "position": Vector3(0.0, 0.0, 8.0), "velocity": Vector3(3.0, 0.0, 0.0), "line_of_fire": true}
	var tuning := {"prediction_quality": 0.84, "reaction_delay": 0.14, "position_quality": 0.88}
	var predicted: Vector3 = equipment.call("_predicted_aim", body, perception.position, perception, tuning, 0.5)
	_check(predicted.x > 1.8 and predicted.x <= 4.0, "charge predicts delayed lateral motion with a bounded lead")
	equipment.set("_aim_position", Vector3(0.0, 0.0, 8.0))
	equipment.set("charge_remaining", 0.5)
	player.global_position = Vector3(-20.0, 0.0, 20.0)
	equipment.call("_update_charge_aim", 0.01, body, perception.position, perception, tuning)
	var direction: Vector3 = equipment.get("_aim_position")
	_check(direction.x > 0.0 and direction.normalized().angle_to(Vector3.BACK) < deg_to_rad(1.5), "aim turns gradually toward the observation and ignores the actual player position")
	equipment.set("charge_remaining", 0.04)
	var committed: Vector3 = equipment.get("_aim_position")
	equipment.call("_update_charge_aim", 0.02, body, Vector3(-4.0, 0.0, 8.0), perception, tuning)
	_check(Vector3(equipment.get("_aim_position")).is_equal_approx(committed), "release commits its last instants instead of snapping to another sample")

	equipment.call("reset")
	equipment.set("charge_remaining", 0.4)
	equipment.set("charge_duration", 0.8)
	equipment.set("dash_remaining", 0.08)
	equipment.set("dash_direction", Vector3.RIGHT)
	_check(bool(equipment.call("_begin_weapon_action")), "weapon charge owns the shared action gate")
	await physics_frame
	var danger := {"projectile_threat": true, "threat_time": 0.12, "threat_direction": Vector3.FORWARD, "line_of_fire": false, "bot_health_fraction": 0.5}
	equipment.call("tick", 0.01, 2.0, false, perception.position, body, player, controller, danger, tuning)
	_check(float(equipment.get("static_remaining")) > 1.4 and is_zero_approx(float(equipment.get("charge_remaining"))), "an imminent visible projectile preempts weapon charge even when the enemy is hidden")
	_check(not bool(equipment.call("is_dashing")), "stasis cancels the active dash instead of resuming it after the shield")
	_check(str(equipment.call("get_action_owner")).is_empty() and int(equipment.get("_shot_serial")) == 0, "defensive preemption leaves no pending weapon discharge")

	equipment.call("set_loadout", {"weapon": "shotgun", "mobility": "pyro_boots"})
	var repair := {"intent": "seek_heal", "destination": Vector3(10.0, 0.0, 0.0), "known": false, "bot_health_fraction": 0.30, "line_of_fire": false}
	controller.blocked = true
	equipment.call("tick", 0.01, 2.0, false, Vector3(12.0, 0.0, 12.0), body, player, controller, repair, tuning)
	_check(not bool(equipment.call("is_dashing")) and is_zero_approx(float(equipment.call("get_module_cooldown", "pyro_boots"))), "blocked repair routes do not consume Pyro Boots")
	controller.blocked = false
	await physics_frame
	equipment.call("tick", 0.01, 2.1, false, Vector3(12.0, 0.0, 12.0), body, player, controller, repair, tuning)
	_check(bool(equipment.call("is_dashing")) and Vector3(equipment.get("dash_direction")).dot(Vector3.RIGHT) > 0.99, "repair mobility follows its destination without a visible opponent")
	_check(is_equal_approx(float(equipment.call("get_module_cooldown", "pyro_boots")), float(DATA.MODULE_DEFINITIONS.pyro_boots.cooldown)), "repair dash keeps the shared player cooldown")
	equipment.call("set_loadout", {"weapon": "blaster", "mobility": "bio_injector"})
	equipment.call("tick", 0.01, 2.2, false, Vector3(12.0, 0.0, 12.0), body, player, controller, repair, tuning)
	_check(float(equipment.get("bio_remaining")) > 2.9, "Bio Injector can accelerate an unseen repair route")

	equipment.call("set_loadout", {"weapon": "shotgun", "mobility": "bio_injector"})
	equipment.set("ammo", 1)
	equipment.set("next_attack_at", 100.0)
	equipment.call("tick", 0.01, 0.5, false, Vector3(10.0, 0.0, 10.0), body, player, controller, {"memory_age": 1.0, "intent": "search", "line_of_fire": false}, tuning)
	_check(is_equal_approx(float(equipment.get("reload_remaining")), float(DATA.WEAPON_DEFINITIONS.shotgun.reload_duration)), "partial magazine is reloaded safely using the shared duration")

	# A correctly led projectile must hit along its flight, not only at the
	# old launch-time endpoint. Conversely a lateral dodge must avoid that line.
	equipment.call("set_loadout", {"weapon": "blaster", "passive": "baroud"})
	equipment.set("charge_duration", float(DATA.WEAPON_DEFINITIONS.blaster.charge_time))
	player.global_position = Vector3(4.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	equipment.call("_launch_projectile", body, player, Vector3(0.0, 0.9, 0.0), Vector3.RIGHT, 0, {})
	await create_timer(0.3).timeout
	var expected_health := 1000.0 - float(DATA.WEAPON_DEFINITIONS.blaster.max_damage)
	_check(is_equal_approx(player.health, expected_health), "charged bot blaster applies shared full-charge damage along its flight")
	equipment.call("_launch_projectile", body, player, Vector3(0.0, 0.9, 0.0), Vector3.RIGHT, 0, {})
	player.global_position = Vector3(4.0, 0.0, 3.0)
	await create_timer(0.65).timeout
	_check(is_equal_approx(player.health, expected_health), "projectile keeps its committed line when the player dodges")
	player.global_position = Vector3(4.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	equipment.call("_launch_projectile", body, player, Vector3(0.0, 0.9, 0.0), Vector3.RIGHT, 0, {})
	var projectile := scene.find_child("DuelBotBlaster", true, false)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 3.0, 4.0)
	collision.shape = shape
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = Vector3(2.0, 1.0, 0.0)
	await create_timer(0.3).timeout
	_check(is_equal_approx(player.health, expected_health) and not is_instance_valid(projectile), "new cover blocks projectiles before they reach the player")
	current_scene = null
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("BOT COMBAT DECISIONS TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		print("BOT COMBAT DECISIONS TEST: FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
