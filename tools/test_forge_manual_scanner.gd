extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
# Developer-only fixture: the released Garage has no manual Scanner command.
class ManualScannerFixture extends "res://scripts/forge_garage.gd":
	var scanner_interface: Control

	func _ready() -> void:
		super._ready()
		scanner_interface = load("res://scripts/forge_manual_scanner_ui.gd").new()
		scanner_interface.configure(self)
		add_child(scanner_interface)

	func _gui_input(event: InputEvent) -> void:
		if scanner_interface != null and scanner_interface.handle_event(event):
			accept_event()
			return
		super._gui_input(event)

var garage
var scanner
var ui
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var existed := FileAccess.file_exists(LOADOUT.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH) if existed else PackedByteArray()
	garage = ManualScannerFixture.new()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	ui = garage.scanner_interface
	scanner = ui.scanner
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	ui.set_process(false)
	var initial: Dictionary = garage.loadout.duplicate(true)
	check(not scanner.enabled and not scanner._motor.playing, "inspection inactive a l'entree")
	check(ui.button.get_rect().end.x < 500 and ui.button.get_rect().end.y < 100, "commande hors des panneaux d'equipement et de demo")
	garage.stage.arm.cancel_service()
	check(garage.stage.inspect_robot(), "cycle Blender disponible avant le scanner")
	garage.stage.arm.advance_service(4.5)
	enter_mode()
	check(garage.stage.arm.manual_control and garage.stage.arm.active, "le controle manuel possede les articulations")
	check(not garage.stage.arm.particles.emitting, "les etincelles du cycle automatique restent eteintes")
	var rest_tip: Vector3 = garage.stage.arm.contact.global_position
	garage.stage.arm.advance_service(3.0)
	check(garage.stage.arm.contact.global_position.is_equal_approx(rest_tip), "la lecture automatique ne reprend pas les articulations")
	check(scanner.joint_positions(scanner._rest)[3].distance_to(rest_tip) < 0.001, "cinematique conforme aux pivots du GLB")
	for identifier in LOADOUT.ROBOTS:
		ui.stop()
		var selected: Dictionary = initial.duplicate(true)
		selected.robot = identifier
		garage.set_loadout(selected)
		enter_mode()
		for zone_index in [0, 1]:
			var pointer := zone_point(zone_index)
			scanner.point_at(pointer, true)
			check(scanner.target_valid, "zone accessible : %s / %d" % [identifier, zone_index])
			var start_tip: Vector3 = garage.stage.arm.contact.global_position
			var safe := true
			var speed_limited := true
			for frame in 180:
				var previous: Vector4 = scanner._command
				scanner.advance(1.0 / 60.0)
				safe = safe and scanner.pose_is_clear(scanner._command)
				for joint in 4:
					speed_limited = speed_limited and absf(angle_difference(previous[joint], scanner._command[joint])) <= scanner.SPEEDS[joint] / 60.0 + 0.0001
			check(safe and speed_limited, "trajectoire sans penetration et vitesse bornee : %s / %d" % [identifier, zone_index])
			check(scanner.scanning and scanner._beam.visible and scanner._lamp.visible, "balayage apres approche : %s / %d" % [identifier, zone_index])
			check(garage.stage.arm.contact.global_position.distance_to(scanner.tool_target) < 0.015, "l'outil reel rejoint sa cible : %s / %d" % [identifier, zone_index])
			check(start_tip.distance_to(garage.stage.arm.contact.global_position) > 0.3, "deplacement reel de l'outil : %s / %d" % [identifier, zone_index])
			check(scanner._motor.playing and scanner._motor.bus == &"Effects", "servo respecte le bus des effets")
			scanner.retract()
			check(not scanner.scanning and not scanner._beam.visible and not scanner._motor.playing, "relachement coupe immediatement le scan et le son")
			step(180)
			check(garage.stage.arm.contact.global_position.distance_to(rest_tip) < 0.01, "retour articule au repos : " + identifier)
		scanner.point_at(zone_point(2), true)
		step(20)
		check(not scanner.target_valid and not scanner.scanning and scanner.rejection == "BRAS HORS PORTÉE", "epaule eloignee refusee : " + identifier)
		for pointer in [Vector2(20, 20), Vector2(-15, 220), Vector2(640, 550), Vector2(640, 145)]:
			scanner.point_at(pointer, true)
			step(2)
			check(not scanner.target_valid and not scanner._beam.visible, "fond, jambes et tete exclus : " + identifier)
		var zones_reachable := 0
		var sweep_safe := true
		for offset in [Vector2(-18, 18), Vector2(12, 12), Vector2(24, -6), Vector2(2, -15), Vector2(0, 18)]:
			scanner.point_at(zone_point(0) + offset, false)
			if scanner.target_valid:
				zones_reachable += 1
				step(90)
				sweep_safe = sweep_safe and scanner.pose_is_clear(scanner._command)
		check(zones_reachable >= 3 and sweep_safe, "suivi de plusieurs points du torse : " + identifier)
		scanner.retract()
		step(180)
	ui.stop()
	garage.set_loadout(initial)
	enter_mode()
	var pointer := zone_point(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = pointer
	garage._gui_input(click)
	check(scanner.held and not garage._rotating_robot and not garage.stage._rotating_robot, "clic scanner distinct du glissement de rotation")
	step(180)
	check(scanner.scanning, "maintien du clic lance le balayage")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = Vector2(1100, 650)
	ui._input(release)
	check(not scanner.held and not scanner._has_pointer, "relachement sur JOUER remet le bras au repos")
	step(180)
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = true
	touch.position = pointer
	garage._gui_input(touch)
	step(180)
	check(scanner.scanning and ui._touch_index == 3, "toucher maintenu utilisable")
	var other_touch := InputEventScreenTouch.new()
	other_touch.index = 4
	other_touch.pressed = true
	other_touch.position = zone_point(1)
	garage._gui_input(other_touch)
	check(ui._touch_index == 3 and scanner._pointer == pointer, "un deuxieme doigt ne vole pas le bras")
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = zone_point(1)
	garage._gui_input(drag)
	step(180)
	check(scanner.target_zone == "ÉPAULE" and scanner.scanning, "le doigt guide l'outil vers l'epaule")
	var canceled := InputEventScreenTouch.new()
	canceled.index = 3
	canceled.canceled = true
	ui._input(canceled)
	check(ui._touch_index == -1 and not scanner._has_pointer and not scanner._beam.visible, "annulation tactile sure")
	click.device = -1
	garage._gui_input(click)
	check(not scanner._has_pointer, "la souris emulee ne relance pas le scan tactile")
	ui._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not scanner.enabled and not garage.stage.arm.active and not scanner._motor.playing, "perte de focus arrete le scanner")
	garage.stage.rotate_robot(0.55)
	var saved_yaw: float = garage.stage.robot.rotation.y
	enter_mode()
	check(is_equal_approx(garage.stage.robot.rotation.y, garage.stage.ROBOT_YAW), "robot oriente pour la zone atteignable")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ui._input(escape)
	check(not scanner.enabled and is_equal_approx(garage.stage.robot.rotation.y, saved_yaw), "Echap quitte le scanner et conserve la rotation precedente")
	garage.stage.robot.rotation.y = garage.stage.ROBOT_YAW
	enter_mode()
	ui.stop()
	garage._module_panel.show()
	garage._open_modules("mobility")
	garage.focus.advance(0.7)
	check(not scanner.enabled and garage._category == "mobility" and garage._module_panel.visible, "les modules retrouvent leur catalogue")
	enter_mode()
	check(not garage._module_panel.visible and garage.focus.zone == "robot", "le scanner retrouve la vue de travail")
	ui.stop()
	(garage.weapon_buttons["longshot"] as Button).pressed.emit()
	garage.focus.advance(0.7)
	check(not scanner.enabled and garage.stage.weapon_id == "longshot" and garage.focus.zone == "robot", "choix d'arme conserve le robot entier")
	check(garage._training_demo.equipment_id == "longshot", "demo de combat preservee")
	enter_mode()
	garage.stage.set_equipment_focus(true)
	check(not scanner.enabled and not scanner._motor.playing, "une inspection externe libere le bras manuel")
	for dimensions in [Vector2i(800, 600), Vector2i(2340, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		await process_frame
		await process_frame
		ui.set_process(false)
		enter_mode()
		scanner.point_at(zone_point(0), true)
		step(180)
		check(scanner.scanning, "coordonnees du scanner adaptees : " + str(dimensions))
		ui.stop()
	enter_mode()
	scanner.point_at(zone_point(0), true)
	step(180)
	garage.hide()
	check(not scanner.enabled and not scanner.is_processing() and not scanner._lamp.visible and not scanner._motor.playing, "sortie du garage sans lumiere ni son ni traitement")
	garage.show()
	check(not scanner.enabled, "reouverture sans geste manuel fantome")
	garage.stage.arm.cancel_service()
	check(garage.stage.inspect_robot(), "cycle Blender disponible apres le scanner")
	garage.stage.arm.advance_service(4.2)
	check(garage.stage.arm.particles.emitting, "effets du cycle automatique toujours synchronises")
	garage.stage.arm.cancel_service()
	await check_routed_input()
	check(FileAccess.file_exists(LOADOUT.SAVE_PATH) == existed and (not existed or FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH) == saved), "inspection sans ecriture de l'equipement sauvegarde")
	garage.queue_free()
	for frame in 8:
		await process_frame
	if failures.is_empty():
		print("FORGE MANUAL SCANNER TEST: PASS (", checks, " checks)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FORGE MANUAL SCANNER TEST: FAIL (", failures.size(), ")")
		quit(1)


func enter_mode() -> void:
	if not scanner.enabled:
		ui.button.pressed.emit()
	scanner.set_process(false)


func check_routed_input() -> void:
	var back_count := [0]
	garage.back_requested.connect(func() -> void: back_count[0] += 1)
	enter_mode()
	ui.set_process(true)
	var pointer := zone_point(0)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	motion.global_position = pointer
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = pointer
	click.global_position = pointer
	Input.parse_input_event(click)
	await process_frame
	check(scanner.held and scanner._has_pointer and not garage._rotating_robot, "routage reel du clic par le viewport")
	check(root.gui_get_hovered_control() == garage, "les controles decoratifs ne bloquent pas le pointeur")
	for frame in 210:
		garage.stage._advance_robot_animation(1.0 / 60.0)
		scanner.advance(1.0 / 60.0)
	check(scanner.scanning and scanner.pose_is_clear(scanner._command), "suivi pendant l'animation idle du vrai robot")
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame
	check(not scanner.held and not scanner._beam.visible, "routage reel du relachement")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(not scanner.enabled and back_count[0] == 0 and garage.visible, "Echap quitte le scanner avant le garage via le viewport")
	ui.set_process(false)


func zone_point(index: int) -> Vector2:
	scanner._update_zones()
	var point: Vector2 = garage.stage.camera.unproject_position(scanner._zones[index].center)
	return point * garage.stage.size / Vector2(garage.stage.viewport.size)


func step(frames: int) -> void:
	for frame in frames:
		scanner.advance(1.0 / 60.0)


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
