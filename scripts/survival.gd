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
const HUD_CONTROLLER := preload("res://scripts/hud_layout_controller.gd")
const HUD_EDITOR := preload("res://scripts/hud_editor.gd")
const TRIAL_DUMMY_SCRIPT := preload("res://scripts/training_dummy.gd")
const HUD_VITALS_SCRIPT := preload("res://scripts/hud_vitals.gd")
const SPELL_BAR_FRAME: Texture2D = preload("res://art/ui/spell-bar-frame.svg")
const REWARD_CARD_ART: Texture2D = preload("res://art/ui/industrial-reward-card.png")
const FONT: Font = preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const FLOOR_TEXTURE: Texture2D = preload("res://art/sand_dust.svg")
const ARENA_HALF := 23.0
const REWARD_INPUT_DELAY := 0.55
const MUSIC_PATHS := [
	"res://son-musique/musiques/survie_early_loop.wav",
	"res://son-musique/musiques/la_forge_semballe_loop.wav",
	"res://son-musique/musiques/survie_late_loop.wav",
]
const REWARD_MUSIC_PATH := "res://son-musique/musiques/survie_respiration_loop.wav"
const MUSIC_STAGE_VOLUME_DB := [-17.0, -17.0, -15.5]
const REWARD_MUSIC_LOOP_START_S := 1.25
const SPAWN_POINTS := [Vector3(-12, 0, -7), Vector3(10, 0, 3), Vector3(12, 0, -7), Vector3(-10, 0, 3), Vector3(0, 0, -9)]

const SYNERGIES := preload("res://scripts/survival_synergies.gd")
const RUN_STATS := preload("res://scripts/survival_run_stats.gd")
const SUMMARY := preload("res://scripts/survival_summary.gd")
var stats := RUN_STATS.new()
var records_path := RUN_STATS.RECORDS_PATH
var summary: Control
var _reinforcement_roles: Array[String] = []
var _reinforcement_positions: Array[Vector3] = []
var _reinforcement_remaining := 0.0
var _spawn_positions: Array[Vector3] = []
var _repair: Node3D
var _synergy_label: Label

var player: CharacterBody3D
var progression: SurvivalProgression
var wave := 0
var defeated := 0
var _enemies: Array[StaticBody3D] = []
var _state := "selection"
var _pause_started_at_msec := -1
var _ui_layer: CanvasLayer
var _hud: Control
var _wave_label: Label
var _vitals: Control
var _spell_slots: Dictionary = {}
var _spell_bar: Control
var _equipment_icons = EQUIPMENT_ICONS.new()
var _pause_button: Button
var _choice_panel: PanelContainer
var _choice_content: VBoxContainer
var _reward_overlay: Control
var _reward_content: VBoxContainer
var _reward_input_delay := -1.0
var _pause_overlay: ColorRect
var _pause_panel: PanelContainer
var _pause_content: VBoxContainer
var _touch: Control
var _music: AudioStreamPlayer
var _other_music: AudioStreamPlayer
var _reward_music: AudioStreamPlayer
var _music_stage := -1
var _music_tween: Tween
var _reward_music_tween: Tween
var _arrival_label: Label
var _arrival_markers: Array[Node3D] = []
var _incoming_roles: Array[String] = []
var _arrival_remaining := 0.0
var _hud_controller
var _hud_editor
var _editor_test_positions: Dictionary = {}
var _editor_test_modes: Dictionary = {}
var _editor_original_player: CharacterBody3D
var _editor_trial_player: CharacterBody3D
var _editor_trial_target: StaticBody3D
var _editor_test_fx_modes: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	progression = PROGRESSION.new()
	var vfx := VFX_MANAGER_SCRIPT.new()
	vfx.name = "VFXManager"
	add_child(vfx)
	_build_world()
	_build_player_and_camera()
	_build_ui()
	player.combat_state.damage_applied.connect(stats.record_received)
	player.combat_state.healing_applied.connect(stats.record_heal)
	_synergy_label = _label("", 13, Color("#efba6c"))
	_synergy_label.position = Vector2(24, 62)
	_hud.add_child(_synergy_label)
	_setup_hud_editor()
	_build_music()
	_show_weapon_choice()

