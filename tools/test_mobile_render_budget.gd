extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manager := preload("res://scripts/vfx_manager.gd").new()
	manager._apply_device_budget(false)
	assert(manager.quality == manager.Quality.NORMAL)
	assert(manager.max_effects == 48 and manager.max_decals == 24 and manager.max_particles == 14)
	manager._apply_device_budget(true)
	assert(manager.quality == manager.Quality.LOW)
	assert(manager.max_effects == 24 and manager.max_decals == 8 and manager.max_particles == 6)
	manager.max_effects = 8
	manager.max_decals = 0
	manager.max_particles = 2
	manager._apply_device_budget(true)
	assert(manager.max_effects == 8 and manager.max_decals == 0 and manager.max_particles == 2)
	assert(is_equal_approx(float(ProjectSettings.get_setting("rendering/scaling_3d/scale.mobile")), 0.75))
	assert(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size.mobile") == 1024)
	manager.free()
	print("PASS: mobile rendering defaults, VFX limits and desktop defaults")
	quit()
