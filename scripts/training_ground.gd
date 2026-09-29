extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const CAMERA_SCRIPT := preload("res://scripts/camera_rig.gd")
const DUMMY_SCRIPT := preload("res://scripts/training_dummy.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const TOUCH_SCRIPT := preload("res://scripts/touch_controls.gd")
const METER_SCRIPT := preload("res://scripts/training_meter.gd")
const VFX_MANAGER_SCRIPT := preload("res://scripts/vfx_manager.gd")
const SAND_TEXTURE: Texture2D = preload("res://art/sand_dust.svg")
const UI_FONT: FontFile = preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const SPELL_BAR_FRAME: Texture2D = preload("res://art/ui/spell-bar-frame.svg")
const JAVELIN_RECAST_ICON: Texture2D = preload("res://art/ui/icons/javelin-recast.svg")
const EQUIPMENT_ICONS := preload("res://scripts/equipment_icons.gd")
const COOLDOWN_RING := preload("res://scripts/cooldown_ring.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const HUD_CONTROLLER := preload("res://scripts/hud_layout_controller.gd")
const HUD_EDITOR := preload("res://scripts/hud_editor.gd")
const HUD_VITALS_SCRIPT := preload("res://scripts/hud_vitals.gd")
var _equipment_icons = EQUIPMENT_ICONS.new()
const CREAM := Color("#f3ddbb")
const MUTED := Color("#bda995")
const CYAN := Color("#42d9e5")
const AMBER := Color("#efb765")

const MAX_FIXED_TARGETS := 12
const SIZE_VALUES := [0.65, 1.0, 1.5]
const MAP_HALF_WIDTH := 44.0
const MAP_HALF_DEPTH := 38.0

var player: CharacterBody3D
var _fixed_targets: Array[StaticBody3D] = []
var _moving_target: StaticBody3D
var _shooter_target: StaticBody3D
var _loadout: Dictionary
var _options := {"invulnerable": false, "instant_cooldowns": false, "unlimited_ammo": false}
var _menu: PanelContainer
var _menu_dim: ColorRect
var _menu_count: Label
var _status: Label
var _vitals: Control
var _tool_mode := ""
var _place_size_index := 1
var _preview: MeshInstance3D
var _touch_controls: Control
var _option_buttons: Dictionary = {}
var _size_buttons: Array[Button] = []
var _meter: Control
var _meter_toggle_button: Button
var _first_picker: OptionButton
var _fixed_serial := 0
var _placement_blockers: Array[Rect2] = []
var _spell_bar: Control
var _spell_labels: Dictionary = {}
var _menu_opened_at_msec := 0
var _ui_layer: CanvasLayer
var _hud_controller
var _hud_editor
var _editor_original_player: CharacterBody3D
var _editor_trial_player: CharacterBody3D
var _editor_trial_target: StaticBody3D
var _editor_test_modes: Dictionary = {}
var _editor_test_positions: Dictionary = {}
var _editor_test_fx_modes: Dictionary = {}
var _reset_button: Button
var _training_menu_button: Button

func _ready() -> void:
	# Input and menu remain available while combat actors are paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_loadout = LOADOUT.load_local()
	var vfx := VFX_MANAGER_SCRIPT.new()
	vfx.name = "VFXManager"
	add_child(vfx)
	_build_world()
	_build_player_and_camera()
	_spawn_dummy("fixed", Vector3(-33.0, 0.0, -11.0), 0.65)
	_spawn_dummy("fixed", Vector3(-24.0, 0.0, -11.0), 1.0)
	_spawn_dummy("fixed", Vector3(-15.0, 0.0, -11.0), 1.5)
	_moving_target = _spawn_dummy("moving", Vector3(0.0, 0.0, -23.0), 1.0)
	_shooter_target = _spawn_dummy("shooter", Vector3(24.0, 0.0, -11.0), 1.0)
	_build_ui()
	_setup_hud_editor()
	_apply_loadout()
	_apply_options()
	_update_status()

func _process(_delta: float) -> void:
	if _spell_bar != null and player != null and not _menu.visible:
		_update_spell_bar()

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#171e24")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a9bdc3")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -30.0, 0.0)
	sun.light_color = Color("#fff0cd")
	sun.light_energy = 1.15
	add_child(sun)
	_make_box("TrainingFloor", Vector3(0.0, -0.3, 0.0), Vector3(88.0, 0.6, 76.0), Color("#4b453e"), true)
	(get_node("TrainingFloor") as StaticBody3D).collision_layer = 5 # Ground rays use layer 4; obstacles stay on layer 1.
	var ground_mesh := get_node("TrainingFloor/Visual") as MeshInstance3D
	var ground_material := ground_mesh.material_override as StandardMaterial3D
	ground_material.albedo_color = Color("#aaa4a0")
	ground_material.albedo_texture = SAND_TEXTURE
	ground_material.uv1_scale = Vector3(7.0, 7.0, 7.0)
	for index in range(-5, 6):
		_make_box("GroundSeamX%d" % index, Vector3(float(index) * 8.0, 0.008, 0.0), Vector3(0.025, 0.012, 75.0), Color("#655d53"), false)
	for index in range(-4, 5):
		_make_box("GroundSeamZ%d" % index, Vector3(0.0, 0.009, float(index) * 8.0), Vector3(87.0, 0.012, 0.025), Color("#655d53"), false)
	_make_zone("SpawnZone", Vector3(0.0, 0.0, 25.0), Vector2(25.0, 18.0), Color("#626963"), Color("#b7c9bf"), "ACCUEIL")
	_make_zone("PlacementZone", Vector3(0.0, 0.0, 5.0), Vector2(18.0, 19.0), Color("#5b625e"), Color("#a7dbc8"), "PLACEMENT LIBRE")
	_make_zone("FixedZone", Vector3(-24.0, 0.0, -5.0), Vector2(34.0, 30.0), Color("#515f66"), Color("#82c6d1"), "CIBLES FIXES")
	_make_zone("MovingZone", Vector3(0.0, 0.0, -22.0), Vector2(20.0, 25.0), Color("#4b625f"), Color("#7fd7bc"), "CIBLE MOBILE")
	_make_zone("ShooterZone", Vector3(24.0, 0.0, -5.0), Vector2(34.0, 30.0), Color("#665248"), Color("#efa66d"), "TIR RECU")
	_make_box("HubWalkway", Vector3(0.0, 0.027, 15.25), Vector3(8.0, 0.026, 3.2), Color("#71847d"), false)
	_make_box("TrackingWalkway", Vector3(0.0, 0.027, -6.5), Vector3(8.0, 0.026, 7.0), Color("#617f75"), false)
	_make_ground_label("FixedDirection", "<  FIXES", Vector3(-7.6, 0.075, 19.0), Color("#d8e9e8"), 45)
	_make_ground_label("MovingDirection", "^  MOBILE", Vector3(0.0, 0.075, 19.0), Color("#d6eee0"), 45)
	_make_ground_label("ShooterDirection", "TIR  >", Vector3(7.6, 0.075, 19.0), Color("#f6d5ae"), 45)
	# Three open firing lanes, a marked tracking rail, and a sheltered shooting bay.
	for index in range(3):
		var lane_x := -33.0 + float(index) * 9.0
		_make_box("FixedLane%d" % index, Vector3(lane_x, 0.035, -11.0), Vector3(7.5, 0.025, 17.0), Color("#596f78"), false)
		_make_box("FixedTargetPad%d" % index, Vector3(lane_x, 0.060, -11.0), Vector3(3.2, 0.035, 3.2), Color("#7eaaa9"), false)
		_make_ground_label("FixedSize%d" % index, ["PETIT", "MOYEN", "GRAND"][index], Vector3(lane_x, 0.075, -17.0), Color("#d3e6e5"), 38)
	for divider_x in [-28.5, -19.5]:
		_make_rail("FixedDivider%d" % int(divider_x + 30.0), Vector3(divider_x, 0.42, -12.0), Vector3(0.45, 0.84, 16.0), Color("#343e43"))
	_make_box("MovingTrack", Vector3(0.0, 0.045, -23.0), Vector3(12.0, 0.03, 3.4), Color("#688d82"), false)
	for marker_x in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		_make_box("TrackMarker%d" % int(marker_x + 6.0), Vector3(marker_x, 0.065, -23.0), Vector3(0.15, 0.02, 4.2), Color("#b0d8c8"), false)
	_make_box("ShooterPad", Vector3(24.0, 0.04, -11.0), Vector3(5.0, 0.035, 5.0), Color("#ac775a"), false)
	_make_rail("FixedWestEntry", Vector3(-7.0, 0.42, -14.5), Vector3(0.45, 0.84, 11.0), Color("#35454b"))
	_make_rail("FixedEastEntry", Vector3(-7.0, 0.42, 7.5), Vector3(0.45, 0.84, 9.0), Color("#35454b"))
	_make_rail("ShooterWestEntry", Vector3(7.0, 0.42, -14.5), Vector3(0.45, 0.84, 11.0), Color("#554039"))
	_make_rail("ShooterEastEntry", Vector3(7.0, 0.42, 7.5), Vector3(0.45, 0.84, 9.0), Color("#554039"))
	_make_rail("MovingLeftEntry", Vector3(-7.0, 0.42, -9.5), Vector3(6.0, 0.84, 0.45), Color("#354d48"))
	_make_rail("MovingRightEntry", Vector3(7.0, 0.42, -9.5), Vector3(6.0, 0.84, 0.45), Color("#354d48"))
	_make_beacon("FixedBeacon", Vector3(-10.2, 0.0, 8.0), Color("#85d3dc"))
	_make_beacon("MovingBeacon", Vector3(0.0, 0.0, -7.2), Color("#8bdcba"))
	_make_beacon("ShooterBeacon", Vector3(10.2, 0.0, 8.0), Color("#ffc28c"))
	_make_crate("FixedCrates", Vector3(-38.0, 0.0, 7.0), Color("#755c46"))
	_make_crate("MovingCrates", Vector3(8.0, 0.0, -30.0), Color("#665f4f"))
	_make_crate("ShooterCrates", Vector3(38.0, 0.0, 7.0), Color("#755344"))
	_make_crate("ShooterCoverLeft", Vector3(16.0, 0.0, -2.0), Color("#76564a"))
	_make_crate("ShooterCoverRight", Vector3(32.0, 0.0, -2.0), Color("#76564a"))
	_make_box("NorthWall", Vector3(0, 1.1, -MAP_HALF_DEPTH), Vector3(88, 2.2, 0.6), Color("#715544"), true)
	_make_box("SouthWall", Vector3(0, 1.1, MAP_HALF_DEPTH), Vector3(88, 2.2, 0.6), Color("#715544"), true)
	_make_box("WestWall", Vector3(-MAP_HALF_WIDTH, 1.1, 0), Vector3(0.6, 2.2, 76), Color("#715544"), true)
	_make_box("EastWall", Vector3(MAP_HALF_WIDTH, 1.1, 0), Vector3(0.6, 2.2, 76), Color("#715544"), true)

func _make_zone(node_name: String, center: Vector3, footprint: Vector2, fill: Color, accent: Color, title: String) -> void:
	_make_box(node_name, center + Vector3(0.0, 0.018, 0.0), Vector3(footprint.x, 0.025, footprint.y), fill, false)
	var edge_x := footprint.x * 0.5
	var edge_z := footprint.y * 0.5
	_make_box(node_name + "NorthLine", center + Vector3(0.0, 0.04, -edge_z), Vector3(footprint.x, 0.025, 0.16), accent, false)
	_make_box(node_name + "SouthLine", center + Vector3(0.0, 0.04, edge_z), Vector3(footprint.x, 0.025, 0.16), accent, false)
	_make_box(node_name + "WestLine", center + Vector3(-edge_x, 0.04, 0.0), Vector3(0.16, 0.025, footprint.y), accent, false)
	_make_box(node_name + "EastLine", center + Vector3(edge_x, 0.04, 0.0), Vector3(0.16, 0.025, footprint.y), accent, false)
	_make_ground_label(node_name + "Label", title, center + Vector3(0.0, 0.078, edge_z - 2.2), accent, 53)

func _make_ground_label(node_name: String, value: String, at: Vector3, color: Color, font_size: int) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = value
	label.font_size = font_size
	label.pixel_size = 0.013
	label.modulate = color
	label.position = at
	label.rotation_degrees.x = -90.0
	add_child(label)

func _make_rail(node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	_make_box(node_name, at, size, color, true)
	_placement_blockers.append(Rect2(Vector2(at.x - size.x * 0.5, at.z - size.z * 0.5), Vector2(size.x, size.z)))
	_make_box(node_name + "Cap", at + Vector3(0.0, size.y * 0.5 + 0.035, 0.0), Vector3(size.x + 0.08, 0.07, size.z + 0.08), Color("#b39a75"), false)

func _make_crate(node_name: String, at: Vector3, color: Color) -> void:
	var size := Vector3(2.1, 1.35, 2.1)
	_make_box(node_name, at + Vector3(0.0, size.y * 0.5, 0.0), size, color, true)
	_placement_blockers.append(Rect2(Vector2(at.x - size.x * 0.5, at.z - size.z * 0.5), Vector2(size.x, size.z)))
	_make_box(node_name + "BandX", at + Vector3(0.0, 1.37, 0.0), Vector3(2.25, 0.10, 0.24), Color("#3b3b37"), false)
	_make_box(node_name + "BandZ", at + Vector3(0.0, 1.38, 0.0), Vector3(0.24, 0.10, 2.25), Color("#3b3b37"), false)

func _make_beacon(node_name: String, at: Vector3, glow: Color) -> void:
	_make_rail(node_name + "Post", at + Vector3(0.0, 0.85, 0.0), Vector3(0.55, 1.7, 0.55), Color("#30373a"))
	var lamp := MeshInstance3D.new()
	lamp.name = node_name + "Lamp"
	var lamp_shape := CylinderMesh.new()
	lamp_shape.top_radius = 0.37
	lamp_shape.bottom_radius = 0.37
	lamp_shape.height = 0.22
	lamp.mesh = lamp_shape
	lamp.position = at + Vector3(0.0, 1.85, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = glow
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = 1.8
	lamp.material_override = material
	add_child(lamp)
	var light := OmniLight3D.new()
	light.name = node_name + "Light"
	light.position = lamp.position
	light.light_color = glow
	light.light_energy = 0.45
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)

func _make_box(node_name: String, at: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = node_name
	root.position = at
	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	root.add_child(mesh)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		body.add_child(collision)
	add_child(root)

func _build_player_and_camera() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(0.0, 0.0, 24.0)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.died.connect(_on_player_died)
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CAMERA_SCRIPT)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 25.5, 22.0)
	camera.fov = 44.0
	camera.current = true
	rig.add_child(camera)
	add_child(rig)
	rig.call("set_target", player)

func _spawn_dummy(kind: String, at: Vector3, size: float) -> StaticBody3D:
	var dummy := StaticBody3D.new()
	dummy.name = "Training_%s_%d" % [kind, get_child_count()]
	dummy.set_script(DUMMY_SCRIPT)
	dummy.set("training_kind", kind)
	dummy.set("training_size", size)
	dummy.position = at
	dummy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(dummy)
	var meter_name := ""
	if kind == "fixed":
		_fixed_serial += 1
		_fixed_targets.append(dummy)
		meter_name = "Fixe %s" % ["petit", "moyen", "grand"][SIZE_VALUES.find(size)]
		if _fixed_serial > 3:
			meter_name += " #%d" % _fixed_serial
	elif kind == "moving":
		meter_name = "Mobile"
	else:
		meter_name = "Tireur"
	dummy.set_meta("meter_name", meter_name)
	var respawn := Timer.new()
	respawn.name = "TrainingRespawnTimer"
	respawn.one_shot = true
	respawn.wait_time = 0.75
	respawn.process_mode = Node.PROCESS_MODE_PAUSABLE
	dummy.add_child(respawn)
	respawn.timeout.connect(_on_dummy_respawn.bind(dummy))
	dummy.connect("died", _on_dummy_died.bind(dummy))
	if _meter != null:
		_register_meter_target(dummy)
	return dummy

func _register_meter_target(dummy: StaticBody3D) -> void:
	_meter.call("register_target", dummy, str(dummy.get_meta("meter_name")))
	var state: CombatState = dummy.get("combat_state")
	state.damage_applied.connect(Callable(_meter, "record_damage").bind(dummy))

func _on_dummy_died(dummy: StaticBody3D) -> void:
	if is_instance_valid(dummy):
		(dummy.get_node("TrainingRespawnTimer") as Timer).start()

func _on_dummy_respawn(dummy: StaticBody3D) -> void:
	if is_instance_valid(dummy) and dummy.is_inside_tree():
		dummy.call("reset_combat_state")

func get_training_targets() -> Array[StaticBody3D]:
	var targets: Array[StaticBody3D] = []
	for dummy in _fixed_targets:
		if is_instance_valid(dummy):
			targets.append(dummy)
	for dummy in [_moving_target, _shooter_target]:
		if is_instance_valid(dummy):
			targets.append(dummy)
	return targets

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TrainingUI"
	add_child(layer)
	_ui_layer = layer
	var ui := Control.new()
	ui.name = "TrainingRoot"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var header := ColorRect.new()
	header.color = Color("#1d2429dd")
	header.position = Vector2(10, 8)
	header.size = Vector2(1080, 58)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(header)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color("#f3e8d1"))
	_status.position = Vector2(18, 16)
	_status.size = Vector2(760, 44)
	ui.add_child(_status)
	_vitals = Control.new()
	_vitals.name = "PlayerVitals"
	_vitals.set_script(HUD_VITALS_SCRIPT)
	_vitals.position = Vector2(22, 100)
	_vitals.size = Vector2(280, 90)
	_vitals.call("set_player", player)
	ui.add_child(_vitals)
	_reset_button = _button("RESET  F5", _reset_trial, "secondary", 46)
	_reset_button.position = Vector2(790, 16)
	_reset_button.size = Vector2(120, 46)
	ui.add_child(_reset_button)
	_training_menu_button = _button("MENU  TAB", _toggle_menu, "secondary", 46)
	_training_menu_button.position = Vector2(920, 16)
	_training_menu_button.size = Vector2(150, 46)
	ui.add_child(_training_menu_button)
	_build_spell_bar(ui)
	_meter = Control.new()
	_meter.name = "TrainingMeter"
	_meter.set_script(METER_SCRIPT)
	ui.add_child(_meter)
	_meter.connect("reset_requested", _reset_trial)
	_meter.connect("expanded_changed", _on_meter_expanded_changed)
	for dummy in get_training_targets():
		_register_meter_target(dummy)
	_menu_dim = ColorRect.new()
	_menu_dim.name = "MenuDim"
	_menu_dim.color = Color("#0b1015a8")
	_menu_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_dim.visible = false
	ui.add_child(_menu_dim)
	_menu = PanelContainer.new()
	_menu.name = "TrainingMenu"
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.position = Vector2(-570, -310)
	_menu.custom_minimum_size = Vector2(1140, 620)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1d252b")
	style.border_color = Color("#6f9aa0")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_menu.add_theme_stylebox_override("panel", style)
	ui.add_child(_menu)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_menu.add_child(content)
	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_column)
	title_column.add_child(_label("TRAINING GROUND", 30))
	_menu_count = _label("3/12 mannequins fixes", 16)
	_menu_count.add_theme_color_override("font_color", Color("#6fe0eb"))
	title_column.add_child(_menu_count)
	_meter_toggle_button = _button("KIKIMÈTRE  K", _toggle_meter, "secondary", 46)
	_meter_toggle_button.name = "MeterToggleButton"
	_meter_toggle_button.custom_minimum_size.x = 185
	title_row.add_child(_meter_toggle_button)
	var close := _button("FERMER  TAB", _toggle_menu, "secondary", 46)
	close.custom_minimum_size.x = 156
	title_row.add_child(close)
	content.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	content.add_child(columns)
	var equipment := VBoxContainer.new()
	equipment.custom_minimum_size.x = 342
	equipment.add_theme_constant_override("separation", 10)
	columns.add_child(equipment)
	equipment.add_child(_label("BUILD", 21))
	_add_loadout_row(equipment, "robot", "Robot", LOADOUT.ROBOTS)
	_add_loadout_row(equipment, "weapon", "Arme", LOADOUT.WEAPONS)
	_add_loadout_row(equipment, "offensive", "Offensif", LOADOUT.OFFENSIVE)
	_add_loadout_row(equipment, "defensive", "Défensif", LOADOUT.DEFENSIVE)
	_add_loadout_row(equipment, "mobility", "Mobilité", LOADOUT.MOBILITY)
	_add_loadout_row(equipment, "passive", "Passif", LOADOUT.PASSIVES)
	var build_hint := _label("Modifications appliquées immédiatement.", 14)
	build_hint.add_theme_color_override("font_color", Color("#aebfc1"))
	equipment.add_child(build_hint)
	columns.add_child(VSeparator.new())
	var dummies := VBoxContainer.new()
	dummies.custom_minimum_size.x = 342
	dummies.add_theme_constant_override("separation", 10)
	columns.add_child(dummies)
	dummies.add_child(_label("MANNEQUINS", 21))
	dummies.add_child(_label("Taille du prochain mannequin", 15))
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 6)
	dummies.add_child(sizes)
	for index in range(3):
		var size_button := _button(["PETIT", "MOYEN", "GRAND"][index], _select_size.bind(index), "secondary", 48)
		size_button.name = ["SmallSizeButton", "MediumSizeButton", "LargeSizeButton"][index]
		size_button.custom_minimum_size.x = 108
		sizes.add_child(size_button)
		_size_buttons.append(size_button)
	_select_size(_place_size_index)
	var place_button := _button("PLACER UN MANNEQUIN", func() -> void: _start_tool("place"), "primary", 52)
	place_button.name = "PlaceButton"
	dummies.add_child(place_button)
	var remove_button := _button("SUPPRIMER UN", func() -> void: _start_tool("remove"), "secondary", 48)
	remove_button.name = "RemoveButton"
	dummies.add_child(remove_button)
	var clear_button := _button("TOUT RETIRER", _remove_all_fixed, "secondary", 48)
	clear_button.name = "ClearButton"
	dummies.add_child(clear_button)
	var dummy_hint := _label("Cliquez sur le terrain pour placer ou retirer.\nClic droit / Échap : annuler l'outil.", 14)
	dummy_hint.add_theme_color_override("font_color", Color("#aebfc1"))
	dummies.add_child(dummy_hint)
	columns.add_child(VSeparator.new())
	var options_column := VBoxContainer.new()
	options_column.custom_minimum_size.x = 342
	options_column.add_theme_constant_override("separation", 10)
	columns.add_child(options_column)
	options_column.add_child(_label("RÈGLES", 21))
	_add_option_button(options_column, "invulnerable", "Invulnérable", "F6")
	_add_option_button(options_column, "instant_cooldowns", "Cooldowns instantanés", "F7")
	_add_option_button(options_column, "unlimited_ammo", "Munitions illimitées", "F8")
	options_column.add_child(HSeparator.new())
	options_column.add_child(_button("SOIGNER  F9", _heal_player, "warm", 48))
	options_column.add_child(_button("50 % PV  F10", _half_health, "warm", 48))
	var keyboard_hint := _label("Flèches + Entrée : naviguer.\nTab ou Échap : reprendre.", 14)
	keyboard_hint.add_theme_color_override("font_color", Color("#aebfc1"))
	options_column.add_child(keyboard_hint)
	content.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)
	footer.add_child(_button("RÉINITIALISER  F5", _reset_trial, "secondary", 50))
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	footer.add_child(_button("Menu principal", _return_to_main_menu, "secondary", 50))
	footer.add_child(_button("Personnaliser l'interface", _open_hud_editor, "secondary", 50))
	var resume := _button("REPRENDRE  TAB", _toggle_menu, "primary", 50)
	resume.name = "ResumeButton"
	resume.custom_minimum_size.x = 235
	footer.add_child(resume)
	_menu.visible = false
	_on_meter_expanded_changed(bool(_meter.call("is_expanded")))
	_touch_controls = Control.new()
	_touch_controls.name = "TouchControls"
	_touch_controls.set_script(TOUCH_SCRIPT)
	_touch_controls.call("set_player", player)
	layer.add_child(_touch_controls)
	_touch_controls.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_preview = MeshInstance3D.new()
	var preview_mesh := CylinderMesh.new()
	preview_mesh.top_radius = 0.78
	preview_mesh.bottom_radius = 0.78
	preview_mesh.height = 0.06
	_preview.mesh = preview_mesh
	_preview.visible = false
	add_child(_preview)

