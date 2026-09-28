extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const TARGET_SCRIPT := preload("res://scripts/target_dummy.gd")
const CAMERA_SCRIPT := preload("res://scripts/camera_rig.gd")
const TOUCH_SCRIPT := preload("res://scripts/touch_controls.gd")
const VFX_MANAGER_SCRIPT := preload("res://scripts/vfx_manager.gd")
const PROGRESSION := preload("res://scripts/survival_progression.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const EQUIPMENT_ICONS := preload("res://scripts/equipment_icons.gd")
const COOLDOWN_RING := preload("res://scripts/cooldown_ring.gd")
const SPELL_BAR_FRAME: Texture2D = preload("res://art/ui/spell-bar-frame.svg")
const FONT: Font = preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const FLOOR_TEXTURE: Texture2D = preload("res://art/sand_dust.svg")
const ARENA_HALF := 23.0
const SPAWN_POINTS := [Vector3(-12, 0, -7), Vector3(10, 0, 3), Vector3(12, 0, -7), Vector3(-10, 0, 3), Vector3(0, 0, -9)]

var player: CharacterBody3D
var progression: SurvivalProgression
var wave := 0
var defeated := 0
var _enemies: Array[StaticBody3D] = []
var _state := "selection"
var _ui_layer: CanvasLayer
var _hud: Control
var _wave_label: Label
var _spell_slots: Dictionary = {}
var _spell_bar: Control
var _equipment_icons = EQUIPMENT_ICONS.new()
var _pause_button: Button
var _choice_panel: PanelContainer
var _choice_content: VBoxContainer
var _pause_overlay: ColorRect
var _pause_panel: PanelContainer
var _pause_content: VBoxContainer
var _touch: Control
var _music: AudioStreamPlayer
var _arrival_label: Label
var _arrival_markers: Array[Node3D] = []
var _incoming_roles: Array[String] = []
var _arrival_remaining := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	progression = PROGRESSION.new()
	var vfx := VFX_MANAGER_SCRIPT.new()
	vfx.name = "VFXManager"
	add_child(vfx)
	_build_world()
	_build_player_and_camera()
	_build_ui()
	_build_music()
	_show_weapon_choice()

func _process(delta: float) -> void:
	if player == null or _wave_label == null:
		return
	_wave_label.text = "VAGUE %d/%d" % [wave, PROGRESSION.TOTAL_WAVES] if wave > 0 else "SURVIE"
	var build := progression.build()
	_pause_button.visible = _state == "combat"
	if _state == "incoming":
		_arrival_remaining = maxf(0.0, _arrival_remaining - delta)
		_arrival_label.text = "VAGUE %d DANS %.1f s" % [wave, _arrival_remaining]
		for marker in _arrival_markers:
			if is_instance_valid(marker):
				marker.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.014) * 0.10)
		if _arrival_remaining <= 0.0:
			_begin_wave_combat()
	_update_spell_bar(build)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _state == "combat":
			_pause_run()
		elif _state == "pause":
			_resume_run()

func get_training_targets() -> Array[StaticBody3D]:
	var active: Array[StaticBody3D] = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and float(enemy.call("get_health")) > 0.0:
			active.append(enemy)
	return active

