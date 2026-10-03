extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var overlay := preload("res://scripts/frame_pacing_overlay.gd").new()
	for i in 119:
		overlay.record_interval(1000.0 / 60.0)
	overlay.record_interval(250.0)
	check(overlay.get_stats().peak_ms == 250.0 and overlay.get_stats().stalls == 1, "Wall-clock counter exposes a stall rather than smoothing it away")
	for i in 120:
		overlay.record_interval(1000.0 / 60.0)
	check(is_equal_approx(overlay.get_stats().fps, 60.0) and overlay.get_stats().stalls == 0, "Old stalls expire from the fixed sample window")
	overlay.free()
	var world := Node3D.new()
	root.add_child(world)
	var scene_processing := world.is_processing()
	var branch := Node3D.new()
	branch.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(branch)
	var ui := Control.new()
	world.add_child(ui)
	var own_viewport := SubViewport.new()
	own_viewport.own_world_3d = true
	ui.add_child(own_viewport)
	var helper := preload("res://scripts/menu_performance.gd").new()
	ui.add_child(helper)
	helper.configure(world)
	helper.set_parked(true)
	check(root.disable_3d and branch.process_mode == Node.PROCESS_MODE_DISABLED, "Hidden arena rendering and processing are parked")
	check(ui.process_mode == Node.PROCESS_MODE_INHERIT and not own_viewport.disable_3d, "Garage UI and its independent viewport stay active")
	var late_branch := Node3D.new()
	late_branch.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(late_branch)
	var short_lived_branch := Node3D.new()
	world.add_child(short_lived_branch)
	short_lived_branch.free()
	await process_frame
	check(late_branch.process_mode == Node.PROCESS_MODE_DISABLED, "Deferred scenery added while parked is also suspended")
	helper.set_parked(false)
	check(not root.disable_3d and branch.process_mode == Node.PROCESS_MODE_PAUSABLE and late_branch.process_mode == Node.PROCESS_MODE_ALWAYS, "Exact original modes are restored")
	check(world.is_processing() == scene_processing, "Original scene processing is restored")
	helper.set_parked(true)
	helper.queue_free()
	await process_frame
	check(not root.disable_3d, "Scene teardown cannot leave the next scene without 3D")
	world.queue_free()
	await process_frame
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node("Interface")
	var garage: Node = flow.get("_forge_garage")
	check(garage != null and not garage.visible, "Garage is prepared before the first menu is interactive")
	flow.call("_open_equipment")
	check(flow.get("_forge_garage") == garage and root.disable_3d, "Opening garage reuses prepared geometry and parks the arena")
	flow.call("_open_menu")
	check(not root.disable_3d, "Main menu showcase keeps its original rendering")
	flow.call("_open_settings")
	check(root.disable_3d, "Opaque settings do not render the hidden arena")
	flow.call("_open_hud_editor")
	check(not root.disable_3d, "HUD editor can preview and test the real arena")
	flow.call("_on_hud_editor_closed")
	check(root.disable_3d, "Closing HUD editor parks the settings backdrop again")
	flow.call("_show_screen", flow.Screen.LOBBY)
	check(root.disable_3d, "Opaque lobby also parks its hidden arena")
	flow.call("_open_equipment")
	flow.call("_show_screen", flow.Screen.COMBAT)
	check(not root.disable_3d and flow.get("_forge_garage") == garage, "Returning to combat restores rendering without recreating garage")
	var director: Node = scene.get_node("CombatPresentationPass")
	director.set("_bootstrap_remaining", 0.0)
	director.set("_scan_pending", false)
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/bush_foliage.gdshader")
	mesh.material_override = material
	scene.add_child(mesh)
	check(director.get("_scan_pending"), "New reactive scenery invalidates discovery")
	director.call("_scan")
	check(not director.get("_scan_pending") and director.get("_prop_ids").has(mesh.get_instance_id()), "Late scenery remains reactive without permanent tree scans")
	var preview_mesh := MeshInstance3D.new()
	preview_mesh.mesh = QuadMesh.new()
	preview_mesh.material_override = material
	garage.stage.world.add_child(preview_mesh)
	check(not director.get("_scan_pending"), "Garage previews do not trigger combat scenery scans")
	# A transient mesh can disappear before deferred material inspection.
	var transient_mesh := MeshInstance3D.new()
	scene.add_child(transient_mesh)
	transient_mesh.free()
	await process_frame
	# Some scenery adapters assign their finish just after entering the tree.
	var late_material_mesh := MeshInstance3D.new()
	scene.add_child(late_material_mesh)
	director.set("_scan_pending", false)
	late_material_mesh.material_override = material
	await process_frame
	check(director.get("_scan_pending"), "Deferred material setup remains discoverable after bootstrap")
	var readout := scene.get_node("TargetDummy/TargetHealthReadout") as Node3D
	readout.hide()
	readout.call("clear_damage_numbers")
	readout.call("show_damage", 40.0)
	readout.call("show_healing", 30.0)
	check(readout.get("_latest_popup") == null and readout.get("_latest_healing_popup") == null, "Hidden cinematic readouts cannot allocate invisible combat numbers")
	readout.show()
	readout.call("set_cinematic_mode", true)
	readout.call("show_damage", 40.0)
	check(readout.get("_latest_popup") == null, "Visibility updates cannot reactivate numbers during a cinematic")
	readout.call("set_cinematic_mode", false)
	readout.call("show_damage", 40.0)
	check(readout.get("_latest_popup") != null, "Visible combat damage still creates the original popup")
	current_scene = null
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("MENU PERFORMANCE TEST: PASS")
	else:
		print("MENU PERFORMANCE TEST: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
