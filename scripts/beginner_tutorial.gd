extends "res://scripts/training_ground.gd"

## Isolated introduction using real training actors and combat observations.
## Never writes the player's build, preferences or advanced challenge progress.
const LESSONS := ["SE DÉPLACER", "VISER ET TIRER", "CHARGER UN TIR", "ESQUIVER", "MODULE OFFENSIF", "SE PROTÉGER"]
const START := Vector3(0, 0, 20)
const DESTINATION := Vector3(4, 0, 20)
var lesson := 0
var lesson_completed := false
var tutorial_paused := false
var _hits := 0
var _shield_seen := false
var _dash_seen := false
var _lesson_target: StaticBody3D
var _destination_marker: MeshInstance3D
var _tutorial_root: Control
var _lesson_panel: PanelContainer
var _lesson_title: Label
var _lesson_body: Label
var _lesson_progress: Label
var _next_button: Button
var _retry_button: Button
var _pause_button: Button
var _exit_button: Button
var _summary: ColorRect

func _ready() -> void:
	super._ready()
	_challenges.hide()
	for identifier in ["training_status", "training_reset", "training_menu", "passive_slot"]:
		_hud_controller.controls.erase(identifier)
	_spell_bar.get_node("PassiveSlot").hide()
	_meter.hide()
	_meter_toggle_button.hide()
	_status.get_parent().get_child(0).hide() # Training-only header plate.
	_status.hide()
	_reset_button.hide()
	_training_menu_button.hide()
	_feedback._notice.position.y = 240
	_options = {"invulnerable": true, "instant_cooldowns": false, "unlimited_ammo": true}
	_apply_options()
	_lesson_target = _fixed_targets[1]
	for dummy in get_training_targets():
		dummy.combat_state.damage_applied.connect(_on_tutorial_hit.bind(dummy))
	_build_tutorial_ui()
	_destination_marker = MeshInstance3D.new()
	_destination_marker.name = "TutorialDestination"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.05
	_destination_marker.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = CYAN
	material.emission_enabled = true
	material.emission = CYAN
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_destination_marker.material_override = material
	add_child(_destination_marker)
	_destination_marker.position = DESTINATION + Vector3.UP * 0.12
	get_viewport().size_changed.connect(_layout_tutorial)
	get_node("/root/GamePreferences").bindings_changed.connect(_refresh_lesson)
	_start_lesson(0)
	_layout_tutorial.call_deferred()

func _apply_loadout() -> void:
	# Called by the training bootstrap too: no save_local or Garage draft writes.
	_loadout = LOADOUT.defaults()
	_loadout.defensive = "static_shield"
	_loadout.passive = "auxiliary_reactor"
	player.apply_loadout(_loadout)
	_update_spell_bar()

