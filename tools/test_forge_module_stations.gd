extends SceneTree

## Real equipment transport, deliberate GUI selection and isolated persistence.
## Run with --script res://tools/test_forge_module_stations.gd; --runtime also
## checks one complete installation using the engine's native frame loop.
const GARAGE := preload("res://scripts/forge_garage.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const LIBRARY := preload("res://scripts/garage_build_library.gd")
const STEP := 1.0 / 60.0
const CATEGORIES := {
	"offensive": LOADOUT.OFFENSIVE, "defensive": LOADOUT.DEFENSIVE,
	"mobility": LOADOUT.MOBILITY, "passive": LOADOUT.PASSIVES,
}
const REAL_MODULES := ["pyro_boots", "bio_injector", "rocket_basket", "magnetic_field", "auxiliary_reactor"]
const PHYSICAL := {
	"weapon": LOADOUT.WEAPONS, "offensive": ["rocket_basket"],
	"defensive": ["magnetic_field"], "mobility": ["pyro_boots", "bio_injector"],
	"passive": ["auxiliary_reactor"],
}
var garage
var failures: Array[String] = []
var checks := 0
var completed: Array[String] = []
var mounted: Array[String] = []
var saved: Array[Dictionary] = []
var tested: Array[Dictionary] = []
var real_files: Dictionary = {}
var temporary_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	for path in [LOADOUT.SAVE_PATH, LIBRARY.SAVE_PATH]:
		real_files[path] = {"existed": FileAccess.file_exists(path), "bytes": _bytes(path)}
	var suffix := str(Time.get_ticks_usec())
	temporary_paths = ["user://forge-stations-test-" + suffix + "-builds.cfg", "user://forge-stations-test-" + suffix + "-loadout.cfg"]
	garage = GARAGE.new()
	garage.library_path = temporary_paths[0]
	garage.legacy_save_path = temporary_paths[1]
	root.add_child(garage)
	await process_frame
	_pause_controllers()
	garage.module_installation.completed.connect(func(identifier: String): completed.append(identifier))
	garage.module_installation.mounted.connect(func(_category: String, identifier: String): mounted.append(identifier))
	garage.build_saved.connect(func(equipment: Dictionary): saved.append(equipment.duplicate(true)))
	garage.test_requested.connect(func(equipment: Dictionary): tested.append(equipment.duplicate(true)))
	_check_storage_inventory()
	if "--runtime" in OS.get_cmdline_user_args():
		await _native_runtime()
	else:
		for chassis in LOADOUT.ROBOTS:
			garage._select_equipment("robot", chassis)
			for category in PHYSICAL:
				for identifier in PHYSICAL[category]:
					await _installation_cycle(category, identifier, chassis)
			await _generic_equipment(chassis)
		await _cancel_and_skip()
		await _gui_and_framing()
		await _double_click_equip()
		await _save_and_test()
	garage.queue_free()
	for frame in 4:
		await process_frame
	for path in real_files:
		var unchanged: bool = FileAccess.file_exists(path) == real_files[path].existed and _bytes(path) == real_files[path].bytes
		check(unchanged, "real user save untouched: " + path)
		if not unchanged:
			_restore(path, real_files[path])
	for path in temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FORGE MODULE STATIONS TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks; ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _pause_controllers() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage.installation.set_process(false)


func _advance(delta: float) -> void:
	garage.module_installation.advance(delta)
	if not garage.module_installation.active:
		garage.focus.advance(delta)


func _check_storage_inventory() -> void:
	var stations = garage.stage.module_stations
	check(stations.station_nodes.size() == 4, "four distinct storage bays exist")
	check(stations.items.size() == 18, "all eighteen module choices retain their catalog storage locations")
	check(garage.stage.weapon_rack != null and garage.stage.weapon_rack.items.size() == 4, "a separate rack stores the four real weapons")
	for category in CATEGORIES:
		check(stations.bounds(category).size.length() > 0.25, "rack has useful world bounds: " + category)
		for identifier in CATEGORIES[category]:
			check(stations.items.has(identifier), "module retains its catalog storage location: " + identifier)
			if identifier in REAL_MODULES:
				_check_pickup_geometry(identifier)
	for identifier in LOADOUT.WEAPONS:
		check(garage.stage.weapon_rack.items.has(identifier), "real weapon stocked separately: " + identifier)
		_check_pickup_geometry(identifier)
	_check_no_placeholders("initial loadout")


func _check_pickup_geometry(identifier: String) -> void:
	var storage = _storage(identifier)
	var transform: Transform3D = storage.module_transform(identifier)
	check(transform.origin.is_finite() and transform.basis.determinant() != 0.0, "valid pickup transform: " + identifier)
	check(transform.is_equal_approx(_storage_item(identifier).global_transform) and _storage_item(identifier).visible, "pickup transform matches the stocked equipment: " + identifier)
	var payload: Node3D = storage.create_payload(identifier)
	check(payload != null and payload.get_parent() == null and payload.visible, "payload starts detached and visible: " + identifier)
	if payload == null:
		return
	check(_same_mesh_resources(_storage_item(identifier), payload), "transported equipment shares its actual rack geometry: " + identifier)
	if identifier in LOADOUT.WEAPONS:
		var source := (garage.stage.WEAPON_MODELS[identifier] as PackedScene).instantiate() as Node3D
		check(_same_mesh_resources(source, payload), "weapon rack displays its actual gameplay model: " + identifier)
		source.free()
	else:
		for node in payload.find_children("*", "MeshInstance3D", true, false):
			check(not (node as MeshInstance3D).mesh is PrimitiveMesh, "modeled module payload contains authored mesh: " + identifier)
	payload.free()


func _installation_cycle(category: String, identifier: String, chassis: String) -> void:
	# Start from a different module so that a premature commit cannot pass.
	var baseline: Dictionary = garage.loadout.duplicate(true)
	var catalog: Array = LOADOUT.WEAPONS if category == "weapon" else CATEGORIES[category]
	baseline[category] = catalog[1] if identifier == catalog[0] else catalog[0]
	garage.set_loadout(baseline)
	_open_station(category)
	garage.focus.advance(1.1)
	var before: Dictionary = garage.loadout.duplicate(true)
	var rest_tip: Vector3 = garage.stage.arm.contact.global_position
	var rest_joints: Array[Transform3D] = _joint_transforms()
	var initial_camera: Transform3D = garage.stage.camera.global_transform
	var completed_before := completed.size()
	var mounted_before := mounted.size()
	garage._select_equipment(category, identifier)
	garage.module_installation.set_process(false)
	check(garage.module_installation.active and garage.loadout == before, "equip begins physical transfer before changing build: " + chassis + " " + identifier)
	check(garage.stage.camera.global_transform.is_equal_approx(initial_camera), "camera starts its travel without a cut: " + identifier)
	var target: Transform3D = garage.stage.weapon_mount_transform(identifier) if category == "weapon" else garage.stage.module_visuals.module_transform(identifier)
	check((garage.module_installation._mount_pose as Transform3D).is_equal_approx(target), "installer uses the actual equipment socket transform: " + identifier)
	var old_tip := rest_tip
	var greatest_movement := 0.0
	var largest_step := 0.0
	var saw_attached_payload := false
	var payload_offset := Transform3D.IDENTITY
	var carried_offset_set := false
	var payload_position := Vector3.ZERO
	var payload_rotation := Quaternion.IDENTITY
	var payload_position_set := false
	var largest_payload_step := 0.0
	var largest_payload_rotation := 0.0
	var saw_mount := false
	var fixed_payload_valid := true
	var pickup_visibility_valid := true
	var before_mount_valid := true
	var mounted_loadout_valid := true
	var mount_contact_valid := true
	var weapon_visibility_valid := true
	var duration := 0.0
	var phases: Array[String] = []
	for frame in 900:
		_advance(STEP)
		duration += STEP
		var installer = garage.module_installation
		if not phases.has(str(installer.phase)):
			phases.append(str(installer.phase))
		var tip: Vector3 = garage.stage.arm.contact.global_position
		greatest_movement = maxf(greatest_movement, rest_tip.distance_to(tip))
		# Returning to the authored rest happens after the physical work.
		if installer.active:
			largest_step = maxf(largest_step, tip.distance_to(old_tip))
		old_tip = tip
		var payload := _payload()
		if is_instance_valid(payload):
			if payload_position_set:
				largest_payload_step = maxf(largest_payload_step, payload_position.distance_to(payload.global_position))
				largest_payload_rotation = maxf(largest_payload_rotation, payload_rotation.angle_to(payload.global_basis.orthonormalized().get_rotation_quaternion()))
			payload_position = payload.global_position
			payload_rotation = payload.global_basis.orthonormalized().get_rotation_quaternion()
			payload_position_set = true
			var gripper: Node3D = garage.module_installation._gripper
			if payload.get_parent() == gripper and gripper.get_parent() == garage.stage.arm.contact:
				saw_attached_payload = true
				if str(installer.phase) == "carry":
					if not carried_offset_set:
						payload_offset = payload.transform
						carried_offset_set = true
					fixed_payload_valid = fixed_payload_valid and payload.transform.is_equal_approx(payload_offset)
				pickup_visibility_valid = pickup_visibility_valid and not _storage_item(identifier).visible
		if mounted.size() == mounted_before:
			before_mount_valid = before_mount_valid and garage.loadout == before
			if category == "weapon":
				weapon_visibility_valid = weapon_visibility_valid and (not garage.stage.weapon_socket.visible if str(installer.phase) in ["align", "work"] else garage.stage.weapon_socket.visible)
		else:
			if not saw_mount:
				mount_contact_valid = garage.stage.arm.contact.global_position.distance_to(installer._mount_pose.origin) <= 0.06
			saw_mount = true
			var expected: Dictionary = before.duplicate(true)
			expected[category] = identifier
			mounted_loadout_valid = mounted_loadout_valid and garage.loadout == expected
			if category == "weapon":
				weapon_visibility_valid = weapon_visibility_valid and garage.stage.weapon_socket.visible
		if not installer.active:
			break
	check(not garage.module_installation.active, "installation reaches a finite completion: " + chassis + " " + identifier)
	check(saw_attached_payload and greatest_movement > 0.5, "arm really collects and transports the module: " + chassis + " " + identifier)
	check(carried_offset_set and fixed_payload_valid, "carried object remains fixed in the gripper: " + identifier)
	check(pickup_visibility_valid, "pickup removes the copy from the rack: " + identifier)
	check(before_mount_valid, "build stays unchanged before physical fastening: " + identifier)
	check(mounted_loadout_valid, "mount changes exactly the selected build slot: " + identifier)
	check(mount_contact_valid, "equipment commits only at the physical mounting contact: " + identifier)
	check(duration > 6.9 and duration < 7.3, "physical transfer lasts approximately seven seconds: " + identifier + " seconds=" + str(duration))
	check(largest_step < 0.5, "arm travels continuously without joint teleport: " + identifier + " step=" + str(largest_step))
	check(largest_payload_step < 0.5, "module travels continuously through pickup and mounting: " + identifier + " step=" + str(largest_payload_step))
	check(largest_payload_rotation < 0.25, "gripper swivel orients the cartridge continuously: " + identifier + " angle=" + str(largest_payload_rotation))
	check(saw_mount and mounted.size() == mounted_before + 1 and completed.size() == completed_before + 1, "one physical mount and one completion: " + identifier)
	check(not garage.stage.arm.active and not garage.stage.arm.manual_control and not garage.stage.arm.particles.emitting, "arm and sparks released after installation: " + identifier)
	check(_same_joint_transforms(rest_joints), "authored resting joints restored: " + identifier)
	check(_storage_item(identifier).visible, "rack available again after work: " + identifier)
	check(garage._ui.visible, "submenu returns after installation: " + identifier)
	check(garage._category == category, "installation returns to its own module or weapon rack: " + identifier)
	_check_no_placeholders("installed " + identifier)
	if category == "weapon":
		check(weapon_visibility_valid, "previous weapon clears alignment and newly mounted weapon is visible: " + identifier)
		check(garage.stage.weapon_id == identifier, "committed weapon uses the real hand socket: " + identifier)
		check(_same_mesh_resources(_storage_item(identifier), garage.stage.weapon_socket), "installed weapon uses the same mesh resources as the rack: " + identifier)
	check(not FileAccess.file_exists(temporary_paths[0]) and not FileAccess.file_exists(temporary_paths[1]), "equipping does not save the draft: " + identifier)
	print("STATION INSTALL ", chassis, " ", identifier, " phases=", phases, " movement=", greatest_movement, " max-step=", largest_step)
	await process_frame
	_pause_controllers()


func _generic_equipment(chassis: String) -> void:
	for category in CATEGORIES:
		for identifier in CATEGORIES[category]:
			if identifier in REAL_MODULES:
				continue
			var draft: Dictionary = garage.loadout.duplicate(true)
			draft[category] = PHYSICAL[category][0]
			garage.set_loadout(draft)
			var mounted_before := mounted.size()
			var completed_before := completed.size()
			var rest_joints := _joint_transforms()
			garage._select_equipment(category, identifier)
			check(str(garage.loadout[category]) == identifier, "unmodeled catalog choice equips directly: " + chassis + " " + identifier)
			check(not garage.module_installation.active and not is_instance_valid(_payload()) and not garage.stage.arm.manual_control, "unmodeled choice creates no transport or fake part: " + identifier)
			check(mounted.size() == mounted_before and completed.size() == completed_before and _same_joint_transforms(rest_joints), "direct choice never performs a fictional physical mount: " + identifier)
			check(not garage.module_installation.begin(identifier, category), "installer rejects unmodeled geometry: " + identifier)
			_check_no_placeholders("direct " + identifier)
	await process_frame
	_pause_controllers()


func _cancel_and_skip() -> void:
	for category in ["offensive", "weapon"]:
		var identifier := "rocket_basket" if category == "offensive" else "shotgun"
		var cancel_phases := ["pickup", "carry", "align", "work"] if category == "weapon" else ["pickup", "carry", "work"]
		for target_phase in cancel_phases:
			var draft: Dictionary = garage.loadout.duplicate(true)
			draft[category] = "javelin" if category == "offensive" else "blaster"
			garage.set_loadout(draft)
			var rest_joints := _joint_transforms()
			garage._select_equipment(category, identifier)
			garage.module_installation.set_process(false)
			var reached := false
			for frame in 700:
				if str(garage.module_installation.phase) == target_phase:
					reached = true
					break
				_advance(STEP)
				if not garage.module_installation.active:
					break
			check(reached, "cancellation exercised for " + identifier + " during " + target_phase)
			if target_phase == "carry":
				garage._save_build()
				garage._test_build()
				check(garage.module_installation.active and not garage.installation.active and saved.is_empty() and tested.is_empty(), "save and test cannot interrupt unmounted equipment or take the arm")
			var before_cancel: Dictionary = garage.loadout.duplicate(true)
			garage.module_installation.cancel()
			check(not garage.module_installation.active and not garage.stage.arm.active, "cancellation releases arm: " + identifier + " " + target_phase)
			check(_storage_item(identifier).visible and not is_instance_valid(_payload()), "cancellation restores rack and destroys carried object: " + identifier + " " + target_phase)
			check(_same_joint_transforms(rest_joints) and garage._ui.visible, "cancellation restores resting pose and UI: " + identifier + " " + target_phase)
			check(garage.loadout == before_cancel, "cancellation preserves last physically committed build: " + identifier + " " + target_phase)
			if category == "weapon":
				check(garage.stage.weapon_socket.visible and garage.stage.weapon_id == str(draft.weapon), "weapon cancellation restores the visible original hand weapon: " + target_phase)
			_check_no_placeholders("cancelled " + identifier)
			await process_frame
			_pause_controllers()
	garage._select_equipment("passive", "auxiliary_reactor")
	garage.module_installation.set_process(false)
	var count := mounted.size()
	garage.module_installation.finish_now()
	check(not garage.module_installation.active and str(garage.loadout.passive) == "auxiliary_reactor" and mounted.size() == count + 1, "skip completes the real pending mount exactly once")
	garage.module_installation.finish_now()
	check(mounted.size() == count + 1, "a second skip cannot mount twice")
	garage._select_equipment("defensive", "magnetic_field")
	garage.module_installation.set_process(false)
	_advance(1.0)
	garage.hide()
	check(not garage.module_installation.active and not garage.stage.arm.active and _storage_item("magnetic_field").visible, "leaving the garage cancels transport cleanly")
	garage.show()
	await process_frame
	_pause_controllers()


func _gui_and_framing() -> void:
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(2340, 1080)]:
		root.size = dimensions
		for frame in 3:
			await process_frame
		_pause_controllers()
		for category in PHYSICAL:
			var identifier: String = PHYSICAL[category][0]
			var catalog: Array = LOADOUT.WEAPONS if category == "weapon" else CATEGORIES[category]
			var baseline: Dictionary = garage.loadout.duplicate(true)
			baseline[category] = catalog[1] if identifier == catalog[0] else catalog[0]
			garage.set_loadout(baseline)
			garage._show_garage()
			garage.focus.advance(1.1)
			await process_frame
			var button: Button = garage.station_buttons[category]
			check(button.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(button.get_global_rect()), "station can be selected at " + str(dimensions) + ": " + category)
			var storage = _storage(identifier)
			var station_point: Vector3 = storage.anchor(category)
			var screen := _project(station_point)
			check(not garage.stage.camera.is_position_behind(station_point) and Rect2(Vector2.ZERO, garage.stage.size).has_point(screen), "world station label is on screen: " + category + " " + str(dimensions))
			var bounds: AABB = storage.bounds(category)
			# The robot deliberately occludes the rear rack; select an exposed
			# portion instead of expecting a ray through the chassis to hit it.
			var pickable: bool = storage.pick(screen) == category
			for corner in 8:
				pickable = pickable or storage.pick(_project(bounds.get_endpoint(corner).lerp(bounds.get_center(), 0.15))) == category
			check(pickable, "exposed 3D rack can be picked at " + str(dimensions) + ": " + category)
			if not pickable:
				print("STATION PICK HUB FAIL ", category, " camera=", garage.stage.camera.global_transform, " anchor-screen=", screen, " returned=", storage.pick(screen))
			await _click(button.get_global_rect().get_center())
			garage.focus.set_process(false)
			garage.focus.advance(1.1)
			check(garage._category == category and garage._module_panel.visible, "actual GUI station opens the matching submenu: " + category)
			for choice in catalog:
				var option: Button = garage._choices[category][choice]
				check(option.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(option.get_global_rect()), "every catalog choice remains visible, including the final passive: " + choice + " " + str(dimensions))
				check(option.get_global_rect().end.y <= garage.equip_button.get_global_rect().position.y - 2.0, "catalog choice leaves the Equip action clear: " + choice + " " + str(dimensions))
			var focused_pick: String = storage.pick(_project(bounds.get_center()))
			check(focused_pick == category, "focused rack center picks the matching category: " + category)
			if focused_pick != category:
				print("STATION PICK FOCUSED FAIL ", category, " camera=", garage.stage.camera.global_transform, " returned=", focused_pick)
			var rect: Rect2 = garage.focus.frame_rect().grow(3.0)
			var fits := true
			for corner in 8:
				var world_point: Vector3 = bounds.get_endpoint(corner)
				fits = fits and not garage.stage.camera.is_position_behind(world_point) and rect.has_point(_project(world_point))
			check(fits, "station is framed between the catalog panels: " + category + " " + str(dimensions))
			var card: Button = garage._choices[category][identifier]
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(card.get_global_rect()), "module card remains accessible: " + identifier + " " + str(dimensions))
			var before: Dictionary = garage.loadout.duplicate(true)
			var previous_preview: String = garage._preview_id
			await _hover(card.get_global_rect().get_center())
			check(garage._preview_id == previous_preview and garage.loadout == before, "hover cannot change selected equipment: " + category + " " + str(dimensions))
			await _click(card.get_global_rect().get_center())
			check(garage.loadout == before and not garage.module_installation.active, "actual card click previews without equipping: " + identifier)
			check(garage._preview_id == identifier and garage._preview_category == category, "card click deliberately selects equipment for the Equip action: " + identifier)
			var other: Button = garage._choices[category][str(before[category])]
			await _hover(other.get_global_rect().get_center())
			check(garage._preview_id == identifier and garage.loadout == before, "hovering another card cannot steal the clicked selection: " + identifier)
			var equip: Button = garage.equip_button
			check(equip.is_visible_in_tree() and not equip.disabled and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(equip.get_global_rect()), "Equip button is actionable at " + str(dimensions))
			await _click(equip.get_global_rect().get_center())
			garage.module_installation.set_process(false)
			check(garage.module_installation.active and garage.loadout == before and not garage._ui.visible, "actual Equip click begins the cinematic: " + identifier)
			garage.module_installation.finish_now()
			check(str(garage.loadout[category]) == identifier and garage._ui.visible, "cinematic commits the GUI-selected module: " + identifier)
			await process_frame
			_pause_controllers()
		garage._open_modules("mobility")
		garage.focus.advance(1.1)
		var before_direct: Dictionary = garage.loadout.duplicate(true)
		await _click((garage._choices.mobility.permutation as Button).get_global_rect().get_center())
		check(garage.loadout == before_direct and garage._preview_id == "permutation", "generic catalog card is also a deliberate preview: " + str(dimensions))
		await _click(garage.equip_button.get_global_rect().get_center())
		check(not garage.module_installation.active and str(garage.loadout.mobility) == "permutation" and garage._ui.visible, "generic Equip applies directly without fictional transport: " + str(dimensions))
		_check_no_placeholders("generic GUI " + str(dimensions))


