extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	_check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/startup.tscn", "startup must be the configured entry point")
	var presets := ConfigFile.new()
	_check(presets.load("res://export_presets.cfg") == OK, "export preset must load")
	for spec in [["main_192x192", 192], ["adaptive_foreground_432x432", 432], ["adaptive_background_432x432", 432]]:
		var path: String = presets.get_value("preset.0.options", "launcher_icons/" + spec[0], "")
		var texture := load(path) as Texture2D
		_check(texture != null and texture.get_size() == Vector2(spec[1], spec[1]), "Android icon dimensions: " + spec[0])
	if OS.get_cmdline_user_args().has("capture-startup"):
		await _capture()
		if OS.get_cmdline_user_args().has("capture-only"):
			quit(0 if failures.is_empty() else 1)
			return
	var startup: Node = load("res://scenes/startup.tscn").instantiate()
	root.add_child(startup)
	current_scene = startup
	var previous := 0.0
	var deadline := Time.get_ticks_msec() + 120000
	while is_instance_valid(startup) and Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(startup):
			var value := float(startup.get("progress"))
			_check(value >= previous, "progress must never move backwards")
			previous = value
			if bool(startup.get("loading_failed")):
				failures.append("real main scene failed to load")
				break
	_check(not is_instance_valid(startup), "startup must finish and remove its input overlay")
	if is_instance_valid(startup):
		print("STARTUP DIAGNOSTIC: progress=", startup.get("progress"), " elapsed=", startup.get("elapsed"), " requested=", startup.get("_requested"), " installing=", startup.get("_installing"), " failed=", startup.get("loading_failed"))
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn", "loaded scene must become current_scene")
	if current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn":
		var flow := current_scene.get_node_or_null("Interface")
		_check(flow != null and int(flow.get("current_screen")) == 0, "startup must reach the menu")
		_check(current_scene.get_node_or_null("Player") != null, "real player must be constructed")
		_check(previous == 1.0, "completion must reach 100 percent")
		current_scene.queue_free()
		for frame in 10:
			await process_frame
	# A failed request stays on the readable screen, and retry can recover.
	var retry: Node = load("res://scenes/startup.tscn").instantiate()
	retry.next_scene_path = "res://scenes/nonexistent-startup-test.tscn"
	root.add_child(retry)
	current_scene = retry
	for frame in 8:
		await process_frame
	_check(bool(retry.get("loading_failed")), "missing scene must expose a failure")
	_check((retry.get("_retry") as Button).visible, "failure must offer retry")
	retry.next_scene_path = "res://scenes/main.tscn"
	(retry.get("_retry") as Button).pressed.emit()
	deadline = Time.get_ticks_msec() + 120000
	while is_instance_valid(retry) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not is_instance_valid(retry), "retry must recover to the real menu")
	if failures.is_empty():
		print("STARTUP TEST: PASS (icons, real threaded load, menu, progress, overlay cleanup, failure and retry)")
	else:
		for message in failures:
			push_error("STARTUP TEST: " + message)
	quit(0 if failures.is_empty() else 1)

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/startup-branding"))
	for viewport_size in [Vector2i(1280, 720), Vector2i(2340, 1080), Vector2i(1024, 768)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		var preview: Node = load("res://scenes/startup.tscn").instantiate()
		root.add_child(preview)
		current_scene = preview
		preview.set("_preview", true)
		for frame in 8:
			await process_frame
		preview.set("progress", 0.52)
		for frame in 35:
			await process_frame
		await RenderingServer.frame_post_draw
		var first := root.get_texture().get_image()
		first.save_png("res://outputs/startup-branding/loading-%dx%d.png" % [viewport_size.x, viewport_size.y])
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var second := root.get_texture().get_image()
		_check(first.get_data() != second.get_data(), "rendered loading screen must visibly animate")
		if viewport_size.x == 1280:
			second.save_png("res://outputs/startup-branding/loading-animated-second.png")
		preview.queue_free()
		await process_frame
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