func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#172129")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#aec4c8")
	environment.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_color = Color("#ffebc5")
	sun.light_energy = 1.2
	add_child(sun)
	_make_box("Floor", Vector3(0, -0.3, 0), Vector3(48, 0.6, 48), Color("#68716c"), 4)
	var floor_mesh := get_node("Floor/Visual") as MeshInstance3D
	var floor_material := floor_mesh.material_override as StandardMaterial3D
	floor_material.albedo_texture = FLOOR_TEXTURE
	floor_material.uv1_scale = Vector3(5, 5, 5)
	_make_marker(Vector3(0, 0.008, 0), Vector3(12.0, 0.012, 38.0), Color("#343e40"))
	_make_marker(Vector3(0, 0.012, 0), Vector3(36.0, 0.012, 7.0), Color("#3d4645"))
	for index in range(-4, 5):
		if index != 0:
			_make_marker(Vector3(0, 0.024, float(index) * 4.2), Vector3(0.12, 0.012, 1.4), Color("#c7a560"))
	for stain in [Vector3(-4.5, 0, -10), Vector3(4, 0, 6), Vector3(13, 0, -2), Vector3(-13, 0, 4)]:
		_make_stain(stain)
	_make_box("NorthWall", Vector3(0, 1, -ARENA_HALF), Vector3(48, 2, 1), Color("#3d4447"), 1)
	_make_box("SouthWall", Vector3(0, 1, ARENA_HALF), Vector3(48, 2, 1), Color("#3d4447"), 1)
	_make_box("WestWall", Vector3(-ARENA_HALF, 1, 0), Vector3(1, 2, 48), Color("#3d4447"), 1)
	_make_box("EastWall", Vector3(ARENA_HALF, 1, 0), Vector3(1, 2, 48), Color("#3d4447"), 1)
	for wreck in [
		{"name": "WreckWest", "at": Vector3(-7.5, 0, -5.0), "turn": -0.28},
		{"name": "WreckEast", "at": Vector3(7.5, 0, -4.5), "turn": 0.36},
		{"name": "WreckSouth", "at": Vector3(0, 0, 9.0), "turn": 1.57},
	]:
		_make_wreck(str(wreck.name), wreck.at, float(wreck.turn), true)
	for index in range(6):
		var angle := TAU * float(index) / 6.0 + 0.25
		_make_wreck("BorderWreck%d" % index, Vector3(cos(angle) * 19.0, 0, sin(angle) * 19.0), angle, false)
	for corner in [Vector3(-19, 0, -19), Vector3(19, 0, -19), Vector3(-19, 0, 19), Vector3(19, 0, 19)]:
		_make_lamp(corner)
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var radius := 15.0 + float(index % 3)
		_make_scrap(Vector3(cos(angle) * radius, 0, sin(angle) * radius), index)
	for edge in [-8.0, 8.0]:
		_make_marker(Vector3(edge, 0.025, 0), Vector3(0.10, 0.02, 16), Color("#91c9c1"))
		_make_marker(Vector3(0, 0.025, edge), Vector3(16, 0.02, 0.10), Color("#91c9c1"))
	for index in range(-2, 3):
		_make_marker(Vector3(float(index) * 4.0, 0.03, 0), Vector3(0.08, 0.02, 1.0), Color("#a5c0b6"))