func _save_and_test() -> void:
	var expected: Dictionary = garage.loadout.duplicate(true)
	garage.build_name = "STATIONS TEST"
	garage._save_build()
	garage.installation.set_process(false)
	check(garage.installation.active and not garage.module_installation.active, "save animation has sole ownership of the service arm")
	for frame in 360:
		garage.installation.advance(STEP)
		if not garage.installation.active:
			break
	check(saved.size() == 1 and LOADOUT.load_local(temporary_paths[1]) == expected, "complete installed build saved only to isolated temporary file")
	var reloaded: Dictionary = LIBRARY.load_local(temporary_paths[0], temporary_paths[1])
	check(reloaded.builds.any(func(entry: Dictionary): return entry.name == "STATIONS TEST" and entry.loadout == expected), "named installed build reloads with all module slots")
	var saved_bytes := _bytes(temporary_paths[0])
	garage._test_build()
	check(tested.size() == 1 and tested[0] == expected, "test action receives the fully installed draft")
	check(_bytes(temporary_paths[0]) == saved_bytes and not garage.stage.arm.active, "test action does not rewrite saved builds or keep arm ownership")
	await process_frame
	_pause_controllers()


func _double_click_equip() -> void:
	root.size = Vector2i(1280, 720)
	for frame in 3:
		await process_frame
	for category in ["mobility", "weapon"]:
		var identifier := "bio_injector" if category == "mobility" else "blaster"
		var draft: Dictionary = garage.loadout.duplicate(true)
		draft[category] = "permutation" if category == "mobility" else "shotgun"
		garage.set_loadout(draft)
		_open_station(category)
		garage.focus.advance(1.1)
		var card: Button = garage._choices[category][identifier]
		await _click(card.get_global_rect().get_center())
		check(garage.loadout == draft and not garage.module_installation.active, "first click remains a preview before double click: " + identifier)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = card.get_global_rect().get_center()
			event.global_position = event.position
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.double_click = pressed
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			root.push_input(event, true)
			await process_frame
		garage.module_installation.set_process(false)
		check(garage.module_installation.active and garage.loadout == draft, "actual double click starts the selected real equipment transfer: " + identifier)
		var count := mounted.size()
		garage.module_installation.finish_now()
		check(str(garage.loadout[category]) == identifier and mounted.size() == count + 1, "double click commits the chosen equipment only once: " + identifier)
		await process_frame
		_pause_controllers()