func _build_spell_bar(ui: Control) -> void:
	_spell_bar = Control.new()
	_spell_bar.name = "SpellBar"
	_spell_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spell_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spell_bar.offset_left = -284.0
	_spell_bar.offset_top = -82.0
	_spell_bar.offset_right = 284.0
	_spell_bar.offset_bottom = -10.0
	ui.add_child(_spell_bar)
	var slots := [
		{"id": "offensive", "key": "A"},
		{"id": "defensive", "key": "E"},
		{"id": "mobility", "key": "R"},
	]
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		var module_id: String = slot.id
		var content := Control.new()
		content.name = "%sSlot" % module_id.capitalize()
		content.position = Vector2(float(index) * 192.0, 0.0)
		content.size = Vector2(184.0, 72.0)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spell_bar.add_child(content)
		var backdrop := TextureRect.new()
		backdrop.texture = SPELL_BAR_FRAME
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_SCALE
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(backdrop)
		var icon := TextureRect.new()
		icon.name = "ModuleIcon"
		icon.position = Vector2(13.0, 12.0)
		icon.size = Vector2(42.0, 48.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		_spell_labels["%s_icon" % module_id] = icon
		var cooldown_ring := Control.new()
		cooldown_ring.name = "CooldownRing"
		cooldown_ring.set_script(COOLDOWN_RING)
		cooldown_ring.position = Vector2(10.0, 9.0)
		cooldown_ring.size = Vector2(48.0, 54.0)
		cooldown_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(cooldown_ring)
		_spell_labels["%s_ring" % module_id] = cooldown_ring
		var key_label := _spell_label(str(slot.key), 13, AMBER, Vector2(63.0, 9.0), Vector2(23.0, 23.0), HORIZONTAL_ALIGNMENT_CENTER)
		content.add_child(key_label)
		var module_label := _spell_label("", 11, CREAM, Vector2(88.0, 9.0), Vector2(89.0, 23.0), HORIZONTAL_ALIGNMENT_LEFT)
		module_label.name = "ModuleName"
		module_label.clip_text = true
		module_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		content.add_child(module_label)
		_spell_labels[module_id] = module_label
		var status := _spell_label("", 13, CYAN, Vector2(63.0, 39.0), Vector2(112.0, 22.0), HORIZONTAL_ALIGNMENT_CENTER)
		status.name = "Status"
		content.add_child(status)
		_spell_labels["%s_status" % module_id] = status
		if module_id == "offensive":
			var recast_frame := Panel.new()
			recast_frame.name = "JavelinRecastFrame"
			recast_frame.position = Vector2(10.0, 9.0)
			recast_frame.size = Vector2(48.0, 54.0)
			recast_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var frame_style := StyleBoxFlat.new()
			frame_style.bg_color = Color.TRANSPARENT
			frame_style.border_color = Color("#efb765", 0.8)
			frame_style.set_border_width_all(1)
			frame_style.set_corner_radius_all(4)
			recast_frame.add_theme_stylebox_override("panel", frame_style)
			recast_frame.visible = false
			content.add_child(recast_frame)
			_spell_labels.recast_frame = recast_frame
			var recast_track := ColorRect.new()
			recast_track.name = "JavelinRecastTrack"
			recast_track.position = Vector2(12.0, 66.0)
			recast_track.size = Vector2(160.0, 3.0)
			recast_track.color = Color("#5f4737")
			recast_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
			recast_track.visible = false
			content.add_child(recast_track)
			_spell_labels.recast_track = recast_track
			var recast_fill := ColorRect.new()
			recast_fill.name = "JavelinRecastFill"
			recast_fill.color = AMBER
			recast_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			recast_track.add_child(recast_fill)
			_spell_labels.recast_fill = recast_fill

func _spell_label(value: String, font_size: int, color: Color, at: Vector2, dimensions: Vector2, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _update_spell_bar() -> void:
	var modules := {
		"offensive": str(player.call("get_offensive_module_id")),
		"defensive": str(player.call("get_defensive_module_id")),
		"mobility": str(player.call("get_mobility_module_id")),
	}
	var recast_fraction := float(player.call("get_javelin_recast_fraction"))
	for key in modules.keys():
		var identifier: String = modules[key]
		var cooldown := float(player.call("get_module_cooldown", identifier))
		var name_label: Label = _spell_labels[key]
		var icon: TextureRect = _spell_labels["%s_icon" % key]
		var status: Label = _spell_labels["%s_status" % key]
		name_label.text = LOADOUT.display_name(identifier)
		icon.texture = _equipment_icons.get_icon(identifier)
		var recast_active: bool = key == "offensive" and identifier == "javelin" and recast_fraction > 0.0
		var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get(identifier, {})
		_spell_labels["%s_ring" % key].set_cooldown(cooldown, float(definition.get("cooldown", 1.0)), recast_active)
		if key == "offensive":
			_spell_labels.recast_frame.visible = recast_active
			_spell_labels.recast_track.visible = recast_active
			if recast_active:
				_spell_labels.recast_fill.size = Vector2(160.0 * recast_fraction, 3.0)
		if recast_active:
			status.text = "A →"
			status.add_theme_color_override("font_color", AMBER)
			name_label.add_theme_color_override("font_color", CREAM)
			icon.texture = JAVELIN_RECAST_ICON
			icon.modulate = Color.WHITE
		elif cooldown > 0.0:
			status.text = "%.1f s" % cooldown
			status.add_theme_color_override("font_color", CYAN)
			name_label.add_theme_color_override("font_color", CREAM)
			icon.modulate = Color("#b7aaa0")
		else:
			status.text = "PRÊT"
			status.add_theme_color_override("font_color", CYAN)
			name_label.add_theme_color_override("font_color", CREAM)
			icon.modulate = Color.WHITE

func _button(title: String, callback: Callable, variant: String = "secondary", height: float = 46.0) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, height)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(button, variant)
	button.pressed.connect(callback)
	return button

func _style_button(button: Button, variant: String) -> void:
	var background := Color("#29333a")
	var border := Color("#6d858b")
	var foreground := Color("#f3e8d1")
	if variant == "primary" or variant == "selected":
		background = Color("#65d6e4")
		border = Color("#b4f1f4")
		foreground = Color("#15242a")
	elif variant == "warm":
		background = Color("#795c36")
		border = Color("#e3ad68")
	button.add_theme_stylebox_override("normal", _button_style(background, border, 1))
	button.add_theme_stylebox_override("hover", _button_style(background.lightened(0.16), border.lightened(0.2), 2))
	button.add_theme_stylebox_override("pressed", _button_style(background.darkened(0.14), border, 2))
	button.add_theme_stylebox_override("focus", _button_style(Color.TRANSPARENT, Color("#f4eee0"), 2))
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)
	button.add_theme_font_size_override("font_size", 15)
	if variant == "primary":
		button.add_theme_font_override("font", UI_FONT)

