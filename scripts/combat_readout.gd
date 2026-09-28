extends Node3D

## A metal health plaque above the actor and grouped world-space damage numbers.

const DAMAGE_POPUP := preload("res://scripts/damage_popup.gd")
const SEGMENT_COUNT := 10
const VIEW_SIZE := Vector2i(300, 108)

var _accent := Color("#42d9e5")
var _display_name := "JOUEUR"
var _damage_side := 1.0
var _viewport: SubViewport
var _sprite: Sprite3D
var _health_number: Label
var _segments: Array[ColorRect] = []
var _badge: Panel
var _badge_mark: Label
var _show_shotgun := false
var _show_blaster := false
var _ammo_recess: Panel
var _ammo_shells: Array[Panel] = []
var _ammo_caps: Array[ColorRect] = []
var _ammo_highlights: Array[ColorRect] = []
var _ammo_progress_track: Panel
var _ammo_progress_fill: ColorRect
var _ammo_progress_tip: ColorRect
var _blaster_coil_recess: Panel
var _blaster_coil: Line2D
var _blaster_progress_track: Panel
var _blaster_progress_fill: ColorRect
var _blaster_progress_tip: ColorRect
var _latest_popup: Node3D
var _latest_healing_popup: Node3D
var _damage_serial := 0


func configure(accent: Color, display_name: String = "JOUEUR", damage_side: float = 1.0) -> void:
	_accent = accent
	_display_name = display_name
	_damage_side = damage_side
	_build()


func set_health(current: float, maximum: float) -> void:
	if _health_number == null:
		return
	var fraction := clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	_health_number.text = "%d" % roundi(current)
	for index in range(SEGMENT_COUNT):
		var fill_fraction := clampf(fraction * SEGMENT_COUNT - index, 0.0, 1.0)
		_segments[index].size.x = 23.0 * fill_fraction
		_segments[index].visible = fill_fraction > 0.0
	_health_number.add_theme_color_override("font_color", Color("#ffb37c") if fraction <= 0.25 else Color("#fff2dc"))


func set_shotgun_ammo(active: bool, ammo: int, capacity: int, reloading: bool, progress: float) -> void:
	if _badge_mark == null:
		return
	_show_shotgun = active
	_sync_weapon_badge()
	_ammo_recess.visible = active
	_ammo_progress_track.visible = active
	_ammo_progress_fill.visible = active and reloading
	_ammo_progress_tip.visible = active and reloading and progress > 0.02
	if not active:
		for shell in _ammo_shells:
			shell.visible = false
		return
	var safe_ammo := clampi(ammo, 0, capacity)
	var reload_progress := clampf(progress, 0.0, 1.0)
	_ammo_progress_fill.size.x = 262.0 * reload_progress
	_ammo_progress_tip.position.x = 2.0 + maxf(0.0, _ammo_progress_fill.size.x - 2.0)
	var loading_shell := mini(_ammo_shells.size() - 1, int(reload_progress * _ammo_shells.size()))
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)
	_ammo_progress_tip.color.a = 0.65 + 0.25 * pulse
	for index in range(_ammo_shells.size()):
		var loaded := index < safe_ammo
		var loading := reloading and index == loading_shell and not loaded
		var shell_color := Color("#ad6247") if loaded else Color("#37393a").lerp(Color("#ad6247"), 0.15 + pulse * 0.35) if loading else Color("#37393a")
		_ammo_shells[index].visible = true
		_ammo_shells[index].add_theme_stylebox_override("panel", _panel_style(shell_color, Color("#d5a16c") if loaded else Color("#88654e") if loading else Color("#685f58"), 1, 2))
		_ammo_caps[index].color = Color("#ddb477") if loaded else Color("#a17e60") if loading else Color("#746456")
		_ammo_highlights[index].color = Color("#e8ab7c") if loaded else Color("#b87c5b") if loading else Color("#555352")


func set_blaster_charge(active: bool, charging: bool, progress: float) -> void:
	if _blaster_coil == null:
		return
	_show_blaster = active
	_sync_weapon_badge()
	_blaster_coil_recess.visible = active
	_blaster_coil.visible = active
	_blaster_progress_track.visible = active
	_blaster_progress_fill.visible = active and charging
	_blaster_progress_tip.visible = active and charging and progress > 0.02
	if not active:
		return
	var ratio := clampf(progress, 0.0, 1.0)
	_blaster_progress_fill.size.x = 262.0 * ratio
	_blaster_progress_tip.position.x = 2.0 + maxf(0.0, _blaster_progress_fill.size.x - 2.0)
	_blaster_coil.default_color = Color("#57bcca").lerp(Color("#aaf7ff"), ratio if charging else 0.0)


func _sync_weapon_badge() -> void:
	var show_badge := not _show_shotgun and not _show_blaster
	_badge.visible = show_badge
	_badge_mark.visible = show_badge


