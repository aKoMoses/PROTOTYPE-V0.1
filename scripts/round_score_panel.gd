extends Control

## Illustrated shell only. GameFlow and NetworkMatch keep owning the live text.
const FRAME: Texture2D = preload("res://art/ui/round-score-forge.png")
const DISPLAY_FONT: Font = preload("res://art/ui/fonts/RussoOne-Regular.ttf")
const PANEL_SIZE := Vector2(400, 128)
# Discard the generator's transparent canvas padding without resampling the art.
const FRAME_REGION := Rect2(10, 78, 2062, 568)

var score_label: Label
var round_label: Label
var phase_label: Label

func _ready() -> void:
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var atlas := AtlasTexture.new()
	atlas.atlas = FRAME
	atlas.region = FRAME_REGION
	var frame := TextureRect.new()
	frame.name = "ForgeFrame"
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture = atlas
	frame.size = Vector2(400, 110)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	round_label = _label("Round", "MANCHE 1", 13, Color("#ead9bb"), Rect2(100, 26, 200, 19))
	score_label = _label("Score", "0 — 0", 29, Color("#f4e4c9"), Rect2(94, 44, 212, 34))
	phase_label = _label("Phase", "PRÉPARATION", 10, Color("#78dbe0"), Rect2(70, 110, 260, 18))

func _label(id: String, text: String, font_size: int, tint: Color, rect: Rect2) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.add_theme_font_override("font", DISPLAY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color("#080c0eed"))
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label
