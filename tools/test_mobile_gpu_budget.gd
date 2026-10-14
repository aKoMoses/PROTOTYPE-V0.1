extends SceneTree
const BUDGET := preload("res://scripts/mobile_render_budget.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	light.light_energy = 0.86
	world.add_child(light)
	var preview := SubViewport.new()
	preview.size = Vector2i(640, 360)
	preview.scaling_3d_scale = 0.75
	preview.msaa_3d = Viewport.MSAA_2X
	world.add_child(preview)
	var budget := BUDGET.new()
	world.add_child(budget)
	await process_frame
	check(not budget.is_processing(), "desktop profile is idle")
	check(light.shadow_enabled and is_equal_approx(preview.scaling_3d_scale, 0.75), "desktop rendering is retained")
	var root_scale := root.scaling_3d_scale
	var physics_hz := Engine.physics_ticks_per_second
	budget.activate()
	check(not light.shadow_enabled, "existing shadow pass is removed")
	check(is_equal_approx(light.light_energy, 0.86), "illumination is retained")
	check(is_equal_approx(preview.scaling_3d_scale, 0.5) and preview.msaa_3d == Viewport.MSAA_DISABLED, "preview gets the same GPU budget")
	check(preview.size == Vector2i(640, 360), "viewport and HUD dimensions are retained")
	check(Engine.physics_ticks_per_second == physics_hz, "physics cadence is retained")
	var late_light := OmniLight3D.new()
	world.add_child(late_light)
	late_light.shadow_enabled = true
	budget._process(0.016)
	check(not late_light.shadow_enabled, "constructor writes after node_added are covered")
	light.shadow_enabled = true
	preview.scaling_3d_scale = 1.0
	preview.msaa_3d = Viewport.MSAA_4X
	paused = true
	budget._process(0.016)
	check(not light.shadow_enabled and preview.scaling_3d_scale == 0.5 and preview.msaa_3d == Viewport.MSAA_DISABLED, "late quality adapters and pause keep the mobile budget")
	paused = false
	preview.scaling_3d_scale = 0.4
	budget._process(0.016)
	check(is_equal_approx(preview.scaling_3d_scale, 0.4), "stricter render scale is retained")
	late_light.free()
	budget._process(0.016)
	check(budget._targets.size() == 3, "freed light leaves no stale target")
	world.remove_child(preview)
	budget._process(0.016)
	check(is_equal_approx(preview.scaling_3d_scale, 0.75) and preview.msaa_3d == Viewport.MSAA_2X, "detached viewport recovers its own settings")
	world.add_child(preview)
	budget._process(0.016)
	check(preview.scaling_3d_scale == 0.5, "reattached viewport is budgeted again")
	budget.deactivate()
	check(light.shadow_enabled and preview.scaling_3d_scale == 0.75 and preview.msaa_3d == Viewport.MSAA_2X, "deactivation restores prior rendering")
	check(is_equal_approx(root.scaling_3d_scale, root_scale), "root scale is restored")
	check(not budget.is_processing(), "deactivated profile has no frame work")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("MOBILE GPU BUDGET: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
