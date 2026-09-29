extends SceneTree

const LAYOUT := preload("res://scripts/hud_layout.gd")

func _initialize() -> void:
	var startup_fixture := Node.new()
	root.add_child(startup_fixture)
	current_scene = startup_fixture
	var suffix := str(Time.get_ticks_usec())
	var primary := "user://prototype0_hud_probe_%s.json" % suffix
	var backup := "user://prototype0_hud_probe_%s.backup.json" % suffix
	var temporary := "user://prototype0_hud_probe_%s.tmp.json" % suffix
	var first := {"version": LAYOUT.VERSION, "families": {"mobile": {"saved": LAYOUT.standard()}}}
	var second := {"version": LAYOUT.VERSION, "families": {"mobile": {"saved": LAYOUT.left_handed()}}}
	var worked := LAYOUT.save_document(first, primary, backup, temporary)
	if worked:
		worked = LAYOUT.save_document(second, primary, backup, temporary)
	if worked:
		var loaded: Dictionary = LAYOUT.load_from_paths(primary, backup)
		worked = loaded.families.has("mobile") and LAYOUT.center(loaded.families.mobile.saved.move, Rect2(0, 0, 1280, 720)).x > 640
	for path in [primary, backup, temporary]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if worked:
		print("P0 HUD USER SAVE TEST: PASS")
		quit(0)
	else:
		push_error("FAIL: écriture/relecture du dossier user://")
		quit(1)