func _process(delta: float) -> void:
	if player == null or _wave_label == null:
		return
	_wave_label.text = "VAGUE %d/%d" % [wave, PROGRESSION.TOTAL_WAVES] if wave > 0 else "SURVIE"
	var build := progression.build()
	_synergy_label.text = SYNERGIES.names(build)
	_synergy_label.visible = _state == "combat"
	if _state == "combat":
		stats.elapsed += delta
		if not _reinforcement_roles.is_empty():
			_reinforcement_remaining = maxf(0.0, _reinforcement_remaining - delta)
			_arrival_label.text = "RENFORTS DANS %.1f s" % _reinforcement_remaining
			if _reinforcement_remaining <= 0.0:
				_spawn_reinforcements()
		if is_instance_valid(_repair) and player.global_position.distance_to(_repair.global_position) < 1.5:
			if float(player.call("heal", 80.0, "repair_pickup")) > 0.0:
				_repair.queue_free()
				_repair = null
	_pause_button.visible = (_state == "combat" or (_hud_editor != null and _hud_editor.visible)) and (_hud_controller == null or bool(_hud_controller.layout.pause.v))
	if _state == "incoming":
		_arrival_remaining = maxf(0.0, _arrival_remaining - delta)
		_arrival_label.text = "VAGUE %d DANS %.1f s" % [wave, _arrival_remaining]
		for marker in _arrival_markers:
			if is_instance_valid(marker):
				marker.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.014) * 0.10)
		if _arrival_remaining <= 0.0:
			_begin_wave_combat()
	if _state == "reward" and _reward_input_delay >= 0.0:
		_reward_input_delay = maxf(0.0, _reward_input_delay - delta)
		if _reward_input_delay <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_key_pressed(KEY_SPACE):
			_reward_input_delay = -1.0
			for card in _reward_overlay.find_children("RewardChoice*", "Button", true, false):
				(card as Button).disabled = false
	_update_spell_bar(build)

func _unhandled_input(event: InputEvent) -> void:
	if _hud_editor != null and _hud_editor.visible:
		return
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
	player.call("set_robot", str(LOADOUT.load_local().robot))
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
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	_music.volume_db = MUSIC_STAGE_VOLUME_DB[0]
	add_child(_music)
	_other_music = AudioStreamPlayer.new()
	_other_music.name = "SurvivalMusicTransition"
	_other_music.process_mode = Node.PROCESS_MODE_ALWAYS
	_other_music.volume_db = -60.0
	add_child(_other_music)
	_reward_music = AudioStreamPlayer.new()
	_reward_music.name = "SurvivalRewardMusic"
	_reward_music.process_mode = Node.PROCESS_MODE_ALWAYS
	_reward_music.volume_db = -60.0
	_reward_music.stream = _load_looping_music(REWARD_MUSIC_PATH)
	add_child(_reward_music)

