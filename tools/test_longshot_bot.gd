extends SceneTree

const DATA := preload("res://scripts/combat_data.gd")
const STATE := preload("res://scripts/longshot_state.gd")
const TARGET := preload("res://scripts/target_dummy.gd")
const PRESETS := preload("res://scripts/bot_build_presets.gd")
var failures: Array[String] = []
var impacts: Array[Dictionary] = []
var checks := 0
var body: Node3D
var controller: Node
var equipment: Node
var probe: DamageProbe

class DamageProbe extends CharacterBody3D:
	var damage_taken := 0.0
	var hit_count := 0
	var ids: Dictionary = {}
	func take_damage(amount: float, _source: String = "", attack_id: String = "") -> float:
		if ids.has(attack_id):
			return 0.0
		ids[attack_id] = true
		damage_taken += amount
		hit_count += 1
		return amount
	func flash_impact(_enhanced := false) -> void:
		pass

func _initialize() -> void:
	var stage := Node3D.new()
	stage.name = "LongshotBotFixture"
	root.add_child(stage)
	current_scene = stage
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _run() -> void:
	body = TARGET.new()
	body.name = "TargetDummy"
	current_scene.add_child(body)
	body.call("set_duel_mode", true)
	body.call("set_duel_loadout", {"weapon": "longshot", "passive": "omnivamp"})
	body.call("set_training_bot_enabled", true)
	body.set_process(false)
	body.set_physics_process(false)
	controller = body.get_node("TrainingBot")
	controller.set_physics_process(false)
	equipment = controller.get_node("DuelEquipment")
	probe = DamageProbe.new()
	probe.name = "Player"
	probe.collision_layer = 4
	probe.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.85
	probe.add_child(collision)
	current_scene.add_child(probe)
	probe.position = Vector3(0, 0, -20)
	await physics_frame
	_check(equipment.get("profile") == "longshot", "bot accepts Longshot loadout")
	_check(float(controller.call("_ideal_combat_range")) >= 16.0, "bot chooses a distance where bonus can build")
	var rig := body.get_node("VisualRoot")
	_check(rig.get("weapon_id") == "longshot" and rig.find_child("LongshotGLB", true, false) != null, "bot carries imported Longshot")
	var state = equipment.get("longshot_state")
	var enhanced_ranks: Array[int] = []
	for rank in range(1, 16):
		body.position = Vector3.ZERO
		equipment.set("_last_tick_elapsed", float(rank) * 2.0)
		equipment.set("next_attack_at", 0.0)
		equipment.set("_aim_position", probe.global_position)
		var before_damage := probe.damage_taken
		var before_hits := probe.hit_count
		equipment.call("_fire", body, probe)
		var projectile := current_scene.get_node_or_null("DuelBotLongshot") as Node3D
		_check(projectile != null, "bot emits projectile at rank %d" % rank)
		if projectile == null:
			continue
		var enhanced := bool(projectile.get_meta("longshot_enhanced", false))
		if enhanced:
			enhanced_ranks.append(rank)
		var speed := float(DATA.WEAPON_DEFINITIONS.longshot.projectile_speed) * (float(DATA.WEAPON_DEFINITIONS.longshot.enhanced_speed_multiplier) if enhanced else 1.0)
		var radius := float(DATA.WEAPON_DEFINITIONS.longshot.projectile_radius) * (float(DATA.WEAPON_DEFINITIONS.longshot.enhanced_size_multiplier) if enhanced else 1.0)
		_check(is_equal_approx(float(projectile.get("_speed")), speed) and is_equal_approx(float(projectile.get("_radius")), radius), "bot fifth projectile has configured speed and radius")
		var muzzle: Transform3D = body.call("get_training_bot_muzzle_transform")
		_check(projectile.global_position.distance_to(muzzle.origin) < 0.001, "distance starts at actual bot barrel")
		projectile.finished.connect(func(hit: Dictionary, distance: float) -> void: impacts.append({"hit": hit, "distance": distance}))
		var emitted: int = state.shots_fired
		equipment.call("_fire", body, probe)
		_check(state.shots_fired == emitted, "bot recovery rejects duplicate emission")
		if rank == 3:
			body.call("set_duel_profile", "shotgun")
			body.call("set_duel_profile", "longshot")
			_check(state.shots_fired == emitted, "switch during flight retains cycle and active projectile")
		# Moving the shooter after launch cannot alter the projectile's distance.
		body.position = Vector3(12, 0, 0)
		await create_timer(0.5).timeout
		_check(probe.hit_count == before_hits + 1, "bot projectile damages exactly once")
		if not impacts.is_empty():
			var expected: float = STATE.damage_at_distance(float(impacts.back().distance), enhanced)
			_check(is_equal_approx(probe.damage_taken - before_damage, expected), "bot damage follows travelled distance after shooter moves")
	_check(enhanced_ranks == [5, 10, 15], "bot enhanced ranks are exactly 5, 10 and 15")
	# Misses still emit, while module ownership and cancellation never emit.
	body.position = Vector3.ZERO
	equipment.set("_last_tick_elapsed", 40.0)
	equipment.set("next_attack_at", 0.0)
	equipment.set("_aim_position", Vector3(20, 0, 0))
	var previous: int = state.shots_fired
	equipment.call("_fire", body, probe)
	_check(state.shots_fired == previous + 1, "bot miss advances cycle")
	await create_timer(0.6).timeout
	equipment.call("set_profile", "shotgun")
	equipment.call("set_profile", "longshot")
	_check(state.shots_fired == previous + 1, "bot weapon switch retains instance progression")
	equipment.call("_fire", body, probe)
	_check(state.shots_fired == previous + 1, "bot switch cannot bypass Longshot instance recovery")
	equipment.set("_next_module_at", 10000.0)
	equipment.set("next_attack_at", 0.0)
	equipment.call("_begin_weapon_action")
	equipment.set("charge_duration", float(DATA.WEAPON_DEFINITIONS.longshot.attack_preparation))
	equipment.set("charge_remaining", float(DATA.WEAPON_DEFINITIONS.longshot.attack_preparation))
	equipment.call("tick", 0.1, 42.0, false, probe.global_position, body, probe, controller, {"line_of_fire": false}, {"position_quality": 0.95})
	_check(state.shots_fired == previous + 1 and float(equipment.get("charge_remaining")) == 0.0, "lost line cancels actual bot preparation without advancing cycle")
	equipment.call("cancel_action")
	_check(state.shots_fired == previous + 1, "cancelled bot preparation preserves emitted count")
	equipment.set("next_attack_at", 0.0)
	equipment.call("_begin_module_action", "javelin")
	equipment.call("_fire", body, probe)
	_check(state.shots_fired == previous + 1, "module ownership rejects bot weapon emission")
	equipment.call("cancel_action")
	equipment.call("set_loadout", {"weapon": "longshot", "passive": "omnivamp"})
	_check(state.shots_fired == 0, "replacement bot loadout starts a new instance cycle")
	state.commit_shot()
	body.call("take_damage", 2000.0, "test", "longshot_bot_death")
	_check(state.shots_fired == 0, "real bot death resets its Longshot cycle")
	state.commit_shot()
	equipment.call("reset")
	_check(state.shots_fired == 0, "new round resets bot cycle")
	var has_marksman := false
	for preset in PRESETS.PRESETS:
		if str(preset.weapon) == "longshot":
			has_marksman = true
	_check(has_marksman, "Longshot is reachable in normal opponent preset bag")
	for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
		projectile.queue_free()
	body.call("set_training_bot_enabled", false)
	current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures:
		push_error("LONGSHOT BOT: " + failure)
	print("LONGSHOT BOT TEST: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
