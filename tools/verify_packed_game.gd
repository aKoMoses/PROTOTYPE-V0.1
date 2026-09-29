extends SceneTree

## Run externally with --main-pack to verify the delivered compiled resources.
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(not DirAccess.dir_exists_absolute("res://captures"), "QA screenshots excluded from game package")
	_check(not DirAccess.dir_exists_absolute("res://tools"), "QA scripts excluded from game package")
	_check(not DirAccess.dir_exists_absolute("res://docs"), "Reports excluded from game package")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	var player := scene.get_node("Player")
	var target := scene.get_node("TargetDummy")
	for cycle in range(5):
		flow.call("_open_equipment")
		flow.call("_open_equipment_category", "offensive")
		await process_frame
		flow.call("_start_duel")
		flow.call("_begin_live_round")
		target.call("set_training_bot_enabled", false)
		_check(bool(player.call("is_gameplay_enabled")), "compiled player enabled in cycle %d" % cycle)
		flow.call("_toggle_pause")
		_check(paused, "compiled pause active")
		flow.call("_resume")
		_check(not paused, "compiled pause resumed")
		flow.set("player_round_score", 3)
		flow.call("_show_final_result")
		flow.call("_return_menu")
		await process_frame
		# The authored menu showcase intentionally reenables its demo actors.
		# The actual match must stop; do not mistake that demo for a live duel.
		_check(not bool(scene.get("duel_active")), "compiled menu stops the match")
	flow.call("_open_equipment")
	flow.call("_open_equipment_category", "offensive")
	for frame in range(10):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var args := OS.get_cmdline_user_args()
		if not args.is_empty():
			_check(root.get_texture().get_image().save_png(args[0]) == OK, "compiled Vulkan forge captured")
	root.get_node("GameSfx").call("clear")
	scene.queue_free()
	await process_frame
	await create_timer(0.12).timeout
	for failure in _failures:
		push_error(failure)
	print("PACKED GAME: %s (5 full navigation/match/pause/result cycles)" % ["PASS" if _failures.is_empty() else "FAIL"])
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