func _load_looping_music(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_error("Musique de Survie absente : " + path)
		return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = int((20.0 if path != REWARD_MUSIC_PATH else REWARD_MUSIC_LOOP_START_S) * wav.mix_rate)
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return stream

func _music_stage_for_wave(next_wave: int) -> int:
	if next_wave <= 4:
		return 0
	if next_wave <= 8:
		return 1
	return 2

func _play_music_for_wave(next_wave: int) -> void:
	var target_stage := _music_stage_for_wave(next_wave)
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	var target_volume_db: float = MUSIC_STAGE_VOLUME_DB[target_stage]
	if target_stage == _music_stage:
		if not _music.playing and _music.stream != null:
			_music.play()
		_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_music_tween.tween_property(_music, "volume_db", target_volume_db, 1.2)
		return
	var next_stream := _load_looping_music(MUSIC_PATHS[target_stage])
	if next_stream == null:
		return
	_music_stage = target_stage
	if not _music.playing:
		_music.stream = next_stream
		_music.volume_db = target_volume_db
		_music.stream_paused = false
		_music.play()
		return
	var previous := _music
	var next_player := _other_music
	next_player.stop()
	next_player.stream = next_stream
	next_player.stream_paused = false
	next_player.volume_db = -60.0
	# Variations share the theme's pulse. Keep its position when changing arrangement.
	next_player.play(minf(previous.get_playback_position(), next_stream.get_length() - 0.1))
	_music = next_player
	_other_music = previous
	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_music_tween.tween_property(_music, "volume_db", target_volume_db, 1.2)
	_music_tween.tween_property(previous, "volume_db", -60.0, 1.2)
	_music_tween.chain().tween_callback(previous.stop)

func _enter_reward_music() -> void:
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(_music, "volume_db", -38.0, 0.8)
	if _reward_music.stream == null:
		return
	if _reward_music_tween != null and _reward_music_tween.is_running():
		_reward_music_tween.kill()
	_reward_music.volume_db = -60.0
	_reward_music.stream_paused = false
	_reward_music.play()
	_reward_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reward_music_tween.tween_property(_reward_music, "volume_db", -24.0, 0.8)

func _leave_reward_music() -> void:
	if _reward_music_tween != null and _reward_music_tween.is_running():
		_reward_music_tween.kill()
	_reward_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reward_music_tween.tween_property(_reward_music, "volume_db", -60.0, 1.2)
	_reward_music_tween.tween_callback(_reward_music.stop)

func _stop_all_music() -> void:
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	if _reward_music_tween != null and _reward_music_tween.is_running():
		_reward_music_tween.kill()
	_music.stop()
	_other_music.stop()
	_reward_music.stop()

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
	bar.name = "WavePanel"
	bar.color = Color("#151d25df")
	bar.position = Vector2(10, 8)
	bar.size = Vector2(204, 50)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(bar)
	_vitals = Control.new()
	_vitals.name = "PlayerVitals"
	_vitals.set_script(HUD_VITALS_SCRIPT)
	_vitals.position = Vector2(22, 102)
	_vitals.size = Vector2(280, 90)
	_vitals.call("set_player", player)
	_hud.add_child(_vitals)
	_wave_label = _label("", 21, Color("#f3ddbb"))
	_wave_label.position = Vector2(14, 10)
	_wave_label.size = Vector2(185, 32)
	bar.add_child(_wave_label)
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
	style.bg_color = Color("#22272b")
	style.border_color = Color("#b78358")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_choice_panel.add_theme_stylebox_override("panel", style)
	_ui_layer.add_child(_choice_panel)
	_choice_content = VBoxContainer.new()
	_choice_content.add_theme_constant_override("separation", 12)
	_choice_panel.add_child(_choice_content)
	_choice_panel.visible = false
	_build_reward_ui()
	_build_pause_menu()

func _build_reward_ui() -> void:
	_reward_overlay = Control.new()
	_reward_overlay.name = "RewardOverlay"
	_reward_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reward_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_reward_overlay.visible = false
	_ui_layer.add_child(_reward_overlay)
	var shade := ColorRect.new()
	shade.color = Color("#091219db")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reward_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_reward_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "RewardPanel"
	panel.custom_minimum_size = Vector2(690, 550)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#17252cdd")
	style.border_color = Color("#415e62")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	_reward_content = VBoxContainer.new()
	_reward_content.add_theme_constant_override("separation", 8)
	panel.add_child(_reward_content)

func _reward_choice_card(choice: Dictionary, index: int) -> Button:
	var card := Button.new()
	card.name = "RewardChoice%d" % index
	card.text = ""
	card.disabled = true
	card.custom_minimum_size = Vector2(290, 435)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, empty)
	card.pressed.connect(_choose_reward.bind(choice))
	var art := TextureRect.new()
	art.texture = REWARD_CARD_ART
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	card.mouse_entered.connect(func() -> void: art.modulate = Color(1.18, 1.13, 1.04))
	card.mouse_exited.connect(func() -> void: art.modulate = Color.WHITE)
	card.focus_entered.connect(func() -> void: art.modulate = Color(1.18, 1.13, 1.04))
	card.focus_exited.connect(func() -> void: art.modulate = Color.WHITE)
	var kinds := {"item": "NOUVEAU MODULE", "evolution": "ÉVOLUTION", "power": "PUISSANCE", "tempo": "RYTHME"}
	var eyebrow := _label(str(kinds.get(str(choice.kind), "AMÉLIORATION")), 12, Color("#b4eeea"))
	eyebrow.position = Vector2(50, 17)
	eyebrow.size = Vector2(190, 27)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(eyebrow)
	var icon := TextureRect.new()
	icon.texture = _equipment_icons.get_icon(str(choice.id))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	icon.position = Vector2(68, 61)
	icon.size = Vector2(154, 155)
	var title := _label(LOADOUT.display_name(str(choice.id)), 19, Color("#f5dfbf"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.position = Vector2(45, 232)
	title.size = Vector2(200, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)
	var description := _label(_reward_card_description(choice), 13, Color("#d7e2dd"))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.position = Vector2(45, 284)
	description.size = Vector2(200, 71)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(description)
	var action := _label("CHOISIR", 15, Color("#f5dfbf"))
	action.position = Vector2(55, 376)
	action.size = Vector2(180, 24)
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(action)
	var synergy_hint := SYNERGIES.preview(progression.build(), choice)
	if synergy_hint != "":
		var hint := _label(synergy_hint, 11, Color("#ffe09a"))
		description.position.y = 280
		description.size.y = 45
		description.add_theme_font_size_override("font_size", 12)
		hint.position = Vector2(40, 329)
		hint.size = Vector2(210, 24)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hint)
		card.tooltip_text = synergy_hint
	return card

func _show_reward_choices() -> void:
	_reward_input_delay = REWARD_INPUT_DELAY
	for child in _reward_content.get_children():
		_reward_content.remove_child(child)
		child.queue_free()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_reward_content.add_child(top)
	var section := _label("SURVIE  /  RÉCOMPENSE", 13, Color("#8fd1d0"))
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(section)
	top.add_child(_label("VAGUE %02d / %02d" % [wave, PROGRESSION.TOTAL_WAVES], 13, Color("#efb765")))
	_reward_content.add_child(_label("CHOISIS UNE AMÉLIORATION", 27, Color("#f5dfbf")))
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 20)
	_reward_content.add_child(cards)
	var choices := progression.reward_choices(wave)
	for index in range(choices.size()):
		cards.add_child(_reward_choice_card(choices[index], index + 1))
	_reward_overlay.visible = true

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
	_spell_bar.visible = ((wave > 0 and _state in ["incoming", "combat"]) or (_hud_editor != null and _hud_editor.visible)) and (_hud_controller == null or bool(_hud_controller.layout.spell_bar.v))
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
	button.add_theme_color_override("font_color", Color("#f3ddbb"))
	button.add_theme_color_override("font_hover_color", Color("#fff0d7"))
	button.add_theme_color_override("font_pressed_color", Color("#f3ddbb"))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#30383b")
	normal.border_color = Color("#86745f")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#45443d")
	hover.border_color = Color("#efb765")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#272d30")
	pressed.border_color = Color("#42d9e5")
	button.add_theme_stylebox_override("pressed", pressed)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#f3ddbb")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
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
	_pause_content.add_child(_pause_action("PERSONNALISER L'INTERFACE", Callable(self, "_open_hud_editor")))
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 10)
	secondary.add_child(_pause_action("RECOMMENCER", Callable(self, "_restart")))
	secondary.add_child(_pause_action("RETOUR AU MENU", Callable(self, "_return_menu")))
	_pause_content.add_child(secondary)