func _build_tutorial_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TutorialLayer"
	layer.layer = 6
	add_child(layer)
	_tutorial_root = Control.new()
	_tutorial_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tutorial_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_tutorial_root)
	_lesson_panel = PanelContainer.new()
	_lesson_panel.name = "TutorialInstruction"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#14232bf2")
	style.border_color = CYAN
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	_lesson_panel.add_theme_stylebox_override("panel", style)
	_tutorial_root.add_child(_lesson_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_lesson_panel.add_child(column)
	_lesson_title = _label("", 23)
	column.add_child(_lesson_title)
	_lesson_body = _label("", 16)
	_lesson_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lesson_body.custom_minimum_size.y = 48
	column.add_child(_lesson_body)
	_lesson_progress = _label("", 16)
	_lesson_progress.add_theme_color_override("font_color", CYAN)
	column.add_child(_lesson_progress)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	_retry_button = _button("REFAIRE", _restart_lesson, "secondary", 42)
	actions.add_child(_retry_button)
	_pause_button = _button("PAUSE", _toggle_menu, "secondary", 42)
	actions.add_child(_pause_button)
	_exit_button = _button("ACCUEIL", _return_to_main_menu, "secondary", 42)
	actions.add_child(_exit_button)
	_next_button = _button("SUIVANT", _next_lesson, "primary", 42)
	_next_button.name = "TutorialNext"
	actions.add_child(_next_button)
	for button in [_retry_button, _pause_button, _exit_button, _next_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
	_summary = ColorRect.new()
	_summary.name = "TutorialSummary"
	_summary.color = Color("#081016ed")
	_summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary.hide()
	_tutorial_root.add_child(_summary)
	var summary_column := VBoxContainer.new()
	summary_column.name = "SummaryContent"
	summary_column.add_theme_constant_override("separation", 16)
	_summary.add_child(summary_column)
	summary_column.add_child(_label("TUTORIEL TERMINÉ", 30))
	var summary_body := _label("Déplacement, tir, charge, esquive et modules : tu as les bases !\n\nAu Garage, choisis ton arme et tes trois modules. En combat, surveille tes PV et les temps de recharge en bas de l’écran.\n\nContinue à ton rythme en entraînement libre, puis essaie un duel solo.", 18)
	summary_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_column.add_child(summary_body)
	summary_column.add_child(_button("ENTRAÎNEMENT LIBRE", _open_free_training, "primary", 50))
	summary_column.add_child(_button("RECOMMENCER LE TUTORIEL", _start_lesson.bind(0), "secondary", 46))
	summary_column.add_child(_button("RETOUR À L’ACCUEIL", _return_to_main_menu, "secondary", 46))
	_layout_tutorial()

func _layout_tutorial() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(760, viewport_size.x - 24)
	# Scale for landscape phones while retaining readable desktop text.
	var factor := minf(1, minf(width / 760, viewport_size.y / 500))
	_lesson_panel.size = Vector2(760, 210)
	_lesson_panel.scale = Vector2.ONE * factor
	_lesson_panel.position = Vector2((viewport_size.x - 760 * factor) * 0.5, 12)
	var content: Control = _summary.get_node("SummaryContent")
	content.size = Vector2(660, 420)
	var summary_factor := minf(1, minf((viewport_size.x - 32) / 660, (viewport_size.y - 32) / 420))
	content.scale = Vector2.ONE * summary_factor
	content.position = (viewport_size - Vector2(660, 420) * summary_factor) * 0.5
	get_node("CameraRig").set_follow_offset(Vector3(0, 0, -3.5 if viewport_size.y < 500 else -2.5), true)

func _start_lesson(index: int) -> void:
	get_tree().paused = false
	tutorial_paused = false
	_menu_opened_at_msec = 0
	_set_combat_sound_state(false, true)
	lesson = clampi(index, 0, LESSONS.size() - 1)
	lesson_completed = false
	_hits = 0
	_shield_seen = false
	_dash_seen = false
	_summary.hide()
	_lesson_panel.show()
	_reset_trial(true)
	_apply_loadout()
	player.global_position = START
	player._set_aim_direction(Vector3.FORWARD)
	player.set_gameplay_enabled(true)
	_lesson_target = _shooter_target if lesson == 5 else _fixed_targets[1]
	for dummy in get_training_targets():
		var selected := dummy == _lesson_target and lesson in [1, 2, 4, 5]
		dummy.visible = selected
		dummy.collision_layer = 2 if selected else 0
		dummy.process_mode = Node.PROCESS_MODE_PAUSABLE if selected else Node.PROCESS_MODE_DISABLED
		dummy.set_training_bot_enabled(selected and lesson == 5)
		(dummy.get_node("TrainingRespawnTimer") as Timer).stop()
	_lesson_target.global_position = Vector3(0, 0, 16.5)
	_lesson_target.training_origin = _lesson_target.global_position
	_lesson_target.combat_state.max_health = 5000
	_lesson_target.reset_combat_state()
	_destination_marker.visible = lesson == 0
	get_node("CameraRig").set_target(player)
	_feedback.reset_round()
	_update_spell_bar()
	_update_touch_visibility()
	_refresh_lesson()

func _restart_lesson() -> void:
	_start_lesson(lesson)

func _key(action: String) -> String:
	return get_node("/root/GamePreferences").key_label(action)

func _refresh_lesson() -> void:
	if _lesson_title == null:
		return
	var touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_lesson_title.text = "%d / %d  ·  %s" % [lesson + 1, LESSONS.size(), LESSONS[lesson]]
	var movement := "Joystick gauche" if touch else "%s / %s / %s / %s" % [_key("move_up"), _key("move_left"), _key("move_down"), _key("move_right")]
	var fire := "le joystick de tir à droite" if touch else "clic gauche ou " + _key("attack")
	var offensive := "le bouton offensif" if touch else _key("offensive")
	var defensive := "le bouton défensif" if touch else _key("defensive")
	var mobility := "le bouton mobilité" if touch else _key("mobility")
	var instructions := [
		"%s : rejoins le cercle cyan. Ici, tu peux apprendre sans perdre de PV." % movement,
		"%s. Vise le mannequin %s, puis touche-le deux fois." % [fire, "avec le joystick droit" if touch else "avec la souris"],
		"Maintiens %s jusqu’au signal de charge, puis relâche pour toucher le mannequin avec un tir puissant." % fire,
		"Déplace-toi, puis utilise %s : les Pyroboots font une esquive dans ta direction de déplacement." % mobility,
		"Vise le mannequin, maintiens puis relâche %s pour lancer le Javelin. Il faut toucher la cible." % offensive,
		"Utilise %s : Static Shield te protège mais t’immobilise. Attends la fin de la coque pour reprendre le combat." % defensive,
	]
	_lesson_body.text = instructions[lesson]
	_lesson_progress.text = "✓ RÉUSSI · Passe à la suite quand tu es prêt." if lesson_completed else "OBJECTIF : " + ["Rejoindre le cercle", "Touches : %d / 2" % _hits, "Réussir un impact chargé", "Effectuer une esquive", "Toucher au Javelin", "Activer la protection, puis en sortir"][lesson]
	if tutorial_paused:
		_lesson_progress.text = "EN PAUSE · Reprends quand tu es prêt."
	_pause_button.text = "REPRENDRE" if tutorial_paused else "PAUSE"
	_next_button.text = "TERMINER" if lesson == LESSONS.size() - 1 else "SUIVANT"
	_next_button.disabled = not lesson_completed or tutorial_paused

func _process(delta: float) -> void:
	super._process(delta)
	if _lesson_title == null or tutorial_paused or _summary.visible:
		return
	# A weapon-cycle input must not leave the exercise impossible to complete.
	if player._weapon_id != "blaster":
		_apply_loadout()
	if lesson_completed:
		return
	if lesson == 0 and player.global_position.distance_to(DESTINATION) < 1.15:
		_complete_lesson()
	elif lesson == 3:
		if player.is_dash_active():
			_dash_seen = true
		elif _dash_seen:
			_complete_lesson()
	elif lesson == 5:
		if player.get_stasis_remaining() > 0:
			_shield_seen = true
		elif _shield_seen:
			_complete_lesson()

func _on_tutorial_hit(amount: float, source: String, attack: String, dummy: StaticBody3D) -> void:
	if tutorial_paused or lesson_completed or dummy != _lesson_target or not source.begins_with("player") or amount <= 0:
		return
	if lesson == 1 and attack.begins_with("blaster:"):
		_hits += 1
		if _hits >= 2:
			_complete_lesson()
		else:
			_refresh_lesson()
	elif lesson == 2 and attack.begins_with("blaster:") and amount >= player._blaster_max_damage * 0.85:
		_complete_lesson()
	elif lesson == 4 and attack.begins_with("javelin:"):
		_complete_lesson()

func _complete_lesson() -> void:
	lesson_completed = true
	_destination_marker.hide()
	_refresh_lesson()

func _next_lesson() -> void:
	if not lesson_completed or tutorial_paused:
		return
	if lesson < LESSONS.size() - 1:
		_start_lesson(lesson + 1)
	else:
		player.set_gameplay_enabled(false)
		get_tree().paused = true
		_set_combat_sound_state(true, true)
		_lesson_panel.hide()
		_summary.show()
		_layout_tutorial.call_deferred()
		_update_touch_visibility()

func _toggle_menu() -> void:
	if _summary != null and _summary.visible:
		_return_to_main_menu()
		return
	tutorial_paused = not tutorial_paused
	if tutorial_paused:
		_menu_opened_at_msec = Time.get_ticks_msec()
	elif _menu_opened_at_msec > 0:
		player.shift_pause_timers(float(Time.get_ticks_msec() - _menu_opened_at_msec) / 1000)
		_menu_opened_at_msec = 0
	get_tree().paused = tutorial_paused
	player.set_gameplay_enabled(not tutorial_paused)
	_set_combat_sound_state(tutorial_paused)
	_update_touch_visibility()
	_refresh_lesson()

func _update_touch_visibility() -> void:
	if _touch_controls != null:
		_touch_controls.visible = (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")) and not tutorial_paused and not _summary.visible

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_TAB]:
			_toggle_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F5 and not _summary.visible:
			_restart_lesson()
			get_viewport().set_input_as_handled()

func _open_free_training() -> void:
	get_tree().paused = false
	_set_combat_sound_state(false, true)
	get_tree().change_scene_to_file("res://scenes/training_ground.tscn")
