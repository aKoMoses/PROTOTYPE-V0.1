extends Control

const LOADOUT := preload("res://scripts/loadout_state.gd")

var player: Node
var _health: Label
var _weapon: Label
var _fill: ColorRect
var _clock := 0.0
var _example := false
var _longshot_segments: Array[ColorRect] = []
var _heat_track: ColorRect
var _heat_fill: ColorRect
var _shell: StyleBoxFlat
var _warning_phase := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(280, 90)
	var background := Panel.new()
	_shell = StyleBoxFlat.new()
	_shell.bg_color = Color("#20272ae8")
	_shell.border_color = Color("#776b5c")
	_shell.set_border_width_all(1)
	_shell.set_corner_radius_all(6)
	background.add_theme_stylebox_override("panel", _shell)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_health = _label(17, Color("#f3ddbb"), Vector2(12, 6), Vector2(256, 26))
	add_child(_health)
	var track := ColorRect.new()
	track.color = Color("#2d4a50")
	track.position = Vector2(12, 35)
	track.size = Vector2(256, 16)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(track)
	_fill = ColorRect.new()
	_fill.color = Color("#42d9e5")
	_fill.position = track.position
	_fill.size = track.size
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	_weapon = _label(14, Color("#42d9e5"), Vector2(12, 58), Vector2(256, 25))
	add_child(_weapon)
	for index in 2:
		var segment := ColorRect.new()
		segment.name = "LongshotSegment%d" % (index + 1)
		segment.position = Vector2(12 + index * 132, 82)
		segment.size = Vector2(124, 4)
		segment.color = Color("#344a50")
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.visible = false
		add_child(segment)
		_longshot_segments.append(segment)
	_heat_track = ColorRect.new()
	_heat_track.position = Vector2(12, 82)
	_heat_track.size = Vector2(256, 7)
	_heat_track.color = Color("#344a50")
	_heat_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heat_track)
	_heat_fill = ColorRect.new()
	_heat_fill.position = _heat_track.position
	_heat_fill.size = _heat_track.size
	_heat_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heat_fill)
	_refresh()

func _label(font_size: int, tint: Color, at: Vector2, dimensions: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label

func set_player(value: Node) -> void:
	player = value
	if is_inside_tree():
		_refresh()

func set_example(value: bool) -> void:
	_example = value
	if is_inside_tree():
		_refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	if not get_tree().paused:
		_warning_phase += delta * TAU * 2.0
	_clock += delta
	if _clock >= 0.1:
		_clock = 0.0
		_refresh()

func _refresh() -> void:
	if _health == null or player == null or not is_instance_valid(player):
		return
	for segment in _longshot_segments:
		segment.visible = false
	_heat_track.visible = false
	_heat_fill.visible = false
	_shell.bg_color = Color("#20272ae8")
	_shell.border_color = Color("#776b5c")
	_shell.set_border_width_all(1)
	_weapon.add_theme_color_override("font_color", Color("#42d9e5"))
	if _example:
		_health.text = "PV 64 / 100"
		_fill.size.x = 256.0 * 0.64
		_weapon.text = "SHOTGUN   2 / 3"
		return
	var health := float(player.call("get_health"))
	var maximum := maxf(1.0, float(player.call("get_max_health")))
	_health.text = "PV %d / %d" % [int(ceil(health)), int(ceil(maximum))]
	var shield := float(player.call("get_shield_health")) if player.has_method("get_shield_health") else 0.0
	_health.add_theme_font_size_override("font_size", 15 if shield > 0.0 else 17)
	if shield > 0.0:
		_health.text += "  •  SH %d" % ceili(shield)
	_fill.size.x = 256.0 * clampf(health / maximum, 0.0, 1.0)
	var weapon_id := str(player.call("get_weapon_id"))
	if weapon_id == "longshot":
		var count := int(player.call("get_longshot_cycle_count")) if player.has_method("get_longshot_cycle_count") else 0
		var ready := bool(player.call("is_longshot_enhanced_ready")) if player.has_method("is_longshot_enhanced_ready") else false
		_weapon.text = "LONGSHOT   EXÉCUTION PRÊTE" if ready else "LONGSHOT   %d / 2 IMPACTS" % count
		_weapon.add_theme_color_override("font_color", Color("#ffd477") if ready else Color("#42d9e5"))
		for index in _longshot_segments.size():
			_longshot_segments[index].visible = true
			_longshot_segments[index].color = Color("#ffd477") if ready else Color("#42d9e5") if index < count else Color("#344a50")
		return
	_weapon.add_theme_color_override("font_color", Color("#42d9e5"))
	if weapon_id == "mekatana":
		var combo: Dictionary = player.call("get_mekatana_state") if player.has_method("get_mekatana_state") else {}
		var phase := str(combo.get("phase", ""))
		var labels := {"preparation": "PRÉP.", "active": "SLASH", "recovery": "RÉCUP."}
		if phase != "":
			_weapon.text = "MEKATANA   %d / 3   %s" % [int(combo.get("step", 0)) + 1, str(labels.get(phase, phase))]
		elif float(combo.get("combo_remaining", 0.0)) > 0.0 and int(combo.get("next_step", 0)) > 0:
			_weapon.text = "MEKATANA   SUIVANT %d   %.1f s" % [int(combo.get("next_step", 0)) + 1, float(combo.get("combo_remaining", 0.0))]
		else:
			_weapon.text = "MEKATANA   PRÊT 1 / 3"
		return
	if weapon_id == "blaster":
		var heat := float(player.call("get_blaster_heat_fraction"))
		var overheated := bool(player.call("is_blaster_overheated"))
		var tint := Color("#ff7960") if overheated else Color("#ff9b52") if heat >= 0.7 else Color("#ffc069")
		_heat_track.visible = true
		_heat_fill.visible = true
		_heat_track.color = Color("#632d29") if overheated else Color("#344a50")
		_heat_fill.size.x = 256.0 * clampf(heat, 0.0, 1.0)
		_heat_fill.color = tint
		if overheated:
			_weapon.text = "SURCHAUFFE   %.1f s" % float(player.call("get_blaster_overheat_remaining"))
			_weapon.add_theme_color_override("font_color", tint)
			_shell.bg_color = Color("#421e20ef")
			_shell.border_color = Color("#cc4e3f").lerp(tint, 0.5 + 0.5 * sin(_warning_phase))
			_shell.set_border_width_all(2)
		elif bool(player.call("is_blaster_charging")):
			_weapon.text = "BLASTER   CHARGE %d %%" % roundi(float(player.call("get_blaster_charge_ratio")) * 100.0)
		else:
			_weapon.text = "BLASTER   CHALEUR %d %%" % roundi(heat * 100.0)
	else:
		_weapon.text = "%s   %d / %d" % [LOADOUT.display_name(weapon_id), int(player.call("get_shotgun_ammo")), int(player.call("get_shotgun_magazine_size"))]