func _setup_hud_editor() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://prototype0_settings.cfg") == OK:
		_touch.call("set_control_scale", clampf(float(settings.get_value("settings", "touch_scale", 1.0)), 0.85, 1.15))
	_hud_controller = Node.new()
	_hud_controller.name = "HudLayoutController"
	_hud_controller.set_script(HUD_CONTROLLER)
	add_child(_hud_controller)
	_hud_controller.bind_touch(_touch)
	_hud_controller.register("wave", _hud.get_node("WavePanel"))
	_hud_controller.register("player_vitals", _vitals)
	_hud_controller.register("arrival", _arrival_label, true)
	_hud_controller.register("pause", _pause_button)
	_hud_controller.register("spell_bar", _spell_bar, true)
	for category in ["offensive", "defensive", "mobility"]:
		_hud_controller.register("%s_slot" % category, _spell_bar.get_node("%sSlot" % category.capitalize()))
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
	_pause_overlay.visible = false
	_pause_panel.visible = false
	_spell_bar.visible = true
	_vitals.call("set_example", true)
	_arrival_label.visible = _hud_controller == null or bool(_hud_controller.layout.arrival.v)
	_arrival_label.text = "VAGUE %d DANS 3.0 s" % maxi(1, wave)
	_hud_editor.begin(_hud_controller)

