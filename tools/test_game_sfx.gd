extends SceneTree

var _heard: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if player == null or target == null:
		_failures.append("Player or TargetDummy missing")
	else:
		root.get_node("GameSfx").connect("event_played", func(event_id: String) -> void: _heard.append(event_id))
		player.global_position = Vector3.ZERO
		player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
		player.set("_offensive_module_id", "javelin")
		target.global_position = Vector3(0.0, 0.0, -2.0)
		player.call("_perform_javelin")
		for _frame in range(240):
			await process_frame
			if bool(target.call("has_javelin_mark")):
				break
		player.call("_perform_javelin")
		await process_frame
		_expect("javelin_teleport")
		player.call("reset_combat_state")
		target.call("reset_combat_state")

		player.set("_last_move_direction", Vector3.RIGHT)
		player.call("_perform_mobility_module")
		_expect("pyro_dash")

		target.call("take_damage", 10.0, "player", "sfx:normal")
		_expect("impact_robot")
		target.call("take_damage", 10.0, "player", "sfx:critical")
		_expect("impact_critical")
		target.call("take_damage", 2000.0, "player", "sfx:kill")
		_expect("robot_destruction")
		player.call("take_damage", 10.0, "sfx", "received")
		_expect("damage_received")

		var decor := StaticBody3D.new()
		decor.name = "SoundTestDecor"
		scene.add_child(decor)
		player.call("_contact_fx", {"position": Vector3.ZERO, "normal": Vector3.UP, "collider": decor}, Color.WHITE)
		_expect("impact_decor")
		var wall := Area3D.new()
		wall.name = "MagneticField"
		scene.add_child(wall)
		player.call("_contact_fx", {"position": Vector3.ZERO, "normal": Vector3.UP, "collider": wall}, Color.WHITE)
		_expect("magnetic_absorb")
		decor.queue_free()
		wall.queue_free()
		await create_timer(4.0).timeout

	var vfx := scene.get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("clear")
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("GAME SFX TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("GAME SFX TEST: FAIL (%d)" % _failures.size())
		quit(1)


func _expect(event_id: String) -> void:
	if not _heard.has(event_id):
		_failures.append("Missing combat sound: " + event_id)
