extends Control

const PREFS := preload("res://scripts/review_preferences.gd")
const DATA := preload("res://scripts/combat_data.gd")
const TITLES := {"counter": "PARADE", "javelin": "MARQUE ET REPOSITIONNEMENT", "fulguro_punch": "ÉCRASEMENT MURAL"}
var ground: Node3D
var feedback: Control
var active := ""
var completed := false
var _snapshot: Dictionary = {}
var _chooser: ColorRect
var _instruction: PanelContainer
var _text: Label
var _temporary_target: StaticBody3D

func configure(owner: Node3D, observer: Control) -> void:
	ground = owner
	feedback = observer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	feedback.action_observed.connect(_observed)
	_chooser = ColorRect.new()
	_chooser.color = Color("#081016d9")
	_chooser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_chooser)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-310, -200)
	panel.custom_minimum_size = Vector2(620, 390)
	panel.add_theme_stylebox_override("panel", _style())
	_chooser.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(_label("DÉFIS GUIDÉS", 27))
	column.add_child(_label("Trois gestes à réussir. Build temporaire, sauvegarde conservée.", 15))
	var values := PREFS.read()
	for id in TITLES:
		var suffix := " · RÉUSSI" if id in values.challenges else ""
		column.add_child(_button(str(TITLES[id]) + suffix, start.bind(str(id))))
	column.add_child(_button("RETOUR", func() -> void: _chooser.hide()))
	_chooser.hide()
	_instruction = PanelContainer.new()
	_instruction.name = "ChallengeInstruction"
	_instruction.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_instruction.position = Vector2(-340, 78)
	_instruction.custom_minimum_size = Vector2(600, 90)
	_instruction.add_theme_stylebox_override("panel", _style())
	add_child(_instruction)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_instruction.add_child(row)
	_text = _label("", 15)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.x = 330
	row.add_child(_text)
	row.add_child(_button("REFAIRE", retry))
	row.add_child(_button("QUITTER", stop))
	_instruction.hide()

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#14232bf2")
	style.border_color = Color("#73dfe3")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	return style

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#f3ddbb"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 42
	button.pressed.connect(callback)
	return button

func open() -> void:
	var values := PREFS.read()
	var column: VBoxContainer = _chooser.get_child(0).get_child(0)
	for index in TITLES.size():
		var id: String = TITLES.keys()[index]
		(column.get_child(index + 2) as Button).text = str(TITLES[id]) + (" · RÉUSSI" if id in values.challenges else "")
	_chooser.show()
	(_chooser.get_child(0).get_child(0).get_child(2) as Button).grab_focus()

func close_chooser() -> bool:
	if not _chooser.visible:
		return false
	_chooser.hide()
	return true

func start(id: String) -> void:
	if not TITLES.has(id):
		return
	if active != "":
		stop()
	var player: Node3D = ground.player
	var target: Node3D = ground._shooter_target
	if id != "counter":
		if ground._fixed_targets.is_empty():
			_temporary_target = ground._spawn_dummy("fixed", Vector3(-20, 0, -11), 1.0)
			target = _temporary_target
		else:
			target = ground._fixed_targets[mini(1, ground._fixed_targets.size() - 1)]
	_snapshot = {"loadout": ground._loadout.duplicate(true), "options": ground._options.duplicate(true), "position": player.global_position, "aim": player.aim_direction, "targets": []}
	for observed in ground.get_training_targets():
		_snapshot.targets.append({"actor": observed, "position": observed.global_position, "origin": observed.training_origin, "layer": observed.collision_layer, "mode": observed.process_mode, "visible": observed.visible, "health": observed.combat_state.max_health})
	active = id
	completed = false
	_chooser.hide()
	if ground._menu.visible:
		ground._toggle_menu()
	ground._reset_trial(true)
	var build: Dictionary = PREFS.PRESETS["TECHNIQUE"].duplicate(true)
	build.weapon = "blaster"
	build.offensive = "fulguro_punch" if id == "fulguro_punch" else "javelin"
	player.apply_loadout(build)
	player.set_training_options(true, true, true)
	for entry in _snapshot.targets:
		if entry.actor != target:
			entry.actor.process_mode = Node.PROCESS_MODE_DISABLED
			entry.actor.collision_layer = 0
			entry.actor.visible = false
	target.combat_state.max_health = 5000.0
	target.reset_combat_state()
	if id == "counter":
		player.global_position = Vector3(24, 0, -5)
		target.global_position = Vector3(24, 0, -11)
		_text.text = "PARADE\nAttends le tir, puis active le module défensif."
	elif id == "javelin":
		player.global_position = Vector3(-20, 0, -5)
		target.global_position = Vector3(-20, 0, -11)
		_text.text = "MARQUE ET REPOSITIONNEMENT\nTouche au Javelin, puis réactive le module offensif."
	else:
		player.global_position = Vector3(-24, 0, -33)
		target.global_position = Vector3(-24, 0, -35.4)
		_text.text = "ÉCRASEMENT MURAL\nVise vers le mur et charge Fulguro Punch."
	target.training_origin = target.global_position
	player._set_aim_direction(Vector3.FORWARD)
	ground.get_node("CameraRig").set_target(player)
	feedback.reset_round()
	_instruction.show()

func _process(_delta: float) -> void:
	_instruction.visible = active != "" and not ground._menu.visible and not ground.get_tree().paused

func _observed(id: String) -> void:
	if active == "" or completed or id != active:
		return
	completed = true
	var unlocked := PREFS.unlock("challenge", id)
	_text.text = "✓ DÉFI RÉUSSI\nTu peux refaire le geste ou revenir au laboratoire."
	if "technicien" in unlocked:
		_text.text = "✓ DÉFI RÉUSSI\nBannière TECHNICIEN débloquée !"

func retry() -> void:
	var id := active
	stop()
	if id != "":
		start(id)

func stop() -> void:
	if active == "":
		return
	active = ""
	completed = false
	for entry in _snapshot.targets:
		if is_instance_valid(entry.actor):
			entry.actor.global_position = entry.position
			entry.actor.training_origin = entry.origin
			entry.actor.collision_layer = entry.layer
			entry.actor.process_mode = entry.mode
			entry.actor.visible = entry.visible
			entry.actor.combat_state.max_health = entry.health
	ground._options = _snapshot.options
	ground.player.apply_loadout(_snapshot.loadout)
	ground._apply_options()
	ground._reset_trial()
	ground.player.global_position = _snapshot.position
	ground.player._set_aim_direction(_snapshot.aim)
	ground.get_node("CameraRig").set_target(ground.player)
	if is_instance_valid(_temporary_target):
		ground._meter.unregister_target(_temporary_target)
		ground._fixed_targets.erase(_temporary_target)
		_temporary_target.queue_free()
		_temporary_target = null
	_snapshot.clear()
	_instruction.hide()
	feedback.reset_round()
