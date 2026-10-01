extends Control

const LOADOUT := preload("res://scripts/loadout_state.gd")

var player: Node
var _health: Label
var _weapon: Label
var _fill: ColorRect
var _clock := 0.0
var _example := false
var _longshot_segments: Array[ColorRect] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(280, 90)
	var background := ColorRect.new()
	background.color = Color("#242629df")
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
	for index in 4:
		var segment := ColorRect.new()
		segment.name = "LongshotSegment%d" % (index + 1)
		segment.position = Vector2(12 + index * 66, 82)
		segment.size = Vector2(58, 4)
		segment.color = Color("#344a50")
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.visible = false
		add_child(segment)
		_longshot_segments.append(segment)
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
	_clock += delta
	if _clock >= 0.1:
		_clock = 0.0
		_refresh()

func _refresh() -> void:
	if _health == null or player == null or not is_instance_valid(player):
		return
	for segment in _longshot_segments:
		segment.visible = false
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
		_weapon.text = "LONGSHOT   TIR AMÉLIORÉ PRÊT" if ready else "LONGSHOT   PROCHAIN %d / 5" % (count + 1)
		_weapon.add_theme_color_override("font_color", Color("#b8faff") if ready else Color("#42d9e5"))
		for index in _longshot_segments.size():
			_longshot_segments[index].visible = true
			_longshot_segments[index].color = Color("#b8faff") if ready else Color("#42d9e5") if index < count else Color("#344a50")
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
	_weapon.text = "%s   %d / %d" % [LOADOUT.display_name(weapon_id), int(player.call("get_shotgun_ammo")), int(player.call("get_shotgun_magazine_size"))] if weapon_id == "shotgun" else "%s   CHARGE %d %%" % [LOADOUT.display_name(weapon_id), int(float(player.call("get_blaster_charge_ratio")) * 100.0)]
