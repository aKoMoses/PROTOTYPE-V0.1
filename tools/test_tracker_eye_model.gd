extends SceneTree

## Actual shoulder-eye installs on three chassis, with isolated save files.
## --runtime runs the same transfer in the native rendered process loop.
const GARAGE := preload("res://scripts/forge_garage.gd")
const BASELINE := {"robot": "polyvalent", "weapon": "blaster", "offensive": "rocket_basket", "defensive": "magnetic_field", "mobility": "bio_injector", "passive": "auxiliary_reactor"}
var checks := 0
var failures: Array[String] = []
var mounted := 0
var completed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	garage.library_path = "user://tracker-eye-test-" + suffix + "-builds.cfg"
	garage.legacy_save_path = "user://tracker-eye-test-" + suffix + "-loadout.cfg"
	root.size = Vector2i(1280, 720)
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.installation.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.mounted.connect(func(_kind: String, _id: String): mounted += 1)
	garage.module_installation.completed.connect(func(_id: String): completed += 1)
	var runtime := OS.get_cmdline_user_args().has("--runtime")
	for chassis in ["polyvalent", "agile", "puissant"]:
		garage.set_loadout(BASELINE.merged({"robot": chassis}, true))
		garage.stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var stock: Node3D = garage.stage.module_stations.items.tracker
		garage._select_equipment("passive", "tracker")
		garage.module_installation.set_process(false)
		garage.module_installation.advance(2.30)
		check(not stock.visible and is_instance_valid(garage.module_installation._payload), "actual eye leaves storage: " + chassis)
		garage.module_installation.cancel(false)
		check(stock.visible and garage.loadout.passive == "auxiliary_reactor", "cancellation restores stock and old passive: " + chassis)
		garage._select_equipment("passive", "tracker")
		garage.module_installation.set_process(runtime)
		var before_mounted := mounted
		var before_completed := completed
		var start := Time.get_ticks_msec()
		var rigid := false
		var contact := false
		var premature := false
		for frame in 1500:
			if runtime:
				await process_frame
			else:
				garage.module_installation.advance(1.0 / 60.0)
			var installer = garage.module_installation
			if installer.phase == "carry" and is_instance_valid(installer._payload):
				rigid = installer._payload.get_parent() == installer._gripper
			if mounted == before_mounted:
				premature = premature or garage.loadout.passive != "auxiliary_reactor"
			elif not contact:
				contact = garage.stage.arm.contact.global_position.distance_to(installer._mount_pose.origin) < .06
			if not installer.active or Time.get_ticks_msec() - start > 15000:
				break
		check(not garage.module_installation.active and completed == before_completed + 1, "installation finishes exactly once: " + chassis)
		check(rigid and contact and not premature, "physical carry and contact precede equip: " + chassis)
		check(garage.loadout.passive == "tracker" and stock.visible and not is_instance_valid(garage.module_installation._payload), "installed eye, restored stock, transport removed: " + chassis)
		var modules = garage.stage.module_visuals
		var eye: Node3D = modules.mounts.tracker
		check(eye.visible and eye.get_parent() is BoneAttachment3D, "real skeletal eye after installation: " + chassis)
		check(modules.triangle_count("tracker") <= 5828, "eye keeps worst complete kit below 30k triangles")
		for mesh in eye.get_children():
			if mesh is MeshInstance3D and String(mesh.name) in ["tracker_ivory", "tracker_ochre"]:
				var uv: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
				var low := Vector2(INF, INF)
				var high := Vector2(-INF, -INF)
				for point in uv:
					low = low.min(point)
					high = high.max(point)
				check((high - low).x > .25 and (high - low).y > .25, "painted surfaces have usable texture UVs: " + String(mesh.name))
		garage.focus.show_equipment("passive", "tracker", false)
		garage.focus.advance(1.2)
		check(garage.focus.region_bounds().encloses(modules.module_bounds("tracker")), "inspection encloses sphere and foot: " + chassis)
		for weapon in ["blaster", "shotgun", "longshot", "mekatana"]:
			for offensive in ["rocket_basket", "javelin", "fulguro_punch", "pelto_smash"]:
				garage.set_loadout(BASELINE.merged({"robot": chassis, "weapon": weapon, "offensive": offensive, "passive": "tracker"}, true))
				check(garage.stage.module_visuals.mounts.tracker.visible and not garage.stage.module_visuals.mounts.reactor.visible, "exclusive eye with weapon and offensive: " + chassis + " " + weapon + " " + offensive)
		print("TRACKER INSTALL ", chassis, " runtime=", runtime, " elapsed_ms=", Time.get_ticks_msec() - start, " contact=", contact)
	var paths := [garage.library_path, garage.legacy_save_path]
	garage.queue_free()
	for frame in 3:
		await process_frame
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("TRACKER EYE TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
