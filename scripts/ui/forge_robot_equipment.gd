extends Control

## Equipment stays around the robot; storage is outside the player's view.
const KINDS := ["weapon", "offensive", "defensive", "mobility", "passive"]
const BONES := {"weapon": "rightshoulder", "offensive": "rightforearm", "defensive": "leftarm", "mobility": "leftleg", "passive": "rightleg"}
var garage
var pins: Dictionary = {}
var choices: Dictionary = {}
var idle_seconds := 0.0
var pin_alpha := 1.0
var _anchors: Dictionary = {}
var _enabled := false
var _catalog := false
var _expanded_detail := false
var _detail_id := ""
var _summary: Label
var _details_button: Button
var _outlined: Dictionary = {}
var _outline_material: ShaderMaterial


func configure(owner_garage: Control) -> void:
	garage = owner_garage
	name = "RobotEquipment"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 6
	_summary = garage._label("", Vector2.ZERO, Vector2(200, 60), 15)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage._detail_panel.add_child(_summary)
	_details_button = garage._button("⋯", Vector2.ZERO, Vector2(44, 44), _toggle_details)
	_details_button.tooltip_text = "Détails, statistiques et démonstration"
	_details_button.reparent(garage._detail_panel)
	for kind in KINDS:
		var title: String = "ARME" if kind == "weapon" else garage.CATEGORY_TITLES[kind]
		var pin: Button = garage._button(title, Vector2.ZERO, Vector2(138, 44), garage._open_station.bind(kind))
		pin.name = "Mount_" + kind
		pin.reparent(self)
		pin.mouse_entered.connect(wake)
		pin.focus_entered.connect(wake)
		pins[kind] = pin
		choices[kind] = {}
		for identifier in garage._options(kind):
			var card: Button = garage._button("", Vector2.ZERO, Vector2(154, 84), garage._preview_equipment.bind(kind, str(identifier)))
			card.name = "Part_" + str(identifier)
			card.reparent(self)
			card.tooltip_text = garage.LOADOUT.display_name(identifier)
			card.mouse_entered.connect(wake)
			card.gui_input.connect(garage._card_input.bind(kind, str(identifier)))
			var icon := TextureRect.new()
			icon.name = "Icon"
			icon.texture = garage._icons.get_icon(identifier)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(icon)
			var label: Label = garage._label(garage.LOADOUT.display_name(identifier), Vector2.ZERO, Vector2(140, 22), 11, garage.CREAM, true)
			label.name = "Title"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			card.add_child(label)
			choices[kind][identifier] = card


func wake() -> void:
	idle_seconds = 0.0


func _toggle_details() -> void:
	_expanded_detail = not _expanded_detail
	apply_layout()


func _short_description(identifier: String) -> String:
	return {"fulguro_punch": "Charge ton poing.\nProjette la cible.", "rocket_basket": "Une salve de roquettes guidées.", "javelin": "Marquage et seconde activation.", "pelto_smash": "Une vague pour attirer la cible."}.get(identifier, str(garage.TAGS.get(identifier, "")))


func pick_mount(point: Vector2) -> String:
	if not _enabled or not is_visible_in_tree():
		return ""
	var local: Vector2 = (point - garage._ui.position) / garage._ui.scale
	var nearest := ""
	var distance := 24.0
	for kind in _anchors:
		var pin: Button = pins[kind]
		var candidate: float = local.distance_to(_anchors[kind])
		if pin.visible and not pin.disabled and candidate < distance:
			distance = candidate
			nearest = kind
	if not nearest.is_empty():
		wake()
	return nearest


