extends SceneTree

const LIBRARY := preload("res://scripts/garage_build_library.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var backups := {}
	for path in [LIBRARY.SAVE_PATH, LOADOUT.SAVE_PATH]:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	var library := LIBRARY.load_local()
	var equipment := LOADOUT.defaults()
	equipment.weapon = "shotgun"
	library = LIBRARY.with_build(library, "", "TEST SOLO", equipment)
	LIBRARY.save_local(library)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_select_arena", "resonance")
	flow.call("_open_solo_setup")
	await process_frame
	var setup: Control = flow.get("_solo_setup")
	assert(setup.visible and not (flow.get("_menu_panel") as Control).visible)
	assert(setup.loadouts.get_item_text(setup.loadouts.selected) == "TEST SOLO")
	setup._cycle(-1)
	assert(flow.get("_arena_variant") == "gyre")
	setup._cycle(1)
	assert(flow.get("_arena_variant") == "resonance")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/BOTTEROOOW/.codex/solo-setup-desktop.png")
		root.size = Vector2i(960, 540)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/BOTTEROOOW/.codex/solo-setup-landscape.png")
	flow.call("_close_solo_setup")
	assert((flow.get("_menu_panel") as Control).visible)
	assert((flow.get("_solo_camera_state") as Dictionary).is_empty())
	flow.call("_open_solo_setup")
	flow.call("_launch_solo")
	await process_frame
	assert(int(flow.get("current_screen")) == 3)
	assert(str(flow.get("loadout").weapon) == "shotgun")
	assert(not setup.visible)
	assert((flow.get("_solo_camera_state") as Dictionary).is_empty())
	for path in backups:
		if backups[path] == null:
			DirAccess.remove_absolute(path)
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backups[path])
	print("SOLO SETUP: PASS (saved build, arena preview, return, direct duel, camera restore)")
	quit()