func _native_runtime() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	garage.stage.set_process(true)
	garage.focus.set_process(true)
	var native_categories := ["weapon"] if "--weapon-only" in OS.get_cmdline_user_args() else ["mobility", "weapon"]
	for category in native_categories:
		var identifier := "bio_injector" if category == "mobility" else "longshot"
		var alternative := "permutation" if category == "mobility" else "blaster"
		var draft: Dictionary = garage.loadout.duplicate(true)
		draft[category] = alternative
		garage.set_loadout(draft)
		garage._show_garage(false)
		for frame in 3:
			await process_frame
		await _click((garage.station_buttons[category] as Button).get_global_rect().get_center())
		await create_timer(1.1).timeout
		check(garage._category == category and garage._module_panel.visible, "native GUI button opens matching equipment rack: " + category)
		await _click((garage._choices[category][identifier] as Button).get_global_rect().get_center())
		check(garage.loadout == draft and not garage.module_installation.active, "native GUI equipment card only previews its choice: " + identifier)
		await _hover((garage._choices[category][alternative] as Button).get_global_rect().get_center())
		check(garage._preview_id == identifier and garage.loadout == draft, "native hover preserves the clicked equipment choice: " + identifier)
		await _click((garage.equip_button as Button).get_global_rect().get_center())
		check(garage.module_installation.active and not garage._ui.visible, "native GUI Equip starts real physical installation: " + identifier)
		var start := Time.get_ticks_msec()
		var completed_before := completed.size()
		while garage.module_installation.active and Time.get_ticks_msec() - start < 15000:
			await process_frame
		check(not garage.module_installation.active and completed.size() == completed_before + 1 and str(garage.loadout[category]) == identifier, "native engine frames complete the physical installation: " + identifier)
		check(not garage.stage.arm.active and garage._ui.visible and garage._category == category, "native completion releases arm and restores the same rack: " + identifier)
		_check_no_placeholders("native " + identifier)
		print("STATION NATIVE ", identifier, " elapsed=", (Time.get_ticks_msec() - start) / 1000.0)
	_pause_controllers()


