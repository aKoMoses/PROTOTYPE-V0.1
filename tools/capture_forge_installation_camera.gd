extends "res://tools/test_forge_installation_camera.gd"

var output := "res://captures/forge-installation-camera/after/"


func _run() -> void:
	if "--before" in OS.get_cmdline_user_args():
		output = "res://captures/forge-installation-camera/before/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open(output + ".gdignore", FileAccess.WRITE)
	ignore.store_string("\n")
	ignore.close()
	await _setup()
	for sample in [["offensive", "rocket_basket", "polyvalent", LOADOUT.OFFENSIVE],
		["defensive", "magnetic_field", "polyvalent", LOADOUT.DEFENSIVE],
		["mobility", "pyro_boots", "puissant", LOADOUT.MOBILITY],
		["passive", "auxiliary_reactor", "agile", LOADOUT.PASSIVES],
		["weapon", "longshot", "polyvalent", LOADOUT.WEAPONS]]:
		_start(sample[0], sample[1], sample[2], sample[3])
		for timestamp in [1.80, 2.75, 3.15, 3.60, 4.05, 4.80, 6.70]:
			while garage.module_installation.active and garage.module_installation.elapsed < timestamp:
				garage.module_installation.advance(STEP)
			_pause()
			await create_timer(0.12).timeout
			await RenderingServer.frame_post_draw
			var label := "%s-%03d-%s" % [sample[1], int(timestamp * 100), garage.module_installation.phase]
			root.get_texture().get_image().save_png(output + label + ".png")
		garage.module_installation.finish_now()
		_pause()
		print("CAMERA CAPTURE ", sample[1])
	garage.queue_free()
	for frame in 4:
		await process_frame
	print("FORGE INSTALLATION CAMERA CAPTURE: ", ProjectSettings.globalize_path(output))
	quit()