func _make_box(node_name: String, at: Vector3, dimensions: Vector3, color: Color, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _make_marker(at: Vector3, dimensions: Vector3, color: Color) -> void:
	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	marker.mesh = mesh
	marker.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	add_child(marker)

func _make_wreck(node_name: String, at: Vector3, turn: float, solid: bool) -> void:
	var wreck := Node3D.new()
	wreck.name = node_name
	wreck.position = at
	wreck.rotation.y = turn
	add_child(wreck)
	var hull := _prop_box(wreck, Vector3(0, 0.70, 0), Vector3(4.0, 1.25, 2.0), Color("#8b4d35"), solid)
	hull.name = "Hull"
	_prop_box(wreck, Vector3(-0.35, 1.55, 0), Vector3(1.7, 0.62, 1.65), Color("#444e4f"), false)
	_prop_box(wreck, Vector3(1.55, 1.19, 0), Vector3(0.8, 0.15, 2.10), Color("#c5a778"), false)
	_prop_box(wreck, Vector3(-1.15, 1.36, 0), Vector3(0.82, 0.10, 1.50), Color("#79a6a5"), false)
	for x in [-1.25, 1.20]:
		for z in [-1.12, 1.12]:
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.51
			mesh.bottom_radius = 0.51
			mesh.height = 0.25
			wheel.mesh = mesh
			wheel.rotation_degrees.x = 90
			wheel.position = Vector3(x, 0.52, z)
			wheel.material_override = _material(Color("#20272a"))
			wreck.add_child(wheel)
	_prop_box(wreck, Vector3(0.2, 1.36, 0.0), Vector3(0.16, 0.06, 2.2), Color("#d9bd87"), false)

func _prop_box(parent: Node3D, at: Vector3, dimensions: Vector3, color: Color, solid: bool) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.position = at
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.material_override = _material(color)
	root.add_child(visual)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = dimensions
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
	parent.add_child(root)
	return root

func _make_lamp(at: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.position = at
	add_child(lamp)
	_prop_box(lamp, Vector3(0, 1.8, 0), Vector3(0.25, 3.6, 0.25), Color("#29383b"), false)
	_prop_box(lamp, Vector3(0, 3.65, 0), Vector3(1.2, 0.16, 0.6), Color("#9e5d39"), false)
	var bulb := _prop_box(lamp, Vector3(0, 3.48, 0), Vector3(0.80, 0.12, 0.42), Color("#ffcb75"), false)
	(bulb.get_child(0) as MeshInstance3D).material_override = _material(Color("#ffcb75"), true)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3.35, 0)
	light.light_color = Color("#ffc487")
	light.light_energy = 0.8
	light.omni_range = 11
	light.shadow_enabled = false
	lamp.add_child(light)

func _make_scrap(at: Vector3, index: int) -> void:
	var heap := Node3D.new()
	heap.name = "Scrap%d" % index
	heap.position = at
	heap.rotation.y = float(index) * 0.72
	add_child(heap)
	_prop_box(heap, Vector3(0, 0.22, 0), Vector3(1.4, 0.38, 0.85), Color("#66534b"), false)
	_prop_box(heap, Vector3(0.12, 0.46, -0.12), Vector3(1.0, 0.11, 1.2), Color("#9a704d"), false)
	_prop_box(heap, Vector3(-0.22, 0.54, 0.20), Vector3(0.25, 0.35, 1.1), Color("#303e43"), false)

func _make_stain(at: Vector3) -> void:
	var stain := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.25
	mesh.bottom_radius = 1.25
	mesh.height = 0.012
	stain.mesh = mesh
	stain.position = at + Vector3.UP * 0.024
	stain.scale = Vector3(1.3, 1, 0.65)
	stain.material_override = _material(Color("#202a2b"))
	add_child(stain)

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material

func _build_player_and_camera() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	var attack_label: Label3D = player.get("_attack_label")
	if attack_label != null:
		attack_label.visible = false
	player.call("set_gameplay_enabled", false)
	player.died.connect(_on_player_died)
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CAMERA_SCRIPT)
	rig.process_mode = Node.PROCESS_MODE_PAUSABLE
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 24, 20)
	camera.fov = 43
	camera.current = true
	rig.add_child(camera)
	add_child(rig)
	rig.call("set_target", player)

func _build_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "SurvivalMusic"
	_music.volume_db = -17
	var path := "res://art/audio/arena_electro_build.wav"
	if ResourceLoader.exists(path):
		_music.stream = load(path)
		if _music.stream is AudioStreamWAV:
			(_music.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	add_child(_music)

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "SurvivalUI"
	_ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_layer)
	_hud = Control.new()
	_hud.name = "HUD"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_hud)
	var bar := ColorRect.new()
	bar.color = Color("#151d25df")
	bar.position = Vector2(10, 8)
	bar.size = Vector2(204, 50)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(bar)
	_wave_label = _label("", 21, Color("#f3ddbb"))
	_wave_label.position = Vector2(24, 18)
	_wave_label.size = Vector2(185, 32)
	_hud.add_child(_wave_label)
	_pause_button = _button("PAUSE", Callable(self, "_pause_run"))
	_pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_button.position = Vector2(-140, 15)
	_pause_button.custom_minimum_size = Vector2(120, 42)
	_hud.add_child(_pause_button)
	_arrival_label = _label("", 25, Color("#ffd18a"))
	_arrival_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_arrival_label.position = Vector2(-270, 165)
	_arrival_label.size = Vector2(540, 50)
	_arrival_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrival_label.visible = false
	_hud.add_child(_arrival_label)
	_build_spell_bar()
	_touch = Control.new()
	_touch.name = "TouchControls"
	_touch.set_script(TOUCH_SCRIPT)
	_touch.call("set_player", player)
	_ui_layer.add_child(_touch)
	_choice_panel = PanelContainer.new()
	_choice_panel.name = "ChoicePanel"
	_choice_panel.custom_minimum_size = Vector2(680, 330)
	_choice_panel.set_anchors_preset(Control.PRESET_CENTER)
	_choice_panel.position = Vector2(-340, -165)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e2930f2")
	style.border_color = Color("#74c9ce")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_choice_panel.add_theme_stylebox_override("panel", style)
	_ui_layer.add_child(_choice_panel)
	_choice_content = VBoxContainer.new()
	_choice_content.add_theme_constant_override("separation", 12)
	_choice_panel.add_child(_choice_content)
	_choice_panel.visible = false
	_build_pause_menu()

