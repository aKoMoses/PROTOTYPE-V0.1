extends RefCounted

## Ben's choices from choix.html, verified on 2026-09-28.
## Keep the downloaded originals intact; atlas regions remove empty margins in UI.
const SOURCES := {
	"blaster": preload("res://art/icons/blaster-gravure.png"),
	"shotgun": preload("res://art/icons/ben/shotgun-a.png"),
	"modulo_drone": preload("res://art/icons/ben/modulo-drone-b.png"),
	"javelin": preload("res://art/icons/ben/javelin-b.png"),
	"magnetic_field": preload("res://art/icons/ben/magnetic-field-a.png"),
	"static_shield": preload("res://art/icons/ben/static-shield-a.png"),
	"pyro_boots": preload("res://art/icons/ben/pyro-boots-a.png"),
	"bio_injector": preload("res://art/icons/ben/bio-injector-a.png"),
	"baroud": preload("res://art/icons/ben/baroud-a.png"),
	"omnivamp": preload("res://art/icons/ben/omnivamp-a.png"),
}
const REGIONS := {
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
	if not _textures.has(identifier):
		var texture := AtlasTexture.new()
		texture.atlas = SOURCES[identifier]
		texture.region = REGIONS[identifier]
		texture.filter_clip = true
		_textures[identifier] = texture
	return _textures[identifier]
