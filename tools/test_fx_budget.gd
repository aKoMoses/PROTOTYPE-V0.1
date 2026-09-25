extends SceneTree


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	for _index in range(60):
		var node := Node3D.new()
		scene.add_child(node)
		scene.call("register_fx_node", node, "burst")
	await create_timer(0.35, true, false, false).timeout
	var active := get_nodes_in_group("prototype0_fx_budget").size()
	if active > int(scene.get("FX_MAX_BURSTS")):
		push_error("FAIL: budget bursts = %d, plafond = %d" % [active, int(scene.get("FX_MAX_BURSTS"))])
		quit(1)
	else:
		print("P0-119 FX BUDGET TEST: PASS (%d bursts actifs)" % active)
		quit(0)
