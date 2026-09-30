extends SceneTree

var failures: Array[String] = []
var shots: Array[Dictionary] = []
var player: Node3D
var player_shots := false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	player = scene.get_node("Player")
	var target: Node3D = scene.get_node("TargetDummy")
	var flow: Node = scene.get_node("Interface")
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	# Preserve real collision and damage; suppress only autonomous AI/input.
	target.call("set_training_bot_enabled", true)
	target.get_node("TrainingBot").set_physics_process(false)
	player.set_physics_process(false)
	player.set_process(false)
	node_added.connect(_on_node_added)
	var equipment: Node = target.get_node("TrainingBot/DuelEquipment")
	var rig: Node = target.get("_visual_rig")
	for weapon in ["blaster", "shotgun"]:
		for distance in [2.0, 5.0]:
			_clear_shots(scene)
			target.call("set_duel_profile", weapon)
			_check(rig.get("weapon_id") == weapon, "bot weapon differs from loadout")
			target.global_position = Vector3(0, 0, 3)
			player.global_position = target.global_position + Vector3.BACK * distance
			player.call("reset_combat_state")
			await physics_frame
			await process_frame
			equipment.set("_aim_position", player.global_position)
			equipment.set("charge_duration", 1.0)
			var health: float = player.call("get_health")
			equipment.call("_fire", target, player)
			var barrel: Transform3D = rig.call("get_muzzle_transform")
			var toward := (player.global_position + Vector3.UP * 0.9 - barrel.origin).normalized()
			_check((-barrel.basis.z).dot(toward) > 0.999, "bot barrel misses close target")
			await create_timer(0.4).timeout
			_check(float(player.call("get_health")) < health, "%s bot shot missed at %.1f m" % [weapon, distance])
			_check(shots.size() == (6 if weapon == "shotgun" else 1), "bot volley count incorrect")
			for shot in shots:
				_check(shot.origin.distance_to(barrel.origin) < 0.01, "bot projectile detached from muzzle")
	_clear_shots(scene)
	target.call("set_training_bot_enabled", false)
	player_shots = true
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0.3, 0, -4)
	for weapon in ["blaster", "shotgun"]:
		_clear_shots(scene)
		player.call("reset_combat_state")
		player.call("set_gameplay_enabled", true)
		player.call("set_weapon", weapon)
		player.set("aim_direction", Vector3.FORWARD)
		await physics_frame
		await process_frame
		if weapon == "blaster":
			player.call("_fire_blaster_projectile", 20.0, 0.0, Vector3.FORWARD)
		else:
			player.call("_perform_shotgun_attack")
		await create_timer(0.2).timeout
		_check(shots.size() == (6 if weapon == "shotgun" else 1), "player volley count incorrect")
		var mean := Vector3.ZERO
		for shot in shots:
			mean += shot.direction
			_check(shot.origin.distance_to(shot.muzzle) < 0.01, "player %s projectile used stale muzzle: origin=%s muzzle=%s distance=%.4f" % [weapon, shot.origin, shot.muzzle, shot.origin.distance_to(shot.muzzle)])
		_check(mean.normalized().dot(Vector3.FORWARD) > 0.9999, "player volley redirected away from aim")
	var controller: Node = flow.get_node("HudLayoutController")
	controller.set_layout(PrototypeHudLayout.standard())
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1024, 600)]:
		root.size = dimensions
		await process_frame
		controller.apply()
		var summary: Rect2 = controller.widget_rect("match_summary")
		var pause: Rect2 = controller.widget_rect("pause")
		var spells: Rect2 = controller.widget_rect("spell_bar")
		_check(absf(summary.get_center().x - root.get_visible_rect().size.x * 0.5) < 1.0, "score is not centred")
		_check(not summary.intersects(pause), "score overlaps pause")
		_check(absf(spells.get_center().x - summary.get_center().x) < 1.0, "modules are off centre")
		_check(not bool(controller.controls.player_vitals.visible), "duplicate vitals visible by default")
	node_added.disconnect(_on_node_added)
	_clear_shots(scene)
	current_scene = null
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("DUEL PRESENTATION TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _on_node_added(node: Node) -> void:
	if node.get_script() != null and node.get_script().resource_path == "res://scripts/live_projectile.gd":
		var muzzle := Vector3.ZERO
		if player_shots:
			var marker: Node3D = player.get("_blaster_muzzle" if player.call("get_weapon_id") == "blaster" else "_shotgun_muzzle")
			muzzle = marker.global_position
		call_deferred("_record_shot", node, player_shots, muzzle)

func _record_shot(node: Node3D, from_player: bool, muzzle: Vector3) -> void:
	if not is_instance_valid(node):
		return
	var direction: Vector3 = node.get("_direction")
	# A physics tick can precede this deferred sample. Undo its measured travel,
	# and compare with the muzzle sampled at creation, before recoil advances.
	var origin := node.global_position - direction * float(node.get("_distance"))
	shots.append({"origin": origin, "direction": direction, "muzzle": muzzle if from_player else origin})

func _clear_shots(scene: Node) -> void:
	scene.call("clear_transient_fx")
	for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
		projectile.queue_free()
	shots.clear()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
