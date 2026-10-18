extends RefCounted

## Shared by the forge, desktop HUD and mobile activation buttons.
## Equipment shares the approved illustrated-metal art and exact grayscale states.
const SOURCES := {
	"rocket_basket": preload("res://art/icons/illustrated-metal/rocket_basket.png"),
	"agile": preload("res://art/robot-concepts/robot-agile-face-v3.png"),
	"polyvalent": preload("res://art/robot-concepts/robot-polyvalent-face-v3.png"),
	"puissant": preload("res://art/robot-concepts/robot-puissant-orange.png"),
	"blaster": preload("res://art/icons/illustrated-metal/blaster.png"),
	"shotgun": preload("res://art/icons/illustrated-metal/shotgun.png"),
	"longshot": preload("res://art/icons/illustrated-metal/longshot.png"),
	"mekatana": preload("res://art/icons/illustrated-metal/mekatana.png"),
	"javelin": preload("res://art/icons/illustrated-metal/javelin.png"),
	"fulguro_punch": preload("res://art/icons/illustrated-metal/fulguro_punch.png"),
	"pelto_smash": preload("res://art/icons/illustrated-metal/pelto_smash.png"),
	"magnetic_field": preload("res://art/icons/illustrated-metal/magnetic_field.png"),
	"counter": preload("res://art/icons/illustrated-metal/counter.png"),
	"static_shield": preload("res://art/icons/illustrated-metal/static_shield.png"),
	"projector": preload("res://art/icons/illustrated-metal/projector.png"),
	"pyro_boots": preload("res://art/icons/illustrated-metal/pyro_boots.png"),
	"bio_injector": preload("res://art/icons/illustrated-metal/bio_injector.png"),
	"permutation": preload("res://art/icons/illustrated-metal/permutation.png"),
	"eclipse": preload("res://art/icons/illustrated-metal/eclipse.png"),
	"baroud": preload("res://art/icons/illustrated-metal/baroud.png"),
	"omnivamp": preload("res://art/icons/illustrated-metal/omnivamp.png"),
	"auxiliary_reactor": preload("res://art/icons/illustrated-metal/auxiliary_reactor.png"),
	"tracker": preload("res://art/icons/illustrated-metal/tracker.png"),
	"alternator": preload("res://art/icons/illustrated-metal/alternator.png"),
	"inertia": preload("res://art/icons/illustrated-metal/inertia.png"),
}
const REGIONS := {
	"agile": Rect2(388, 34, 478, 1174),
	"polyvalent": Rect2(334, 10, 574, 1186),
	"puissant": Rect2(130, 270, 385, 710),
}
var _textures: Dictionary = {}
var _cooldown_textures: Dictionary = {}

func get_cooldown_icon(identifier: String) -> Texture2D:
	if _uses_illustrated_metal(identifier):
		if not _cooldown_textures.has(identifier):
			# Derive the unavailable state from the same pixels: no silhouette jump.
			var image: Image = get_icon(identifier).atlas.get_image()
			image.convert(Image.FORMAT_RGBA8)
			for y in image.get_height():
				for x in image.get_width():
					var pixel := image.get_pixel(x, y)
					var value := pixel.get_luminance()
					image.set_pixel(x, y, Color(value, value, value, pixel.a))
			image.generate_mipmaps()
			var raster := ImageTexture.create_from_image(image)
			var texture := AtlasTexture.new()
			texture.atlas = raster
			texture.region = Rect2(Vector2.ZERO, raster.get_size())
			texture.margin = get_icon(identifier).margin
			texture.filter_clip = true
			_cooldown_textures[identifier] = texture
		return _cooldown_textures[identifier]
	return get_icon(identifier)

func get_icon(identifier: String) -> Texture2D:
	if not SOURCES.has(identifier):
		return null
	if not REGIONS.has(identifier) and not _uses_illustrated_metal(identifier):
		return SOURCES[identifier]
	if not _textures.has(identifier):
		var texture := AtlasTexture.new()
		texture.atlas = SOURCES[identifier]
		texture.set_meta("source_path", SOURCES[identifier].resource_path)
		if _uses_illustrated_metal(identifier):
			# Remove almost invisible matte specks; keep the illustrated silhouette.
			var image: Image = texture.atlas.get_image()
			image.convert(Image.FORMAT_RGBA8)
			var pixels := image.get_data()
			for offset in range(3, pixels.size(), 4):
				if pixels[offset] < 8:
					pixels[offset] = 0
			image = Image.create_from_data(image.get_width(), image.get_height(), image.has_mipmaps(), Image.FORMAT_RGBA8, pixels)
			image.generate_mipmaps()
			texture.atlas = ImageTexture.create_from_image(image)
		texture.region = REGIONS.get(identifier, Rect2(Vector2.ZERO, texture.atlas.get_size()))
		if _uses_illustrated_metal(identifier):
			# Keep artwork comfortably inside the 54 px HUD ring.
			var padding := (texture.atlas.get_size() * 0.10).round()
			texture.margin = Rect2(padding, padding * 2.0)
		texture.filter_clip = true
		_textures[identifier] = texture
	return _textures[identifier]


func _uses_illustrated_metal(identifier: String) -> bool:
	return SOURCES.has(identifier) and SOURCES[identifier].resource_path.begins_with("res://art/icons/illustrated-metal/")
