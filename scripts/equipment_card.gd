extends Button

## Tooltip shared by every loadout card. Its text comes from loadout_state.gd.

func _make_custom_tooltip(for_text: String) -> Object:
	var lines := for_text.split("\n")
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#211e20")
	style.border_color = Color("#42d9e5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	for index in range(lines.size()):
		if lines[index].is_empty():
			continue
		var label := Label.new()
		label.text = lines[index]
		label.custom_minimum_size.x = 300
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16 if index == 0 else 13)
		label.add_theme_color_override("font_color", Color("#f3ddbb") if index != 2 else Color("#42d9e5"))
		content.add_child(label)
	return panel