func apply_layout() -> void:
	var g = garage
	var w: float = g._ui.size.x
	var h: float = g._ui.size.y
	size = g._ui.size
	var compact: bool = g._compact_layout
	_catalog = g._view in ["catalog", "detail"] and g._category in KINDS
	_enabled = g._view in ["hub", "summary"] or _catalog
	visible = _enabled
	# The same close camera is used at the entry, during editing and mounting.
	g._ui.set_meta("robot_workbench", true)
	_summary.hide()
	_details_button.hide()
	g._detail_icon.show()
	if _detail_id != g._preview_id:
		_expanded_detail = false
		_detail_id = g._preview_id
	if not _enabled:
		_outline_selection("")
		return
	var guided: bool = g._creating and g._journey_step < KINDS.size()
	g._header_title.text = "NOUVEAU BUILD" if guided else "GARAGE  |  MON BUILD"
	g._header_title.add_theme_font_size_override("font_size", 21 if compact else 26)
	g._family_selector.hide()
	g._catalog_title.hide()
	g._hub_caption.hide()
	for grid: GridContainer in g._grids.values():
		grid.hide()
	for card: Button in g._edit_choices.values():
		card.hide()
	g._stats_panel.hide()
	g._edit_selector.visible = g._view == "hub"
	g._edit_selector.position = Vector2(18, 76)
	g._edit_selector.size = Vector2(190 if compact else 230, 48)
	g._footer.show()
	g._test_button.show()
	g._save_button.visible = not guided
	g._library_button.show()
	g._save_state.show()
	if not compact:
		g._footer.hide()
		g._test_button.position = Vector2(w * 0.5 - 206, h - 82)
		g._test_button.size = Vector2(196, 48)
		g._test_button.text = "▶  TESTER"
		g._save_button.position = Vector2(w * 0.5 + 4, h - 82)
		g._save_button.size = Vector2(214, 48)
		# Save belongs beside Test; the amber accent is reserved for equipment.
		for state in ["normal", "hover", "pressed", "focus"]:
			g._save_button.add_theme_stylebox_override(state, g._style(state != "normal"))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			g._save_button.add_theme_color_override(state, g.CREAM)
		g._library_button.position = Vector2(w - 152, 8)
		g._library_button.size = Vector2(136, 44)
		g._edit_selector.hide()
		g._save_state.hide()
	else:
		g._test_button.text = "TESTER"
		g._primary_style(g._save_button)
	g._status.position = Vector2(172, h - 58)
	g._status.size = Vector2(maxf(0, w - 526), 44)
	g._status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if not compact:
		g._status.position = Vector2(20, h - 60)
		g._status.size = Vector2(w * 0.27, 42)
	g._detail_panel.visible = _catalog
	var top: float = 108 if guided else 80
	# Reserve room on both sides of the robot for the fan and the description.
	var frame := Rect2(w * 0.29, top - 12, w * 0.41, h - top - 62)
	frame.position.y = h * 0.48 - frame.size.y * 0.5
	if compact:
		frame = Rect2(w * 0.27, top, w * 0.43, h - top - 80)
	g._ui.set_meta("preview_rect", frame)
	if _catalog:
		var panel_w: float = minf(410 if not compact else 300, w * 0.27)
		var panel_h: float = minf(360 if not compact else 260, h - top - 88)
		if not compact and not _expanded_detail:
			panel_h = 176
		g._detail_panel.position = Vector2(w * 0.705 if not compact else w - panel_w - 14, h * 0.32 if not compact else top + (h - top - 80 - panel_h) * 0.5)
		g._detail_panel.size = Vector2(panel_w, panel_h)
		g._detail_icon.position = Vector2(panel_w - 65, 12)
		g._detail_icon.size = Vector2(48, 48)
		g._detail_title.position = Vector2(14, 12)
		g._detail_title.size = Vector2(panel_w - 85, 52)
		g._detail_title.add_theme_font_size_override("font_size", 16 if compact else 21)
		var scroll: ScrollContainer = g._detail_description.get_parent()
		scroll.position = Vector2(14, 76)
		scroll.size = Vector2(panel_w - 28, maxf(42, panel_h - (188 if compact else 236)))
		scroll.clip_contents = true
		g._detail_description.custom_minimum_size.x = panel_w - 44
		g._detail_description.size.x = panel_w - 44
		g._detail_description.add_theme_font_size_override("font_size", 14 if compact else 16)
		# The old layout may have widened the scroll to the label's previous
		# minimum. Shrink the child first, then recompute the container width.
		g._detail_description.update_minimum_size()
		scroll.update_minimum_size()
		scroll.size = Vector2(panel_w - 28, maxf(42, panel_h - (188 if compact else 236)))
		g._detail_stats.visible = not compact
		g._detail_stats.position = Vector2(14, panel_h - 158)
		g._detail_stats.size = Vector2(panel_w - 28, 32)
		g.equip_button.show()
		g._demo_button.show()
		g.equip_button.position = Vector2(12, panel_h - 60)
		g.equip_button.size = Vector2(panel_w - 24, 46)
		g.equip_button.add_theme_font_size_override("font_size", 14 if compact else 17)
		g._demo_button.position = Vector2(12, panel_h - 112)
		g._demo_button.size = Vector2(panel_w - 24, 46)
		g._demo_button.add_theme_font_size_override("font_size", 12)
		if not compact:
			_details_button.show()
			_details_button.position = Vector2(panel_w - 48, 5)
			_details_button.size = Vector2(44, 44)
			if not _expanded_detail:
				scroll.hide()
				g._detail_stats.hide()
				g._demo_button.hide()
				g._detail_icon.position = Vector2(12, 28)
				g._detail_icon.size = Vector2(112, 124)
				g._detail_title.position = Vector2(138, 12)
				g._detail_title.size = Vector2(panel_w - 188, 48)
				g._detail_title.add_theme_font_size_override("font_size", 18)
				_summary.show()
				_summary.text = _short_description(g._preview_id)
				_summary.position = Vector2(138, 64)
				_summary.size = Vector2(panel_w - 154, 48)
				g.equip_button.position = Vector2(138, panel_h - 58)
				g.equip_button.size = Vector2(panel_w - 154, 44)
				if not guided:
					g.equip_button.text = "ÉQUIPÉ  ✓" if g.equip_button.disabled else "ÉQUIPER"
			else:
				scroll.show()
				g._detail_icon.hide()
		else:
			scroll.show()
	for kind in KINDS:
		var pin: Button = pins[kind]
		pin.visible = not compact or not _catalog or kind == g._category
		pin.disabled = guided and kind != KINDS[g._journey_step]
		pin.add_theme_font_size_override("font_size", 12 if compact else 15)
		pin.add_theme_stylebox_override("normal", g._style(_catalog and kind == g._category))
		if not compact:
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				pin.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		pin.tooltip_text = g.LOADOUT.display_name(str(g.loadout[kind]))
		var index := 0
		var count: int = choices[kind].size()
		var columns := 2 if compact else 1
		var rows := ceili(float(count) / columns)
		var fan_top: float = 128 if compact else top
		var card_h: float = minf(78 if compact else 88, (h - fan_top - 110) / rows - 6)
		var card_w: float = minf(108 if not compact else 80, w * 0.19)
		var total: float = rows * (card_h + 8) - 8
		for identifier in choices[kind]:
			var card: Button = choices[kind][identifier]
			card.visible = _catalog and kind == g._category
			card.position = Vector2(16 + (index % columns) * (card_w + 6) + sin(float(index) / maxf(count - 1, 1) * PI) * (4 if compact else 26), fan_top + (h - fan_top - 84 - total) * 0.5 + (index / columns) * (card_h + 8))
			card.size = Vector2(card_w, card_h)
			card.get_node("Icon").position = Vector2(8, 4)
			card.get_node("Icon").size = Vector2(card_w - 16, card_h - 27)
			card.get_node("Title").position = Vector2(4, card_h - 24)
			card.get_node("Title").size = Vector2(card_w - 8, 20)
			card.add_theme_stylebox_override("normal", g._style(identifier == g._preview_id))
			card.get_node("Title").visible = compact
			card.rotation = 0.0
			if not compact:
				var ratio := float(index) / maxf(count - 1, 1)
				card.pivot_offset = card.size * 0.5
				card.rotation = deg_to_rad(lerpf(-10.0, 10.0, ratio))
				card.position = Vector2(w * 0.205 + sin(ratio * PI) * 14, h * 0.48 - total * 0.5 + index * (card_h + 8))
				card.get_node("Icon").position = Vector2(5, 4)
				card.get_node("Icon").size = card.size - Vector2(10, 8)
				var style: StyleBoxFlat = g._style(identifier == g._preview_id)
				style.bg_color = Color(0.08, 0.075, 0.06, 0.82)
				style.shadow_color = Color(g.AMBER, 0.35) if identifier == g._preview_id else Color(0, 0, 0, 0.2)
				style.shadow_size = 9 if identifier == g._preview_id else 3
				card.add_theme_stylebox_override("normal", style)
			index += 1
	_outline_selection(g._preview_id if _catalog else "")
	wake()
	_update_pins()