func _project(point: Vector3) -> Vector2:
	return garage.stage.camera.unproject_position(point) * garage.stage.size / Vector2(garage.stage.viewport.size)


func _storage_item(identifier: String) -> Node3D:
	var item: Variant = _storage(identifier).items[identifier]
	return item if item is Node3D else item.get("node", item.get("root", null))


func _storage(identifier: String):
	return garage.stage.weapon_rack if identifier in LOADOUT.WEAPONS else garage.stage.module_stations


func _open_station(category: String) -> void:
	if category == "weapon":
		garage._open_weapon_rack()
	else:
		garage._open_modules(category)


func _same_mesh_resources(first: Node3D, second: Node3D) -> bool:
	var original: Array[Node] = first.find_children("*", "MeshInstance3D", true, false)
	var copied: Array[Node] = second.find_children("*", "MeshInstance3D", true, false)
	if original.is_empty() or original.size() != copied.size():
		return false
	for index in original.size():
		if (original[index] as MeshInstance3D).mesh != (copied[index] as MeshInstance3D).mesh:
			return false
	return true


func _check_no_placeholders(label: String) -> void:
	check(garage.stage.skeleton.find_children("GarageInstalled_*", "BoneAttachment3D", true, false).is_empty(), "robot has no generic cartridge attachments: " + label)
	check(garage.module_installation._installed.is_empty(), "installer retains no substitute geometry on robot: " + label)
	for key in garage.stage.module_visuals.mounts:
		var id: String = garage.stage.module_visuals.MOUNT_IDS[key]
		var category: String = garage.stage.module_visuals.MODEL_CATEGORIES[id]
		check((garage.stage.module_visuals.mounts[key] as Node3D).visible == (str(garage.loadout[category]) == id), "robot shows only its actual selected module mesh: " + label + " " + key)


func _payload() -> Node3D:
	return garage.module_installation.get("_payload") as Node3D


func _joint_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for label in ["BaseYaw", "Shoulder", "Elbow", "Wrist"]:
		var joint := garage.stage.arm.model.find_child(label, true, false) as Node3D
		result.append(joint.transform)
	return result


func _same_joint_transforms(expected: Array[Transform3D]) -> bool:
	var actual := _joint_transforms()
	for index in expected.size():
		if not actual[index].is_equal_approx(expected[index]):
			return false
	return true


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _hover(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	for frame in 2:
		await process_frame


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


func _restore(path: String, backup: Dictionary) -> void:
	if not backup.existed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(backup.bytes)
		file.close()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition and not failures.has(label):
		failures.append(label)
