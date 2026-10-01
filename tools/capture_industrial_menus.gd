extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const OUTPUT := "res://captures/industrial-menus/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	flow.call("_open_settings")
	await _capture("01-settings.png")
	flow.get("_settings_panel").call("_select_page", 1)
	await _capture("01b-commands.png")
	flow.get("_settings_panel").call("_select_page", 2)
	await _capture("01c-interface.png")
	flow.call("_clear_screen")
	var lobby: Control = flow.get("_lobby_panel")
	lobby.show()
	var session: Node = root.get_node("NetworkSession")
	# Deterministic demonstration data; do not create a real hosted lobby.
	session.set("connected", true)
	lobby.call("_update_controls")
	lobby.call("_on_rooms_changed", [{"title": "Salon de Romain", "players": 1}, {"title": "Duel du soir", "players": 1}])
	await _capture("02-room-browser.png")
	session.set("current_room", {"title": "Salon de Romain", "host_id": 77, "guest_id": 22, "phase": "waiting"})
	lobby.call("_on_room_changed", session.get("current_room"))
	# Presentation fixture is the host seat; no relay connection is started.
	lobby.get("_host_label").text = "Vous"
	lobby.get("_guest_label").text = "Adversaire"
	lobby.get("_start_button").disabled = false
	await _capture("03-joined-room.png")
	flow.call("_clear_screen")
	var first: Dictionary = LOADOUT.defaults()
	var second := {"robot": "agile", "weapon": "longshot", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"}
	var precombat: Control = flow.get("_precombat_overlay")
	precombat.call("reveal", first, second, 8.0)
	await _capture("04-precombat.png")
	root.size = Vector2i(1600, 720)
	await _capture("04b-precombat-wide.png")
	root.size = Vector2i(960, 540)
	await _capture("04c-precombat-mobile.png")
	root.size = Vector2i(800, 600)
	await _capture("04d-precombat-tablet.png")
	root.size = Vector2i(1600, 720)
	flow.call("_open_settings")
	await _capture("01d-settings-wide.png")
	session.set("connected", false)
	session.set("current_room", {})
	scene.queue_free()
	await process_frame
	print("INDUSTRIAL MENUS CAPTURE: PASS")
	quit()

func _capture(filename: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var path := OUTPUT+filename
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Capture failed: "+path)
		quit(1)
