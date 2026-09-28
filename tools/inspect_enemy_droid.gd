extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var source := ProjectSettings.globalize_path("res://art/enemy_droid.glb")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		source = args[0]
	var error := document.append_from_file(source, state)
	if error != OK:
		push_error(error_string(error))
		quit(1)
		return
	var model := document.generate_scene(state)
	root.add_child(model)
	var report := {"source": source, "skeletons": [], "players": [], "meshes": 0}
	walk(model, model, report)
	DirAccess.make_dir_recursive_absolute("res://docs")
	var output := FileAccess.open("res://docs/enemy_droid_godot_audit.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("ENEMY_DROID_INSPECTION: docs/enemy_droid_godot_audit.json; skeletons=%d meshes=%d players=%d" % [report.skeletons.size(), report.meshes, report.players.size()])
	model.queue_free()
	quit()

func walk(node: Node, model: Node, report: Dictionary) -> void:
	if node is Skeleton3D:
		var bones := []
		for i in node.get_bone_count():
			bones.append({"index": i, "name": node.get_bone_name(i), "parent": node.get_bone_parent(i), "rest": str(node.get_bone_rest(i))})
		report.skeletons.append({"path": str(model.get_path_to(node)), "bones": bones})
	if node is AnimationPlayer:
		var clips := []
		for name in node.get_animation_list():
			var clip: Animation = node.get_animation(name)
			var tracks := []
			for i in clip.get_track_count():
				tracks.append(str(clip.track_get_path(i)))
			clips.append({"name": name, "length": clip.length, "loop": clip.loop_mode, "tracks": tracks})
		report.players.append({"path": str(model.get_path_to(node)), "root_node": str(node.root_node), "libraries": node.get_animation_library_list(), "clips": clips})
	if node is MeshInstance3D:
		report.meshes += 1
	for child in node.get_children():
		walk(child, model, report)
