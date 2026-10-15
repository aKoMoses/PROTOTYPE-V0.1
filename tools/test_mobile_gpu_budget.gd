extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	var budget := root.get_node("MobileRenderBudget")
	check(not budget.is_processing(), "desktop profile is idle")
	root.scaling_3d_scale = 0.75
	root.msaa_3d = Viewport.MSAA_2X
	var size_before := root.size
	var physics_hz := Engine.physics_ticks_per_second
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	light.light_energy = 0.86
	scene.add_child(light)
	var preview := SubViewport.new()
	preview.size = Vector2i(640, 360)
	preview.scaling_3d_scale = 0.8
	preview.msaa_3d = Viewport.MSAA_4X
	scene.add_child(preview)
	var preview_light := OmniLight3D.new()
	preview_light.shadow_enabled = true
	preview.add_child(preview_light)
	budget.activate()
	check(light.shadow_enabled and root.scaling_3d_scale == 0.75 and root.msaa_3d == Viewport.MSAA_2X, "menu keeps its original rendering")
	flow.call("_show_screen", 1)
	budget._process(0.016)
	check(light.shadow_enabled and root.scaling_3d_scale == 0.75, "garage keeps its original rendering")
	flow.call("_start_duel")
	budget._process(0.016)
	check(not light.shadow_enabled and is_equal_approx(light.light_energy, 0.86), "duel removes shadow passes while retaining lighting")
	check(root.scaling_3d_scale == 0.5 and root.msaa_3d == Viewport.MSAA_DISABLED, "duel reduces the main 3D viewport")
	check(is_equal_approx(preview.scaling_3d_scale, 0.8) and preview.msaa_3d == Viewport.MSAA_4X and preview_light.shadow_enabled, "preview rendering is never changed")
	check(root.size == size_before and Engine.physics_ticks_per_second == physics_hz, "HUD dimensions and physics cadence are retained")
	var late_light := OmniLight3D.new()
	scene.add_child(late_light)
	late_light.shadow_enabled = true
	await process_frame
	budget._process(0.016)
	check(not late_light.shadow_enabled, "new combat lights are budgeted after configuration")
	light.shadow_enabled = true
	root.scaling_3d_scale = 1.0
	paused = true
	budget._process(0.016)
	check(not light.shadow_enabled and root.scaling_3d_scale == 0.5, "paused combat retains its budget")
	paused = false
	root.scaling_3d_scale = 0.4
	budget._process(0.016)
	check(is_equal_approx(root.scaling_3d_scale, 0.4), "stricter render scale is retained")
	flow.call("_show_screen", 0)
	budget._process(0.016)
	check(light.shadow_enabled and late_light.shadow_enabled, "returning to the menu restores shadow settings")
	check(root.scaling_3d_scale == 0.75 and root.msaa_3d == Viewport.MSAA_2X, "returning to the menu restores viewport settings")
	flow.call("_start_duel")
	budget._process(0.016)
	budget.deactivate()
	check(light.shadow_enabled and root.scaling_3d_scale == 0.75, "deactivation restores rendering during combat")
	check(not budget.is_processing(), "deactivated profile has no frame work")
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("MOBILE GPU BUDGET: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