func _on_hud_editor_closed() -> void:
	_vitals.call("set_example", false)
	_pause_overlay.visible = true
	_pause_panel.visible = true
	_arrival_label.visible = false
	_spell_bar.visible = false
	_touch.visible = false
	get_tree().paused = true

func _on_hud_test_started() -> void:
	_set_combat_sound_state(false, true)
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
	for enemy in _enemies:
		if is_instance_valid(enemy):
			_editor_test_positions[enemy] = enemy.global_position
			_editor_test_modes[enemy] = enemy.process_mode
			enemy.global_position = Vector3(5000, 0, 5000)
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
	_editor_trial_player = CharacterBody3D.new()
	_editor_trial_player.name = "HudTrialPlayer"
	_editor_trial_player.set_script(PLAYER_SCRIPT)
	_editor_trial_player.position = player.global_position
	add_child(_editor_trial_player)
	_editor_trial_player.call("configure_survival_build", progression.build())
	_editor_trial_player.call("set_training_options", true, false, true)
	_editor_trial_player.call("set_gameplay_enabled", true)
	_editor_trial_target = StaticBody3D.new()
	_editor_trial_target.name = "HudTrialTarget"
	_editor_trial_target.set_script(TRIAL_DUMMY_SCRIPT)
	_editor_trial_target.position = _editor_trial_player.position + Vector3(5, 0, -5)
	add_child(_editor_trial_target)
	player = _editor_trial_player
	_touch.call("set_player", player)
	_vitals.call("set_player", player)
	_vitals.call("set_example", false)
	get_node("CameraRig").call("set_target", player)
	_arrival_label.visible = false
	get_tree().paused = false

func _on_hud_test_finished() -> void:
	_set_combat_sound_state(true, true)
	_touch.call("reset_inputs")
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
	_touch.call("set_player", player)
	_vitals.call("set_player", player)
	_vitals.call("set_example", true)
	player.visible = true
	player.process_mode = _editor_test_modes[player]
	get_node("CameraRig").call("set_target", player)
	for enemy in _editor_test_positions.keys():
		if is_instance_valid(enemy):
			enemy.global_position = _editor_test_positions[enemy]
			enemy.process_mode = _editor_test_modes[enemy]
	_editor_test_positions.clear()
	_editor_test_modes.clear()
	_arrival_label.visible = true
	_spell_bar.visible = true

func _show_weapon_choice() -> void:
	_state = "selection"
	_reward_overlay.visible = false
	_clear_choices()
	_choice_content.add_child(_label("SURVIE", 25, Color("#f3ddbb")))
	_choice_content.add_child(_label("12 vagues · Choisis une arme", 16, Color("#c7d2d1")))
	var records := RUN_STATS.read_records(records_path)
	var favorite: Dictionary = records.get("favorite_build", {})
	if not favorite.is_empty():
		var items := PackedStringArray()
		for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
			if str(favorite.get(category, "")) != "":
				items.append(LOADOUT.display_name(str(favorite[category])))
		var reference := _label("FAVORI · " + " / ".join(items), 12, Color("#efba6c"))
		reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_choice_content.add_child(reference)
	_choice_content.add_child(_label("Réparation : 100 PV après les vagues 3, 6 et 9. Kits : +80 PV dans l'arène.", 12, Color("#9dbab6")))
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
	_start_wave()