func _button_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func _add_option_button(container: VBoxContainer, key: String, title: String, shortcut: String) -> void:
	var button := _button(title, func() -> void: _toggle_option(key), "secondary", 50)
	button.set_meta("base_title", title)
	button.set_meta("shortcut", shortcut)
	_option_buttons[key] = button
	container.add_child(button)

func _select_size(index: int) -> void:
	_place_size_index = index
	for button_index in range(_size_buttons.size()):
		_style_button(_size_buttons[button_index], "selected" if button_index == index else "secondary")

func _toggle_meter() -> void:
	if _meter != null:
		_meter.call("toggle_panel")

func _on_meter_expanded_changed(expanded: bool) -> void:
	if _meter_toggle_button != null:
		_meter_toggle_button.text = "KIKIMÈTRE  K  %s" % ("ON" if expanded else "OFF")
	if _hud_controller != null:
		(_meter.get_node("MeterPanel") as Control).visible = expanded and bool(_hud_controller.layout.training_meter.v)
		(_meter.get_node("MeterChip") as Control).visible = not expanded and bool(_hud_controller.layout.training_meter_chip.v)

func _label(value: String, size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#f3e8d1"))
	if size >= 20:
		label.add_theme_font_override("font", UI_FONT)
	return label

func _add_loadout_row(container: VBoxContainer, category: String, title: String, choices: Array) -> void:
	var row := HBoxContainer.new()
	container.add_child(row)
	var heading := _label(title, 15)
	heading.custom_minimum_size.x = 84
	row.add_child(heading)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(244, 48)
	_style_button(picker, "secondary")
	for identifier in choices:
		picker.add_item(LOADOUT.display_name(str(identifier)))
	picker.select(maxi(0, choices.find(str(_loadout.get(category, "")))))
	picker.item_selected.connect(_on_loadout_selected.bind(category, choices))
	row.add_child(picker)
	if _first_picker == null:
		_first_picker = picker

func _on_loadout_selected(index: int, category: String, choices: Array) -> void:
	_loadout[category] = choices[index]
	_apply_loadout()

func _apply_loadout() -> void:
	_loadout = LOADOUT.sanitize(_loadout)
	LOADOUT.save_local(_loadout)
	player.call("apply_loadout", _loadout)
	_update_spell_bar()
	_update_status()

func _toggle_option(key: String) -> void:
	_options[key] = not bool(_options[key])
	_apply_options()

func _apply_options() -> void:
	player.call("set_training_options", bool(_options.invulnerable), bool(_options.instant_cooldowns), bool(_options.unlimited_ammo))
	for key in _option_buttons.keys():
		var button: Button = _option_buttons[key]
		var active := bool(_options[key])
		button.text = "%s   %s   %s" % ["ON" if active else "OFF", str(button.get_meta("base_title")), str(button.get_meta("shortcut"))]
		_style_button(button, "selected" if active else "secondary")
	_update_status()

func _reset_trial() -> void:
	var vfx := get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("clear")
	for node in get_tree().get_nodes_in_group("prototype0_fx_budget"):
		if is_instance_valid(node):
			node.queue_free()
	player.call("reset_combat_state")
	for dummy in get_training_targets():
		(dummy.get_node("TrainingRespawnTimer") as Timer).stop()
		if dummy.has_method("reset_training_position"):
			dummy.call("reset_training_position")
	if _meter != null:
		_meter.call("reset_measurement")
	if not _menu.visible and _tool_mode == "":
		player.call("set_gameplay_enabled", true)
	_update_status()

func _heal_player() -> void:
	if bool(player.call("is_real_dead")):
		player.call("reset_combat_state")
	player.call("heal", float(player.call("get_max_health")), "training")
	if not _menu.visible and _tool_mode == "":
		player.call("set_gameplay_enabled", true)
	_update_status()

func _half_health() -> void:
	player.call("set_training_health_ratio", 0.5)
	if not _menu.visible and _tool_mode == "":
		player.call("set_gameplay_enabled", true)
	_update_status()

func _setup_hud_editor() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://prototype0_settings.cfg") == OK:
		_touch_controls.call("set_control_scale", clampf(float(settings.get_value("settings", "touch_scale", 1.0)), 0.85, 1.15))
	_hud_controller = Node.new()
	_hud_controller.name = "HudLayoutController"
	_hud_controller.set_script(HUD_CONTROLLER)
	add_child(_hud_controller)
	_hud_controller.bind_touch(_touch_controls)
	_hud_controller.register("training_status", _status)
	_hud_controller.register("player_vitals", _vitals)
	_hud_controller.register("training_reset", _reset_button)
	_hud_controller.register("training_menu", _training_menu_button)
	_hud_controller.register("spell_bar", _spell_bar, true)
	for category in ["offensive", "defensive", "mobility"]:
		_hud_controller.register("%s_slot" % category, _spell_bar.get_node("%sSlot" % category.capitalize()))
	_hud_controller.register("training_meter", _meter.get_node("MeterPanel"), true)
	_hud_controller.register("training_meter_chip", _meter.get_node("MeterChip"), true)
	_hud_editor = Control.new()
	_hud_editor.name = "HudEditor"
	_hud_editor.set_script(HUD_EDITOR)
	_ui_layer.add_child(_hud_editor)
	_hud_editor.closed.connect(_on_hud_editor_closed)
	_hud_editor.test_started.connect(_on_hud_test_started)
	_hud_editor.test_finished.connect(_on_hud_test_finished)

func _open_hud_editor() -> void:
	if _hud_editor == null or _hud_editor.visible:
		return
	_menu.visible = false
	_menu_dim.visible = false
	_spell_bar.visible = true
	_vitals.call("set_example", true)
	_meter.visible = true
	_update_spell_bar()
	_hud_editor.begin(_hud_controller)

func _on_hud_editor_closed() -> void:
	_vitals.call("set_example", false)
	_menu.visible = true
	_menu_dim.visible = true
	_spell_bar.visible = false
	_meter.visible = false
	_touch_controls.visible = false
	get_tree().paused = true

func _on_hud_test_started() -> void:
	_editor_test_fx_modes.clear()
	for group in ["prototype0_gameplay_projectiles", "prototype0_fx_budget"]:
		for node in get_tree().get_nodes_in_group(group):
			_editor_test_fx_modes[node.get_instance_id()] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
	_editor_original_player = player
	_editor_test_modes[player] = player.process_mode
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	_editor_test_positions.clear()
	for dummy in get_training_targets():
		_editor_test_positions[dummy] = dummy.global_position
		_editor_test_modes[dummy] = dummy.process_mode
		dummy.global_position = Vector3(5000, 0, 5000)
		dummy.process_mode = Node.PROCESS_MODE_DISABLED
	_editor_trial_player = CharacterBody3D.new()
	_editor_trial_player.name = "HudTrialPlayer"
	_editor_trial_player.set_script(PLAYER_SCRIPT)
	_editor_trial_player.position = player.global_position
	add_child(_editor_trial_player)
	_editor_trial_player.call("apply_loadout", _loadout)
	_editor_trial_player.call("set_training_options", true, false, true)
	_editor_trial_player.call("set_gameplay_enabled", true)
	_editor_trial_target = StaticBody3D.new()
	_editor_trial_target.name = "HudTrialTarget"
	_editor_trial_target.set_script(DUMMY_SCRIPT)
	_editor_trial_target.position = _editor_trial_player.position + Vector3(5, 0, -5)
	add_child(_editor_trial_target)
	player = _editor_trial_player
	_touch_controls.call("set_player", player)
	_vitals.call("set_player", player)
	_vitals.call("set_example", false)
	get_node("CameraRig").call("set_target", player)
	get_tree().paused = false

func _on_hud_test_finished() -> void:
	_touch_controls.call("reset_inputs")
	get_tree().paused = true
	for group in ["prototype0_gameplay_projectiles", "prototype0_fx_budget"]:
		for node in get_tree().get_nodes_in_group(group):
			if _editor_test_fx_modes.has(node.get_instance_id()):
				node.process_mode = _editor_test_fx_modes[node.get_instance_id()]
			else:
				node.queue_free()
	_editor_test_fx_modes.clear()
	if _editor_trial_player != null and is_instance_valid(_editor_trial_player):
		_editor_trial_player.call("set_gameplay_enabled", false)
		_editor_trial_player.queue_free()
	_editor_trial_player = null
	if _editor_trial_target != null and is_instance_valid(_editor_trial_target):
		_editor_trial_target.queue_free()
	_editor_trial_target = null
	player = _editor_original_player
	_touch_controls.call("set_player", player)
	_vitals.call("set_player", player)
	_vitals.call("set_example", true)
	player.visible = true
	player.process_mode = _editor_test_modes[player]
	get_node("CameraRig").call("set_target", player)
	for dummy in _editor_test_positions.keys():
		if is_instance_valid(dummy):
			dummy.global_position = _editor_test_positions[dummy]
			dummy.process_mode = _editor_test_modes[dummy]
	_editor_test_positions.clear()
	_editor_test_modes.clear()
	_update_spell_bar()

func _toggle_menu() -> void:
	if _hud_editor != null and _hud_editor.visible:
		return
	if _tool_mode != "":
		_cancel_tool()
	_menu.visible = not _menu.visible
	_menu_dim.visible = _menu.visible
	_meter.visible = not _menu.visible
	_spell_bar.visible = not _menu.visible and (_hud_controller == null or bool(_hud_controller.layout.spell_bar.v))
	if _menu.visible:
		_menu_opened_at_msec = Time.get_ticks_msec()
	elif _menu_opened_at_msec > 0:
		player.call("shift_pause_timers", float(Time.get_ticks_msec() - _menu_opened_at_msec) / 1000.0)
		_menu_opened_at_msec = 0
	get_tree().paused = _menu.visible
	if _touch_controls != null:
		_touch_controls.visible = (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")) and not _menu.visible
	player.call("set_gameplay_enabled", not _menu.visible and not bool(player.call("is_real_dead")))
	if _menu.visible and _first_picker != null:
		_first_picker.grab_focus()
	elif not _menu.visible:
		get_viewport().gui_release_focus()
	if not _menu.visible:
		_update_spell_bar()
	_update_status()

func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_player_died() -> void:
	_update_status()

func _update_status() -> void:
	if _status == null:
		return
	if _menu_count != null:
		_menu_count.text = "%d/%d mannequins fixes" % [_fixed_targets.size(), MAX_FIXED_TARGETS]
	if _tool_mode != "":
		_status.text = "CLIQUER : %s  •  clic droit/Échap : annuler" % ("placer" if _tool_mode == "place" else "supprimer")
		return
	var flags := []
	if bool(_options.invulnerable): flags.append("INVULNÉRABLE")
	if bool(_options.instant_cooldowns): flags.append("CD 0")
	if bool(_options.unlimited_ammo): flags.append("MUNITIONS ∞")
	_status.text = "TRAINING GROUND  •  %d/%d mannequins fixes  •  %s" % [_fixed_targets.size(), MAX_FIXED_TARGETS, " / ".join(flags) if not flags.is_empty() else "règles normales"]
	if player != null and bool(player.call("is_real_dead")):
		_status.text += "  •  F5 pour réapparaître"

func _start_tool(mode: String) -> void:
	if _menu.visible:
		_toggle_menu()
	_tool_mode = mode
	player.call("set_gameplay_enabled", false)
	if _touch_controls != null:
		_touch_controls.visible = false
	_update_status()

func _cancel_tool() -> void:
	_tool_mode = ""
	_preview.visible = false
	player.call("set_gameplay_enabled", not _menu.visible and not bool(player.call("is_real_dead")))
	if _touch_controls != null:
		_touch_controls.visible = (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")) and not _menu.visible
	_update_status()

func _remove_all_fixed() -> void:
	for dummy in _fixed_targets:
		if is_instance_valid(dummy):
			_meter.call("unregister_target", dummy)
			dummy.queue_free()
	_fixed_targets.clear()
	_update_status()

func _input(event: InputEvent) -> void:
	if _hud_editor != null and _hud_editor.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				_toggle_menu()
			KEY_ESCAPE:
				if _tool_mode != "":
					_cancel_tool()
				else:
					_toggle_menu()
			KEY_F5:
				_reset_trial()
			KEY_F6:
				_toggle_option("invulnerable")
			KEY_F7:
				_toggle_option("instant_cooldowns")
			KEY_F8:
				_toggle_option("unlimited_ammo")
			KEY_F9:
				_heal_player()
			KEY_F10:
				_half_health()
			KEY_K:
				_toggle_meter()
			_:
				return
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _hud_editor != null and _hud_editor.visible:
		return
	if _tool_mode == "":
		return
	if event is InputEventMouseMotion:
		_update_preview(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_tool()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_use_tool(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_use_tool(event.position)

func _ground_point(screen_position: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * 150.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.get("position", Vector3.INF)

func _valid_placement(point: Vector3, size: float) -> bool:
	if not point.is_finite() or absf(point.x) > MAP_HALF_WIDTH - 2.0 - size or absf(point.z) > MAP_HALF_DEPTH - 2.0 - size or _fixed_targets.size() >= MAX_FIXED_TARGETS:
		return false
	if point.distance_to(player.global_position) < 1.7 + size:
		return false
	for blocker in _placement_blockers:
		if blocker.grow(0.8 * size).has_point(Vector2(point.x, point.z)):
			return false
	for dummy in get_training_targets():
		if point.distance_to(dummy.global_position) < 1.0 + size + float(dummy.call("get_training_hit_radius")):
			return false
	return true

func _update_preview(screen_position: Vector2) -> void:
	_preview.visible = _tool_mode == "place"
	if not _preview.visible:
		return
	var point := _ground_point(screen_position)
	if not point.is_finite():
		_preview.visible = false
		return
	var size: float = SIZE_VALUES[_place_size_index]
	_preview.position = Vector3(point.x, 0.055, point.z)
	_preview.scale = Vector3.ONE * size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.9, 0.45, 0.55) if _valid_placement(point, size) else Color(0.95, 0.25, 0.25, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview.material_override = material

func _use_tool(screen_position: Vector2) -> void:
	if _tool_mode == "place":
		var point := _ground_point(screen_position)
		var size: float = SIZE_VALUES[_place_size_index]
		if _valid_placement(point, size):
			_spawn_dummy("fixed", Vector3(point.x, 0.0, point.z), size)
			_update_status()
	elif _tool_mode == "remove":
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var from := camera.project_ray_origin(screen_position)
		var to := from + camera.project_ray_normal(screen_position) * 150.0
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 2
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		var hit: Object = result.get("collider", null)
		if hit in _fixed_targets:
			_fixed_targets.erase(hit)
			_meter.call("unregister_target", hit)
			hit.queue_free()
			_update_status()
