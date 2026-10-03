extends Control

signal replay_requested
signal menu_requested
const STATS := preload("res://scripts/survival_run_stats.gd")
const SYNERGIES := preload("res://scripts/survival_synergies.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const ASPECTS := preload("res://scripts/survival_aspects.gd")
const FONT: Font = preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const EQUIPMENT_ICONS := preload("res://scripts/equipment_icons.gd")
var _equipment_icons = EQUIPMENT_ICONS.new()
var records_path := STATS.RECORDS_PATH
var result: Dictionary
var records: Dictionary
var status: Label
var title: Label
var _exporting := false

func present(data: Dictionary) -> void:
	result = data
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_theme_font_override("font", FONT)
	var shade := ColorRect.new()
	shade.color = Color("#1b2023")
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	var won := bool(data.won)
	title = text("VICTOIRE · 12 VAGUES" if won else "FIN DE PARTIE · VAGUE %d" % int(data.wave), 30, Color("#8fe6aa") if won else Color("#f28a79"))
	content.add_child(title)
	records = STATS.read_records(records_path)
	var old_best := int(records.get("best_wave", 0))
	var best := maxi(old_best, int(data.completed_waves))
	records.best_wave = best
	records.last_run = data
	var saved := STATS.save_records(records, records_path)
	var seconds := int(data.elapsed)
	content.add_child(text("%02d:%02d de combat   ·   %d ennemis vaincus   ·   %d vagues terminées   ·   Record : %d/12" % [seconds / 60, seconds % 60, int(data.kills), int(data.completed_waves), best], 16))
	var total_damage := total(data.damage)
	content.add_child(text("%s dégâts infligés     %s soins reçus     %s dégâts subis" % [str(roundi(total_damage)), str(roundi(total(data.healing))), str(roundi(data.received))], 20, Color("#72d7e4")))
	content.add_child(HSeparator.new())
	content.add_child(text("BUILD FINAL", 19))
	var build: Dictionary = data.build
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		var id := str(build.get(category, ""))
		if id == "":
			continue
		var ranks: Dictionary = build.get("upgrades", {}).get(category, {})
		var evolution := ASPECTS.label(build, category)
		evolution = " · " + evolution if evolution != "" else ""
		var equipment_row := HBoxContainer.new()
		equipment_row.add_theme_constant_override("separation", 12)
		var icon := TextureRect.new()
		icon.texture = _equipment_icons.get_icon(id)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		equipment_row.add_child(icon)
		var equipment_label := text("%s%s   ·   Puissance %d / Rythme %d" % [LOADOUT.display_name(id), evolution, int(ranks.get("power", 0)), int(ranks.get("tempo", 0))], 15)
		equipment_label.size_flags_horizontal = SIZE_EXPAND_FILL
		equipment_label.size_flags_vertical = SIZE_SHRINK_CENTER
		equipment_row.add_child(equipment_label)
		content.add_child(equipment_row)
	var synergies := SYNERGIES.names(build)
	content.add_child(text("Synergies : " + (synergies if synergies != "" else "aucune activée"), 16, Color("#efba6c")))
	content.add_child(HSeparator.new())
	content.add_child(text("CONTRIBUTION DU BUILD · DÉGÂTS EFFECTIFS", 18))
	var keys: Array = data.damage.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(data.damage[a]) > float(data.damage[b]))
	for key in keys:
		var row := HBoxContainer.new()
		var label := text(STATS.label_for(str(key)), 14)
		label.custom_minimum_size.x = 250
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = SIZE_EXPAND_FILL
		bar.custom_minimum_size.y = 16
		bar.size_flags_vertical = SIZE_SHRINK_CENTER
		bar.show_percentage = false
		var track := StyleBoxFlat.new()
		track.bg_color = Color("#343d3e")
		track.border_color = Color("#7b6955")
		track.set_border_width_all(1)
		track.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", track)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("#42d9e5")
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.value = float(data.damage[key]) * 100.0 / maxf(1.0, total_damage)
		row.add_child(bar)
		var amount := text("%d  (%d %%)" % [roundi(data.damage[key]), roundi(bar.value)], 14)
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount.custom_minimum_size.x = 130
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)
		content.add_child(row)
	if keys.is_empty():
		content.add_child(text("Aucun dégât infligé.", 14))
	for key in data.healing:
		content.add_child(text("Soins · %s : %d PV" % [STATS.label_for(str(key)), roundi(data.healing[key])], 14, Color("#8fe6aa")))
	var actions := HFlowContainer.new()
	for entry in [["REJOUER", func() -> void: replay_requested.emit()], ["MENU", func() -> void: menu_requested.emit()], ["GARDER CE BUILD", _save_favorite], ["ENREGISTRER LA CARTE", _export_card]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(165, 42)
		_style_action(button)
		button.pressed.connect(entry[1])
		actions.add_child(button)
	layout.add_child(actions)
	status = text("Le favori conserve une référence du build ; les équipements restent à acquérir.", 12, Color("#acbcbf"))
	layout.add_child(status)
	if saved != OK:
		status.text = "Impossible de sauvegarder le record sur cet appareil."

func text(value: String, font_size: int, color: Color = Color("#f3e6d1")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func total(values: Dictionary) -> float:
	var result_total := 0.0
	for value in values.values():
		result_total += float(value)
	return result_total

func _save_favorite() -> void:
	records.favorite_build = result.build.duplicate(true)
	var saved := STATS.save_records(records, records_path) == OK
	status.text = "Build favori enregistré sur cet appareil." if saved else "Échec de l'enregistrement du favori."
	get_node("/root/UiSfx").play("confirmation" if saved else "denied")

func _export_card() -> void:
	if _exporting:
		return
	_exporting = true
	# Dedicated viewport exports the entire card, even when the screen is scrolled.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.size = viewport.size
	background.color = Color("#1b2023")
	viewport.add_child(background)
	var card := VBoxContainer.new()
	card.position = Vector2(48, 40)
	card.size = Vector2(1104, 770)
	card.add_theme_font_override("font", FONT)
	card.add_theme_constant_override("separation", 22)
	viewport.add_child(card)
	card.add_child(text("PROTOTYPE · SURVIE", 24, Color("#72d7e4")))
	card.add_child(text(title.text, 36))
	card.add_child(text("%d vagues terminées · %d éliminations · %02d:%02d" % [int(result.completed_waves), int(result.kills), int(result.elapsed) / 60, int(result.elapsed) % 60], 24))
	card.add_child(text("%d dégâts · %d soins" % [roundi(total(result.damage)), roundi(total(result.healing))], 24))
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		var id := str(result.build.get(category, ""))
		if id != "":
			var aspect := ASPECTS.label(result.build, category)
			card.add_child(text(LOADOUT.display_name(id) + (" · " + aspect if aspect != "" else ""), 22))
	card.add_child(text(SYNERGIES.names(result.build), 24, Color("#efba6c")))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "user://survie-%d.png" % Time.get_unix_time_from_system()
	var error := viewport.get_texture().get_image().save_png(path)
	viewport.queue_free()
	_exporting = false
	status.text = "Carte enregistrée : " + ProjectSettings.globalize_path(path) if error == OK else "Échec de l'export de la carte."
	get_node("/root/UiSfx").play("confirmation" if error == OK else "denied")

func _style_action(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#30383b") if state == "normal" else Color("#45443d") if state == "hover" else Color("#252b2e")
		style.border_color = Color("#f3ddbb") if state == "focus" else Color("#efb765") if state == "hover" else Color("#86745f")
		style.set_border_width_all(2 if state == "focus" else 1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 12
		style.content_margin_right = 12
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color("#f3ddbb"))
