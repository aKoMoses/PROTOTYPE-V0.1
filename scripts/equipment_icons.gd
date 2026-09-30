extends RefCounted

## Ben's choices from choix.html, verified on 2026-09-28.
## Keep the downloaded originals intact; atlas regions remove empty margins in UI.
const SOURCES := {
	"agile": preload("res://art/robot-concepts/robot-agile-face-v3.png"),
	"polyvalent": preload("res://art/robot-concepts/robot-polyvalent-face-v3.png"),
	"puissant": preload("res://art/robot-concepts/robot-puissant-face-v3.png"),
	"blaster": preload("res://art/icons/blaster-gravure.png"),
	"shotgun": preload("res://art/icons/ben/shotgun-a.png"),
	"longshot": preload("res://art/icons/longshot.svg"),
	"mekatana": preload("res://art/ui/icons/mekatana.svg"),
	"modulo_drone": preload("res://art/icons/ben/modulo-drone-b.png"),
	"javelin": preload("res://art/icons/ben/javelin-b.png"),
	"fulguro_punch": preload("res://art/icons/fulguro-punch.svg"),
	"pelto_smash": preload("res://art/icons/pelto-smash.svg"),
	"magnetic_field": preload("res://art/icons/ben/magnetic-field-a.png"),
	"static_shield": preload("res://art/icons/ben/static-shield-a.png"),
	"pyro_boots": preload("res://art/icons/ben/pyro-boots-a.png"),
	"bio_injector": preload("res://art/icons/ben/bio-injector-a.png"),
	"baroud": preload("res://art/icons/ben/baroud-a.png"),
	"omnivamp": preload("res://art/icons/ben/omnivamp-a.png"),
}
const REGIONS := {
	"agile": Rect2(388, 34, 478, 1174),
	"polyvalent": Rect2(334, 10, 574, 1186),
	"puissant": Rect2(292, 4, 670, 1216),
	"blaster": Rect2(100, 270, 1100, 770),
	"shotgun": Rect2(20, 335, 1220, 610),
	"modulo_drone": Rect2(15, 237, 1225, 770),
	"javelin": Rect2(23, 20, 1210, 1220),
	"magnetic_field": Rect2(85, 172, 1085, 945),
	"static_shield": Rect2(71, 214, 1115, 835),
	"pyro_boots": Rect2(96, 147, 1115, 1010),
	"bio_injector": Rect2(183, 54, 940, 1157),
	"baroud": Rect2(148, 147, 958, 961),
	"omnivamp": Rect2(78, 64, 1093, 1113),
}
var _textures: Dictionary = {}

func get_icon(identifier: String) -> Texture2D:
	if not SOURCES.has(identifier):
		return null
	if identifier in ["fulguro_punch", "pelto_smash", "mekatana", "longshot"]:
		return SOURCES[identifier]
	if not _textures.has(identifier):
		var texture := AtlasTexture.new()
		texture.atlas = SOURCES[identifier]
		texture.region = REGIONS.get(identifier, Rect2(Vector2.ZERO, texture.atlas.get_size()))
		texture.filter_clip = true
		_textures[identifier] = texture
	return _textures[identifier]
