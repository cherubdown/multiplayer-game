extends RefCounted
## The old-school look of the inventory, chest, crafting window and character
## sheet: panels of dark grey stone inside a carved, bevelled metal frame with
## a boss in each corner, and slots sunk into the stone with a bevelled rim.
##
## Every texture is drawn here in code, pixel by pixel, so nothing needs
## importing on a fresh checkout. They're made once and cached.

## The metal of the frames, and the pale gold of titles on them.
const METAL := Color(0.63, 0.58, 0.45)
const TITLE_COLOR := Color(0.9, 0.82, 0.58)
## Width of the metal band round a panel, and of each corner piece.
const BAND := 16
const CORNER := 40
## The tiling stone in the middle of a panel, in pixels. The panel texture is
## CORNER + TILE + CORNER across, so its edges and middle tile seamlessly.
const TILE := 128

static var _panel_style: StyleBoxTexture
static var _slot_textures := {}


## The stylebox of a panel: stone inside a carved metal frame.
static func panel_style() -> StyleBoxTexture:
	if _panel_style != null:
		return _panel_style
	var size := CORNER * 2 + TILE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var stone := _stone(TILE)
	for y in size:
		for x in size:
			# Stone everywhere first, wrapped so every tiled part lines up.
			var color := stone.get_pixel(posmod(x - CORNER, TILE), posmod(y - CORNER, TILE))
			var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			if edge < BAND:
				color = _band(edge, x if (y < BAND or y >= size - BAND) else y)
			elif edge <= BAND + 2:
				# The frame's shadow on the stone.
				color = color.darkened(0.65 - 0.25 * (edge - BAND))
			if (x < CORNER or x >= size - CORNER) and (y < CORNER or y >= size - CORNER):
				var corner := _corner(x if x < CORNER else size - 1 - x, y if y < CORNER else size - 1 - y)
				if corner.a > 0.0:
					color = corner
			image.set_pixel(x, y, color)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.set_texture_margin_all(CORNER)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.set_content_margin_all(BAND + 12)
	_panel_style = style
	return style


## The stylebox of a slot sunk into the stone. `rim` lights its bevel: "" for
## an ordinary slot, "hover" under the mouse, "held" for the tool in hand.
## `tint` colours the inside a little, for what's in it.
static func slot_style(rim := "", tint := Color.TRANSPARENT) -> StyleBoxTexture:
	if not _slot_textures.has(rim):
		_slot_textures[rim] = ImageTexture.create_from_image(_slot_image(rim))
	var style := StyleBoxTexture.new()
	style.texture = _slot_textures[rim]
	style.set_texture_margin_all(5)
	style.set_content_margin_all(8)
	if tint.a > 0.0:
		style.modulate_color = Color.WHITE.lerp(tint.lightened(0.3), 0.45)
	return style


## Styles a title label to stand out on the stone.
static func title(label: Label, font_size := 20) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))


## Mottled dark grey stone, seamless when tiled.
static func _stone(size: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 5
	noise.frequency = 0.035
	var cracks := FastNoiseLite.new()
	cracks.seed = 11
	cracks.noise_type = FastNoiseLite.TYPE_CELLULAR
	cracks.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cracks.frequency = 0.05
	var mottle := noise.get_seamless_image(size, size)
	var veins := cracks.get_seamless_image(size, size)
	var grain := RandomNumberGenerator.new()
	grain.seed = 3
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := 0.12 + mottle.get_pixel(x, y).r * 0.2 + grain.randf_range(-0.02, 0.02)
			# Thin dark veins where the cells meet.
			v -= (1.0 - smoothstep(0.0, 0.08, veins.get_pixel(x, y).r)) * 0.06
			image.set_pixel(x, y, Color(v, v, v * 1.04))
	return image


## One pixel of the metal band, `edge` pixels in from the outside and `along`
## pixels along it: a raised rim each side of a sunken channel, with a braid
## of two strands winding over and under each other down the channel.
static func _band(edge: int, along: int) -> Color:
	if edge == 0 or edge == BAND - 1:
		return _metal(0.25)
	if edge <= 3:
		return _metal(1.15 - 0.12 * edge)  # The outer rim, lit from outside.
	if edge == 4 or edge == BAND - 5:
		return _metal(0.35)
	if edge >= BAND - 4:
		return _metal(0.75 + 0.1 * (BAND - 1 - edge))  # The inner rim.
	var middle := (BAND - 1) * 0.5
	var swing := (BAND - 9) * 0.5 - 0.5
	var phase := along * TAU / 16.0
	var first_on_top := cos(phase) > 0.0
	var light := 0.42  # The bottom of the channel.
	var lit := false
	for strand in [[middle + swing * sin(phase), first_on_top], [middle - swing * sin(phase), not first_on_top]]:
		var gap := absf(edge - strand[0])
		if gap < 1.3 and (not lit or strand[1]):
			light = 1.1 - 0.35 * gap
			lit = true
	return _metal(light)


## One pixel of a corner piece, from its outer corner, or transparent where
## the band shows through: a domed boss with a beaded rim and a raised
## four-petalled flower.
static func _corner(x: int, y: int) -> Color:
	var radius := CORNER * 0.42
	var center := Vector2(CORNER * 0.45, CORNER * 0.45)
	var at := Vector2(x + 0.5, y + 0.5)
	var distance := at.distance_to(center)
	if distance > radius:
		return Color.TRANSPARENT
	if distance > radius - 1.5:
		return _metal(0.25)
	# Light comes from the top left.
	var normal := (at - center) / radius
	var out := distance / radius
	var dome := 0.62 - 0.3 * (normal.x + normal.y)
	if absf(out - 0.86) < 0.07:
		return _metal(dome * 1.4)
	var petal := 0.3 + 0.5 * pow(absf(cos(2.0 * normal.angle())), 3.0)
	if out < 0.18:
		return _metal(1.35 - 0.8 * (normal.x + normal.y))
	if out < petal:
		return _metal(1.15 - 0.45 * (normal.x + normal.y) - 0.3 * out / petal)
	return _metal(dome * 0.7)


## The frame's metal, lit by `light` (1 for its own colour), fully opaque.
static func _metal(light: float) -> Color:
	return Color(clampf(METAL.r * light, 0.0, 1.0), clampf(METAL.g * light, 0.0, 1.0), clampf(METAL.b * light, 0.0, 1.0))


static func _slot_image(rim: String) -> Image:
	var size := 24
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var inside := Color(0.045, 0.045, 0.06)
	var lit := Color(0.42, 0.4, 0.36)
	var shadow := Color(0.01, 0.01, 0.015)
	match rim:
		"hover":
			lit = Color(0.7, 0.68, 0.6)
			inside = Color(0.07, 0.07, 0.09)
		"held":
			lit = Color(1.0, 0.82, 0.32)
			shadow = Color(0.55, 0.4, 0.1)
	for y in size:
		for x in size:
			var color := inside
			var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			if edge < 2:
				# Sunk in: the top and left edges are in shadow, the bottom
				# and right catch the light.
				var top_left := (y < 2 and x < size - 1 - y) or (x < 2 and y < size - 1 - x)
				color = shadow if top_left else lit
				if rim == "held":
					color = lit if edge == 0 else shadow
			elif edge == 2:
				color = inside.darkened(0.5)
			image.set_pixel(x, y, color)
	return image