func show_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	if _latest_popup == null or not is_instance_valid(_latest_popup) or not bool(_latest_popup.call("can_merge")):
		_damage_serial += 1
		_latest_popup = Node3D.new()
		_latest_popup.name = "DamageNumber%d" % _damage_serial
		_latest_popup.set_script(DAMAGE_POPUP)
		_latest_popup.set("side", _damage_side)
		add_child(_latest_popup)
	_latest_popup.call("add_damage", amount)
	var popups := get_children().filter(func(child: Node) -> bool: return child.name.begins_with("DamageNumber"))
	if popups.size() > 4:
		popups.front().queue_free()


func show_healing(amount: float) -> void:
	if amount <= 0.0:
		return
	if _latest_healing_popup == null or not is_instance_valid(_latest_healing_popup) or not bool(_latest_healing_popup.call("can_merge")):
		_damage_serial += 1
		_latest_healing_popup = Node3D.new()
		_latest_healing_popup.name = "HealingNumber%d" % _damage_serial
		_latest_healing_popup.set_script(DAMAGE_POPUP)
		_latest_healing_popup.set("side", -_damage_side)
		_latest_healing_popup.set("healing_mode", true)
		add_child(_latest_healing_popup)
	_latest_healing_popup.call("add_healing", amount)


func clear_damage_numbers() -> void:
	_latest_popup = null
	_latest_healing_popup = null
	for child in get_children():
		if child.name.begins_with("DamageNumber") or child.name.begins_with("HealingNumber"):
			child.queue_free()


func set_cinematic_mode(enabled: bool) -> void:
	if _sprite != null:
		_sprite.visible = not enabled