func _build_pause_menu() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.color = Color("#081015b8")
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	_ui_layer.add_child(_pause_overlay)
	_pause_panel = PanelContainer.new()
	_pause_panel.name = "PausePanel"
	_pause_panel.custom_minimum_size = Vector2(750, 0)
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.position = Vector2(-375, -250)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1b252bf8")
	style.border_color = Color("#d39462")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	_pause_panel.add_theme_stylebox_override("panel", style)
	_ui_layer.add_child(_pause_panel)
	_pause_content = VBoxContainer.new()
	_pause_content.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(_pause_content)
	_pause_panel.visible = false

func _build_spell_bar() -> void:
	_spell_bar = Control.new()
	_spell_bar.name = "SpellBar"
	_spell_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spell_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spell_bar.offset_left = -284.0
	_spell_bar.offset_top = -82.0
	_spell_bar.offset_right = 284.0
	_spell_bar.offset_bottom = -10.0
	_spell_bar.visible = false
	_hud.add_child(_spell_bar)
	for index in range(3):
		var category: String = ["offensive", "defensive", "mobility"][index]
		var slot := Control.new()
		slot.name = "%sSlot" % category.capitalize()
		slot.position = Vector2(index * 192.0, 0.0)
		slot.size = Vector2(184.0, 72.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spell_bar.add_child(slot)
		var frame := TextureRect.new()
		frame.texture = SPELL_BAR_FRAME
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(frame)
		var icon := TextureRect.new()
		icon.position = Vector2(13.0, 12.0)
		icon.size = Vector2(42.0, 48.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var ring := Control.new()
		ring.set_script(COOLDOWN_RING)
		ring.position = Vector2(10.0, 9.0)
		ring.size = Vector2(48.0, 54.0)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ring)
		var key := _label({"offensive": "A", "defensive": "E", "mobility": "R"}[category], 13, Color("#efb765"))
		key.position = Vector2(63.0, 9.0)
		key.size = Vector2(23.0, 23.0)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(key)
		var name_label := _label("", 11, Color("#f3ddbb"))
		name_label.position = Vector2(88.0, 9.0)
		name_label.size = Vector2(89.0, 23.0)
		name_label.clip_text = true
		slot.add_child(name_label)
		var status := _label("", 13, Color("#92e1d7"))
		status.position = Vector2(63.0, 39.0)
		status.size = Vector2(112.0, 22.0)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(status)
		_spell_slots[category] = {"icon": icon, "ring": ring, "name": name_label, "status": status}

func _update_spell_bar(build: Dictionary) -> void:
	_spell_bar.visible = wave > 0 and _state in ["incoming", "combat"]
	if not _spell_bar.visible:
		return
	var multipliers: Dictionary = player.get("_survival_cooldown_multipliers")
	for category in ["offensive", "defensive", "mobility"]:
		var identifier := str(build[category])
		var slot: Dictionary = _spell_slots[category]
		var icon: TextureRect = slot.icon
		var ring: Control = slot.ring
		var name_label: Label = slot.name
		var status: Label = slot.status
		icon.texture = _equipment_icons.get_icon(identifier)
		name_label.text = LOADOUT.display_name(identifier) if identifier != "" else "—"
		if identifier == "":
			status.text = "—"
			status.add_theme_color_override("font_color", Color("#8e9a9c"))
			ring.call("set_cooldown", 0.0, 1.0)
			continue
		var cooldown := float(player.call("get_module_cooldown", identifier))
		var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get(identifier, {})
		var duration := float(definition.get("cooldown", 1.0)) * float(multipliers.get(category, 1.0))
		var recast: bool = category == "offensive" and identifier == "javelin" and float(player.call("get_javelin_recast_fraction")) > 0.0
		ring.call("set_cooldown", cooldown, duration, recast)
		status.text = "A →" if recast else "%.1f s" % cooldown if cooldown > 0.0 else "PRÊT"
		status.add_theme_color_override("font_color", Color("#efb765") if cooldown > 0.0 or recast else Color("#92e1d7"))
		icon.modulate = Color("#b7aaa0") if cooldown > 0.0 and not recast else Color.WHITE

func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if size >= 20:
		label.add_theme_font_override("font", FONT)
	return label

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(590, 58)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(callback)
	return button

func _clear_choices() -> void:
	for child in _choice_content.get_children():
		_choice_content.remove_child(child)
		child.queue_free()

func _clear_pause_content() -> void:
	for child in _pause_content.get_children():
		_pause_content.remove_child(child)
		child.queue_free()

func _pause_build_card(category: String, title: String, build: Dictionary) -> PanelContainer:
	var identifier := str(build[category])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(338, 84)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#26343a")
	style.border_color = Color("#60969a") if identifier != "" else Color("#4a5558")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(9)
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(58, 62)
	icon.texture = _equipment_icons.get_icon(identifier)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 1)
	row.add_child(details)
	details.add_child(_label(title, 12, Color("#efb765")))
	var item_name := _label(LOADOUT.display_name(identifier) if identifier != "" else "NON ÉQUIPÉ", 16, Color("#f3ddbb") if identifier != "" else Color("#8e9a9c"))
	item_name.clip_text = true
	details.add_child(item_name)
	var upgrades: Dictionary = build["upgrades"][category]
	var status := "EN ATTENTE" if identifier == "" else "ÉVOLUTION  ·  PUISSANCE +%d  ·  RYTHME +%d" % [int(upgrades["power"]), int(upgrades["tempo"])] if bool(build["evolutions"][category]) else "PUISSANCE +%d  ·  RYTHME +%d" % [int(upgrades["power"]), int(upgrades["tempo"])]
	var status_label := _label(status, 11, Color("#92d5d2") if identifier != "" else Color("#8e9a9c"))
	status_label.clip_text = true
	details.add_child(status_label)
	return card

