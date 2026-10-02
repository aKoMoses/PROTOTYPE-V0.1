extends "res://scripts/ui/industrial_screen.gd"

const LOADOUT := preload("res://scripts/loadout_state.gd")
const ICONS := preload("res://scripts/equipment_icons.gd")
const PORTRAIT := preload("res://scripts/ui/combat_portrait.gd")
const CATEGORIES := ["robot", "weapon", "offensive", "defensive", "mobility", "passive"]
const TITLES := ["CHÂSSIS", "ARME", "OFFENSIF", "DÉFENSIF", "MOBILITÉ", "PASSIF"]
var local_loadout: Dictionary = {}
var opponent_loadout: Dictionary = {}
var _equipment_icons = ICONS.new()
var _rows: Array = []
var _portraits: Array = []
var _number: Label
var _fill: ColorRect
var _duration := 8.0

func _ready() -> void:
	super._ready()
	title_label.text = "PRÉ-COMBAT"
	subtitle_label.text = "DUEL 1 CONTRE 1"
	subtitle_label.position.x = 535
	for side in range(2):
		var panel := plate(canvas, Rect2(165 if side == 0 else 670, 186, 443, 365))
		text(panel, "VOUS" if side == 0 else "ADVERSAIRE", Rect2(20, 6, 403, 36), 21, CYAN if side == 0 else ORANGE, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var portrait := PORTRAIT.new()
		portrait.name = "LocalPortrait" if side == 0 else "OpponentPortrait"
		portrait.face_left = side == 1
		portrait.position = Vector2(0 if side == 0 else 241, 45)
		portrait.size = Vector2(200, 310)
		panel.add_child(portrait)
		_portraits.append(portrait)
		var rows: Array = []
		for i in range(CATEGORIES.size()):
			var row := plate(panel, Rect2(204 if side == 0 else 12, 45+i*51, 225, 47))
			var equipment_icon := icon(row, null, Rect2(5, 3, 42, 41))
			text(row, TITLES[i], Rect2(55, 2, 164, 17), 11, MUTED)
			var value := text(row, "", Rect2(55, 19, 164, 25), 14, CREAM, true)
			rows.append({"icon": equipment_icon, "value": value, "row": row})
		_rows.append(rows)
	text(canvas, "VS", Rect2(610, 321, 55, 70), 38, MUTED, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer()
	text(canvas, "DÉBUT DU COMBAT DANS", Rect2(430, 567, 420, 27), 15, CREAM, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number = text(canvas, "08", Rect2(565, 594, 150, 44), 39, ORANGE, true)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line(canvas, Rect2(554, 641, 172, 4), Color("#3c464b"))
	_fill = line(canvas, Rect2(554, 641, 172, 4), CYAN)
	hide()

func reveal(local: Dictionary, opponent: Dictionary, duration := 8.0) -> void:
	local_loadout = LOADOUT.sanitize(local)
	opponent_loadout = LOADOUT.sanitize(opponent)
	_duration = maxf(0.1, duration)
	var builds := [local_loadout, opponent_loadout]
	for side in range(2):
		_portraits[side].call("set_chassis", str(builds[side].robot))
		for i in range(CATEGORIES.size()):
			var identifier := str(builds[side][CATEGORIES[i]])
			_rows[side][i].icon.texture = _equipment_icons.get_icon(identifier)
			_rows[side][i].value.text = LOADOUT.display_name(identifier)
			_rows[side][i].row.tooltip_text = LOADOUT.display_name(identifier)+"\n"+LOADOUT.category_description(identifier)
			_rows[side][i].row.mouse_filter = Control.MOUSE_FILTER_PASS
	show()
	set_remaining(duration)

func set_remaining(seconds: float) -> void:
	_number.text = "%02d" % maxi(0, ceili(seconds))
	_fill.size.x = 172.0 * clampf(seconds/_duration, 0.0, 1.0)
