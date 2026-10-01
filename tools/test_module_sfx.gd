extends SceneTree

const COUNTER := preload("res://scripts/counter.gd")
const BASKET := preload("res://scripts/rocket_basket.gd")
const ROCKET := preload("res://scripts/homing_rocket.gd")
const NETWORK := preload("res://scripts/network_player.gd")
var heard: Array[String] = []
var failures: Array[String] = []

class Actor extends StaticBody3D:
	var health := 1000.0
	var targets: Array = []
	func _ready() -> void:
		collision_layer = 2
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.6
		shape.shape = sphere
		shape.position.y = 0.9
		add_child(shape)
	func get_health() -> float: return health
	func take_damage(amount: float, _source: String = "", _id: String = "") -> float:
		health -= amount
		return amount
	func _module_target() -> Node: return targets[0] if not targets.is_empty() else null

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var caster := Actor.new()
	var enemy := Actor.new()
	scene.add_child(caster)
	scene.add_child(enemy)
	enemy.position.z = -4.0
	caster.targets = [enemy]
	var sfx := root.get_node("GameSfx")
	sfx.event_played.connect(func(id: String) -> void: heard.append(id))
	var guard := COUNTER.ensure(caster)
	guard.begin()
	check(not heard.has("counter_guard"), "No guard sound during preparation")
	guard.update(float(guard.definition.preparation))
	check(heard.count("counter_guard") == 1, "Guard sounds when protection begins")
	var payload := {"id":"parry", "counter_trigger":true}
	guard.intercept(payload)
	guard.intercept(payload)
	check(heard.count("counter_intercept") == 1 and heard.count("counter_capture") == 1, "Repeated pellets do not repeat parry or energy capture")
	var charge := COUNTER.weapon_attack(caster, "release", {"counter_trigger":true})
	COUNTER.impact(enemy, 10.0, "test", "release1", charge, enemy.global_position + Vector3.UP * 0.9)
	COUNTER.impact(enemy, 10.0, "test", "release2", charge, enemy.global_position + Vector3.UP * 0.9)
	check(heard.count("counter_release") == 1, "One discharge for one consumed surcharge")
	var empty := COUNTER.weapon_attack(caster, "empty", {"counter_trigger":true})
	COUNTER.impact(enemy, 10.0, "test", "empty1", empty, enemy.global_position)
	check(heard.count("counter_release") == 1, "Uncharged attack does not discharge")
	var rockets := BASKET.launch(caster, Vector3.FORWARD, "test", "audio-volley", {})
	check(heard.count("rocket_launch") == 1, "One launch for all five rockets")
	for rocket in rockets:
		check(rocket._propulsion.playing and rocket._propulsion.bus == &"Effects", "Each rocket carries an effects-bus engine")
	rockets[0].take_damage(100.0)
	check(heard.count("rocket_destroyed") == 1, "Shot-down rocket plays destruction")
	check(not rockets[0]._propulsion.playing, "Shot-down rocket stops engine immediately")
	for frame in range(120): await physics_frame
	check(heard.count("rocket_impact") >= 1, "Real flight collision plays impact")
	check(get_nodes_in_group(ROCKET.GROUP).is_empty(), "No engines remain after rockets retire")
	var second := BASKET.launch(caster, Vector3.FORWARD, "test", "cleanup", {})
	var destruction_count := heard.count("rocket_destroyed")
	BASKET.clear(caster)
	check(heard.count("rocket_destroyed") == destruction_count, "Round cleanup produces no fake destruction")
	for rocket in second: check(not rocket._propulsion.playing, "Cleanup stops every engine immediately")
	var replica := NETWORK.new()
	replica.authoritative = false
	replica.remote_controlled = true
	scene.add_child(replica)
	replica.set_gameplay_enabled(true)
	replica.receive_action("rocket_end", {"sound":"rocket_destroyed", "center":Vector3.ZERO}, true)
	check(heard.count("rocket_destroyed") == destruction_count + 1, "Client plays authoritative rocket outcome")
	replica.receive_action("counter_explosion", {"center":Vector3.ZERO}, true)
	check(heard.count("counter_release") == 2, "Client hears authoritative Counter discharge")
	sfx.set_paused(true)
	var count := heard.size()
	sfx.play_module_event("rocket_arm", Vector3.ZERO)
	check(heard.size() == count, "Paused feedback cannot start voices")
	sfx.clear()
	check(sfx._module_voices.is_empty(), "Scene reset retires persistent impact voices")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("MODULE SFX TEST: PASS")
		quit(0)
	else:
		for message in failures: push_error(message)
		quit(1)
