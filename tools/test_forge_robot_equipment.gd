extends SceneTree

const GARAGE := preload("res://scripts/forge_garage.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var garage
var failures: Array[String] = []
var checks := 0
var installations := 0
var mounted_signals := 0
var paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	paths = ["user://robot-equipment-test-" + suffix + ".cfg", "user://robot-equipment-test-legacy-" + suffix + ".cfg"]
	garage.library_path = paths[0]
	garage.legacy_save_path = paths[1]
	root.add_child(garage)
	await process_frame
	_pause()
	garage.equipment_selected.connect(func(_kind, _id): mounted_signals += 1)
	_check(garage._view == "entry", "entry still offers edit and creation")
	await _click(garage._entry_choices["MODIFIER UN BUILD"])
	garage.focus.advance(1.0)
	_pause()
	_check(garage._view == "hub", "real edit click opens the robot")
	_check(not garage.stage.module_stations.is_visible_in_tree() and not garage.stage.weapon_rack.is_visible_in_tree(), "all physical shelves are hidden")
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(844, 390)]:
		root.size = dimensions
		await process_frame
		await process_frame
		for chassis in LOADOUT.ROBOTS:
			var equipment: Dictionary = LOADOUT.defaults()
			equipment.robot = chassis
			garage.set_loadout(equipment)
			garage._show_garage(false)
			garage.focus.advance(0.0)
			_pause()
			var screen := _robot_rect()
			_check(screen.size.y > dimensions.y * 0.42 and screen.size.y < dimensions.y * 0.94, "large complete robot: %s %s %s" % [dimensions, chassis, screen])
			for kind in garage.BUILD_STEPS:
				var pin: Button = garage.robot_equipment.pins[kind]
				_check(pin.is_visible_in_tree(), "mount is visible: " + kind)
				_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(pin.get_global_rect()), "mount stays within window: %s %s" % [dimensions, kind])
	garage.set_loadout(LOADOUT.defaults())
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	garage._show_garage(false)
	_pause()
	var mount_point: Vector2 = garage._ui.position + garage.robot_equipment._anchors.defensive * garage._ui.scale
	await _click_point(mount_point)
	_check(garage._category == "defensive" and garage._view == "catalog", "body marker itself opens its equipment category")
	await _click(garage.robot_equipment.pins.offensive)
	_check(garage._category == "offensive" and garage.focus.zone == "garage", "body pin keeps the camera on the robot")
	var before: Dictionary = garage.loadout.duplicate(true)
	await _click(garage.robot_equipment.choices.offensive.fulguro_punch)
	_check(garage._preview_id == "fulguro_punch", "real fan click selects the requested piece")
	_check(garage.loadout == before and garage.stage.module_visuals.equipment_ids.offensive == "fulguro_punch", "preview changes only the visible robot")
	_check(garage._detail_description.get_parent().size.x < garage._detail_panel.size.x, "description stays inside its panel")
	_check(garage.robot_equipment._summary.visible and not garage._detail_description.get_parent().visible, "equipment opens with a short summary")
	await _click(garage.robot_equipment._details_button)
	_check(garage._detail_description.get_parent().visible and garage._demo_button.visible, "details reveal the complete description and demonstration")
	await _click(garage.robot_equipment._details_button)
	_check(garage.robot_equipment._summary.visible and not garage._demo_button.visible, "details close back into the compact card")
	await _click(garage.equip_button)
	_pause()
	_check(garage.module_installation.active, "real install click starts physical mounting")
	garage.module_installation.advance(1.0)
	_check(garage.module_installation.reached_module, "cancel sample has physically picked the piece up")
	garage.module_installation.cancel()
	_check(garage.loadout == before and garage.stage.module_visuals.equipment_ids.offensive == before.offensive, "cancelling before contact restores preview and draft")
	_check(garage.module_installation._payload == null, "cancel releases the carried piece")
	for chassis in LOADOUT.ROBOTS:
		for kind in garage.BUILD_STEPS:
			var options: Array = garage._options(kind)
			for index in options.size():
				var identifier: String = options[index]
				var baseline: Dictionary = LOADOUT.defaults()
				baseline.robot = chassis
				baseline[kind] = options[(index + 1) % options.size()]
				garage.set_loadout(baseline)
				garage._show_garage(false)
				garage._open_station(kind)
				garage._preview_equipment(kind, identifier)
				garage._select_equipment(kind, identifier)
				_pause()
				var installer = garage.module_installation
				var label: String = str(chassis) + " / " + identifier
				_check(installer.active, "mount starts: " + label)
				var camera: Transform3D = garage.stage.camera.global_transform
				var signal_before := mounted_signals
				var screen_source: Vector2 = garage.stage.camera.unproject_position(installer._source.origin)
				_check(screen_source.x > garage.stage.viewport.size.x, "pickup is outside the view: " + label)
				var same_camera := true
				for frame in 125:
					if not installer.active:
						break
					installer.advance(1.0 / 30.0)
					if installer.active:
						same_camera = same_camera and garage.stage.camera.global_transform.is_equal_approx(camera)
				_check(not installer.active and installer.mounted_module, "physical contact completes: " + label)
				_check(garage.loadout[kind] == identifier and mounted_signals == signal_before + 1, "draft changes once at contact: " + label)
				_check(same_camera, "camera stays with robot: " + label)
				_check(garage.stage._mount_pose_bones.is_empty() and not garage.stage.arm.manual_control, "pose and arm restored: " + label)
				_check(not FileAccess.file_exists(paths[0]), "mounting does not save to disk: " + label)
				installations += 1
	var target: String = "shotgun" if garage.loadout.weapon != "shotgun" else "blaster"
	garage._open_station("weapon")
	garage._preview_equipment("weapon", target)
	garage._equip_preview()
	garage.module_installation.advance(1.0)
	garage.module_installation.finish_now()
	_check(not garage.module_installation.active and garage.loadout.weapon == target, "accelerating finishes the same mounting path")
	garage._show_entry(false)
	await _click(garage._entry_choices["CRÉER UN BUILD"])
	_check(garage._creating and garage._journey_step == 0, "creation starts with the weapon")
	garage._open_station("passive")
	_check(garage._category == "weapon", "creation keeps the required order")
	for kind in garage.BUILD_STEPS:
		_check(garage._category == kind, "guided category: " + kind)
		garage._preview_equipment(kind, str(garage.loadout[kind]))
		garage._equip_preview()
	_check(garage._view == "summary" and garage._journey_step == 5, "validating equipped pieces completes creation")
	var tested: Array[Dictionary] = []
	garage.test_requested.connect(func(value: Dictionary): tested.append(value))
	garage._test_build()
	_check(tested.size() == 1 and tested[0] == garage.loadout, "test transmits the current draft")
	garage._save_build()
	garage.installation.advance(garage.installation.DURATION)
	_check(FileAccess.file_exists(paths[0]) and not garage.is_dirty(), "save persists this isolated build")
	_check(garage._view == "hub", "save returns to the robot")
	for pin: Button in garage.robot_equipment.pins.values():
		pin.release_focus()
	var leave := InputEventMouseMotion.new()
	leave.position = Vector2.ZERO
	root.push_input(leave, true)
	garage.robot_equipment._process(4.0)
	_check(garage.robot_equipment.pin_alpha == 0.0, "idle labels fade away")
	garage.robot_equipment.wake()
	garage.robot_equipment._process(1.0)
	_check(garage.robot_equipment.pin_alpha == 1.0, "activity reveals the labels again")
	garage._new_build()
	var draft: Dictionary = garage.draft_state()
	garage._show_entry(false)
	garage.restore_draft(draft)
	_check(garage._creating and garage._journey_step == 0 and garage._category == "weapon", "training return restores guided draft")
	garage.queue_free()
	await process_frame
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.35).timeout
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("FORGE ROBOT EQUIPMENT: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", installations, " installations, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)

func _robot_rect() -> Rect2:
	var bounds: AABB = garage.stage._robot_pick_bounds
	var screen := Rect2()
	for corner in 8:
		var world: Vector3 = garage.stage.robot.global_transform * bounds.get_endpoint(corner)
		var point: Vector2 = garage.stage.camera.unproject_position(world)
		screen = Rect2(point, Vector2.ZERO) if corner == 0 else screen.expand(point)
	return screen

func _pause() -> void:
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	garage.module_installation.set_process(false)
	garage.installation.set_process(false)
	garage.robot_equipment.set_process(false)
	garage.robot_equipment.pin_alpha = 1.0
	garage.robot_equipment._update_pins()

func _click(button: Control) -> void:
	_check(button.is_visible_in_tree(), "clicked control is visible: " + str(button.name))
	var point := button.get_global_rect().get_center()
	await _click_point(point)

func _click_point(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	_pause()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)
