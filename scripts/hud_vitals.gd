extends Control

## One compact readout for life and the live weapon, shared by all combat modes.
const ICONS := preload("res://scripts/equipment_icons.gd")
var player: Node
var _health: Label
var _warning: Label
var _weapon: Label
var _weapon_icon: TextureRect
var _fill: ColorRect
var _weapon_fill: ColorRect
var _clock := 0.0
var _example := false
var _icons := ICONS.new()
var _longshot_segments: Array[ColorRect] = []
var _shell_segments: Array[ColorRect] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(366, 40)
	var background := Panel.new()
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color("#171d20ee")
	shell.border_color = Color("#80694e")
	shell.set_border_width_all(1)
	shell.set_corner_radius_all(5)
	background.add_theme_stylebox_override("panel", shell)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_warning = _label("VitalState", 10, Color("#f3ddbb"), Vector2(10, 3), Vector2(81, 16))
	_health = _label("Health", 14, Color("#f3ddbb"), Vector2(92, 2), Vector2(83, 19))
	_health.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bar(Vector2(10, 25), Vector2(165, 6), Color("#34454b"))
	_fill = _bar(Vector2(10, 25), Vector2(165, 6), Color("#42d9e5"))
	_bar(Vector2(184, 8), Vector2(1, 24), Color("#80694e"))
	_weapon_icon = TextureRect.new()
	_weapon_icon.position = Vector2(191, 6)
	_weapon_icon.size = Vector2(32, 27)
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_weapon_icon)
	_weapon = _label("WeaponState", 12, Color("#42d9e5"), Vector2(228, 3), Vector2(130, 21))
	_weapon.clip_text = true
	_bar(Vector2(228, 27), Vector2(128, 4), Color("#34454b"))
	_weapon_fill = _bar(Vector2(228, 27), Vector2(0, 4), Color("#42d9e5"))
	for index in 2:
		var segment := _bar(Vector2(228 + index * 66, 27), Vector2(62, 4), Color("#344a50"))
		segment.name = "LongshotSegment%d" % (index + 1)
		segment.visible = false
		_longshot_segments.append(segment)
	for index in 3:
		var segment := _bar(Vector2(228 + index * 44, 27), Vector2(40, 4), Color("#344a50"))
		segment.visible = false
		_shell_segments.append(segment)
	_refresh()

func _label(id: String, font_size: int, tint: Color, at: Vector2, dimensions: Vector2) -> Label:
	var item := Label.new()
	item.name = id
	item.position = at
	item.size = dimensions
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", tint)
	add_child(item)
	return item

func _bar(at: Vector2, dimensions: Vector2, tint: Color) -> ColorRect:
	var item := ColorRect.new()
	item.position = at
	item.size = dimensions
	item.color = tint
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item)
	return item

func set_player(value: Node) -> void:
	player = value
	if is_inside_tree(): _refresh()

func set_example(value: bool) -> void:
	_example = value
	if is_inside_tree(): _refresh()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_clock += delta
	if _clock >= 0.1:
		_clock = 0.0
		_refresh()

func _refresh() -> void:
	if _health == null or not is_instance_valid(player): return
	for segment in _longshot_segments + _shell_segments:
		segment.visible = false
	var health := 640.0 if _example else float(player.call("get_health"))
	var maximum := 1000.0 if _example else maxf(1.0, float(player.call("get_max_health")))
	_health.text = "%d / %d" % [ceili(health), ceili(maximum)]
	var ratio := clampf(health / maximum, 0.0, 1.0)
	var low := ratio <= 0.25 and health > 0.0
	_fill.size.x = 165.0 * ratio
	_fill.color = Color("#ff6262") if low else Color("#42d9e5")
	_health.add_theme_color_override("font_color", Color("#ff8585") if low else Color("#f3ddbb"))
	var shield := float(player.call("get_shield_health")) if player.has_method("get_shield_health") else 0.0
	_warning.text = "⚠ PV · SH %d" % ceili(shield) if low and shield > 0.0 else "⚠ PV FAIBLES" if low else "PV · SH %d" % ceili(shield) if shield > 0.0 else "PV"
	_warning.add_theme_color_override("font_color", Color("#ff8585") if low else Color("#f3ddbb"))
	# Keep shield information even during the low-life warning.
	tooltip_text = "PV %d / %d · Bouclier %d" % [ceili(health), ceili(maximum), ceili(shield)]
	var weapon_id := "shotgun" if _example else str(player.call("get_weapon_id"))
	_weapon_icon.texture = _icons.get_icon(weapon_id)
	_weapon.add_theme_color_override("font_color", Color("#42d9e5"))
	_weapon_fill.color = Color("#42d9e5")
	_weapon_fill.size.x = 0.0
	match weapon_id:
		"longshot":
			var count := int(player.call("get_longshot_cycle_count"))
			var ready := bool(player.call("is_longshot_enhanced_ready"))
			_weapon.text = "EXÉCUTION PRÊTE" if ready else "LONGSHOT · %d / 2" % count
			_weapon.add_theme_color_override("font_color", Color("#ffd477") if ready else Color("#42d9e5"))
			for index in 2:
				_longshot_segments[index].visible = true
				_longshot_segments[index].color = Color("#ffd477") if ready else Color("#42d9e5") if index < count else Color("#344a50")
		"mekatana":
			var combo: Dictionary = player.call("get_mekatana_state")
			var phase := str(combo.get("phase", ""))
			var labels := {"preparation": "PRÉP.", "active": "SLASH", "recovery": "RÉCUP."}
			if not phase.is_empty():
				_weapon.text = "MEKATANA %d / 3 · %s" % [int(combo.get("step", 0)) + 1, labels.get(phase, phase)]
			elif float(combo.get("combo_remaining", 0.0)) > 0.0 and int(combo.get("next_step", 0)) > 0:
				_weapon.text = ("SUIVANT %d · %.1f s" % [int(combo.next_step) + 1, float(combo.combo_remaining)]).replace(".", ",")
			else:
				_weapon.text = "MEKATANA · PRÊT"
		"shotgun":
			var ammo := 2 if _example else int(player.call("get_shotgun_ammo"))
			var capacity := 3 if _example else int(player.call("get_shotgun_magazine_size"))
			var reloading := not _example and bool(player.call("is_shotgun_reloading"))
			_weapon.text = "RECHARGE..." if reloading else "SHOTGUN · %d / %d" % [ammo, capacity]
			_weapon.add_theme_color_override("font_color", Color("#efb565") if reloading else Color("#42d9e5"))
			if reloading:
				_weapon_fill.size.x = 128.0 * float(player.call("get_shotgun_reload_progress"))
				_weapon_fill.color = Color("#efb565")
			for index in 3:
				_shell_segments[index].visible = not reloading
				_shell_segments[index].color = Color("#efb565") if index < ammo else Color("#344a50")
		_:
			var charge := clampf(float(player.call("get_blaster_charge_ratio")), 0.0, 1.0)
			_weapon.text = "CHARGE %d %%" % roundi(charge * 100.0)
			_weapon_fill.size.x = 128.0 * charge