func _process(delta: float) -> void:
	if not _enabled or not is_visible_in_tree():
		return
	var local_mouse: Vector2 = garage.get_local_mouse_position()
	var owner_focus := get_viewport().gui_get_focus_owner()
	var engaged: bool = _catalog or garage.stage.is_robot_at_position(local_mouse) or (owner_focus != null and is_ancestor_of(owner_focus))
	for pin: Button in pins.values():
		engaged = engaged or pin.is_hovered()
	if engaged:
		wake()
	else:
		idle_seconds += delta
	var target := 1.0 if engaged or idle_seconds < 2.5 or garage._compact_layout else 0.0
	pin_alpha = move_toward(pin_alpha, target, delta * 2.0)
	for pin: Button in pins.values():
		pin.modulate.a = pin_alpha * (0.38 if pin.disabled else 1.0)
	_update_pins()


func _update_pins() -> void:
	var g = garage
	if g.focus == null or g.stage.camera == null:
		return
	var frame: Rect2 = g._ui.get_meta("preview_rect")
	var compact: bool = g._compact_layout
	var pin_size := Vector2(110 if compact else 112, 48 if compact else 44)
	var positions := {"weapon": Vector2(0.04, 0.13), "offensive": Vector2(0.0, 0.43), "passive": Vector2(0.02, 0.78), "defensive": Vector2(0.76, 0.26), "mobility": Vector2(0.76, 0.75)}
	_anchors.clear()
	for kind in KINDS:
		var world_point: Vector3 = g.focus.anchor(BONES[kind])
		var screen: Vector2 = g.stage.camera.unproject_position(world_point) * g.stage.size / Vector2(g.stage.viewport.size)
		_anchors[kind] = (screen - g._ui.position) / g._ui.scale
		var pin: Button = pins[kind]
		var ratio: Vector2 = positions[kind]
		pin.position = frame.position + frame.size * ratio - Vector2(pin_size.x * (1.0 if kind in ["weapon", "offensive", "passive"] else 0.0), 0)
		var anchor_point: Vector2 = _anchors[kind]
		pin.position.x = anchor_point.x + (28 if kind in ["defensive", "mobility"] else -pin_size.x - 28)
		pin.position.x = clampf(pin.position.x, 150 if _catalog and compact else (190 if _catalog else 18), size.x - pin_size.x - (size.x * 0.25 + 20 if _catalog else 18))
		pin.size = pin_size
		if not compact:
			pin.position.x = anchor_point.x + (44 if kind in ["defensive", "mobility"] else -pin_size.x - 44)
			if kind == "passive":
				pin.position.y = frame.position.y + frame.size.y * 0.78
		if compact and _catalog:
			pin.position = Vector2(16, 72)
			pin.size.x = 166
	queue_redraw()