func _pause_action(value: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#1b252b") if primary else Color("#f3ddbb"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#efb765") if primary else Color("#303e43")
	normal.border_color = Color("#efb765") if primary else Color("#69898b")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#ffd08c") if primary else Color("#40585c")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(callback)
	return button

func _show_pause_content() -> void:
	_clear_pause_content()
	var heading := _label("PAUSE", 29, Color("#f3ddbb"))
	_pause_content.add_child(heading)
	_pause_content.add_child(_label("VAGUE %d/%d   ·   BUILD ACTUEL" % [wave, PROGRESSION.TOTAL_WAVES], 15, Color("#92d5d2")))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_pause_content.add_child(grid)
	var build := progression.build()
	for entry in [["weapon", "ARME"], ["offensive", "OFFENSIF"], ["defensive", "DÉFENSIF"], ["mobility", "MOBILITÉ"], ["passive", "PASSIF"]]:
		grid.add_child(_pause_build_card(str(entry[0]), str(entry[1]), build))
	_pause_content.add_child(_pause_action("REPRENDRE", Callable(self, "_resume_run"), true))
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 10)
	secondary.add_child(_pause_action("RECOMMENCER", Callable(self, "_restart")))
	secondary.add_child(_pause_action("RETOUR AU MENU", Callable(self, "_return_menu")))
	_pause_content.add_child(secondary)

func _show_weapon_choice() -> void:
	_state = "selection"
	_clear_choices()
	_choice_content.add_child(_label("SURVIE", 25, Color("#f3ddbb")))
	_choice_content.add_child(_label("12 vagues · Choisis une arme", 16, Color("#c7d2d1")))
	_choice_content.add_child(_button("BLASTER", func() -> void: _choose_weapon("blaster")))
	_choice_content.add_child(_button("SHOTGUN", func() -> void: _choose_weapon("shotgun")))
	_choice_content.add_child(_button("RETOUR AU MENU", Callable(self, "_return_menu")))
	_choice_panel.visible = true
	_touch.visible = false