func _exit_tree() -> void:
	# SubViewportTexture keeps a reference to its viewport until the sprite releases it.
	if _sprite != null:
		_sprite.texture = null


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "HealthBarViewport"
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var root := Control.new()
	root.name = "HealthBarUI"
	root.size = Vector2(VIEW_SIZE)
	_viewport.add_child(root)
	var plate := Panel.new()
	plate.name = "MetalPlate"
	plate.position = Vector2(5, 4)
	plate.size = Vector2(290, 79)
	var plate_style := _panel_style(Color("#211d1e"), Color("#a57b50"), 4, 11)
	plate_style.shadow_color = Color(0.03, 0.02, 0.02, 0.65)
	plate_style.shadow_size = 5
	plate.add_theme_stylebox_override("panel", plate_style)
	root.add_child(plate)
	var header := Panel.new()
	header.position = Vector2(11, 9)
	header.size = Vector2(278, 34)
	header.add_theme_stylebox_override("panel", _panel_style(Color("#322b29"), Color("#5c4a3c"), 1, 7))
	root.add_child(header)
	var name_label := _label(_display_name, 20, Color("#f5e6d0"))
	name_label.name = "ActorName"
	name_label.position = Vector2(29, 13)
	name_label.size = Vector2(170, 29)
	root.add_child(name_label)
	_health_number = _label("", 22, Color("#fff2dc"))
	_health_number.name = "HealthNumber"
	_health_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_health_number.position = Vector2(196, 12)
	_health_number.size = Vector2(74, 30)
	root.add_child(_health_number)
	var track := Panel.new()
	track.position = Vector2(13, 45)
	track.size = Vector2(274, 34)
	track.add_theme_stylebox_override("panel", _panel_style(Color("#0c1113"), Color("#665346"), 2, 4))
	root.add_child(track)
	for index in range(SEGMENT_COUNT):
		var cell := Panel.new()
		cell.position = Vector2(18 + index * 26.5, 51)
		cell.size = Vector2(23, 22)
		cell.add_theme_stylebox_override("panel", _panel_style(Color("#242d2e"), Color("#14191b"), 1, 2))
		root.add_child(cell)
		var fill := ColorRect.new()
		fill.position = Vector2.ZERO
		fill.size = Vector2(23, 22)
		fill.color = _accent
		cell.add_child(fill)
		_segments.append(fill)
	_badge = Panel.new()
	_badge.position = Vector2(112, 78)
	_badge.size = Vector2(76, 25)
	_badge.add_theme_stylebox_override("panel", _panel_style(Color("#241f1f"), Color("#a57b50"), 2, 5))
	root.add_child(_badge)
	_badge_mark = _label("◆", 19, _accent)
	_badge_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_mark.position = Vector2(134, 77)
	_badge_mark.size = Vector2(32, 26)
	root.add_child(_badge_mark)
	_ammo_recess = Panel.new()
	_ammo_recess.name = "ShotgunAmmoRecess"
	_ammo_recess.position = Vector2(124, 13)
	_ammo_recess.size = Vector2(63, 26)
	_ammo_recess.add_theme_stylebox_override("panel", _panel_style(Color("#211f1e"), Color("#5d4a3a"), 1, 4))
	_ammo_recess.visible = false
	root.add_child(_ammo_recess)
	for index in range(3):
		var shell := Panel.new()
		shell.name = "ShotgunShell%d" % (index + 1)
		shell.position = Vector2(130 + index * 19, 16)
		shell.size = Vector2(12, 19)
		shell.add_theme_stylebox_override("panel", _panel_style(Color("#37393a"), Color("#685f58"), 1, 2))
		shell.visible = false
		root.add_child(shell)
		_ammo_shells.append(shell)
		var cap := ColorRect.new()
		cap.color = Color("#746456")
		cap.position = Vector2(1, 14)
		cap.size = Vector2(10, 4)
		shell.add_child(cap)
		_ammo_caps.append(cap)
		var highlight := ColorRect.new()
		highlight.color = Color("#555352")
		highlight.position = Vector2(2, 2)
		highlight.size = Vector2(2, 10)
		shell.add_child(highlight)
		_ammo_highlights.append(highlight)
	_ammo_progress_track = Panel.new()
	_ammo_progress_track.name = "ShotgunReloadGroove"
	_ammo_progress_track.position = Vector2(17, 74)
	_ammo_progress_track.size = Vector2(266, 8)
	_ammo_progress_track.add_theme_stylebox_override("panel", _panel_style(Color("#151a1b"), Color("#6b503e"), 1, 2))
	_ammo_progress_track.visible = false
	root.add_child(_ammo_progress_track)
	_ammo_progress_fill = ColorRect.new()
	_ammo_progress_fill.color = Color("#d2945e")
	_ammo_progress_fill.position = Vector2(2, 2)
	_ammo_progress_fill.size = Vector2(0, 4)
	_ammo_progress_fill.visible = false
	_ammo_progress_track.add_child(_ammo_progress_fill)
	_ammo_progress_tip = ColorRect.new()
	_ammo_progress_tip.color = Color("#ffdaa1")
	_ammo_progress_tip.position = Vector2(2, 2)
	_ammo_progress_tip.size = Vector2(3, 4)
	_ammo_progress_tip.visible = false
	_ammo_progress_track.add_child(_ammo_progress_tip)
	_blaster_coil_recess = Panel.new()
	_blaster_coil_recess.name = "BlasterCoilRecess"
	_blaster_coil_recess.position = Vector2(124, 13)
	_blaster_coil_recess.size = Vector2(63, 26)
	_blaster_coil_recess.add_theme_stylebox_override("panel", _panel_style(Color("#1b292c"), Color("#466d70"), 1, 4))
	_blaster_coil_recess.visible = false
	root.add_child(_blaster_coil_recess)
	_blaster_coil = Line2D.new()
	_blaster_coil.name = "BlasterCoil"
	_blaster_coil.points = PackedVector2Array([Vector2(141, 18), Vector2(157, 18), Vector2(160, 20), Vector2(157, 22), Vector2(141, 22), Vector2(138, 24), Vector2(141, 26), Vector2(157, 26), Vector2(160, 28), Vector2(157, 30), Vector2(141, 30)])
	_blaster_coil.width = 2.0
	_blaster_coil.default_color = Color("#57bcca")
	_blaster_coil.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_blaster_coil.end_cap_mode = Line2D.LINE_CAP_ROUND
	_blaster_coil.visible = false
	root.add_child(_blaster_coil)
	_blaster_progress_track = Panel.new()
	_blaster_progress_track.name = "BlasterChargeGroove"
	_blaster_progress_track.position = Vector2(17, 74)
	_blaster_progress_track.size = Vector2(266, 8)
	_blaster_progress_track.add_theme_stylebox_override("panel", _panel_style(Color("#121d20"), Color("#3c7076"), 1, 2))
	_blaster_progress_track.visible = false
	root.add_child(_blaster_progress_track)
	_blaster_progress_fill = ColorRect.new()
	_blaster_progress_fill.color = Color("#46d5e7")
	_blaster_progress_fill.position = Vector2(2, 2)
	_blaster_progress_fill.size = Vector2(0, 4)
	_blaster_progress_fill.visible = false
	_blaster_progress_track.add_child(_blaster_progress_fill)
	_blaster_progress_tip = ColorRect.new()
	_blaster_progress_tip.color = Color("#d7ffff")
	_blaster_progress_tip.position = Vector2(2, 2)
	_blaster_progress_tip.size = Vector2(3, 4)
	_blaster_progress_tip.visible = false
	_blaster_progress_track.add_child(_blaster_progress_tip)
	for bolt_position in [Vector2(12, 12), Vector2(276, 12)]:
		var bolt := Panel.new()
		bolt.position = bolt_position
		bolt.size = Vector2(10, 10)
		bolt.add_theme_stylebox_override("panel", _panel_style(Color("#d1a670"), Color("#59402d"), 2, 5))
		root.add_child(bolt)
	_sprite = Sprite3D.new()
	_sprite.name = "HealthBarSprite"
	_sprite.texture = _viewport.get_texture()
	_sprite.position = Vector3(0.0, 2.95, 0.0)
	_sprite.pixel_size = 0.013
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	add_child(_sprite)


func _label(value: String, font_size: int, color: Color) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.add_theme_color_override("font_outline_color", Color("#11100f"))
	item.add_theme_constant_override("outline_size", 2)
	return item


func _panel_style(color: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