func _start_wave() -> void:
	_set_combat_sound_state(false, true)
	get_tree().paused = false
	_clear_enemies()
	wave += 1
	defeated = 0
	_state = "incoming"
	_play_music_for_wave(wave)
	_update_spell_bar(progression.build())
	_choice_panel.visible = false
	_touch.visible = false
	_arrival_remaining = 2.0
	_arrival_label.visible = _hud_controller == null or bool(_hud_controller.layout.arrival.v)
	_incoming_roles.clear()
	var count: int = [3, 3, 4, 4, 6, 6, 7, 7, 8, 8, 10, 10][wave - 1]
	for index in range(count):
		_incoming_roles.append(["chaser", "shooter", "charger"][(wave + index - 1) % 3])
	if wave == 12:
		_incoming_roles[count - 1] = "boss"
	var split := ceili(count * 0.5)
	_spawn_positions.clear()
	_reinforcement_positions.clear()
	for index in range(count):
		var point: Vector3 = SPAWN_POINTS[index] if index < 5 else Vector3(-15 + (index - 5) * 7, 0, 14)
		if point.distance_to(player.global_position) < 4.0:
			point = -point
		if index < split:
			_spawn_positions.append(point)
		else:
			_reinforcement_positions.append(point)
	_reinforcement_roles.assign(_incoming_roles.slice(split))
	_incoming_roles.resize(split)
	_create_arrival_markers(_spawn_positions, _incoming_roles)
	_reinforcement_remaining = 5.0
	if wave in [2, 5, 8, 11]:
		_create_repair()
	player.call("set_gameplay_enabled", false)

func _begin_wave_combat() -> void:
	if _state != "incoming":
		return
	for marker in _arrival_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_arrival_markers.clear()
	for index in range(_incoming_roles.size()):
		_spawn_enemy(_spawn_positions[index], _incoming_roles[index])
	_create_arrival_markers(_reinforcement_positions, _reinforcement_roles)
	_arrival_label.visible = not _reinforcement_roles.is_empty()
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
	var bot := enemy.get_node("TrainingBot")
	bot.set("survival_role", role)
	bot.set("training_attack_damage", 36.0 if role == "boss" else (15.0 if role == "charger" else 10.0 if role == "chaser" else 7.0) + 1.2 * float(wave))
	bot.set("training_attack_interval", 2.6 if role == "boss" else 3.2 if role == "charger" else 1.5 if role == "chaser" else 2.5)
	enemy.call("set_training_bot_enabled", true)
	readout.call("update_actor_identity", _role_color(role), _role_name(role))
	readout.call("set_blaster_charge", false, false, 0.0)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_enemies.append(enemy)
	state.damage_applied.connect(stats.record_damage)
	if wave in [3, 6, 9] and _enemies.size() == 1:
		var elite: String = {3: "double_charge", 6: "spread", 9: "shield"}[wave]
		bot.set("survival_elite", elite)
		bot.set("survival_role", {3: "charger", 6: "shooter", 9: "chaser"}[wave])
		enemy.set_meta("survival_elite", elite)
		state.max_health *= 1.35
		enemy.call("reset_combat_state")
		readout.call("update_actor_identity", Color("#ffe09a"), {3: "ÉLITE · DOUBLE CHARGE", 6: "ÉLITE · ÉVENTAIL", 9: "ÉLITE · BOUCLIER FRONTAL"}[wave])
		var crown := Label3D.new()
		crown.text = "ÉLITE"
		crown.font_size = 28
		crown.modulate = Color("#ffe09a")
		crown.position.y = 3.4
		crown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		enemy.add_child(crown)
		if elite == "shield":
			var shield := MeshInstance3D.new()
			shield.name = "EliteShield"
			var shield_mesh := BoxMesh.new()
			shield_mesh.size = Vector3(1.8, 1.7, 0.10)
			shield.mesh = shield_mesh
			shield.material_override = _material(Color("#60cde980"), true)
			enemy.add_child(shield)

func _on_enemy_died(enemy: StaticBody3D) -> void:
	if _state != "combat":
		return
	enemy.call("set_training_bot_enabled", false)
	if progression.evolutions.passive and progression.equipment.passive == "omnivamp":
		player.call("heal", 35.0, "omnivamp_kill")
	defeated += 1
	stats.kills += 1
	if defeated >= _enemies.size():
		call_deferred("_complete_wave")

func _complete_wave() -> void:
	if _state != "combat" or defeated < _enemies.size() or not _reinforcement_roles.is_empty():
		return
	player.call("set_gameplay_enabled", false)
	_touch.call("reset_inputs")
	if wave >= PROGRESSION.TOTAL_WAVES:
		_show_result(true)
		return
	_state = "reward"
	_set_combat_sound_state(true, true)
	_spell_bar.visible = false
	get_tree().paused = true
	_enter_reward_music()
	_choice_panel.visible = false
	_show_reward_choices()
	_touch.visible = false

