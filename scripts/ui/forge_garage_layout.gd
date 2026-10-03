extends RefCounted

## Layout in readable interface units. Compact windows use successive views;
## desktop windows keep the catalog alongside the equipment detail.
static func safe_rect(garage) -> Rect2:
	var full := Rect2(Vector2.ZERO, garage.size)
	if garage.safe_area_override.has_area():
		return full.intersection(garage.safe_area_override)
	if OS.has_feature("mobile"):
		var display := DisplayServer.get_display_safe_area()
		var window := DisplayServer.window_get_size()
		if display.size.x > 0 and display.size.y > 0 and window.x > 0 and window.y > 0:
			return full.intersection(Rect2(Vector2(display.position) * full.size / Vector2(window), Vector2(display.size) * full.size / Vector2(window)))
	return full


static func place(control: Control, position: Vector2, dimensions: Vector2) -> void:
	control.position = position
	control.size = dimensions


static func apply(g) -> void:
	var safe := safe_rect(g)
	var window: Vector2 = Vector2(g.get_window().size)
	g._compact_layout = OS.has_feature("mobile") or window.x < 1050 or window.y < 600
	var unit: float = minf(g.size.y / 390.0, g.size.x / 600.0) if g._compact_layout else minf(1.25, minf(g.size.x / 1280.0, g.size.y / 720.0))
	unit = maxf(unit, 0.01)
	g._ui.scale = Vector2.ONE * unit
	g._ui.position = safe.position
	g._ui.size = safe.size / unit
	var w: float = g._ui.size.x
	var h: float = g._ui.size.y
	var compact: bool = g._compact_layout
	if not compact and g._view == "detail":
		g._view = "catalog"
	var hub: bool = g._view == "hub"
	var builds: bool = g._view == "builds"
	var catalog: bool = g._view == "catalog"
	var detail: bool = g._view == "detail" or (catalog and not compact)
	place(g._header, Vector2.ZERO, Vector2(w, 64))
	place(g._back_button, Vector2(12, 8), Vector2(48, 48))
	g._back_button.add_theme_font_size_override("font_size", 26)
	place(g._header_title, Vector2(76, 10), Vector2(w - 290, 46))
	g._header_title.add_theme_font_size_override("font_size", 26 if compact else 34)
	g._header_title.text = "GARAGE" if hub else ("MES BUILDS" if builds else ("CHÂSSIS" if g._category == "robot" else ("ARMES" if g._category == "weapon" else (g.LOADOUT.display_name(g._preview_id) if g._view == "detail" else "MODULES"))))
	if g._view == "detail":
		g._header_title.add_theme_font_size_override("font_size", 22)
		g._header_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	g._save_state.visible = hub or builds
	place(g._save_state, Vector2(w - 218, 23), Vector2(200, 26))
	g._family_selector.visible = catalog
	place(g._family_selector, Vector2(w - 230, 8), Vector2(218, 48))
	for index in g._family_selector.item_count:
		if str(g._family_selector.get_item_metadata(index)) == g._category:
			g._family_selector.select(index)
	g._family_selector.get_popup().add_theme_font_size_override("font_size", 18)
	g._family_selector.get_popup().add_theme_constant_override("v_separation", 20)
	g._module_panel.hide()
	for button in g.module_buttons.values():
		button.hide()
	for button in g.arena_buttons.values():
		button.hide()
	g._hub_caption.visible = hub
	place(g._hub_caption, Vector2(24, 79), Vector2(240, 30))
	g._hub_caption.add_theme_font_size_override("font_size", 16 if compact else 20)
	var sidebar: float = 144.0 if compact else 220.0
	var card_h: float = maxf(64.0, (h - 208.0) / 3.0) if compact else minf(160.0, (h - 240.0) / 3.0)
	for index in 3:
		var title: String = ["ARMES", "MODULES", "MES BUILDS"][index]
		var button: Button = g._nav[title]
		button.visible = hub
		place(button, Vector2(20, 114 + index * (card_h + 10)), Vector2(sidebar, card_h))
		place(button.get_node("HubIcon"), Vector2(20, 6), Vector2(sidebar - 40, card_h - 35))
		place(button.get_node("HubTitle"), Vector2(5, card_h - 30), Vector2(sidebar - 10, 24))
		button.get_node("HubTitle").add_theme_font_size_override("font_size", 14 if compact else 18)
	g._footer.visible = hub or builds
	place(g._footer, Vector2(0, h - 72), Vector2(w, 72))
	g._test_button.visible = hub
	g._save_button.visible = hub
	place(g._test_button, Vector2(w - 332, h - 60), Vector2(126, 48))
	place(g._save_button, Vector2(w - 194, h - 60), Vector2(182, 48))
	place(g._status, Vector2(20, h - 57), Vector2(maxf(200, w - 366), 45))
	g._status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g._stats_panel.visible = hub
	place(g._stats_panel, Vector2(sidebar + 60, h - 112), Vector2(w - sidebar - 88, 30))
	g._stats_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	place(g._stat_name, Vector2.ZERO, g._stats_panel.size)
	g._stat_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._health.hide()
	g._speed.hide()
	g._catalog_title.visible = catalog
	g._catalog_title.text = "Choisis un châssis" if g._category == "robot" else ("Choisis une arme" if g._category == "weapon" else "Choisis un module")
	place(g._catalog_title, Vector2(20, 76), Vector2(320, 26))
	var left: float = w - 40.0 if compact else (w - 48.0) * 0.43
	var cols: int = 3 if compact and g._options(g._category).size() != 4 else 2
	var rows: int = ceili(float(g._options(g._category).size()) / cols)
	var available_h: float = h - 120.0
	var cell := Vector2((left - (cols - 1) * 12) / cols, minf(220, (available_h - (rows - 1) * 12) / rows))
	for kind in g._grids:
		var grid: GridContainer = g._grids[kind]
		grid.visible = catalog and kind == g._category
		if kind != g._category:
			continue
		grid.columns = cols
		for button: Button in g._choices[kind].values():
			button.custom_minimum_size = cell
			place(button.get_node("EquipmentIcon"), Vector2(12, 10), Vector2(cell.x - 24, maxf(30, cell.y - (45 if compact else 70))))
			place(button.get_node("CardTitle"), Vector2(6, cell.y - (32 if compact else 54)), Vector2(cell.x - 12, 26))
			button.get_node("CardTitle").add_theme_font_size_override("font_size", 14 if compact else 17)
			button.get_node("CardTag").visible = not compact
			place(button.get_node("CardTag"), Vector2(6, cell.y - 28), Vector2(cell.x - 12, 24))
			place(button.get_node("Selected"), Vector2(cell.x - 29, 7), Vector2(24, 26))
		place(grid, Vector2(20, 110), Vector2(left, cell.y * rows + (rows - 1) * 12))
		grid.queue_sort()
	g._detail_panel.visible = detail
	if detail:
		var panel_w: float = minf(w * 0.47, 370.0) if compact else w - left - 60.0
		var panel_h: float = h - 88.0 if compact else minf(310.0, h * 0.43)
		place(g._detail_panel, Vector2(w - panel_w - 20, 76 if compact else h - panel_h - 20), Vector2(panel_w, panel_h))
		place(g._detail_icon, Vector2(panel_w - 66, 12), Vector2(50, 50))
		place(g._detail_title, Vector2(16, 12), Vector2(panel_w - 94, 50))
		g._detail_title.add_theme_font_size_override("font_size", 20 if compact else 26)
		var scroll: ScrollContainer = g._detail_description.get_parent()
		place(scroll, Vector2(16, 72), Vector2(panel_w - 32, maxf(48, panel_h - (190 if compact else 195))))
		if compact and g._category == "robot":
			scroll.size.y = panel_h - 88
		g._detail_description.text = g.LOADOUT.category_description(g._preview_id)
		if compact:
			g._detail_description.text += "\n\n" + g.LOADOUT.stat_line(g._preview_id)
		g._detail_description.custom_minimum_size = Vector2(panel_w - 48, 0)
		g._detail_description.add_theme_font_size_override("font_size", 16 if compact else 17)
		g._detail_stats.visible = not compact
		place(g._detail_stats, Vector2(16, panel_h - 120), Vector2(panel_w - 32, 40))
		g.equip_button.visible = g._category != "robot"
		g._demo_button.visible = g._category != "robot"
		if compact:
			place(g._demo_button, Vector2(16, panel_h - 112), Vector2(panel_w - 32, 48))
			place(g.equip_button, Vector2(16, panel_h - 56), Vector2(panel_w - 32, 48))
		else:
			place(g.equip_button, Vector2(16, panel_h - 66), Vector2((panel_w - 44) * 0.5, 50))
			place(g._demo_button, Vector2(28 + (panel_w - 44) * 0.5, panel_h - 66), Vector2((panel_w - 44) * 0.5, 50))
		g._ui.set_meta("preview_rect", Rect2(20 if compact else left + 40, 80, w - panel_w - 60 if compact else panel_w, h - 104 if compact else h - panel_h - 110))
	else:
		g.equip_button.hide()
		g._demo_button.hide()
		g._ui.set_meta("preview_rect", Rect2(sidebar + 56, 76, w - sidebar - 84, maxf(100, h - (182 if compact else 210))) if hub else Rect2(20, 80, w - 40, h - 100))
	g._ui.set_meta("garage_hero", hub or builds)
	g._ui.set_meta("garage_hero_compact", compact)
	g._builds_panel.visible = builds
	if builds:
		layout_builds(g, w, h, compact)
	var rename_w: float = minf(460, w - 40)
	place(g._rename_panel, Vector2((w - rename_w) * 0.5, (h - 86) * 0.5), Vector2(rename_w, 86))
	place(g._name_input, Vector2(12, 18), Vector2(rename_w - 84, 48))
	place(g._rename_panel.get_child(1), Vector2(rename_w - 60, 18), Vector2(48, 48))
	for overlay: Control in [g._cinema, g._installation_controls]:
		if overlay == null:
			continue
		overlay.scale = g._ui.scale
		overlay.position = g._ui.position
		overlay.size = g._ui.size
	if g._cinema != null:
		place(g._cinema.get_child(0), Vector2.ZERO, Vector2(w, 60))
		place(g._cinema.get_child(1), Vector2(0, h - 76), Vector2(w, 76))
		place(g._cinema_title, Vector2(16, 16), Vector2(w - 32, 30))
		g._cinema_title.add_theme_font_size_override("font_size", 16 if compact else 20)
		place(g._cinema_phase, Vector2(16, h - 61), Vector2(w - 225, 30))
		g._cinema_phase.add_theme_font_size_override("font_size", 14 if compact else 18)
		place(g._cinema_progress, Vector2(16, h - 12), Vector2(w - 32, 3))
		place(g._cinema.get_child(g._cinema.get_child_count() - 1), Vector2(w - 204, h - 64), Vector2(188, 48))
	if g._installation_controls != null:
		place(g._installation_status, Vector2(20, h - 61), Vector2(w - 225, 35))
		place(g._installation_controls.get_node("SkipInstallation"), Vector2(w - 204, h - 64), Vector2(188, 48))


