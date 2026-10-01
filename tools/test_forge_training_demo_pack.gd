extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ProjectSettings.load_resource_pack(args[0]):
		push_error("Unable to load the exported resource pack")
		quit(1)
		return
	var script = load("res://scripts/forge_training_demo.gd")
	var expected: Dictionary = {}
	if args.size() > 1:
		var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		for item in manifest:
			expected[item.id] = item.sha256
	var preview = script.new()
	root.add_child(preview)
	var failures := 0
	for identifier in script.CLIPS:
		if expected.has(identifier) and FileAccess.get_sha256("res://art/forge-demos/%s.ogv" % identifier) != expected[identifier]:
			push_error("Exported video differs from the verified clip: " + str(identifier))
			failures += 1
		preview.show_equipment(identifier)
		await create_timer(0.45).timeout
		if not preview.video.is_playing() or preview.video.get_stream_position() <= 0 or preview.video.get_video_texture().get_width() < 640:
			push_error("Exported video unavailable: " + str(identifier))
			failures += 1
	print("FORGE TRAINING DEMO PACK: ", "PASS" if failures == 0 else "FAIL", " (", script.CLIPS.size(), " clips)")
	preview.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