func _choose_weapon(identifier: String) -> void:
	if not progression.choose_weapon(identifier):
		return
	player.call("configure_survival_build", progression.build())
	player.call("reset_combat_state")
	if _music.stream != null:
		_music.play()
	_start_wave()

func _start_wave() -> void:
	get_tree().paused = false
	_clear_enemies()
	wave += 1
	defeated = 0
	_state = "incoming"
	_update_spell_bar(progression.build())
	_choice_panel.visible = false
	_touch.visible = false
	_arrival_remaining = 2.0
	_arrival_label.visible = true
	_incoming_roles.clear()
	var regular_count := 3 if wave == PROGRESSION.TOTAL_WAVES else mini(2 + int((wave - 1) / 3), 5)
	for index in range(regular_count):
		_incoming_roles.append(["chaser", "shooter", "charger"][(wave + index - 1) % 3])
	if wave == PROGRESSION.TOTAL_WAVES:
		_incoming_roles.append("boss")
	for index in range(_incoming_roles.size()):
		var marker := MeshInstance3D.new()
		marker.name = "Arrival_%d" % index
		var ring := TorusMesh.new()
		ring.inner_radius = 0.65 if _incoming_roles[index] != "boss" else 1.3
		ring.outer_radius = 0.85 if _incoming_roles[index] != "boss" else 1.55
		marker.mesh = ring
		marker.rotation_degrees.x = 90
		marker.position = SPAWN_POINTS[index] + Vector3.UP * 0.09
		marker.material_override = _material(_role_color(_incoming_roles[index]), true)
		add_child(marker)
		_arrival_markers.append(marker)
	player.call("set_gameplay_enabled", false)

func _begin_wave_combat() -> void:
	if _state != "incoming":
		return
	for marker in _arrival_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_arrival_markers.clear()
	for index in range(_incoming_roles.size()):
		_spawn_enemy(SPAWN_POINTS[index], _incoming_roles[index])
	_arrival_label.visible = false
	_state = "combat"
	_update_spell_bar(progression.build())
	_touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	player.call("set_gameplay_enabled", true)

func _role_color(role: String) -> Color:
	return {"chaser": Color("#ee9361"), "shooter": Color("#70d3dc"), "charger": Color("#ee6264"), "boss": Color("#e7b850")}.get(role, Color.WHITE)

func _role_name(role: String) -> String:
	return {"chaser": "POURSUITE", "shooter": "TIREUR", "charger": "CHARGE", "boss": "BROYEUR"}.get(role, role.to_upper())

func _spawn_enemy(at: Vector3, role: String) -> void:
	var enemy := StaticBody3D.new()
	enemy.name = "WaveEnemy_%02d_%02d" % [wave, _enemies.size()]
	enemy.set_script(TARGET_SCRIPT)
	enemy.position = at
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemy.call("set_duel_mode", true)
	var state: CombatState = enemy.get("combat_state")
	state.max_health = 1200.0 if role == "boss" else (65.0 if role == "shooter" else 155.0 if role == "charger" else 110.0) + 32.0 * float(wave)
	enemy.call("reset_combat_state")
	enemy.scale = Vector3.ONE * (1.5 if role == "boss" else 1.18 if role == "charger" else 0.86 if role == "shooter" else 1.0)
	var readout: Node = enemy.get_node("TargetHealthReadout")
	readout.call("update_actor_identity", _role_color(role), _role_name(role))
	var bot := enemy.get_node("TrainingBot")
	bot.set("survival_role", role)
	bot.set("training_attack_damage", 36.0 if role == "boss" else (15.0 if role == "charger" else 10.0 if role == "chaser" else 7.0) + 1.2 * float(wave))
	bot.set("training_attack_interval", 2.6 if role == "boss" else 3.2 if role == "charger" else 1.5 if role == "chaser" else 2.5)
	enemy.call("set_training_bot_enabled", true)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_enemies.append(enemy)

func _on_enemy_died(enemy: StaticBody3D) -> void:
	if _state != "combat":
		return
	enemy.call("set_training_bot_enabled", false)
	if progression.evolutions.passive and progression.equipment.passive == "omnivamp":
		player.call("heal", 35.0, "omnivamp_kill")
	defeated += 1
	if defeated >= _enemies.size():
		call_deferred("_complete_wave")

