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
var _latest_popup: Node3D
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


func clear_damage_numbers() -> void:
	_latest_popup = null
	for child in get_children():
		if child.name.begins_with("DamageNumber"):
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
	var badge := Panel.new()
	badge.position = Vector2(116, 78)
	badge.size = Vector2(68, 25)
	badge.add_theme_stylebox_override("panel", _panel_style(Color("#241f1f"), Color("#a57b50"), 2, 5))
	root.add_child(badge)
	var badge_mark := _label("◆", 19, _accent)
	badge_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_mark.position = Vector2(134, 77)
	badge_mark.size = Vector2(32, 26)
	root.add_child(badge_mark)
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
