extends SceneTree

## Exercise the new authored objects through the real garage selection path.
## Saves are isolated; --runtime exercises both installs in the native loop.
const GARAGE := preload("res://scripts/forge_garage.gd")
const MODELS := {"fulguro_punch": "offensive", "static_shield": "defensive"}
const BASELINE := {"robot": "polyvalent", "weapon": "blaster", "offensive": "rocket_basket", "defensive": "magnetic_field", "mobility": "bio_injector", "passive": "auxiliary_reactor"}
var garage
var checks := 0
var failures: Array[String] = []
var mounted: Array[String] = []
var completed: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	garage.library_path = "user://fulguro-static-test-" + suffix + "-builds.cfg"
	garage.legacy_save_path = "user://fulguro-static-test-" + suffix + "-loadout.cfg"
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.installation.set_process(false)
	garage.focus.set_process(false)
	garage.stage.robot_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	garage.module_installation.mounted.connect(func(_category: String, identifier: String): mounted.append(identifier))
	garage.module_installation.completed.connect(func(identifier: String): completed.append(identifier))
	var runtime := OS.get_cmdline_user_args().has("--runtime")
	for chassis in (["polyvalent"] if runtime else ["polyvalent", "agile", "puissant"]):
		var equipment: Dictionary = BASELINE.duplicate()
		equipment.robot = chassis
		garage.set_loadout(equipment)
		for identifier in MODELS:
			var category: String = MODELS[identifier]
			var item: Node3D = garage.stage.module_stations.items[identifier]
			check(item.get_meta("equipment_id", "") == identifier, "authored catalog identity: " + identifier)
			for mesh in item.find_children("*", "MeshInstance3D", true, false):
				check(mesh.mesh is ArrayMesh and not mesh.mesh is PrimitiveMesh, "real mesh in storage: " + identifier)
			# Cancellation restores the real storage piece and does not equip it.
			garage._select_equipment(category, identifier)
			garage.module_installation.set_process(false)
			check(garage.module_installation.active, "selection starts arm transfer: " + identifier)
			garage.module_installation.advance(2.30)
			check(not item.visible and is_instance_valid(garage.module_installation._payload), "real module picked up: " + identifier)
			garage.module_installation.cancel(false)
			check(item.visible and garage.loadout[category] == equipment[category], "cancel restores stock without changing loadout: " + identifier)
			garage._select_equipment(category, identifier)
			garage.module_installation.set_process(runtime)
			var before: Dictionary = garage.loadout.duplicate(true)
			var mounted_before := mounted.size()
			var completed_before := completed.size()
			var deadline := Time.get_ticks_msec() + 15000
			var contact_ok := false
			var carried := false
			var premature := false
			var start := Time.get_ticks_msec()
			for frame in 1500:
				if runtime:
					await process_frame
				else:
					garage.module_installation.advance(1.0 / 60.0)
				var installer = garage.module_installation
				if installer.phase == "carry" and is_instance_valid(installer._payload):
					carried = installer._payload.get_parent() == installer._gripper
				if mounted.size() == mounted_before:
					premature = premature or garage.loadout != before
				elif not contact_ok:
					contact_ok = garage.stage.arm.contact.global_position.distance_to(installer._mount_pose.origin) < 0.06
				if not installer.active or Time.get_ticks_msec() > deadline:
					break
			check(not garage.module_installation.active and completed.size() == completed_before + 1 and completed.back() == identifier, "complete real install: " + chassis + " " + identifier)
			check(carried and contact_ok and not premature, "rigid transport and physical fastening precede equip: " + chassis + " " + identifier)
			check(garage.loadout[category] == identifier, "selected module installed: " + identifier)
			check(item.visible and garage._ui.visible and not garage._cinema.visible, "stock and garage UI restored: " + identifier)
			check(not is_instance_valid(garage.module_installation._payload), "transport copy removed: " + identifier)
			var module_key := "fulguro" if identifier == "fulguro_punch" else "static"
			var mount: Node3D = garage.stage.module_visuals.mounts[module_key]
			check(mount.visible, "authored part visible after install: " + identifier)
			var pose: Transform3D = garage.stage.module_visuals.module_transform(identifier)
			garage.focus.show_equipment(category, identifier, false)
			garage.focus.advance(0.8)
			check(garage.focus.region_bounds().encloses(garage.stage.module_visuals.module_bounds(identifier)), "inspection frames the actual insert: " + identifier)
			check(pose.origin.distance_to(garage.stage.robot.global_position) > 0.3, "socket stays on the robot: " + identifier)
			print("NEW MODULE INSTALL ", chassis, " ", identifier, " runtime=", runtime, " elapsed_ms=", Time.get_ticks_msec()-start, " contact=", contact_ok)
			equipment[category] = identifier
	garage.module_installation.set_process(false)
	# Both inserts coexist; each remains visible with all four weapons.
	for weapon in ["blaster", "shotgun", "longshot", "mekatana"]:
		var equipment: Dictionary = BASELINE.duplicate()
		equipment.weapon = weapon
		equipment.offensive = "fulguro_punch"
		equipment.defensive = "static_shield"
		garage.set_loadout(equipment)
		check(garage.stage.module_visuals.mounts.fulguro.visible and garage.stage.module_visuals.mounts.static.visible, "both inserts with weapon: " + weapon)
	var paths := [garage.library_path, garage.legacy_save_path]
	garage.queue_free()
	for frame in 3:
		await process_frame
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("FULGURO STATIC MODELS TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