static func layout_builds(g, w: float, h: float, compact: bool) -> void:
	var panel_w: float = w - 40 if compact else minf(550, w * 0.48)
	var panel_h: float = h - 98 if compact else h - 115
	place(g._builds_panel, Vector2(20, 78), Vector2(panel_w, panel_h))
	g._builds_title.visible = not compact
	place(g._builds_title, Vector2(18, 15), Vector2(panel_w - 36, 32))
	var y: float = 12 if compact else 62
	place(g._build_selector, Vector2(18, y), Vector2(panel_w - 36, 48))
	y += 60
	g._arena_selector.visible = g._arena_enabled
	if compact:
		place(g._presets, Vector2(18, y), Vector2((panel_w - 48) * 0.5 if g._arena_enabled else panel_w - 36, 48))
		place(g._arena_selector, Vector2(panel_w * 0.5 + 6, y), Vector2((panel_w - 48) * 0.5, 48))
		y += 60
		for index in 4:
			place(g._build_actions[index], Vector2(18 + index * (panel_w - 24) / 4, y), Vector2((panel_w - 60) / 4, 48))
			g._build_actions[index].add_theme_font_size_override("font_size", 12)
		y += 60
	else:
		place(g._presets, Vector2(18, y), Vector2(panel_w - 36, 48))
		y += 60
		if g._arena_enabled:
			place(g._arena_selector, Vector2(18, y), Vector2(panel_w - 36, 48))
			y += 60
		for index in 4:
			place(g._build_actions[index], Vector2(18 + (index % 2) * (panel_w - 24) * 0.5, y + (index / 2) * 60), Vector2((panel_w - 48) * 0.5, 48))
		y += 120
	place(g._nav.ROBOT, Vector2(18, y), Vector2(panel_w - 36, 48))
	g._ui.set_meta("preview_rect", Rect2(panel_w + 48, 80, w - panel_w - 68, h - 100) if not compact else Rect2(20, 80, w - 40, h - 100))