func _complete_wave() -> void:
	if _state != "combat" or defeated < _enemies.size():
		return
	player.call("set_gameplay_enabled", false)
	_touch.call("reset_inputs")
	if wave >= PROGRESSION.TOTAL_WAVES:
		_show_result(true)
		return
	_state = "reward"
	_spell_bar.visible = false
	get_tree().paused = true
	_clear_choices()
	_choice_content.add_child(_label("VAGUE %d TERMINÉE" % wave, 24, Color("#f3ddbb")))
	_choice_content.add_child(_label("Choisis une amélioration", 16, Color("#c7d2d1")))
	for choice in progression.reward_choices(wave):
		var value := "%s\n%s" % [str(choice.title), _reward_description(choice)]
		var button := _button(value, _choose_reward.bind(choice))
		button.custom_minimum_size.y = 108
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_choice_content.add_child(button)
	_choice_panel.visible = true
	_touch.visible = false

func _choose_reward(choice: Dictionary) -> void:
	if _state != "reward" or not progression.apply_reward(wave, choice):
		return
	get_tree().paused = false
	player.call("configure_survival_build", progression.build())
	player.call("heal", 150.0, "wave_reward")
	_start_wave()

func _on_player_died() -> void:
	if _state == "combat":
		call_deferred("_show_result", false)

func _show_result(won: bool) -> void:
	if _state != "combat":
		return
	_state = "result"
	_spell_bar.visible = false
	player.call("set_gameplay_enabled", false)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.call("set_training_bot_enabled", false)
	get_tree().paused = true
	if _music != null:
		_music.stop()
	_clear_choices()
	_choice_content.add_child(_label("VICTOIRE  ·  12 VAGUES" if won else "DÉFAITE  ·  VAGUE %d" % wave, 28, Color("#8fe6aa") if won else Color("#f28a79")))
	_choice_content.add_child(_label("Arme : %s  ·  Ennemis vaincus : %d" % [LOADOUT.display_name(progression.weapon), _total_defeated()], 17, Color("#f3ddbb")))
	_choice_content.add_child(_button("RECOMMENCER", Callable(self, "_restart")))
	_choice_content.add_child(_button("RETOUR AU MENU", Callable(self, "_return_menu")))
	_choice_panel.visible = true
	_touch.visible = false

func _total_defeated() -> int:
	var count := 0
	for completed in range(1, wave):
		count += mini(2 + int((completed - 1) / 3), 5)
	return count + defeated

func _pause_run() -> void:
	if _state != "combat":
		return
	_state = "pause"
	_spell_bar.visible = false
	get_tree().paused = true
	_music.stream_paused = true
	_touch.call("reset_inputs")
	_show_pause_content()
	_pause_overlay.visible = true
	_pause_panel.visible = true
	_touch.visible = false

func _resume_run() -> void:
	if _state != "pause":
		return
	_state = "combat"
	_update_spell_bar(progression.build())
	get_tree().paused = false
	_music.stream_paused = false
	_pause_overlay.visible = false
	_pause_panel.visible = false
	_touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

func _clear_enemies() -> void:
	for marker in _arrival_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_arrival_markers.clear()
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()

func _restart() -> void:
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/survival.tscn")

func _return_menu() -> void:
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")

func _short_name(identifier: String) -> String:
	return LOADOUT.display_name(identifier) if identifier != "" else "—"

func _reward_description(choice: Dictionary) -> String:
	if str(choice.kind) != "item":
		return str(choice.description)
	return {
		"modulo_drone": "Tir guidé. Brûle et révèle la cible.",
		"javelin": "Lance un javelot. Réappui pour te téléporter.",
		"magnetic_field": "Mur qui absorbe les tirs pendant 2,5 s.",
		"static_shield": "Invulnérable 1,5 s. Actions bloquées.",
		"pyro_boots": "Ruée de 3 m. Recharge : 6 s.",
		"bio_injector": "Vitesse et tirs accélérés pendant 3 s.",
		"baroud": "Survis brièvement à un coup fatal.",
		"omnivamp": "Soigne 15 % des dégâts infligés.",
	}.get(str(choice.id), str(choice.description))
