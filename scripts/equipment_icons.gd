extends RefCounted

## Shared by the forge, desktop HUD and mobile activation buttons.
## Module vectors follow Pelto's illustrated metal style; PNG originals stay intact.
const SOURCES := {
	"rocket_basket": preload("res://art/icons/rocket-basket.svg"),
	"agile": preload("res://art/robot-concepts/robot-agile-face-v3.png"),
	"polyvalent": preload("res://art/robot-concepts/robot-polyvalent-face-v3.png"),
	"puissant": preload("res://art/robot-concepts/robot-puissant-face-v3.png"),
	"blaster": preload("res://art/icons/blaster-gravure.png"),
	"shotgun": preload("res://art/icons/ben/shotgun-a.png"),
	"longshot": preload("res://art/icons/longshot.svg"),
	"mekatana": preload("res://art/ui/icons/mekatana.svg"),
	"javelin": preload("res://art/icons/javelin.svg"),
	"fulguro_punch": preload("res://art/icons/fulguro-punch.svg"),
	"pelto_smash": preload("res://art/icons/pelto-smash.svg"),
	"magnetic_field": preload("res://art/icons/magnetic-field.svg"),
	"counter": preload("res://art/icons/counter.svg"),
	"static_shield": preload("res://art/icons/static-shield.svg"),
	"projector": preload("res://art/icons/projector.svg"),
	"pyro_boots": preload("res://art/icons/pyro-boots.svg"),
	"bio_injector": preload("res://art/icons/bio-injector.svg"),
	"permutation": preload("res://art/icons/permutation.svg"),
	"eclipse": preload("res://art/icons/eclipse.svg"),
	"baroud": preload("res://art/icons/baroud.svg"),
	"omnivamp": preload("res://art/icons/omnivamp.svg"),
	"auxiliary_reactor": preload("res://art/icons/auxiliary-reactor.svg"),
	"tracker": preload("res://art/icons/tracker.svg"),
	"alternator": preload("res://art/icons/alternator.svg"),
	"inertia": preload("res://art/icons/inertia.svg"),
}
const REGIONS := {
	"agile": Rect2(388, 34, 478, 1174),
	"polyvalent": Rect2(334, 10, 574, 1186),
	"puissant": Rect2(292, 4, 670, 1216),
	"blaster": Rect2(100, 270, 1100, 770),
	"shotgun": Rect2(20, 335, 1220, 610),
}
var _textures: Dictionary = {}
const COOLDOWN_SOURCES := {
	"rocket_basket": preload("res://art/icons/cooldown/rocket-basket.svg"),
	"javelin": preload("res://art/icons/cooldown/javelin.svg"),
	"fulguro_punch": preload("res://art/icons/cooldown/fulguro-punch.svg"),
	"pelto_smash": preload("res://art/icons/cooldown/pelto-smash.svg"),
	"magnetic_field": preload("res://art/icons/cooldown/magnetic-field.svg"),
	"static_shield": preload("res://art/icons/cooldown/static-shield.svg"),
	"projector": preload("res://art/icons/cooldown/projector.svg"),
	"counter": preload("res://art/icons/cooldown/counter.svg"),
	"pyro_boots": preload("res://art/icons/cooldown/pyro-boots.svg"),
	"bio_injector": preload("res://art/icons/cooldown/bio-injector.svg"),
	"permutation": preload("res://art/icons/cooldown/permutation.svg"),
	"eclipse": preload("res://art/icons/cooldown/eclipse.svg"),
}

func get_cooldown_icon(identifier: String) -> Texture2D:
	return COOLDOWN_SOURCES.get(identifier, get_icon(identifier))

func get_icon(identifier: String) -> Texture2D:
	if not SOURCES.has(identifier):
		return null
	if not REGIONS.has(identifier):
		return SOURCES[identifier]
	if not _textures.has(identifier):
		var texture := AtlasTexture.new()
		texture.atlas = SOURCES[identifier]
		texture.region = REGIONS.get(identifier, Rect2(Vector2.ZERO, texture.atlas.get_size()))
		texture.filter_clip = true
		_textures[identifier] = texture
	return _textures[identifier]