func _draw() -> void:
	if not _enabled:
		return
	for kind in _anchors:
		var pin: Button = pins[kind]
		if not pin.visible:
			continue
		var point: Vector2 = _anchors[kind]
		var rect := pin.get_rect()
		if not garage._compact_layout:
			var style: StyleBoxFlat = garage._style((_catalog and garage._category == kind) or pin.is_hovered() or pin.has_focus())
			style.bg_color.a = 0.82 * pin_alpha
			style.border_color.a = pin_alpha
			draw_style_box(style, rect.grow_individual(0, -7, 0, -7))
		var edge := Vector2(rect.end.x if point.x > rect.get_center().x else rect.position.x, rect.get_center().y)
		var color: Color = garage.AMBER if _catalog and garage._category == kind else garage.CREAM
		color.a = pin_alpha * (0.20 if pin.disabled else 0.75)
		draw_polyline(PackedVector2Array([edge, Vector2(lerpf(edge.x, point.x, 0.60), edge.y), point]), color, 1.5, true)
		draw_circle(point, 4.0, color, false, 1.5, true)


func _outline_selection(identifier: String) -> void:
	for mesh in _outlined:
		if is_instance_valid(mesh):
			mesh.material_overlay = _outlined[mesh]
	_outlined.clear()
	if identifier.is_empty() or garage.stage.module_visuals == null:
		return
	if _outline_material == null:
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded, cull_front; void vertex(){ VERTEX += NORMAL * 0.012; } void fragment(){ ALBEDO = vec3(1.0, 0.62, 0.15); EMISSION = vec3(1.0, 0.48, 0.08) * 1.8; }"
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = shader
	var modules = garage.stage.module_visuals
	for key in modules.mounts:
		if str(modules.MOUNT_IDS[key]) != identifier:
			continue
		for child in modules.mounts[key].get_children():
			if child is MeshInstance3D:
				_outlined[child] = child.material_overlay
				child.material_overlay = _outline_material


func _exit_tree() -> void:
	for mesh in _outlined:
		if is_instance_valid(mesh):
			mesh.material_overlay = _outlined[mesh]
