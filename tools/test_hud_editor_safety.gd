extends SceneTree

const LAYOUT := preload("res://scripts/hud_layout.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var primary := "user://hud_schema_probe.json"
	var backup := "user://hud_schema_probe.backup.json"
	var temporary := "user://hud_schema_probe.tmp.json"
	var standard := {"version": LAYOUT.VERSION, "families": {"mobile": {"saved": LAYOUT.standard()}}}
	var left := {"version": LAYOUT.VERSION, "families": {"mobile": {"saved": LAYOUT.left_handed()}}}
	_check(LAYOUT.save_document(standard, primary, backup, temporary) and LAYOUT.save_document(left, primary, backup, temporary), "creates isolated saved layouts")
	var corrupted := FileAccess.open(primary, FileAccess.WRITE)
	corrupted.store_string('{"version":1,"families":"corrupted"}')
	corrupted.close()
	_check(LAYOUT.save_document(left, primary, backup, temporary), "repairs a primary layout with invalid schema")
	corrupted = FileAccess.open(primary, FileAccess.WRITE)
	corrupted.store_string("{")
	corrupted.close()
	var recovered: Dictionary = LAYOUT.load_from_paths(primary, backup)
	_check(recovered.families.has("mobile"), "repairing corrupt primary preserves the last readable backup")
	corrupted = FileAccess.open(primary, FileAccess.WRITE)
	corrupted.store_string(JSON.stringify({"version": 0, "layout": LAYOUT.left_handed()}))
	corrupted.close()
	_check(LAYOUT.save_document(standard, primary, backup, temporary), "migrates a readable legacy HUD layout")
	corrupted = FileAccess.open(primary, FileAccess.WRITE)
	corrupted.store_string("{")
	corrupted.close()
	recovered = LAYOUT.load_from_paths(primary, backup)
	var safe := Rect2(0, 0, 1280, 720)
	_check(recovered.families.has("mobile") and LAYOUT.center(recovered.families.mobile.saved.move, safe).x > safe.get_center().x, "legacy player layout remains recoverable after its first migration")
	for path in [primary, backup, temporary]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_open_settings")
	flow.call("_open_hud_editor")
	var editor: Control = flow.get_node("HudEditor")
	editor.call("_hint", "Touchez un élément pour le déplacer ou modifier sa taille.")
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720), Vector2i(800, 600)]:
		root.size = dimensions
		for _frame in range(4):
			await process_frame
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		var toolbar: Control = editor.get("_top")
		var side: Control = editor.get("_side")
		_check(viewport.grow(1).encloses(side.get_global_rect()), "editor panel fits %s: %s" % [dimensions, side.get_global_rect()])
		for control in toolbar.get_children():
			_check(viewport.grow(1).encloses(control.get_global_rect()), "toolbar item %s fits %s" % [control.name, dimensions])
		_check(side.position.y >= toolbar.get_global_rect().end.y, "toolbar does not overlap the editor panel at %s" % dimensions)
	editor.call("_discard_and_close")
	scene.queue_free()
	await process_frame
	print("HUD EDITOR/RECOVERY SAFETY: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