func _choose_reward(choice: Dictionary) -> void:
	if _state != "reward" or not progression.apply_reward(wave, choice):
		return
	_reward_overlay.visible = false
	get_tree().paused = false
	_leave_reward_music()
	player.call("configure_survival_build", progression.build())
	if wave % 3 == 0:
		player.call("heal", 100.0, "wave_reward")
	_start_wave()

func _on_player_died() -> void:
	if _state == "combat":
		call_deferred("_show_result", false)

func _show_result(won: bool) -> void:
	if _state != "combat":
		return
	_state = "result"
	_set_combat_sound_state(true, true)
	_reward_overlay.visible = false
	_spell_bar.visible = false
	player.call("set_gameplay_enabled", false)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.call("set_training_bot_enabled", false)
	get_tree().paused = true
	_stop_all_music()
	_clear_choices()
	_choice_panel.visible = false
	_arrival_label.visible = false
	_synergy_label.visible = false
	_touch.visible = false
	if player.survival_synergies != null:
		player.survival_synergies.clear_effects()
	summary = SUMMARY.new()
	summary.records_path = records_path
	_ui_layer.add_child(summary)
	summary.present(stats.snapshot(won, wave, progression.build()))
	summary.replay_requested.connect(_restart)
	summary.menu_requested.connect(_return_menu)

func _total_defeated() -> int:
	return stats.kills

func _create_arrival_markers(points: Array[Vector3], roles: Array[String]) -> void:
	for index in range(points.size()):
		var marker := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.7 if roles[index] != "boss" else 1.3
		ring.outer_radius = ring.inner_radius + 0.2
		marker.mesh = ring
		marker.position = points[index] + Vector3.UP * 0.08
		marker.material_override = _material(_role_color(roles[index]), true)
		add_child(marker)
		_arrival_markers.append(marker)

func _spawn_reinforcements() -> void:
	if _state != "combat" or _reinforcement_roles.is_empty():
		return
	for index in range(_reinforcement_roles.size()):
		_spawn_enemy(_reinforcement_positions[index], _reinforcement_roles[index])
	_reinforcement_roles.clear()
	for marker in _arrival_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_arrival_markers.clear()
	_arrival_label.visible = false

func _create_repair() -> void:
	_repair = Node3D.new()
	_repair.name = "RepairPickup"
	add_child(_repair)
	_repair.position = Vector3(14 if wave % 2 == 0 else -14, 0, 7)
	var label := Label3D.new()
	label.text = "+80 PV"
	label.font_size = 40
	label.modulate = Color("#75ffad")
	label.position.y = 1.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_repair.add_child(label)
	for size in [Vector3(1.2, 0.12, 0.35), Vector3(0.35, 0.12, 1.2)]:
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		visual.mesh = mesh
		visual.position.y = 0.15
		visual.material_override = _material(Color("#75ffad"), true)
		_repair.add_child(visual)

func _pause_run() -> void:
	if _state != "combat":
		return
	_state = "pause"
	_pause_started_at_msec = Time.get_ticks_msec()
	_set_combat_sound_state(true)
	_spell_bar.visible = false
	get_tree().paused = true
	_music.stream_paused = true
	_other_music.stream_paused = true
	_reward_music.stream_paused = true
	_touch.call("reset_inputs")
	if player.has_method("reset_desktop_inputs"):
		player.call("reset_desktop_inputs")
	_show_pause_content()
	_pause_overlay.visible = true
	_pause_panel.visible = true
	_touch.visible = false

func _resume_run() -> void:
	if _state != "pause":
		return
	if _pause_started_at_msec >= 0:
		player.call("shift_pause_timers", float(Time.get_ticks_msec() - _pause_started_at_msec) / 1000.0)
		_pause_started_at_msec = -1
	_set_combat_sound_state(false)
	_state = "combat"
	_update_spell_bar(progression.build())
	get_tree().paused = false
	_music.stream_paused = false
	_other_music.stream_paused = false
	_reward_music.stream_paused = false
	_pause_overlay.visible = false
	_pause_panel.visible = false
	_touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

func _clear_enemies() -> void:
	_reinforcement_roles.clear()
	if is_instance_valid(_repair):
		_repair.queue_free()
	_repair = null
	if player.survival_synergies != null:
		player.survival_synergies.clear_effects()
	for marker in _arrival_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_arrival_markers.clear()
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()

