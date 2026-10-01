extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const OUTPUT := "res://captures/garage-builds/"
var garage


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	garage = GARAGE.new()
	garage.library_path = "user://garage-capture-builds.cfg"
	garage.legacy_save_path = "user://garage-capture-loadout.cfg"
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage._select_equipment("robot", "agile")
	garage._select_equipment("passive", "alternator")
	await create_timer(0.8).timeout
	await capture("01-passifs")
	garage._select_equipment("passive", "omnivamp")
	await create_timer(0.6).timeout
	await capture("02-description-video")
	garage._navigate("ARMES")
	await capture("03-armes")
	garage._open_modules("passive")
	garage._save_build()
	garage.installation.set_process(false)
	for frame in 70:
		garage.installation.advance(1.0 / 60.0)
	await capture("04-installation-torse")
	for frame in 72:
		garage.installation.advance(1.0 / 60.0)
	await capture("05-installation-bras")
	for frame in 72:
		garage.installation.advance(1.0 / 60.0)
	await capture("06-installation-jambes")
	for frame in 87:
		garage.installation.advance(1.0 / 60.0)
	await capture("07-sauvegarde")
	root.size = Vector2i(960, 540)
	await capture("08-mobile-paysage")
	root.size = Vector2i(1600, 900)
	garage._open_modules("defensive")
	garage._select_equipment("defensive", "projector")
	await create_timer(0.5).timeout
	await capture("09-fiche-longue")
	garage.queue_free()
	await process_frame
	for path in ["user://garage-capture-builds.cfg", "user://garage-capture-loadout.cfg"]:
		DirAccess.remove_absolute(path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await capture("00-menu")
	main.queue_free()
	for frame in 4:
		await process_frame
	print("GARAGE BUILD CAPTURE: PASS")
	quit()


func capture(label: String) -> void:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	print("GARAGE BUILD CAPTURE: ", label, " code=", root.get_texture().get_image().save_png(OUTPUT + label + ".png"))
