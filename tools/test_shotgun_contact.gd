extends SceneTree

var failures: Array[String] = []
var player: CharacterBody3D
var target: StaticBody3D
var shots: Array[Dictionary] = []
var checks := 0
var aim := Vector3.FORWARD
var move := Vector3.ZERO
var rig: PlayerVisualRig
var camera: Camera3D

func _initialize() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	call_deferred("_run")

func _run() -> void:
	player = load("res://scripts/player.gd").new()
	player.name = "Player"
	current_scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	rig = player.get_node("VisualRoot")
	target = load("res://scripts/target_dummy.gd").new()
	target.name = "TargetDummy"
	current_scene.add_child(target)
	target.set_duel_mode(true)
	target.set_training_bot_enabled(false)
	camera = Camera3D.new()
	current_scene.add_child(camera)
	camera.position = Vector3(0.0, 20.5, 17.5)
	camera.fov = 38.0
	camera.look_at(Vector3(0.0, 0.45, 0.0))
	camera.make_current()
	node_added.connect(_on_node_added)
	physics_frame.connect(_animate)
	for heading in [0.0, 90.0, 180.0, 270.0, 45.0, 135.0, 225.0, 315.0]:
		move = Vector3.ZERO if fmod(heading, 90.0) == 0.0 else Vector3.RIGHT
		for distance in [0.65, 0.9, 1.1, 1.4, 1.8, 2.5, 4.0, 6.5]:
			for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
				projectile.queue_free()
			player.reset_combat_state()
			player.set_gameplay_enabled(true)
			player.set_weapon("shotgun")
			aim = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(heading))
			player._set_aim_direction(aim)
			target.global_position = aim * distance
			target.reset_combat_state()
			await physics_frame
			await process_frame
			shots.clear()
			player._perform_shotgun_attack()
			await create_timer(0.5).timeout
			var damage: float = target.get_max_health() - target.get_health()
			checks += 1
			if damage <= 0.0:
				var detail := "shotgun missed at %.2f m / %.0f degrees; shots=%s" % [distance, heading, shots]
				failures.append(detail)
				print("CONTACT_FAILURE: ", detail)
			else:
				print("CONTACT_HIT: distance=%.2f heading=%.0f damage=%.1f" % [distance, heading, damage])
	await create_timer(0.5).timeout
	move = Vector3.ZERO
	for heading in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		# Lower/middle/upper torso pixels exercise real perspective picking.
		for sample in [Vector2(2, 1.0), Vector2(2, 1.35), Vector2(2, 1.7), Vector2(4, 1.0), Vector2(4, 1.35), Vector2(4, 1.7), Vector2(6, 1.0), Vector2(6, 1.35), Vector2(6, 1.7)]:
			var distance: float = sample.x
			for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
				projectile.queue_free()
			player.reset_combat_state()
			player.set_gameplay_enabled(true)
			player.set_weapon("shotgun")
			target.global_position = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(heading)) * distance
			target.reset_combat_state()
			await physics_frame
			await process_frame
			var cursor := camera.unproject_position(target.global_position + Vector3.UP * sample.y)
			player._aim_at_screen_position(cursor, camera)
			aim = player.aim_direction
			shots.clear()
			player._perform_shotgun_attack()
			await create_timer(0.5).timeout
			checks += 1
			var damage: float = target.get_max_health() - target.get_health()
			print("SCREEN_SHOT: distance=%.2f heading=%.0f torso_height=%.2f damage=%.1f aim=%s" % [distance, heading, sample.y, damage, aim])
			if damage <= 0.0:
				failures.append("cursor on body missed at %.2f m / %.0f degrees / torso %.2f m" % [distance, heading, sample.y])
	await create_timer(0.5).timeout
	physics_frame.disconnect(_animate)
	node_added.disconnect(_on_node_added)
	current_scene.queue_free()
	current_scene = null
	await process_frame
	print("SHOTGUN CONTACT TEST: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _animate() -> void:
	if rig != null:
		rig.update_visual_state(move, aim, 0.0 if move.is_zero_approx() else player.move_speed, player.move_speed, 1.0 / Engine.physics_ticks_per_second)

func _on_node_added(node: Node) -> void:
	if node.get_script() != null and node.get_script().resource_path == "res://scripts/live_projectile.gd":
		call_deferred("_record", node)

func _record(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var direction: Vector3 = node.get("_direction")
	shots.append({"origin": node.global_position - direction * float(node.get("_distance")), "direction": direction})
