extends SceneTree
## Export sizes and Android safe margins; the generated artwork stays untouched.
func _initialize() -> void:
	var source := Image.load_from_file("res://art/branding/prototype0-icon-source.png")
	if source == null:
		quit(1)
		return
	for spec in [["prototype0-icon.png", 512, 440], ["android-icon.png", 192, 166], ["android-foreground.png", 432, 280], ["boot-emblem.png", 256, 220]]:
		var side: int = spec[1]
		var artwork_side: int = spec[2]
		var canvas := Image.create(side, side, false, Image.FORMAT_RGBA8)
		canvas.fill(Color("10151e"))
		var artwork := source.duplicate() as Image
		artwork.convert(Image.FORMAT_RGBA8)
		artwork.resize(artwork_side, artwork_side, Image.INTERPOLATE_LANCZOS)
		var margin := (side - artwork_side) / 2
		canvas.blit_rect(artwork, Rect2i(0, 0, artwork_side, artwork_side), Vector2i(margin, margin))
		if canvas.save_png("res://art/branding/" + spec[0]) != OK:
			quit(1)
			return
	var background := Image.create(432, 432, false, Image.FORMAT_RGB8)
	background.fill(Color("10151e"))
	var result := background.save_png("res://art/branding/android-background.png")
	print("STARTUP ASSETS: ", "OK" if result == OK else "FAILED")
	quit(0 if result == OK else 1)