func _restart() -> void:
	_set_combat_sound_state(false, true)
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/survival.tscn")

func _return_menu() -> void:
	_set_combat_sound_state(false, true)
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")

func _set_combat_sound_state(paused: bool, clear_voices: bool = false) -> void:
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null:
		if clear_voices:
			sfx.call("clear")
		sfx.call("set_paused", paused)

func _short_name(identifier: String) -> String:
	return LOADOUT.display_name(identifier) if identifier != "" else "—"

func _reward_description(choice: Dictionary) -> String:
	if str(choice.kind) != "item":
		return str(choice.description)
	return {
		"modulo_drone": "Tir guidé. Brûle et révèle la cible.",
		"javelin": "Lance un javelot. Réappui pour te téléporter.",
		"pelto_smash": "Vague de terre aller-retour. Ralentit puis tracte.",
		"magnetic_field": "Mur qui absorbe les tirs pendant 2,5 s.",
		"static_shield": "Invulnérable 1,5 s. Actions bloquées.",
		"pyro_boots": "Ruée de 3 m. Recharge : 6 s.",
		"bio_injector": "Vitesse et tirs accélérés pendant 3 s.",
		"baroud": "Survis brièvement à un coup fatal.",
		"omnivamp": "Soigne 15 % des dégâts infligés.",
	}.get(str(choice.id), str(choice.description))

func _reward_card_description(choice: Dictionary) -> String:
	var identifier := str(choice.id)
	match str(choice.kind):
		"item":
			return {
				"modulo_drone": "Envoie un drone sur l'ennemi visé et le brûle.",
				"javelin": "Lance un javelot. Réappuie sur A pour rejoindre la cible touchée.",
				"magnetic_field": "Pose un mur qui bloque les tirs ennemis.",
				"static_shield": "Te protège des dégâts, mais bloque tes actions un instant.",
				"pyro_boots": "Te propulse de quelques mètres dans ta direction.",
				"bio_injector": "Accélère tes déplacements et tes tirs un instant.",
				"baroud": "Après un coup fatal, tu peux encore te battre brièvement.",
				"omnivamp": "Tes dégâts te rendent de la vie.",
			}.get(identifier, _reward_description(choice))
		"evolution":
			return {
				"blaster": "Tirs renforcés. Ils traversent et touchent un second ennemi.",
				"shotgun": "Tirs renforcés. Deux projectiles de plus par tir.",
				"modulo_drone": "Drone renforcé. Il touche aussi un second ennemi.",
				"javelin": "Javelot renforcé. L'impact blesse les ennemis proches.",
				"magnetic_field": "Mur renforcé. Il électrocute les ennemis proches.",
				"static_shield": "Bouclier renforcé. À sa fin, il blesse les ennemis proches.",
				"pyro_boots": "Dash renforcé. Il laisse une traînée brûlante.",
				"bio_injector": "Bonus renforcé. L'activation blesse les ennemis proches.",
				"baroud": "Baroud renforcé. Son activation repousse les ennemis proches.",
				"omnivamp": "Vol de vie renforcé. Éliminer un ennemi te soigne aussi.",
			}.get(identifier, _reward_description(choice))
		"power":
			return {
				"blaster": "Tes tirs infligent davantage de dégâts.",
				"shotgun": "Tes tirs infligent davantage de dégâts.",
				"modulo_drone": "Ton drone frappe plus fort et brûle plus longtemps.",
				"javelin": "Ton javelot inflige davantage de dégâts.",
				"magnetic_field": "Ton mur reste actif plus longtemps.",
				"static_shield": "Ton bouclier reste actif plus longtemps.",
				"pyro_boots": "Ton dash va plus loin.",
				"bio_injector": "Tu te déplaces et tires encore plus vite.",
				"baroud": "Baroud te laisse plus de temps pour survivre.",
				"omnivamp": "Tes dégâts te rendent davantage de vie.",
			}.get(identifier, "Effet renforcé.")
		"tempo":
			if str(choice.category) == "passive":
				return "Tu gagnes plus de vie maximale."
			return "Tu tires plus souvent." if str(choice.category) == "weapon" else "Ce module se recharge plus vite."
	return _reward_description(choice)
