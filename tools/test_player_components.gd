extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
var _failures: Array[String] = []
var _fixture: Node3D


func _initialize() -> void:
	_fixture = Node3D.new()
	_fixture.name = "PlayerLifetimeFixture"
	root.add_child(_fixture)
	current_scene = _fixture
	_run.call_deferred()


func _spawn_player() -> CharacterBody3D:
	var actor := PLAYER.new() as CharacterBody3D
	actor.name = "Player"
	_fixture.add_child(actor)
	actor.set_physics_process(false)
	return actor


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _run() -> void:
	_check(is_equal_approx(PLAYER.mobile_blaster_release_ratio(0.5, 0.2, 1.0), 0.5), "Static Player API lost during extraction")
	# A caller can discard a freshly constructed actor before it enters a scene.
	var detached := PLAYER.new() as CharacterBody3D
	var detached_ref: WeakRef = weakref(detached)
	detached.free()
	_check(detached_ref.get_ref() == null, "Detached player was not released")
	# Destruction during preparation must cancel callbacks owned by the actor.
	for action in ["_perform_rocket_basket", "_perform_javelin", "_perform_shotgun_attack", "_begin_blaster_charge", "_perform_pelto_smash", "_perform_longshot_attack", "_perform_mekatana_attack"]:
		var actor := _spawn_player()
		var weapon := "blaster"
		if action == "_perform_shotgun_attack":
			weapon = "shotgun"
		elif action == "_perform_longshot_attack":
			weapon = "longshot"
		elif action == "_perform_mekatana_attack":
			weapon = "mekatana"
		actor.call("set_weapon", weapon)
		actor.call(action)
		_check(str(actor.call("get_action_owner")) != "", "Action did not begin: " + action)
		if action == "_begin_blaster_charge":
			actor.call("_release_blaster_charge")
		elif action == "_perform_pelto_smash":
			actor.call("_cancel_pelto_smash")
		var old_actor: WeakRef = weakref(actor)
		actor.queue_free()
		await process_frame
		await create_timer(0.40).timeout
		_check(old_actor.get_ref() == null, "Actor survived scene removal: " + action)
		var fresh := _spawn_player()
		_check(int(fresh.call("get_longshot_shots_fired")) == 0, "Replacement inherited LONGSHOT cycle: " + action)
		_check(str(fresh.call("get_action_owner")) == "", "Replacement inherited a pending action: " + action)
		_check(is_equal_approx(float(fresh.call("get_health")), float(fresh.call("get_max_health"))), "Replacement inherited damage: " + action)
		fresh.call("_begin_blaster_charge")
		_check(bool(fresh.call("is_blaster_charging")), "Replacement cannot attack: " + action)
		fresh.call("reset_combat_state")
		fresh.queue_free()
		await process_frame
	_fixture.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PLAYER COMPONENT LIFETIME TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("PLAYER COMPONENT LIFETIME TEST: FAIL (%d)" % _failures.size())
		quit(1)
